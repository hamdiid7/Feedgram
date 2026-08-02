import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:feedgram/data/app_database.dart';

/// Exercises the v4 → v7 upgrade: v5 removes the forward graph, v6 moves feed
/// membership into `channel_lists`, v7 adds content classification, v8 adds the
/// stored For You score, v9 the seen-post memory. A real device jumps straight
/// from 4 to 9, so that is the path tested.
///
/// The DDL below is copied verbatim from a real v4 database pulled off a device,
/// not hand-idealised, so this tests the migration against what actually shipped.
///
/// The dangerous part is `channels.source`: drift stores a text enum by its Dart
/// *name*, so a row still reading `'suggested'` after that value is gone from the
/// enum throws on the very first select. A migration that drops the table but
/// forgets the rewrite would leave the app unable to read its own channel list.
const _v4Ddl = '''
CREATE TABLE "channels" ("id" INTEGER NOT NULL, "username" TEXT NULL UNIQUE,
  "title" TEXT NOT NULL DEFAULT '', "subscriber_count" INTEGER NOT NULL DEFAULT 0,
  "last_synced_message_id" INTEGER NULL, "source" TEXT NOT NULL,
  PRIMARY KEY ("id"));
CREATE INDEX channels_source ON channels (source);
CREATE TABLE "messages" ("chat_id" INTEGER NOT NULL REFERENCES channels (id),
  "message_id" INTEGER NOT NULL, "date" INTEGER NOT NULL, "grouped_id" INTEGER NULL,
  "text" TEXT NOT NULL DEFAULT '', "entities_json" TEXT NULL, "spans_json" TEXT NULL,
  "media_json" TEXT NULL, "view_count" INTEGER NOT NULL DEFAULT 0,
  "reaction_count" INTEGER NOT NULL DEFAULT 0, "forward_count" INTEGER NOT NULL DEFAULT 0,
  "forwarded_from_chat_id" INTEGER NULL, "edit_date" INTEGER NULL,
  "thread_id" INTEGER NULL, "reply_count" INTEGER NOT NULL DEFAULT 0,
  "chosen_reaction" TEXT NULL, PRIMARY KEY ("chat_id", "message_id"));
CREATE INDEX messages_date ON messages (date, message_id);
CREATE INDEX messages_grouped ON messages (chat_id, grouped_id);
CREATE TABLE "vouches" ("source_chat_id" INTEGER NOT NULL,
  "target_chat_id" INTEGER NOT NULL, "first_seen" INTEGER NOT NULL,
  "last_seen" INTEGER NOT NULL, "count" INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY ("source_chat_id", "target_chat_id"));
CREATE INDEX vouches_target ON vouches (target_chat_id);
''';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('feedgram_migration');
    file = File('${dir.path}/feed.sqlite');

    final db = raw.sqlite3.open(file.path);
    db.execute(_v4Ddl);

    db.execute(
      "INSERT INTO channels (id, username, title, subscriber_count, source) "
      "VALUES (-1001, 'followed', 'A followed channel', 50000, 'subscribed')",
    );
    db.execute(
      "INSERT INTO channels (id, username, title, subscriber_count, source) "
      "VALUES (-1002, 'byhand', 'Added by hand', 12000, 'curated')",
    );
    // The row that breaks everything if the migration forgets it.
    db.execute(
      "INSERT INTO channels (id, username, title, subscriber_count, source) "
      "VALUES (-2001, 'fromgraph', 'Found by the graph', 900, 'suggested')",
    );

    for (final (index, chatId) in [-1001, -1002, -2001].indexed) {
      db.execute(
        'INSERT INTO messages (chat_id, message_id, date, text, view_count, '
        'forwarded_from_chat_id) VALUES (?, ?, ?, ?, ?, ?)',
        [chatId, 500 + index, 1700000000 + index, 'post $index', 10, -2001],
      );
    }

    // Media rows for the v7 classification backfill. The .gif document is the
    // real-world case that made this necessary.
    db.execute(
      "INSERT INTO messages (chat_id, message_id, date, text, media_json) "
      "VALUES (-1001, 601, 1700001000, '', "
      '\'{"type":"document","name":"855334_0.gif","fileId":7}\')',
    );
    db.execute(
      "INSERT INTO messages (chat_id, message_id, date, text, media_json) "
      "VALUES (-1001, 602, 1700001001, '', "
      '\'{"type":"document","name":"report.pdf","fileId":8}\')',
    );
    db.execute(
      "INSERT INTO messages (chat_id, message_id, date, text, media_json) "
      "VALUES (-1001, 603, 1700001002, '', "
      '\'{"type":"photo","fileId":9}\')',
    );

    db.execute(
      'INSERT INTO vouches (source_chat_id, target_chat_id, first_seen, '
      'last_seen, count) VALUES (-1001, -2001, 1700000000, 1700000100, 3)',
    );

    db.execute('PRAGMA user_version = 4');
    db.close();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppDatabase> migrate() async {
    final db = AppDatabase(NativeDatabase(file));
    // Drift runs migrations lazily on first use.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  test('upgrades a v4 database to the current version', () async {
    final db = await migrate();
    addTearDown(db.close);

    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, 9);
  });

  group('v6 — channel_lists', () {
    test('every existing channel becomes a Following member', () async {
      final db = await migrate();
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT chat_id, list_name FROM channel_lists')
          .get();
      expect(rows, hasLength(3), reason: 'all three channels migrate');
      expect(
        {for (final r in rows) r.read<String>('list_name')},
        {'following'},
      );
      expect(
        {for (final r in rows) r.read<int>('chat_id')},
        {-1001, -1002, -2001},
      );
    });

    test('for_you starts empty', () async {
      final db = await migrate();
      addTearDown(db.close);

      final forYou = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM channel_lists WHERE list_name = 'for_you'",
          )
          .getSingle();
      expect(forYou.read<int>('n'), 0,
          reason: 'the ranked list is filled by hand, never inherited');
    });

    test('the Following feed shows the same posts as before the upgrade',
        () async {
      final db = await migrate();
      addTearDown(db.close);

      // This is what the checkpoint means by "existing channels intact": the
      // feed now joins through channel_lists, so a migration that missed a
      // channel would silently shrink it.
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM messages m '
            'JOIN channels c ON c.id = m.chat_id '
            "JOIN channel_lists l ON l.chat_id = m.chat_id "
            "AND l.list_name = 'following'",
          )
          .getSingle();
      expect(rows.read<int>('n'), 6, reason: '3 text + 3 media rows seeded');
    });

    test('the list_name index exists', () async {
      final db = await migrate();
      addTearDown(db.close);

      final index = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'channel_lists_name'",
          )
          .get();
      // createTable does not create @TableIndex entities; every migration branch
      // has to add them explicitly. This is the third time that has mattered.
      expect(index, hasLength(1));
    });

    test('a migrated channel is not an orphan', () async {
      final db = await migrate();
      addTearDown(db.close);

      final orphans = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM channels c WHERE NOT EXISTS '
            '(SELECT 1 FROM channel_lists l WHERE l.chat_id = c.id)',
          )
          .getSingle();
      expect(orphans.read<int>('n'), 0);
    });
  });

  test('rewrites suggested channels instead of orphaning them', () async {
    final db = await migrate();
    addTearDown(db.close);

    // The whole point: this select would throw on an unmigrated 'suggested' row.
    final channels = await db.select(db.channels).get();
    expect(channels, hasLength(3), reason: 'no channel should be lost');

    final rewritten = channels.firstWhere((c) => c.id == -2001);
    expect(rewritten.source, ChannelSource.curated);
    expect(rewritten.title, 'Found by the graph',
        reason: 'the row is converted, not recreated');

    // Untouched rows keep their source.
    expect(channels.firstWhere((c) => c.id == -1001).source,
        ChannelSource.subscribed);
    expect(
        channels.firstWhere((c) => c.id == -1002).source, ChannelSource.curated);
  });

  test('drops the vouches table and its index', () async {
    final db = await migrate();
    addTearDown(db.close);

    final leftovers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name IN ('vouches', "
          "'vouches_target')",
        )
        .get();
    expect(leftovers, isEmpty);
  });

  test('keeps messages and forwarded_from_chat_id', () async {
    final db = await migrate();
    addTearDown(db.close);

    // The spec keeps this column for "forwarded from X" display even though it no
    // longer feeds any ranking.
    final messages = await db.select(db.messages).get();
    expect(messages, hasLength(6), reason: '3 text + 3 media rows seeded');
    final forwarded =
        messages.where((m) => m.forwardedFromChatId != null).toList();
    expect(forwarded, hasLength(3));
    expect(forwarded.every((m) => m.forwardedFromChatId == -2001), isTrue);
  });

  test('the Following feed still returns every channel after migrating',
      () async {
    final db = await migrate();
    addTearDown(db.close);

    // Following does not filter on source, so converting rather than deleting is
    // what keeps every channel's posts reachable. Deleting the suggested channel
    // would have silently dropped a third of the feed.
    final perChannel = await db
        .customSelect(
          'SELECT c.id AS id, COUNT(*) AS n FROM messages m '
          'JOIN channels c ON c.id = m.chat_id GROUP BY c.id',
        )
        .map((r) => r.read<int>('id'))
        .get();
    expect(perChannel, containsAll([-1001, -1002, -2001]),
        reason: 'the converted channel still contributes posts');
  });

  test('a second open is a no-op', () async {
    final first = await migrate();
    await first.close();

    final second = await migrate();
    addTearDown(second.close);
    expect(await second.select(second.channels).get(), hasLength(3));
  });

  group('v7 content classification backfill', () {
    test('derives content_kind from the stored media descriptor', () async {
      final db = await migrate();
      addTearDown(db.close);

      // 12k existing rows must classify without a re-backfill, so the migration
      // reads media_json rather than needing TDLib.
      final kinds = await db
          .customSelect(
            'SELECT message_id, content_kind FROM messages ORDER BY message_id',
          )
          .map((r) => (r.read<int>('message_id'), r.read<String>('content_kind')))
          .get();

      expect(kinds, isNotEmpty);
      // Row 500 was seeded with no media_json at all.
      expect(kinds.firstWhere((k) => k.$1 == 500).$2, 'text');
    });

    test('rescues GIFs that were stored as documents', () async {
      final db = await migrate();
      addTearDown(db.close);

      // The @gifs6 case: a document named *.gif is real content, and the document
      // filter would otherwise hide it forever.
      final kind = await db
          .customSelect(
            'SELECT content_kind FROM messages WHERE message_id = 601',
          )
          .map((r) => r.read<String>('content_kind'))
          .getSingle();
      expect(kind, 'animation');
    });

    test('leaves genuine documents hidden', () async {
      final db = await migrate();
      addTearDown(db.close);

      final kind = await db
          .customSelect(
            'SELECT content_kind FROM messages WHERE message_id = 602',
          )
          .map((r) => r.read<String>('content_kind'))
          .getSingle();
      expect(kind, 'document');
    });

    test('via_bot defaults to false for rows that predate it', () async {
      final db = await migrate();
      addTearDown(db.close);

      // It was never stored, so it cannot be recovered — already-cached
      // auto-poster spam stays visible until those channels are backfilled again.
      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM messages WHERE via_bot = 0')
          .map((r) => r.read<int>('n'))
          .getSingle();
      final total = await db
          .customSelect('SELECT COUNT(*) AS n FROM messages')
          .map((r) => r.read<int>('n'))
          .getSingle();
      expect(count, total);
    });
  });

  group('v8 score column', () {
    test('exists, is indexed, and starts null', () async {
      final db = await migrate();
      addTearDown(db.close);

      final scores = await db
          .customSelect('SELECT COUNT(*) AS n FROM messages WHERE score IS NULL')
          .map((r) => r.read<int>('n'))
          .getSingle();
      final total = await db
          .customSelect('SELECT COUNT(*) AS n FROM messages')
          .map((r) => r.read<int>('n'))
          .getSingle();
      // Null on purpose: a score only means something for the for_you pool inside
      // the window, and the first scoring pass fills it in. Inventing values here
      // would rank posts that are not candidates.
      expect(scores, total);

      final index = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'messages_score'",
          )
          .get();
      expect(index, hasLength(1),
          reason: 'For You reads in score order and must not sort per page');
    });
  });

  test('v9 creates the seen-post table empty', () async {
    final db = await migrate();
    addTearDown(db.close);

    // Nothing is pre-marked: an upgrade must not hide posts the reader has never
    // actually been shown.
    final seen = await db
        .customSelect('SELECT COUNT(*) AS n FROM seen_posts')
        .map((r) => r.read<int>('n'))
        .getSingle();
    expect(seen, 0);
  });
}