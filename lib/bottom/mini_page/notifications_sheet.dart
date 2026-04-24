import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../database/services/profile_service.dart';

/// Лист уведомлений: загрузка внутри виджета (корректный loading/список).
class NotificationsSheet extends StatefulWidget {
  final ProfileService profileService;

  const NotificationsSheet({super.key, required this.profileService});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Не авторизован';
      });
      return;
    }
    try {
      final list = await widget.profileService.getNotifications(user.id);
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inHours < 1) return '${diff.inMinutes} мин.';
      if (diff.inDays < 1) return '${diff.inHours} ч.';
      return '${date.day}.${date.month}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _markAll() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await widget.profileService.markAllNotificationsAsRead(user.id);
    setState(() {
      for (final n in _items) {
        n['is_watched'] = true;
      }
    });
  }

  Future<void> _markOne(int index) async {
    final id = _items[index]['id'];
    await widget.profileService.markNotificationAsRead(id);
    if (mounted) {
      setState(() {
        _items[index]['is_watched'] = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Уведомления',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              TextButton(
                onPressed: _items.isEmpty || _loading ? null : _markAll,
                child: const Text(
                  'Все прочитаны',
                  style: TextStyle(color: Color(0xFF7C3AED)),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Пока нет уведомлений',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF7C3AED),
                onRefresh: _load,
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (context, index) {
                    final notif = _items[index];
                    final isRead = notif['is_watched'] == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isRead
                            ? Colors.grey.withValues(alpha: 0.3)
                            : const Color(0xFF7C3AED),
                        child: Text(
                          isRead ? '✓' : '•',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        '${notif['title'] ?? 'Событие'}',
                        style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${notif['content'] ?? ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Text(
                        _formatDate(notif['created_at']?.toString()),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                      onTap: () => _markOne(index),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
