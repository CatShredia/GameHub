-- Демо-данные GameHub: 5 пользователей и заполнение всех таблиц.
-- Пароль для всех: GameHub123!
-- Запуск: Get-Content supabase/seed/024_demo_seed.sql -Raw | npx supabase db query --linked

begin;

create extension if not exists pgcrypto;

-- ========== ОЧИСТКА ==========
truncate table
  public."User_rating",
  public."Bid_auction",
  public."Auction_items",
  public."Favorite",
  public."Report",
  public."PostLike",
  public."Post_tag",
  public."Comment",
  public."Post",
  public."Message",
  public."ChatMember",
  public."ChatNotificationMute",
  public."Chat",
  public."Notification",
  public."NotificationPreference",
  public."DevicePushToken",
  public."Payment",
  public."Tag"
restart identity cascade;

delete from public."User";
delete from auth.identities;
delete from auth.users;

-- Категории ленты (справочник)
insert into public."PostCategory" (name, sort_order)
values
  ('Новости', 10),
  ('Обзоры', 20),
  ('Гайды', 30),
  ('Аукционы', 40),
  ('Обсуждение', 50)
on conflict (name) do nothing;

-- ========== 5 ПОЛЬЗОВАТЕЛЕЙ (auth + User) ==========
-- u1 Алиса, u2 Борис, u3 Катя, u4 Дмитрий, u5 Елена
do $seed$
declare
  v_instance uuid := coalesce(
    (select instance_id from auth.users limit 1),
    '00000000-0000-0000-0000-000000000000'::uuid
  );
  pwd text := crypt('GameHub123!', gen_salt('bf'));
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, recovery_sent_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
  ('a1000000-0000-4000-8000-000000000001', v_instance, 'authenticated', 'authenticated',
   'alice@gamehub.demo', pwd, now(), now(), now(),
   '{"provider":"email","providers":["email"]}'::jsonb,
   '{"username":"Алиса"}'::jsonb, now() - interval '120 days', now(), '', '', '', ''),
  ('a2000000-0000-4000-8000-000000000002', v_instance, 'authenticated', 'authenticated',
   'boris@gamehub.demo', pwd, now(), now(), now(),
   '{"provider":"email","providers":["email"]}'::jsonb,
   '{"username":"Борис"}'::jsonb, now() - interval '90 days', now(), '', '', '', ''),
  ('a3000000-0000-4000-8000-000000000003', v_instance, 'authenticated', 'authenticated',
   'katya@gamehub.demo', pwd, now(), now(), now(),
   '{"provider":"email","providers":["email"]}'::jsonb,
   '{"username":"Катя"}'::jsonb, now() - interval '60 days', now(), '', '', '', ''),
  ('a4000000-0000-4000-8000-000000000004', v_instance, 'authenticated', 'authenticated',
   'dmitry@gamehub.demo', pwd, now(), now(), now(),
   '{"provider":"email","providers":["email"]}'::jsonb,
   '{"username":"Дмитрий"}'::jsonb, now() - interval '45 days', now(), '', '', '', ''),
  ('a5000000-0000-4000-8000-000000000005', v_instance, 'authenticated', 'authenticated',
   'elena@gamehub.demo', pwd, now(), now(), now(),
   '{"provider":"email","providers":["email"]}'::jsonb,
   '{"username":"Елена"}'::jsonb, now() - interval '30 days', now(), '', '', '', '');

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) values
  (gen_random_uuid(), 'a1000000-0000-4000-8000-000000000001',
   '{"sub":"a1000000-0000-4000-8000-000000000001","email":"alice@gamehub.demo"}'::jsonb,
   'email', 'a1000000-0000-4000-8000-000000000001', now(), now(), now()),
  (gen_random_uuid(), 'a2000000-0000-4000-8000-000000000002',
   '{"sub":"a2000000-0000-4000-8000-000000000002","email":"boris@gamehub.demo"}'::jsonb,
   'email', 'a2000000-0000-4000-8000-000000000002', now(), now(), now()),
  (gen_random_uuid(), 'a3000000-0000-4000-8000-000000000003',
   '{"sub":"a3000000-0000-4000-8000-000000000003","email":"katya@gamehub.demo"}'::jsonb,
   'email', 'a3000000-0000-4000-8000-000000000003', now(), now(), now()),
  (gen_random_uuid(), 'a4000000-0000-4000-8000-000000000004',
   '{"sub":"a4000000-0000-4000-8000-000000000004","email":"dmitry@gamehub.demo"}'::jsonb,
   'email', 'a4000000-0000-4000-8000-000000000004', now(), now(), now()),
  (gen_random_uuid(), 'a5000000-0000-4000-8000-000000000005',
   '{"sub":"a5000000-0000-4000-8000-000000000005","email":"elena@gamehub.demo"}'::jsonb,
   'email', 'a5000000-0000-4000-8000-000000000005', now(), now(), now());
