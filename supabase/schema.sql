-- HUB DE MIIANA — schéma Supabase
-- À exécuter dans Supabase > SQL Editor > Run

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('fondateur','co_fondateur','admin','staff','helpeur','membre');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  role public.user_role not null default 'membre',
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  icon text default '📁',
  position integer not null default 0,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.category_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  title text not null,
  description text,
  link text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.category_items enable row level security;

create or replace function public.current_user_role()
returns public.user_role
language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid(); $$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.current_user_role() in ('fondateur','co_fondateur','admin','staff','helpeur'), false); $$;

-- Profils
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
for select to authenticated using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
for insert to authenticated with check (id = auth.uid());

-- Pas de UPDATE direct sur profiles : les rôles passent par set_user_role().
drop policy if exists profiles_update_staff on public.profiles;

-- Tout membre connecté peut lire les catégories et leur contenu.
drop policy if exists categories_select_authenticated on public.categories;
create policy categories_select_authenticated on public.categories
for select to authenticated using (true);

drop policy if exists category_items_select_authenticated on public.category_items;
create policy category_items_select_authenticated on public.category_items
for select to authenticated using (true);

-- Création/modification/suppression réservées au staff.
drop policy if exists categories_insert_staff on public.categories;
create policy categories_insert_staff on public.categories
for insert to authenticated with check (public.is_staff() and created_by = auth.uid());

drop policy if exists categories_update_staff on public.categories;
create policy categories_update_staff on public.categories
for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists categories_delete_staff on public.categories;
create policy categories_delete_staff on public.categories
for delete to authenticated using (public.is_staff());

drop policy if exists category_items_insert_staff on public.category_items;
create policy category_items_insert_staff on public.category_items
for insert to authenticated with check (public.is_staff() and created_by = auth.uid());

drop policy if exists category_items_update_staff on public.category_items;
create policy category_items_update_staff on public.category_items
for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists category_items_delete_staff on public.category_items;
create policy category_items_delete_staff on public.category_items
for delete to authenticated using (public.is_staff());

-- Création automatique d'un profil à l'inscription.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, role)
  values (new.id, split_part(coalesce(new.email,'membre'), '@', 1), 'membre')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Gestion sécurisée des rôles depuis le panneau Admin.
-- Fondateur : peut attribuer tous les rôles.
-- Co-Fondateur : peut gérer admin/staff/helpeur/membre/co-fondateur, mais pas créer
-- ou remplacer un Fondateur.
create or replace function public.set_user_role(target_user_id uuid, new_role public.user_role)
returns public.user_role
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role public.user_role;
  target_role public.user_role;
begin
  select role into actor_role from public.profiles where id = auth.uid();
  select role into target_role from public.profiles where id = target_user_id;

  if actor_role is null then
    raise exception 'Profil introuvable';
  end if;

  if actor_role = 'fondateur' then
    null;
  elsif actor_role = 'co_fondateur' then
    if new_role = 'fondateur' or target_role = 'fondateur' then
      raise exception 'Le Co-Fondateur ne peut pas modifier le Fondateur';
    end if;
  else
    raise exception 'Permission refusée';
  end if;

  update public.profiles set role = new_role where id = target_user_id;
  if not found then raise exception 'Membre introuvable'; end if;
  return new_role;
end;
$$;

grant execute on function public.set_user_role(uuid, public.user_role) to authenticated;

-- Après avoir créé ton compte, exécute UNE FOIS cette ligne en remplaçant EMAIL_FONDATEUR.
-- update public.profiles set role = 'fondateur'
-- where id = (select id from auth.users where email = 'EMAIL_FONDATEUR');
