import 'dart:async';

import 'package:drift/drift.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../telegram/td_exception.dart';
import '../telegram/telegram_client.dart';
import 'app_database.dart';
import 'for_you_repository.dart';
import 'message_mapping.dart';

/// One feed row: a post plus the channel that published it.
class FeedEntry {
  const FeedEntry({required this.message, required this.channel});

  final Message message;
  final Channel channel;
}

/// Opaque position in the feed for keyset pagination.
class FeedCursor {
  const FeedCursor({required this.date, required this.messageId});

  final int date;
  final int messageId;
}

/// Backfill, live sync, and the feed queries.
class MessageRepository {
  MessageRepository({required TelegramClient client, required AppDatabase db})
    : _client = client,
      _db = db;

  final TelegramClient _client;
  final AppDatabase _db;

  /// Set by the app scope. Ranking lives in its own repository, but the counters
  /// that drive it arrive here, so this is where rescoring has to be triggered
  /// from.
  ForYouRepository? forYou;

  /// Chats currently open for live push. TDLib pushes `updateNewMessage` only
  /// for open chats, but hundreds of open chats is exactly the pattern that gets
  /// accounts flagged, so this stays bounded.
  static const _maxOpenChats = 20;
  final _openChats = <int>{};

  StreamSubscription<td.Update>? _updates;

  // ---------------------------------------------------------------------------
  // Backfill
  // ---------------------------------------------------------------------------

  /// Pulls history for one channel, newest first.
  ///
  /// The retry loop is not defensive padding — it is required. TDLib answers
  /// `getChatHistory` from its **local cache first**, so the opening call on a
  /// channel it has never fetched routinely returns zero or a handful of rows
  /// while it goes to the network in the background. Treating that as
  /// end-of-history is the classic way to end up with an almost-empty feed, so
  /// only [_emptyRoundsBeforeStop] consecutive empty replies count as the end.
  Future<int> backfillChannel(int chatId, {int target = 60}) async {
    await _openChat(chatId);

    final collected = <int, td.Message>{};
    var fromMessageId = 0; // 0 = start from the newest message
    var emptyRounds = 0;

    try {
      while (collected.length < target &&
          emptyRounds < _emptyRoundsBeforeStop) {
        final td.Messages batch;
        try {
          batch = await _client.send<td.Messages>(
            td.GetChatHistory(
              chatId: chatId,
              fromMessageId: fromMessageId,
              offset: 0,
              limit: 100,
              onlyLocal: false,
            ),
          );
        } on TdException catch (e) {
          final flood = e.floodWait;
          if (flood != null) {
            // Full duration, every time.
            await Future<void>.delayed(flood);
            continue;
          }
          rethrow;
        }

        if (batch.messages.isEmpty) {
          emptyRounds++;
          continue;
        }

        emptyRounds = 0;
        for (final message in batch.messages) {
          collected[message.id] = message;
        }
        // Walk backwards from the oldest message in this batch.
        fromMessageId = batch.messages.last.id;
      }
    } finally {
      await _closeChat(chatId);
    }

    if (collected.isEmpty) return 0;
    await _persist(collected.values);
    await _advanceCursor(
      chatId,
      collected.keys.reduce((a, b) => a > b ? a : b),
    );
    return collected.length;
  }

  static const _emptyRoundsBeforeStop = 3;

  /// Backfills every tracked channel, **one at a time**.
  ///
  /// Sequential by design: parallel history pulls are the single fastest way to
  /// get an account rate-limited or flagged.
  /// Backfills every channel that is in at least one list.
  ///
  /// Orphans are skipped: they are a cache, and spending requests refreshing
  /// channels no feed can show is exactly the kind of avoidable traffic the rate
  /// limits punish.
  Future<int> backfillAll({
    int perChannel = 60,
    void Function(int done, int total)? onProgress,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT chat_id FROM channel_lists',
          readsFrom: {_db.channelLists},
        )
        .get();
    return backfillChannels(
      [for (final row in rows) row.read<int>('chat_id')],
      perChannel: perChannel,
      onProgress: onProgress,
    );
  }

