# GameHub

Flutter-приложение GameHub: лента, чаты, аукционы, профиль, push-уведомления (Firebase Cloud Messaging + Supabase) и пополнение баланса через Stripe.

## Запуск

```powershell
flutter pub get
flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_xxx
```

При первом запуске на Android-устройстве нужно положить `android/app/google-services.json` (см. раздел про push-уведомления). Stripe `--dart-define` нужен только если хочешь тестировать оплату.

## Настройка push-уведомлений

Уведомления состоят из двух связанных частей:

1. **Внутри приложения** (in-app) — Realtime-канал Supabase (`Notification`-таблица + DB-триггеры). Работает «из коробки» после применения миграций.
2. **Push-уведомления** (FCM) — приходят, даже когда приложение свёрнуто или закрыто. Требует Firebase + Service Account на стороне Supabase.

### 1. Применение миграций Supabase

```powershell
npx supabase link --project-ref <YOUR_PROJECT_REF>
npx supabase db push
```

Миграции, отвечающие за уведомления:

- `018_notification_preferences.sql` — таблицы `NotificationPreference`, `ChatNotificationMute`, RPC `create_feed_notification`, обновлённые DB-триггеры (фильтрация по настройкам пользователя).
- `019_push_notification_tokens.sql` — таблица `DevicePushToken` (хранит FCM-токены устройств).
- `020_message_push_webhook.sql` — резервный вариант через managed Database Webhook (используется только если включён `supabase_functions.http_request`).
- `021_message_push_pg_net.sql` — основной механизм: `pg_net`-триггер на `Message INSERT`, вызывающий Edge Function `send-message-push`.

### 2. Firebase: подключение Android

