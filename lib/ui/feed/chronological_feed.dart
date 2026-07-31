import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/message_repository.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import 'post_card.dart';

/// The Following feed: every tracked channel merged, strict reverse-chronological.
///
/// Two sources feed one list:
/// * the newest page is **watched**, so posts arriving over `updateNewMessage`
///   appear without polling;
/// * older pages are appended by **keyset pagination** on `(date, message_id)`.
///
/// `OFFSET` is deliberately not used — it rescans from the top for every page and
/// shifts under you as new posts land, which duplicates and skips rows.
class ChronologicalFeed extends StatefulWidget {
  const ChronologicalFeed({
    super.key,
    this.list = ChannelList.following,
    this.chatId,
    this.emptyMessage,
  });

  /// Which membership list scopes the feed. Ignored when [chatId] is set.
  final ChannelList list;

  /// When set, the feed shows only this channel.
  final int? chatId;

  final String? emptyMessage;

  @override
  State<ChronologicalFeed> createState() => _ChronologicalFeedState();
}

class _ChronologicalFeedState extends State<ChronologicalFeed> {
  static const _pageSize = 30;

  final _scrollController = ScrollController();

  StreamSubscription<List<FeedEntry>>? _headSubscription;

  /// Live newest page.
  var _head = <FeedEntry>[];

  /// Pages appended by scrolling, oldest-growing.
  final _older = <FeedEntry>[];

  var _loadingMore = false;
  var _reachedEnd = false;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final messages = AppScope.messagesOf(context);
    _headSubscription = messages
        .watchFeedHead(
          limit: _pageSize,
          chatId: widget.chatId,
          list: widget.list,
        )
        .listen((entries) => setState(() => _head = entries));

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _headSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// The visible list: the live head plus appended pages, de-duplicated.
  ///
  /// Overlap is expected — a post can sit in the head page and in an older page
  /// fetched before it arrived — so identity wins over position.
  List<FeedEntry> get _entries {
    final seen = <String>{};
    final combined = <FeedEntry>[];
    for (final entry in [..._head, ..._older]) {
      final key = '${entry.message.chatId}:${entry.message.messageId}';
      if (seen.add(key)) combined.add(entry);
    }
    return combined;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd) return;

    final current = _entries;
    if (current.isEmpty) return;

    setState(() => _loadingMore = true);

    final last = current.last.message;
    final page = await AppScope.messagesOf(context).feedPage(
      after: FeedCursor(date: last.date, messageId: last.messageId),
      limit: _pageSize,
      chatId: widget.chatId,
      list: widget.list,
    );

    if (!mounted) return;
    setState(() {
      _older.addAll(page);
      _loadingMore = false;
      // A short page is genuinely the end here: this reads the local database,
      // not TDLib, so there is no cache-warming caveat.
      if (page.length < _pageSize) _reachedEnd = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    if (entries.isEmpty) {
      return _EmptyFeed(message: widget.emptyMessage);
    }

    // Albums collapse into one carousel card, so item count is computed after
    // grouping rather than from the raw row count.
    final items = groupFeedEntries(entries);

    return ListView.builder(
      controller: _scrollController,
      // Virtualized: only visible cards are built, and each one renders from
      // precomputed spans.
      itemCount: items.length + (_reachedEnd ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return PostCard(key: ValueKey(items[index].key), item: items[index]);
      },
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message ??
              'Nothing here yet.\n\nSync your channels, then run a backfill to '
                  'pull their recent posts.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
