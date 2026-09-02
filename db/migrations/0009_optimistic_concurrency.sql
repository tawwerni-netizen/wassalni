-- Wassalni / وصلني — optimistic concurrency on every mutating RPC.
-- Depends on 0001..0008.
--
-- ARCHITECTURE.md §7 point 3 describes this: "a report is matched while a
-- stale client is still editing it" — the client sends the `updated_at` it
-- last saw, and the server rejects the mutation if the row has moved on.
--
-- SCOPED DECISION, flagged rather than silently made: on a mismatch this
-- raises a distinct `STALE_STATE` exception rather than returning the current
-- row alongside a soft failure. A raised exception aborts the transaction, so
-- returning "current state" in the same round trip would require every one of
-- these RPCs to change its return type from a scalar (claim_status,
-- report_status, uuid) to a composite/jsonb envelope. No client exists yet to
-- consume that contract — the repositories land in M3/M6 — so widening the
-- contract now would be speculative. `STALE_STATE` is a distinct, catchable
-- signal the client can use to trigger "refetch and retry" instead of showing
-- a raw error; the refetch is a second cheap RPC call, not a redesign. If a
-- future screen needs the row back in the same round trip, that is a reason to
-- revisit this, not a reason to guess at the shape now.
--
-- `p_expected_updated_at` defaults to null and is optional everywhere: an
-- omitted check does not weaken anything else these RPCs already enforce (the
-- `for update` locks and the partial unique index remain the actual
-- correctness guarantees for the race conditions in ARCHITECTURE §7 points 1
-- and 2 — this is additive, for the "stale view" case specifically).

begin;

-- CREATE OR REPLACE cannot add a parameter and still replace the old function
-- — a different parameter LIST is a different overload to Postgres, not a
-- replacement, and the old and new versions then become ambiguous for any
-- call that only supplies the original arguments (exactly the shape every
-- existing call site uses, since nothing has been updated to pass
-- p_expected_updated_at yet). Caught by running 002_rls_behaviour.sql:
-- "function submit_claim(uuid, jsonb) is not unique". Every function below
-- needs its previous signature dropped first, for the same reason.
drop function if exists submit_claim(uuid, jsonb);

create or replace function submit_claim(
  p_report_id uuid,
  p_answers   jsonb,
  p_expected_updated_at timestamptz default null
)
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

  if p_expected_updated_at is not null and v_report.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: report % changed since it was last viewed', p_report_id
      using hint = 'البلاغ اتغيّر — حدّث الصفحة وحاول تاني.';
  end if;

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

drop function if exists grade_claim(uuid, jsonb, boolean, text);

create or replace function grade_claim(
  p_claim_id uuid,
  p_grades jsonb,
  p_approve boolean,
  p_note text default null,
  p_expected_updated_at timestamptz default null
)
returns claim_status
language plpgsql security definer set search_path = public as $$
declare v_claim claims; v_report reports; g jsonb;
begin
  select r.* into v_report from reports r
    join claims c on c.report_id = r.id
   where c.id = p_claim_id for update of r;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;

  select * into v_claim from claims where id = p_claim_id for update;

  if p_expected_updated_at is not null and v_claim.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: claim % changed since it was last viewed', p_claim_id
      using hint = 'الطلب اتغيّر — حدّث الصفحة وحاول تاني.';
  end if;

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

drop function if exists confirm_return(uuid);

create or replace function confirm_return(
  p_claim_id uuid,
  p_expected_updated_at timestamptz default null
)
returns report_status
language plpgsql security definer set search_path = public as $$
declare
  v_claim  claims;
  v_report reports;
  v_is_finder boolean;
begin
  select * into v_claim from claims where id = p_claim_id for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_claim.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: claim % changed since it was last viewed', p_claim_id
      using hint = 'الحالة اتغيّرت — حدّث الصفحة وحاول تاني.';
  end if;

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

    delete from private_verification_details where report_id = v_report.id;
    delete from claim_answers where claim_id = p_claim_id;
  end if;

  return (select status from reports where id = v_report.id);
end;
$$;

drop function if exists withdraw_claim(uuid);

create or replace function withdraw_claim(
  p_claim_id uuid,
  p_expected_updated_at timestamptz default null
)
returns claim_status
language plpgsql security definer set search_path = public as $$
declare
  v_claim claims;
