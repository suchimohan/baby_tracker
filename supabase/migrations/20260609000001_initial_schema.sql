-- Baby Tracker v1 — initial schema
-- Cloud source of truth. Clients sync via supabase_flutter (Realtime + REST).
-- COPPA: all child data cascades on delete; see delete_child_data() below.

-- ============================================================
-- Profiles (one row per auth user / caregiver)
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  email text not null,
  -- COPPA: parental consent verified via email confirmation link
  consent_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create a profile when a user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- Children
-- ============================================================
create table public.children (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  date_of_birth date not null,
  photo_url text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Caregiver <-> child membership. v1: every caregiver gets read+write.
create table public.caregiver_children (
  child_id uuid not null references public.children (id) on delete cascade,
  caregiver_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'caregiver' check (role in ('primary', 'caregiver')),
  joined_at timestamptz not null default now(),
  primary key (child_id, caregiver_id)
);

-- Email invites for secondary caregivers
create table public.caregiver_invites (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children (id) on delete cascade,
  invited_by uuid not null references public.profiles (id),
  invite_email text not null,
  token uuid not null default gen_random_uuid(),
  accepted_by uuid references public.profiles (id),
  accepted_at timestamptz,
  expires_at timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now()
);

-- ============================================================
-- Tracking logs
-- All logs carry:
--   client_id   — UUID generated on-device (offline-first idempotency key)
--   logged_by   — which caregiver created it
--   server time defaults — LWW conflict resolution uses updated_at
-- ============================================================
create table public.sleep_logs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  child_id uuid not null references public.children (id) on delete cascade,
  logged_by uuid not null references public.profiles (id),
  started_at timestamptz not null,
  ended_at timestamptz, -- null = sleep in progress (timer running)
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz, -- soft delete so offline peers converge
  check (ended_at is null or ended_at > started_at)
);

create table public.feeding_logs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  child_id uuid not null references public.children (id) on delete cascade,
  logged_by uuid not null references public.profiles (id),
  feeding_type text not null check (feeding_type in ('bottle', 'breast', 'solids')),
  started_at timestamptz not null,
  ended_at timestamptz, -- null = feeding in progress
  amount_ml numeric, -- bottle only
  foods text[], -- solids only: what was eaten (e.g. {banana, oatmeal})
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ended_at is null or ended_at >= started_at)
);

create table public.diaper_logs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  child_id uuid not null references public.children (id) on delete cascade,
  logged_by uuid not null references public.profiles (id),
  diaper_type text not null check (diaper_type in ('wet', 'dirty', 'mixed', 'dry')),
  changed_at timestamptz not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  child_id uuid not null references public.children (id) on delete cascade,
  created_by uuid not null references public.profiles (id),
  kind text not null check (kind in ('sleep', 'feeding', 'diaper', 'custom')),
  title text not null,
  remind_at timestamptz not null,
  repeat_interval_minutes integer, -- null = one-shot
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Indexes for the hot query: "latest logs for child X"
create index sleep_logs_child_started_idx on public.sleep_logs (child_id, started_at desc);
create index feeding_logs_child_started_idx on public.feeding_logs (child_id, started_at desc);
create index diaper_logs_child_changed_idx on public.diaper_logs (child_id, changed_at desc);
create index reminders_child_idx on public.reminders (child_id, remind_at);

-- updated_at maintenance (LWW conflict resolution depends on this)
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger sleep_logs_touch before update on public.sleep_logs
  for each row execute function public.touch_updated_at();
create trigger feeding_logs_touch before update on public.feeding_logs
  for each row execute function public.touch_updated_at();
create trigger diaper_logs_touch before update on public.diaper_logs
  for each row execute function public.touch_updated_at();
create trigger reminders_touch before update on public.reminders
  for each row execute function public.touch_updated_at();
