-- LOCAL DEV ONLY — never applied in CI or to Supabase.
--
-- This machine has no C toolchain matching the MSVC-built PostgreSQL 17
-- installer (no gcc/make), so the real pgTAP extension cannot be built from
-- source here. CI installs the genuine `postgresql-15-pgtap` package on
-- Ubuntu via apt and runs the real thing.
--
-- This file provides just enough of pgTAP's public function surface — the
-- ~14 functions 001_schema_invariants.sql and 002_rls_behaviour.sql actually
-- call — so those two files can be run VERBATIM against a local Postgres,
-- proving the committed SQL and its own tests are internally consistent
-- rather than trusting them by inspection. To use: run this file instead of
-- `create extension pgtap`, i.e. strip that one line from the test files
-- before piping them to psql (see db/tests/fixtures/run_local.sh).
--
-- Deliberately NOT feature-complete: no TAP-protocol output, no diagnostics
-- formatting, no bail-out. Enough to get a pass/fail per assertion.

-- plan/ok/finish are SECURITY DEFINER so the pass/fail bookkeeping table stays
-- writable regardless of which role a given assertion runs under — 002 spends
-- most of its time as `authenticated`, and that role has no reason to hold
-- privileges on this harness's own scratch state. This is what pgTAP itself
-- does for the same reason. The test PAYLOAD (is_empty/throws_like/etc.) must
-- NOT be security definer — it has to run as whichever role the test just set,
-- since that is the entire point of a role-switched RLS test.
create or replace function plan(p_n int) returns void language plpgsql security definer as $$
begin
  drop table if exists pg_temp._tap_state;
  create temp table _tap_state (n int, passed int, failed int);
  insert into _tap_state values (p_n, 0, 0);
  raise notice '1..%', p_n;
end;
$$;

create or replace function ok(p_cond boolean, p_desc text default '') returns text language plpgsql security definer as $$
declare v_num int;
begin
  update _tap_state
     set passed = passed + (case when p_cond then 1 else 0 end),
         failed = failed + (case when p_cond then 0 else 1 end);
  select passed + failed into v_num from _tap_state;
  if coalesce(p_cond, false) then
    raise notice 'ok % - %', v_num, p_desc;
  else
    raise warning 'not ok % - %', v_num, p_desc;
  end if;
  return '';
end;
$$;

create or replace function is(p_got anyelement, p_expected anyelement, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(p_got is not distinct from p_expected,
    p_desc || case when p_got is distinct from p_expected
                    then format(' [got: %s, expected: %s]', p_got, p_expected)
                    else '' end);
end;
$$;

create or replace function is_empty(p_sql text, p_desc text default '') returns text language plpgsql as $$
declare v_cnt int;
begin
  execute 'select count(*) from (' || p_sql || ') _s' into v_cnt;
  return ok(v_cnt = 0, p_desc);
end;
$$;

create or replace function isnt_empty(p_sql text, p_desc text default '') returns text language plpgsql as $$
declare v_cnt int;
begin
  execute 'select count(*) from (' || p_sql || ') _s' into v_cnt;
  return ok(v_cnt > 0, p_desc);
end;
$$;

create or replace function has_table(p_table text, p_desc text default '') returns text language plpgsql as $$
begin
  return ok(exists(select 1 from information_schema.tables
                     where table_schema = 'public' and table_name = p_table), p_desc);
end;
$$;

create or replace function has_view(p_view text, p_desc text default '') returns text language plpgsql as $$
begin
  return ok(exists(select 1 from information_schema.views
                     where table_schema = 'public' and table_name = p_view), p_desc);
end;
$$;

create or replace function has_column(p_table text, p_column text, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(exists(select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = p_table and column_name = p_column),
            p_desc);
end;
$$;

create or replace function hasnt_column(p_table text, p_column text, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(not exists(select 1 from information_schema.columns
                         where table_schema = 'public' and table_name = p_table and column_name = p_column),
            p_desc);
end;
$$;

create or replace function has_index(p_schema text, p_table text, p_index text, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(exists(select 1 from pg_indexes
                     where schemaname = p_schema and tablename = p_table and indexname = p_index),
            p_desc);
end;
$$;

create or replace function has_trigger(p_table text, p_trigger text, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(exists(select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                     where c.relname = p_table and t.tgname = p_trigger and not t.tgisinternal),
            p_desc);
end;
$$;

create or replace function col_is_null(p_table text, p_column text, p_desc text default '')
returns text language plpgsql as $$
begin
  return ok(exists(select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = p_table and column_name = p_column
                       and is_nullable = 'YES' and column_default is null),
            p_desc);
end;
$$;

-- Runs p_sql, expects it to raise an error whose message matches p_pattern
-- (a plain SQL LIKE pattern). PL/pgSQL has no explicit SAVEPOINT/ROLLBACK TO
-- statement — that is SQL-level transaction control, not available inside a
-- function body — but a BEGIN/EXCEPTION block does the same thing implicitly:
-- it wraps the block in a savepoint and rolls back to it when the exception
-- fires, which is exactly what is needed here and is how the real pgTAP
-- throws_ok/throws_like are implemented internally.
create or replace function throws_like(p_sql text, p_pattern text, p_desc text default '')
returns text language plpgsql as $$
declare
  v_msg text;
  v_raised boolean := false;
begin
  begin
    execute p_sql;
  exception when others then
    v_raised := true;
    v_msg := sqlerrm;
  end;

  if not v_raised then
    return ok(false, p_desc || ' [expected an error, none was raised]');
  end if;

  return ok(v_msg like p_pattern,
    p_desc || case when v_msg not like p_pattern then format(' [error was: %s]', v_msg) else '' end);
end;
$$;

create or replace function finish() returns table(result text) language plpgsql security definer as $$
declare v_n int; v_passed int; v_failed int;
begin
  select n, passed, failed into v_n, v_passed, v_failed from _tap_state;
  raise notice '--- % of % assertions passed (% failed) ---', v_passed, v_n, v_failed;
  if v_failed > 0 then
    raise exception 'LOCAL PGTAP STUB: % of % assertions FAILED', v_failed, v_n;
  end if;
  return query select 'ok'::text;
end;
$$;
