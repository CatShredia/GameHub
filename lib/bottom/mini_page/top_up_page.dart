import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  static const _amounts = [100, 300, 500, 1000, 2500, 5000];
  static const _paymentMethods = [
    ('Банковская карта', Icons.credit_card),
  ];
  static const _supabaseUrl = 'https://tvjggbkxmgbdtcfxggza.supabase.co';

  int _selectedAmount = _amounts[2];
  String _selectedPayment = _paymentMethods.first.$1;
  bool _processing = false;

  Future<void> _pay() async {
    if (_processing) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _showError('Войдите в аккаунт, чтобы пополнить баланс');
      return;
    }

    setState(() => _processing = true);
    try {
      final intent = await _createPaymentIntent(
        accessToken: session.accessToken,
        points: _selectedAmount,
      );

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'GameHub',
          style: ThemeMode.dark,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              background: Color(0xFF1A1A2E),
              primary: Color(0xFF7C3AED),
              componentBackground: Color(0xFF14142B),
              componentBorder: Color(0xFF2A2A45),
              componentText: Colors.white,
              primaryText: Colors.white,
              secondaryText: Colors.white70,
              placeholderText: Colors.white38,
              icon: Colors.white70,
            ),
            shapes: PaymentSheetShape(
              borderRadius: 14,
              borderWidth: 1,
            ),
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Оплата принята: +$_selectedAmount ⭐'),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } on StripeException catch (e) {
      final msg = e.error.localizedMessage ?? e.error.message ?? 'Оплата отменена';
      if (e.error.code == FailureCode.Canceled) {
        _showError('Оплата отменена');
      } else {
        _showError(msg);
      }
    } catch (e) {
      _showError('Не удалось провести оплату: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<_PaymentIntentResult> _createPaymentIntent({
    required String accessToken,
    required int points,
  }) async {
    final res = await http.post(
      Uri.parse('$_supabaseUrl/functions/v1/stripe-create-payment-intent'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'points': points}),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final secret = data['client_secret'] as String?;
    if (secret == null || secret.isEmpty) {
      throw Exception('Empty client_secret in response');
    }
    return _PaymentIntentResult(
      clientSecret: secret,
      paymentId: data['payment_id'] as String?,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text(
          'Пополнить баланс',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите сумму баллов',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _amounts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.6,
              ),
              itemBuilder: (context, index) {
                final amount = _amounts[index];
                final selected = amount == _selectedAmount;

                return InkWell(
                  onTap: _processing
                      ? null
                      : () => setState(() => _selectedAmount = amount),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF7C3AED)
                            : Colors.white12,
                        width: selected ? 2 : 1,
                      ),
                      color: selected
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.18)
                          : const Color(0xFF1A1A2E),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$amount ⭐',
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFFA78BFA)
                                  : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$amount ₽',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            const Text(
              'Способ оплаты',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            ..._paymentMethods.map((method) {
              final selected = method.$1 == _selectedPayment;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: _processing
                      ? null
                      : () => setState(() => _selectedPayment = method.$1),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF7C3AED)
                            : Colors.white12,
                      ),
                      color: const Color(0xFF1A1A2E),
                    ),
                    child: Row(
                      children: [
                        Icon(method.$2, color: const Color(0xFF7C3AED)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                method.$1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Visa, MasterCard, МИР',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? const Color(0xFF7C3AED)
                              : Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: Color(0xFF7C3AED), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Тестовая оплата через Stripe.\nКарта: 4242 4242 4242 4242, 12/34, 123',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _processing ? null : _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  disabledBackgroundColor:
                      const Color(0xFF7C3AED).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Оплатить $_selectedAmount ₽',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentIntentResult {
  final String clientSecret;
  final String? paymentId;
  const _PaymentIntentResult({required this.clientSecret, this.paymentId});
}