end $seed$;

insert into public."User" (id, email, login, username, scope, avatar, date_of_birth, created_at)
values
  ('a1000000-0000-4000-8000-000000000001', 'alice@gamehub.demo', 'alice',
   'Алиса', 3200,
   'https://api.dicebear.com/7.x/avataaars/svg?seed=alice',
   '1998-03-12', now() - interval '120 days'),
  ('a2000000-0000-4000-8000-000000000002', 'boris@gamehub.demo', 'boris',
   'Борис', 1850,
   'https://api.dicebear.com/7.x/avataaars/svg?seed=boris',
   '1995-07-22', now() - interval '90 days'),
  ('a3000000-0000-4000-8000-000000000003', 'katya@gamehub.demo', 'katya',
   'Катя', 2400,
   'https://api.dicebear.com/7.x/avataaars/svg?seed=katya',
   '1999-11-05', now() - interval '60 days'),
  ('a4000000-0000-4000-8000-000000000004', 'dmitry@gamehub.demo', 'dmitry',
   'Дмитрий', 980,
   'https://api.dicebear.com/7.x/avataaars/svg?seed=dmitry',
   '1996-01-18', now() - interval '45 days'),
  ('a5000000-0000-4000-8000-000000000005', 'elena@gamehub.demo', 'elena',
   'Елена', 4100,
   'https://api.dicebear.com/7.x/avataaars/svg?seed=elena',
   '1997-09-30', now() - interval '30 days');

-- ========== ТЕГИ ==========
insert into public."Tag" (name, kind) values
  ('cs2', 'game'),
  ('dota2', 'game'),
  ('инди', 'topic'),
  ('скидки', 'topic'),
  ('гайд', 'topic')
on conflict (name) do nothing;

-- ========== ПОСТЫ ==========
insert into public."Post" (id, user_id, content, "like", category_id, created_at)
overriding system value values
  (1, 'a1000000-0000-4000-8000-000000000001',
   'Кто играл в Hades 2? Для меня это лучший #инди релиз года 🔥', 12,
   (select id from public."PostCategory" where name = 'Обзоры'), now() - interval '5 days'),
  (2, 'a2000000-0000-4000-8000-000000000002',
   'Собрал пачку #скидок на Steam — делюсь в комментариях', 7,
   (select id from public."PostCategory" where name = 'Новости'), now() - interval '4 days'),
  (3, 'a3000000-0000-4000-8000-000000000003',
   '#гайд: как не переплатить за ключи и не попасть на скам', 19,
   (select id from public."PostCategory" where name = 'Гайды'), now() - interval '3 days'),
  (4, 'a4000000-0000-4000-8000-000000000004',
   'Ищу напарника в #cs2 на вечер, ранг Gold Nova', 4,
   (select id from public."PostCategory" where name = 'Обсуждение'), now() - interval '2 days'),
  (5, 'a5000000-0000-4000-8000-000000000005',
   'Прошла Baldur''s Gate 3 второй раз — всё ещё 10/10', 25,
   (select id from public."PostCategory" where name = 'Обзоры'), now() - interval '1 day'),
  (6, 'a1000000-0000-4000-8000-000000000001',
   'Кто-нибудь торгует скинами в #dota2? Нужен совет по цене', 6,
   (select id from public."PostCategory" where name = 'Обсуждение'), now() - interval '12 hours');

insert into public."Post_tag" (post_id, tag_id)
select p.id, t.id
from (values
  (1, 'инди'),
  (2, 'скидки'),
  (3, 'гайд'),
  (4, 'cs2'),
  (5, 'инди'),
  (6, 'dota2')
) as x(post_id, tag_name)
join public."Post" p on p.id = x.post_id
join public."Tag" t on t.name = x.tag_name::citext;

