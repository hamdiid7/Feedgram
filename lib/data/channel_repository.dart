import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../telegram/td_exception.dart';
import '../telegram/telegram_client.dart';
import 'app_database.dart';
import '../config/seed_channels.dart';
import 'channel_username.dart';

/// A channel plus which lists it belongs to.
///
/// The Channels screen needs both together; the feeds only ever need one list at
/// a time and query it directly.
class TrackedChannel {
  const TrackedChannel({required this.channel, required this.lists});

  final Channel channel;
  final Set<ChannelList> lists;

  bool get isOrphan => lists.isEmpty;
  bool inList(ChannelList list) => lists.contains(list);
}

/// Outcome of trying to add one channel by username. Per-username rather than
/// per-batch so one dead handle never kills a whole sync pass.
sealed class AddChannelResult {
  const AddChannelResult(this.input);
  final String input;
}

final class ChannelAdded extends AddChannelResult {
  const ChannelAdded(super.input, this.channel);
  final Channel channel;
}

final class ChannelAddFailed extends AddChannelResult {
  const ChannelAddFailed(super.input, this.reason);
  final String reason;
}

/// Maps TDLib chats onto the local `channels` table.
///
/// Everything above this class deals in [Channel] rows; TDLib objects stop here.
class ChannelRepository {
  ChannelRepository({required TelegramClient client, required AppDatabase db})
      : _client = client,
        _db = db;

  final TelegramClient _client;
  final AppDatabase _db;

  /// Every known channel, orphans included, each with its list memberships.
  ///
  /// Orphans are shown on purpose: they are cached, not deleted, so the Channels
  /// screen has to be the place you can see and re-add them. The feeds never see
  /// them because they join through `channel_lists`.
  Stream<List<TrackedChannel>> watchChannels() {
    final query = _db.select(_db.channels).join([
      leftOuterJoin(
        _db.channelLists,
        _db.channelLists.chatId.equalsExp(_db.channels.id),
      ),
    ])
      ..orderBy([
        OrderingTerm.desc(_db.channels.subscriberCount),
        OrderingTerm(expression: _db.channels.title),
      ]);

    // One row per (channel, list) pair, folded back into one entry per channel.
    return query.watch().map((rows) {
      final byId = <int, TrackedChannel>{};
      for (final row in rows) {
        final channel = row.readTable(_db.channels);
        final membership = row.readTableOrNull(_db.channelLists);
        final existing = byId[channel.id];
        final lists = existing?.lists ?? <ChannelList>{};
        if (membership != null) lists.add(membership.listName);
        byId[channel.id] = TrackedChannel(channel: channel, lists: lists);
      }
      return byId.values.toList();
    });
  }

