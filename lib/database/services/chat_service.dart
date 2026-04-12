import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// Сервис для работы с чатами через Supabase Realtime (WebSocket).
class ChatService {
  // ===== Одиночка =====
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  // ===== Стрим сообщений =====
  final Map<String, StreamController<List<Map<String, dynamic>>>> _msgStreams =
      {};
  final Map<String, RealtimeChannel> _msgChannels = {};
  final Map<String, List<Map<String, dynamic>>> _lastMessages = {};

  /// Возвращает стрим сообщений для конкретного чата.
  Stream<List<Map<String, dynamic>>> messagesStream(dynamic chatId) {
    final key = chatId.toString();
    if (_msgStreams.containsKey(key)) {
      return _msgStreams[key]!.stream;
    }

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onCancel: () {
        _unsubscribeMessages(key);
      },
    );

    _msgStreams[key] = controller;
    _subscribeMessages(key, controller);

    return controller.stream;
  }

  Future<void> _subscribeMessages(
    String chatKey,
    StreamController<List<Map<String, dynamic>>> controller,
  ) async {
    debugPrint('ChatService[_subscribeMessages]: chatKey=$chatKey');

    try {
      final data = await supabase
          .from('Message')
          .select('id, content, created_at, sender_id')
          .eq('chat_id', chatKey)
          .order('created_at', ascending: true);

      final messages = List<Map<String, dynamic>>.from(data);
      _lastMessages[chatKey] = messages;
      debugPrint(
        'ChatService[_subscribeMessages]: загружено ${messages.length} сообщений',
      );
      controller.add(messages);
    } catch (e, st) {
      debugPrint('ChatService[_subscribeMessages]: ошибка загрузки: $e\n$st');
      controller.addError(e, st);
      return;
    }

    // Подписка на Realtime
    debugPrint('ChatService: создаю канал msg:$chatKey');
    final channel = supabase
        .channel('msg:$chatKey')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'Message',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatKey,
          ),
          callback: (payload) {
            debugPrint(
              'ChatService[Realtime EVENT]: '
              'event=${payload.eventType}, '
              'chatKey=$chatKey, '
              'newRecordKeys=${payload.newRecord.keys.toList()}, '
              'hasListener=${controller.hasListener}',
            );

            final current = List<Map<String, dynamic>>.from(
              _lastMessages[chatKey] ?? [],
            );
            final eventType = payload.eventType;

            if (eventType == PostgresChangeEvent.insert) {
              final newMsg = Map<String, dynamic>.from(payload.newRecord);
              if (newMsg['id'] is String) {
                newMsg['id'] =
                    int.tryParse(newMsg['id'].toString()) ?? newMsg['id'];
              }
              current.add(newMsg);
              current.sort(
                (a, b) => DateTime.parse(
                  a['created_at'] as String,
                ).compareTo(DateTime.parse(b['created_at'] as String)),
              );
              debugPrint(
                'ChatService[Realtime]: INSERT, теперь ${current.length} сообщений',
              );
            } else if (eventType == PostgresChangeEvent.update) {
              final updated = payload.newRecord;
              final idx = current.indexWhere(
                (m) => m['id'].toString() == updated['id'].toString(),
              );
              if (idx != -1) {
                current[idx] = Map<String, dynamic>.from(updated);
                debugPrint('ChatService[Realtime]: UPDATE на индексе $idx');
              }
            } else if (eventType == PostgresChangeEvent.delete) {
              final deleted = payload.oldRecord;
              final before = current.length;
              current.removeWhere(
                (m) => m['id'].toString() == deleted['id'].toString(),
              );
              debugPrint(
                'ChatService[Realtime]: DELETE, было $before, стало ${current.length}',
              );
            }

            _lastMessages[chatKey] = current;
            debugPrint(
              'ChatService[Realtime]: controller.hasListener=${controller.hasListener}',
            );
            if (controller.hasListener) {
              controller.add(current);
              debugPrint('ChatService[Realtime]: событие отправлено в стрим');
            } else {
              debugPrint('ChatService[Realtime]: ВНИМАНИЕ — нет слушателей!');
            }
          },
        )
        .subscribe((status, [errorMsg]) {
          debugPrint(
            'ChatService[subscribe STATUS]: '
            'channel=msg:$chatKey, status=$status, error=$errorMsg',
          );
        });

    _msgChannels[chatKey] = channel;
  }

  void _unsubscribeMessages(String chatKey) {
    debugPrint('ChatService: отписка от сообщений chatKey=$chatKey');
    _msgChannels[chatKey]?.unsubscribe();
    _msgChannels.remove(chatKey);
    _msgStreams.remove(chatKey);
    _lastMessages.remove(chatKey);
  }

  // ===== Стрим чатов пользователя =====
  final StreamController<List<Map<String, dynamic>>> _chatsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  RealtimeChannel? _chatsChannel;

  Stream<List<Map<String, dynamic>>> get chatsStream {
    _initChatsStream();
    return _chatsController.stream;
  }

  Future<void> _initChatsStream() async {
    if (_chatsChannel != null) return;

    debugPrint('ChatService: инициализация стрима чатов');

    try {
      await _loadUserChats();
    } catch (e) {
      debugPrint('ChatService: ошибка инициализации: $e');
      if (!_chatsController.isClosed && _chatsController.hasListener) {
        _chatsController.add([]);
      }
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('ChatService: пользователь не авторизован');
      return;
    }

    // Уникальное имя канала для каждого пользователя
    final channelName = 'chats:$userId';
    debugPrint('ChatService: создаю канал $channelName');

    _chatsChannel = supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'Message',
          callback: (payload) {
            debugPrint(
              'ChatService[Realtime Message]: '
              'событие=INSERT, chat_id=${payload.newRecord['chat_id']}, '
              'content=${payload.newRecord['content']}',
            );
            _loadUserChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'Chat',
          callback: (payload) {
            debugPrint(
              'ChatService[Realtime Chat]: '
              'событие=INSERT, chat_id=${payload.newRecord['id']}',
            );
            _loadUserChats();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ChatMember',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            debugPrint('ChatService[Realtime ChatMember]: перезагрузка');
            _loadUserChats();
          },
        )
        .subscribe((status, [errorMsg]) {
          debugPrint(
            'ChatService[chats subscribe]: '
            'channel=$channelName, status=$status, error=$errorMsg',
          );
        });
  }

  Future<void> _loadUserChats() async {
    final user = supabase.auth.currentUser;
    debugPrint('ChatService: загрузка чатов, user=${user?.id ?? "null"}');

    if (user == null) {
      if (!_chatsController.isClosed && _chatsController.hasListener) {
        _chatsController.add([]);
      }
      return;
    }

    try {
      final response = await supabase
          .from('ChatMember')
          .select('''
            chat:Chat (
              id,
              namechat,
              type_chat,
              created_at
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false, referencedTable: 'chat');

      debugPrint('ChatService: найдено ${response.length} чатов');

      final chatsWithLastMsg = <Map<String, dynamic>>[];
      for (final row in response) {
        final chatData = row['chat'];
        if (chatData == null) continue;

        final chatId = chatData['id'];
        final lastMessage = await supabase
            .from('Message')
            .select('content, created_at, sender_id')
            .eq('chat_id', chatId)
            .order('created_at', ascending: false)
            .limit(1);

        chatsWithLastMsg.add({...row, 'last_message': lastMessage});
      }

      if (!_chatsController.isClosed && _chatsController.hasListener) {
        debugPrint(
          'ChatService: отправляю ${chatsWithLastMsg.length} чатов в стрим',
        );
        _chatsController.add(chatsWithLastMsg);
      }
    } catch (e, st) {
      debugPrint('ChatService: ошибка загрузки чатов: $e\n$st');
      if (!_chatsController.isClosed && _chatsController.hasListener) {
        _chatsController.addError(e);
      }
    }
  }

  Future<void> refreshChats() => _loadUserChats();

  Future<void> sendMessage({
    required dynamic chatId,
    required String content,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || content.trim().isEmpty) return;

    await supabase.from('Message').insert({
      'chat_id': chatId is int
          ? chatId
          : int.tryParse(chatId.toString()) ?? chatId,
      'sender_id': user.id,
      'content': content.trim(),
      'status': true,
    });
  }

  Future<Map<String, dynamic>?> createPrivateChat(String targetLogin) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return null;

    final target = await supabase
        .from('User')
        .select('id, username')
        .eq('login', targetLogin)
        .maybeSingle();

    if (target == null) return null;

    final newChat = await supabase
        .from('Chat')
        .insert({'namechat': target['username'], 'type_chat': 'private'})
        .select()
        .single();

    await supabase.from('ChatMember').insert([
      {'user_id': currentUser.id, 'chat_id': newChat['id']},
      {'user_id': target['id'], 'chat_id': newChat['id']},
    ]);

    await _loadUserChats();
    return newChat;
  }

  void disposeAll() {
    for (final key in _msgChannels.keys) {
      _msgChannels[key]?.unsubscribe();
    }
    _msgChannels.clear();
    _msgStreams.clear();
    _lastMessages.clear();

    _chatsChannel?.unsubscribe();
    _chatsChannel = null;
    if (!_chatsController.isClosed) _chatsController.close();
  }
}
