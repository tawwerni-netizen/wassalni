-- Wassalni / وصلني — initial schema
-- Target: Supabase (Postgres 15), region eu-central-1
-- Privacy tiers referenced below (P0..P3) are defined in ARCHITECTURE.md §4.
--
-- Invariants this file is responsible for:
--   * RLS is ENABLED on every table. Default deny.
--   * No column anywhere stores a phone number, address, or government ID.
--   * private_verification_details is never readable by a claimant.
--   * At most one approved claim per report (enforced by index, not code).

begin;

create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Enums
-- ---------------------------------------------------------------------------

create type report_type as enum ('lost', 'found');

create type report_status as enum (
  'open', 'possible_match', 'claim_in_progress', 'matched',
  'returned', 'closed', 'removed'
);

create type claim_status as enum (
  'pending', 'verifying', 'approved', 'rejected', 'withdrawn', 'expired'
);

create type user_role as enum ('user', 'moderator', 'admin');

create type moderation_reason as enum (
  'scam', 'fake_report', 'dangerous', 'inappropriate', 'privacy'
);

-- ---------------------------------------------------------------------------
-- 2. Arabic normalisation (immutable — safe in generated columns and indexes)
-- ---------------------------------------------------------------------------

create or replace function wassalni_normalize_ar(input text)
returns text
language sql
immutable
parallel safe
as $$
  select nullif(
    btrim(
      regexp_replace(
        regexp_replace(
          translate(
            -- strip tashkeel (U+064B..U+0652) and tatweel (U+0640)
            regexp_replace(lower(coalesce(input, '')), '[ً-ْـ]', '', 'g'),
            -- alef/hamza/teh-marbuta/alef-maqsura variants + Arabic-Indic digits
            'أإآٱةىؤئ٠١٢٣٤٥٦٧٨٩',
            'ااااهيوي0123456789'
          ),
          -- Postgres uses POSIX ARE: there is no \p{L}. [:alnum:] is
          -- locale-aware under a UTF-8 collation and matches Arabic letters.
          '[^[:alnum:] ]', ' ', 'g'    -- drop punctuation, keep letters/digits/space
        ),
        '\s+', ' ', 'g'                 -- collapse whitespace
      )
    ),
    ''
  );
$$;

comment on function wassalni_normalize_ar is
  'Folds Arabic orthographic variants so search and trigram matching work. Must stay IMMUTABLE.';

-- Rejects free text that looks like a government ID, card number, IBAN or phone.
-- Privacy hard rule #1 (ARCHITECTURE.md §4).
create or replace function wassalni_contains_sensitive_number(input text)
returns boolean
language sql
immutable
parallel safe
as $$
  select coalesce(input, '') ~ '[0-9٠-٩][ \-]?(?:[0-9٠-٩][ \-]?){7,}'
      or coalesce(input, '') ~* '\m(EG[0-9]{2}[A-Z0-9]{10,})\M';
$$;

-- ---------------------------------------------------------------------------
-- 3. Reference data
-- ---------------------------------------------------------------------------

