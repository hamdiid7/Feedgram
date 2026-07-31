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
}