insert into public."PostLike" (user_id, post_id, created_at) values
  ('a2000000-0000-4000-8000-000000000002', 1, now() - interval '4 days'),
  ('a3000000-0000-4000-8000-000000000003', 1, now() - interval '4 days'),
  ('a5000000-0000-4000-8000-000000000005', 1, now() - interval '3 days'),
  ('a1000000-0000-4000-8000-000000000001', 3, now() - interval '2 days'),
  ('a4000000-0000-4000-8000-000000000004', 5, now() - interval '1 day'),
  ('a2000000-0000-4000-8000-000000000002', 5, now() - interval '1 day');

-- ========== КОММЕНТАРИИ (с ответом) ==========
insert into public."Comment" (id, user_id, post_id, content, parent_comment_id, created_at)
overriding system value values
  (1, 'a2000000-0000-4000-8000-000000000002', 1,
   'Hades 2 уже в раннем доступе, советую!', null, now() - interval '4 days 20 hours'),
  (2, 'a3000000-0000-4000-8000-000000000003', 1,
   'Согласна, саундтрек огонь', 1, now() - interval '4 days 18 hours'),
  (3, 'a4000000-0000-4000-8000-000000000004', 4,
   'Могу зайти после 20:00, пиши в личку', null, now() - interval '1 day 5 hours'),
  (4, 'a5000000-0000-4000-8000-000000000005', 3,
   'Спасибо за гайд, очень полезно!', null, now() - interval '2 days');

-- ========== ЧАТЫ ==========
insert into public."Chat" (id, namechat, descriptions, type_chat, created_at)
overriding system value values
  (1, 'Личный чат', null, 'private', now() - interval '10 days'),
  (2, 'Личный чат', null, 'private', now() - interval '8 days'),
  (3, 'GameHub Новости', 'Официальные новости и анонсы', 'channel', now() - interval '30 days'),
  (4, 'CS2 Трейды', 'Обмен скинами и поиск тиммейтов', 'group', now() - interval '20 days'),
  (5, 'Личный чат', null, 'private', now() - interval '3 days');

insert into public."ChatMember" (user_id, chat_id, role, created_at) values
  ('a1000000-0000-4000-8000-000000000001', 1, 'member', now() - interval '10 days'),
  ('a2000000-0000-4000-8000-000000000002', 1, 'member', now() - interval '10 days'),
  ('a1000000-0000-4000-8000-000000000001', 2, 'member', now() - interval '8 days'),
  ('a3000000-0000-4000-8000-000000000003', 2, 'member', now() - interval '8 days'),
  ('a1000000-0000-4000-8000-000000000001', 3, 'member', now() - interval '30 days'),
  ('a2000000-0000-4000-8000-000000000002', 3, 'member', now() - interval '25 days'),
  ('a3000000-0000-4000-8000-000000000003', 3, 'member', now() - interval '20 days'),
  ('a4000000-0000-4000-8000-000000000004', 3, 'member', now() - interval '15 days'),
  ('a5000000-0000-4000-8000-000000000005', 3, 'member', now() - interval '10 days'),
  ('a2000000-0000-4000-8000-000000000002', 4, 'member', now() - interval '20 days'),
  ('a4000000-0000-4000-8000-000000000004', 4, 'member', now() - interval '18 days'),
  ('a4000000-0000-4000-8000-000000000004', 5, 'member', now() - interval '3 days'),
  ('a5000000-0000-4000-8000-000000000005', 5, 'member', now() - interval '3 days');

insert into public."Message" (chat_id, sender_id, content, status, is_delete, created_at) values
  (1, 'a1000000-0000-4000-8000-000000000001', 'Привет! Видел твой пост про скидки 👋', true, false, now() - interval '9 days'),
  (1, 'a2000000-0000-4000-8000-000000000002', 'Привет! Да, завтра скину список', true, false, now() - interval '9 days' + interval '5 minutes'),
  (1, 'a1000000-0000-4000-8000-000000000001', 'Супер, жду', true, false, now() - interval '9 days' + interval '6 minutes'),
  (2, 'a3000000-0000-4000-8000-000000000003', 'Алиса, зайдёшь в BG3 кооп?', true, false, now() - interval '2 days'),
  (2, 'a1000000-0000-4000-8000-000000000001', 'Давай в субботу вечером!', true, false, now() - interval '2 days' + interval '10 minutes'),
  (3, 'a5000000-0000-4000-8000-000000000005', 'Вышло обновление GameHub — проверяйте ленту 🎮', true, false, now() - interval '1 day'),
  (4, 'a4000000-0000-4000-8000-000000000004', 'Кто на Mirage сегодня?', true, false, now() - interval '6 hours'),
  (5, 'a5000000-0000-4000-8000-000000000005', 'Дмитрий, спасибо за сделку!', true, false, now() - interval '1 day');

