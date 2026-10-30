-- VasFlow Phase 4: applications, payments and documents.
-- Run this AFTER schema.sql and phase3_workspaces.sql (it depends on the
-- workspaces RLS helpers). Safe to run more than once.
--
-- How it works
--  * client_applications: one row per university/visa application a client has.
--  * client_payments: one row per fee (amount, paid amount, date, reference).
--    The balance is amount - paid_amount.
--  * client_documents: metadata rows; the files live in the PRIVATE
--    "client-documents" storage bucket under
--    <workspace_id>/<client_id>/<uuid>-<filename>.
--  * Every table is workspace-scoped with RLS: members read/write, admins
--    delete documents (the files are sensitive evidence).

create extension if not exists pgcrypto;

-- ---------- Applications ----------
create table if not exists public.client_applications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  application_type text not null default 'University admission',
  country text not null default '',
  institution text not null default '',
  course text not null default '',
  intake text not null default '',
  status text not null default 'Draft',
  submission_date date,
  deadline date,
  updated_at timestamptz not null default now()
);

create index if not exists client_applications_client_idx
  on public.client_applications (client_id);

-- ---------- Payments ----------
create table if not exists public.client_payments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  fee_type text not null default 'Consultation fee',
  description text not null default '',
  amount numeric not null default 0 check (amount >= 0),
  paid_amount numeric not null default 0 check (paid_amount >= 0),
  paid_date date,
  reference text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists client_payments_client_idx
  on public.client_payments (client_id);

-- ---------- Documents (metadata only; files live in storage) ----------
create table if not exists public.client_documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  name text not null,
  category text not null default 'Other supporting documents',
  file_path text not null,
  mime_type text not null default '',
  size_bytes bigint not null default 0,
  uploaded_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists client_documents_client_idx
  on public.client_documents (client_id);

-- ---------- Row Level Security ----------
alter table public.client_applications enable row level security;
alter table public.client_payments enable row level security;
alter table public.client_documents enable row level security;

-- Applications and payments follow the client rules: any member of the
-- workspace can read, add, edit and delete.
drop policy if exists "Members can read applications" on public.client_applications;
create policy "Members can read applications" on public.client_applications
  for select to authenticated using (public.is_workspace_member(workspace_id));
drop policy if exists "Members can add applications" on public.client_applications;
create policy "Members can add applications" on public.client_applications
  for insert to authenticated with check (public.is_workspace_member(workspace_id));
drop policy if exists "Members can edit applications" on public.client_applications;
create policy "Members can edit applications" on public.client_applications
  for update to authenticated
  using (public.is_workspace_member(workspace_id))
  with check (public.is_workspace_member(workspace_id));
drop policy if exists "Members can delete applications" on public.client_applications;
create policy "Members can delete applications" on public.client_applications
  for delete to authenticated using (public.is_workspace_member(workspace_id));

drop policy if exists "Members can read payments" on public.client_payments;
create policy "Members can read payments" on public.client_payments
  for select to authenticated using (public.is_workspace_member(workspace_id));
drop policy if exists "Members can add payments" on public.client_payments;
create policy "Members can add payments" on public.client_payments
  for insert to authenticated with check (public.is_workspace_member(workspace_id));
drop policy if exists "Members can edit payments" on public.client_payments;
create policy "Members can edit payments" on public.client_payments
  for update to authenticated
  using (public.is_workspace_member(workspace_id))
  with check (public.is_workspace_member(workspace_id));
drop policy if exists "Members can delete payments" on public.client_payments;
create policy "Members can delete payments" on public.client_payments
  for delete to authenticated using (public.is_workspace_member(workspace_id));

-- Documents: members manage them, but only admins may delete rows AND files.
drop policy if exists "Members can read documents" on public.client_documents;
create policy "Members can read documents" on public.client_documents
  for select to authenticated using (public.is_workspace_member(workspace_id));
drop policy if exists "Members can add documents" on public.client_documents;
create policy "Members can add documents" on public.client_documents
  for insert to authenticated with check (public.is_workspace_member(workspace_id));
drop policy if exists "Members can edit documents" on public.client_documents;
create policy "Members can edit documents" on public.client_documents
  for update to authenticated
  using (public.is_workspace_member(workspace_id))
  with check (public.is_workspace_member(workspace_id));
drop policy if exists "Admins can delete documents" on public.client_documents;
create policy "Admins can delete documents" on public.client_documents
  for delete to authenticated using (public.is_workspace_admin(workspace_id));

-- ---------- Private document storage bucket ----------
insert into storage.buckets (id, name, public)
values ('client-documents', 'client-documents', false)
on conflict (id) do nothing;

-- File paths look like: <workspace uuid>/<client uuid>/<uuid>-name.ext
create or replace function public.uuid_or_null(v text)
returns uuid
language sql
immutable
as $$
  select case
    when v ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then v::uuid
    else null
  end;
$$;

revoke all on function public.uuid_or_null(text) from public, anon;
grant execute on function public.uuid_or_null(text) to authenticated;

drop policy if exists "Members can read workspace documents" on storage.objects;
create policy "Members can read workspace documents" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'client-documents'
    and public.is_workspace_member(public.uuid_or_null((storage.foldername(name))[1]))
  );

drop policy if exists "Members can upload workspace documents" on storage.objects;
create policy "Members can upload workspace documents" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'client-documents'
    and public.is_workspace_member(public.uuid_or_null((storage.foldername(name))[1]))
  );

drop policy if exists "Members can update workspace documents" on storage.objects;
create policy "Members can update workspace documents" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'client-documents'
    and public.is_workspace_member(public.uuid_or_null((storage.foldername(name))[1]))
  )
  with check (
    bucket_id = 'client-documents'
    and public.is_workspace_member(public.uuid_or_null((storage.foldername(name))[1]))
  );

drop policy if exists "Admins can delete workspace documents" on storage.objects;
create policy "Admins can delete workspace documents" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'client-documents'
    and public.is_workspace_admin(public.uuid_or_null((storage.foldername(name))[1]))
  );
