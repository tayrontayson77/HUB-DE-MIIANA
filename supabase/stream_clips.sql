-- À exécuter dans Supabase SQL Editor
create table if not exists public.stream_clips (
  id uuid primary key default gen_random_uuid(),
  author text not null,
  title text not null,
  url text not null,
  description text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

alter table public.stream_clips enable row level security;

drop policy if exists clips_public_approved on public.stream_clips;
create policy clips_public_approved on public.stream_clips
for select to anon, authenticated using (status = 'approved');

drop policy if exists clips_submit_public on public.stream_clips;
create policy clips_submit_public on public.stream_clips
for insert to anon, authenticated
with check (status = 'pending');

-- La modération (approved/rejected) doit être faite depuis un espace sécurisé
-- avec le rôle Fondateur/Staff, pas depuis le navigateur public.
