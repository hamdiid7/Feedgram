import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/channel_repository.dart';
import 'package:feedgram/data/message_repository.dart';
import 'package:feedgram/telegram/telegram_client.dart';

/// Membership behaviour, and the feed queries that join through it.
///
/// None of these paths touch TDLib, so a bare [TelegramClient] is enough — it
/// spawns nothing until `start()`.
void main() {
  late AppDatabase db;
  late ChannelRepository channels;
  late MessageRepository messages;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    channels = ChannelRepository(client: TelegramClient(), db: db);
    messages = MessageRepository(client: TelegramClient(), db: db);

    for (final (index, id) in [-1001, -1002, -1003].indexed) {
      await db.into(db.channels).insert(ChannelsCompanion.insert(
            id: Value(id),
            title: Value('Channel $index'),
            username: Value('chan$index'),
            subscriberCount: Value(1000 * (index + 1)),
            source: ChannelSource.curated,
          ));
      await db.into(db.messages).insert(MessagesCompanion.insert(
            chatId: id,
            messageId: 500 + index,
            date: 1700000000 + index,
            body: Value('post $index'),
          ));
    }
  });

  tearDown(() => db.close());

  group('membership', () {
    test('the enum is stored as the snake_case name the schema specifies',
        () async {
      await channels.addToList(-1001, ChannelList.forYou);

      final raw = await db
          .customSelect('SELECT list_name FROM channel_lists')
          .map((r) => r.read<String>('list_name'))
          .get();
      // Not 'forYou' — drift's default would have written the Dart identifier.
      expect(raw, ['for_you']);
    });

    test('a channel can be in both lists at once', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1001, ChannelList.forYou);

      expect(await channels.listsFor(-1001),
          {ChannelList.following, ChannelList.forYou});
    });

    test('adding twice keeps the original added_at', () async {
      await db.into(db.channelLists).insert(ChannelListsCompanion.insert(
            chatId: -1001,
            listName: ChannelList.following,
            addedAt: 111,
          ));
      await channels.addToList(-1001, ChannelList.following);

      final addedAt = await db
          .customSelect('SELECT added_at FROM channel_lists')
          .map((r) => r.read<int>('added_at'))
          .getSingle();
      expect(addedAt, 111, reason: 'a re-add must not look like a fresh add');
    });

    test('removing from one list leaves the other', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1001, ChannelList.forYou);

      await channels.removeFromList(-1001, ChannelList.following);
      expect(await channels.listsFor(-1001), {ChannelList.forYou});
    });

    test('channelsIn returns only that list', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1002, ChannelList.forYou);

      expect([for (final c in await channels.channelsIn(ChannelList.following)) c.id],
          [-1001]);
      expect([for (final c in await channels.channelsIn(ChannelList.forYou)) c.id],
          [-1002]);
    });

    test('watchChannels folds one row per channel, not per membership',
        () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1001, ChannelList.forYou);

      final tracked = await channels.watchChannels().first;
      expect(tracked, hasLength(3), reason: 'a dual-list channel is still one row');

      final both = tracked.firstWhere((t) => t.channel.id == -1001);
      expect(both.lists, {ChannelList.following, ChannelList.forYou});
      expect(both.isOrphan, isFalse);
    });
  });

  group('the two feeds are independent', () {
    test('each list returns only its own members', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1002, ChannelList.forYou);

      final following =
          await messages.watchFeedHead(list: ChannelList.following).first;
      final forYou =
          await messages.watchFeedHead(list: ChannelList.forYou).first;

      expect([for (final e in following) e.message.chatId], [-1001]);
      expect([for (final e in forYou) e.message.chatId], [-1002]);
    });

    test('a dual-list channel appears in both', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1001, ChannelList.forYou);

      for (final list in ChannelList.values) {
        final feed = await messages.watchFeedHead(list: list).first;
        expect([for (final e in feed) e.message.chatId], contains(-1001),
            reason: 'should be in ${list.name}');
      }
    });

    test('for_you is empty when nothing has been added to it', () async {
      await channels.addToList(-1001, ChannelList.following);
      await channels.addToList(-1002, ChannelList.following);

      expect(await messages.watchFeedHead(list: ChannelList.forYou).first,
          isEmpty);
    });

    test('paging respects the list scope', () async {
      // Two members in for_you, one page size of 1, so the cursor has to stay
      // inside the list rather than wandering into Following's posts.
      await channels.addToList(-1001, ChannelList.forYou);
      await channels.addToList(-1002, ChannelList.forYou);
      await channels.addToList(-1003, ChannelList.following);

      final head = await messages
          .watchFeedHead(limit: 1, list: ChannelList.forYou)
          .first;
      expect(head, hasLength(1));

      final next = await messages.feedPage(
        after: FeedCursor(
          date: head.first.message.date,
          messageId: head.first.message.messageId,
        ),
        limit: 10,
        list: ChannelList.forYou,
      );
      expect([for (final e in next) e.message.chatId], isNot(contains(-1003)));
    });
  });

  group('orphans', () {
    test('a channel in no list is an orphan but is still listed', () async {
      final tracked = await channels.watchChannels().first;
      expect(tracked.every((t) => t.isOrphan), isTrue);
      expect(await channels.orphanedChannels(), hasLength(3));
    });

    test('orphans are invisible to the Following feed', () async {
      await channels.addToList(-1001, ChannelList.following);

      final feed = await messages.watchFeedHead().first;
      expect([for (final e in feed) e.message.chatId], [-1001],
          reason: 'only members contribute posts');
    });

    test('an orphan keeps its posts, and re-adding needs no backfill', () async {
      await channels.addToList(-1002, ChannelList.following);
      await channels.removeFromList(-1002, ChannelList.following);

      // The decision: cached, not deleted.
      final stillThere = await (db.select(db.messages)
            ..where((m) => m.chatId.equals(-1002)))
          .get();
      expect(stillThere, hasLength(1));

      await channels.addToList(-1002, ChannelList.following);
      final feed = await messages.watchFeedHead().first;
      expect([for (final e in feed) e.message.chatId], contains(-1002));
    });

    test('a channel profile still works for an orphan', () async {
      // Scoped queries address a channel directly, so they deliberately skip the
      // membership join.
      final feed = await messages.watchFeedHead(chatId: -1003).first;
      expect(feed, hasLength(1));
    });

    test('purge removes orphans and their posts, only when asked', () async {
      await channels.addToList(-1001, ChannelList.following);

      final purged = await channels.purgeOrphanedChannels();
      expect(purged, 2);
      expect(await channels.countChannels(), 1);
      expect(await messages.countMessages(), 1);
    });

    test('purge is a no-op when everything is a member', () async {
      for (final id in [-1001, -1002, -1003]) {
        await channels.addToList(id, ChannelList.following);
      }
      expect(await channels.purgeOrphanedChannels(), 0);
      expect(await channels.countChannels(), 3);
    });
  });
}
