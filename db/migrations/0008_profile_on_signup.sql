-- Wassalni / وصلني — create a profiles row automatically on signup.
-- Depends on 0001..0007.
--
-- TASKS.md M1 calls for this explicitly ("profiles row created on first
-- sign-in (DB trigger on auth.users)") and it did not exist in any prior
-- migration. Without it, every RLS policy that joins to `profiles` (current
-- community, current role, is-suspended checks) fails for a brand new user
-- until some client-side code remembers to insert the row — a race the client
-- should never be responsible for winning.

begin;

create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, display_name)
  values (
    new.id,
    -- A safe default so the row is never invalid; onboarding (M1) is expected
    -- to prompt the user to set a real display name before their first report.
    'مستخدم جديد'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- Fires on auth.users, which is owned by the auth schema/extension, not by us.
-- Supabase permits triggers on it from a migration; this is the platform's
-- documented pattern for this exact use case.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

commit;