create table communities (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name_ar     text not null,
  name_en     text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Curated, NOT free text. This is what makes "same area" a real match signal
-- and what stops users typing a home address. Privacy hard rule #3.
create table areas (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references communities(id) on delete cascade,
  name_ar       text not null,
  name_en       text not null,
  sort_order    int not null default 0,
  unique (community_id, name_ar)
);

-- A table, not a Kotlin enum: categories change without an app release.
create table categories (
  id          text primary key,           -- 'phone', 'wallet', ...
  group_key   text not null,              -- partial-match grouping
  name_ar     text not null,
  name_en     text not null,
  icon_key    text,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

create table colors (
  id       text primary key,              -- 'black', 'brown', ...
  name_ar  text not null,
  name_en  text not null,
  hex      text not null
);

-- Curated adjacency for partial colour credit in the matching score.
create table color_adjacency (
  color_id     text not null references colors(id) on delete cascade,
  adjacent_id  text not null references colors(id) on delete cascade,
  primary key (color_id, adjacent_id),
  check (color_id <> adjacent_id)
);

-- ---------------------------------------------------------------------------
-- 4. Profiles
-- ---------------------------------------------------------------------------
-- Deliberately holds no phone, no address, no national ID. See ARCHITECTURE §4.

create table profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  display_name   text not null check (char_length(display_name) between 2 and 40),
  community_id   uuid references communities(id) on delete set null,
  role           user_role not null default 'user',
  is_suspended   boolean not null default false,
  suspended_at   timestamptz,
  suspended_reason text,
  returns_count  int not null default 0,     -- trust signal, not a score shown as certainty
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- SECURITY DEFINER helpers. Without these, a policy on `profiles` that reads
-- `profiles` recurses infinitely.
create or replace function current_role_is(target user_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.id = auth.uid() and p.role = target);
$$;

create or replace function current_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p
                 where p.id = auth.uid() and p.role in ('moderator','admin'));
$$;

create or replace function current_community_id()
returns uuid language sql stable security definer set search_path = public as $$
  select p.community_id from profiles p where p.id = auth.uid();
$$;

create or replace function current_is_active()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.id = auth.uid() and not p.is_suspended);
$$;

-- ---------------------------------------------------------------------------
-- 5. Reports (P0 public, community-scoped)
-- ---------------------------------------------------------------------------

create table reports (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid references profiles(id) on delete set null,  -- null = deleted account
  report_type    report_type not null,
  status         report_status not null default 'open',
  community_id   uuid not null references communities(id),
  area_id        uuid references areas(id),
  category_id    text not null references categories(id),
  color_id       text references colors(id),
  brand          text check (brand is null or char_length(brand) <= 40),
  title          text not null check (char_length(title) between 3 and 80),
  description    text not null check (char_length(description) between 10 and 1000),

  -- NOTE: the P1 location hint deliberately does NOT live here. RLS is
  -- row-level, not column-level, so any column on this table is visible to
  -- everyone who can read the row. P1 data lives in report_private_details.

  occurred_on    date not null,
  occurred_time_bucket text check (
    occurred_time_bucket is null or
    occurred_time_bucket in ('early_morning','morning','afternoon','evening','night','unknown')
  ),

  is_hidden      boolean not null default false,   -- auto-hide on 3 abuse reports
  hidden_reason  text,

  normalized_text text generated always as (
    wassalni_normalize_ar(coalesce(title,'') || ' ' || coalesce(description,'') || ' ' || coalesce(brand,''))
  ) stored,

  search_vector  tsvector generated always as (
    to_tsvector('simple', wassalni_normalize_ar(
      coalesce(title,'') || ' ' || coalesce(description,'') || ' ' || coalesce(brand,'')))
  ) stored,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
  -- area_id must belong to community_id; enforced by the trigger below because
  -- a CHECK constraint cannot reference another table.
);

create index reports_feed_idx on reports (community_id, status, created_at desc)
  where not is_hidden;
create index reports_match_idx on reports (community_id, report_type, status, occurred_on);
create index reports_search_idx on reports using gin (search_vector);
create index reports_trgm_idx on reports using gin (normalized_text gin_trgm_ops);
create index reports_profile_idx on reports (profile_id, created_at desc);

-- P0 free text must never carry an ID/card/phone number. Privacy hard rule #1,
-- enforced server-side so a modified client cannot bypass the UI check.
create or replace function reports_reject_sensitive_text()
returns trigger language plpgsql as $$
begin
  if wassalni_contains_sensitive_number(new.title)
     or wassalni_contains_sensitive_number(new.description) then
    raise exception 'SENSITIVE_NUMBER_IN_PUBLIC_TEXT'
      using hint = 'لا تكتب أرقام بطاقات أو هويات أو تليفونات في البلاغ.';
  end if;

  if new.area_id is not null and not exists (
       select 1 from areas a where a.id = new.area_id and a.community_id = new.community_id) then
    raise exception 'AREA_NOT_IN_COMMUNITY';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger reports_guard
  before insert or update on reports
  for each row execute function reports_reject_sensitive_text();

