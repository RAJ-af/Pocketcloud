-- PocketCloud baseline schema. Review in a staging project before production.
-- Every exposed public table has RLS and explicit grants because new Supabase projects
-- no longer expose newly-created tables automatically.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_type text not null check (policy_type in ('terms','privacy')),
  policy_version text not null check (char_length(policy_version) <= 32),
  consented boolean not null,
  decided_at timestamptz not null default now(),
  source text not null default 'mobile_onboarding' check (source in ('mobile_onboarding','settings','web')),
  created_at timestamptz not null default now()
);
create index if not exists user_consents_owner_version_idx on public.user_consents(user_id, policy_type, policy_version, decided_at desc);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  install_id uuid not null,
  name text not null default 'Android device' check (char_length(name) between 1 and 80),
  platform text not null check (platform in ('android','ios','web','windows','macos','linux','unknown')),
  role text not null default 'client' check (role in ('client','server')),
  server_enabled boolean not null default false,
  is_online boolean not null default false,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, install_id),
  check ((server_enabled and role = 'server') or (not server_enabled and role = 'client'))
);
create index if not exists devices_user_created_idx on public.devices(user_id, created_at desc);
create index if not exists devices_active_idx on public.devices(user_id, is_online) where revoked_at is null;

create table if not exists public.pairing_codes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  server_device_id uuid not null references public.devices(id) on delete cascade,
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check (status in ('pending','used','revoked','expired')),
  can_upload boolean not null default false,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (owner_id, code_hash),
  check (expires_at > created_at and expires_at <= created_at + interval '5 minutes')
);
create index if not exists pairing_codes_lookup_idx on public.pairing_codes(owner_id, code_hash, status, expires_at);

create table if not exists public.device_pairs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  server_device_id uuid not null references public.devices(id) on delete cascade,
  client_device_id uuid not null references public.devices(id) on delete cascade,
  can_list boolean not null default true,
  can_download boolean not null default true,
  can_upload boolean not null default false,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (server_device_id <> client_device_id),
  unique (owner_id, server_device_id, client_device_id)
);
create index if not exists device_pairs_owner_idx on public.device_pairs(owner_id, created_at desc);

create table if not exists public.signaling_messages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  from_device_id uuid not null references public.devices(id) on delete cascade,
  to_device_id uuid not null references public.devices(id) on delete cascade,
  message_type text not null check (message_type in ('offer','answer','candidate','hangup')),
  payload jsonb not null check (pg_column_size(payload) <= 24576),
  created_at timestamptz not null default now(),
  check (from_device_id <> to_device_id)
);
create index if not exists signaling_recipient_idx on public.signaling_messages(owner_id, to_device_id, created_at);

create table if not exists public.connection_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  event_type text not null check (event_type in ('server_started','server_stopped','peer_connected','peer_disconnected','pairing_created','pairing_revoked','transfer_completed','transfer_failed')),
  details jsonb not null default '{}'::jsonb check (pg_column_size(details) <= 4096),
  created_at timestamptz not null default now()
);
create index if not exists connection_events_owner_created_idx on public.connection_events(owner_id, created_at desc);

-- Consent gate: the app UI is not a security boundary. Enforce current policy
-- acceptance in database policies and server-side pairing redemption too.
-- Bump these versions in this migration whenever lib/core/legal_versions.dart changes.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create or replace function private.has_current_consent()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select c.consented from public.user_consents c
    where c.user_id = (select auth.uid()) and c.policy_type = 'terms'
      and c.policy_version = '2026-10-24'
    order by c.decided_at desc, c.created_at desc, c.id desc limit 1
  ), false) and coalesce((
    select c.consented from public.user_consents c
    where c.user_id = (select auth.uid()) and c.policy_type = 'privacy'
      and c.policy_version = '2026-10-24'
    order by c.decided_at desc, c.created_at desc, c.id desc limit 1
  ), false);
$$;
revoke all on function private.has_current_consent() from public, anon;
grant execute on function private.has_current_consent() to authenticated;

