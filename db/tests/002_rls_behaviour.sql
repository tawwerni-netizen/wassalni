-- Wassalni — RLS behavioural tests (pgTAP).
--
-- Precondition: db/tests/fixtures/000_local_only_bootstrap.sql and every file
-- in db/migrations/ have already been applied to this database (same
-- precondition as 001_schema_invariants.sql).
--
-- 001 tests SCHEMA FACTS (does the grant exist, does the trigger exist). This
-- file tests BEHAVIOUR under a real, role-switched session: what a claimant
-- can actually SELECT, what a direct INSERT actually does. A structural
-- assertion can pass for the wrong reason (nothing was ever granted, so
-- nothing needed revoking); only running the query as that role proves the
-- boundary holds.
--
-- Role-switching pattern: `set local role` / `set local "request.jwt.claim.sub"`
-- are issued as their own top-level statements, never chained inside a
-- throws_ok/is_empty call. pgTAP's error-catching helpers wrap the tested SQL
-- in an internal savepoint; a role change made *inside* that savepoint would
-- be rolled back along with everything else the moment the tested statement
-- raises, leaving the next assertion running as the wrong role. Setting the
-- role beforehand, as a plain statement, avoids that entirely.

begin;
create extension if not exists pgtap;

select plan(7);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
-- Users are created via auth.users, not profiles directly, so the
-- handle_new_auth_user() trigger from 0008 fires and this suite also
-- incidentally proves that trigger works.

insert into auth.users (id, email) values (gen_random_uuid(), 'finder@test.local')
returning id as finder_id \gset

insert into auth.users (id, email) values (gen_random_uuid(), 'claimant@test.local')
returning id as claimant_id \gset

update profiles set display_name = 'صاحب البلاغ' where id = :'finder_id';
update profiles set display_name = 'مطالب' where id = :'claimant_id';

select id as country_id from communities where slug = 'eg' \gset

insert into communities (slug, name_ar, name_en, kind, parent_id, is_reportable)
select 'test-venue-002', 'مكان اختبار', 'Test Venue', 'campus', id, true
  from communities where slug = 'eg-cairo'
returning id as venue_id \gset

-- The finder posts a FOUND report with one private verification question.
set local role authenticated;
set local "request.jwt.claim.sub" = :'finder_id';

insert into reports (profile_id, report_type, community_id, category_id, title, description, occurred_on)
values (:'finder_id', 'found', :'venue_id', 'wallet', 'محفظة جلد لقيتها', 'لقيت محفظة جلد بنية جنب البوابة الرئيسية', current_date)
returning id as report_id \gset

insert into private_verification_details (report_id, question_ar, expected_answer)
values (:'report_id', 'فيها كام كارت شخصي؟', 'كارتين')
returning id as detail_id \gset

reset role;

-- The claimant submits a claim through the RPC, the only path clients have.
set local role authenticated;
set local "request.jwt.claim.sub" = :'claimant_id';

select submit_claim(
  :'report_id'::uuid,
  jsonb_build_array(jsonb_build_object('detail_id', :'detail_id', 'answer', 'كارت واحد'))
) as claim_id \gset

reset role;

-- ---------------------------------------------------------------------------
-- 1 & 2 — the guessing oracle stays closed even for the claimant's own claim
-- ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = :'claimant_id';

select is_empty(
  format('select 1 from private_verification_details where report_id = %L', :'report_id'),
  'a claimant cannot read the finder''s private verification questions'
);

-- claim_answers got a full table-level SELECT revoke in 0006 (not row-filtered
-- like private_verification_details above), so the query does not come back
-- empty — it is flatly denied. Stronger closure, different assertion helper.
select throws_like(
  format('select 1 from claim_answers where claim_id = %L', :'claim_id'),
  '%permission denied%',
  'a claimant cannot read graded_correct feedback on their own answers (the guessing oracle)'
);

reset role;

-- ---------------------------------------------------------------------------
-- 3 — a rejected claim cannot be retried by the claimant alone
-- ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = :'finder_id';

select grade_claim(:'claim_id'::uuid, '[]'::jsonb, false, 'مش هي دي');

reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = :'claimant_id';

select throws_like(
  format('select submit_claim(%L::uuid, %L::jsonb)', :'report_id', '[]'),
  '%CLAIM_REJECTED_CONTACT_FINDER%',
  'a rejected claimant cannot resubmit without the finder explicitly reopening the claim'
);

-- ---------------------------------------------------------------------------
-- 4 — no direct INSERT into claims; submit_claim is the only path
-- ---------------------------------------------------------------------------

select throws_like(
  format('insert into claims (report_id, claimant_id, status) values (%L, %L, ''pending'')',
         :'report_id', :'claimant_id'),
  '%permission denied%',
  'a client cannot insert a claims row directly, bypassing submit_claim''s checks and rate limit'
);

reset role;

-- ---------------------------------------------------------------------------
-- 5 — is_hidden cannot be written by the report owner, not even to false
-- ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = :'finder_id';

select throws_like(
  format('update reports set is_hidden = false where id = %L', :'report_id'),
  '%permission denied%',
  'the report owner cannot revert their own moderation; is_hidden is staff-RPC-only'
);

-- ---------------------------------------------------------------------------
-- 6 — profile_id is not selectable, so a person's movements cannot be
--     reconstructed by filtering reports on it. This is also, mechanically,
--     what makes PostgREST's `?profile_id=eq.<id>` filter impossible: the
--     filter compiles to a WHERE clause referencing the column, and it is
--     gated by the exact same column-level SELECT grant tested here.
-- ---------------------------------------------------------------------------

select throws_like(
  format('select profile_id from reports where id = %L', :'report_id'),
  '%permission denied%',
  'profile_id cannot be read or filtered on, closing the movement-reconstruction path'
);

reset role;

-- ---------------------------------------------------------------------------
-- 7 — browsing above district scope requires an actual search term
-- ---------------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claim.sub" = :'claimant_id';

select throws_like(
  format('select * from search_reports(p_scope_id => %L)', :'country_id'),
  '%QUERY_REQUIRED_FOR_WIDE_SCOPE%',
  'browsing all of Egypt without a query is refused, closing the nationwide enumeration surface'
);

reset role;

select * from finish();
rollback;
