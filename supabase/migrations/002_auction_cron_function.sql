-- Фоновое завершение аукционов на стороне БД.
-- 1) Выполнить этот скрипт в Supabase SQL Editor.
-- 2) Включить расширение pg_cron: Database → Extensions → pg_cron.
-- 3) Запланировать (раз в минуту):
--    select cron.schedule(
--      'finalize-expired-auctions',
--      '* * * * *',
--      $$ select public.finalize_expired_auctions_sql(); $$
--    );
--
-- Имена таблиц приведи к фактическим (регистр) в твоей базе: Auction_items, Bid_auction.

CREATE OR REPLACE FUNCTION public.finalize_expired_auctions_sql()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "Auction_items" AS a
  SET
    is_active = false,
    winner_id = w.uid
  FROM (
    SELECT
      a2.id AS aid,
      (
        SELECT b.user_id
        FROM "Bid_auction" b
        WHERE b.auction_id = a2.id
        ORDER BY b.new_price DESC
        LIMIT 1
      ) AS uid
    FROM "Auction_items" a2
    WHERE a2.is_active
      AND a2.ended_at <= now()
  ) AS w
  WHERE a.id = w.aid;
END;
$$;
