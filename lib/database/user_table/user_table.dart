import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserTable {
  final SupabaseClient _client = Supabase.instance.client;
  static const List<String> _candidates = ['User', 'users', 'user', '"User"'];
  String? _resolvedTable;

  Future<String> _table() async {
    if (_resolvedTable != null) return _resolvedTable!;
    for (final t in _candidates) {
      try {
        await _client.from(t).select('id').limit(1);
        _resolvedTable = t;
        return t;
      } catch (_) {}
    }
    _resolvedTable = 'User';
    return _resolvedTable!;
  }

  // ? Описание
  Future<void> addUserTable({
    required String userId,
    required String username,
    required String email,
    String? fullName,
    String? avatar,
  }) async {
    try {
      final table = await _table();
      await _client.from(table).insert({
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

  /// Идемпотентно создаёт профиль в public.User, если его ещё нет.
  /// Генерирует уникальный login на основе [username], подстраивается
  /// под уже существующие записи.
  Future<void> ensureProfile({
    required String userId,
    required String username,
    required String email,
    String? avatar,
  }) async {
    try {
      final table = await _table();
      final existing = await _client
          .from(table)
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (existing != null) return;

      final login = await _uniqueLogin(username);
      await _client.from(table).insert({
        'id': userId,
        'username': username,
        'email': email,
        'login': login,
        'password': '',
        'avatar': avatar ?? '',
        'scope': 0,
      });
    } catch (e) {
      debugPrint('ensureProfile: $e');
    }
  }

  Future<String> _uniqueLogin(String base) async {
    final cleaned = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.]+'), '_');
    final start = cleaned.isEmpty ? 'user' : cleaned;
    var candidate = start;
    var suffix = 1;
    while (true) {
      final row = await _client
          .from(await _table())
          .select('id')
          .eq('login', candidate)
          .maybeSingle();
      if (row == null) return candidate;
      suffix += 1;
      candidate = '$start$suffix';
    }
  }

  // ? Описание
  Future<void> updateAvatar(String userId, String avatarUrl) async {
    final table = await _table();
    await _client.from(table).update({'avatar': avatarUrl}).eq('id', userId);
  }

  // ? Описание
  Future<void> updateUsername(String userId, String newUsername) async {
    final table = await _table();
    await _client
        .from(table)
        .update({'username': newUsername})
        .eq('id', userId);
  }
}
