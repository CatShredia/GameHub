-- В схеме из "Supabase BD.txt" на [Bid_auction.new_price] стоит UNIQUE глобально — разные аукционы
-- не смогут иметь одинаковую сумму ставки. Выполните в SQL Editor Supabase:

ALTER TABLE public."Bid_auction" DROP CONSTRAINT IF EXISTS "Bid_auction_new_price_key";

CREATE UNIQUE INDEX IF NOT EXISTS bid_auction_auction_new_price_unique
  ON public."Bid_auction" (auction_id, new_price);
