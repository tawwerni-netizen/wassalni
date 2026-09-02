-- Wassalni — schema invariants (pgTAP).
--
-- Run:  psql "$DATABASE_URL" -f db/tests/001_schema_invariants.sql
--
-- This file asserts the things that must be true of the schema itself. The
-- policy-behaviour tests — "a claimant gets zero rows from
-- private_verification_details" — need real auth contexts and live in
-- 002_rls_behaviour.sql, which lands with M3/M6.

begin;
create extension if not exists pgtap;

select plan(44);

-- ---------------------------------------------------------------------------
-- 1. RLS is on everywhere. Default deny is the whole security model; a single
--    table with RLS off is a full data leak, so this is asserted as a set
--    difference rather than table by table (a new table added without RLS must
--    fail this test, and a per-table list would silently miss it).
-- ---------------------------------------------------------------------------

select is_empty(
  $$ select c.relname from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity $$,
  'every public table has row level security enabled'
);

-- ---------------------------------------------------------------------------
-- 2. The privacy hard rules, as schema facts.
-- ---------------------------------------------------------------------------

select is_empty(
  $$ select table_name || '.' || column_name
       from information_schema.columns
      where table_schema = 'public'
        and (column_name ~* '(phone|mobile|tel)'
             or column_name ~* '(national_id|passport|iban|card_number|ssn)'
             or column_name ~* '(street|address|postcode|zip)') $$,
  'no column stores a phone number, government ID, or postal address'
);

-- RLS is row-level: any column on a readable row is readable. So the P1 hint
-- must not be a column on the publicly-readable reports table.
select hasnt_column('reports', 'location_hint', 'the P1 location hint is not a column on reports');

select has_table('report_private_details', 'P1 data lives in its own table');
select has_table('private_verification_details', 'P2 data lives in its own table');

-- ---------------------------------------------------------------------------
-- 3. Race-condition guards exist as constraints, not as application logic.
-- ---------------------------------------------------------------------------

select has_index('public', 'claims', 'claims_one_approved_per_report',
  'a partial unique index enforces at most one approved claim per report');

select is(
  (select indexdef from pg_indexes
    where indexname = 'claims_one_approved_per_report') ~ 'WHERE .*approved',
  true,
  'the approved-claim index is partial, scoped to status = approved'
);

-- col_is_null asserts the column is nullable with no NOT NULL constraint.
-- Combined with having no explicit DEFAULT (true here), a fresh row leaves it
-- NULL until confirm_return() sets it — this is a schema-level proxy for that,
-- not a fixture-and-check of an actual inserted row.
select col_is_null('claims', 'finder_confirmed_at',
  'finder confirmation is nullable with no default, so it starts unset');
select col_is_null('claims', 'claimant_confirmed_at',
  'claimant confirmation is nullable with no default, so it starts unset');

-- ---------------------------------------------------------------------------
-- 4. State machine.
-- ---------------------------------------------------------------------------

select has_table('report_status_transitions', 'valid transitions are data, not code');

select isnt_empty(
  $$ select 1 from report_status_transitions where staff_only $$,
  'some transitions are staff-only'
);

select is_empty(
  $$ select 1 from report_status_transitions
      where from_status = 'returned' and to_status = 'open' $$,
  'a returned report cannot be reopened to open'
);

select is_empty(
  $$ select 1 from report_status_transitions
      where from_status = 'open' and to_status = 'matched' $$,
  'a report cannot jump straight from open to matched'
);

-- ---------------------------------------------------------------------------
-- 5. Arabic normalisation. This is the contract with ArabicText.kt on the
--    client; if the two drift, users see matches the server cannot find.
-- ---------------------------------------------------------------------------

select is(wassalni_normalize_ar('محفظة'), wassalni_normalize_ar('محفظه'),
  'taa marbuta folds to haa');

select is(wassalni_normalize_ar('أحمد'), wassalni_normalize_ar('احمد'),
  'hamza on alef folds to bare alef');

select is(wassalni_normalize_ar('مصطفى'), wassalni_normalize_ar('مصطفي'),
  'alef maqsura folds to yaa');

select is(wassalni_normalize_ar('مِفْتَاح'), wassalni_normalize_ar('مفتاح'),
  'tashkeel is stripped');

