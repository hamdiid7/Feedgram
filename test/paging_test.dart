import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/channel_repository.dart';
import 'package:feedgram/data/message_repository.dart';
import 'package:feedgram/telegram/telegram_client.dart';
import 'package:feedgram/ui/feed/chronological_feed.dart';

/// Keyset pagination over the real query.
///
/// `OFFSET` is never used: it rescans from the top for every page and shifts under
/// you as new posts land, which both duplicates and skips rows. These tests pin
/// that the cursor behaves instead.
void main() {
  late AppDatabase db;
  late ChannelRepository channels;
  late MessageRepository messages;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    channels = ChannelRepository(client: TelegramClient(), db: db);
    messages = MessageRepository(client: TelegramClient(), db: db);

    await db.into(db.channels).insert(ChannelsCompanion.insert(
          id: const Value(-1001),
          title: const Value('A channel'),
          username: const Value('chan'),
          source: ChannelSource.curated,
        ));
    await channels.addToList(-1001, ChannelList.following);

    // 120 posts, newest first by date.
    for (var i = 0; i < 120; i++) {
      await db.into(db.messages).insert(MessagesCompanion.insert(
            chatId: -1001,
            messageId: 1000 + i,
            date: 1700000000 + i,
            body: Value('post $i'),
            contentKind: const Value(ContentKind.text),
          ));
    }
  });

  tearDown(() => db.close());

  test('page sizes follow the spec', () {
    expect(ChronologicalFeed.firstPageSize, 100);
    expect(ChronologicalFeed.pageSize, 50);
    expect(ChronologicalFeed.profileFirstPageSize, 50);
    // Prefetch must start before the bottom, or the user always meets a spinner.
    expect(ChronologicalFeed.prefetchThreshold, greaterThan(0));
  });

  test('the first page is the newest 100', () async {
    final head = await messages
        .watchFeedHead(limit: ChronologicalFeed.firstPageSize)
        .first;

    expect(head, hasLength(100));
    // Newest first.
    expect(head.first.message.messageId, 1119);
    expect(head.last.message.messageId, 1020);
  });

  test('paging walks backwards without gaps or repeats', () async {
    final seen = <int>[];

    var page = await messages
        .watchFeedHead(limit: ChronologicalFeed.firstPageSize)
        .first;
    seen.addAll([for (final e in page) e.message.messageId]);

    while (page.isNotEmpty) {
      final last = page.last.message;
      page = await messages.feedPage(
        after: FeedCursor(date: last.date, messageId: last.messageId),
        limit: ChronologicalFeed.pageSize,
      );
      seen.addAll([for (final e in page) e.message.messageId]);
    }

    expect(seen, hasLength(120), reason: 'every post exactly once');
    expect(seen.toSet(), hasLength(120), reason: 'no duplicates');
    // Strictly descending.
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], lessThan(seen[i - 1]));
    }
  });

  test('a new post arriving mid-scroll does not shift older pages', () async {
    final head = await messages.watchFeedHead(limit: 50).first;
    final last = head.last.message;

    // The failure mode OFFSET has: insert at the top, then the next page skips a
    // row because everything shifted down by one.
    await db.into(db.messages).insert(MessagesCompanion.insert(
          chatId: -1001,
          messageId: 9999,
          date: 1700009999,
          body: const Value('breaking'),
          contentKind: const Value(ContentKind.text),
        ));

    final next = await messages.feedPage(
      after: FeedCursor(date: last.date, messageId: last.messageId),
      limit: 50,
    );

    final ids = [for (final e in next) e.message.messageId];
    expect(ids, isNot(contains(9999)), reason: 'the new post belongs at the top');
    expect(ids.first, last.messageId - 1, reason: 'continues exactly where it left off');
  });

  test('ties on date are resolved by message id', () async {
    // date alone is not unique — Telegram timestamps are per-second and albums
    // share one. Without the tuple comparison these rows would repeat or vanish.
    for (var i = 0; i < 4; i++) {
      await db.into(db.messages).insert(MessagesCompanion.insert(
            chatId: -1001,
            messageId: 7000 + i,
            date: 1700005000,
            body: Value('same second $i'),
            contentKind: const Value(ContentKind.text),
          ));
    }

    final all = <int>[];
    var page = await messages.watchFeedHead(limit: 3).first;
    all.addAll([for (final e in page) e.message.messageId]);

    while (page.isNotEmpty && all.length < 130) {
      final last = page.last.message;
      page = await messages.feedPage(
        after: FeedCursor(date: last.date, messageId: last.messageId),
        limit: 3,
      );
      all.addAll([for (final e in page) e.message.messageId]);
    }

    final tied = all.where((id) => id >= 7000 && id < 7004).toList();
    expect(tied, hasLength(4), reason: 'all four same-second rows appear once');
    expect(tied.toSet(), hasLength(4));
  });

  test('an exhausted feed reports a short page', () async {
    final head = await messages.watchFeedHead(limit: 100).first;
    final last = head.last.message;

    final next = await messages.feedPage(
      after: FeedCursor(date: last.date, messageId: last.messageId),
      limit: ChronologicalFeed.pageSize,
    );

    // 120 total, 100 in the head, so this page is short — which is what tells the
    // feed to show "all caught up" rather than a spinner forever.
    expect(next, hasLength(20));
    expect(next.length, lessThan(ChronologicalFeed.pageSize));
  });
}