-- The trusted Edge function calls this helper with the authenticated JWT-derived user ID.
-- This helper is never executable by mobile/anon clients directly.
create or replace function private.owner_has_current_consent(p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select c.consented from public.user_consents c
    where c.user_id = p_user_id and c.policy_type = 'terms'
      and c.policy_version = '2026-10-24'
    order by c.decided_at desc, c.created_at desc, c.id desc limit 1
  ), false) and coalesce((
    select c.consented from public.user_consents c
    where c.user_id = p_user_id and c.policy_type = 'privacy'
      and c.policy_version = '2026-10-24'
    order by c.decided_at desc, c.created_at desc, c.id desc limit 1
  ), false);
$$;
revoke all on function private.owner_has_current_consent(uuid) from public, anon, authenticated;
grant execute on function private.owner_has_current_consent(uuid) to service_role;

-- Database timestamps are authoritative. Client-provided activity timestamps are ignored.
create or replace function private.stamp_device_activity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.last_seen_at := pg_catalog.now();
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;
revoke all on function private.stamp_device_activity() from public, anon, authenticated;
drop trigger if exists devices_stamp_activity on public.devices;
create trigger devices_stamp_activity before insert or update on public.devices
for each row execute function private.stamp_device_activity();

-- RLS on every exposed table.
alter table public.profiles enable row level security;
alter table public.user_consents enable row level security;
alter table public.devices enable row level security;
alter table public.pairing_codes enable row level security;
alter table public.device_pairs enable row level security;
alter table public.signaling_messages enable row level security;
alter table public.connection_events enable row level security;

-- Revoke accidental broad defaults and grant only the operations the client uses.
revoke all on public.profiles, public.user_consents, public.devices, public.pairing_codes, public.device_pairs, public.signaling_messages, public.connection_events from anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant insert (id, display_name, updated_at) on public.profiles to authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;
-- Clients cannot forge consent timestamps; PostgreSQL supplies decided_at/created_at.
grant select on public.user_consents to authenticated;
grant insert (user_id, policy_type, policy_version, consented, source) on public.user_consents to authenticated;
grant select on public.devices to authenticated;
grant insert (user_id, install_id, name, platform, role, server_enabled, is_online, last_seen_at) on public.devices to authenticated;
grant update (name, role, server_enabled, is_online, last_seen_at, updated_at) on public.devices to authenticated;
grant insert (owner_id, server_device_id, code_hash, can_upload) on public.pairing_codes to authenticated;
grant select on public.device_pairs to authenticated;
grant update (revoked_at) on public.device_pairs to authenticated;
grant select on public.signaling_messages to authenticated;
grant insert (owner_id, from_device_id, to_device_id, message_type, payload) on public.signaling_messages to authenticated;
grant delete on public.signaling_messages to authenticated;
grant select on public.connection_events to authenticated;
grant insert (owner_id, device_id, event_type, details) on public.connection_events to authenticated;

-- Profile: strictly self-owned. Do not use editable user_metadata as an authorization claim.
create policy profiles_select_self on public.profiles for select to authenticated using ((select auth.uid()) = id and (select private.has_current_consent()));
create policy profiles_insert_self on public.profiles for insert to authenticated with check ((select auth.uid()) = id and (select private.has_current_consent()));
create policy profiles_update_self on public.profiles for update to authenticated using ((select auth.uid()) = id and (select private.has_current_consent())) with check ((select auth.uid()) = id and (select private.has_current_consent()));

-- Consent records are append-only from the client, including rejection decisions.
create policy consents_select_self on public.user_consents for select to authenticated using ((select auth.uid()) = user_id);
create policy consents_insert_self on public.user_consents for insert to authenticated with check ((select auth.uid()) = user_id);

create policy devices_select_self on public.devices for select to authenticated using ((select auth.uid()) = user_id and (select private.has_current_consent()));
create policy devices_insert_self on public.devices for insert to authenticated with check ((select auth.uid()) = user_id and role = 'client' and server_enabled = false and revoked_at is null and (select private.has_current_consent()));
create policy devices_update_self on public.devices for update to authenticated using ((select auth.uid()) = user_id and revoked_at is null and (select private.has_current_consent())) with check ((select auth.uid()) = user_id and revoked_at is null and (select private.has_current_consent()));

