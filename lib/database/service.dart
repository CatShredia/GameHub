import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthServices {
  final _client = Supabase.instance.client;

  // ? Описание
  Future<User?> signIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return response.user;
    } on AuthException catch (e) {
      debugPrint('Login error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected login error: $e');
      rethrow;
    }
  }

  // ? Описание
  Future<User?> signUp(
    String email,
    String password, {
    String? username,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username?.trim() ?? email.split('@')[0]},
      );

      return response.user;
    } on AuthException catch (e) {
      debugPrint('Register error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected register error: $e');
      rethrow;
    }
  }

  // ? Описание
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ? Описание
  User? get currentUser => _client.auth.currentUser;

  // ? Описание
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
