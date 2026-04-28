-- Автосоздание профиля в public."User" при регистрации в auth.users.
-- Без этого триггера ProfileService падает с «Профиль не найден в базе данных»,
-- и все джойны User!user_id возвращают null.

create table if not exists public."User" (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text not null,
  login         text not null unique,
  email         text not null,
  password      text not null default '',
  avatar        text not null default '',
  scope         integer not null default 0,
  date_of_birth date,
  created_at    timestamptz not null default now()
);

-- Удобный помощник: уникальный login на основе желаемого значения.
create or replace function public._gh_unique_login(p_base text)
returns text
language plpgsql
as $$
declare
  v_base   text := lower(regexp_replace(coalesce(nullif(p_base, ''), 'user'), '[^a-z0-9_.]+', '_', 'gi'));
  v_try    text := v_base;
  v_suffix int  := 1;
begin
  -- Если вдруг стало пусто после очистки — fallback.
  if v_try is null or length(v_try) = 0 then
    v_try := 'user';
    v_base := v_try;
  end if;

  while exists (select 1 from public."User" where lower(login) = v_try) loop
    v_suffix := v_suffix + 1;
    v_try := v_base || v_suffix::text;
  end loop;

  return v_try;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
  v_login    text;
  v_email    text := coalesce(new.email, '');
begin
  -- Приоритет: raw_user_meta_data.username → часть email до @ → 'user'.
  v_username := coalesce(
    nullif(new.raw_user_meta_data ->> 'username', ''),
    nullif(split_part(v_email, '@', 1), ''),
    'user'
  );
  v_login := public._gh_unique_login(v_username);

  insert into public."User" (id, username, login, email, password, avatar, scope)
  values (
    new.id,
    v_username,
    v_login,
    v_email,
    '',
    coalesce(new.raw_user_meta_data ->> 'avatar', ''),
    0
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user();

-- Бэкфилл: создаём профили для уже зарегистрированных, но без записи в User.
insert into public."User" (id, username, login, email, password, avatar, scope)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'username', ''),
           nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
           'user') as username,
  public._gh_unique_login(
    coalesce(nullif(u.raw_user_meta_data ->> 'username', ''),
             nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
             'user')
  ) as login,
  coalesce(u.email, ''),
  '',
  coalesce(u.raw_user_meta_data ->> 'avatar', ''),
  0
from auth.users u
left join public."User" p on p.id = u.id
where p.id is null;
