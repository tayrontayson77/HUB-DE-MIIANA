-- HUB DE MIIANA - Supabase
-- Execute ce script dans Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Membre',
  role text not null default 'membre' check (role in ('fondateur','co-fonda','admin','moderateur','helper','membre')),
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  icon text default '📁',
  position integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.category_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  title text not null,
  description text default '',
  link text default '',
  image text default '',
  position integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references auth.users(id) on delete set null,
  author_name text not null,
  content text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.category_items enable row level security;
alter table public.posts enable row level security;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.can_manage()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.my_role() in ('fondateur','co-fonda','admin'), false) $$;

-- Profils : chacun peut voir son profil; fondateur/co-fonda/admin peuvent gérer les rôles.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select using (true);
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert with check (id = auth.uid() or public.can_manage());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update using (id = auth.uid() or public.can_manage()) with check (id = auth.uid() or public.can_manage());

-- Catégories : publiques en lecture, gestion réservée aux responsables.
drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories for select using (true);
drop policy if exists categories_manage on public.categories;
create policy categories_manage on public.categories for all using (public.can_manage()) with check (public.can_manage());

-- Éléments de catégories.
drop policy if exists items_select on public.category_items;
create policy items_select on public.category_items for select using (true);
drop policy if exists items_manage on public.category_items;
create policy items_manage on public.category_items for all using (public.can_manage()) with check (public.can_manage());

-- Publications : lecture publique, création connectée, suppression par auteur ou responsable.
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select using (true);
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert with check (auth.uid() = author_id);
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete using (auth.uid() = author_id or public.can_manage());

-- Après création de ton premier compte, remplace TON_USER_ID et exécute :
-- update public.profiles set role = 'fondateur', username = 'Tayron' where id = 'TON_USER_ID';
