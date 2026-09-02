-- Wassalni / وصلني — nationwide coverage with hierarchical scope.
-- Depends on 0001_init.sql, 0002_matching_search_rpcs.sql.
--
-- WHY THIS SHAPE
-- The product decision is "all of Egypt, and every community type". The naive
-- implementation is to delete the community boundary and let everything match
-- everything. That destroys the only signal matching has: a wallet lost in
-- Aswan has nothing to do with one found in Alexandria, and a feed of national
-- noise is worse than an empty local one.
--
-- So scope becomes a HIERARCHY rather than a boundary:
--
--     Egypt (country)
--       └─ Governorate  (27)
--            └─ City / District
--                 └─ Campus | Mall | Compound | Workplace   <- reports attach here
--                      └─ Area (curated landmarks)
--
--   * SEARCH is nationwide. A user can widen the scope to any ancestor, up to
--     the whole country, and the feed defaults to their own community.
--   * AUTOMATIC MATCHING is bounded to the governorate, because that is where
--     the signal actually lives. Proximity is scored, not merely required.
--   * "Same area" therefore still means something, which is what keeps the
--     match suggestions credible.

begin;

create type community_kind as enum (
  'country', 'governorate', 'city', 'district',
  'campus', 'mall', 'compound', 'workplace'
);

alter table communities
  add column parent_id     uuid references communities(id) on delete restrict,
  add column kind          community_kind not null default 'campus',
  add column ancestor_ids  uuid[] not null default '{}',   -- self + all ancestors
  add column depth         int not null default 0,
  -- reports attach to venues and districts, never to a governorate or country
  add column is_reportable boolean not null default true;

create index communities_ancestors_idx on communities using gin (ancestor_ids);
create index communities_parent_idx    on communities (parent_id, kind);

-- Maintains ancestor_ids/depth. Also refuses cycles, which would otherwise
-- make every subtree query non-terminating.
create or replace function communities_set_path()
returns trigger language plpgsql as $$
declare
  parent_ancestors uuid[];
  parent_depth int;
begin
  if new.parent_id is null then
    new.ancestor_ids := array[new.id];
    new.depth := 0;
  else
    select c.ancestor_ids, c.depth into parent_ancestors, parent_depth
      from communities c where c.id = new.parent_id;
    if not found then
      raise exception 'PARENT_COMMUNITY_NOT_FOUND';
    end if;
    if new.id = any(parent_ancestors) then
      raise exception 'COMMUNITY_CYCLE_DETECTED';
    end if;
    new.ancestor_ids := parent_ancestors || new.id;
    new.depth := parent_depth + 1;
  end if;
  return new;
end;
$$;

create trigger communities_path_trg
  before insert or update of parent_id on communities
  for each row execute function communities_set_path();

-- Rewriting a parent must rewrite the whole subtree, or ancestor_ids goes stale
-- and scope queries silently return wrong results.
create or replace function communities_reparent_subtree()
returns trigger language plpgsql as $$
begin
  if new.ancestor_ids is distinct from old.ancestor_ids then
    update communities c
       set parent_id = c.parent_id          -- re-fires the BEFORE trigger
     where c.parent_id = new.id;
  end if;
  return null;
end;
$$;

create trigger communities_reparent_trg
  after update of ancestor_ids on communities
  for each row execute function communities_reparent_subtree();

-- ---------------------------------------------------------------------------
-- Reports carry a denormalised governorate id so matching stays a single
-- indexed predicate instead of a recursive walk on every insert.
-- ---------------------------------------------------------------------------

alter table reports add column governorate_id uuid references communities(id);

create index reports_governorate_match_idx
  on reports (governorate_id, report_type, status, occurred_on)
  where not is_hidden;

create or replace function reports_set_governorate()
returns trigger language plpgsql as $$
declare
  v_kind community_kind;
  v_ancestor_ids uuid[];
begin
  select c.kind, c.ancestor_ids into v_kind, v_ancestor_ids
    from communities c where c.id = new.community_id;
  if v_kind is null then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if v_kind in ('country','governorate') then
    raise exception 'COMMUNITY_NOT_REPORTABLE: reports attach to a venue or district, not a %', v_kind;
  end if;

  -- `= any((select ...))` parses as ANY (subquery), not ANY (array); see the
  -- 0005 redefinition of this same function for the full explanation. Fixed
  -- here too so this file is correct standalone, even though 0005 supersedes
  -- it moments later in the applied migration order.
  select c.id into new.governorate_id
    from communities c
   where c.id = any(v_ancestor_ids)
     and c.kind = 'governorate';

  return new;
end;
$$;

create trigger reports_governorate_trg
  before insert or update of community_id on reports
  for each row execute function reports_set_governorate();

-- ---------------------------------------------------------------------------
-- RLS: reports are P0 and now nationally visible. Writing is still scoped.
-- ---------------------------------------------------------------------------

drop policy reports_read on reports;
create policy reports_read on reports
  for select to authenticated
  using (
    current_is_staff()
    or profile_id = auth.uid()
    or (status <> 'removed' and not is_hidden)
  );

