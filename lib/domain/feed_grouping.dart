import '../data/message_repository.dart';

/// One card in the feed: either a single post or an album shown as a carousel.
sealed class FeedItem {
  const FeedItem();

  /// Newest post in the item — the feed's sort key and the dedup anchor.
  FeedEntry get lead;

  String get key => '${lead.message.chatId}:${lead.message.messageId}';
}

final class SinglePost extends FeedItem {
  const SinglePost(this.entry);

  final FeedEntry entry;

  @override
  FeedEntry get lead => entry;
}

/// Several posts Telegram published as one album.
final class AlbumPost extends FeedItem {
  const AlbumPost(this.entries);

  /// Newest first, matching the feed's order.
  final List<FeedEntry> entries;

  @override
  FeedEntry get lead => entries.first;

  /// Albums carry the caption on exactly one of their members, so the card has
  /// to look across all of them rather than trusting the lead.
  FeedEntry get captioned =>
      entries.firstWhere((e) => e.message.body.isNotEmpty,
          orElse: () => entries.first);
}

/// Collapses consecutive posts sharing a non-zero `grouped_id` into one
/// [AlbumPost].
///
/// Only *consecutive* runs are merged, and only within the same chat. Album
/// members are published together so they always land adjacent in a
/// `date DESC` ordering; scanning the whole list for matches instead would let a
/// coincidental id collision across distant dates fuse unrelated posts.
///
/// When [mayHaveMore] is true, a trailing run that shares a `grouped_id` is
/// **held back** rather than rendered.
///
/// Without that, an album straddling a page boundary renders as two cards: the
/// members on this page, then the rest when the next page arrives. Buffering the
/// incomplete tail costs one partial album's worth of latency and makes the split
/// invisible. The buffered entries stay in the caller's list, so the pagination
/// cursor is unaffected.
List<FeedItem> groupFeedEntries(
  List<FeedEntry> entries, {
  bool mayHaveMore = false,
}) {
  final usable = mayHaveMore ? _withoutTrailingAlbum(entries) : entries;
  return _group(usable);
}

/// Drops the trailing entries that belong to the same album as the last one.
///
/// Only trims when the run could plausibly continue — a run already longer than
/// any real album, or one that starts the list, is rendered as-is rather than
/// hidden forever.
List<FeedEntry> _withoutTrailingAlbum(List<FeedEntry> entries) {
  if (entries.isEmpty) return entries;

  final groupedId = entries.last.message.groupedId;
  if (groupedId == null) return entries;

  var cut = entries.length;
  while (cut > 0 &&
      entries[cut - 1].message.groupedId == groupedId &&
      entries[cut - 1].message.chatId == entries.last.message.chatId) {
    cut--;
  }

  // Never hide everything: if the whole page is one album, showing a partial
  // carousel beats showing nothing.
  return cut == 0 ? entries : entries.sublist(0, cut);
}

List<FeedItem> _group(List<FeedEntry> entries) {
  final items = <FeedItem>[];
  var index = 0;

  while (index < entries.length) {
    final entry = entries[index];
    final groupedId = entry.message.groupedId;

    if (groupedId == null) {
      items.add(SinglePost(entry));
      index++;
      continue;
    }

    final run = <FeedEntry>[entry];
    var next = index + 1;
    while (next < entries.length &&
        entries[next].message.groupedId == groupedId &&
        entries[next].message.chatId == entry.message.chatId) {
      run.add(entries[next]);
      next++;
    }

    items.add(run.length == 1 ? SinglePost(entry) : AlbumPost(run));
    index = next;
  }

  return items;
}
