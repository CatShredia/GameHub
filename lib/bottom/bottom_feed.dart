import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../database/post_content_codec.dart';

final supabase = Supabase.instance.client;

// ? Лента в стиле Twitter: текст, фото, цитата, лайки/комменты с обновлением
class BottomFeed extends StatefulWidget {
  const BottomFeed({super.key});

  @override
  State<BottomFeed> createState() => _BottomFeedState();
}

class _BottomFeedState extends State<BottomFeed> {
  List<Map<String, dynamic>> _posts = [];
  Set<int> _likedPostIds = {};
  bool _isLoading = true;
  final _postController = TextEditingController();
  final _feedSearchController = TextEditingController();
  final List<String> _draftImages = [];
  Map<String, dynamic>? _quoteFrom;

  late final RealtimeChannel _postSub;
  late final RealtimeChannel _likeSub;
  late final RealtimeChannel _commentSub;

  @override
  void initState() {
    super.initState();
    _feedSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchPosts();
    _subscribeToChanges();
  }

  List<Map<String, dynamic>> _visiblePosts() {
    final q = _feedSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _posts;
    return _posts.where((post) {
      final user = post['user'] as Map<String, dynamic>? ?? {};
      final un = (user['username'] as String? ?? '').toLowerCase();
      final ln = (user['login'] as String? ?? '').toLowerCase();
      final raw = post['content'] as String? ?? '';
      final d = decodePostContent(raw);
      final searchBlob = [d.text, raw, un, '@$ln'].join(' ').toLowerCase();
      return searchBlob.contains(q);
    }).toList();
  }

