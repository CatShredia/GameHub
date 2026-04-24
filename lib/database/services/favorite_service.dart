import 'package:supabase_flutter/supabase_flutter.dart';

enum FavoriteKind { post, auction }

extension FavoriteKindX on FavoriteKind {
  String get value => this == FavoriteKind.post ? 'post' : 'auction';
}

/// Закладки пользователя (посты и аукционы).
class FavoriteService {
  FavoriteService._();
  static final FavoriteService instance = FavoriteService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Поставить/снять закладку. Возвращает новое состояние (true — в закладках).
  Future<bool> toggle({required FavoriteKind kind, required int refId}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    final existing = await _sb
        .from('Favorite')
        .select('id')
        .eq('user_id', uid)
        .eq('kind', kind.value)
        .eq('ref_id', refId)
        .maybeSingle();
    if (existing != null) {
      await _sb.from('Favorite').delete().eq('id', existing['id'] as Object);
      return false;
    }
    await _sb.from('Favorite').insert({
      'user_id': uid,
      'kind': kind.value,
      'ref_id': refId,
    });
    return true;
  }

  Future<bool> isFavorite({required FavoriteKind kind, required int refId}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _sb
        .from('Favorite')
        .select('id')
        .eq('user_id', uid)
        .eq('kind', kind.value)
        .eq('ref_id', refId)
        .maybeSingle();
    return row != null;
  }

  /// Все id для текущего юзера по указанному типу — для массовой подсветки.
  Future<Set<int>> listIds(FavoriteKind kind) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return <int>{};
    final rows = await _sb
        .from('Favorite')
        .select('ref_id')
        .eq('user_id', uid)
        .eq('kind', kind.value);
    return {
      for (final r in (rows as List))
        ((r as Map)['ref_id'] as num).toInt(),
    };
  }

  /// Последние сохранённые посты с джойном пользователя.
  Future<List<Map<String, dynamic>>> listFavoritePosts({int limit = 50}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    final favs = await _sb
        .from('Favorite')
        .select('ref_id, created_at')
        .eq('user_id', uid)
        .eq('kind', FavoriteKind.post.value)
        .order('created_at', ascending: false)
        .limit(limit);
    final ids = [
      for (final f in (favs as List)) ((f as Map)['ref_id'] as num).toInt(),
    ];
    if (ids.isEmpty) return const [];
    final posts = await _sb
        .from('Post')
        .select('id, content, created_at, user_id, User!inner(username, login, avatar)')
        .inFilter('id', ids);
    final byId = {
      for (final p in (posts as List)) ((p as Map)['id'] as num).toInt(): p,
    };
    return [
      for (final id in ids)
        if (byId[id] != null) Map<String, dynamic>.from(byId[id] as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listFavoriteAuctions({int limit = 50}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    final favs = await _sb
        .from('Favorite')
        .select('ref_id, created_at')
        .eq('user_id', uid)
        .eq('kind', FavoriteKind.auction.value)
        .order('created_at', ascending: false)
        .limit(limit);
    final ids = [
      for (final f in (favs as List)) ((f as Map)['ref_id'] as num).toInt(),
    ];
    if (ids.isEmpty) return const [];
    final rows = await _sb
        .from('Auction_items')
        .select()
        .inFilter('id', ids);
    final byId = {
      for (final p in (rows as List)) ((p as Map)['id'] as num).toInt(): p,
    };
    return [
      for (final id in ids)
        if (byId[id] != null) Map<String, dynamic>.from(byId[id] as Map),
    ];
  }
}
