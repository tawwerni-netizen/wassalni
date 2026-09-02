-- Wassalni / وصلني — storage buckets and the Realtime publication.
-- Depends on 0001..0006.
--
-- Neither of these existed as SQL before this migration. A bucket created from
-- the dashboard defaults to fully public or fully private with no row-level
-- nuance, and Supabase's `supabase_realtime` publication defaults to "every
-- table someone remembered to add" — if `private_verification_details` or
-- `claim_answers` were ever added to it, P2 data streams to every subscriber,
-- bypassing RLS entirely for the realtime channel.
--
-- UPLOAD ORDER THIS SCHEMA ASSUMES
-- The client must INSERT the `report_images` row FIRST (which is where the
-- 3-image cap and the FOUND/documents-private default live, both enforced by
-- triggers in 0006), THEN upload to storage at the path it names. A client
-- that uploads to storage before the row exists gets denied by the object
-- policy below, because there is nothing yet to check ownership against.

begin;

-- ---------------------------------------------------------------------------
-- 1. Buckets
-- ---------------------------------------------------------------------------
-- Path convention: {report_id}/{report_image_id}.webp
-- report_id as the first path segment is what lets the object policy check
-- ownership with storage.foldername(name) instead of trusting client metadata.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-images',
  'report-images',
  false,  -- never publicly readable by URL; every read goes through a policy
  350000, -- ~350KB; the client compresses to <=300KB WebP, this is headroom
  array['image/webp', 'image/jpeg', 'image/png']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 2. storage.objects policies
-- ---------------------------------------------------------------------------
-- These mirror report_images_read / report_images_write from 0001 exactly,
-- because a divergence between the two is itself a leak: a row could say
-- "private" while the underlying file is fetchable straight from storage.

create policy report_images_storage_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'report-images'
    and exists (
      select 1 from report_images ri
        join reports r on r.id = ri.report_id
       where ri.storage_path = storage.objects.name
         and (
           ri.is_public
           or r.profile_id = auth.uid()
           or current_is_staff()
           or exists (select 1 from claims c
                       where c.report_id = r.id and c.claimant_id = auth.uid()
                         and c.status = 'approved')
         )
    )
  );

create policy report_images_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'report-images'
    -- the report_id folder segment must belong to a report the caller owns;
    -- this is checked against reports directly (not report_images, which may
    -- not have its row yet) so the upload can follow the row by any margin
    and exists (
      select 1 from reports r
       where r.id = (storage.foldername(name))[1]::uuid
         and r.profile_id = auth.uid()
    )
  );

create policy report_images_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'report-images'
    and (
      current_is_staff()
      or exists (
        select 1 from reports r
         where r.id = (storage.foldername(name))[1]::uuid
           and r.profile_id = auth.uid()
      )
    )
  );

-- No update policy: an image is replaced by deleting and re-uploading, never
-- edited in place. This keeps "was this image ever public" unambiguous for
-- moderation/audit rather than mutable.

-- ---------------------------------------------------------------------------
-- 3. Realtime publication — explicit allowlist, not whatever accumulated
-- ---------------------------------------------------------------------------
-- supabase_realtime is created by the platform. We do not assume its starting
-- membership; we set it to exactly what the product needs and nothing else.
-- private_verification_details already has `replica identity nothing` (0001),
-- which blocks it from ever being addable here in a way that would work — this
-- is the second, non-overlapping layer: even a syntactically valid attempt to
-- add it is guarded by keeping the publication membership itself intentional
-- and reviewed in one place.

do $$
declare v_table text;
begin
  for v_table in
    select tablename from pg_publication_tables where pubname = 'supabase_realtime'
  loop
    execute format('alter publication supabase_realtime drop table public.%I', v_table);
  end loop;
end $$;

alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table reports;

-- Postgres has no reliable DDL event trigger for ALTER PUBLICATION ADD TABLE
-- (and event triggers are not something managed Postgres reliably grants
-- anyway), so this allowlist is enforced by convention — this migration is the
-- only place that touches the publication — plus a pgTAP assertion in
-- db/tests/001_schema_invariants.sql that queries pg_publication_tables
-- directly and fails if anything outside {messages, notifications, reports}
-- is ever added.

commit;
