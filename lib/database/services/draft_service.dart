import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Черновик поста — хранится локально в SharedPreferences.
class PostDraft {
  final String text;
  final List<String> imageUrls;
  final String? audioUrl;
  final int? audioDurationMs;
  final DateTime updatedAt;

  const PostDraft({
    required this.text,
    this.imageUrls = const [],
    this.audioUrl,
    this.audioDurationMs,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        't': text,
        if (imageUrls.isNotEmpty) 'i': imageUrls,
        if (audioUrl != null) 'a': audioUrl,
        if (audioDurationMs != null) 'ad': audioDurationMs,
        'u': updatedAt.toIso8601String(),
      };

  factory PostDraft.fromJson(Map<String, dynamic> j) => PostDraft(
        text: (j['t'] as String?) ?? '',
        imageUrls:
            (j['i'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        audioUrl: j['a'] as String?,
        audioDurationMs: (j['ad'] as num?)?.toInt(),
        updatedAt:
            DateTime.tryParse((j['u'] as String?) ?? '') ?? DateTime.now(),
      );

  bool get isEmpty =>
      text.trim().isEmpty && imageUrls.isEmpty && (audioUrl ?? '').isEmpty;
}

class DraftService {
  DraftService._();
  static final DraftService instance = DraftService._();

  static const _key = 'gh_post_draft_v1';

  Future<void> save(PostDraft d) async {
    final prefs = await SharedPreferences.getInstance();
    if (d.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, jsonEncode(d.toJson()));
  }

  Future<PostDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PostDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
