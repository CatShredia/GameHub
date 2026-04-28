import 'dart:convert';

import 'message_content_codec.dart' show AttachmentMeta;

export 'message_content_codec.dart' show AttachmentMeta;

/// Содержимое [Post.content]: обычный текст или JSON для ленты (как в Twitter + голос/файлы).
class PostContentData {
  final String text;
  final List<String> imageUrls;
  final int? quotePostId;
  final Map<String, dynamic>? quoteSnapshot;

  final String? audioUrl;
  final int? audioDurationMs;
  final List<AttachmentMeta> attachments;
  final List<String> tags;

  const PostContentData({
    required this.text,
    this.imageUrls = const [],
    this.quotePostId,
    this.quoteSnapshot,
    this.audioUrl,
    this.audioDurationMs,
    this.attachments = const [],
    this.tags = const [],
  });

  bool get hasMedia => imageUrls.isNotEmpty;
  bool get hasQuote =>
      quotePostId != null || (quoteSnapshot != null && quoteSnapshot!.isNotEmpty);
  bool get hasVoice => (audioUrl ?? '').isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasTags => tags.isNotEmpty;
}

const String _jsonPrefix = 'GHPOST:';

/// Кодирует пост в одну строку [Post.content] (совместимо со старыми plain-текст постами).
String encodePostContent(PostContentData d) {
  final rich = d.hasMedia ||
      d.hasQuote ||
      d.hasVoice ||
      d.hasAttachments ||
      d.hasTags;
  if (!rich) {
    return d.text;
  }
  final map = <String, dynamic>{
    't': d.text,
    if (d.imageUrls.isNotEmpty) 'i': d.imageUrls,
    if (d.quotePostId != null) 'q': d.quotePostId,
    if (d.quoteSnapshot != null) 'qs': d.quoteSnapshot,
    if (d.hasVoice) 'a': d.audioUrl,
    if (d.audioDurationMs != null) 'ad': d.audioDurationMs,
    if (d.attachments.isNotEmpty)
      'f': d.attachments.map((e) => e.toJson()).toList(),
    if (d.tags.isNotEmpty) 'tg': d.tags,
  };
  return '$_jsonPrefix${jsonEncode(map)}';
}

/// Разбор [Post.content] в структуру.
PostContentData decodePostContent(String raw) {
  final s = raw.trim();
  if (s.startsWith(_jsonPrefix)) {
    try {
      final m =
          jsonDecode(s.substring(_jsonPrefix.length)) as Map<String, dynamic>;
      final text = (m['t'] as String?) ?? '';
      final imgs =
          (m['i'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              <String>[];
      final q = m['q'] is int ? m['q'] as int : int.tryParse('${m['q']}');
      final qs = m['qs'] is Map
          ? Map<String, dynamic>.from(m['qs'] as Map)
          : null;
      final audio = m['a']?.toString();
      final dur = (m['ad'] as num?)?.toInt();
      final files = (m['f'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  AttachmentMeta.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const <AttachmentMeta>[];
      final tags = (m['tg'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      return PostContentData(
        text: text,
        imageUrls: imgs,
        quotePostId: q,
        quoteSnapshot: qs,
        audioUrl: (audio ?? '').isEmpty ? null : audio,
        audioDurationMs: dur,
        attachments: files,
        tags: tags,
      );
    } catch (_) {
      return PostContentData(text: raw);
    }
  }
  return PostContentData(text: raw);
}
