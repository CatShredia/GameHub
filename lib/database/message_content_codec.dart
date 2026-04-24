import 'dart:convert';

/// Вложение сообщения/поста: файл в Storage с подписанным/публичным URL.
class AttachmentMeta {
  final String url;
  final String name;
  final int sizeBytes;
  final String? mime;

  const AttachmentMeta({
    required this.url,
    required this.name,
    required this.sizeBytes,
    this.mime,
  });

  Map<String, dynamic> toJson() => {
        'u': url,
        'n': name,
        's': sizeBytes,
        if (mime != null) 'm': mime,
      };

  factory AttachmentMeta.fromJson(Map<String, dynamic> j) => AttachmentMeta(
        url: j['u']?.toString() ?? '',
        name: j['n']?.toString() ?? 'file',
        sizeBytes: (j['s'] as num?)?.toInt() ?? 0,
        mime: j['m']?.toString(),
      );
}

/// Содержимое [Message.content]: текст + картинки + голосовое + файлы.
class MessageContentData {
  final String text;
  final List<String> imageUrls;
  final String? audioUrl;
  final int? audioDurationMs;
  final List<AttachmentMeta> attachments;

  const MessageContentData({
    this.text = '',
    this.imageUrls = const [],
    this.audioUrl,
    this.audioDurationMs,
    this.attachments = const [],
  });

  bool get hasText => text.trim().isNotEmpty;
  bool get hasImages => imageUrls.isNotEmpty;
  bool get hasVoice => (audioUrl ?? '').isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get isRich => hasImages || hasVoice || hasAttachments;
}

const String _msgPrefix = 'GHMSG:';

/// Упаковывает сообщение в строку [Message.content]. Plain-текст сохраняется как есть.
String encodeMessageContent(MessageContentData d) {
  if (!d.isRich) return d.text;
  final map = <String, dynamic>{
    if (d.text.isNotEmpty) 't': d.text,
    if (d.imageUrls.isNotEmpty) 'i': d.imageUrls,
    if (d.hasVoice) 'a': d.audioUrl,
    if (d.audioDurationMs != null) 'ad': d.audioDurationMs,
    if (d.attachments.isNotEmpty)
      'f': d.attachments.map((e) => e.toJson()).toList(),
  };
  return '$_msgPrefix${jsonEncode(map)}';
}

/// Разбор [Message.content]. Старые plain-текст сообщения читаются как только [text].
MessageContentData decodeMessageContent(String? raw) {
  final s = (raw ?? '').trim();
  if (!s.startsWith(_msgPrefix)) {
    return MessageContentData(text: raw ?? '');
  }
  try {
    final map =
        jsonDecode(s.substring(_msgPrefix.length)) as Map<String, dynamic>;
    final text = (map['t'] as String?) ?? '';
    final images = (map['i'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    final audio = map['a']?.toString();
    final dur = (map['ad'] as num?)?.toInt();
    final files = (map['f'] as List?)
            ?.whereType<Map>()
            .map((e) => AttachmentMeta.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <AttachmentMeta>[];
    return MessageContentData(
      text: text,
      imageUrls: images,
      audioUrl: (audio ?? '').isEmpty ? null : audio,
      audioDurationMs: dur,
      attachments: files,
    );
  } catch (_) {
    return MessageContentData(text: raw ?? '');
  }
}
