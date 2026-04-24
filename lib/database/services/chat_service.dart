import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// ? Сервис для работы с чатами через Supabase Realtime (WebSocket)
class ChatService {
  // ? Одиночка — единственный экземпляр на всё приложение
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  // ===== Стримы сообщений =====
  final Map<String, StreamController<List<Map<String, dynamic>>>> _msgStreams =
      {};
  final Map<String, RealtimeChannel> _msgChannels = {};
  final Map<String, List<Map<String, dynamic>>> _lastMessages = {};

  // ? Возвращает стрим сообщений для конкретного чата с Realtime-обновлениями
  Stream<List<Map<String, dynamic>>> messagesStream(dynamic chatId) {
    final key = chatId.toString();
    if (_msgStreams.containsKey(key)) {
      return _msgStreams[key]!.stream;
    }

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onCancel: () => _unsubscribeMessages(key),
    );

    _msgStreams[key] = controller;
    _subscribeMessages(key, controller);

    return controller.stream;
  }

  // ? Загружает начальные сообщения и подписывается на Realtime-изменения
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

    // ? Подписка на Realtime-изменения таблицы Message
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

  // ? Отписывается от Realtime-канала сообщений чата
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
  /// Одна инициализация на все подписчики (несколько StreamBuilder в вкладках).
  Future<void>? _chatsPipelineFuture;
  /// Последняя отданная в стрим витрина: новые подписчики на broadcast ничего не видят — отдаём кэш.
  List<Map<String, dynamic>>? _lastChatsSnapshot;
  /// Один [Stream] на всё приложение: иначе каждый rebuild/новая вкладка = новый стрим и вечный waiting.
  Stream<List<Map<String, dynamic>>>? _chatsStreamCache;

  // ? Список чатов: сначала [last] снимок, потом live broadcast (повторный вход на вкладку не ломается)
  Stream<List<Map<String, dynamic>>> get chatsStream {
    _chatsPipelineFuture ??= _ensureChatsPipeline();
    return _chatsStreamCache ??= _createChatsStreamWithReplay();
  }

  Stream<List<Map<String, dynamic>>> _createChatsStreamWithReplay() {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      controller.add(
        List<Map<String, dynamic>>.from(
          _lastChatsSnapshot ?? <Map<String, dynamic>>[],
        ),
      );
      final sub = _chatsController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );
      controller.onCancel = sub.cancel;
    });
  }

  void _emitChats(List<Map<String, dynamic>> list) {
    if (_chatsController.isClosed) return;
    _lastChatsSnapshot = List<Map<String, dynamic>>.from(list);
    _chatsController.add(_lastChatsSnapshot!);
  }

  /// Загрузка + Realtime. Без [hasListener]: иначе первая [add] чаще всего до подписки и спиннер вечен.
  Future<void> _ensureChatsPipeline() async {
    if (_chatsChannel != null) return;

    try {
      // Даём StreamBuilder'ам подписаться на broadcast, иначе первый add теряется.
      await Future<void>.delayed(Duration.zero);
      await _loadUserChats();
    } catch (e) {
      debugPrint('ChatService: ошибка первой загрузки чатов: $e');
      if (!_chatsController.isClosed) {
        _emitChats(<Map<String, dynamic>>[]);
      }
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('ChatService: пользователь не авторизован');
      return;
    }

    if (_chatsChannel != null) return;

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
              'ChatService[Realtime Message]: chat_id='
              '${payload.newRecord['chat_id']}',
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
              'ChatService[Realtime Chat]: id='
              '${payload.newRecord['id']}',
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

  // ? Загружает чаты пользователя с последними сообщениями
  Future<void> _loadUserChats() async {
    final user = supabase.auth.currentUser;
    debugPrint('ChatService: загрузка чатов, user=${user?.id ?? 'null'}');

    if (user == null) {
      if (!_chatsController.isClosed) {
        _emitChats(<Map<String, dynamic>>[]);
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

      if (!_chatsController.isClosed) {
        debugPrint(
          'ChatService: отправляю ${chatsWithLastMsg.length} чатов в стрим',
        );
        _emitChats(chatsWithLastMsg);
      }
    } catch (e, st) {
      debugPrint('ChatService: ошибка загрузки чатов: $e\n$st');
      if (!_chatsController.isClosed) {
        _emitChats(<Map<String, dynamic>>[]);
      }
    }
  }

  // ? Обновляет список чатов вручную (pull-to-refresh)
  Future<void> refreshChats() => _loadUserChats();

  // ? Отправляет сообщение в чат
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

  /// Каналы и группы, в которые пользователь ещё не вступил ([type_chat]: channel | group).
  Future<List<Map<String, dynamic>>> listDiscoverChats(String typeChat) async {
    final me = supabase.auth.currentUser;
    if (me == null) return [];

    final all = await supabase
        .from('Chat')
        .select('id, namechat, descriptions, type_chat, created_at')
        .eq('type_chat', typeChat)
        .order('created_at', ascending: false);

    final mine = await supabase
        .from('ChatMember')
        .select('chat_id')
        .eq('user_id', me.id);
    final myIds = <int>{
      for (final r in List<Map<String, dynamic>>.from(mine))
        (r['chat_id'] as num).toInt(),
    };

    return List<Map<String, dynamic>>.from(all)
        .where((c) => !myIds.contains(c['id']))
        .toList();
  }

  /// Вступить в чат/канал/группу (роль — участник).
  Future<String?> joinChat(int chatId) async {
    final me = supabase.auth.currentUser;
    if (me == null) return 'Войдите в аккаунт';
    try {
      await supabase.from('ChatMember').insert({
        'user_id': me.id,
        'chat_id': chatId,
        'role': 'member',
      });
      await _loadUserChats();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Создать канал или группу; создатель сразу участник.
  Future<Map<String, dynamic>?> createRoom({
    required String name,
    required String description,
    required String typeChat, // 'channel' | 'group'
  }) async {
    final me = supabase.auth.currentUser;
    if (me == null) return null;
    final chat = await supabase
        .from('Chat')
        .insert({
          'namechat': name.trim(),
          'descriptions': description.trim().isEmpty ? null : description.trim(),
          'type_chat': typeChat,
        })
        .select()
        .single();
    final id = (chat['id'] as num).toInt();
    await supabase.from('ChatMember').insert({
      'user_id': me.id,
      'chat_id': id,
      'role': 'admin',
    });
    await _loadUserChats();
    return chat;
  }

  // ? Создаёт приватный чат с другим пользователем
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

  // ? Закрывает все Realtime-подписки и стримы
  void disposeAll() {
    for (final key in _msgChannels.keys) {
      _msgChannels[key]?.unsubscribe();
    }
    _msgChannels.clear();
    _msgStreams.clear();
    _lastMessages.clear();

    _chatsChannel?.unsubscribe();
    _chatsChannel = null;
    _chatsPipelineFuture = null;
    _chatsStreamCache = null;
    _lastChatsSnapshot = null;
    if (!_chatsController.isClosed) _chatsController.close();
  }
}
