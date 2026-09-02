-- Wassalni / وصلني — fix cross-table ownership checks broken by the
-- profile_id column-select revoke in 0006.
-- Depends on 0001..0010.
--
-- CAUGHT BY RUNNING db/tests/002_rls_behaviour.sql AGAINST A REAL DATABASE.
-- Every fixture insert past the report itself failed with "permission denied
-- for table reports" — inserting a private_verification_details row, which is
-- gated by pvd_owner_only:
--
--   exists (select 1 from reports r where r.id = ... and r.profile_id = auth.uid())
--
-- That EXISTS is a genuine, separate SELECT against `reports`, executed with
-- the privileges of whichever role is running the outer statement. 0006
-- revoked `authenticated`'s SELECT on reports.profile_id specifically to close
-- the movement-reconstruction hole — and that revoke applies here too, because
-- this is a real cross-table query, not the row already being operated on.
--
-- It is NOT a general problem, and the fix is NOT to restore the grant. Tested
-- directly: reports_update_own's own bare `profile_id = auth.uid()`, evaluated
-- as part of THAT table's own policy on its own row, works fine with no
-- column privilege at all — Postgres treats a table's row under its own
-- policy the way a trigger treats NEW/OLD, not as an ordinary column read. The
-- break is specific to policies on OTHER tables reaching into `reports` via a
-- subquery, which is an ordinary SELECT and genuinely needs privilege for the
-- calling role.
--
-- Fixed the same way current_is_staff()/current_community_id() already solve
-- the identical shape of problem for `profiles`: a SECURITY DEFINER helper.
-- Being SECURITY DEFINER, it runs as its owner, who can read profile_id
-- regardless of what `authenticated` is granted — closing the enumeration
-- hole and un-breaking every cross-table ownership check at the same time.

begin;

create or replace function current_owns_report(p_report_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from reports where id = p_report_id and profile_id = auth.uid());
$$;

-- report_images -------------------------------------------------------------

drop policy report_images_read on report_images;
create policy report_images_read on report_images
  for select to authenticated
  using (
    is_public
    or current_owns_report(report_id)
    or current_is_staff()
    or exists (select 1 from claims c
                where c.report_id = report_images.report_id and c.claimant_id = auth.uid()
                  and c.status = 'approved')
  );

drop policy report_images_write on report_images;
create policy report_images_write on report_images
  for all to authenticated
  using (current_owns_report(report_id))
  with check (current_owns_report(report_id));

-- report_private_details (P1) ------------------------------------------------

drop policy report_private_details_read on report_private_details;
create policy report_private_details_read on report_private_details
  for select to authenticated
  using (
    current_is_staff()
    or current_owns_report(report_id)
    or exists (select 1 from claims c
                where c.report_id = report_private_details.report_id
                  and c.claimant_id = auth.uid() and c.status = 'approved')
  );

drop policy report_private_details_write on report_private_details;
create policy report_private_details_write on report_private_details
  for all to authenticated
  using (current_owns_report(report_id))
  with check (current_owns_report(report_id));

-- private_verification_details (P2) ------------------------------------------

drop policy pvd_owner_only on private_verification_details;
create policy pvd_owner_only on private_verification_details
  for all to authenticated
  using (current_owns_report(report_id) or current_role_is('admin'))
  with check (current_owns_report(report_id));

-- claims ----------------------------------------------------------------------

drop policy claims_read on claims;
create policy claims_read on claims
  for select to authenticated
  using (
    claimant_id = auth.uid()
    or current_is_staff()
    or current_owns_report(report_id)
  );

drop policy claims_insert on claims;
create policy claims_insert on claims
  for insert to authenticated
  with check (
    claimant_id = auth.uid()
    and current_is_active()
    and not current_owns_report(report_id)   -- cannot claim your own report
    and exists (
      select 1 from reports r
       where r.id = claims.report_id
         and r.community_id = current_community_id()
         and r.status in ('open','possible_match','claim_in_progress')
         and not r.is_hidden
    )
  );

-- match_candidates --------------------------------------------------------------

drop policy match_candidates_read on match_candidates;
create policy match_candidates_read on match_candidates
  for select to authenticated
  using (current_owns_report(report_id));

drop policy match_candidates_dismiss on match_candidates;
create policy match_candidates_dismiss on match_candidates
  for update to authenticated
  using (current_owns_report(report_id));

-- conversations and messages ------------------------------------------------
-- The join to `reports` in these three existed only to read profile_id; with
-- the helper it is no longer needed at all.

drop policy conversations_read on conversations;
create policy conversations_read on conversations
  for select to authenticated
  using (
    current_is_staff()
    or exists (
      select 1 from claims c
       where c.id = conversations.claim_id
         and (c.claimant_id = auth.uid() or current_owns_report(c.report_id))
    )
  );

drop policy messages_read on messages;
create policy messages_read on messages
  for select to authenticated
  using (
    current_is_staff()
    or exists (
      select 1 from conversations cv join claims c on c.id = cv.claim_id
       where cv.id = messages.conversation_id
         and (c.claimant_id = auth.uid() or current_owns_report(c.report_id))
    )
  );

drop policy messages_insert on messages;
create policy messages_insert on messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and current_is_active()
    and exists (
      select 1 from conversations cv join claims c on c.id = cv.claim_id
       where cv.id = messages.conversation_id
         and c.status = 'approved'
         and (c.claimant_id = auth.uid() or current_owns_report(c.report_id))
    )
  );

commit;