-- ---------------------------------------------------------------------------
-- 5b. Report participant details (P1)
-- ---------------------------------------------------------------------------
-- Separate table, not a column on `reports`, because RLS is row-level: any
-- column on a readable row is readable. Visible to the report owner and to the
-- counterparty of an APPROVED claim, and to nobody else.

create table report_private_details (
  report_id      uuid primary key references reports(id) on delete cascade,
  location_hint  text check (location_hint is null or char_length(location_hint) <= 160),
  updated_at     timestamptz not null default now()
);

create or replace function report_private_details_guard()
returns trigger language plpgsql as $$
begin
  if wassalni_contains_sensitive_number(new.location_hint) then
    raise exception 'SENSITIVE_NUMBER_IN_PUBLIC_TEXT'
      using hint = 'لا تكتب أرقام بطاقات أو هويات أو تليفونات في البلاغ.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger report_private_details_guard_trg
  before insert or update on report_private_details
  for each row execute function report_private_details_guard();

-- ---------------------------------------------------------------------------
-- 6. Report status machine
-- ---------------------------------------------------------------------------

create table report_status_transitions (
  from_status  report_status not null,
  to_status    report_status not null,
  staff_only   boolean not null default false,
  primary key (from_status, to_status)
);

insert into report_status_transitions (from_status, to_status, staff_only) values
  ('open','possible_match',false),
  ('open','claim_in_progress',false),
  ('open','closed',false),
  ('possible_match','open',false),
  ('possible_match','claim_in_progress',false),
  ('possible_match','closed',false),
  ('claim_in_progress','matched',false),
  ('claim_in_progress','open',false),            -- all claims rejected/withdrawn
  ('claim_in_progress','possible_match',false),
  ('matched','returned',false),
  ('matched','claim_in_progress',false),         -- approved claim withdrawn
  ('returned','closed',false),
  ('open','removed',true),
  ('possible_match','removed',true),
  ('claim_in_progress','removed',true),
  ('matched','removed',true),
  ('returned','removed',true),
  ('closed','removed',true);

create table audit_log (
  id           bigserial primary key,
  actor_id     uuid,
  entity       text not null,
  entity_id    uuid not null,
  action       text not null,
  before_state jsonb,
  after_state  jsonb,
  created_at   timestamptz not null default now()
);

create index audit_log_entity_idx on audit_log (entity, entity_id, created_at desc);

-- SECURITY DEFINER: this trigger writes to audit_log, which has no INSERT
-- policy for clients by design. Without DEFINER, every legitimate status change
-- would fail on the audit write.
create or replace function reports_enforce_transition()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t report_status_transitions%rowtype;
begin
  if new.status = old.status then
    return new;
  end if;

  select * into t from report_status_transitions
   where from_status = old.status and to_status = new.status;

  if not found then
    raise exception 'INVALID_REPORT_TRANSITION: % -> %', old.status, new.status;
  end if;

  if t.staff_only and not current_is_staff() then
    raise exception 'TRANSITION_REQUIRES_STAFF: % -> %', old.status, new.status;
  end if;

  -- Invariant guards. A report owner holds UPDATE on their own row, so the
  -- transition table alone is not enough: these states must be *earned*, not
  -- asserted by a client.
  if new.status = 'matched' and not exists (
       select 1 from claims c where c.report_id = new.id and c.status = 'approved') then
    raise exception 'MATCHED_REQUIRES_APPROVED_CLAIM';
  end if;

  if new.status = 'returned' and not exists (
       select 1 from claims c
        where c.report_id = new.id and c.status = 'approved'
          and c.finder_confirmed_at is not null
          and c.claimant_confirmed_at is not null) then
    raise exception 'RETURNED_REQUIRES_BOTH_CONFIRMATIONS';
  end if;

  insert into audit_log (actor_id, entity, entity_id, action, before_state, after_state)
  values (auth.uid(), 'report', new.id, 'status_change',
          jsonb_build_object('status', old.status),
          jsonb_build_object('status', new.status));

  return new;