-- Device foreign keys are constrained to the same owner for pairings and signaling.
create policy pairing_codes_select_self on public.pairing_codes for select to authenticated using ((select auth.uid()) = owner_id);
create policy pairing_codes_insert_self on public.pairing_codes for insert to authenticated with check (
  (select auth.uid()) = owner_id and (select private.has_current_consent()) and status = 'pending' and used_at is null
  and expires_at > pg_catalog.now() and expires_at <= pg_catalog.now() + interval '5 minutes'
  and created_at <= pg_catalog.now() + interval '1 minute'
  and exists (select 1 from public.devices d where d.id = server_device_id and d.user_id = auth.uid() and d.server_enabled and d.revoked_at is null)
);
create policy pairing_codes_update_self on public.pairing_codes for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);

create policy device_pairs_select_self on public.device_pairs for select to authenticated using ((select auth.uid()) = owner_id and (select private.has_current_consent()));
create policy device_pairs_insert_self on public.device_pairs for insert to authenticated with check (
  (select auth.uid()) = owner_id
  and exists (select 1 from public.devices s where s.id = server_device_id and s.user_id = auth.uid() and s.server_enabled and s.revoked_at is null)
  and exists (select 1 from public.devices c where c.id = client_device_id and c.user_id = auth.uid() and c.revoked_at is null)
);
create policy device_pairs_update_self on public.device_pairs for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);

create policy signaling_select_pair_members on public.signaling_messages for select to authenticated using (
  (select auth.uid()) = owner_id and (select private.has_current_consent()) and exists (
    select 1 from public.device_pairs p
    where p.owner_id = auth.uid() and p.revoked_at is null
      and ((p.server_device_id = from_device_id and p.client_device_id = to_device_id)
        or (p.server_device_id = to_device_id and p.client_device_id = from_device_id))
  )
);
create policy signaling_insert_pair_members on public.signaling_messages for insert to authenticated with check (
  (select auth.uid()) = owner_id and (select private.has_current_consent())
  and exists (select 1 from public.devices d where d.id = from_device_id and d.user_id = auth.uid() and d.revoked_at is null)
  and exists (select 1 from public.devices d where d.id = to_device_id and d.user_id = auth.uid() and d.revoked_at is null)
  and exists (
    select 1 from public.device_pairs p where p.owner_id = auth.uid() and p.revoked_at is null
      and ((p.server_device_id = from_device_id and p.client_device_id = to_device_id)
        or (p.server_device_id = to_device_id and p.client_device_id = from_device_id))
  )
);
create policy signaling_delete_self on public.signaling_messages for delete to authenticated using ((select auth.uid()) = owner_id);

create policy events_select_self on public.connection_events for select to authenticated using ((select auth.uid()) = owner_id and (select private.has_current_consent()));
create policy events_insert_self on public.connection_events for insert to authenticated with check (
  (select auth.uid()) = owner_id and (select private.has_current_consent()) and (device_id is null or exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))
);

-- Realtime database-change messages are used for WebRTC signalling, not file contents.
-- On supported Supabase projects, add only this table to the publication. If already present,
-- run the guarded block rather than blindly altering the publication.
do $$ begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'signaling_messages'
  ) then
    alter publication supabase_realtime add table public.signaling_messages;
  end if;
exception when undefined_object then
  raise notice 'supabase_realtime publication not available; enable replication for signaling_messages in Dashboard > Database > Publications.';
end $$;

-- Harden client privileges after table creation. Pair creation is only via the
-- authenticated Edge Function + service-role-only atomic RPC below.
revoke select, update on public.pairing_codes from authenticated;
revoke insert on public.pairing_codes from authenticated;
grant insert (owner_id, server_device_id, code_hash, can_upload) on public.pairing_codes to authenticated;
drop policy if exists pairing_codes_select_self on public.pairing_codes;
drop policy if exists pairing_codes_update_self on public.pairing_codes;