  Future<void> _syncLikedFlags(List<int> postIds) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null || postIds.isEmpty) {
      _likedPostIds = {};
      return;
    }
    final rows = await supabase
        .from('PostLike')
        .select('post_id')
        .eq('user_id', me);
    final want = postIds.toSet();
    final set = <int>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final pid = (r['post_id'] as num).toInt();
      if (want.contains(pid)) set.add(pid);
    }
    _likedPostIds = set;
  }

  Future<void> _syncLikeCount(int postId) async {
    final rows = await supabase
        .from('PostLike')
        .select('id')
        .eq('post_id', postId);
    final n = List.from(rows).length;
    try {
      await supabase.from('Post').update({'like': n}).eq('id', postId);
    } catch (_) {
      /* колонка like может быть зарезервирована в RLS */
    }
  }

  Future<void> _fetchPosts() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('Post')
          .select('''
            id,
            created_at,
            content,
            like,
            user:User!user_id (username, avatar, login),
            likes:PostLike!post_id (count),
            comments:Comment!post_id (count)
          ''')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data);
      final ids = list.map((e) => (e['id'] as num).toInt()).toList();
      await _syncLikedFlags(ids);

      setState(() {
        _posts = list;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Лента: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToChanges() {
    _postSub = supabase
        .channel('post_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Post',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _likeSub = supabase
        .channel('like_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'PostLike',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();

    _commentSub = supabase
        .channel('comment_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Comment',
          callback: (_) => _fetchPosts(),
        )
        .subscribe();
  }

  Future<void> _toggleLike(int postId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final existing = await supabase
          .from('PostLike')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        await supabase.from('PostLike').delete().eq('id', existing['id']);
        _likedPostIds.remove(postId);
      } else {
        await supabase.from('PostLike').insert({
          'user_id': user.id,
          'post_id': postId,
        });
        _likedPostIds.add(postId);
      }
      await _syncLikeCount(postId);
      await _fetchPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка лайка: $e')),
        );
      }
    }
  }

  Future<void> _addComment(int postId, String text) async {
    final user = supabase.auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    try {
      await supabase.from('Comment').insert({
        'user_id': user.id,
        'post_id': postId,
        'content': text.trim(),
      });
      await _fetchPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Комментарий: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите в аккаунт')),
      );
      return;
    }
    try {
      final bytes = await x.readAsBytes();
      final path = 'feed/${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      if (!mounted) return;
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      setState(() => _draftImages.add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Загрузка фото: $e')),
        );
      }
    }
  }

  Future<void> _publishPost() async {
    final base = _postController.text.trim();
    if (base.isEmpty && _draftImages.isEmpty && _quoteFrom == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите в аккаунт')),
      );
      return;
    }

    Map<String, dynamic>? qs;
    int? qid;
    if (_quoteFrom != null) {
      final idRaw = _quoteFrom!['id'];
      qid = idRaw is int ? idRaw : (idRaw as num).toInt();
      final u = _quoteFrom!['user'] as Map<String, dynamic>? ?? {};
      qs = {
        'id': qid,
        'text': (_quoteFrom!['content'] as String?) ?? '',
        'user': u['username'] ?? u['login'] ?? '',
        'login': u['login'],
      };
    }

    final encoded = encodePostContent(
      PostContentData(
        text: base,
        imageUrls: List.from(_draftImages),
        quotePostId: qid,
        quoteSnapshot: qs,
      ),
    );

    try {
      await supabase.from('Post').insert({
        'user_id': user.id,
        'content': encoded,
      });
      _postController.clear();
      setState(() {
        _draftImages.clear();
        _quoteFrom = null;
      });
      await _fetchPosts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пост опубликован')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _showComments(int postId) {
    final controller = TextEditingController();
    var ver = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setModal) {
              Future<List<Map<String, dynamic>>> load() async {
                final r = await supabase
                    .from('Comment')
                    .select('''
                      id, content, created_at,
                      user:User!user_id (username, login, avatar)
                    ''')
                    .eq('post_id', postId)
                    .order('created_at', ascending: true);
                return List<Map<String, dynamic>>.from(r);
              }

              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Комментарии',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      key: ValueKey(ver),
                      future: load(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final comments = snapshot.data!;
                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: comments.length,
                          itemBuilder: (context, i) {
                            final c = comments[i];
                            final u = c['user'] as Map<String, dynamic>? ?? {};
                            final un = u['username'] as String? ?? 'user';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF7C3AED),
                                child: Text(
                                  un.isNotEmpty ? un[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                un,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                c['content'] ?? '',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: Text(
                                timeago.format(
                                  DateTime.parse(c['created_at'] as String),
                                  locale: 'ru',
                                ),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      MediaQuery.of(context).viewInsets.bottom + 20,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Комментарий...',
                              hintStyle: const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
                          onPressed: () async {
                            await _addComment(postId, controller.text);
                            controller.clear();
                            ver++;
                            setModal(() {});
                            await _fetchPosts();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _postSub.unsubscribe();
    _likeSub.unsubscribe();
    _commentSub.unsubscribe();
    _postController.dispose();
    _feedSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser;
    final visible = _visiblePosts();

    return RefreshIndicator(
      color: const Color(0xFF7C3AED),
      onRefresh: _fetchPosts,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Лента',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Посты, фото и репосты с комментарием',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _feedSearchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск в ленте: текст, @логин, имя...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 22),
                      suffixIcon: _feedSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                              onPressed: () {
                                _feedSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_quoteFrom != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D1B69).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.format_quote, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Цитата: ${_previewText(_quoteFrom!['content'] as String? ?? '')}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                            onPressed: () => setState(() => _quoteFrom = null),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF7C3AED),
                              radius: 20,
                              child: Text(
                                me?.email?.isNotEmpty == true
                                    ? me!.email![0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _postController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: 'Что нового?',
                                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                                  border: InputBorder.none,
                                ),
                                minLines: 2,
                                maxLines: 6,
                              ),
                            ),
                          ],
                        ),
                        if (_draftImages.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _draftImages
                                .map(
                                  (u) => Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          u,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: InkWell(
                                          onTap: () =>
                                              setState(() => _draftImages.remove(u)),
                                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image_outlined, color: Color(0xFF7C3AED)),
                              tooltip: 'Фото',
                            ),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: _publishPost,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Опубликовать',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text('Пока нет постов', style: TextStyle(color: Colors.grey)),
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Ничего не найдено по «${_feedSearchController.text.trim()}»',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final post = visible[index];
                  final postId = (post['id'] as num).toInt();
                  final userData = post['user'] as Map<String, dynamic>? ?? {};
                  final username = userData['username'] as String? ?? 'Пользователь';
                  final login = userData['login'] as String? ?? '';
                  final time = timeago.format(
                    DateTime.parse(post['created_at'] as String),
                    locale: 'ru',
                  );
                  final rawContent = post['content'] as String? ?? '';
                  final parsed = decodePostContent(rawContent);

                  final likesCount = (() {
                    final likes = post['likes'];
                    if (likes is List && likes.isNotEmpty) {
                      return (likes[0]['count'] as int?) ?? 0;
                    }
                    return 0;
                  })();

                  final commentsCount = (() {
                    final c = post['comments'];
                    if (c is List && c.isNotEmpty) {
                      return (c[0]['count'] as int?) ?? 0;
                    }
                    return 0;
                  })();

                  return _PostCardX(
                    postId: postId,
                    username: username,
                    login: login,
                    time: time,
                    parsed: parsed,
                    rawFallback: rawContent,
                    likes: likesCount,
                    comments: commentsCount,
                    liked: _likedPostIds.contains(postId),
                    onLike: () => _toggleLike(postId),
                    onComment: () {
                      _showComments(postId);
                    },
                    onQuote: () {
                      setState(() {
                        _quoteFrom = {
                          'id': postId,
                          'content': rawContent,
                          'user': userData,
                        };
                      });
                    },
                  );
                },
                childCount: visible.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

String _previewText(String s) {
  if (s.startsWith('GHPOST:')) {
    final d = decodePostContent(s);
    return d.text.isNotEmpty ? d.text : (s.length > 80 ? '${s.substring(0, 80)}…' : s);
  }
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}

class _PostCardX extends StatelessWidget {
  final int postId;
  final String username;
  final String login;
  final String time;
  final PostContentData parsed;
  final String rawFallback;
  final int likes;
  final int comments;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onQuote;

  const _PostCardX({
    required this.postId,
    required this.username,
    required this.login,
    required this.time,
    required this.parsed,
    required this.rawFallback,
    required this.likes,
    required this.comments,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onQuote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: const Border(
          top: BorderSide(color: Color(0xFF2F3336), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF7C3AED),
                child: Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '@$login',
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const Text(' · ', style: TextStyle(color: Colors.grey)),
                        Text(
                          time,
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                    if (parsed.text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        parsed.text,
                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                      ),
                    ] else if (!parsed.hasMedia && !parsed.hasQuote) ...[
                      const SizedBox(height: 6),
                      Text(
                        _stripCodec(rawFallback),
                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                      ),
                    ],
                    if (parsed.hasQuote) _QuoteBlock(data: parsed),
                    if (parsed.hasMedia) ...[
                      const SizedBox(height: 10),
                      ...parsed.imageUrls.map(
                        (u) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              u,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Text('…'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onComment,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('$comments', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: onQuote,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.repeat, size: 18, color: Colors.grey),
                      SizedBox(width: 4),
                      Text('Цитата', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: onLike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: liked ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likes',
                        style: TextStyle(
                          color: liked ? Colors.red : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stripCodec(String raw) {
    if (raw.startsWith('GHPOST:')) {
      return decodePostContent(raw).text;
    }
    return raw;
  }
}

class _QuoteBlock extends StatelessWidget {
  final PostContentData data;

  const _QuoteBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = data.quoteSnapshot;
    final preview = s?['text'] as String? ?? '';
    final u = s?['user'] as String? ?? s?['login'] as String? ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF536471)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (u.isNotEmpty)
            Text(
              u,
              style: const TextStyle(
                color: Color(0xFF7C3AED),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (preview.isNotEmpty)
            Text(
              preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.3),
            ),
        ],
      ),
    );
  }
}