end;
$$;

create trigger reports_transition_guard
  before update of status on reports
  for each row execute function reports_enforce_transition();

-- ---------------------------------------------------------------------------
-- 7. Images
-- ---------------------------------------------------------------------------

create table report_images (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references reports(id) on delete cascade,
  storage_path text not null,
  is_public   boolean not null default true,   -- false => P1
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create index report_images_report_idx on report_images (report_id, sort_order);

-- ---------------------------------------------------------------------------
-- 8. Private verification details (P2 — the most sensitive table in the app)
-- ---------------------------------------------------------------------------
-- Written by the FINDER. Readable ONLY by the report owner and admins.
-- There is deliberately no view, RPC, or realtime publication over this table.

create table private_verification_details (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null references reports(id) on delete cascade,
  question_ar    text not null check (char_length(question_ar) between 5 and 160),
  expected_answer text not null check (char_length(expected_answer) between 1 and 160),
  normalized_expected text generated always as (wassalni_normalize_ar(expected_answer)) stored,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now()
);

create index pvd_report_idx on private_verification_details (report_id, sort_order);

alter table private_verification_details replica identity nothing;  -- keep out of realtime

-- ---------------------------------------------------------------------------
-- 9. Claims
-- ---------------------------------------------------------------------------

create table claims (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null references reports(id) on delete cascade,
  claimant_id    uuid not null references profiles(id) on delete cascade,
  status         claim_status not null default 'pending',
  rejection_note text,

  finder_confirmed_at    timestamptz,
  claimant_confirmed_at  timestamptz,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  unique (report_id, claimant_id)
);

-- Race condition #1: at most one approved claim per report, enforced by the
-- database rather than by application logic.
create unique index claims_one_approved_per_report
  on claims (report_id) where status = 'approved';

create index claims_report_idx on claims (report_id, status);
create index claims_claimant_idx on claims (claimant_id, created_at desc);

create table claim_answers (
  id           uuid primary key default gen_random_uuid(),
  claim_id     uuid not null references claims(id) on delete cascade,
  detail_id    uuid not null references private_verification_details(id) on delete cascade,
  answer       text not null check (char_length(answer) between 1 and 160),
  normalized_answer text generated always as (wassalni_normalize_ar(answer)) stored,
  graded_correct boolean,          -- set by the FINDER, never automatically
  created_at   timestamptz not null default now(),
  unique (claim_id, detail_id)
);

-- ---------------------------------------------------------------------------
-- 10. Match candidates
-- ---------------------------------------------------------------------------

create table match_candidates (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null references reports(id) on delete cascade,
  candidate_id   uuid not null references reports(id) on delete cascade,
  score          int not null check (score between 0 and 100),
  reasons        text[] not null default '{}',   -- 'same_area','same_category','close_date',...
  dismissed_at   timestamptz,
  dismissed_by   uuid references profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (report_id, candidate_id),
  check (report_id <> candidate_id)
);

create index match_candidates_report_idx
  on match_candidates (report_id, score desc) where dismissed_at is null;

-- ---------------------------------------------------------------------------
-- 11. Conversations and messages (P1 — participants only)
-- ---------------------------------------------------------------------------
-- A conversation exists only for an APPROVED claim. There is no way to message
-- a stranger in this product.

create table conversations (
  id          uuid primary key default gen_random_uuid(),
  claim_id    uuid not null unique references claims(id) on delete cascade,
  is_locked   boolean not null default false,
  created_at  timestamptz not null default now()
);

create table messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references conversations(id) on delete cascade,
  sender_id        uuid not null references profiles(id) on delete cascade,
  body             text not null check (char_length(body) between 1 and 1000),
  created_at       timestamptz not null default now(),
  read_at          timestamptz
);

create index messages_conversation_idx on messages (conversation_id, created_at desc);

