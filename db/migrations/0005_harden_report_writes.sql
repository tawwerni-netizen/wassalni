-- Wassalni / وصلني — close two write holes on `reports`.
-- Depends on 0001..0004.
--
-- ROOT CAUSE (applies to both holes)
-- An RLS policy's WITH CHECK cannot see the OLD row, so it can express "you own
-- this row" but never "you may change this column and not that one".
-- `reports_update_own` therefore granted the owner UPDATE on *every* column.
-- Two consequences, both exploitable:
--
--   1. moderation_autohide() sets reports.is_hidden = true after three distinct
--      users flag a report. The owner simply set it back to false. The whole
--      moderation control was revertible by the person being moderated.
--
--   2. reports_governorate_trg fired only `before insert or update OF
--      community_id`. A direct `UPDATE reports SET governorate_id = <busiest>`
--      never fired it, and since generate_match_candidates() bounds candidates
--      by governorate_id, one statement injected a report into any
--      governorate's match suggestions nationwide.
--
-- FIX
-- Column privileges, which RLS cannot express, plus SECURITY DEFINER RPCs for
-- the state changes that must be earned rather than asserted. This is the first
-- instalment of the wider "writes go through RPCs, tables are read-mostly to
-- clients" decision.

begin;

-- ---------------------------------------------------------------------------
-- 1. Owners may edit content. Nothing else.
-- ---------------------------------------------------------------------------
-- Column-level REVOKE cannot subtract from a table-level grant, so the table
-- grant is dropped and the allowed columns are granted back explicitly.
-- RLS still applies on top: reports_update_own restricts *which rows*, these
-- grants restrict *which columns*.

revoke update on reports from authenticated;

grant update (
  title,
  description,
  brand,
  color_id,
  category_id,
  area_id,
  occurred_on,
  occurred_time_bucket
) on reports to authenticated;

-- Deliberately NOT granted: status, is_hidden, hidden_reason, profile_id,
-- community_id, governorate_id, created_at, updated_at.

-- ---------------------------------------------------------------------------
-- 2. governorate_id is always derived, never accepted from a client.
-- ---------------------------------------------------------------------------

drop trigger if exists reports_governorate_trg on reports;

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

  -- Recomputed on every write, so a supplied value is always overwritten
  -- rather than trusted.
  --
  -- `= any((select ...))` is a trap: the extra parens make Postgres parse this
  -- as the SQL-standard "ANY (subquery)" form — compare against each ROW the
  -- subquery returns — not "ANY (array)". Our subquery returns one row holding
  -- one uuid[] value, so that form tried to evaluate `uuid = uuid[]` and
  -- failed. Selecting the array into a plain variable first is unambiguous.
  select c.id into new.governorate_id
    from communities c
   where c.id = any(v_ancestor_ids)
     and c.kind = 'governorate';

  return new;
end;
$$;

create trigger reports_governorate_trg
  before insert or update on reports
  for each row execute function reports_set_governorate();

-- ---------------------------------------------------------------------------
-- 3. Freeze the identifying fields once a report leaves `open`.
-- ---------------------------------------------------------------------------
-- Otherwise: post something innocuous, collect claims, then rewrite it into
-- something else. Bait-and-switch. Wording stays editable — people fix typos
-- and add detail, and blocking that would push them to delete and repost.

create or replace function reports_freeze_after_open()
returns trigger language plpgsql as $$
begin
  if old.status <> 'open' and (
       new.category_id  is distinct from old.category_id
    or new.area_id      is distinct from old.area_id
    or new.report_type  is distinct from old.report_type
    or new.community_id is distinct from old.community_id
  ) then
    raise exception 'REPORT_LOCKED_AFTER_OPEN'
      using hint = 'مش هينفع تغيّر نوع البلاغ أو مكانه بعد ما حد يبدأ يتواصل.';
  end if;
  return new;
end;
$$;

create trigger reports_freeze_trg
  before update on reports
  for each row execute function reports_freeze_after_open();

-- ---------------------------------------------------------------------------
-- 4. RPCs for the writes the column grants now block.
-- ---------------------------------------------------------------------------

-- An owner giving up on a report, or one that resolved off-platform.
create or replace function close_my_report(p_report_id uuid)
returns report_status
language plpgsql security definer set search_path = public as $$
declare v_report reports;
begin
  select * into v_report from reports where id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;
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

-- Staff hide/unhide. This is the path that the owner could previously take.
create or replace function moderate_report_visibility(
  p_report_id uuid,
  p_hidden    boolean,
  p_reason    text default null
)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not current_is_staff() then raise exception 'REQUIRES_STAFF'; end if;

  update reports
     set is_hidden = p_hidden,
         hidden_reason = case when p_hidden then coalesce(p_reason, 'moderator') else null end
   where id = p_report_id;

  insert into audit_log (actor_id, entity, entity_id, action, after_state)
  values (auth.uid(), 'report', p_report_id,
          case when p_hidden then 'hidden' else 'unhidden' end,
          jsonb_build_object('reason', p_reason));

  -- The author is told, so an auto-hide from three coordinated flags is not a
  -- silent disappearance with no way to appeal.
  insert into notifications (profile_id, kind, payload)
  select r.profile_id,
         case when p_hidden then 'report_hidden' else 'report_restored' end,
         jsonb_build_object('report_id', p_report_id)
    from reports r where r.id = p_report_id and r.profile_id is not null;

  return p_hidden;
end;
$$;

create or replace function moderate_report_remove(p_report_id uuid, p_reason text)
returns report_status
language plpgsql security definer set search_path = public as $$
begin
  if not current_is_staff() then raise exception 'REQUIRES_STAFF'; end if;

  update reports set status = 'removed', hidden_reason = p_reason where id = p_report_id;

  insert into notifications (profile_id, kind, payload)
  select r.profile_id, 'report_removed', jsonb_build_object('report_id', p_report_id)
    from reports r where r.id = p_report_id and r.profile_id is not null;

  return 'removed';
end;
$$;

commit;
