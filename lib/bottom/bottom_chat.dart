import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../database/services/chat_service.dart';
import 'mini_page/chat_screen.dart';

final supabase = Supabase.instance.client;

// ? Страница списка чатов пользователя
class BottomChat extends StatefulWidget {
  const BottomChat({super.key});

  @override
  State<BottomChat> createState() => _BottomChatState();
}

class _BottomChatState extends State<BottomChat> {
  final _chatService = ChatService();
  final _searchController = TextEditingController();
  final _createController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  // ? Создаёт новый приватный чат по логину пользователя
  Future<void> _createPrivateChat() async {
    final login = _createController.text.trim();
    if (login.isEmpty) return;

    try {
      final newChat = await _chatService.createPrivateChat(login);

      if (newChat == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пользователь не найден')),
          );
        }
        return;
      }

      _createController.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Чат создан')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  // ? Обновляет список чатов вручную
  Future<void> _refreshChats() async {
    await _chatService.refreshChats();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshChats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Text(
                '💬 Чаты',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),

            // ? Поле поиска и кнопка создания чата
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Поиск чатов...',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1430),
                          title: const Text(
                            'Новый чат',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: TextField(
                            controller: _createController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Логин пользователя',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _createPrivateChat();
                              },
                              child: const Text(
                                'Создать',
                                style: TextStyle(color: Color(0xFF7C3AED)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.add_circle,
                      color: Color(0xFF7C3AED),
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ? Список чатов через StreamBuilder с Realtime-обновлениями
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.chatsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(80),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Text(
                        'Ошибка: ${snapshot.error}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                final chats = snapshot.data ?? [];
                final query = _searchController.text.trim().toLowerCase();
                final filteredChats = query.isEmpty
                    ? chats
                    : chats.where((item) {
                        final name =
                            (item['chat'] as Map<String, dynamic>?)?['namechat']
                                ?.toString()
                                .toLowerCase() ??
                            '';
                        return name.contains(query);
                      }).toList();

                if (filteredChats.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 80,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Пока нет чатов',
                            style: TextStyle(fontSize: 20, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Создайте новый чат с помощью кнопки +',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredChats.length,
                  itemBuilder: (context, index) {
                    final item = filteredChats[index];
                    final chat = item['chat'] as Map<String, dynamic>?;
                    if (chat == null) return const SizedBox.shrink();

                    final name = chat['namechat'] as String? ?? 'Чат';
                    final avatar = name.isNotEmpty
                        ? name[0].toUpperCase()
                        : '💬';

                    final lastMsgList =
                        item['last_message'] as List<dynamic>? ?? [];
                    final lastMsg = lastMsgList.isNotEmpty
                        ? lastMsgList.first['content'] as String? ??
                              'Нет сообщений'
                        : 'Нет сообщений';

                    final time = lastMsgList.isNotEmpty
                        ? timeago.format(
                            DateTime.parse(lastMsgList.first['created_at']),
                            locale: 'ru',
                          )
                        : 'Недавно';

                    return _ChatItem(
                      name: name,
                      lastMsg: lastMsg,
                      time: time,
                      avatar: avatar,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ChatScreen(chatId: chat['id'], chatName: name),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _createController.dispose();
    super.dispose();
  }
}

// ? Виджет отдельного элемента чата в списке
class _ChatItem extends StatelessWidget {
  final String name, lastMsg, time, avatar;
  final VoidCallback? onTap;

  const _ChatItem({
    super.key,
    required this.name,
    required this.lastMsg,
    required this.time,
    required this.avatar,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFF7C3AED),
        child: Text(avatar, style: const TextStyle(fontSize: 26)),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        lastMsg,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Text(
        time,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }
}