drop policy reports_insert on reports;
create policy reports_insert on reports
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and current_is_active()
    and exists (
      select 1 from communities c
       where c.id = reports.community_id
         and c.is_active
         and c.is_reportable
    )
  );

-- ---------------------------------------------------------------------------
-- Matching: scope proximity replaces the hard community equality check.
-- ---------------------------------------------------------------------------

create or replace function match_score(anchor reports, cand reports)
returns table (score int, reasons text[])
language plpgsql
stable
as $$
declare
  s int := 0;
  r text[] := '{}';
  anchor_group text;
  cand_group   text;
  anchor_parent uuid;
  cand_parent   uuid;
  day_gap int;
  sim real;
begin
  select group_key into anchor_group from categories where id = anchor.category_id;
  select group_key into cand_group   from categories where id = cand.category_id;

  -- category
  if anchor.category_id = cand.category_id then
    s := s + 30; r := r || 'same_category';
  elsif anchor_group is not null and anchor_group = cand_group then
    s := s + 15; r := r || 'similar_category';
  end if;

  -- scope proximity, most specific wins
  select parent_id into anchor_parent from communities where id = anchor.community_id;
  select parent_id into cand_parent   from communities where id = cand.community_id;

  if anchor.area_id is not null and anchor.area_id = cand.area_id then
    s := s + 25; r := r || 'same_area';
  elsif anchor.community_id = cand.community_id then
    s := s + 12; r := r || 'same_community';
  elsif anchor_parent is not null and anchor_parent = cand_parent then
    s := s + 6;  r := r || 'nearby_place';
  elsif anchor.governorate_id is not null and anchor.governorate_id = cand.governorate_id then
    s := s + 3;  r := r || 'same_governorate';
  end if;

  -- date proximity
  day_gap := abs(anchor.occurred_on - cand.occurred_on);
  if day_gap <= 1 then
    s := s + 20; r := r || 'same_day';
  elsif day_gap <= 3 then
    s := s + 15; r := r || 'close_date';
  elsif day_gap <= 7 then
    s := s + 10; r := r || 'close_date';
  elsif day_gap <= 14 then
    s := s + 5;  r := r || 'nearby_date';
  end if;

  -- colour
  if anchor.color_id is not null and anchor.color_id = cand.color_id then
    s := s + 10; r := r || 'same_color';
  elsif anchor.color_id is not null and cand.color_id is not null
        and exists (select 1 from color_adjacency ca
                     where ca.color_id = anchor.color_id and ca.adjacent_id = cand.color_id) then
    s := s + 5; r := r || 'similar_color';
  end if;

  -- free-text similarity
  sim := similarity(coalesce(anchor.normalized_text,''), coalesce(cand.normalized_text,''));
  if sim >= 0.45 then
    s := s + 15; r := r || 'similar_description';
  elsif sim >= 0.30 then
    s := s + 8;  r := r || 'similar_description';
  end if;

  -- brand
  if anchor.brand is not null and cand.brand is not null
     and wassalni_normalize_ar(anchor.brand) = wassalni_normalize_ar(cand.brand) then
    s := s + 10; r := r || 'same_brand';
  end if;

  score := least(s, 100);
  reasons := r;
  return next;
end;
$$;

