-- Рейтинги участников аукциона: покупатель оценивает продавца, продавец — покупателя.
-- Выполни в Supabase SQL Editor.

create table if not exists public."User_rating" (
  id          bigserial primary key,
  rater_id    uuid not null references auth.users(id) on delete cascade,
  target_id   uuid not null references auth.users(id) on delete cascade,
  auction_id  bigint not null references public."Auction_items"(id) on delete cascade,
  role        text not null check (role in ('seller','buyer')),
  stars       smallint not null check (stars between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now(),
  constraint user_rating_unique_per_auction
    unique (rater_id, auction_id, role),
  constraint user_rating_not_self
    check (rater_id <> target_id)
);

create index if not exists user_rating_target_idx
  on public."User_rating" (target_id, created_at desc);

alter table public."User_rating" enable row level security;

drop policy if exists "User_rating read all" on public."User_rating";
create policy "User_rating read all"
  on public."User_rating"
  for select
  using (true);

drop policy if exists "User_rating insert own" on public."User_rating";
create policy "User_rating insert own"
  on public."User_rating"
  for insert
  with check (auth.uid() = rater_id);

drop policy if exists "User_rating update own" on public."User_rating";
create policy "User_rating update own"
  on public."User_rating"
  for update
  using (auth.uid() = rater_id)
  with check (auth.uid() = rater_id);

drop policy if exists "User_rating delete own" on public."User_rating";
create policy "User_rating delete own"
  on public."User_rating"
  for delete
  using (auth.uid() = rater_id);

create or replace view public."User_rating_stats" as
select
  target_id       as user_id,
  round(avg(stars)::numeric, 2) as avg_stars,
  count(*)        as ratings_count
from public."User_rating"
group by target_id;

grant select on public."User_rating_stats" to anon, authenticated;
