-- 022_stripe_payments.sql
-- История платежей через Stripe + атомарное начисление баллов на User.points
--
-- Заметка: сам баланс остаётся в существующем поле public."User".points,
-- эта таблица хранит только историю транзакций.

create extension if not exists pgcrypto;

create table if not exists public."Payment" (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public."User"(id) on delete cascade,
  stripe_payment_intent_id text not null unique,
  amount_minor             integer not null,        -- сумма в минимальных единицах валюты (копейки)
  currency                 text not null,           -- 'rub', 'usd', ...
  points                   integer not null,        -- сколько баллов начислить
  status                   text not null default 'pending',  -- pending | succeeded | failed | canceled
  metadata                 jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index if not exists idx_payment_user on public."Payment"(user_id);
create index if not exists idx_payment_status on public."Payment"(status);

alter table public."Payment" enable row level security;

drop policy if exists "Payment select own" on public."Payment";
create policy "Payment select own" on public."Payment"
  for select using (auth.uid() = user_id);

-- INSERT/UPDATE выполняются только из Edge Function под service_role,
-- поэтому policy для пользователей не создаём (анон/authenticated не пишут).

-- Идемпотентное начисление баллов после успешной оплаты.
-- Вызывается из Edge Function stripe-webhook.
create or replace function public.apply_payment_credit(p_payment_intent_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pmt public."Payment"%rowtype;
begin
  select * into pmt
  from public."Payment"
  where stripe_payment_intent_id = p_payment_intent_id
  for update;

  if not found then
    raise exception 'Payment % not found', p_payment_intent_id;
  end if;

  -- Идемпотентность: если уже зачислено — выходим без изменений.
  if pmt.status = 'succeeded' then
    return;
  end if;

  update public."Payment"
     set status = 'succeeded', updated_at = now()
   where id = pmt.id;

  update public."User"
     set points = coalesce(points, 0) + pmt.points
   where id = pmt.user_id;
end;
$$;

revoke all on function public.apply_payment_credit(text) from public;
grant execute on function public.apply_payment_credit(text) to service_role;

-- Удобный update-помощник для перевода в неуспешный статус (failed/canceled).
create or replace function public.mark_payment_status(
  p_payment_intent_id text,
  p_status text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('failed', 'canceled', 'pending') then
    raise exception 'Invalid status %', p_status;
  end if;

  update public."Payment"
     set status = p_status, updated_at = now()
   where stripe_payment_intent_id = p_payment_intent_id
     and status <> 'succeeded';  -- не перетираем уже успешные
end;
$$;

revoke all on function public.mark_payment_status(text, text) from public;
grant execute on function public.mark_payment_status(text, text) to service_role;