create or replace function generate_match_candidates(p_report_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  anchor reports;
  cand   reports;
  m      record;
  created int := 0;
begin
  select * into anchor from reports where id = p_report_id;
  if not found or anchor.status not in ('open','possible_match') then
    return 0;
  end if;

  for cand in
    select r.* from reports r
     where r.governorate_id is not distinct from anchor.governorate_id  -- see header note
       and r.report_type <> anchor.report_type
       and r.status in ('open','possible_match')
       and not r.is_hidden
       and r.id <> anchor.id
       and (r.profile_id is distinct from anchor.profile_id)
       and case when anchor.report_type = 'lost'
                then r.occurred_on between anchor.occurred_on - 2 and anchor.occurred_on + 14
                else anchor.occurred_on between r.occurred_on - 2 and r.occurred_on + 14
           end
     -- prefer the most local candidates when the governorate is busy
     order by (r.community_id = anchor.community_id) desc, r.created_at desc
     limit 200
  loop
    select * into m from match_score(anchor, cand);

    if m.score >= 45 then
      insert into match_candidates (report_id, candidate_id, score, reasons)
      values (anchor.id, cand.id, m.score, m.reasons)
      on conflict (report_id, candidate_id)
        do update set score = excluded.score, reasons = excluded.reasons
        where match_candidates.dismissed_at is null;

      insert into match_candidates (report_id, candidate_id, score, reasons)
      values (cand.id, anchor.id, m.score, m.reasons)
      on conflict (report_id, candidate_id)
        do update set score = excluded.score, reasons = excluded.reasons
        where match_candidates.dismissed_at is null;

      created := created + 1;

      update reports set status = 'possible_match'
       where id in (anchor.id, cand.id) and status = 'open';

      insert into notifications (profile_id, kind, payload)
      select r.profile_id, 'possible_match',
             jsonb_build_object('report_id', r.id, 'reasons', to_jsonb(m.reasons))
        from reports r where r.id in (anchor.id, cand.id) and r.profile_id is not null;
    end if;
  end loop;

  return created;
end;
$$;

-- ---------------------------------------------------------------------------
-- Search: nationwide, scoped to any node in the tree.
-- ---------------------------------------------------------------------------

drop function if exists search_reports(text, report_type, text, uuid, text, date, date, int, int);

-- p_scope_id: any community id. Pass the user's own community for a local feed,
-- a governorate to widen, or the country root for all of Egypt. Null defaults
-- to the user's own community; pass the root explicitly to search nationally.
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
returns setof reports
language sql
stable
as $$
  with params as (
    select wassalni_normalize_ar(p_query) as q,
           coalesce(p_scope_id, current_community_id()) as scope
  )
  select r.*
    from reports r
    join communities cm on cm.id = r.community_id,
         params p
   where (p.scope is null or p.scope = any(cm.ancestor_ids))
     and r.status <> 'removed'
     and not r.is_hidden
     and (p_type        is null or r.report_type = p_type)
     and (p_category_id is null or r.category_id = p_category_id)
     and (p_area_id     is null or r.area_id     = p_area_id)
     and (p_color_id    is null or r.color_id    = p_color_id)
     and (p_from        is null or r.occurred_on >= p_from)
     and (p_to          is null or r.occurred_on <= p_to)
     and (
       p.q is null
       or r.search_vector @@ plainto_tsquery('simple', p.q)
       or r.normalized_text % p.q
     )
   order by
     -- local first, then relevance, then recency
     (r.community_id = current_community_id()) desc,
     case when p.q is null then 0
          else ts_rank(r.search_vector, plainto_tsquery('simple', p.q))
               + similarity(r.normalized_text, p.q)
     end desc,
     r.created_at desc
   limit least(coalesce(p_limit, 20), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- How many reports exist just outside the current scope? Drives the
-- "وسّع البحث" affordance instead of showing a dead end.
create or replace function count_reports_in_scope(p_scope_id uuid, p_type report_type default null)
returns int
language sql
stable
as $$
  select count(*)::int
    from reports r join communities cm on cm.id = r.community_id
   where p_scope_id = any(cm.ancestor_ids)
     and r.status not in ('removed','closed')
     and not r.is_hidden
     and (p_type is null or r.report_type = p_type);
$$;

-- ---------------------------------------------------------------------------
-- Seed: Egypt and its 27 governorates.
-- Cities/districts and venues are seeded per-launch; see docs/SEEDING.md.
-- ---------------------------------------------------------------------------

insert into communities (slug, name_ar, name_en, kind, is_reportable) values
  ('eg', 'مصر', 'Egypt', 'country', false);

insert into communities (slug, name_ar, name_en, kind, is_reportable, parent_id)
select v.slug, v.ar, v.en, 'governorate', false, (select id from communities where slug = 'eg')
from (values
  ('eg-cairo',      'القاهرة',        'Cairo'),
  ('eg-giza',       'الجيزة',         'Giza'),
  ('eg-alexandria', 'الإسكندرية',     'Alexandria'),
  ('eg-qalyubia',   'القليوبية',      'Qalyubia'),
  ('eg-portsaid',   'بورسعيد',        'Port Said'),
  ('eg-suez',       'السويس',         'Suez'),
  ('eg-dakahlia',   'الدقهلية',       'Dakahlia'),
  ('eg-sharqia',    'الشرقية',        'Sharqia'),
  ('eg-gharbia',    'الغربية',        'Gharbia'),
  ('eg-monufia',    'المنوفية',       'Monufia'),
  ('eg-beheira',    'البحيرة',        'Beheira'),
  ('eg-kafrelsheikh','كفر الشيخ',     'Kafr El Sheikh'),
  ('eg-damietta',   'دمياط',          'Damietta'),
  ('eg-ismailia',   'الإسماعيلية',    'Ismailia'),
  ('eg-faiyum',     'الفيوم',         'Faiyum'),
  ('eg-benisuef',   'بني سويف',       'Beni Suef'),
  ('eg-minya',      'المنيا',         'Minya'),
  ('eg-asyut',      'أسيوط',          'Asyut'),
  ('eg-sohag',      'سوهاج',          'Sohag'),
  ('eg-qena',       'قنا',            'Qena'),
  ('eg-luxor',      'الأقصر',         'Luxor'),
  ('eg-aswan',      'أسوان',          'Aswan'),
  ('eg-redsea',     'البحر الأحمر',   'Red Sea'),
  ('eg-newvalley',  'الوادي الجديد',  'New Valley'),
  ('eg-matrouh',    'مطروح',          'Matrouh'),
  ('eg-northsinai', 'شمال سيناء',     'North Sinai'),
  ('eg-southsinai', 'جنوب سيناء',     'South Sinai')
) as v(slug, ar, en);

commit;