revoke insert, update on public.device_pairs from authenticated;
grant update (revoked_at) on public.device_pairs to authenticated;
drop policy if exists device_pairs_insert_self on public.device_pairs;
drop policy if exists device_pairs_update_self on public.device_pairs;
create policy device_pairs_revoke_self on public.device_pairs
  for update to authenticated
  using ((select auth.uid()) = owner_id and revoked_at is null)
  with check ((select auth.uid()) = owner_id and revoked_at is not null);

-- Keep clients from self-unrevoking or changing the installation ownership.
revoke update on public.devices from authenticated;
grant update (name, role, server_enabled, is_online, last_seen_at, updated_at) on public.devices to authenticated;

-- Atomic redemption runs with the invoker role. Only the trusted Edge Function service_role can execute it.
create or replace function public.redeem_pairing_code_atomic(
  p_owner_id uuid,
  p_code_hash text,
  p_client_device_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_code public.pairing_codes%rowtype;
  v_pair_id uuid;
  v_client public.devices%rowtype;
  v_server public.devices%rowtype;
begin
  if p_owner_id is null or p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' or p_client_device_id is null then
    raise exception 'invalid pairing request' using errcode = '22023';
  end if;
  if not private.owner_has_current_consent(p_owner_id) then
    raise exception 'current terms and privacy consent required' using errcode = '42501';
  end if;

  select * into v_code from public.pairing_codes
    where owner_id = p_owner_id and code_hash = p_code_hash
    for update;
  if not found or v_code.status <> 'pending' or v_code.expires_at <= pg_catalog.now() then
    raise exception 'pairing code invalid, expired, or already used' using errcode = '22023';
  end if;

  select * into v_server from public.devices where id = v_code.server_device_id and user_id = p_owner_id for update;
  select * into v_client from public.devices where id = p_client_device_id and user_id = p_owner_id for update;
  if not found or v_server.id is null or v_client.id is null or v_server.revoked_at is not null
    or v_client.revoked_at is not null or not v_server.server_enabled or v_server.id = v_client.id then
    raise exception 'server/client device is not eligible for pairing' using errcode = '22023';
  end if;

  insert into public.device_pairs(owner_id, server_device_id, client_device_id, can_list, can_download, can_upload)
    values (p_owner_id, v_server.id, v_client.id, true, true, v_code.can_upload)
    on conflict (owner_id, server_device_id, client_device_id)
    do update set can_list = excluded.can_list, can_download = excluded.can_download,
                  can_upload = excluded.can_upload, revoked_at = null
    returning id into v_pair_id;

  update public.pairing_codes set status = 'used', used_at = pg_catalog.now() where id = v_code.id;
  return v_pair_id;
end;
$$;
revoke all on function public.redeem_pairing_code_atomic(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.redeem_pairing_code_atomic(uuid, text, uuid) to service_role;

-- Trusted device revocation is performed server-side so an app cannot restore
-- the revoked_at timestamp by making a normal Data API update.
create or replace function public.revoke_device_atomic(p_owner_id uuid, p_device_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_owner_id is null or p_device_id is null then
    raise exception 'invalid revocation request' using errcode = '22023';
  end if;
  update public.devices set revoked_at = pg_catalog.now(), server_enabled = false, role = 'client', is_online = false, updated_at = pg_catalog.now()
    where id = p_device_id and user_id = p_owner_id and revoked_at is null;
  if not found then return false; end if;
  update public.device_pairs set revoked_at = pg_catalog.now()
    where owner_id = p_owner_id and revoked_at is null
      and (server_device_id = p_device_id or client_device_id = p_device_id);
  update public.pairing_codes set status = 'revoked'
    where owner_id = p_owner_id and server_device_id = p_device_id and status = 'pending';
  return true;
end;
$$;
revoke all on function public.revoke_device_atomic(uuid, uuid) from public, anon, authenticated;
grant execute on function public.revoke_device_atomic(uuid, uuid) to service_role;