-- Messages are P1 but still must not become a channel for leaking card/ID
-- numbers between two people who have not met.
create or replace function messages_guard()
returns trigger language plpgsql as $$
begin
  if wassalni_contains_sensitive_number(new.body) then
    raise exception 'SENSITIVE_NUMBER_IN_MESSAGE'
      using hint = 'من فضلك لا ترسل أرقام بطاقات أو هويات.';
  end if;
  if exists (select 1 from conversations c where c.id = new.conversation_id and c.is_locked) then
    raise exception 'CONVERSATION_LOCKED';
  end if;
  return new;
end;
$$;

create trigger messages_guard_trg
  before insert on messages
  for each row execute function messages_guard();

-- ---------------------------------------------------------------------------
-- 12. Moderation, notifications, devices, rate limiting
-- ---------------------------------------------------------------------------

create table moderation_reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references profiles(id) on delete cascade,
  entity        text not null check (entity in ('report','message','profile')),
  entity_id     uuid not null,
  reason        moderation_reason not null,
  note          text check (note is null or char_length(note) <= 500),
  resolved_at   timestamptz,
  resolved_by   uuid references profiles(id) on delete set null,
  resolution    text,
  created_at    timestamptz not null default now(),
  unique (reporter_id, entity, entity_id)
);

create index moderation_open_idx on moderation_reports (created_at desc) where resolved_at is null;

-- Auto-hide a report once 3 distinct users flag it. Reversible by a moderator.
create or replace function moderation_autohide()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.entity = 'report' and (
       select count(*) from moderation_reports m
        where m.entity = 'report' and m.entity_id = new.entity_id) >= 3 then
    update reports set is_hidden = true, hidden_reason = 'auto_threshold'
     where id = new.entity_id and not is_hidden;
  end if;
  return new;
end;
$$;

create trigger moderation_autohide_trg
  after insert on moderation_reports
  for each row execute function moderation_autohide();

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profiles(id) on delete cascade,
  kind        text not null,
  payload     jsonb not null default '{}',   -- ids and enums only, never free text
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_inbox_idx on notifications (profile_id, created_at desc);

create table device_tokens (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profiles(id) on delete cascade,
  fcm_token   text not null unique,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);

create table rate_limit_events (
  id          bigserial primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,
  action      text not null,
  created_at  timestamptz not null default now()
);

create index rate_limit_lookup_idx on rate_limit_events (profile_id, action, created_at desc);

create or replace function enforce_rate_limit(p_action text, p_limit int, p_window interval)
returns void language plpgsql security definer set search_path = public as $$
declare
  used int;