insert into public."ChatNotificationMute" (user_id, chat_id, created_at) values
  ('a4000000-0000-4000-8000-000000000004', 4, now() - interval '5 days');

-- ========== АУКЦИОНЫ (исторические данные в БД) ==========
insert into public."Auction_items" (
  id, owner_id, url_item, title, start_price, is_active, ended_at, winner_id, bid_count, steam_key, created_at
)
overriding system value values
  (1, 'a2000000-0000-4000-8000-000000000002',
   'https://cdn.akamai.steamstatic.com/steam/apps/730/header.jpg',
   'Counter-Strike 2', 500, true,
   (now() + interval '2 days')::timestamp, null, 2, 'DEMO-KEY-CS2-001', now() - interval '1 day'),
  (2, 'a5000000-0000-4000-8000-000000000005',
   'https://cdn.akamai.steamstatic.com/steam/apps/570/header.jpg',
   'Dota 2', 300, true,
   (now() + interval '5 days')::timestamp, null, 1, 'DEMO-KEY-DOTA-001', now() - interval '12 hours'),
  (3, 'a1000000-0000-4000-8000-000000000001',
   'https://cdn.akamai.steamstatic.com/steam/apps/1091500/header.jpg',
   'Cyberpunk 2077', 800, false,
   (now() - interval '3 days')::timestamp,
   'a3000000-0000-4000-8000-000000000003', 4, 'DEMO-KEY-CP2077', now() - interval '10 days'),
  (4, 'a4000000-0000-4000-8000-000000000004',
   'https://cdn.akamai.steamstatic.com/steam/apps/1174180/header.jpg',
   'Red Dead Redemption 2', 600, false,
   (now() - interval '7 days')::timestamp,
   'a2000000-0000-4000-8000-000000000002', 3, 'DEMO-KEY-RDR2', now() - interval '14 days');

insert into public."Bid_auction" (user_id, auction_id, new_price, created_at) values
  ('a3000000-0000-4000-8000-000000000003', 1, 550, now() - interval '20 hours'),
  ('a4000000-0000-4000-8000-000000000004', 1, 600, now() - interval '18 hours'),
  ('a1000000-0000-4000-8000-000000000001', 2, 350, now() - interval '6 hours'),
  ('a3000000-0000-4000-8000-000000000003', 3, 850, now() - interval '4 days'),
  ('a5000000-0000-4000-8000-000000000005', 3, 900, now() - interval '3 days 20 hours'),
  ('a3000000-0000-4000-8000-000000000003', 3, 950, now() - interval '3 days 18 hours'),
  ('a2000000-0000-4000-8000-000000000002', 4, 650, now() - interval '8 days'),
  ('a5000000-0000-4000-8000-000000000005', 4, 700, now() - interval '7 days 12 hours');

insert into public."User_rating" (rater_id, target_id, auction_id, role, stars, comment, created_at) values
  ('a3000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', 3, 'seller', 5,
   'Ключ пришёл моментально, спасибо!', now() - interval '2 days'),
  ('a1000000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000003', 3, 'buyer', 5,
   'Быстрая оплата, приятное общение', now() - interval '2 days'),
  ('a2000000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-000000000004', 4, 'seller', 4,
   'Всё ок, небольшая задержка с ответом', now() - interval '6 days'),
  ('a4000000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-000000000002', 4, 'buyer', 5,
   'Надёжный продавец', now() - interval '6 days');

-- ========== ЗАКЛАДКИ, ЖАЛОБЫ, ПЛАТЕЖИ ==========
insert into public."Favorite" (user_id, kind, ref_id, created_at) values
  ('a2000000-0000-4000-8000-000000000002', 'post', 3, now() - interval '2 days'),
  ('a4000000-0000-4000-8000-000000000004', 'post', 5, now() - interval '1 day'),
  ('a3000000-0000-4000-8000-000000000003', 'auction', 1, now() - interval '3 hours');

insert into public."Report" (reporter_id, target_kind, target_id, reason, comment, status, created_at) values
  ('a5000000-0000-4000-8000-000000000005', 'post', '4', 'spam', 'Повторяющиеся приглашения в игру', 'open', now() - interval '1 day');