1. Открой [Firebase Console](https://console.firebase.google.com/) и создай (или выбери) проект.
2. Добавь Android-приложение с пакетом `com.example.gamehub` (см. `android/app/build.gradle.kts` → `applicationId`).
3. Скачай `google-services.json` и положи его в `android/app/google-services.json`. Этот файл **не коммитится**, он уже в `.gitignore`.
4. Убедись, что в `android/app/build.gradle.kts` подключён `com.google.gms.google-services`, а в `android/settings.gradle.kts` — `com.google.gms.google-services` plugin.

В `AndroidManifest.xml` уже добавлено разрешение `POST_NOTIFICATIONS` (нужно для Android 13+).

### 3. Firebase: Service Account для FCM HTTP v1

Google с июня 2024 г. отключает Legacy-API (`fcm/send`). Используем **FCM HTTP v1** через Service Account.

1. Firebase Console → **Project Settings** → вкладка **Service accounts** → **Generate new private key** → скачать JSON (например, `gamehub-XXXXX-firebase-adminsdk-fbsvc-XXXXXXXXXXX.json`).
2. Этот файл — **секрет**. Он уже добавлен в `.gitignore` (паттерн `**/firebase-adminsdk*.json`). Не коммить.
3. Загрузи его в Supabase как секрет `FCM_SERVICE_ACCOUNT` (одной компактной строкой, чтобы не было проблем с переносами):

   ```powershell
   $obj = Get-Content -Raw ".\gamehub-XXXXX-firebase-adminsdk-fbsvc-XXXXXXXXXXX.json" | ConvertFrom-Json
   $oneLine = $obj | ConvertTo-Json -Compress -Depth 10
   "FCM_SERVICE_ACCOUNT=$oneLine" | Set-Content -NoNewline -Encoding utf8 .\.fcm-secret.env
   npx supabase secrets set --env-file .\.fcm-secret.env
   Remove-Item .\.fcm-secret.env
   ```

4. Деплой Edge Function:

   ```powershell
   npx supabase functions deploy send-message-push --no-verify-jwt
   ```

5. (Опционально) удалить устаревший Legacy-ключ:

   ```powershell
   npx supabase secrets unset FCM_SERVER_KEY
   ```

### 4. Проверка push end-to-end

Прямой вызов Edge Function (подставь свой `chat_id`, `sender_id` и `Bearer`-ключ — anon/publishable):

```powershell
$body = @{ record = @{ id = 999999; chat_id = 12; sender_id = "<UUID_отправителя>"; content = "TEST v1 push" } } | ConvertTo-Json -Depth 5
Invoke-RestMethod `
  -Uri "https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/send-message-push" `
  -Method POST -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer <SUPABASE_PUBLISHABLE_OR_ANON_KEY>" } `
  -Body $body | ConvertTo-Json -Depth 8
```

Ожидаемый ответ:

```json
{
  "provider": "fcm_v1",
  "sent": 1,
  "results": [
    { "status": 200, "body": { "name": "projects/<id>/messages/0:..." }, "token": "..." }
  ]
}
```

На устройстве в этот момент должен прийти баннер уведомления.

### 5. Архитектура push-потока

```
Message INSERT
   │
   ▼
trg_message_push_pg_net  (Postgres trigger)
   │  net.http_post → Edge Function
   ▼
send-message-push (Deno)
   │  читает ChatMember, NotificationPreference,
   │  ChatNotificationMute, DevicePushToken
   │  подписывает JWT Service Account → access_token
   ▼
FCM HTTP v1 (messages:send)
   │
   ▼
Android-устройство (firebase_messaging)
```

### 6. Клиентская часть

- `lib/database/services/push_notification_service.dart` — инициализирует Firebase, получает FCM-токен, апсёртит в `DevicePushToken`, обрабатывает foreground/background сообщения. Если `google-services.json` отсутствует — сервис безопасно отключается (приложение не падает).
- `lib/database/services/notification_preferences_service.dart` — настройки пользователя (топики `chats` / `auctions` / `feed`, mute конкретного чата).
- `lib/bottom/mini_page/notification_settings_page.dart` — экран «Настроить уведомления» (Профиль → одноимённая кнопка).
- `lib/bottom/mini_page/chat_screen.dart` — кнопка mute/unmute в `AppBar` чата.

### 7. Полезные диагностические команды

```powershell
# Список секретов и их digests
npx supabase secrets list

# Версии задеплоенных функций
npx supabase functions list

# Кол-во сохранённых FCM-токенов
@"
select count(*) from public."DevicePushToken";
"@ | Set-Content -NoNewline .\_q.sql; npx supabase db query --linked -f .\_q.sql -o table; Remove-Item .\_q.sql

# Последние HTTP-ответы pg_net (вызовы Edge Function из триггера)
@"
select id, status_code, error_msg, content::text as body, created
from net._http_response
where created > now() - interval '1 hour'
order by created desc
limit 10;
"@ | Set-Content -NoNewline .\_q.sql; npx supabase db query --linked -f .\_q.sql -o table; Remove-Item .\_q.sql
```

## Платежи (Stripe, тестовый режим)

Пополнение баланса (`User.points`) реализовано через **Stripe PaymentSheet** + Supabase Edge Functions. Историю транзакций ведём в таблице `Payment`.

### 1. Получи тестовые ключи Stripe

1. Зарегистрируйся / войди в [Stripe Dashboard](https://dashboard.stripe.com/test/apikeys).
2. Скопируй на странице **Developers → API keys**:
   - **Publishable key** — `pk_test_...`
   - **Secret key** — `sk_test_...`

### 2. Загрузи серверные ключи в Supabase

```powershell
@"
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_PUBLISHABLE_KEY=pk_test_xxx
PAYMENT_CURRENCY=rub
PAYMENT_POINT_PRICE_MINOR=100
"@ | Set-Content -NoNewline -Encoding utf8 .\.stripe-secret.env
npx supabase secrets set --env-file .\.stripe-secret.env
Remove-Item .\.stripe-secret.env
```

`PAYMENT_POINT_PRICE_MINOR` — цена 1 балла в **минимальных** единицах валюты. Для RUB значение `100` означает «1 ⭐ = 1 ₽» (100 копеек).

### 3. Применить миграцию и задеплоить функции

```powershell
npx supabase db push
npx supabase functions deploy stripe-create-payment-intent --no-verify-jwt
npx supabase functions deploy stripe-webhook --no-verify-jwt
```

### 4. Настроить Stripe Webhook

1. Открой [Stripe Dashboard → Developers → Webhooks](https://dashboard.stripe.com/test/webhooks).
2. **Add endpoint** → URL: `https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/stripe-webhook`.
3. **Listen to** → выбрать события:
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `payment_intent.canceled`
4. После создания скопируй **Signing secret** (`whsec_...`) и положи в Supabase, затем перезадеплой webhook:

   ```powershell
   "STRIPE_WEBHOOK_SECRET=whsec_xxx" | Set-Content -NoNewline -Encoding utf8 .\.stripe-webhook.env
   npx supabase secrets set --env-file .\.stripe-webhook.env
   Remove-Item .\.stripe-webhook.env
   npx supabase functions deploy stripe-webhook --no-verify-jwt
   ```

### 5. Запусти приложение с publishable-ключом

```powershell
flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_xxx
```

> Если запустить без `--dart-define`, Stripe не инициализируется и кнопка «Оплатить» не сработает (в логе появится `Stripe disabled: STRIPE_PUBLISHABLE_KEY is not set`).

### 6. Тестовая карта

В Stripe PaymentSheet введи:

| Поле | Значение |
|---|---|
| Номер | `4242 4242 4242 4242` |
| Срок | любая дата в будущем, например `12 / 34` |
| CVC | `123` |
| ZIP/индекс | `12345` |

Ещё полезные тестовые карты ([полный список](https://docs.stripe.com/testing)):

- `4000 0025 0000 3155` — требует 3D Secure (проверка аутентификации).
- `4000 0000 0000 9995` — недостаточно средств.
- `4000 0000 0000 0002` — карта отклоняется банком.

### 7. Архитектура платёжного потока

```
TopUpPage (Flutter)
  │  POST /functions/v1/stripe-create-payment-intent  (Bearer access_token)
  ▼
stripe-create-payment-intent (Edge Function)
  │  Stripe API: POST /v1/payment_intents
  │  INSERT public."Payment" (status='pending')
  ▼
TopUpPage  ← client_secret
  │  Stripe.instance.initPaymentSheet + presentPaymentSheet
  ▼
Stripe (тестовый платёж)
  │  webhook: payment_intent.succeeded
  ▼
stripe-webhook (Edge Function, signature verify)
  │  RPC apply_payment_credit(payment_intent_id)
  ▼
public."Payment".status = 'succeeded'
public."User".points += points
```

### 8. Локальный тест webhook'а (опционально)

Если установлен [Stripe CLI](https://docs.stripe.com/stripe-cli):

```powershell
stripe listen --forward-to https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/stripe-webhook
stripe trigger payment_intent.succeeded
```

### 9. Проверка истории платежей

```powershell
@"
select id, user_id, amount_minor, currency, points, status, created_at
from public.""Payment""
order by created_at desc
limit 10;
"@ | Set-Content -NoNewline .\_q.sql
npx supabase db query --linked -f .\_q.sql -o table
Remove-Item .\_q.sql
```

## Типичные проблемы

| Симптом | Причина | Решение |
|---|---|---|
| `PushNotificationService disabled: Failed to load FirebaseOptions` | Нет `android/app/google-services.json` | Скачать из Firebase Console и положить в `android/app/` |
| `pg_net` отвечает `500: FCM_SERVER_KEY/FCM_SERVICE_ACCOUNT is not configured` | Не задан секрет в Supabase | См. раздел про FCM |
| FCM возвращает `404 Not Found` (HTML) | Используется Legacy API, который отключён | Перейти на v1 (Service Account) |
| Push приходит только в foreground | OS блокирует уведомления | Разрешить уведомления в настройках Android (Android 13+ — `POST_NOTIFICATIONS`) |
| Токен `DevicePushToken` не сохраняется | Пользователь не залогинен в Supabase | Логин → токен апсёртится в `_listenAuthAndToken` |
| `Stripe disabled: STRIPE_PUBLISHABLE_KEY is not set` | Запустил приложение без `--dart-define` | Запусти с `--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...` |
| `STRIPE_SECRET_KEY is not configured` (в Edge Function) | Не загружены серверные ключи Stripe | См. шаг 2 в разделе «Платежи» |
| Платёж прошёл, но баллы не начислились | Не настроен webhook или неверный `STRIPE_WEBHOOK_SECRET` | Проверь Stripe Dashboard → Webhooks → последние события и ошибки signing |
| `IllegalStateException: You need to use Theme.AppCompat` (Android) | Тема приложения не AppCompat/MaterialComponents | Уже исправлено в `android/app/src/main/res/values{,-night}/styles.xml` |