begin
  select count(*) into used
    from rate_limit_events
   where profile_id = auth.uid() and action = p_action and created_at > now() - p_window;

  if used >= p_limit then
    raise exception 'RATE_LIMITED: % (% per %)', p_action, p_limit, p_window;
  end if;

  insert into rate_limit_events (profile_id, action) values (auth.uid(), p_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Row Level Security — enable everywhere, then grant explicitly
-- ---------------------------------------------------------------------------

alter table communities                  enable row level security;
alter table areas                        enable row level security;
alter table categories                   enable row level security;
alter table colors                       enable row level security;
alter table color_adjacency              enable row level security;
alter table profiles                     enable row level security;
alter table reports                      enable row level security;
alter table report_images                enable row level security;
alter table report_private_details       enable row level security;
alter table private_verification_details enable row level security;
alter table claims                       enable row level security;
alter table claim_answers                enable row level security;
alter table match_candidates             enable row level security;
alter table conversations                enable row level security;
alter table messages                     enable row level security;
alter table moderation_reports           enable row level security;
alter table notifications                enable row level security;
alter table device_tokens                enable row level security;
alter table rate_limit_events            enable row level security;
alter table audit_log                    enable row level security;
alter table report_status_transitions    enable row level security;

-- Reference data: readable by any signed-in user, writable by nobody but staff.
create policy ref_read_communities on communities for select to authenticated using (true);
create policy ref_read_areas       on areas       for select to authenticated using (true);
create policy ref_read_categories  on categories  for select to authenticated using (is_active);
create policy ref_read_colors      on colors      for select to authenticated using (true);
create policy ref_read_adjacency   on color_adjacency for select to authenticated using (true);
create policy ref_read_transitions on report_status_transitions for select to authenticated using (true);

-- Profiles: you can read yourself, and the minimal public shape of others in
-- your community. Column-level exposure is handled by the client-facing view
-- `public_profiles` below rather than by selecting from this table directly.
create policy profiles_self_read on profiles
  for select to authenticated
  using (id = auth.uid() or current_is_staff() or community_id = current_community_id());

-- A subquery over `profiles` inside a policy on `profiles` recurses infinitely.
-- Role and suspension escalation is therefore blocked by a trigger, not a
-- WITH CHECK expression.
create policy profiles_self_update on profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_staff_update on profiles
  for update to authenticated
  using (current_role_is('admin'));

create or replace function profiles_block_self_escalation()
returns trigger language plpgsql as $$
begin
  if (new.role is distinct from old.role
      or new.is_suspended is distinct from old.is_suspended)
     and not current_role_is('admin') then
    raise exception 'ROLE_ESCALATION_DENIED';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_no_escalation
  before update on profiles
  for each row execute function profiles_block_self_escalation();

create view public_profiles
  with (security_invoker = true) as
  select id, display_name, returns_count, community_id from profiles where not is_suspended;

-- Reports: community-scoped, hidden and removed rows excluded, own rows always
-- visible to the author.
create policy reports_read on reports
  for select to authenticated
  using (
    current_is_staff()
    or profile_id = auth.uid()
    or (community_id = current_community_id() and status <> 'removed' and not is_hidden)
  );

create policy reports_insert on reports
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and current_is_active()
    and community_id = current_community_id()
  );

create policy reports_update_own on reports
  for update to authenticated
  using (profile_id = auth.uid() and current_is_active())
  with check (profile_id = auth.uid());

create policy reports_update_staff on reports
  for update to authenticated using (current_is_staff());

-- Images: public ones follow the report; private ones need ownership or an
-- approved claim on that report.
create policy report_images_read on report_images
  for select to authenticated
  using (
    exists (
      select 1 from reports r
       where r.id = report_images.report_id
         and (
           report_images.is_public
           or r.profile_id = auth.uid()
           or current_is_staff()
           or exists (select 1 from claims c
                       where c.report_id = r.id and c.claimant_id = auth.uid()
                         and c.status = 'approved')
         )
    )
  );

create policy report_images_write on report_images
  for all to authenticated
  using (exists (select 1 from reports r where r.id = report_images.report_id and r.profile_id = auth.uid()))
  with check (exists (select 1 from reports r where r.id = report_images.report_id and r.profile_id = auth.uid()));

-- P1: the report owner always; the counterparty only once their claim is
-- approved. This is why the location hint is not a column on `reports`.
create policy report_private_details_read on report_private_details
  for select to authenticated
  using (
    current_is_staff()
    or exists (select 1 from reports r
                where r.id = report_private_details.report_id and r.profile_id = auth.uid())
    or exists (select 1 from claims c
                where c.report_id = report_private_details.report_id
                  and c.claimant_id = auth.uid()
                  and c.status = 'approved')
  );

create policy report_private_details_write on report_private_details
  for all to authenticated
  using (exists (select 1 from reports r
                  where r.id = report_private_details.report_id and r.profile_id = auth.uid()))
  with check (exists (select 1 from reports r
                       where r.id = report_private_details.report_id and r.profile_id = auth.uid()));

-- THE critical policy. A claimant must never be able to read this table, by any
-- path. Only the report owner (the finder) and admins.
create policy pvd_owner_only on private_verification_details
  for all to authenticated
  using (
    exists (select 1 from reports r
             where r.id = private_verification_details.report_id
               and r.profile_id = auth.uid())
    or current_role_is('admin')
  )
  with check (
    exists (select 1 from reports r
             where r.id = private_verification_details.report_id
               and r.profile_id = auth.uid())
  );

