import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../database/post_content_codec.dart';
import '../../database/services/favorite_service.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/voice_player.dart';

/// Страница закладок: сохранённые посты пользователя.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _posts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await FavoriteService.instance.listFavoritePosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _removePost(int postId) async {
    await FavoriteService.instance
        .toggle(kind: FavoriteKind.post, refId: postId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Закладки', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _postsList(),
    );
  }

  Widget _postsList() {
    if (_posts.isEmpty) {
      return const Center(
        child: Text(
          'Пока нет сохранённых постов',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (_, i) {
          final post = _posts[i];
          final postId = (post['id'] as num).toInt();
          final raw = post['content'] as String? ?? '';
          final d = decodePostContent(raw);
          final user = post['User'] as Map<String, dynamic>? ?? {};
          final createdAt =
              DateTime.tryParse(post['created_at'] as String? ?? '') ??
                  DateTime.now();

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${user['username'] ?? 'user'} · ${timeago.format(createdAt, locale: 'ru')}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark, color: Color(0xFF7C3AED)),
                      onPressed: () => _removePost(postId),
                      tooltip: 'Убрать из закладок',
                    ),
                  ],
                ),
                if (d.text.isNotEmpty)
                  Text(
                    d.text,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                if (d.hasVoice) ...[
                  const SizedBox(height: 8),
                  VoicePlayer(url: d.audioUrl!, durationMs: d.audioDurationMs),
                ],
                if (d.hasAttachments) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        d.attachments.map((a) => AttachmentTile(meta: a)).toList(),
                  ),
                ],
                if (d.hasTags) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: d.tags
                        .map(
                          (t) => Text(
                            '#$t',
                            style: const TextStyle(
                              color: Color(0xFF7C3AED),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: _posts.length,
      ),
    );
  }
}
