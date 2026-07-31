import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// How a channel came to be known — **provenance only**.
///
/// * [subscribed] — the account follows it on Telegram; found via `loadChats`.
/// * [curated] — added by hand, by username, with `searchPublicChat`. Not joined.
///
/// This no longer decides which feed a channel appears in; [ChannelLists] does.
/// It is kept because it is real information that cannot be recovered without a
/// full re-sync, and it is worth showing ("you follow this on Telegram" reads
/// differently from "you added this"). Nothing branches on it.
enum ChannelSource { subscribed, curated }

/// Which feed a channel feeds.
///
/// A channel may be in both, neither, or one. Membership is the *only* thing that
/// decides what a feed shows.
enum ChannelList { following, forYou }

/// Stores [ChannelList] as the snake_case names the schema specifies
/// (`following` / `for_you`) rather than drift's default of the Dart identifier,
/// which would write `forYou`.
class ChannelListConverter extends TypeConverter<ChannelList, String>
    with JsonTypeConverter<ChannelList, String> {
  const ChannelListConverter();

  static const _names = {
    ChannelList.following: 'following',
    ChannelList.forYou: 'for_you',
  };

  @override
  ChannelList fromSql(String fromDb) {
    for (final entry in _names.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError.value(fromDb, 'fromDb', 'Unknown channel list');
  }

  @override
  String toSql(ChannelList value) => _names[value]!;
}

/// Which lists a channel belongs to.
///
/// A join table rather than a column because the two lists are independent: a
/// channel can be in Following, For You, both, or neither, and a single enum
/// cannot say that.
///
/// A channel in **neither** list is an orphan. Orphans are deliberately kept as a
/// cache: re-adding a channel is then instant and costs no backfill, and its
/// posts stay available to any future screen that addresses a channel directly.
/// They are invisible to both feeds regardless, since feeds join through this
/// table. `ChannelRepository.purgeOrphanedChannels` exists for when you actually
/// want the space back — nothing deletes them automatically.
/// The generated row class is named explicitly: drift would otherwise
/// singularise `ChannelLists` into `ChannelList` and collide with the enum above.
/// The SQL table is still `channel_lists`.
@DataClassName('ChannelMembership')
@TableIndex(name: 'channel_lists_name', columns: {#listName})
class ChannelLists extends Table {
  IntColumn get chatId => integer().references(Channels, #id)();

  TextColumn get listName =>
      text().map(const ChannelListConverter())();

  /// When it joined this list. Lets a future "recently added" view exist, and
  /// makes a migrated row distinguishable from a deliberate one by timestamp.
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {chatId, listName};
}

@TableIndex(name: 'channels_source', columns: {#source})
class Channels extends Table {
  /// TDLib chat ID. Channels get large negative IDs (-100…), which is why this
  /// is a 64-bit integer and not an unsigned anything.
  IntColumn get id => integer()();

  /// Public @username, absent for private channels reached via invite.
  TextColumn get username => text().nullable().unique()();

  TextColumn get title => text().withDefault(const Constant(''))();

  IntColumn get subscriberCount => integer().withDefault(const Constant(0))();

  /// Backfill cursor for Phase 4 — the newest message already persisted.
  /// Deliberately preserved across re-syncs; see `ChannelRepository`.
  IntColumn get lastSyncedMessageId => integer().nullable()();

  TextColumn get source => textEnum<ChannelSource>()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One channel post.
///
/// Indexes are the whole point of this table: the Following feed is a single
/// `ORDER BY date DESC` scan across every tracked channel, so it must never
/// sort at query time.
@TableIndex(name: 'messages_date', columns: {#date, #messageId})
@TableIndex(name: 'messages_grouped', columns: {#chatId, #groupedId})
class Messages extends Table {
  IntColumn get chatId => integer().references(Channels, #id)();
  IntColumn get messageId => integer()();

  /// Unix seconds. The feed's sort key.
  IntColumn get date => integer()();

  /// TDLib's `media_album_id`, null when the post is not part of an album.
  /// Phase 6 groups consecutive posts sharing one of these into a carousel.
  IntColumn get groupedId => integer().nullable()();

  /// Plain text with no markup, for previews and future search.
  ///
  /// The Dart getter is `body` but the SQL column stays `text`: a getter named
  /// `text` would shadow drift's own `text()` column builder inside this class,
  /// and drift then fails to resolve the table at all.
  TextColumn get body => text().named('text').withDefault(const Constant(''))();

  /// Raw TDLib entities, kept so spans can be rebuilt if the renderer changes.
  TextColumn get entitiesJson => text().nullable()();

  /// **Precomputed** render segments — flattened, non-overlapping, ready to map
  /// straight onto `TextSpan`s. Built once at insert time precisely so that
  /// nothing parses entities during scroll.
  TextColumn get spansJson => text().nullable()();

  /// Media descriptor including the inline `minithumbnail`. Full-size files are
  /// only ever downloaded on tap, which keeps backfill cheap on mobile data.
  TextColumn get mediaJson => text().nullable()();

  IntColumn get viewCount => integer().withDefault(const Constant(0))();
  IntColumn get reactionCount => integer().withDefault(const Constant(0))();
  IntColumn get forwardCount => integer().withDefault(const Constant(0))();

  /// Set when this post is a forward from another channel. The Phase 7 forward
  /// graph is built entirely from this column.
  IntColumn get forwardedFromChatId => integer().nullable()();

  /// Non-null once TDLib reports the post was edited.
  IntColumn get editDate => integer().nullable()();

  /// Linked-discussion thread, when the channel has comments enabled.
  ///
  /// Comes from `Message.messageThreadId`, **not** from
  /// `interaction_info.reply_info` — TDLib 1.8.36 has no `message_thread_id` on
  /// `MessageReplyInfo`.
  IntColumn get threadId => integer().nullable()();

  /// Comment count, from `interaction_info.reply_info.reply_count`.
  IntColumn get replyCount => integer().withDefault(const Constant(0))();

  /// The emoji this account reacted with, if any. Drives the like toggle.
  TextColumn get chosenReaction => text().nullable()();

  @override
  Set<Column> get primaryKey => {chatId, messageId};
}

@DriftDatabase(tables: [Channels, Messages, ChannelLists])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(messages);

          // v3 exists only to repair v2. `createTable` creates the table but
          // *not* its `@TableIndex` entities, so databases upgraded to v2 ended
          // up with no index on `date` — every feed query then sorted the whole
          // messages table in a temp B-tree. Fresh installs were fine, which is
          // exactly why this needed catching on a real device.
          //
          // Every branch below therefore creates its indexes explicitly.
          if (from < 3) {
            await m.create(messagesDate);
            await m.create(messagesGrouped);
          }

          if (from < 4) {
            await m.addColumn(messages, messages.threadId);
            await m.addColumn(messages, messages.replyCount);
            await m.addColumn(messages, messages.chosenReaction);
            // v4 created a `vouches` table. v5 drops it again; on a v3-or-older
            // database there is nothing to create in the first place.
          }

          // v5 removes the forward graph.
          if (from < 5) {
            // Rewrite before anything reads the column. `source` is stored as the
            // enum *name*, so a leftover 'suggested' row would throw on the first
            // select once the value no longer exists in the enum.
            //
            // Converted rather than deleted: these channels' posts are already in
            // the Following feed, which does not filter on source, so deleting
            // them would silently empty part of a working feed. They become
            // ordinary hand-tracked channels and can be removed from the Channels
            // screen if unwanted.
            await m.database.customStatement(
              "UPDATE channels SET source = 'curated' WHERE source = 'suggested'",
            );
            await m.database
                .customStatement('DROP INDEX IF EXISTS vouches_target');
            await m.database.customStatement('DROP TABLE IF EXISTS vouches');
          }

          // v6 moves feed membership out of `channels.source` and into its own
          // table.
          if (from < 6) {
            await m.createTable(channelLists);
            await m.create(channelListsName);

            // Everything already tracked becomes a Following member, so the feed
            // that was working before this migration still shows exactly the same
            // posts afterwards. Nothing is placed in `for_you` — that list starts
            // empty and is filled by hand, which is the whole point of the rework.
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await m.database.customStatement(
              'INSERT OR IGNORE INTO channel_lists (chat_id, list_name, added_at) '
              "SELECT id, 'following', ?1 FROM channels",
              [now],
            );
          }
        },
      );

  /// Opens the feed database next to TDLib's own storage, inside app-private
  /// storage. Kept separate from TDLib's database on purpose: a dev reset wipes
  /// TDLib's directory, and the feed cache should be independently disposable.
  static Future<AppDatabase> open() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'feed'));
    await dir.create(recursive: true);
    return AppDatabase(NativeDatabase(File(p.join(dir.path, 'feed.sqlite'))));
  }
}
