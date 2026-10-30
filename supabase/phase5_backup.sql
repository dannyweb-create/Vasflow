-- VasFlow Phase 5: cloud backup foundation (workspace_backups + private bucket).
-- Run this AFTER phase4_features.sql (it reuses public.uuid_or_null from there,
-- and the phase 3 helper functions public.is_workspace_member / public.is_workspace_admin).
-- Safe to run more than once: every statement is idempotent.
--
-- Purpose
--  * workspace_backups stores backup history metadata for one workspace:
--    who ran it, when, what status it reached, checksum and file counts.
--  * The backup payload itself is one ZIP file in the private "workspace-backups"
--    bucket at <workspace uuid>/<backup uuid>.zip.
--  * Authorization (server-side, never UI-only):
--      - Any workspace member may LIST/READ backup metadata of their workspace.
--      - Only workspace ADMINS may create, update, delete backup records and the
--        backup files in storage. This mirrors the client delete rules in phase 3/4.
--  * History cap: a trigger blocks the 51st completed backup row per workspace.
--    Nothing is deleted automatically; the app must explicitly delete the oldest
--    completed record and its storage file before running a new backup at the cap.
--
-- This file does NOT touch existing tables, existing policies, or the
-- "client-documents" bucket. There is no restore-staging table on purpose:
-- restores write through the normal (already RLS-guarded) business tables.

-- ---------- Backup history table ----------
create table if not exists public.workspace_backups (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  kind text not null default 'manual' check (kind in ('manual', 'auto')),
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed')),
  manifest_sha256 text
    check (manifest_sha256 is null or manifest_sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  record_count integer check (record_count is null or record_count >= 0),
  file_count integer check (file_count is null or file_count >= 0),
  storage_path text check (
    storage_path is null
    or (
      -- First folder must be this row's workspace uuid.
      public.uuid_or_null(split_part(storage_path, '/', 1)) = workspace_id
      -- Second segment must be "<uuid>.zip" and nothing deeper.
      and split_part(storage_path, '/', 2)
        ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.zip$'
      and split_part(storage_path, '/', 3) = ''
    )
  ),
  error text check (error is null or char_length(error) <= 2000),
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists workspace_backups_workspace_idx
  on public.workspace_backups (workspace_id, created_at desc);

alter table public.workspace_backups enable row level security;

-- ---------- Row Level Security ----------
drop policy if exists "Members can read workspace backups" on public.workspace_backups;
create policy "Members can read workspace backups" on public.workspace_backups
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

drop policy if exists "Admins can record workspace backups" on public.workspace_backups;
create policy "Admins can record workspace backups" on public.workspace_backups
  for insert to authenticated
  with check (public.is_workspace_admin(workspace_id));

drop policy if exists "Admins can update workspace backups" on public.workspace_backups;
create policy "Admins can update workspace backups" on public.workspace_backups
  for update to authenticated
  using (public.is_workspace_admin(workspace_id))
  with check (public.is_workspace_admin(workspace_id));

drop policy if exists "Admins can delete workspace backups" on public.workspace_backups;
create policy "Admins can delete workspace backups" on public.workspace_backups
  for delete to authenticated
  using (public.is_workspace_admin(workspace_id));

-- ---------- Completed-backup history cap (max 50) ----------
-- Blocks only the write that would push a workspace past 50 completed rows.
-- It never deletes anything: pruning is an explicit, admin-driven step in the
-- app (delete record + storage file together), so history stays consistent.
create or replace function public.guard_backup_history_cap()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_completed integer;
begin
  -- Serialize concurrent finalizations for the same workspace: two simultaneous
  -- inserts could both pass the count check before either commits. The
  -- transaction-scoped lock is released automatically at commit or rollback.
  -- hashtextextended maps the workspace uuid onto one 64-bit lock key; a hash
  -- collision only over-serializes different workspaces, it never under-locks.
  perform pg_advisory_xact_lock(hashtextextended(new.workspace_id::text, 42));
  if new.status is distinct from 'completed' then
    return new;
  end if;
  select count(*) into v_completed
  from public.workspace_backups
  where workspace_id = new.workspace_id
    and status = 'completed'
    and id <> new.id;
  if v_completed >= 50 then
    raise exception 'This workspace already has 50 completed backups. Delete the oldest one (history will confirm) before backing up again.';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_backup_history_cap() from public, anon;
grant execute on function public.guard_backup_history_cap() to authenticated;

drop trigger if exists backups_completed_cap on public.workspace_backups;
create trigger backups_completed_cap
  before insert or update of status
  on public.workspace_backups
  for each row
  execute function public.guard_backup_history_cap();

-- ---------- Private backup storage bucket ----------
insert into storage.buckets (id, name, public)
values ('workspace-backups', 'workspace-backups', false)
on conflict (id) do nothing;

-- File paths look like: <workspace uuid>/<backup uuid>.zip
drop policy if exists "Admins can read backup files" on storage.objects;
create policy "Admins can read backup files" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'workspace-backups'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
  );

drop policy if exists "Admins can upload backup files" on storage.objects;
create policy "Admins can upload backup files" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'workspace-backups'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
    and array_length((storage.foldername(name)), 1) = 2
    and (storage.foldername(name))[2]
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.zip$'
  );

drop policy if exists "Admins can replace backup files" on storage.objects;
create policy "Admins can replace backup files" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'workspace-backups'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
  )
  with check (
    bucket_id = 'workspace-backups'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
    and array_length((storage.foldername(name)), 1) = 2
    and (storage.foldername(name))[2]
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.zip$'
  );

drop policy if exists "Admins can delete backup files" on storage.objects;
create policy "Admins can delete backup files" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'workspace-backups'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
  );
