-- VasFlow database schema (Phase 1 hardening of the starter schema).
-- Run this whole file in the Supabase SQL Editor. It is safe to run more than once.
-- NOTE: clients are still visible only to the user who created them. Phase 3 replaces
-- this with workspace membership so staff can share records. Do not store real
-- client or passport data until that is done and tested.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'staff' check (role in ('admin','staff')),
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid default auth.uid() references auth.users(id) on delete set null,
  full_name text not null,
  email text default '',
  phone text default '',
  country text default '',
  university text default '',
  visa_status text default 'Not started',
  passport_number text default '',
  notes text default '',
  stage text default 'New lead',
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.clients enable row level security;

-- SECURITY FIX: the old starter let any user insert their OWN profile row, which
-- meant a user could give themselves role = 'admin'. Profiles are now created only
-- by the trigger below (always as 'staff'). Users can read their own profile but
-- cannot insert or update profiles at all.
drop policy if exists "Users can create own profile" on public.profiles;
drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id, split_part(coalesce(new.email, ''), '@', 1), 'staff')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Create profiles for people who signed up before this trigger existed.
insert into public.profiles (id, display_name, role)
select u.id, split_part(coalesce(u.email, ''), '@', 1), 'staff'
from auth.users u
on conflict (id) do nothing;

drop policy if exists "Users can read their own clients" on public.clients;
drop policy if exists "Users can insert their own clients" on public.clients;
drop policy if exists "Users can update their own clients" on public.clients;
create policy "Users can read their own clients" on public.clients
  for select to authenticated using (owner_id = auth.uid());
create policy "Users can insert their own clients" on public.clients
  for insert to authenticated with check (owner_id = auth.uid());
create policy "Users can update their own clients" on public.clients
  for update to authenticated using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
-- Deliberately no delete policy yet: deletes are refused by the server.
-- Phase 3/4 will add archiving and an admin-only delete based on workspace roles.

-- To make YOURSELF the first admin, run this separately in the SQL Editor
-- (replace the email). This runs with full database rights, so it cannot be
-- done from inside the app:
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'you@example.com');

-- To check nobody gave themselves admin with the old starter schema:
--   select id, display_name, role from public.profiles;

-- Storage: create a PRIVATE bucket named "client-documents" in the Supabase
-- dashboard later (Phase 4). Never make passport or visa documents public.
