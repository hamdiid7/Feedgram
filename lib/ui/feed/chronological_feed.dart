import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/message_repository.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../widgets/floating_nav_bar.dart';
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

  /// A big first page so the feed is immediately scrollable, then smaller ones —
  /// the first load is the only one the user waits on.
  static const firstPageSize = 100;
  static const pageSize = 50;

  /// Channel profiles open with a page the same size as a subsequent one: a
  /// single channel's history is shallower and the screen is entered deliberately.
  static const profileFirstPageSize = 50;

  /// How many cards from the end to start fetching. Waiting for the actual bottom
  /// guarantees the user meets a spinner.
  static const prefetchThreshold = 10;

  @override
  State<ChronologicalFeed> createState() => _ChronologicalFeedState();
}

class _ChronologicalFeedState extends State<ChronologicalFeed>
    with AutomaticKeepAliveClientMixin {
  /// Survives being swiped away from, so returning keeps the loaded pages and
  /// the scroll position. See the note on `ForYouFeed` — the cost there is
  /// worse, but neither feed should reload.
  @override
  bool get wantKeepAlive => true;

  StreamSubscription<List<FeedEntry>>? _headSubscription;

  /// Live newest page.
  var _head = <FeedEntry>[];

  /// Pages appended by scrolling, oldest-growing.
  final _older = <FeedEntry>[];

  var _loadingMore = false;
  var _reachedEnd = false;
  var _started = false;

  /// Set when a page fetch fails. A feed that silently stops loading is
  /// indistinguishable from one that has reached the end, so this is surfaced with
  /// a retry instead.
  Object? _pageError;

  int get _headSize =>
      widget.chatId != null
          ? ChronologicalFeed.profileFirstPageSize
          : ChronologicalFeed.firstPageSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final messages = AppScope.messagesOf(context);
    _headSubscription = messages
        .watchFeedHead(
          limit: _headSize,
          chatId: widget.chatId,
          list: widget.list,
        )
        .listen((entries) => setState(() => _head = entries));
  }

  @override
  void dispose() {
    _headSubscription?.cancel();
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

  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd || _pageError != null) return;

    final current = _entries;
    if (current.isEmpty) return;

    setState(() => _loadingMore = true);

    // The cursor is the last *loaded* entry, not the last rendered one — a
    // buffered incomplete album must not be re-fetched.
    final last = current.last.message;
    try {
      final page = await AppScope.messagesOf(context).feedPage(
        after: FeedCursor(date: last.date, messageId: last.messageId),
        limit: ChronologicalFeed.pageSize,
        chatId: widget.chatId,
        list: widget.list,
      );

      if (!mounted) return;
      setState(() {
        _older.addAll(page);
        _loadingMore = false;
        // A short page is genuinely the end here: this reads the local database,
        // not TDLib, so there is no cache-warming caveat.
        if (page.length < ChronologicalFeed.pageSize) _reachedEnd = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _pageError = e;
      });
    }
  }

  void _retryPage() {
    setState(() => _pageError = null);
    _loadMore();
  }

  /// Pull-to-refresh: actually goes to the network for this feed's channels, then
  /// lets the watched head re-query.
  ///
  /// A local re-sort would be pointless — the feed is already live on the database,
  /// so the only thing a refresh can usefully add is *new posts*. Channels are
  /// fetched sequentially with FLOOD_WAIT respected, same as any other backfill.
  Future<void> _refresh() async {
    final messages = AppScope.messagesOf(context);
    final channels = AppScope.channelsOf(context);

    try {
      final ids = widget.chatId != null
          ? [widget.chatId!]
          : await channels.channelIdsIn(widget.list);

      await messages.refreshChannels(ids);

      if (!mounted) return;
      // Older pages are dropped: new posts change what "page 2" means, and keeping
      // stale pages around is how duplicates appear.
      setState(() {
        _older.clear();
        _reachedEnd = false;
        _pageError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _pageError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Required by AutomaticKeepAliveClientMixin.
    super.build(context);

    final entries = _entries;

    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: MediaQuery.paddingOf(context).top,
        // An empty feed still needs to be pullable, so the list must be
        // scrollable even with nothing in it.
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _EmptyFeed(message: widget.emptyMessage),
            ),
          ],
        ),
      );
    }

    // Albums collapse into one carousel card, so item count comes from the grouped
    // list. `mayHaveMore` holds back an album that is still arriving.
    final items = groupFeedEntries(entries, mayHaveMore: !_reachedEnd);

    return RefreshIndicator(
      onRefresh: _refresh,
      // Clear of the floating header, which is what the top inset measures.
      // Left at zero the spinner appears behind the pills.
      edgeOffset: MediaQuery.paddingOf(context).top,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // Top comes from the MediaQuery inset the floating header sets; bottom
        // clears the floating nav bar, so the last card is not stuck behind it.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
          bottom: FloatingNavBar.spaceFor(context),
        ),
        // Virtualized: only visible cards are built, and each renders from
        // precomputed spans.
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index >= items.length) return _footer();

          // Prefetch by item index rather than scroll offset: card heights vary
          // enormously here (a text post versus a photo), so a pixel threshold is
          // a poor proxy for "nearly at the end".
          if (index >= items.length - ChronologicalFeed.prefetchThreshold) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }

          return FeedItemEntrance(
            key: ValueKey(items[index].key),
            index: index,
            child: PostCard(
              item: items[index],
              // Scoped to one channel means you are already on its profile, so
              // the header would push a second copy of this very screen.
              linkChannel: widget.chatId == null,
            ),
          );
        },
      ),
    );
  }

  /// The three end states, told apart explicitly. A silent stop reads as a bug.
  Widget _footer() {
    final theme = Theme.of(context);

    if (_pageError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Could not load more', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '$_pageError',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _retryPage,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_reachedEnd) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Center(
          child: Text(
            "You're all caught up",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
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