  /// Backfills the given channels sequentially, tolerating per-channel failures.
  ///
  /// The guard is not optional: `getChatHistory` on a channel the account
  /// cannot view answers `400: Can't access the chat`. A hand-added handle can
  /// be private, renamed, or deleted, and letting that propagate would abort
  /// the whole pass on the first bad one.
  Future<int> backfillChannels(
    Iterable<int> chatIds, {
    int perChannel = 60,
    void Function(int done, int total)? onProgress,
  }) async {
    final ids = chatIds.toList();
    var total = 0;

    for (var i = 0; i < ids.length; i++) {
      try {
        total += await backfillChannel(ids[i], target: perChannel);
      } on TdException {
        // Inaccessible, private, or gone — skip it and keep going.
      }
      onProgress?.call(i + 1, ids.length);
    }

    // Scores are recomputed once per pass, not per channel: `m` is an aggregate
    // over the whole window and would otherwise be recalculated 150 times.
    await forYou?.recomputeScores();

    return total;
  }

  /// Fetches only what is *newer* than what we already hold, for pull-to-refresh.
  ///
  /// Deliberately not a backfill: it walks forward from `last_synced_message_id`
  /// and stops as soon as it reaches known ground, so a refresh costs one small
  /// request per channel rather than re-reading history. Sequential with full
  /// FLOOD_WAIT sleeps, like every other network pass — a pull-to-refresh across
  /// 150 channels is exactly where an impatient implementation gets an account
  /// limited.
  Future<int> refreshChannels(
    Iterable<int> chatIds, {
    int perChannel = 30,
    void Function(int done, int total)? onProgress,
  }) async {
    final ids = chatIds.toList();
    var fetched = 0;

    for (var i = 0; i < ids.length; i++) {
      try {
        fetched += await _refreshChannel(ids[i], limit: perChannel);
      } on TdException {
        // One unreachable channel must not fail the whole gesture.
      }
      onProgress?.call(i + 1, ids.length);
    }

    await forYou?.recomputeScores();

    return fetched;
  }

  Future<int> _refreshChannel(int chatId, {required int limit}) async {
    final cursor = await (_db.select(
      _db.channels,
    )..where((c) => c.id.equals(chatId))).getSingleOrNull();

    await _openChat(chatId);
    try {
      final batch = await _client.send<td.Messages>(
        td.GetChatHistory(
          chatId: chatId,
          // 0 means "from the newest", which is what a refresh wants.
          fromMessageId: 0,
          offset: 0,
          limit: limit,
          onlyLocal: false,
        ),
      );

      if (batch.messages.isEmpty) return 0;

      final known = cursor?.lastSyncedMessageId ?? 0;
      // Only genuinely new posts. Re-persisting known ones would be harmless but
      // pointless work on every pull.
      final fresh = batch.messages.where((m) => m.id > known).toList();
      if (fresh.isEmpty) return 0;

      await _persist(fresh);
      await _advanceCursor(
        chatId,
        fresh.map((m) => m.id).reduce((a, b) => a > b ? a : b),
      );
      return fresh.length;
    } on TdException catch (e) {
      final flood = e.floodWait;
      if (flood != null) {
        // Full duration. A refresh is not urgent enough to justify shortening it.
        await Future<void>.delayed(flood);
        return 0;
      }
      rethrow;
    } finally {
      await _closeChat(chatId);
    }
  }

  // ---------------------------------------------------------------------------
  // Live sync
  // ---------------------------------------------------------------------------

