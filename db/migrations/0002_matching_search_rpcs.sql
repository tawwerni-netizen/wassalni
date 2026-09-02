-- Wassalni / وصلني — matching, search, and the transactional claim RPCs.
-- Depends on 0001_init.sql.
--
-- Design notes:
--   * Matching is rule-based and explainable. The score is an internal ordering
--     device; the CLIENT NEVER RECEIVES IT as a confidence figure — it receives
--     `reasons`, which is what the UI renders as chips.
--   * Every state transition that can race is done inside one function with an
--     explicit row lock. See ARCHITECTURE.md §7.

begin;

-- ---------------------------------------------------------------------------
-- 1. Matching
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

  -- area
  if anchor.area_id is not null and anchor.area_id = cand.area_id then
    s := s + 25; r := r || 'same_area';
  elsif anchor.community_id = cand.community_id then
    s := s + 10; r := r || 'same_community';
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
     where r.community_id = anchor.community_id
       and r.report_type <> anchor.report_type
       and r.status in ('open','possible_match')
       and not r.is_hidden
       and r.id <> anchor.id
       and (r.profile_id is distinct from anchor.profile_id)
       -- a found report normally happens on or after the loss; allow 2 days of
       -- slack for people who misremember the date
       and case when anchor.report_type = 'lost'
                then r.occurred_on between anchor.occurred_on - 2 and anchor.occurred_on + 14
                else anchor.occurred_on between r.occurred_on - 2 and r.occurred_on + 14
           end
     order by r.created_at desc
     limit 200
  loop
    select * into m from match_score(anchor, cand);

    if m.score >= 45 then
      -- symmetric: both owners should see the suggestion
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

create or replace function reports_after_insert_match()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform generate_match_candidates(new.id);
  return null;
end;
$$;

create trigger reports_match_trg
  after insert on reports
  for each row execute function reports_after_insert_match();

-- Nightly sweep: date windows widen as time passes, and a report created today
-- can become a candidate for one created two weeks ago.
create or replace function sweep_match_candidates()
returns int language plpgsql security definer set search_path = public as $$
declare
  rec record; total int := 0;
begin
  for rec in select id from reports
              where status in ('open','possible_match')
                and created_at > now() - interval '14 days'
  loop
    total := total + generate_match_candidates(rec.id);
  end loop;
  return total;
end;
$$;

-- select cron.schedule('wassalni-match-sweep', '0 2 * * *', 'select sweep_match_candidates()');

-- ---------------------------------------------------------------------------
-- 2. Search
-- ---------------------------------------------------------------------------

