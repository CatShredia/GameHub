// Создаёт Stripe PaymentIntent под текущего пользователя и записывает строку в Payment.
// Принимает JSON: { points: number }
// Возвращает: { client_secret, publishable_key, payment_id, amount_minor, currency }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const stripeSecret = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const stripePublishable = Deno.env.get('STRIPE_PUBLISHABLE_KEY') ?? '';
const currency = (Deno.env.get('PAYMENT_CURRENCY') ?? 'rub').toLowerCase();
const pointPriceMinor = Number(Deno.env.get('PAYMENT_POINT_PRICE_MINOR') ?? '100');
// 1 балл стоит pointPriceMinor минимальных единиц валюты.
// Для RUB это копейки: 100 = 1 ₽ за 1 балл.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  if (!stripeSecret) {
    return jsonResponse(
      { error: 'STRIPE_SECRET_KEY is not configured' },
      500,
    );
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing Authorization header' }, 401);
  }

  // Аутентифицируем пользователя через Supabase
  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonResponse({ error: 'Invalid or expired token' }, 401);
  }
  const user = userData.user;

  let body: { points?: number } = {};
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const points = Math.floor(Number(body.points ?? 0));
  if (!Number.isFinite(points) || points <= 0 || points > 1_000_000) {
    return jsonResponse({ error: 'Invalid points amount' }, 400);
  }

  const amountMinor = points * pointPriceMinor;

  // Создаём PaymentIntent в Stripe
  const stripeBody = new URLSearchParams();
  stripeBody.set('amount', String(amountMinor));
  stripeBody.set('currency', currency);
  stripeBody.set('automatic_payment_methods[enabled]', 'true');
  stripeBody.set('metadata[user_id]', user.id);
  stripeBody.set('metadata[points]', String(points));
  stripeBody.set('description', `GameHub: ${points} баллов`);

  const stripeRes = await fetch('https://api.stripe.com/v1/payment_intents', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${stripeSecret}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: stripeBody.toString(),
  });

  const intent = await stripeRes.json().catch(() => ({}));
  if (!stripeRes.ok || !intent?.client_secret) {
    console.error('Stripe error:', stripeRes.status, intent);
    return jsonResponse(
      {
        error: 'Failed to create payment intent',
        stripe_status: stripeRes.status,
        stripe_body: intent,
      },
      502,
    );
  }

  // Записываем строку в Payment под service_role
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: payment, error: insertErr } = await adminClient
    .from('Payment')
    .insert({
      user_id: user.id,
      stripe_payment_intent_id: intent.id,
      amount_minor: amountMinor,
      currency,
      points,
      status: 'pending',
      metadata: { description: `GameHub: ${points} баллов` },
    })
    .select('id')
    .single();

  if (insertErr) {
    console.error('Payment insert failed:', insertErr);
    return jsonResponse(
      { error: 'Failed to record payment', details: insertErr.message },
      500,
    );
  }

  return jsonResponse({
    client_secret: intent.client_secret,
    publishable_key: stripePublishable,
    payment_id: payment?.id,
    payment_intent_id: intent.id,
    amount_minor: amountMinor,
    currency,
    points,
  });
});