  /// Applies incoming TDLib updates to the local store.
  ///
  /// Deletions and edits are handled here as well as inserts, because a cache
  /// that keeps serving removed posts is worse than no cache.
  void startLiveUpdates() {
    _updates ??= _client.updates.listen((update) async {
      switch (update) {
        case td.UpdateNewMessage(:final message):
          if (await _isTracked(message.chatId)) {
            await _persist([message]);
            await _advanceCursor(message.chatId, message.id);
          }

        // Carries only the new edit timestamp — the replacement content arrives
        // separately as updateMessageContent.
        case td.UpdateMessageEdited(
          :final chatId,
          :final messageId,
          :final editDate,
        ):
          await (_db.update(_db.messages)..where(
                (m) => m.chatId.equals(chatId) & m.messageId.equals(messageId),
              ))
              .write(MessagesCompanion(editDate: Value(editDate)));

        case td.UpdateMessageContent(
          :final chatId,
          :final messageId,
          :final newContent,
        ):
          await _applyEditedContent(chatId, messageId, newContent);

        case td.UpdateDeleteMessages(
          :final chatId,
          :final messageIds,
          :final isPermanent,
          :final fromCache,
        ):
          // `fromCache` means TDLib is only evicting its own copy — the post
          // still exists, so dropping it here would blank rows that are fine.
          if (isPermanent && !fromCache) {
            await (_db.delete(_db.messages)..where(
                  (m) => m.chatId.equals(chatId) & m.messageId.isIn(messageIds),
                ))
                .go();
          }

        case td.UpdateMessageInteractionInfo(
          :final chatId,
          :final messageId,
          :final interactionInfo,
        ):
          await (_db.update(_db.messages)..where(
                (m) => m.chatId.equals(chatId) & m.messageId.equals(messageId),
              ))
              .write(
                MessagesCompanion(
                  viewCount: Value(interactionInfo?.viewCount ?? 0),
                  forwardCount: Value(interactionInfo?.forwardCount ?? 0),
                  reactionCount: Value(
                    interactionInfo?.reactions?.reactions.fold<int>(
                          0,
                          (sum, r) => sum + r.totalCount,
                        ) ??
                        0,
                  ),
                  replyCount: Value(
                    interactionInfo?.replyInfo?.replyCount ?? 0,
                  ),
                  // This is the authoritative answer on our own reaction, and it is
                  // what reconciles the optimistic write in [toggleReaction] —
                  // including a reaction added from another device.
                  chosenReaction: Value(chosenReactionOf(interactionInfo)),
                ),
              );
          // The counters that just changed *are* the ranking inputs, so the score
          // has to follow them. Uses the cached prior rather than re-aggregating —
          // these updates arrive constantly while scrolling.
          await forYou?.rescoreMessage(chatId, messageId);

        default:
          break;
      }
    });
  }

  /// Rebuilds text, spans and media for an edited post, leaving the counters and
  /// the original date alone.
  ///
  /// Goes through the same [contentFieldsOf] the insert path uses, so an edited
  /// post cannot end up rendering differently from a fresh one.
  Future<void> _applyEditedContent(
    int chatId,
    int messageId,
    td.MessageContent content,
  ) async {
    final fields = contentFieldsOf(content);

    await (_db.update(_db.messages)..where(
          (m) => m.chatId.equals(chatId) & m.messageId.equals(messageId),
        ))
        .write(
          MessagesCompanion(
            body: Value(fields.text),
            entitiesJson: Value(fields.entitiesJson),
            spansJson: Value(fields.spansJson),
            mediaJson: Value(fields.mediaJson),
            contentKind: Value(fields.kind),
          ),
        );
  }

  Future<void> stopLiveUpdates() async {
    await _updates?.cancel();
    _updates = null;
    for (final chatId in _openChats.toList()) {
      await _closeChat(chatId);
    }
  }

  // ---------------------------------------------------------------------------
  // Feed queries — all the ordering and paging happens in SQL
  // ---------------------------------------------------------------------------

  /// Watches the newest [limit] posts. Live: drift re-runs it whenever the table
  /// changes, so posts arriving over `updateNewMessage` appear without polling.
  ///
  /// Pass [chatId] to scope the feed to a single channel — same query, same
  /// index, same pagination.
  Stream<List<FeedEntry>> watchFeedHead({
    int limit = 30,
    int? chatId,
    ChannelList list = ChannelList.following,
  }) {
    return _feedQuery(
      limit: limit,
      chatId: chatId,
      list: list,
    ).watch().map(_mapRows);
  }