create or replace function search_reports(
  p_query        text default null,
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
  with normalized as (select wassalni_normalize_ar(p_query) as q)
  select r.*
    from reports r, normalized n
   where r.community_id = current_community_id()
     and r.status <> 'removed'
     and not r.is_hidden
     and (p_type        is null or r.report_type = p_type)
     and (p_category_id is null or r.category_id = p_category_id)
     and (p_area_id     is null or r.area_id     = p_area_id)
     and (p_color_id    is null or r.color_id    = p_color_id)
     and (p_from        is null or r.occurred_on >= p_from)
     and (p_to          is null or r.occurred_on <= p_to)
     and (
       n.q is null
       or r.search_vector @@ plainto_tsquery('simple', n.q)
       or r.normalized_text % n.q                      -- trigram fallback for typos
     )
   order by
     case when n.q is null then 0
          else ts_rank(r.search_vector, plainto_tsquery('simple', n.q))
               + similarity(r.normalized_text, n.q)
     end desc,
     r.created_at desc
   limit least(coalesce(p_limit, 20), 50)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- ---------------------------------------------------------------------------
-- 3. Claim lifecycle — the transactional parts
-- ---------------------------------------------------------------------------

create or replace function submit_claim(
  p_report_id uuid,
  p_answers   jsonb            -- [{"detail_id":"...","answer":"..."}]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim_id uuid;
  v_report   reports;
  a jsonb;
begin
  perform enforce_rate_limit('claim_submit', 10, interval '1 day');

  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;
  if v_report.profile_id = auth.uid() then raise exception 'CANNOT_CLAIM_OWN_REPORT'; end if;
  if v_report.status not in ('open','possible_match','claim_in_progress') then
    raise exception 'REPORT_NOT_CLAIMABLE: %', v_report.status;
  end if;
  if exists (select 1 from claims where report_id = p_report_id and status = 'approved') then
    raise exception 'REPORT_ALREADY_MATCHED';
  end if;

  insert into claims (report_id, claimant_id, status)
  values (p_report_id, auth.uid(), 'verifying')
  on conflict (report_id, claimant_id) do update set status = 'verifying', updated_at = now()
  returning id into v_claim_id;

  for a in select * from jsonb_array_elements(p_answers) loop
    -- a claimant may only answer questions belonging to THIS report; the answer
    -- is stored, never compared against the expected value on their behalf
    insert into claim_answers (claim_id, detail_id, answer)
    select v_claim_id, (a->>'detail_id')::uuid, a->>'answer'
     where exists (select 1 from private_verification_details d
                    where d.id = (a->>'detail_id')::uuid and d.report_id = p_report_id)
    on conflict (claim_id, detail_id) do update set answer = excluded.answer;
  end loop;

  update reports set status = 'claim_in_progress'
   where id = p_report_id and status in ('open','possible_match');

  insert into audit_log (actor_id, entity, entity_id, action, after_state)
  values (auth.uid(), 'claim', v_claim_id, 'submitted', jsonb_build_object('report_id', p_report_id));

  insert into notifications (profile_id, kind, payload)
  select v_report.profile_id, 'claim_submitted', jsonb_build_object('claim_id', v_claim_id)
   where v_report.profile_id is not null;

  return v_claim_id;
end;
$$;

-- Called by the FINDER. The finder grades each answer; the system never decides.
create or replace function grade_claim(
  p_claim_id uuid,
  p_grades   jsonb,             -- [{"detail_id":"...","correct":true}]
  p_approve  boolean,
  p_note     text default null
)
returns claim_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim  claims;
  v_report reports;
  g jsonb;
begin
  select * into v_claim from claims where id = p_claim_id for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;

  select * into v_report from reports where id = v_claim.report_id for update;
  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;
  if v_claim.status not in ('pending','verifying') then
    raise exception 'CLAIM_NOT_GRADABLE: %', v_claim.status;
  end if;

  for g in select * from jsonb_array_elements(p_grades) loop
    update claim_answers
       set graded_correct = (g->>'correct')::boolean
     where claim_id = p_claim_id and detail_id = (g->>'detail_id')::uuid;
  end loop;

  if p_approve then
    -- Race condition #1. If another claim was approved between the SELECT above
    -- and here, the partial unique index raises and the transaction rolls back.
    update claims set status = 'approved', updated_at = now() where id = p_claim_id;

    update claims set status = 'rejected', rejection_note = 'another_claim_approved', updated_at = now()
     where report_id = v_claim.report_id and id <> p_claim_id
       and status in ('pending','verifying');

    update reports set status = 'matched' where id = v_claim.report_id;

    insert into conversations (claim_id) values (p_claim_id)
      on conflict (claim_id) do nothing;

    insert into notifications (profile_id, kind, payload)
    values (v_claim.claimant_id, 'claim_approved', jsonb_build_object('claim_id', p_claim_id));
  else
    update claims set status = 'rejected', rejection_note = p_note, updated_at = now()
     where id = p_claim_id;

    -- if no live claims remain, the report goes back to being findable
    update reports set status = 'possible_match'
     where id = v_claim.report_id
       and status = 'claim_in_progress'
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

-- Direct UPDATE on `claims` is revoked from clients (see 0001), so withdrawal
-- needs its own RPC rather than a permissive RLS policy.
create or replace function withdraw_claim(p_claim_id uuid)
returns claim_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim claims;
begin
  select * into v_claim from claims where id = p_claim_id for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  if v_claim.claimant_id <> auth.uid() then raise exception 'NOT_CLAIMANT'; end if;
  if v_claim.status not in ('pending','verifying','approved') then
    raise exception 'CLAIM_NOT_WITHDRAWABLE: %', v_claim.status;
  end if;

  update claims set status = 'withdrawn', updated_at = now() where id = p_claim_id;

  -- An approved claim being withdrawn must release the report, or it is stuck
  -- in `matched` forever with nobody able to claim it.
  update reports set status = 'claim_in_progress'
   where id = v_claim.report_id and status = 'matched';

  update reports r set status = 'possible_match'
   where r.id = v_claim.report_id
     and r.status = 'claim_in_progress'
     and not exists (select 1 from claims c
                      where c.report_id = r.id and c.status in ('pending','verifying','approved'));

  update conversations set is_locked = true where claim_id = p_claim_id;

  insert into audit_log (actor_id, entity, entity_id, action, before_state, after_state)
  values (auth.uid(), 'claim', p_claim_id, 'withdrawn',
          jsonb_build_object('status', v_claim.status),
          jsonb_build_object('status', 'withdrawn'));

  return 'withdrawn';
end;
$$;

-- Race condition #2. Idempotent, order-independent, converges under concurrency.
create or replace function confirm_return(p_claim_id uuid)
returns report_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim  claims;
  v_report reports;
  v_is_finder boolean;
begin
  select * into v_claim from claims where id = p_claim_id for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  if v_claim.status <> 'approved' then raise exception 'CLAIM_NOT_APPROVED'; end if;

  select * into v_report from reports where id = v_claim.report_id for update;
  v_is_finder := (v_report.profile_id = auth.uid());

  if not v_is_finder and v_claim.claimant_id <> auth.uid() then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  if v_is_finder then
    update claims set finder_confirmed_at = now(), updated_at = now()
     where id = p_claim_id and finder_confirmed_at is null;
  else
    update claims set claimant_confirmed_at = now(), updated_at = now()
     where id = p_claim_id and claimant_confirmed_at is null;
  end if;

  select * into v_claim from claims where id = p_claim_id;

  if v_claim.finder_confirmed_at is not null
     and v_claim.claimant_confirmed_at is not null
     and v_report.status = 'matched' then

    update reports set status = 'returned' where id = v_report.id and status = 'matched';

    update conversations set is_locked = true where claim_id = p_claim_id;

    update profiles set returns_count = returns_count + 1
     where id in (v_report.profile_id, v_claim.claimant_id);

    -- P2 data has served its purpose; it should not outlive the return
    delete from private_verification_details where report_id = v_report.id;
    delete from claim_answers where claim_id = p_claim_id;
  end if;

  return (select status from reports where id = v_report.id);
end;
$$;

-- Idle claims must not block a report forever.
create or replace function expire_stale_claims()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with expired as (
    update claims set status = 'expired', updated_at = now()
     where status in ('pending','verifying')
       and updated_at < now() - interval '7 days'
    returning report_id
  )
  select count(*) into n from expired;

  update reports r set status = 'possible_match'
   where r.status = 'claim_in_progress'
     and not exists (select 1 from claims c
                      where c.report_id = r.id and c.status in ('pending','verifying','approved'));
  return n;
end;
$$;

-- select cron.schedule('wassalni-expire-claims', '0 3 * * *', 'select expire_stale_claims()');

-- ---------------------------------------------------------------------------
-- 4. Share card payload — P0 whitelist only.
-- ---------------------------------------------------------------------------
-- There is no code path from here to a name, an image, or a precise location.

create or replace function share_card_payload(p_report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'report_type', r.report_type,
    'category_ar', c.name_ar,
    'area_ar',     a.name_ar,
    'community_ar',cm.name_ar,
    'occurred_on', r.occurred_on,
    'status',      r.status
  )
    from reports r
    join categories c on c.id = r.category_id
    join communities cm on cm.id = r.community_id
    left join areas a on a.id = r.area_id
   where r.id = p_report_id
     and r.status <> 'removed'
     and not r.is_hidden;
$$;

commit;
