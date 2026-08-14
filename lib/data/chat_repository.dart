import 'package:handy_tdlib/api.dart' as td;

import '../telegram/telegram_client.dart';
import 'app_database.dart';
import 'message_mapping.dart';

/// One row in the chats list.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.lastMessageDate,
    required this.unreadCount,
  });

  final int id;
  final String title;

  /// A one-line preview. Empty when the chat has no messages yet.
  final String lastMessage;

  final int lastMessageDate;
  final int unreadCount;
}

/// One message in a conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.date,
    required this.isOutgoing,
    required this.fields,
  });

  final int id;
  final int date;

  /// Sent by you, which is what puts it on the right of the thread.
  final bool isOutgoing;

  final MessageContentFields fields;
}

/// The chats list and one conversation at a time.
///
/// Separate from [MessageRepository] on purpose. That one owns the *feed*: it
/// persists channel posts to SQLite, ranks them and pages them with a keyset.
/// Conversations are read straight from TDLib and never stored — a chat is a live
/// thing you scroll to the bottom of, not a corpus to query.
class ChatRepository {
  ChatRepository({required TelegramClient client}) : _client = client;

  final TelegramClient _client;

  /// Ceiling on how many chats are examined per load, whatever the caller asks
  /// for. One `getChat` each, so this is the worst-case round-trip count.
  static const _maxScan = 120;

  /// One-to-one chats with people, most recent first. Nothing else.
  ///
  /// Private chats only — no channels, no supergroups, no basic groups. This
  /// account follows enough channels that they buried the handful of real
  /// conversations, and groups did the same on a smaller scale. Channels already
  /// have two whole tabs of their own.
  ///
  /// Bots are excluded as well. They are private chats technically, but a
  /// download bot or a search bot is a tool you issue commands to, not someone
  /// you have a conversation with — and on this account they outnumber the
  /// people.
  ///
  /// Secret chats are excluded too: they are bound to the device that created
  /// them, so surfacing them from a second client mostly produces rows that
  /// cannot be read.
  ///
  /// `loadChats` first: `getChats` only answers from what TDLib has already
  /// loaded into memory, so on a cold start it returns a short list or nothing at
  /// all. Asking it to load is what makes the first open of this tab show
  /// something. The 404 is expected and means "nothing more to load".
  Future<List<ChatSummary>> chats({int limit = 40}) async {
    // Over-fetch, but bounded. Channels are filtered out below and they
    // outnumber conversations badly on this account, so asking for exactly
    // `limit` would return a handful of rows once they are dropped. The cap
    // matters as much as the multiplier: every id costs a `getChat`, and an
    // unbounded scan is a long serial stall on a cold cache — which is exactly
    // what a spinner that never resolves looks like.
    final fetch = (limit * 4).clamp(0, _maxScan);
    try {
      await _client.send<td.Ok>(
        td.LoadChats(chatList: const td.ChatListMain(), limit: fetch),
      );
    } catch (_) {
      // 404 = the list is fully loaded already. Any other failure still leaves
      // getChats below able to answer from cache.
    }

    final chats = await _client.send<td.Chats>(
      td.GetChats(chatList: const td.ChatListMain(), limit: fetch),
    );

    final summaries = <ChatSummary>[];
    var scanned = 0;
    for (final id in chats.chatIds) {
      if (summaries.length >= limit || scanned >= _maxScan) break;
      scanned++;
      try {
        final chat = await _client.send<td.Chat>(td.GetChat(chatId: id));
        final last = chat.lastMessage;

        // Whitelist rather than a list of exclusions: TDLib gains chat types
        // over time, and "everything except the three I thought of" would let a
        // new one back into a list that is supposed to be people.
        final type = chat.type;
        if (type is! td.ChatTypePrivate) continue;
        if (await _isBot(type.userId)) continue;

        summaries.add(ChatSummary(
          id: chat.id,
          title: chat.title,
          lastMessage:
              last == null ? '' : _preview(contentFieldsOf(last.content)),
          lastMessageDate: last?.date ?? 0,
          unreadCount: chat.unreadCount,
        ));
      } catch (_) {
        // One inaccessible chat must not empty the whole list.
      }
    }

    return summaries;
  }

  /// Whether a user id belongs to a bot.
  ///
  /// Cached for the life of the repository: the answer never changes for a given
  /// id, and without this every reload of the list would re-ask about the same
  /// accounts.
  final _botCache = <int, bool>{};

  Future<bool> _isBot(int userId) async {
    final known = _botCache[userId];
    if (known != null) return known;

    try {
      final user = await _client.send<td.User>(td.GetUser(userId: userId));
      final isBot = user.type is td.UserTypeBot;
      _botCache[userId] = isBot;
      return isBot;
    } catch (_) {
      // Unknown means keep it: dropping a chat because one lookup failed is
      // worse than showing one bot.
      return false;
    }
  }

  /// Newest messages in a chat, oldest first so the list reads top to bottom.
  Future<List<ChatMessage>> history(int chatId, {int limit = 50}) async {
    final messages = await _client.send<td.Messages>(
      td.GetChatHistory(
        chatId: chatId,
        fromMessageId: 0,
        offset: 0,
        limit: limit,
        onlyLocal: false,
      ),
    );

    return [
      // TDLib answers newest-first; a conversation reads the other way.
      for (final message in messages.messages.reversed)
        ChatMessage(
          id: message.id,
          date: message.date,
          isOutgoing: message.isOutgoing,
          fields: contentFieldsOf(message.content),
        ),
    ];
  }

  /// Sends a plain text message.
  Future<void> send(int chatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _client.send<td.Message>(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        inputMessageContent: td.InputMessageText(
          // No entities: what was typed stays literal rather than having
          // anything that looks like markup silently reinterpreted.
          text: td.FormattedText(text: trimmed, entities: const []),
          clearDraft: true,
        ),
      ),
    );
  }

  /// Marks the chat read, so the unread badge in the list clears.
  Future<void> markRead(int chatId, Iterable<int> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      await _client.send<td.Ok>(td.ViewMessages(
        chatId: chatId,
        messageIds: messageIds.toList(),
        source: null,
        forceRead: true,
      ));
    } catch (_) {
      // Cosmetic. A badge that stays put is not worth surfacing an error for.
    }
  }

  /// One line for the list. Media without a caption still needs to say
  /// *something*, or a photo-only chat shows a blank row.
  String _preview(MessageContentFields fields) {
    final text = fields.text.trim();
    if (text.isNotEmpty) return text.replaceAll('\n', ' ');
    return switch (fields.kind) {
      ContentKind.photo => 'Photo',
      ContentKind.video => 'Video',
      ContentKind.animation => 'GIF',
      ContentKind.document => 'File',
      ContentKind.audio => 'Audio',
      ContentKind.voice => 'Voice message',
      ContentKind.poll => 'Poll',
      ContentKind.text => '',
      ContentKind.other => '',
    };
  }
}
