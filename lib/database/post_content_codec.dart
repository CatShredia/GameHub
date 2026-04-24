import 'dart:convert';

/// Содержимое [Post.content]: обычный текст или JSON для ленты «как в Twitter».
class PostContentData {
  final String text;
  final List<String> imageUrls;
  final int? quotePostId;
  final Map<String, dynamic>? quoteSnapshot;

  const PostContentData({
    required this.text,
    this.imageUrls = const [],
    this.quotePostId,
    this.quoteSnapshot,
  });

  bool get hasMedia => imageUrls.isNotEmpty;
  bool get hasQuote => quotePostId != null || (quoteSnapshot != null && quoteSnapshot!.isNotEmpty);
}

const String _jsonPrefix = 'GHPOST:';

/// Кодирует пост в одну строку [Post.content] (совместимо со старыми plain-текст постами).
String encodePostContent(PostContentData d) {
  if (!d.hasMedia && !d.hasQuote) {
    return d.text;
  }
  final map = <String, dynamic>{
    't': d.text,
    if (d.imageUrls.isNotEmpty) 'i': d.imageUrls,
    if (d.quotePostId != null) 'q': d.quotePostId,
    if (d.quoteSnapshot != null) 'qs': d.quoteSnapshot,
  };
  return '$_jsonPrefix${jsonEncode(map)}';
}

/// Разбор [Post.content] в структуру.
PostContentData decodePostContent(String raw) {
  final s = raw.trim();
  if (s.startsWith(_jsonPrefix)) {
    try {
      final m = jsonDecode(s.substring(_jsonPrefix.length)) as Map<String, dynamic>;
      final text = (m['t'] as String?) ?? '';
      final imgs = (m['i'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
      final q = m['q'] is int ? m['q'] as int : int.tryParse('${m['q']}');
      final qs = m['qs'] is Map ? Map<String, dynamic>.from(m['qs'] as Map) : null;
      return PostContentData(
        text: text,
        imageUrls: imgs,
        quotePostId: q,
        quoteSnapshot: qs,
      );
    } catch (_) {
      return PostContentData(text: raw);
    }
  }
  return PostContentData(text: raw);
}