  /// Channels in one list, for backfill and feed scoping.
  Future<List<Channel>> channelsIn(ChannelList list) async {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.channelLists,
        _db.channelLists.chatId.equalsExp(_db.channels.id) &
            _db.channelLists.listName.equalsValue(list),
      ),
    ]);
    final rows = await query.get();
    return [for (final row in rows) row.readTable(_db.channels)];
  }

  Future<List<int>> channelIdsIn(ChannelList list) async {
    final channels = await channelsIn(list);
    return [for (final channel in channels) channel.id];
  }

  Future<Set<ChannelList>> listsFor(int chatId) async {
    final rows = await (_db.select(_db.channelLists)
          ..where((l) => l.chatId.equals(chatId)))
        .get();
    return {for (final row in rows) row.listName};
  }

  /// Idempotent — adding a channel to a list it is already in keeps the original
  /// `added_at` rather than resetting it.
  Future<void> addToList(int chatId, ChannelList list) async {
    await _db.into(_db.channelLists).insert(
          ChannelListsCompanion.insert(
            chatId: chatId,
            listName: list,
            addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Removes anything that is not a real broadcast channel from both lists.
  ///
  /// The spec asks for this in the migration, but a migration cannot ask TDLib
  /// what a chat *is* — the local schema never recorded chat type. So it runs as a
  /// verification pass instead, over the ids already tracked.
  ///
  /// Groups, private chats and bot conversations behave nothing like channels
  /// (no view counts, different history semantics), so a leaked one produces a
  /// feed of noise. Membership is dropped; the cached rows stay, per the
  /// orphans-as-cache decision.
  Future<List<int>> purgeNonChannels() async {
    final rows = await _db.customSelect(
      'SELECT DISTINCT chat_id FROM channel_lists',
      readsFrom: {_db.channelLists},
    ).get();

    final removed = <int>[];
    for (final row in rows) {
      final chatId = row.read<int>('chat_id');
      try {
        final chat = await _client.send<td.Chat>(td.GetChat(chatId: chatId));
        if (_isChannel(chat)) continue;
      } on TdException {
        // Unreadable tells us nothing about its type — leave it alone rather than
        // dropping a channel that is merely temporarily inaccessible.
        continue;
      }

      await (_db.delete(_db.channelLists)
            ..where((l) => l.chatId.equals(chatId)))
          .go();
      removed.add(chatId);
    }
    return removed;
  }

  Future<void> removeFromList(int chatId, ChannelList list) async {
    await (_db.delete(_db.channelLists)
          ..where((l) => l.chatId.equals(chatId) & l.listName.equalsValue(list)))
        .go();
  }

  /// Channels in no list at all. Their posts stay cached and invisible.
  Future<List<Channel>> orphanedChannels() async {
    final rows = await _db.customSelect(
      'SELECT c.* FROM channels c '
      'WHERE NOT EXISTS (SELECT 1 FROM channel_lists l WHERE l.chat_id = c.id)',
      readsFrom: {_db.channels, _db.channelLists},
    ).get();
    return [for (final row in rows) _db.channels.map(row.data)];
  }

  /// Deletes orphans and their cached posts. Never called automatically — see the
  /// note on [ChannelLists].
  Future<int> purgeOrphanedChannels() async {
    final orphans = await orphanedChannels();
    if (orphans.isEmpty) return 0;

    final ids = [for (final channel in orphans) channel.id];
    await _db.batch((batch) {
      // Messages first: `messages.chat_id` references `channels.id`.
      batch.deleteWhere(_db.messages, (m) => m.chatId.isIn(ids));
      batch.deleteWhere(_db.channels, (c) => c.id.isIn(ids));
    });
    return orphans.length;
  }

  Future<int> countChannels() async {
    final count = _db.channels.id.count();
    final row = await (_db.selectOnly(_db.channels)..addColumns([count]))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Pulls every channel the account follows.
  ///
  /// Three things about `loadChats` that are easy to get wrong:
  ///
  /// 1. **Chats do not come back as a return value.** `loadChats` answers `Ok`
  ///    and the actual chats arrive separately as `updateNewChat`.
  /// 2. **Error 404 is the success condition**, meaning "no more chats". Any
  ///    other error is real.
  /// 3. **`updateNewChat` is not a list of what exists**, it is a notification
  ///    of what is new, delivered once per chat per session. Listening for it is
  ///    necessary but not sufficient; `getChats` below is what makes the result
  ///    the whole account rather than only the part TDLib had not seen yet.
  Future<int> syncSubscribedChannels() async {
    final discovered = <int, td.Chat>{};

    final subscription = _client.updates.listen((update) {
      if (update is td.UpdateNewChat) {
        discovered[update.chat.id] = update.chat;
      }
    });

    try {
      // Archive as well as Main. A muted channel that was swiped away is still
      // followed, and it does not appear in ChatListMain at all — walking only
      // Main quietly returns fewer channels than the account actually has, with
      // nothing to indicate any were skipped.
      for (final list in const [td.ChatListMain(), td.ChatListArchive()]) {
        while (true) {
          try {
            await _client.send<td.Ok>(td.LoadChats(chatList: list, limit: 100));
          } on TdException catch (e) {
            if (e.code == 404) break;

            final flood = e.floodWait;
            if (flood != null) {
              // Sleep the full duration TDLib asked for, then resume where we
              // left off. Shortening this is what gets accounts flagged.
              await Future<void>.delayed(flood);
              continue;
            }
            rethrow;
          }
        }
      }

      // `loadChats` returns before its updates have all been delivered, so give
      // the port a moment to drain rather than cancelling mid-flight.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } finally {
      await subscription.cancel();
    }

    // Ask for the ids outright, rather than trusting the update stream alone.
    //
    // `updateNewChat` fires once per chat per TDLib session. Any chat already
    // loaded earlier in this run — by the Messages tab, which walks the same
    // list, or by an earlier sync in the same process — is never announced
    // again, so listening only sees whatever happens to be new. On a warm
    // session that is a fraction of the account: this found 38 of 88 channels.
    //
    // `getChats` answers from what TDLib has loaded, which the pagination above
    // has just made sure is everything.
    final ids = <int>{...discovered.keys};
    for (final list in const [td.ChatListMain(), td.ChatListArchive()]) {
      try {
        final chats = await _client.send<td.Chats>(
          td.GetChats(chatList: list, limit: 1000),
        );
        ids.addAll(chats.chatIds);
      } on TdException {
        // One unreadable list must not discard the other.
      }
    }

    final chats = <td.Chat>[];
    for (final id in ids) {
      final known = discovered[id];
      if (known != null) {
        chats.add(known);
        continue;
      }
      try {
        // Local cache, so this is cheap despite being one call per chat.
        chats.add(await _client.send<td.Chat>(td.GetChat(chatId: id)));
      } on TdException {
        continue;
      }
    }

    final channels = chats.where(_isChannel).toList();
    debugPrint(
      'sync: ${ids.length} chats known, ${chats.length} readable, '
      '${channels.length} channels',
    );


    // Sequential on purpose. getSupergroup is served from TDLib's local cache,
    // but keeping the whole sync single-file is the habit that matters once
    // Phase 4 starts pulling history.
    var saved = 0;
    var failed = 0;
    for (final chat in channels) {
      final type = chat.type as td.ChatTypeSupergroup;
      try {
        final supergroup = await _client.send<td.Supergroup>(
          td.GetSupergroup(supergroupId: type.supergroupId),
        );
        await _upsert(
          id: chat.id,
          title: chat.title,
          username: _primaryUsername(supergroup),
          subscriberCount: supergroup.memberCount,
          source: ChannelSource.subscribed,
        );
        // Subscriptions land in Following only, never For You.
        await addToList(chat.id, ChannelList.following);
        saved++;
      } catch (e) {
        // Anything, not just TdException. `channels.username` is UNIQUE, so a
        // handle that has moved to a different chat id throws a *database*
        // error here — and catching only TdException let that abort the entire
        // pass at whichever channel happened to collide, silently capping how
        // many were ever saved.
        failed++;
        // Id only. Titles are the user's data and this goes to the device log.
        debugPrint('sync: skipped channel ${chat.id}: $e');
        continue;
      }
    }
    debugPrint('sync: saved $saved, skipped $failed');

    // Verify what is already tracked while TDLib is warm. Cheap (getChat is
    // served from local cache) and it is the only place that can tell a group
    // from a channel.
    final purged = await purgeNonChannels();
    debugPrint(
      'sync: purge dropped ${purged.length}, '
      'db holds ${await countChannels()} channels',
    );

    return saved;
  }

  /// Registers a public channel by username **without joining it**.
  ///
  /// `searchPublicChat` resolves the handle and makes TDLib aware of the chat;
  /// it does not subscribe the account, which is what lets the feed track
  /// channels the user does not follow.
  Future<AddChannelResult> addCuratedChannel(
    String input, {
    ChannelSource source = ChannelSource.curated,
    Set<ChannelList> lists = const {ChannelList.following},
  }) async {
    final username = normalizeChannelUsername(input);
    if (username == null) {
      return ChannelAddFailed(input, 'Not a valid public channel username.');
    }

    try {
      final chat =
          await _client.send<td.Chat>(td.SearchPublicChat(username: username));

      if (!_isChannel(chat)) {
        return ChannelAddFailed(
          input,
          'That is a user or group, not a channel.',
        );
      }

      final type = chat.type as td.ChatTypeSupergroup;
      final supergroup = await _client.send<td.Supergroup>(
        td.GetSupergroup(supergroupId: type.supergroupId),
      );

      await _upsert(
        id: chat.id,
        title: chat.title,
        username: _primaryUsername(supergroup) ?? username,
        subscriberCount: supergroup.memberCount,
        source: source,
      );

      for (final list in lists) {
        await addToList(chat.id, list);
      }

      final saved = await (_db.select(_db.channels)
            ..where((c) => c.id.equals(chat.id)))
          .getSingle();
      return ChannelAdded(input, saved);
    } on TdException catch (e) {
      return ChannelAddFailed(input, _explain(e));
    }
  }

  /// Adds several usernames, one at a time, collecting per-username outcomes.
  Future<List<AddChannelResult>> addCuratedChannels(
    Iterable<String> usernames, {
    ChannelSource source = ChannelSource.curated,
    Set<ChannelList> lists = const {ChannelList.following},
    void Function(int done, int total)? onProgress,
  }) async {
    final all = usernames.toList();
    final results = <AddChannelResult>[];
    for (var i = 0; i < all.length; i++) {
      results.add(
        await addCuratedChannel(all[i], source: source, lists: lists),
      );
      onProgress?.call(i + 1, all.length);
    }
    return results;
  }

  /// Registers everything in [seedChannels].
  ///
  /// Sequential and per-entry guarded: one dead or renamed handle must never kill
  /// the pass, which is the whole reason [AddChannelResult] is a result type
  /// rather than an exception.
  Future<List<AddChannelResult>> addSeedChannels({
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <AddChannelResult>[];
    for (var i = 0; i < seedChannels.length; i++) {
      final seed = seedChannels[i];
      results.add(await addCuratedChannel(
        seed.username,
        source: seed.source,
        lists: seed.lists,
      ));
      onProgress?.call(i + 1, seedChannels.length);
    }
    return results;
  }


  Future<void> removeChannel(int id) async {
    await (_db.delete(_db.channels)..where((c) => c.id.equals(id))).go();
  }

  /// Writes what we just learned without touching [Channels.lastSyncedMessageId]
  /// — that cursor belongs to the backfill in Phase 4 and a re-sync must not
  /// reset it.
  ///
  /// [ChannelSource.subscribed] also never gets downgraded: a channel the
  /// account actually follows stays marked that way even if it is later added by
  /// username again.
  Future<void> _upsert({
    required int id,
    required String title,
    required String? username,
    required int subscriberCount,
    required ChannelSource source,
  }) async {
    final existing = await (_db.select(_db.channels)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();

    final effectiveSource =
        existing?.source == ChannelSource.subscribed ? ChannelSource.subscribed : source;

    await _db.into(_db.channels).insert(
          ChannelsCompanion.insert(
            id: Value(id),
            title: Value(title),
            username: Value(username),
            subscriberCount: Value(subscriberCount),
            source: effectiveSource,
          ),
          onConflict: DoUpdate(
            (_) => ChannelsCompanion(
              title: Value(title),
              username: Value(username),
              subscriberCount: Value(subscriberCount),
              source: Value(effectiveSource),
            ),
          ),
        );
  }
}

bool _isChannel(td.Chat chat) {
  final type = chat.type;
  return type is td.ChatTypeSupergroup && type.isChannel;
}

/// Channels can hold several usernames; the editable one is the canonical
/// handle, with the first active one as fallback.
String? _primaryUsername(td.Supergroup supergroup) {
  final usernames = supergroup.usernames;
  if (usernames == null) return null;
  if (usernames.editableUsername.isNotEmpty) return usernames.editableUsername;
  if (usernames.activeUsernames.isNotEmpty) return usernames.activeUsernames.first;
  return null;
}

String _explain(TdException e) {
  final flood = e.floodWait;
  if (flood != null) {
    return 'Rate limited — retry in ${flood.inSeconds}s.';
  }
  return switch (e.message) {
    'USERNAME_NOT_OCCUPIED' => 'No channel with that username.',
    'USERNAME_INVALID' => 'That username is not valid.',
    'CHANNEL_PRIVATE' =>
      'That channel is private — it needs a real invite, same as in Telegram.',
    _ => '${e.message} (${e.code})',
  };
}
