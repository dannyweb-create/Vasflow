-- VasFlow Phase 3: workspaces, Admin/Staff roles, invite codes.
-- Run this in the Supabase SQL Editor AFTER schema.sql. Safe to run more than once.
--
-- How it works
--  * A workspace is one business. Each person belongs to ONE workspace for now.
--  * Roles live in workspace_members (admin or staff), never in the app.
--  * Staff can read, add and edit clients in their workspace. Only admins can delete.
--  * Creating a workspace, making invite codes and joining go through functions
--    below, so nobody can give themselves a role by writing to a table directly.
--  * Invite codes are stored hashed, work once, and expire after 48 hours.

create extension if not exists pgcrypto;

-- ---------- Tables ----------
create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'staff')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

-- One workspace per person (keeps the app simple for now).
create unique index if not exists workspace_members_one_workspace_per_user
  on public.workspace_members (user_id);

create table if not exists public.workspace_invites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  code_hash text not null unique,
  role text not null default 'staff' check (role = 'staff'),
  expires_at timestamptz not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz
);

alter table public.clients
  add column if not exists workspace_id uuid references public.workspaces(id) on delete cascade;
create index if not exists clients_workspace_idx on public.clients (workspace_id);

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invites enable row level security;

-- ---------- Helper functions used by the policies ----------
create or replace function public.is_workspace_member(ws uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = ws and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_workspace_admin(ws uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = ws and m.user_id = auth.uid() and m.role = 'admin'
  );
$$;

-- ---------- Functions the app calls ----------
create or replace function public.create_workspace(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ws uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Workspace name must be at least 2 characters';
  end if;
  if exists (select 1 from public.workspace_members m where m.user_id = auth.uid()) then
    raise exception 'You already belong to a workspace';
  end if;

  insert into public.workspaces (name, created_by)
  values (trim(p_name), auth.uid())
  returning id into v_ws;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_ws, auth.uid(), 'admin');

  -- Adopt clients this person created before workspaces existed.
  update public.clients
  set workspace_id = v_ws
  where owner_id = auth.uid() and workspace_id is null;

  return v_ws;
end;
$$;

create or replace function public.create_invite()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ws uuid;
  v_code text;
begin
  select m.workspace_id into v_ws
  from public.workspace_members m
  where m.user_id = auth.uid() and m.role = 'admin';

  if v_ws is null then
    raise exception 'Only an admin can create invite codes';
  end if;

  v_code := upper(encode(gen_random_bytes(8), 'hex'));

  insert into public.workspace_invites (workspace_id, code_hash, expires_at)
  values (v_ws, encode(digest(v_code, 'sha256'), 'hex'), now() + interval '48 hours');

  return substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4) || '-' ||
         substr(v_code, 9, 4) || '-' || substr(v_code, 13, 4);
end;
$$;

create or replace function public.redeem_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_norm text;
  v_inv public.workspace_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;
  if exists (select 1 from public.workspace_members m where m.user_id = auth.uid()) then
    raise exception 'You already belong to a workspace';
  end if;

  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Fa-f]', '', 'g'));

  select * into v_inv
  from public.workspace_invites i
  where i.code_hash = encode(digest(v_norm, 'sha256'), 'hex')
    and i.used_at is null
    and i.expires_at > now()
  for update;

  if not found then
    raise exception 'That invite code is not valid or has expired';
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_inv.workspace_id, auth.uid(), v_inv.role);

  update public.workspace_invites
  set used_by = auth.uid(), used_at = now()
  where id = v_inv.id;

  return v_inv.workspace_id;
end;
$$;

create or replace function public.list_team()
returns table (user_id uuid, display_name text, role text, joined_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select m.user_id, coalesce(p.display_name, ''), m.role, m.created_at
  from public.workspace_members m
  left join public.profiles p on p.id = m.user_id
  where m.workspace_id = (
    select w.workspace_id from public.workspace_members w where w.user_id = auth.uid()
  )
  order by m.created_at;
$$;

-- Only signed-in users may call these functions.
revoke all on function public.is_workspace_member(uuid) from public, anon;
revoke all on function public.is_workspace_admin(uuid) from public, anon;
revoke all on function public.create_workspace(text) from public, anon;
revoke all on function public.create_invite() from public, anon;
revoke all on function public.redeem_invite(text) from public, anon;
revoke all on function public.list_team() from public, anon;
grant execute on function public.is_workspace_member(uuid) to authenticated;
grant execute on function public.is_workspace_admin(uuid) to authenticated;
grant execute on function public.create_workspace(text) to authenticated;
grant execute on function public.create_invite() to authenticated;
grant execute on function public.redeem_invite(text) to authenticated;
grant execute on function public.list_team() to authenticated;

-- ---------- Row Level Security policies ----------
drop policy if exists "Members can read their workspace" on public.workspaces;
drop policy if exists "Admins can rename their workspace" on public.workspaces;
create policy "Members can read their workspace" on public.workspaces
  for select to authenticated using (public.is_workspace_member(id));
create policy "Admins can rename their workspace" on public.workspaces
  for update to authenticated
  using (public.is_workspace_admin(id)) with check (public.is_workspace_admin(id));

drop policy if exists "People can read their own membership" on public.workspace_members;
create policy "People can read their own membership" on public.workspace_members
  for select to authenticated using (user_id = auth.uid());
-- No insert/update/delete policies on purpose: membership changes only happen
-- through the functions above. workspace_invites has no policies at all, so it
-- cannot be read or written directly.

-- Clients: replace the old owner-only rules with workspace rules.
drop policy if exists "Users can read their own clients" on public.clients;
drop policy if exists "Users can insert their own clients" on public.clients;
drop policy if exists "Users can update their own clients" on public.clients;
drop policy if exists "Members can read workspace clients" on public.clients;
drop policy if exists "Members can add workspace clients" on public.clients;
drop policy if exists "Members can edit workspace clients" on public.clients;
drop policy if exists "Admins can delete workspace clients" on public.clients;

create policy "Members can read workspace clients" on public.clients
  for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "Members can add workspace clients" on public.clients
  for insert to authenticated with check (public.is_workspace_member(workspace_id));
create policy "Members can edit workspace clients" on public.clients
  for update to authenticated
  using (public.is_workspace_member(workspace_id))
  with check (public.is_workspace_member(workspace_id));
create policy "Admins can delete workspace clients" on public.clients
  for delete to authenticated using (public.is_workspace_admin(workspace_id));