begin
  select * into v_claim from claims where id = p_claim_id for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_claim.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: claim % changed since it was last viewed', p_claim_id
      using hint = 'الحالة اتغيّرت — حدّث الصفحة وحاول تاني.';
  end if;

  if v_claim.claimant_id <> auth.uid() then raise exception 'NOT_CLAIMANT'; end if;
  if v_claim.status not in ('pending','verifying','approved') then
    raise exception 'CLAIM_NOT_WITHDRAWABLE: %', v_claim.status;
  end if;

  update claims set status = 'withdrawn', updated_at = now() where id = p_claim_id;

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

drop function if exists reopen_claim(uuid);

create or replace function reopen_claim(
  p_claim_id uuid,
  p_expected_updated_at timestamptz default null
)
returns claim_status
language plpgsql security definer set search_path = public as $$
declare v_claim claims; v_report reports;
begin
  select * into v_claim from claims where id = p_claim_id;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_claim.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: claim % changed since it was last viewed', p_claim_id
      using hint = 'الحالة اتغيّرت — حدّث الصفحة وحاول تاني.';
  end if;

  select * into v_report from reports where id = v_claim.report_id for update;
  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;
  if v_claim.attempt_count >= 2 then raise exception 'CLAIM_ATTEMPTS_EXHAUSTED'; end if;

  update claims set status = 'verifying', rejection_note = null, updated_at = now()
   where id = p_claim_id;
  return 'verifying';
end;
$$;

drop function if exists close_my_report(uuid);

create or replace function close_my_report(
  p_report_id uuid,
  p_expected_updated_at timestamptz default null
)
returns report_status
language plpgsql security definer set search_path = public as $$
declare v_report reports;
begin
  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_report.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: report % changed since it was last viewed', p_report_id
      using hint = 'البلاغ اتغيّر — حدّث الصفحة وحاول تاني.';
  end if;

  if v_report.profile_id <> auth.uid() then raise exception 'NOT_REPORT_OWNER'; end if;

  if exists (select 1 from claims c
              where c.report_id = p_report_id and c.status = 'approved') then
    raise exception 'CANNOT_CLOSE_WITH_APPROVED_CLAIM'
      using hint = 'في حد بيستلم منك دلوقتي — أكّد التسليم أو الغِ الطلب الأول.';
  end if;

  update reports set status = 'closed' where id = p_report_id;
  return 'closed';
end;
$$;

drop function if exists moderate_report_visibility(uuid, boolean, text);

create or replace function moderate_report_visibility(
  p_report_id uuid,
  p_hidden    boolean,
  p_reason    text default null,
  p_expected_updated_at timestamptz default null
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_report reports;
begin
  if not current_is_staff() then raise exception 'REQUIRES_STAFF'; end if;

  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_report.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: report % changed since it was last viewed', p_report_id
      using hint = 'البلاغ اتغيّر — حدّث الصفحة وحاول تاني.';
  end if;

  update reports
     set is_hidden = p_hidden,
         hidden_reason = case when p_hidden then coalesce(p_reason, 'moderator') else null end
   where id = p_report_id;

  insert into audit_log (actor_id, entity, entity_id, action, after_state)
  values (auth.uid(), 'report', p_report_id,
          case when p_hidden then 'hidden' else 'unhidden' end,
          jsonb_build_object('reason', p_reason));

  insert into notifications (profile_id, kind, payload)
  select r.profile_id,
         case when p_hidden then 'report_hidden' else 'report_restored' end,
         jsonb_build_object('report_id', p_report_id)
    from reports r where r.id = p_report_id and r.profile_id is not null;

  return p_hidden;
end;
$$;

drop function if exists moderate_report_remove(uuid, text);

create or replace function moderate_report_remove(
  p_report_id uuid,
  p_reason text,
  p_expected_updated_at timestamptz default null
)
returns report_status
language plpgsql security definer set search_path = public as $$
declare v_report reports;
begin
  if not current_is_staff() then raise exception 'REQUIRES_STAFF'; end if;

  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;

  if p_expected_updated_at is not null and v_report.updated_at <> p_expected_updated_at then
    raise exception 'STALE_STATE: report % changed since it was last viewed', p_report_id
      using hint = 'البلاغ اتغيّر — حدّث الصفحة وحاول تاني.';
  end if;

  update reports set status = 'removed', hidden_reason = p_reason where id = p_report_id;

  insert into notifications (profile_id, kind, payload)
  select r.profile_id, 'report_removed', jsonb_build_object('report_id', p_report_id)
    from reports r where r.id = p_report_id and r.profile_id is not null;

  return 'removed';
end;
$$;

commit;
