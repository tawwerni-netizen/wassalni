-- Wassalni / وصلني — close the verification oracle, the enumeration surface,
-- and the unenforced rate limits.
-- Depends on 0001..0005.
--
-- Three of the holes below were CREATED by the nationwide decision in 0003.
-- Before it, `reports_read` was scoped to the caller's community, which
-- incidentally bounded how much an attacker could harvest. Opening it up
-- nationally removed that accidental protection without replacing it.

begin;

-- ===========================================================================
-- 1. CRITICAL — the ownership-verification oracle
-- ===========================================================================
-- Three things combined:
--   * submit_claim used ON CONFLICT DO UPDATE, so a REJECTED claimant could
--     resubmit forever.
--   * claim_answers let the claimant SELECT their own rows, including
--     graded_correct — per-question right/wrong feedback.
--   * the same FOR ALL policy let them UPDATE the answer in place.
-- Net effect: guess, see which answers were wrong, correct them, resubmit.
-- Ten attempts a day against the mechanism that decides who receives someone
-- else's lost property.
--
-- Fix: clients get no DML and no SELECT on claim_answers at all. The finder
-- reads answers through an RPC; the claimant learns only their claim's status.

revoke insert, update, delete on claim_answers from authenticated;
revoke select on claim_answers from authenticated;
revoke insert, update, delete on claims from authenticated;

drop policy if exists claim_answers_rw on claim_answers;

-- Kept so staff can investigate an abuse report; ordinary clients now reach
-- this table only through the RPCs below.
create policy claim_answers_staff_read on claim_answers
  for select to authenticated
  using (current_is_staff());

-- Track attempts so a claim cannot be retried indefinitely.
alter table claims add column attempt_count int not null default 1;

-- The finder's grading view. Only the report owner may call it.
create or replace function get_claim_answers_for_grading(p_claim_id uuid)
returns table (
  detail_id uuid,
  question text,
  answer text,
  graded_correct boolean,
  similarity_hint real
)
language plpgsql stable security definer set search_path = public as $$
declare v_claim claims; v_report reports;
begin
  select * into v_claim from claims where id = p_claim_id;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;

  select * into v_report from reports where id = v_claim.report_id;
  if v_report.profile_id <> auth.uid() and not current_is_staff() then
    raise exception 'NOT_REPORT_OWNER';
  end if;

  return query
    select d.id,
           d.question_ar,
           a.answer,
           a.graded_correct,
           -- a hint, never a decision: real answers vary too much
           -- ("أزرق" vs "ازرق فاتح") for an automatic comparison to be fair.
           similarity(d.normalized_expected, a.normalized_answer)
      from private_verification_details d
      left join claim_answers a on a.detail_id = d.id and a.claim_id = p_claim_id
     where d.report_id = v_claim.report_id
     order by d.sort_order;
end;
$$;

-- What a claimant is allowed to see about their own claim: the outcome, and
-- nothing per-question.
create or replace function get_my_claim_status(p_claim_id uuid)
returns table (status claim_status, rejection_note text, attempts_left int)
language sql stable security definer set search_path = public as $$
  select c.status, c.rejection_note, greatest(0, 2 - c.attempt_count)
    from claims c
   where c.id = p_claim_id and c.claimant_id = auth.uid();
$$;

