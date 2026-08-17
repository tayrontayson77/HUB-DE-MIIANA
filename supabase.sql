-- HUB DE MIIANA - Supabase / rôles + catégories privées
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Membre',
  role text not null default 'membre',
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  icon text default '📁',
  visibility text not null default 'public',
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

-- Migration pour une base déjà créée
alter table public.profiles add column if not exists role text default 'membre';
alter table public.categories add column if not exists visibility text default 'public';

-- Normalise les rôles existants
update public.profiles set role='membre' where role is null;
update public.categories set visibility='public' where visibility is null;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.category_items enable row level security;
alter table public.posts enable row level security;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public
as $$ select coalesce((select role from public.profiles where id=auth.uid()), 'membre') $$;

create or replace function public.role_rank(r text)
returns integer language sql immutable
as $$ select case r when 'membre' then 0 when 'helper' then 1 when 'helpeur' then 1 when 'moderateur' then 2 when 'staff' then 3 when 'admin' then 4 when 'co-fonda' then 5 when 'direction' then 5 when 'fondateur' then 6 else 0 end $$;

create or replace function public.can_manage()
returns boolean language sql stable security definer set search_path = public
as $$ select public.my_role() in ('fondateur','co-fonda','admin') $$;

-- Lecture des profils
 drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select using (true);
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert with check (id=auth.uid() or public.can_manage());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update using (id=auth.uid() or public.can_manage()) with check (id=auth.uid() or public.can_manage());

-- Catégories : le rôle détermine la visibilité
drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories for select using (
  visibility='public'
  or public.role_rank(public.my_role()) >= public.role_rank(visibility)
  or (visibility='direction' and public.my_role() in ('direction','fondateur','co-fonda','admin'))
);
drop policy if exists categories_manage on public.categories;
create policy categories_manage on public.categories for all using (public.can_manage()) with check (public.can_manage());

-- Contenu d'une catégorie : seulement si l'utilisateur peut voir la catégorie
drop policy if exists items_select on public.category_items;
create policy items_select on public.category_items for select using (
  exists (select 1 from public.categories c where c.id=category_id and (
    c.visibility='public' or public.role_rank(public.my_role()) >= public.role_rank(c.visibility)
    or (c.visibility='direction' and public.my_role() in ('direction','fondateur','co-fonda','admin'))
  ))
);
drop policy if exists items_manage on public.category_items;
create policy items_manage on public.category_items for all using (public.can_manage()) with check (public.can_manage());

-- Publications
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select using (true);
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert with check (auth.uid()=author_id);
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete using (auth.uid()=author_id or public.can_manage());

-- Après création du compte fondateur, remplace TON_USER_ID par son UUID :
-- update public.profiles set role='fondateur', username='Tayron' where id='TON_USER_ID';