  /// Next page, older than [after]. Keyset pagination — `OFFSET` would rescan
  /// from the top on every page and drift as new posts arrive.
  Future<List<FeedEntry>> feedPage({
    required FeedCursor after,
    int limit = 30,
    int? chatId,
    ChannelList list = ChannelList.following,
  }) async {
    final rows = await _feedQuery(
      limit: limit,
      after: after,
      chatId: chatId,
      list: list,
    ).get();
    return _mapRows(rows);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _feedQuery({
    required int limit,
    FeedCursor? after,
    int? chatId,
    ChannelList list = ChannelList.following,
  }) {
    final query = _db.select(_db.messages).join([
      innerJoin(_db.channels, _db.channels.id.equalsExp(_db.messages.chatId)),
      // Membership is what makes a post part of this feed. An orphaned channel's
      // posts stay cached but stop appearing, with no delete required.
      //
      // Skipped when scoped to a single channel: the channel profile screen
      // addresses a channel directly and should still work for an orphan.
      if (chatId == null)
        innerJoin(
          _db.channelLists,
          _db.channelLists.chatId.equalsExp(_db.messages.chatId) &
              _db.channelLists.listName.equalsValue(list),
        ),
    ]);

    if (chatId != null) {
      query.where(_db.messages.chatId.equals(chatId));
    }

    // Content filtering happens here, in SQL, never at insert time — the rules
    // are expected to change and re-backfilling to revise one would be absurd.
    // Applies to channel profiles too, so a channel looks the same wherever you
    // read it.
    query.where(
      _db.messages.contentKind.isNotIn([
        for (final kind in hiddenContentKinds) kind.name,
      ]),
    );
    // Posts pushed through an inline bot: auto-posters, RSS bridges, ads.
    query.where(_db.messages.viaBot.equals(false));

    if (after != null) {
      // Strict tuple comparison on (date, message_id): date alone is not unique,
      // and ties would either repeat or skip rows across page boundaries.
      query.where(
        _db.messages.date.isSmallerThanValue(after.date) |
            (_db.messages.date.equals(after.date) &
                _db.messages.messageId.isSmallerThanValue(after.messageId)),
      );
    }

    query
      ..orderBy([
        OrderingTerm.desc(_db.messages.date),
        OrderingTerm.desc(_db.messages.messageId),
      ])
      ..limit(limit);

    return query;
  }

  List<FeedEntry> _mapRows(List<TypedResult> rows) => [
    for (final row in rows)
      FeedEntry(
        message: row.readTable(_db.messages),
        channel: row.readTable(_db.channels),
      ),
  ];

  // ---------------------------------------------------------------------------
  // Reactions and threads
  // ---------------------------------------------------------------------------

  /// Default "like". Telegram has no like — a heart reaction is the closest
  /// equivalent, and it is what the official clients use for the quick tap.
  static const likeEmoji = '❤';

  /// Toggles a reaction on a post.
  ///
  /// The local row is updated optimistically so the tap feels instant, then
  /// TDLib's `updateMessageInteractionInfo` corrects the authoritative counts.
  /// If the request fails the optimistic write is rolled back — a like that
  /// silently didn't happen is worse than one that visibly failed.
  Future<void> toggleReaction(
    int chatId,
    int messageId, {
    String emoji = likeEmoji,
  }) async {
    final row =
        await (_db.select(_db.messages)..where(
              (m) => m.chatId.equals(chatId) & m.messageId.equals(messageId),
            ))
            .getSingleOrNull();
    if (row == null) return;

    final wasChosen = row.chosenReaction == emoji;

    await _writeReaction(
      chatId,
      messageId,
      chosen: wasChosen ? null : emoji,
      countDelta: wasChosen ? -1 : 1,
    );

    try {
      if (wasChosen) {
        await _client.send<td.Ok>(
          td.RemoveMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: td.ReactionTypeEmoji(emoji: emoji),
          ),
        );
      } else {
        await _client.send<td.Ok>(
          td.AddMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: td.ReactionTypeEmoji(emoji: emoji),
            isBig: false,
            updateRecentReactions: true,
          ),
        );
      }
    } on TdException {
      await _writeReaction(
        chatId,
        messageId,
        chosen: row.chosenReaction,
        countDelta: wasChosen ? 1 : -1,
      );
      rethrow;
    }
  }

  Future<void> _writeReaction(
    int chatId,
    int messageId, {
    required String? chosen,
    required int countDelta,
  }) async {
    await _db.customUpdate(
      'UPDATE messages SET chosen_reaction = ?1, '
      'reaction_count = MAX(reaction_count + ?2, 0) '
      'WHERE chat_id = ?3 AND message_id = ?4',
      variables: [
        chosen == null
            ? const Variable<String>(null)
            : Variable.withString(chosen),
        Variable.withInt(countDelta),
        Variable.withInt(chatId),
        Variable.withInt(messageId),
      ],
      updates: {_db.messages},
    );
  }

  /// Comments on a post, from the linked discussion group.
  ///
  /// This is the closest thing Telegram has to replies on a channel post.
  /// `getMessageThreadHistory` takes the **post's own** message id, not a
  /// separate thread id.
  Future<List<ThreadComment>> threadComments(
    int chatId,
    int messageId, {
    int limit = 50,
  }) async {
    final messages = await _client.send<td.Messages>(
      td.GetMessageThreadHistory(
        chatId: chatId,
        messageId: messageId,
        fromMessageId: 0,
        offset: 0,
        limit: limit,
      ),
    );

    return [
      for (final message in messages.messages.reversed)
        ThreadComment(
          messageId: message.id,
          date: message.date,
          fields: contentFieldsOf(message.content),
        ),
    ];
  }

  /// Video and GIF posts only, newest first — the Shorts feed.
  ///
  /// Deliberately not scoped to a membership list. Shorts is a browsing surface
  /// rather than a subscription: restricting it to Following would leave it empty
  /// for anyone whose video channels sit in For You, and the two feeds already
  /// cover the "only what I chose" case.
  ///
  /// Ordered by date rather than by score. A ranked short-video feed sounds
  /// appealing until you notice the ranking is tuned on views-per-reaction for
  /// *text* posts, which says nothing useful about a clip.
  Future<List<FeedEntry>> videoPosts({int limit = 60, int? beforeDate}) async {
    final query = _db.select(_db.messages).join([
      innerJoin(_db.channels, _db.channels.id.equalsExp(_db.messages.chatId)),
    ])
      ..where(
        _db.messages.contentKind.isIn([
          ContentKind.video.name,
          ContentKind.animation.name,
        ]),
      )
      // A clip with no file cached and no thumbnail would be a black screen you
      // cannot swipe past fast enough.
      ..where(_db.messages.mediaJson.isNotNull())
      ..where(_db.messages.viaBot.equals(false))
      ..orderBy([OrderingTerm.desc(_db.messages.date)])
      ..limit(limit);

    if (beforeDate != null) {
      query.where(_db.messages.date.isSmallerThanValue(beforeDate));
    }

    return _mapRows(await query.get());
  }

  /// Posts a comment on a channel post.
  ///
  /// Two calls, and the first is not optional. A channel post has no comments of
  /// its own — the comments live in a *linked discussion group*, a different chat
  /// entirely. `getMessageThread` is what maps a post to that chat and to the
  /// thread inside it; sending to the channel's own id would either fail or, on a
  /// channel you can post to, publish a new post instead of a reply.
  Future<void> sendComment(int chatId, int messageId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final thread = await _client.send<td.MessageThreadInfo>(
      td.GetMessageThread(chatId: chatId, messageId: messageId),
    );

    await _client.send<td.Message>(
      td.SendMessage(
        chatId: thread.chatId,
        messageThreadId: thread.messageThreadId,
        inputMessageContent: td.InputMessageText(
          // Entities left empty: this is a plain composer, and anything the user
          // typed that looks like markup should stay literal rather than being
          // silently reinterpreted.
          text: td.FormattedText(text: trimmed, entities: const []),
          clearDraft: true,
        ),
      ),
    );
  }

  Future<int> countMessages() async {
    final count = _db.messages.messageId.count();
    final row = await (_db.selectOnly(
      _db.messages,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _persist(Iterable<td.Message> messages) async {
    // Channel posts only; service messages and anything from a chat we do not
    // track would violate the messages -> channels foreign key.
    final rows = [for (final m in messages) messageToRow(m)];
    if (rows.isEmpty) return;

    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.messages, rows);
    });
  }

  Future<bool> _isTracked(int chatId) async {
    final row = await (_db.select(
      _db.channels,
    )..where((c) => c.id.equals(chatId))).getSingleOrNull();
    return row != null;
  }

  /// Moves [Channels.lastSyncedMessageId] forward only. Message IDs in a chat
  /// increase monotonically, so this is a high-water mark.
  Future<void> _advanceCursor(int chatId, int messageId) async {
    await (_db.update(_db.channels)..where(
          (c) =>
              c.id.equals(chatId) &
              (c.lastSyncedMessageId.isSmallerThanValue(messageId) |
                  c.lastSyncedMessageId.isNull()),
        ))
        .write(ChannelsCompanion(lastSyncedMessageId: Value(messageId)));
  }

  Future<void> _openChat(int chatId) async {
    if (_openChats.contains(chatId)) return;

    // Close the oldest if we are at the cap rather than growing without bound.
    if (_openChats.length >= _maxOpenChats) {
      await _closeChat(_openChats.first);
    }

    await _client.send<td.Ok>(td.OpenChat(chatId: chatId));
    _openChats.add(chatId);
  }

  Future<void> _closeChat(int chatId) async {
    if (!_openChats.remove(chatId)) return;
    try {
      await _client.send<td.Ok>(td.CloseChat(chatId: chatId));
    } on TdException {
      // Already closed server-side; nothing to undo.
    }
  }
}

/// One comment from a post's linked discussion thread.
class ThreadComment {
  const ThreadComment({
    required this.messageId,
    required this.date,
    required this.fields,
  });

  final int messageId;
  final int date;

  /// Reuses the same content mapping as the feed, so comments get precomputed
  /// spans and render through exactly the same widget.
  final MessageContentFields fields;
}