-- Claims: visible to the claimant and to the owner of the claimed report.
create policy claims_read on claims
  for select to authenticated
  using (
    claimant_id = auth.uid()
    or current_is_staff()
    or exists (select 1 from reports r where r.id = claims.report_id and r.profile_id = auth.uid())
  );

create policy claims_insert on claims
  for insert to authenticated
  with check (
    claimant_id = auth.uid()
    and current_is_active()
    and exists (
      select 1 from reports r
       where r.id = claims.report_id
         and r.profile_id <> auth.uid()          -- cannot claim your own report
         and r.community_id = current_community_id()
         and r.status in ('open','possible_match','claim_in_progress')
         and not r.is_hidden
    )
  );

-- No client UPDATE policy on `claims` at all — deliberately. A WITH CHECK
-- cannot see OLD, so a permissive update policy would let a claimant set their
-- own claim to 'approved' straight through PostgREST. Every claim state change
-- goes through a SECURITY DEFINER RPC in 0002 (submit_claim, grade_claim,
-- withdraw_claim, confirm_return), each of which re-checks the caller's role.
revoke update, delete on claims from authenticated;

create policy claim_answers_rw on claim_answers
  for all to authenticated
  using (
    exists (
      select 1 from claims c
       where c.id = claim_answers.claim_id
         and (c.claimant_id = auth.uid()
              or exists (select 1 from reports r where r.id = c.report_id and r.profile_id = auth.uid()))
    )
  )
  with check (
    exists (select 1 from claims c where c.id = claim_answers.claim_id and c.claimant_id = auth.uid())
  );

-- Match candidates: only the owner of the anchor report sees its suggestions.
create policy match_candidates_read on match_candidates
  for select to authenticated
  using (exists (select 1 from reports r where r.id = match_candidates.report_id and r.profile_id = auth.uid()));

create policy match_candidates_dismiss on match_candidates
  for update to authenticated
  using (exists (select 1 from reports r where r.id = match_candidates.report_id and r.profile_id = auth.uid()));

-- Conversations and messages: participants of the approved claim only.
create policy conversations_read on conversations
  for select to authenticated
  using (
    exists (
      select 1 from claims c join reports r on r.id = c.report_id
       where c.id = conversations.claim_id
         and (c.claimant_id = auth.uid() or r.profile_id = auth.uid())
    )
    or current_is_staff()
  );

create policy messages_read on messages
  for select to authenticated
  using (
    exists (
      select 1 from conversations cv
        join claims c on c.id = cv.claim_id
        join reports r on r.id = c.report_id
       where cv.id = messages.conversation_id
         and (c.claimant_id = auth.uid() or r.profile_id = auth.uid())
    )
    or current_is_staff()
  );

create policy messages_insert on messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and current_is_active()
    and exists (
      select 1 from conversations cv
        join claims c on c.id = cv.claim_id
        join reports r on r.id = c.report_id
       where cv.id = messages.conversation_id
         and c.status = 'approved'
         and (c.claimant_id = auth.uid() or r.profile_id = auth.uid())
    )
  );

-- Moderation: a user can file and see their own; staff see all.
create policy moderation_insert on moderation_reports
  for insert to authenticated
  with check (reporter_id = auth.uid() and current_is_active());

create policy moderation_read on moderation_reports
  for select to authenticated
  using (reporter_id = auth.uid() or current_is_staff());

create policy moderation_resolve on moderation_reports
  for update to authenticated using (current_is_staff());

create policy notifications_own on notifications
  for all to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy device_tokens_own on device_tokens
  for all to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- P3: no client access at all. Written by SECURITY DEFINER functions, read via
-- the admin console using the service role.
create policy audit_admin_read on audit_log
  for select to authenticated using (current_role_is('admin'));

-- rate_limit_events: deliberately NO policy => default deny to all clients.
-- Only enforce_rate_limit() (SECURITY DEFINER) touches it.

commit;