insert into public."Payment" (user_id, stripe_payment_intent_id, amount_minor, currency, points, status, metadata, created_at) values
  ('a1000000-0000-4000-8000-000000000001', 'pi_demo_alice_001', 49900, 'rub', 500, 'succeeded', '{"source":"demo"}'::jsonb, now() - interval '30 days'),
  ('a5000000-0000-4000-8000-000000000005', 'pi_demo_elena_001', 99900, 'rub', 1000, 'succeeded', '{"source":"demo"}'::jsonb, now() - interval '15 days'),
  ('a4000000-0000-4000-8000-000000000004', 'pi_demo_dmitry_001', 29900, 'rub', 300, 'pending', '{"source":"demo"}'::jsonb, now() - interval '2 days');

insert into public."DevicePushToken" (user_id, token, platform, created_at, updated_at) values
  ('a1000000-0000-4000-8000-000000000001', 'fcm_demo_token_alice', 'android', now(), now()),
  ('a3000000-0000-4000-8000-000000000003', 'fcm_demo_token_katya', 'android', now(), now());

-- ========== УВЕДОМЛЕНИЯ ==========
insert into public."Notification" (user_id, type, title, content, payload, is_watched, created_at) values
  ('a1000000-0000-4000-8000-000000000001', 'new_message', 'Новое сообщение',
   'Борис: Да, завтра скину список',
   '{"chat_id":1,"sender_id":"a2000000-0000-4000-8000-000000000002"}'::jsonb, false, now() - interval '9 days'),
  ('a2000000-0000-4000-8000-000000000002', 'new_bid', 'Новая ставка',
   'Ставка 600 ⭐ на Counter-Strike 2',
   '{"auction_id":1,"bidder_id":"a4000000-0000-4000-8000-000000000004","new_price":600}'::jsonb, true, now() - interval '18 hours'),
  ('a1000000-0000-4000-8000-000000000001', 'auction_ended', 'Аукцион завершён',
   'Cyberpunk 2077 — победитель @katya',
   '{"auction_id":3}'::jsonb, true, now() - interval '3 days'),
  ('a3000000-0000-4000-8000-000000000003', 'new_rating', 'Новая оценка',
   'Алиса оценила вас на 5 ⭐',
   '{"stars":5,"auction_id":3}'::jsonb, false, now() - interval '2 days'),
  ('a4000000-0000-4000-8000-000000000004', 'new_message', 'Новое сообщение',
   'Елена: Дмитрий, спасибо за сделку!',
   '{"chat_id":5}'::jsonb, false, now() - interval '1 day');

insert into public."NotificationPreference" (user_id, chats_enabled, auctions_enabled, feed_enabled, updated_at)
values
  ('a1000000-0000-4000-8000-000000000001', true, true, true, now()),
  ('a2000000-0000-4000-8000-000000000002', true, false, true, now()),
  ('a3000000-0000-4000-8000-000000000003', true, true, true, now()),
  ('a4000000-0000-4000-8000-000000000004', true, true, false, now()),
  ('a5000000-0000-4000-8000-000000000005', false, true, true, now());

-- Сброс sequences
select setval(pg_get_serial_sequence('public."Post"', 'id'), (select coalesce(max(id), 1) from public."Post"));
select setval(pg_get_serial_sequence('public."Comment"', 'id'), (select coalesce(max(id), 1) from public."Comment"));
select setval(pg_get_serial_sequence('public."Chat"', 'id'), (select coalesce(max(id), 1) from public."Chat"));
select setval(pg_get_serial_sequence('public."ChatMember"', 'id'), (select coalesce(max(id), 1) from public."ChatMember"));
select setval(pg_get_serial_sequence('public."Message"', 'id'), (select coalesce(max(id), 1) from public."Message"));
select setval(pg_get_serial_sequence('public."Auction_items"', 'id'), (select coalesce(max(id), 1) from public."Auction_items"));
select setval(pg_get_serial_sequence('public."Bid_auction"', 'id'), (select coalesce(max(id), 1) from public."Bid_auction"));
select setval(pg_get_serial_sequence('public."PostLike"', 'id'), (select coalesce(max(id), 1) from public."PostLike"));
select setval(pg_get_serial_sequence('public."Notification"', 'id'), (select coalesce(max(id), 1) from public."Notification"));

commit;
