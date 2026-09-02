-- Wassalni — local/CI-only Supabase platform stub.
--
-- NEVER apply this to a real Supabase project. Supabase already provides
-- everything here (the auth schema, the anon/authenticated/service_role
-- roles, their default grants, the storage schema, and the
-- supabase_realtime publication). This file exists only so migrations and
-- tests can run against a vanilla Postgres instance during development and
-- in CI, where none of that platform scaffolding exists.
--
-- The grants below matter more than they look: a freshly created Postgres
-- table has NO privileges for any role but its owner. Supabase grants
-- `anon`/`authenticated` broad table privileges by default specifically so
-- that Row Level Security is the enforcement boundary, not the grant itself.
-- Without replicating that here, every `revoke ... from authenticated` in our
-- migrations would test against a table that was never granted in the first
-- place — the assertion would pass whether or not the revoke actually ran.
-- That gap existed in this repo's CI job before this file was added.

-- ---------------------------------------------------------------------------
-- Roles and default grants (mirrors Supabase's platform bootstrap)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all routines in schema public to anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on routines to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- auth schema stub
-- ---------------------------------------------------------------------------

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

-- Real Supabase reads the JWT claim; here the test harness sets it per session
-- with `set local request.jwt.claim.sub = '<uuid>'` and `set local role
-- authenticated` to simulate a specific signed-in user.
create or replace function auth.uid() returns uuid
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- storage schema stub — minimal shape needed by 0007's policies
-- ---------------------------------------------------------------------------

create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz not null default now()
);

alter table storage.objects enable row level security;

create or replace function storage.foldername(name text)
returns text[] language sql immutable as $$
  select case
    when array_length(string_to_array(name, '/'), 1) <= 1 then '{}'::text[]
    else (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1]
  end;
$$;

grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.buckets, storage.objects to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Realtime publication stub — empty, so 0007's ALTER PUBLICATION statements
-- have something to operate on.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'create publication supabase_realtime';
  end if;
end $$;
