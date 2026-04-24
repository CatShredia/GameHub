import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../database/services/chat_service.dart';
import 'chat_screen.dart';

/// Профиль пользователя по [userId] и кнопка «Начать чат».
class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _row;
  bool _startingChat = false;

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
    try {
      final r = await Supabase.instance.client
          .from('User')
          .select('id, login, username, avatar, scope, created_at, date_of_birth')
          .eq('id', widget.userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _row = r;
        _loading = false;
        if (r == null) _error = 'Пользователь не найден';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startChat() async {
    final login = _row?['login'] as String?;
    if (login == null || login.isEmpty) return;

    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите в аккаунт')),
      );
      return;
    }
    if (me == widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Это ваш профиль')),
      );
      return;
    }

    setState(() => _startingChat = true);
    try {
      final chat = await ChatService().createPrivateChat(login);
      if (!mounted) return;
      if (chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать чат')),
        );
        return;
      }
      final name = (_row?['username'] as String?) ?? login;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: (chat['id'] as num).toInt(),
            chatName: name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Профиль'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final u = _row!;
    final login = u['login'] as String? ?? '';
    final name = u['username'] as String? ?? '';
    final avatar = u['avatar'] as String?;
    final scope = (u['scope'] as num?)?.toInt() ?? 0;

    final isSelf =
        Supabase.instance.client.auth.currentUser?.id == widget.userId;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFF7C3AED),
            backgroundImage:
                (avatar != null && avatar.isNotEmpty && avatar.startsWith('http'))
                    ? NetworkImage(avatar)
                    : null,
            child: (avatar == null || avatar.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '👤',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '@$login',
            style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 16),
          ),
        ),
        const SizedBox(height: 24),
        _tile(Icons.stars, 'Очки', '$scope ⭐'),
        if (!isSelf) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startingChat ? null : _startChat,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _startingChat
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_outline),
              label: Text(_startingChat ? '…' : 'Начать чат'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
