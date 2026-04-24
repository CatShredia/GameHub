import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  // ? Описание
  Future<Map<String, dynamic>> getProfileData(String userId) async {
    final user = await _client
        .from('User')
        .select('id, email, login, username, scope, avatar, created_at')
        .eq('id', userId)
        .maybeSingle();

    if (user == null) {
      throw Exception('Профиль не найден в базе данных');
    }

    final posts = await _client.from('Post').select('id').eq('user_id', userId);
    final postsCount = posts.length;

    final auctions = await _client
        .from('Auction_items')
        .select('id, is_active')
        .eq('owner_id', userId);

    final activeAuctions = auctions.where((a) => a['is_active'] == true).length;
    final completedAuctions = auctions.length - activeAuctions;

    final scope = (user['scope'] as num?)?.toInt() ?? 0;
    return {
      'user': user,
      'points': scope,
      'postsCount': postsCount,
      'activeAuctions': activeAuctions,
      'completedAuctions': completedAuctions,
      'rating': 4.9,
      'joinedAt': user['created_at'],
    };
  }

  /// Таблица [Notification] в схеме; при отличии регистра в PostgREST пробуем [notification].
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    Future<List<Map<String, dynamic>>> run(String table) async {
      final response = await _client
          .from(table)
          .select('id, title, content, is_watched, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response as List);
    }

    try {
      return await run('Notification');
    } catch (e) {
      debugPrint('getNotifications(Notification): $e');
    }
    try {
      return await run('notification');
    } catch (e) {
      debugPrint('getNotifications(notification): $e');
      rethrow;
    }
  }

  Future<void> markNotificationAsRead(dynamic notificationId) async {
    for (final t in ['Notification', 'notification']) {
      try {
        await _client
            .from(t)
            .update({'is_watched': true})
            .eq('id', notificationId);
        return;
      } catch (e) {
        debugPrint('markNotificationAsRead from $t: $e');
      }
    }
  }

  Future<void> markAllNotificationsAsRead(String userId) async {
    for (final t in ['Notification', 'notification']) {
      try {
        await _client
            .from(t)
            .update({'is_watched': true})
            .eq('user_id', userId);
        return;
      } catch (e) {
        debugPrint('markAll from $t: $e');
      }
    }
  }

  // ? Описание
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
