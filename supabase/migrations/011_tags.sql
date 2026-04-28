-- Теги постов (#cs2, #скины, ...). Парсинг хэштегов — на клиенте, сервер только хранит.

create extension if not exists citext;

create table if not exists public."Tag" (
  id          bigserial primary key,
  name        citext not null unique,
  kind        text not null default 'topic' check (kind in ('game','topic')),
  created_at  timestamptz not null default now()
);

create table if not exists public."Post_tag" (
  post_id  bigint not null references public."Post"(id) on delete cascade,
  tag_id   bigint not null references public."Tag"(id)  on delete cascade,
  primary key (post_id, tag_id)
);

create index if not exists post_tag_tag_idx on public."Post_tag" (tag_id, post_id desc);

alter table public."Tag"      enable row level security;
alter table public."Post_tag" enable row level security;

drop policy if exists "Tag read all" on public."Tag";
create policy "Tag read all"
  on public."Tag" for select using (true);

drop policy if exists "Tag insert authenticated" on public."Tag";
create policy "Tag insert authenticated"
  on public."Tag" for insert with check (auth.uid() is not null);

drop policy if exists "Post_tag read all" on public."Post_tag";
create policy "Post_tag read all"
  on public."Post_tag" for select using (true);

drop policy if exists "Post_tag insert own post" on public."Post_tag";
create policy "Post_tag insert own post"
  on public."Post_tag" for insert
  with check (
    exists (
      select 1 from public."Post" p
      where p.id = post_id and p.user_id = auth.uid()
    )
  );

drop policy if exists "Post_tag delete own post" on public."Post_tag";
create policy "Post_tag delete own post"
  on public."Post_tag" for delete
  using (
    exists (
      select 1 from public."Post" p
      where p.id = post_id and p.user_id = auth.uid()
    )
  );

-- Популярные теги за последние 30 дней (для чипов в ленте).
create or replace view public."Tag_popular" as
select
  t.id,
  t.name,
  t.kind,
  count(pt.post_id) as uses
from public."Tag" t
left join public."Post_tag" pt on pt.tag_id = t.id
left join public."Post" p on p.id = pt.post_id
  and p.created_at >= now() - interval '30 days'
group by t.id, t.name, t.kind
order by uses desc;

grant select on public."Tag_popular" to anon, authenticated;
