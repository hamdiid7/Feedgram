import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/data/message_repository.dart';
import 'package:feedgram/domain/feed_grouping.dart';

FeedEntry entry({
  required int messageId,
  int chatId = -100,
  int? groupedId,
  int date = 1000,
  String body = '',
}) {
  return FeedEntry(
    message: Message(
      chatId: chatId,
      messageId: messageId,
      date: date,
      groupedId: groupedId,
      body: body,
      viewCount: 0,
      reactionCount: 0,
      forwardCount: 0,
      replyCount: 0,
      contentKind: ContentKind.photo,
      viaBot: false,
    ),
    channel: const Channel(
      id: -100,
      title: 'Test',
      subscriberCount: 10,
      source: ChannelSource.subscribed,
    ),
  );
}

void main() {
  group('groupFeedEntries', () {
    test('leaves posts without a grouped_id alone', () {
      final items = groupFeedEntries([
        entry(messageId: 3),
        entry(messageId: 2),
        entry(messageId: 1),
      ]);
      expect(items, hasLength(3));
      expect(items.every((i) => i is SinglePost), isTrue);
    });

    test('collapses a consecutive run into one album', () {
      final items = groupFeedEntries([
        entry(messageId: 5, groupedId: 99),
        entry(messageId: 4, groupedId: 99),
        entry(messageId: 3, groupedId: 99),
        entry(messageId: 2),
      ]);
      expect(items, hasLength(2));
      expect(items.first, isA<AlbumPost>());
      expect((items.first as AlbumPost).entries, hasLength(3));
      expect(items.last, isA<SinglePost>());
    });

    test('a lone grouped post stays a single card', () {
      final items = groupFeedEntries([entry(messageId: 1, groupedId: 42)]);
      expect(items.single, isA<SinglePost>());
    });

    // Two albums can share an id across different channels; fusing them would
    // splice unrelated posts into one carousel.
    test('does not merge across channels', () {
      final items = groupFeedEntries([
        entry(messageId: 2, chatId: -1, groupedId: 7),
        entry(messageId: 1, chatId: -2, groupedId: 7),
      ]);
      expect(items, hasLength(2));
    });

    // Only consecutive runs merge, so a coincidental id reuse separated by other
    // posts cannot fuse.
    test('does not merge non-consecutive runs', () {
      final items = groupFeedEntries([
        entry(messageId: 4, groupedId: 7),
        entry(messageId: 3),
        entry(messageId: 2, groupedId: 7),
      ]);
      expect(items, hasLength(3));
      expect(items.every((i) => i is SinglePost), isTrue);
    });

    test('finds the caption wherever in the album it lives', () {
      final items = groupFeedEntries([
        entry(messageId: 3, groupedId: 8),
        entry(messageId: 2, groupedId: 8, body: 'the caption'),
        entry(messageId: 1, groupedId: 8),
      ]);
      final album = items.single as AlbumPost;
      expect(album.captioned.message.body, 'the caption');
      // The lead stays the newest post — that is the feed's sort anchor.
      expect(album.lead.message.messageId, 3);
    });

    test('preserves every entry exactly once', () {
      final input = [
        entry(messageId: 6, groupedId: 1),
        entry(messageId: 5, groupedId: 1),
        entry(messageId: 4),
        entry(messageId: 3, groupedId: 2),
        entry(messageId: 2, groupedId: 2),
        entry(messageId: 1),
      ];
      final flattened = <int>[];
      for (final item in groupFeedEntries(input)) {
        switch (item) {
          case SinglePost(:final entry):
            flattened.add(entry.message.messageId);
          case AlbumPost(:final entries):
            flattened.addAll(entries.map((e) => e.message.messageId));
        }
      }
      expect(flattened, [6, 5, 4, 3, 2, 1]);
    });

    test('handles an empty feed', () {
      expect(groupFeedEntries([]), isEmpty);
    });
  });

  group('page boundaries', () {
    test('an album still arriving is held back, not shown in halves', () {
      // Page ends mid-album: three of five members are here.
      final entries = [
        entry(messageId: 1),
        entry(messageId: 2, groupedId: 77),
        entry(messageId: 3, groupedId: 77),
        entry(messageId: 4, groupedId: 77),
      ];

      final items = groupFeedEntries(entries, mayHaveMore: true);

      // Rendering it now would produce a 3-photo carousel followed later by a
      // second card with the remaining two — the album-splitting bug.
      expect(items, hasLength(1));
      expect(items.single, isA<SinglePost>());
      expect(items.single.lead.message.messageId, 1);
    });

    test('the same album renders in full once the page is complete', () {
      final entries = [
        entry(messageId: 1),
        entry(messageId: 2, groupedId: 77),
        entry(messageId: 3, groupedId: 77),
        entry(messageId: 4, groupedId: 77),
      ];

      final items = groupFeedEntries(entries, mayHaveMore: false);

      expect(items, hasLength(2));
      expect(items.last, isA<AlbumPost>());
      expect((items.last as AlbumPost).entries, hasLength(3));
    });

    test('the next page completes the album rather than starting a new card', () {
      // What the feed actually holds after appending page 2.
      final combined = [
        entry(messageId: 1),
        entry(messageId: 2, groupedId: 77),
        entry(messageId: 3, groupedId: 77),
        entry(messageId: 4, groupedId: 77),
        entry(messageId: 5, groupedId: 77),
        entry(messageId: 6, groupedId: 77),
        entry(messageId: 7),
      ];

      final items = groupFeedEntries(combined, mayHaveMore: true);

      // One album of five, not two cards of three and two.
      final albums = items.whereType<AlbumPost>().toList();
      expect(albums, hasLength(1));
      expect(albums.single.entries, hasLength(5));
    });

    test('a trailing single post is never held back', () {
      final entries = [entry(messageId: 1), entry(messageId: 2)];
      expect(groupFeedEntries(entries, mayHaveMore: true), hasLength(2));
    });

    test('a page that is entirely one album still renders', () {
      // Holding everything back would show an empty feed forever.
      final entries = [
        entry(messageId: 1, groupedId: 5),
        entry(messageId: 2, groupedId: 5),
      ];
      final items = groupFeedEntries(entries, mayHaveMore: true);
      expect(items, hasLength(1));
      expect(items.single, isA<AlbumPost>());
    });

    test('an album from a different chat does not absorb the tail', () {
      final entries = [
        entry(messageId: 1, chatId: -1, groupedId: 9),
        entry(messageId: 2, chatId: -2, groupedId: 9),
      ];
      // Same grouped_id, different channels — coincidence, not one album.
      final items = groupFeedEntries(entries, mayHaveMore: true);
      expect(items, hasLength(1), reason: 'only the last chat run is buffered');
      expect(items.single.lead.message.chatId, -1);
    });
  });
}