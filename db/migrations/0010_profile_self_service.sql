-- Wassalni / وصلني — self-service profile reads and account deletion.
-- Depends on 0001..0009.
--
-- ISSUE FOUND WHILE IMPLEMENTING M1
-- 0006 narrowed the column grant on `profiles` to (id, display_name,
-- returns_count, community_id) for `authenticated`, closing a real
-- enumeration hole. But column grants are not row-aware: the same narrowing
-- also hid `is_suspended` and `role` from a user reading THEIR OWN row, which
-- the suspended-account gate needs. Rather than widen the table-wide grant
-- (safe today only because profiles_self_read's row policy happens to hide a
-- suspended stranger's row — correct, but a second policy change away from
-- being wrong), this follows the same pattern already used for v_reports: a
-- narrow, self-only definer view.

begin;

create or replace view v_my_profile as
  select id, display_name, community_id, role, is_suspended, suspended_reason,
         returns_count, created_at, updated_at
    from profiles
   where id = auth.uid();

grant select on v_my_profile to authenticated;

-- ---------------------------------------------------------------------------
-- Account deletion, data half.
-- ---------------------------------------------------------------------------
-- Deleting the auth.users row itself is deliberately NOT done here. Supabase's
-- own guidance is to delete a user through the Admin API (service_role), not
-- by removing auth.users directly from SQL — the auth schema also tracks
-- identities, sessions and refresh tokens that a raw DELETE would not
-- consistently unwind. That requires a service-role Edge Function, which
-- cannot be authored or deployed without a live Supabase project; see
-- ARCHITECTURE.md and the M1 task notes.
--
-- What CAN be done entirely within our own schema, and is done here: apply
-- privacy hard rule 7 (ARCHITECTURE §4) — reports are anonymised rather than
-- deleted, so a completed return's history stays coherent, and P2 data is hard
-- deleted immediately, because it has no reason to survive the account.

create or replace function anonymize_my_data()
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_my_report_ids uuid[];
begin
  -- Capture ownership BEFORE clearing it. audit_log only records status
  -- TRANSITIONS, not creation, so a report that never changed status would be
  -- invisible to any attempt to reconstruct "which reports were mine" after
  -- the fact — this must be the first thing the function does.
  select coalesce(array_agg(id), array[]::uuid[]) into v_my_report_ids
    from reports where profile_id = auth.uid();

  -- P2 has no reason to outlive the account it verifies ownership for.
  -- claim_answers on these details cascade-deletes with them (0001 FK).
  delete from private_verification_details where report_id = any(v_my_report_ids);

  -- Detach authorship. The profile row itself is not touched here — actual
  -- account removal is the Edge Function's job — so this is an explicit clear,
  -- not a cascade from deleting profiles.
  update reports set profile_id = null where id = any(v_my_report_ids);

  -- Claims made as a claimant elsewhere: withdraw any still-live ones so those
  -- reports are not left stuck waiting on someone who is leaving, and drop the
  -- answer text submitted to other people's verification questions.
  update claims set status = 'withdrawn', updated_at = now()
   where claimant_id = auth.uid() and status in ('pending','verifying');

  delete from claim_answers
   where claim_id in (select id from claims where claimant_id = auth.uid());

  delete from device_tokens where profile_id = auth.uid();
  delete from notifications where profile_id = auth.uid();

  insert into audit_log (actor_id, entity, entity_id, action)
  values (auth.uid(), 'profile', auth.uid(), 'self_anonymized');
end;
$$;

commit;