create trigger children_touch before update on public.children
  for each row execute function public.touch_updated_at();
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ============================================================
-- Row-Level Security
-- Rule: a caregiver may read/write rows only for children they
-- are linked to via caregiver_children.
-- ============================================================
alter table public.profiles enable row level security;
alter table public.children enable row level security;
alter table public.caregiver_children enable row level security;
alter table public.caregiver_invites enable row level security;
alter table public.sleep_logs enable row level security;
alter table public.feeding_logs enable row level security;
alter table public.diaper_logs enable row level security;
alter table public.reminders enable row level security;

create or replace function public.is_caregiver_of(target_child uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (
    select 1 from public.caregiver_children cc
    where cc.child_id = target_child and cc.caregiver_id = auth.uid()
  );
$$;

-- profiles: user manages own row
create policy "own profile read" on public.profiles
  for select using (id = auth.uid());
create policy "own profile update" on public.profiles
  for update using (id = auth.uid());

-- children
create policy "caregivers read children" on public.children
  for select using (public.is_caregiver_of(id));
create policy "create child" on public.children
  for insert with check (created_by = auth.uid());
create policy "caregivers update children" on public.children
  for update using (public.is_caregiver_of(id));
create policy "primary deletes child" on public.children
  for delete using (
    exists (
      select 1 from public.caregiver_children cc
      where cc.child_id = id and cc.caregiver_id = auth.uid() and cc.role = 'primary'
    )
  );

-- caregiver_children
create policy "read own memberships" on public.caregiver_children
  for select using (caregiver_id = auth.uid() or public.is_caregiver_of(child_id));
create policy "self-link on create or accepted invite" on public.caregiver_children
  for insert with check (caregiver_id = auth.uid());
create policy "leave or primary removes" on public.caregiver_children
  for delete using (caregiver_id = auth.uid());

-- caregiver_invites
create policy "caregivers manage invites" on public.caregiver_invites
  for all using (public.is_caregiver_of(child_id));
-- invited users may read their invite by email (to accept)
create policy "invitee reads invite" on public.caregiver_invites
  for select using (invite_email = (select email from public.profiles where id = auth.uid()));

-- log tables: identical pattern
create policy "caregivers all sleep" on public.sleep_logs
  for all using (public.is_caregiver_of(child_id)) with check (public.is_caregiver_of(child_id));
create policy "caregivers all feeding" on public.feeding_logs
  for all using (public.is_caregiver_of(child_id)) with check (public.is_caregiver_of(child_id));
create policy "caregivers all diaper" on public.diaper_logs
  for all using (public.is_caregiver_of(child_id)) with check (public.is_caregiver_of(child_id));
create policy "caregivers all reminders" on public.reminders
  for all using (public.is_caregiver_of(child_id)) with check (public.is_caregiver_of(child_id));

-- ============================================================
-- Realtime: broadcast log changes to caregivers
-- ============================================================
alter publication supabase_realtime add table public.sleep_logs;
alter publication supabase_realtime add table public.feeding_logs;
alter publication supabase_realtime add table public.diaper_logs;
alter publication supabase_realtime add table public.children;
alter publication supabase_realtime add table public.reminders;

-- ============================================================
-- COPPA helpers
-- ============================================================
-- One-action deletion of all data about a child (parental control).
create or replace function public.delete_child_data(target_child uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.caregiver_children cc
    where cc.child_id = target_child
      and cc.caregiver_id = auth.uid()
      and cc.role = 'primary'
  ) then
    raise exception 'only the primary caregiver can delete child data';
  end if;
  delete from public.children where id = target_child; -- cascades to all logs
end;
$$;

-- Accept an invite by token: links the calling user to the child.
create or replace function public.accept_caregiver_invite(invite_token uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_invite public.caregiver_invites;
begin
  select * into v_invite from public.caregiver_invites
  where token = invite_token and accepted_at is null and expires_at > now();
  if v_invite.id is null then
    raise exception 'invite not found or expired';
  end if;
  insert into public.caregiver_children (child_id, caregiver_id, role)
  values (v_invite.child_id, auth.uid(), 'caregiver')
  on conflict do nothing;
  update public.caregiver_invites
  set accepted_by = auth.uid(), accepted_at = now()
  where id = v_invite.id;
  return v_invite.child_id;
end;
$$;
