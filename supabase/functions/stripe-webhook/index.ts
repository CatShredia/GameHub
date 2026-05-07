// Stripe webhook без зависимости от stripe-sdk: ручная верификация подписи (HMAC-SHA256)
// и обработка событий через JSON.parse. Это надёжнее, чем тянуть Node-SDK в Deno,
// и даёт подробные логи на каждом шаге.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';
// Допуск по времени: 5 минут (Stripe рекомендует ≤ 5 мин).
const TOLERANCE_SECONDS = 300;

const supabase = createClient(supabaseUrl, serviceRoleKey);

function parseSignatureHeader(header: string): {
  timestamp: number;
  v1Signatures: string[];
} | null {
  const parts = header.split(',').map((p) => p.trim());
  let timestamp = 0;
  const v1Signatures: string[] = [];
  for (const part of parts) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const key = part.slice(0, eq);
    const value = part.slice(eq + 1);
    if (key === 't') timestamp = Number(value);
    else if (key === 'v1') v1Signatures.push(value);
  }
  if (!timestamp || v1Signatures.length === 0) return null;
  return { timestamp, v1Signatures };
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(payload));
  const bytes = new Uint8Array(sig);
  let hex = '';
  for (const b of bytes) hex += b.toString(16).padStart(2, '0');
  return hex;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function verifyStripeSignature(
  rawBody: string,
  header: string,
  secret: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const parsed = parseSignatureHeader(header);
  if (!parsed) return { ok: false, reason: 'Cannot parse Stripe-Signature header' };
  const { timestamp, v1Signatures } = parsed;

  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - timestamp) > TOLERANCE_SECONDS) {
    return { ok: false, reason: `Timestamp out of tolerance (skew=${nowSec - timestamp}s)` };
  }

  const signedPayload = `${timestamp}.${rawBody}`;
  const expected = await hmacSha256Hex(secret, signedPayload);

  for (const sig of v1Signatures) {
    if (timingSafeEqual(expected, sig)) return { ok: true };
  }
  return { ok: false, reason: 'No v1 signature matched' };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!webhookSecret) {
    console.error('STRIPE_WEBHOOK_SECRET is not configured');
    return new Response('STRIPE_WEBHOOK_SECRET is not configured', { status: 500 });
  }

  const signature = req.headers.get('stripe-signature');
  if (!signature) {
    return new Response('Missing stripe-signature', { status: 400 });
  }

  const rawBody = await req.text();

  const verify = await verifyStripeSignature(rawBody, signature, webhookSecret);
  if (!verify.ok) {
    console.error(`Signature verification failed: ${verify.reason}`);
    return new Response(`Webhook signature verification failed: ${verify.reason}`, {
      status: 400,
    });
  }

  let event: { id?: string; type?: string; data?: { object?: Record<string, unknown> } };
  try {
    event = JSON.parse(rawBody);
  } catch (e) {
    console.error('JSON parse error:', e);
    return new Response('Invalid JSON', { status: 400 });
  }

  const eventType = event.type ?? '';
  const intent = event.data?.object as Record<string, unknown> | undefined;
  const intentId = (intent?.id as string | undefined) ?? '';

  console.log(`📥 Stripe event ${event.id} type=${eventType} intent=${intentId}`);

  try {
    switch (eventType) {
      case 'payment_intent.succeeded': {
        if (!intentId) {
          console.warn('payment_intent.succeeded without intent.id');
          break;
        }
        const { error } = await supabase.rpc('apply_payment_credit', {
          p_payment_intent_id: intentId,
        });
        if (error) {
          console.error('apply_payment_credit failed:', error.message, error.details);
          return new Response(`RPC error: ${error.message}`, { status: 500 });
        }
        console.log(`✅ Credited payment ${intentId}`);
        break;
      }
      case 'payment_intent.payment_failed': {
        if (!intentId) break;
        const { error } = await supabase.rpc('mark_payment_status', {
          p_payment_intent_id: intentId,
          p_status: 'failed',
        });
        if (error) console.error('mark_payment_status(failed):', error.message);
        else console.log(`Marked ${intentId} as failed`);
        break;
      }
      case 'payment_intent.canceled': {
        if (!intentId) break;
        const { error } = await supabase.rpc('mark_payment_status', {
          p_payment_intent_id: intentId,
          p_status: 'canceled',
        });
        if (error) console.error('mark_payment_status(canceled):', error.message);
        else console.log(`Marked ${intentId} as canceled`);
        break;
      }
      default:
        console.log(`Ignoring event type: ${eventType}`);
    }
  } catch (e) {
    console.error('Handler error:', e);
    return new Response(`Handler error: ${e}`, { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
