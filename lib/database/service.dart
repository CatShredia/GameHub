import 'package:supabase_flutter/supabase_flutter.dart';

class AuthServices {
  final _client = Supabase.instance.client;

  /// Вход в систему
  Future<User?> singIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return response.user;
    } on AuthException catch (e) {
      print('❌ Login error: ${e.message}');
      rethrow; // чтобы ловить в UI
    } catch (e) {
      print('❌ Unexpected login error: $e');
      rethrow;
    }
  }

  /// Регистрация нового пользователя
  Future<User?> singUp(String email, String password, {String? username}) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': username?.trim() ?? email.split('@')[0],
        },
      );

      return response.user;
    } on AuthException catch (e) {
      print('❌ Register error: ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Unexpected register error: $e');
      rethrow;
    }
  }

  /// Выход
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}