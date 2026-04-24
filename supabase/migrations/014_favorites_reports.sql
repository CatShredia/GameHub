-- Закладки (Favorite) и жалобы (Report).
-- Favorite: пользователь сохраняет себе пост или аукцион.
-- Report: пользователь жалуется на пост/аукцион/другого пользователя.

create table if not exists public."Favorite" (
  id          bigserial primary key,
  user_id     uuid   not null references auth.users(id) on delete cascade,
  kind        text   not null check (kind in ('post','auction')),
  ref_id      bigint not null,
  created_at  timestamptz not null default now(),
  constraint favorite_unique unique (user_id, kind, ref_id)
);

create index if not exists favorite_user_idx
  on public."Favorite" (user_id, created_at desc);

alter table public."Favorite" enable row level security;

drop policy if exists "Favorite read own" on public."Favorite";
create policy "Favorite read own"
  on public."Favorite" for select
  using (auth.uid() = user_id);

drop policy if exists "Favorite insert own" on public."Favorite";
create policy "Favorite insert own"
  on public."Favorite" for insert
  with check (auth.uid() = user_id);

drop policy if exists "Favorite delete own" on public."Favorite";
create policy "Favorite delete own"
  on public."Favorite" for delete
  using (auth.uid() = user_id);

create table if not exists public."Report" (
  id          bigserial primary key,
  reporter_id uuid   not null references auth.users(id) on delete cascade,
  target_kind text   not null check (target_kind in ('post','auction','user','message')),
  target_id   text   not null,
  reason      text   not null,
  comment     text,
  status      text   not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at  timestamptz not null default now()
);

create index if not exists report_target_idx
  on public."Report" (target_kind, target_id, created_at desc);

create index if not exists report_reporter_idx
  on public."Report" (reporter_id, created_at desc);

alter table public."Report" enable row level security;

drop policy if exists "Report insert own" on public."Report";
create policy "Report insert own"
  on public."Report" for insert
  with check (auth.uid() = reporter_id);

drop policy if exists "Report read own" on public."Report";
create policy "Report read own"
  on public."Report" for select
  using (auth.uid() = reporter_id);
