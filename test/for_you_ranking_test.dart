import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/channel_repository.dart';
import 'package:feedgram/data/for_you_repository.dart';
import 'package:feedgram/data/message_repository.dart';
import 'package:feedgram/domain/for_you_ranking.dart';
import 'package:feedgram/telegram/telegram_client.dart';

/// The For You ranking, against the real schema and the real SQL.
///
/// Two properties are mandatory per spec and both are easy to lose silently:
/// smoothing toward the mean, and the hard view floor. A regression in either
/// fills the feed with low-view oddities, which is exactly the failure the
/// checkpoint asks you to look for.
void main() {
  const now = 1700000000;
  const day = 86400;

  late AppDatabase db;
  late ChannelRepository channels;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    channels = ChannelRepository(client: TelegramClient(), db: db);
  });

  tearDown(() => db.close());

  Future<void> channel(int id, {bool inForYou = true, bool following = false}) async {
    await db.into(db.channels).insert(ChannelsCompanion.insert(
          id: Value(id),
          title: Value('Channel $id'),
          username: Value('c$id'),
          source: ChannelSource.curated,
        ));
    if (inForYou) await channels.addToList(id, ChannelList.forYou);
    if (following) await channels.addToList(id, ChannelList.following);
  }

  Future<void> post({
    required int chatId,
    required int messageId,
    required int views,
    required int likes,
    int ageDays = 1,
    ContentKind kind = ContentKind.photo,
    bool viaBot = false,
  }) async {
    await db.into(db.messages).insert(MessagesCompanion.insert(
          chatId: chatId,
          messageId: messageId,
          date: now - ageDays * day,
          body: Value('post $messageId'),
          viewCount: Value(views),
          reactionCount: Value(likes),
          contentKind: Value(kind),
          viaBot: Value(viaBot),
        ));
  }

  ForYouRepository repo({ForYouWeights? weights}) =>
      ForYouRepository(db: db, weights: weights ?? const ForYouWeights());

  Future<List<int>> ranked(ForYouRepository r, {int limit = 50}) async {
    final page = await r.page(limit: limit, nowSeconds: now);
    return [for (final e in page) e.message.messageId];
  }

  group('smoothing', () {
    test('shrinks a score toward the mean in proportion to how thin the '
        'evidence is', () async {
      await channel(-1);
      // Same 50% ratio, wildly different volume. Both above the floor, so this
      // isolates the smoothing.
      await post(chatId: -1, messageId: 1, views: 600, likes: 300);
      await post(chatId: -1, messageId: 2, views: 60000, likes: 30000);
      // A large ordinary post, so the pool mean is well below 50%. Without it the
      // mean *is* 50% and shrinking toward it is a no-op — correct, but it would
      // prove nothing.
      await post(chatId: -1, messageId: 3, views: 200000, likes: 4000);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final scores = await db
          .customSelect('SELECT message_id, score FROM messages')
          .map((row) =>
              (row.read<int>('message_id'), row.read<double>('score')))
          .get();
      final thin = scores.firstWhere((s) => s.$1 == 1).$2;
      final solid = scores.firstWhere((s) => s.$1 == 2).$2;

      // The identical raw ratio must not produce identical scores: the post with
      // a hundred times the evidence keeps far more of it.
      // Compared relatively: every score now carries the same recency multiplier
      // at equal age, so absolute values would just be testing that constant.
      expect(thin, lessThan(solid));
      expect(solid / thin, greaterThan(1.4),
          reason: 'a hundred times the evidence should keep visibly more of it');
      // ...and neither is dragged below the pool mean.
      expect(thin, greaterThan(r.meanRatio));
    });

    test('a ratio built on almost nothing collapses to the mean', () async {
      await channel(-1);
      // The pathological case: 2 views, 1 like, raw ratio 0.5. With no view floor
      // it is still a candidate, so smoothing is the only thing standing between
      // it and the top of the feed.
      await post(chatId: -1, messageId: 1, views: 2, likes: 1);
      await post(chatId: -1, messageId: 2, views: 20000, likes: 1000);
      await post(chatId: -1, messageId: 3, views: 30000, likes: 6000);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final scores = await db
          .customSelect('SELECT message_id, score FROM messages')
          .map((row) => (row.read<int>('message_id'), row.read<double>('score')))
          .get();
      final tiny = scores.firstWhere((e) => e.$1 == 1).$2;

      // Shrunk to well under half its raw 0.5: two views is no evidence, so it
      // lands near the pool mean instead of at the top.
      expect(tiny, lessThan(0.25));
      expect(tiny, greaterThan(r.meanRatio),
          reason: 'above average, but only just');
      // And a genuinely strong, high-volume post beats it outright.
      expect((await ranked(r)).first, 3);
    });

    test('a low-view post cannot outrank a clearly better one', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5, likes: 3);
      await post(chatId: -1, messageId: 2, views: 40000, likes: 8000);
      // A third, ordinary post so the pool mean sits below the good one. With only
      // two posts the strong one *defines* average and cannot be above it — a
      // property of the metric, not a bug, but it makes the comparison vacuous.
      await post(chatId: -1, messageId: 3, views: 60000, likes: 1200);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [2, 1, 3]);
    });

    test('volume earns an extreme score', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 50000, likes: 15000); // 30%
      await post(chatId: -1, messageId: 2, views: 50000, likes: 2500); // 5%

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [1, 2]);
    });

    test('the prior is the pooled ratio, not the mean of ratios', () async {
      await channel(-1);
      // One huge post at 10%, many tiny ones at 50%. Averaging ratios would put
      // the prior near 50% and let the tiny posts set the standard.
      await post(chatId: -1, messageId: 1, views: 100000, likes: 10000);
      for (var i = 0; i < 5; i++) {
        await post(chatId: -1, messageId: 10 + i, views: 600, likes: 300);
      }

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      // Pooled: 11500 likes / 103000 views ≈ 0.112, dominated by the big post.
      expect(r.meanRatio, closeTo(0.112, 0.01));
    });
  });

  group('view floor', () {
    test('posts under the floor do not rank at all', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 499, likes: 400);
      await post(chatId: -1, messageId: 2, views: 501, likes: 10);

      final r = repo(weights: const ForYouWeights(minViews: 500));
      await r.recomputeScores(nowSeconds: now);

      // Belt and braces with smoothing: below the floor it is not a candidate,
      // whatever its ratio.
      expect(await ranked(r), [2]);
    });

    test('the floor is enforced in the score column, not just the query',
        () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 10, likes: 10);

      final r = repo(weights: const ForYouWeights(minViews: 500));
      await r.recomputeScores(nowSeconds: now);

      final score = await db
          .customSelect('SELECT score FROM messages WHERE message_id = 1')
          .map((row) => row.readNullable<double>('score'))
          .getSingle();
      expect(score, isNull);
    });
  });

  group('window', () {
    test('posts older than 7 days are excluded outright', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 1000, likes: 100, ageDays: 3);
      await post(chatId: -1, messageId: 2, views: 90000, likes: 40000, ageDays: 9);

      // Opt-in: the feed no longer windows by default, because a hard cutoff made
      // it simply end. The recency boost handles freshness instead.
      final r = repo(weights: const ForYouWeights(windowDays: 7));
      await r.recomputeScores(nowSeconds: now);

      // With a window set, even a spectacular old post is out.
      expect(await ranked(r), [1]);
    });

    test('a post falling out of the window has its score cleared', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 1000, likes: 100, ageDays: 6);

      final r = repo(weights: const ForYouWeights(windowDays: 7));
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [1]);

      // Three days later the same post is outside the window.
      await r.recomputeScores(nowSeconds: now + 3 * day);
      final page = await r.page(nowSeconds: now + 3 * day);
      expect(page, isEmpty, reason: 'a stale score must not linger');
    });
  });

  group('pool', () {
    test('Following-only channels never rank', () async {
      await channel(-1, inForYou: false, following: true);
      await channel(-2);
      await post(chatId: -1, messageId: 1, views: 100000, likes: 50000);
      await post(chatId: -2, messageId: 2, views: 1000, likes: 10);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [2]);
    });

    test('content filters still apply', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);
      await post(
          chatId: -1, messageId: 2, views: 90000, likes: 80000,
          kind: ContentKind.document);
      await post(chatId: -1, messageId: 3, views: 90000, likes: 80000, viaBot: true);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [1]);
    });
  });

  group('diversity', () {
    test('one channel cannot take the page', () async {
      await channel(-1);
      await channel(-2);
      // -1 has the ten best posts outright.
      for (var i = 0; i < 10; i++) {
        await post(chatId: -1, messageId: 100 + i, views: 10000, likes: 5000 - i);
      }
      for (var i = 0; i < 4; i++) {
        await post(chatId: -2, messageId: 200 + i, views: 10000, likes: 500 - i);
      }

      final r = repo(weights: const ForYouWeights(maxPerPage: 3));
      await r.recomputeScores(nowSeconds: now);

      final page = await r.page(limit: 50, nowSeconds: now);
      final perChannel = <int, int>{};
      for (final entry in page) {
        perChannel.update(entry.message.chatId, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(perChannel[-1], lessThanOrEqualTo(3));
      expect(perChannel[-2], lessThanOrEqualTo(3));
    });

    test('cards from one channel are not consecutive', () async {
      await channel(-1);
      await channel(-2);
      await channel(-3);
      for (final chatId in [-1, -2, -3]) {
        for (var i = 0; i < 3; i++) {
          await post(
              chatId: chatId, messageId: -chatId * 100 + i,
              views: 10000, likes: 1000 - i);
        }
      }

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      final page = await r.page(limit: 9, nowSeconds: now);

      final chats = [for (final e in page) e.message.chatId];
      for (var i = 1; i < chats.length; i++) {
        expect(chats[i], isNot(chats[i - 1]),
            reason: 'round-robin should interleave channels');
      }
    });
  });

  group('paging', () {
    test('the keyset walks down the score order without repeats', () async {
      await channel(-1);
      await channel(-2);
      await channel(-3);
      for (final chatId in [-1, -2, -3]) {
        for (var i = 0; i < 3; i++) {
          await post(
              chatId: chatId, messageId: -chatId * 100 + i,
              views: 10000, likes: 900 - i * 10 + chatId);
        }
      }

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final seen = <int>[];
      var page = await r.page(limit: 4, nowSeconds: now);
      seen.addAll([for (final e in page) e.message.messageId]);

      var cursor = ForYouRepository.cursorFrom(page);
      while (page.isNotEmpty && cursor != null && seen.length < 20) {
        page = await r.page(after: cursor, limit: 4, nowSeconds: now);
        seen.addAll([for (final e in page) e.message.messageId]);
        cursor = ForYouRepository.cursorFrom(page) ?? cursor;
      }

      expect(seen.toSet(), hasLength(seen.length), reason: 'no duplicates');
    });

    test('a short page is not the end of the feed', () async {
      // Three channels x maxPerPage 3 means a page can never exceed nine rows,
      // however large the limit. ForYouFeed used to read that shortfall as
      // "exhausted" and stop after one page, stranding everything below.
      for (final chatId in [-1, -2, -3]) {
        await channel(chatId);
        for (var i = 0; i < 40; i++) {
          await post(
              chatId: chatId, messageId: -chatId * 1000 + i,
              views: 10000, likes: 2000 - i * 10 + chatId);
        }
      }

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final first = await r.page(limit: 100, nowSeconds: now);
      expect(first, hasLength(lessThan(100)),
          reason: 'the per-channel cap makes a full page impossible here');
      expect(first, isNotEmpty);

      // The posts the short page did not reach are still there, which is what
      // makes ending on a short page wrong.
      final next = await r.page(
          after: ForYouRepository.cursorFrom(first),
          limit: 100,
          nowSeconds: now);
      expect(next, isNotEmpty,
          reason: 'a short page must not be treated as exhaustion');
    });

    test('an exhausted pool refills once the seen history is forgotten',
        () async {
      await channel(-1);
      for (var i = 0; i < 3; i++) {
        await post(chatId: -1, messageId: 100 + i, views: 10000, likes: 500 - i);
      }

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      await r.markSeen(await r.page(nowSeconds: now));
      expect(await r.page(nowSeconds: now), isEmpty);

      // What ForYouFeed._recycle relies on to keep the feed endless: candidates
      // outlive the seen history, so clearing it serves them again.
      expect(await r.countCandidates(nowSeconds: now), greaterThan(0));
      await r.forgetSeen();
      expect(await r.page(nowSeconds: now), hasLength(3));
    });
  });

  group('rescoring', () {
    test('a counter update changes the score', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 50);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final before = await db
          .customSelect('SELECT score FROM messages WHERE message_id = 1')
          .map((row) => row.read<double>('score'))
          .getSingle();

      await (db.update(db.messages)..where((m) => m.messageId.equals(1)))
          .write(const MessagesCompanion(reactionCount: Value(2500)));
      await r.rescoreMessage(-1, 1, nowSeconds: now);

      final after = await db
          .customSelect('SELECT score FROM messages WHERE message_id = 1')
          .map((row) => row.read<double>('score'))
          .getSingle();

      expect(after, greaterThan(before));
    });
  });

  test('defaults rank everything, with recency as a nudge', () {
    const w = ForYouWeights();
    // No window and no view floor: the feed should not run out. Smoothing keeps
    // low-volume posts honest, so the floor is a dial rather than a default.
    expect(w.hasWindow, isFalse);
    expect(w.minViews, 0);
    expect(w.priorViews, 500);
    expect(w.maxPerPage, 3);
    // Mild on purpose — engagement stays the primary signal.
    expect(w.recencyBoost, lessThanOrEqualTo(0.3));
    expect(w.recencyBoost, greaterThan(0));
  });

  group('recency', () {
    test('breaks a tie toward the fresher post', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 10000, likes: 800, ageDays: 0);
      await post(chatId: -1, messageId: 2, views: 10000, likes: 800, ageDays: 20);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [1, 2]);
    });

    test('cannot overturn a clearly better post', () async {
      await channel(-1);
      // Fresh but mediocre versus old and excellent. Engagement must still win —
      // the boost is a nudge, not a re-ordering.
      await post(chatId: -1, messageId: 1, views: 10000, likes: 200, ageDays: 0);
      await post(chatId: -1, messageId: 2, views: 10000, likes: 3000, ageDays: 30);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      expect(await ranked(r), [2, 1]);
    });
  });

  group('posts with reactions switched off', () {
    test('rank at the pool mean rather than being dropped', () async {
      await channel(-1);
      // Reactions off: 20.8K people saw it, and likes say nothing about it.
      await post(chatId: -1, messageId: 1, views: 20800, likes: 0);
      // Comfortably above the mean.
      await post(chatId: -1, messageId: 2, views: 5000, likes: 500);
      // Comfortably below it.
      await post(chatId: -1, messageId: 3, views: 5000, likes: 50);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      // Slotted between the two measured posts: no evidence either way is exactly
      // average, not worthless.
      expect(await ranked(r), [2, 1, 3]);
    });

    test('are ordered among themselves by views', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 1000, likes: 0);
      await post(chatId: -1, messageId: 2, views: 90000, likes: 0);
      await post(chatId: -1, messageId: 3, views: 9000, likes: 0);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      // More views means more people saw it, which is the only signal left.
      expect(await ranked(r), [2, 3, 1]);
    });

    test('do not drag the pooled prior', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 100000, likes: 0);
      await post(chatId: -1, messageId: 2, views: 1000, likes: 100);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      // Including the 100k-view zero-like post would push m to ~0.001 and distort
      // every other score.
      expect(r.meanRatio, closeTo(0.1, 0.001));
    });
  });

  group('already seen', () {
    test('a post shown once never comes back', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);
      await post(chatId: -1, messageId: 2, views: 5000, likes: 100);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);

      final first = await r.page(nowSeconds: now);
      expect([for (final e in first) e.message.messageId], [1, 2]);

      await r.markSeen(first);
      expect(await r.page(nowSeconds: now), isEmpty);
    });

    test('marking is keyed on the permanent link, not the row', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      await r.markSeen(await r.page(nowSeconds: now));

      final link = await db
          .customSelect('SELECT link FROM seen_posts')
          .map((row) => row.read<String>('link'))
          .getSingle();
      // A t.me URL survives a cache wipe and a re-backfill; a row id does not.
      expect(link, 't.me/c-1/1');
    });

    test('a re-cached post is still remembered', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      await r.markSeen(await r.page(nowSeconds: now));

      // Simulate a wipe and re-backfill: the post row is gone and comes back.
      await db.delete(db.messages).go();
      await post(chatId: -1, messageId: 1, views: 9000, likes: 900);
      await r.recomputeScores(nowSeconds: now);

      expect(await r.page(nowSeconds: now), isEmpty,
          reason: 'the memory outlives the copy of the post it was about');
    });

    test('marking the same post twice keeps the first sighting', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      final page = await r.page(nowSeconds: now);
      await r.markSeen(page);
      await r.markSeen(page);

      expect(await r.countSeen(), 1);
    });

    test('forgetting brings the feed back', () async {
      await channel(-1);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      await r.markSeen(await r.page(nowSeconds: now));
      expect(await r.page(nowSeconds: now), isEmpty);

      await r.forgetSeen();
      expect(await r.page(nowSeconds: now), hasLength(1));
    });

    test('Following is unaffected — only For You hides what you have read',
        () async {
      await channel(-1, following: true);
      await post(chatId: -1, messageId: 1, views: 5000, likes: 500);

      final r = repo();
      await r.recomputeScores(nowSeconds: now);
      await r.markSeen(await r.page(nowSeconds: now));

      final messages = MessageRepository(client: TelegramClient(), db: db);
      final feed = await messages.watchFeedHead().first;
      expect(feed, hasLength(1),
          reason: 'a chronological timeline should not develop holes');
    });
  });
}