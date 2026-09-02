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

select plan(25);

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

select col_is_null('claims', 'finder_confirmed_at', 'finder confirmation starts null');
select col_is_null('claims', 'claimant_confirmed_at', 'claimant confirmation starts null');

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

select * from finish();
rollback;