create or replace function submit_claim(p_report_id uuid, p_answers jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_claim_id uuid;
  v_report   reports;
  v_existing claims;
  a jsonb;
begin
  perform enforce_rate_limit('claim_submit', 5, interval '1 day');

  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;
  if v_report.profile_id = auth.uid() then raise exception 'CANNOT_CLAIM_OWN_REPORT'; end if;
  if v_report.status not in ('open','possible_match','claim_in_progress') then
    raise exception 'REPORT_NOT_CLAIMABLE: %', v_report.status;
  end if;
  if exists (select 1 from claims where report_id = p_report_id and status = 'approved') then
    raise exception 'REPORT_ALREADY_MATCHED';
  end if;

  select * into v_existing from claims
   where report_id = p_report_id and claimant_id = auth.uid() for update;

  if found then
    -- A rejected claimant does not get to try again on their own. The finder
    -- must reopen, which puts a human between the attacker and the next guess.
    if v_existing.status = 'rejected' then
      raise exception 'CLAIM_REJECTED_CONTACT_FINDER'
        using hint = 'البلاغ ده اتراجع قبل كده. لو متأكد إنها بتاعتك، استنى صاحب البلاغ يفتح الطلب تاني.';
    end if;
    if v_existing.status in ('withdrawn','expired') and v_existing.attempt_count >= 2 then
      raise exception 'CLAIM_ATTEMPTS_EXHAUSTED';
    end if;

    update claims
       set status = 'verifying',
           attempt_count = v_existing.attempt_count + 1,
           updated_at = now()
     where id = v_existing.id
    returning id into v_claim_id;
  else
    insert into claims (report_id, claimant_id, status)
    values (p_report_id, auth.uid(), 'verifying')
    returning id into v_claim_id;
  end if;

  for a in select * from jsonb_array_elements(p_answers) loop
    insert into claim_answers (claim_id, detail_id, answer)
    select v_claim_id, (a->>'detail_id')::uuid, a->>'answer'
     where exists (select 1 from private_verification_details d
                    where d.id = (a->>'detail_id')::uuid and d.report_id = p_report_id)
    on conflict (claim_id, detail_id)
      do update set answer = excluded.answer, graded_correct = null;
  end loop;

  update reports set status = 'claim_in_progress'
   where id = p_report_id and status in ('open','possible_match');

  insert into audit_log (actor_id, entity, entity_id, action, after_state)
  values (auth.uid(), 'claim', v_claim_id, 'submitted',
          jsonb_build_object('report_id', p_report_id));

  insert into notifications (profile_id, kind, payload)
  select v_report.profile_id, 'claim_submitted', jsonb_build_object('claim_id', v_claim_id)
   where v_report.profile_id is not null;

  return v_claim_id;
end;
$$;

-- The finder can deliberately give a second chance. Explicit, logged, and
-- rate-limited by being a human decision rather than a retry loop.
create or replace function reopen_claim(p_claim_id uuid)
returns claim_status
language plpgsql security definer set search_path = public as $$
declare v_claim claims; v_report reports;
begin
  select * into v_claim from claims where id = p_claim_id;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  select * into v_report from reports where id = v_claim.report_id for update;
  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;
  if v_claim.attempt_count >= 2 then raise exception 'CLAIM_ATTEMPTS_EXHAUSTED'; end if;

  update claims set status = 'verifying', rejection_note = null, updated_at = now()
   where id = p_claim_id;
  return 'verifying';
end;
$$;

-- ===========================================================================
-- 2. HIGH — a person's whereabouts could be reconstructed
-- ===========================================================================
-- reports.profile_id was readable on every nationally-visible report. Read one
-- report, take the author's id, filter every report by it: a dated, located
-- movement history for a named person. This is the worst privacy outcome the
-- product can produce and it existed by accident.

-- Revoking a column's SELECT also blocks FILTERING by it, which is the actual
-- attack: PostgREST needs SELECT on a column to accept `?profile_id=eq.<uuid>`.
-- The base table stays otherwise readable, so RLS policies on other tables that
-- reference `reports` in EXISTS subqueries keep working.
revoke select (profile_id) on reports from authenticated;

-- Deliberately NOT security_invoker. Under invoker semantics this view would be
-- subject to the revoke above and could not compute is_mine at all. As a
-- definer view it can read profile_id, reduce it to a boolean, and hand back
-- nothing joinable — but that means RLS is bypassed inside it, so the row rules
-- must be stated here explicitly rather than inherited.
create or replace view v_reports as
  select r.id, r.report_type, r.status, r.community_id, r.governorate_id,
         r.area_id, r.category_id, r.color_id, r.brand, r.title, r.description,
         r.occurred_on, r.occurred_time_bucket,
         r.created_at, r.updated_at,
         (r.profile_id = auth.uid()) as is_mine,
         p.display_name as author_display_name,
         p.returns_count as author_returns_count
    from reports r
    left join profiles p on p.id = r.profile_id
   where
     -- mirrors the reports_read policy, which this view no longer inherits
     r.profile_id = auth.uid()
     or current_is_staff()
     or (r.status <> 'removed' and not r.is_hidden);

grant select on v_reports to authenticated;

-- Reports are national now, so display names must be readable nationally or
-- every out-of-community report renders with a blank author. Only the
-- display-name shape is exposed; the base table stays gated.
drop policy if exists profiles_self_read on profiles;
create policy profiles_self_read on profiles
  for select to authenticated
  using (id = auth.uid() or current_is_staff() or not is_suspended);

revoke select on profiles from authenticated;
grant select (id, display_name, returns_count, community_id) on profiles to authenticated;

-- ===========================================================================
-- 3. HIGH — enumerating valuable lost items nationwide
-- ===========================================================================
-- "category = jewelry, status = open, all of Egypt, page 40" is a shopping list
-- for fraudulent claims, complete with area and date. Before 0003 the community
-- scope bounded this; now nothing does.
--
-- The fix preserves the real use case and kills the harvesting one: someone who
-- lost a thing searches for that thing by name. Nobody legitimately browses
-- every jewelry report in Egypt by page number.

create or replace function search_reports(
  p_query        text default null,
  p_scope_id     uuid default null,
  p_type         report_type default null,
  p_category_id  text default null,
  p_area_id      uuid default null,
  p_color_id     text default null,
  p_from         date default null,
  p_to           date default null,
  p_limit        int default 20,
  p_offset       int default 0
)
returns setof v_reports
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := wassalni_normalize_ar(p_query);
  v_scope uuid := coalesce(p_scope_id, current_community_id());
  v_scope_kind community_kind;
begin
  select kind into v_scope_kind from communities where id = v_scope;

  -- Browsing without a search term is a local activity. Widening past a
  -- district requires actually searching for something.
  if v_q is null and v_scope_kind in ('country','governorate') then
    raise exception 'QUERY_REQUIRED_FOR_WIDE_SCOPE'
      using hint = 'اكتب اسم الحاجة اللي بتدور عليها عشان تبحث في نطاق أوسع.';
  end if;

  -- Deep pagination is harvesting, not searching. Refine instead.
  if coalesce(p_offset, 0) > 200 then
    raise exception 'RESULT_DEPTH_EXCEEDED'
      using hint = 'ضيّق البحث بدل ما تكمل تصفّح.';
  end if;

  return query
    select v.* from v_reports v
      join communities cm on cm.id = v.community_id
     where v_scope = any(cm.ancestor_ids)
       and (p_type        is null or v.report_type = p_type)
       and (p_category_id is null or v.category_id = p_category_id)
       and (p_area_id     is null or v.area_id     = p_area_id)
       and (p_color_id    is null or v.color_id    = p_color_id)
       and (p_from        is null or v.occurred_on >= p_from)
       and (p_to          is null or v.occurred_on <= p_to)
       and (
         v_q is null
         or exists (select 1 from reports r
                     where r.id = v.id
                       and (r.search_vector @@ plainto_tsquery('simple', v_q)
                            or r.normalized_text % v_q))
       )
     order by (v.community_id = current_community_id()) desc,
              v.created_at desc
     limit least(coalesce(p_limit, 20), 50)
    offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- ===========================================================================
-- 4. HIGH — a photographed ID becoming a public image
-- ===========================================================================
-- The text guard catches an ID typed into a description. It cannot see a photo
-- of the ID card sitting inside the found wallet. Images default to public,
-- which is exactly backwards for a FOUND report: its whole premise is that
-- identifying detail stays back as verification material.

create or replace function report_images_default_privacy()
returns trigger language plpgsql as $$
declare v_type report_type; v_category text;
begin
  select report_type, category_id into v_type, v_category
    from reports where id = new.report_id;

  -- FOUND images and anything filed under documents are private unless the
  -- owner deliberately publishes them.
  if v_type = 'found' or v_category = 'documents' then
    new.is_public := false;
  end if;
  return new;
end;
$$;

create trigger report_images_privacy_trg
  before insert on report_images
  for each row execute function report_images_default_privacy();

-- Documents can never be published, deliberately or otherwise.
create or replace function report_images_block_document_publish()
returns trigger language plpgsql as $$
begin
  if new.is_public and exists (
       select 1 from reports r
        where r.id = new.report_id and r.category_id = 'documents') then
    raise exception 'DOCUMENT_IMAGES_CANNOT_BE_PUBLIC'
      using hint = 'صور المستندات مش بتظهر للناس — بتتستخدم للتأكد من صاحبها بس.';
  end if;
  return new;
end;
$$;

create trigger report_images_document_guard_trg
  before insert or update on report_images
  for each row execute function report_images_block_document_publish();

-- At most three images per report, enforced server-side. The client cap was
-- advisory.
create or replace function report_images_cap()
returns trigger language plpgsql as $$
begin
  if (select count(*) from report_images where report_id = new.report_id) >= 3 then
    raise exception 'TOO_MANY_IMAGES';
  end if;
  return new;
end;
$$;

create trigger report_images_cap_trg
  before insert on report_images
  for each row execute function report_images_cap();

-- ===========================================================================
-- 5. HIGH — documented rate limits that were never enforced
-- ===========================================================================
-- ARCHITECTURE §8 promised 5 reports/day, 30 messages/minute, 3 abuse
-- reports/day. enforce_rate_limit() existed and was called in exactly one
-- place. Triggers are used rather than RPC rewrites so the limits bind no
-- matter which path the write takes.

create or replace function rate_limit_reports()
returns trigger language plpgsql as $$
begin
  perform enforce_rate_limit('report_create', 5, interval '1 day');
  return new;
end;
$$;

create trigger reports_rate_limit_trg
  before insert on reports
  for each row execute function rate_limit_reports();

create or replace function rate_limit_messages()
returns trigger language plpgsql as $$
begin
  perform enforce_rate_limit('message_send', 30, interval '1 minute');
  return new;
end;
$$;

create trigger messages_rate_limit_trg
  before insert on messages
  for each row execute function rate_limit_messages();

create or replace function rate_limit_moderation()
returns trigger language plpgsql as $$
begin
  perform enforce_rate_limit('abuse_report', 3, interval '1 day');
  return new;
end;
$$;

create trigger moderation_rate_limit_trg
  before insert on moderation_reports
  for each row execute function rate_limit_moderation();

-- ===========================================================================
-- 6. MEDIUM — deadlock from inconsistent lock ordering
-- ===========================================================================
-- submit_claim locked reports then claims; grade_claim, confirm_return and
-- withdraw_claim locked claims then reports. Two people acting on one report at
-- the same moment deadlock. Postgres aborts one, so it surfaces as a random
-- failure rather than corruption. Everything now locks reports first.

create or replace function grade_claim(
  p_claim_id uuid, p_grades jsonb, p_approve boolean, p_note text default null
)
returns claim_status
language plpgsql security definer set search_path = public as $$
declare v_claim claims; v_report reports; g jsonb;
begin
  -- reports first, always
  select r.* into v_report from reports r
    join claims c on c.report_id = r.id
   where c.id = p_claim_id for update of r;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;

  select * into v_claim from claims where id = p_claim_id for update;
  if v_claim.status not in ('pending','verifying') then
    raise exception 'CLAIM_NOT_GRADABLE: %', v_claim.status;
  end if;

  for g in select * from jsonb_array_elements(p_grades) loop
    update claim_answers set graded_correct = (g->>'correct')::boolean
     where claim_id = p_claim_id and detail_id = (g->>'detail_id')::uuid;
  end loop;

  if p_approve then
    update claims set status = 'approved', updated_at = now() where id = p_claim_id;
    update claims set status = 'rejected', rejection_note = 'another_claim_approved', updated_at = now()
     where report_id = v_claim.report_id and id <> p_claim_id
       and status in ('pending','verifying');
    update reports set status = 'matched' where id = v_claim.report_id;
    insert into conversations (claim_id) values (p_claim_id) on conflict (claim_id) do nothing;
    insert into notifications (profile_id, kind, payload)
    values (v_claim.claimant_id, 'claim_approved', jsonb_build_object('claim_id', p_claim_id));
  else
    update claims set status = 'rejected', rejection_note = p_note, updated_at = now()
     where id = p_claim_id;
    update reports set status = 'possible_match'
     where id = v_claim.report_id and status = 'claim_in_progress'
       and not exists (select 1 from claims c
                        where c.report_id = v_claim.report_id
                          and c.status in ('pending','verifying','approved'));
    insert into notifications (profile_id, kind, payload)
    values (v_claim.claimant_id, 'claim_rejected', jsonb_build_object('claim_id', p_claim_id));
  end if;

  insert into audit_log (actor_id, entity, entity_id, action, before_state, after_state)
  values (auth.uid(), 'claim', p_claim_id, 'graded',
          jsonb_build_object('status', v_claim.status),
          jsonb_build_object('approved', p_approve));

  return (select status from claims where id = p_claim_id);
end;
$$;

-- ===========================================================================
-- 7. MEDIUM — a matched report could stall forever
-- ===========================================================================
-- confirm_return needs both sides. expire_stale_claims only ever expired
-- pending/verifying, so if one party confirmed and the other vanished, the
-- report sat in `matched` permanently: unclaimable by anyone else, and absent
-- from the time-to-resolution metric.

create or replace function expire_stale_claims()
returns int language plpgsql security definer set search_path = public as $$
declare n int; m int;
begin
  with expired as (
    update claims set status = 'expired', updated_at = now()
     where status in ('pending','verifying')
       and updated_at < now() - interval '7 days'
    returning 1
  ) select count(*) into n from expired;

  with released as (
    update claims set status = 'expired', updated_at = now()
     where status = 'approved'
       and (finder_confirmed_at is null or claimant_confirmed_at is null)
       and updated_at < now() - interval '14 days'
    returning report_id
  ) select count(*) into m from released;

  update reports r set status = 'claim_in_progress'
   where r.status = 'matched'
     and not exists (select 1 from claims c
                      where c.report_id = r.id and c.status = 'approved');

  update reports r set status = 'possible_match'
   where r.status = 'claim_in_progress'
     and not exists (select 1 from claims c
                      where c.report_id = r.id and c.status in ('pending','verifying','approved'));

  return n + m;
end;
$$;

commit;
