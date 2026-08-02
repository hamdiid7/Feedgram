import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/channel_repository.dart';
import 'package:feedgram/data/message_repository.dart';
import 'package:feedgram/telegram/telegram_client.dart';

/// Feed filtering, exercised through the real query.
///
/// The rules live in SQL rather than at insert time so they can change without
/// re-backfilling, which means the query is the only place they can be verified.
void main() {
  late AppDatabase db;
  late ChannelRepository channels;
  late MessageRepository messages;

  var nextId = 500;

  setUp(() async {
    nextId = 500;
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
  });

  tearDown(() => db.close());

  Future<int> add({
    required ContentKind kind,
    bool viaBot = false,
  }) async {
    final id = nextId++;
    await db.into(db.messages).insert(MessagesCompanion.insert(
          chatId: -1001,
          messageId: id,
          date: 1700000000 + id,
          body: Value('post $id'),
          contentKind: Value(kind),
          viaBot: Value(viaBot),
        ));
    return id;
  }

  Future<List<int>> feedIds() async {
    final feed = await messages.watchFeedHead().first;
    return [for (final entry in feed) entry.message.messageId];
  }

  group('hidden kinds', () {
    test('documents, audio and voice never appear', () async {
      final text = await add(kind: ContentKind.text);
      final photo = await add(kind: ContentKind.photo);
      await add(kind: ContentKind.document);
      await add(kind: ContentKind.audio);
      await add(kind: ContentKind.voice);

      expect(await feedIds(), unorderedEquals([text, photo]));
    });

    test('video, animation and poll are kept', () async {
      final video = await add(kind: ContentKind.video);
      final animation = await add(kind: ContentKind.animation);
      final poll = await add(kind: ContentKind.poll);

      expect(await feedIds(), unorderedEquals([video, animation, poll]));
    });

    test('the hidden set is exactly what the spec names', () {
      expect(hiddenContentKinds, {
        ContentKind.document,
        ContentKind.audio,
        ContentKind.voice,
      });
    });
  });

  group('via bot', () {
    test('bot-posted content is hidden whatever kind it is', () async {
      final human = await add(kind: ContentKind.photo);
      await add(kind: ContentKind.photo, viaBot: true);
      await add(kind: ContentKind.text, viaBot: true);

      expect(await feedIds(), [human]);
    });
  });

  group('scope', () {
    test('a channel profile applies the same filters', () async {
      final photo = await add(kind: ContentKind.photo);
      await add(kind: ContentKind.document);
      await add(kind: ContentKind.photo, viaBot: true);

      // A channel must look the same wherever you read it; filtering only the
      // merged feed would make the profile the odd one out.
      final feed = await messages.watchFeedHead(chatId: -1001).first;
      expect([for (final e in feed) e.message.messageId], [photo]);
    });

    test('filters survive keyset pagination', () async {
      // Interleave hidden rows so a page boundary lands on one.
      final kept = <int>[];
      for (var i = 0; i < 6; i++) {
        kept.add(await add(kind: ContentKind.photo));
        await add(kind: ContentKind.document);
      }

      final head = await messages.watchFeedHead(limit: 3).first;
      expect(head, hasLength(3));

      final last = head.last.message;
      final next = await messages.feedPage(
        after: FeedCursor(date: last.date, messageId: last.messageId),
        limit: 10,
      );

      final all = [
        for (final e in [...head, ...next]) e.message.messageId,
      ];
      expect(all, hasLength(6), reason: 'no hidden row leaks in via a page edge');
      expect(all.toSet(), kept.toSet());
    });
  });
}
