import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserTable {
  final SupabaseClient _client = Supabase.instance.client;

  // ? Описание
  Future<void> addUserTable({
    required String userId,
    required String username,
    required String email,
    String? fullName,
    String? avatar,
  }) async {
    try {
      await _client.from('User').insert({
        'id': userId,
        'username': username,
        'email': email,
        'login': username.toLowerCase(),
        'password': '',
        'avatar': avatar ?? '',
        'scope': 0,
      });
    } catch (e) {
      debugPrint('Ошибка при создании профиля пользователя: $e');
    }
  }

  // ? Описание
  Future<void> updateAvatar(String userId, String avatarUrl) async {
    await _client.from('User').update({'avatar': avatarUrl}).eq('id', userId);
  }

  // ? Описание
  Future<void> updateUsername(String userId, String newUsername) async {
    await _client
        .from('User')
        .update({'username': newUsername})
        .eq('id', userId);
  }
}
