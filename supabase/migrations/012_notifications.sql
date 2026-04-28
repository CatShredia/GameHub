-- In-app уведомления (Supabase Realtime). Всё локальное: без FCM/OneSignal.
-- Типы: new_message, new_bid, auction_won, auction_ended, new_rating.

create table if not exists public."Notification" (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null default 'new_message',
  payload     jsonb not null default '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- На случай старой версии таблицы (title/content/is_watched) — добиваем новые колонки.
alter table public."Notification"
  add column if not exists type       text        not null default 'new_message',
  add column if not exists payload    jsonb       not null default '{}'::jsonb,
  add column if not exists read_at    timestamptz;

create index if not exists notification_user_unread_idx
  on public."Notification" (user_id, read_at, created_at desc);

alter table public."Notification" enable row level security;

drop policy if exists "Notification read own" on public."Notification";
create policy "Notification read own"
  on public."Notification" for select
  using (auth.uid() = user_id);

drop policy if exists "Notification update own" on public."Notification";
create policy "Notification update own"
  on public."Notification" for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Notification delete own" on public."Notification";
create policy "Notification delete own"
  on public."Notification" for delete
  using (auth.uid() = user_id);

-- insert выполняют триггеры (security definer), обычные клиенты вставлять не должны.

-- =================== Триггеры ===================

-- 1) Новое сообщение → уведомление всем участникам чата, кроме отправителя.
create or replace function public._notify_new_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public."Notification" (user_id, type, payload)
  select
    cm.user_id,
    'new_message',
    jsonb_build_object(
      'chat_id',    new.chat_id,
      'message_id', new.id,
      'sender_id',  new.sender_id,
      'preview',    left(coalesce(new.content,''), 120)
    )
  from public."ChatMember" cm
  where cm.chat_id = new.chat_id
    and cm.user_id <> new.sender_id;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_message on public."Message";
create trigger trg_notify_new_message
  after insert on public."Message"
  for each row execute function public._notify_new_message();

-- 2) Новая ставка → уведомление владельцу лота (если не он сам).
create or replace function public._notify_new_bid()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  owner uuid;
begin
  select owner_id into owner from public."Auction_items" where id = new.auction_id;
  if owner is null or owner = new.user_id then
    return new;
  end if;

  insert into public."Notification" (user_id, type, payload)
  values (
    owner,
    'new_bid',
    jsonb_build_object(
      'auction_id', new.auction_id,
      'bidder_id',  new.user_id,
      'new_price',  new.new_price
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_new_bid on public."Bid_auction";
create trigger trg_notify_new_bid
  after insert on public."Bid_auction"
  for each row execute function public._notify_new_bid();

-- 3) Аукцион завершён (winner_id только что установлен) → уведомления победителю и владельцу.
create or replace function public._notify_auction_finalized()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.winner_id is not null
     and (old.winner_id is null or old.winner_id <> new.winner_id) then

    insert into public."Notification" (user_id, type, payload)
    values (
      new.winner_id,
      'auction_won',
      jsonb_build_object('auction_id', new.id, 'owner_id', new.owner_id)
    );

    if new.owner_id is not null and new.owner_id <> new.winner_id then
      insert into public."Notification" (user_id, type, payload)
      values (
        new.owner_id,
        'auction_ended',
        jsonb_build_object('auction_id', new.id, 'winner_id', new.winner_id)
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_auction_finalized on public."Auction_items";
create trigger trg_notify_auction_finalized
  after update on public."Auction_items"
  for each row execute function public._notify_auction_finalized();

-- 4) Новый рейтинг → уведомление получателю.
create or replace function public._notify_new_rating()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public."Notification" (user_id, type, payload)
  values (
    new.target_id,
    'new_rating',
    jsonb_build_object(
      'rater_id',  new.rater_id,
      'auction_id', new.auction_id,
      'stars',     new.stars,
      'role',      new.role
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_new_rating on public."User_rating";
create trigger trg_notify_new_rating
  after insert on public."User_rating"
  for each row execute function public._notify_new_rating();
