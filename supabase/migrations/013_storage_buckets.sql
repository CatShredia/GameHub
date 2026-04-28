-- Бакеты для голосовых/вложений/медиа в чате и ленте. Публичное чтение, запись только owner.
-- Выполни в Supabase SQL Editor. Если бакет создан через UI — INSERT для него не сработает, это норма.

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do update set public = excluded.public;

-- Пути: {bucket}/{userId}/{uuid}.{ext}. Первый сегмент (foldername[1]) — uuid пользователя.

drop policy if exists "chat-media read" on storage.objects;
create policy "chat-media read"
  on storage.objects for select
  using (bucket_id = 'chat-media');

drop policy if exists "chat-media upload own" on storage.objects;
create policy "chat-media upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "chat-media update own" on storage.objects;
create policy "chat-media update own"
  on storage.objects for update
  using (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "chat-media delete own" on storage.objects;
create policy "chat-media delete own"
  on storage.objects for delete
  using (
    bucket_id = 'chat-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media read" on storage.objects;
create policy "post-media read"
  on storage.objects for select
  using (bucket_id = 'post-media');

drop policy if exists "post-media upload own" on storage.objects;
create policy "post-media upload own"
  on storage.objects for insert
  with check (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media update own" on storage.objects;
create policy "post-media update own"
  on storage.objects for update
  using (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media delete own" on storage.objects;
create policy "post-media delete own"
  on storage.objects for delete
  using (
    bucket_id = 'post-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
