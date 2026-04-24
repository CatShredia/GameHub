import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _sb = Supabase.instance.client;

/// Теги и хэштеги постов. Парсинг [#...] на клиенте.
class TagService {
  TagService._();
  static final TagService instance = TagService._();

  /// Буквы/цифры/подчёркивания (включая кириллицу).
  static final RegExp _hashRx = RegExp(r'#([\p{L}\p{N}_]{2,40})', unicode: true);

  List<String> parseTags(String text) {
    final set = <String>{};
    for (final m in _hashRx.allMatches(text)) {
      final t = m.group(1)!.toLowerCase();
      set.add(t);
    }
    return set.toList();
  }

  /// Создаёт недостающие теги и связывает их с постом. [names] — без #.
  Future<void> upsertPostTags({
    required int postId,
    required List<String> names,
    String kind = 'topic',
  }) async {
    if (names.isEmpty) return;
    try {
      final uniq = names.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet().toList();

      final upserted = await _sb.from('Tag').upsert(
        uniq.map((n) => {'name': n, 'kind': kind}).toList(),
        onConflict: 'name',
      ).select('id, name');

      final list = List<Map<String, dynamic>>.from(upserted);
      if (list.isEmpty) return;

      await _sb.from('Post_tag').upsert(
        list
            .map((t) => {'post_id': postId, 'tag_id': t['id']})
            .toList(),
        onConflict: 'post_id,tag_id',
      );
    } catch (e) {
      debugPrint('TagService.upsertPostTags: $e');
    }
  }

  Future<List<Map<String, dynamic>>> popular({int limit = 12}) async {
    try {
      final rows = await _sb
          .from('Tag_popular')
          .select('id, name, kind, uses')
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('TagService.popular: $e');
      return [];
    }
  }

  /// id постов с данным тегом (для фильтра ленты).
  Future<List<int>> postIdsByTag(String name, {int limit = 100}) async {
    try {
      final tag = await _sb
          .from('Tag')
          .select('id')
          .eq('name', name.toLowerCase())
          .maybeSingle();
      if (tag == null) return const [];
      final tid = tag['id'];
      final rows = await _sb
          .from('Post_tag')
          .select('post_id')
          .eq('tag_id', tid)
          .order('post_id', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows)
          .map((r) => (r['post_id'] as num).toInt())
          .toList();
    } catch (e) {
      debugPrint('TagService.postIdsByTag: $e');
      return const [];
    }
  }
}