select is(wassalni_normalize_ar('مفـــتاح'), wassalni_normalize_ar('مفتاح'),
  'tatweel is stripped');

select is(wassalni_normalize_ar('iPhone ١٣'), 'iphone 13',
  'arabic-indic digits fold to latin and text lowercases');

select is(wassalni_normalize_ar('  محفظة،  جلد   بني!! '), 'محفظه جلد بني',
  'punctuation and whitespace collapse');

-- ---------------------------------------------------------------------------
-- 6. The sensitive-number guard. False positives are the expensive failure:
--    a guard that blocks ordinary descriptions trains users to write nothing.
-- ---------------------------------------------------------------------------

select ok(wassalni_contains_sensitive_number('29801011234567'),
  'a 14-digit national ID is caught');

select ok(wassalni_contains_sensitive_number('4111 1111 1111 1111'),
  'a spaced card number is caught');

select ok(not wassalni_contains_sensitive_number('موديل 2024'),
  'a year is not flagged');

select ok(not wassalni_contains_sensitive_number('حوالي 1500 جنيه'),
  'a price is not flagged');

select ok(not wassalni_contains_sensitive_number('مبنى 5 قاعة 302'),
  'a building and room number is not flagged');

-- ---------------------------------------------------------------------------
-- 7. Write hardening (0005). RLS cannot express "this column but not that one",
--    so these are column privileges — and they are exactly what stopped a
--    report owner from reverting their own moderation.
-- ---------------------------------------------------------------------------

select ok(not has_column_privilege('authenticated', 'reports', 'is_hidden', 'UPDATE'),
  'an owner cannot un-hide their own moderated report');

select ok(not has_column_privilege('authenticated', 'reports', 'governorate_id', 'UPDATE'),
  'governorate cannot be spoofed to inject into another region''s match pool');

select ok(not has_column_privilege('authenticated', 'reports', 'status', 'UPDATE'),
  'status is earned through RPCs and triggers, never asserted by a client');

select ok(not has_column_privilege('authenticated', 'reports', 'profile_id', 'UPDATE'),
  'authorship cannot be reassigned');

select ok(has_column_privilege('authenticated', 'reports', 'title', 'UPDATE'),
  'owners can still fix their own wording');

-- The governorate trigger must not be column-scoped: an UPDATE that touches
-- only governorate_id has to fire it too.
select is_empty(
  $$ select 1 from pg_trigger
      where tgname = 'reports_governorate_trg' and tgattr <> ''::int2vector $$,
  'the governorate trigger fires on any update, not only on community_id'
);

select has_trigger('reports', 'reports_freeze_trg',
  'identifying fields freeze once a report leaves open');

-- ---------------------------------------------------------------------------
-- 8. The oracle, enumeration and image-leak fixes (0006).
-- ---------------------------------------------------------------------------

select ok(not has_table_privilege('authenticated', 'claim_answers', 'SELECT'),
  'a claimant cannot read per-question grading feedback (the guessing oracle)');

select ok(not has_table_privilege('authenticated', 'claim_answers', 'UPDATE'),
  'a claimant cannot edit an answer after seeing it graded');

select ok(not has_table_privilege('authenticated', 'claims', 'UPDATE'),
  'claim state changes go through RPCs, never a direct write');

select has_column('claims', 'attempt_count', 'claim attempts are counted and capped');

-- Read one report, take the author id, filter every report by it: a dated,
-- located movement history for a named person.
select ok(not has_column_privilege('authenticated', 'reports', 'profile_id', 'SELECT'),
  'authorship is not joinable, so a person''s movements cannot be reconstructed');

select has_view('v_reports', 'clients read reports through a view that exposes ownership as a boolean');

-- Images
select has_trigger('report_images', 'report_images_privacy_trg',
  'FOUND and document images default to private');
select has_trigger('report_images', 'report_images_document_guard_trg',
  'document images can never be made public');
select has_trigger('report_images', 'report_images_cap_trg',
  'the three-image cap is enforced server-side, not just in the client');

-- Rate limits that were documented but never wired up
select has_trigger('reports', 'reports_rate_limit_trg', 'report creation is rate limited');
select has_trigger('messages', 'messages_rate_limit_trg', 'messaging is rate limited');
select has_trigger('moderation_reports', 'moderation_rate_limit_trg', 'abuse reporting is rate limited');

select * from finish();
rollback;
