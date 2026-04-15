import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'home.dart';

// ? Страница проверки авторизации при запуске приложения
class CheckPage extends StatefulWidget {
  const CheckPage({super.key});

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // ? Проверяет наличие активной сессии Supabase
  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 400));

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    debugPrint(
      '🔍 Auth check: user=${user?.email}, session exists=${session != null}',
    );

    if (mounted) {
      setState(() {
        _isLoggedIn = user != null && session != null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }

    return _isLoggedIn ? const HomePage() : const AuthPage();
  }
}
