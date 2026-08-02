import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/for_you_repository.dart';
import '../../data/message_repository.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import '../motion.dart';
import 'chronological_feed.dart';
import 'post_card.dart';

/// For You: the `for_you` channel pool, ranked by smoothed engagement.
///
/// Ordered by the **stored** `score` column, so paging uses a `(score, message_id)`
/// keyset. That is the whole reason the score is persisted rather than computed per
/// query — a value that changed between pages would shift under the cursor.
class ForYouFeed extends StatefulWidget {
  const ForYouFeed({super.key});

  @override
  State<ForYouFeed> createState() => _ForYouFeedState();
}

class _ForYouFeedState extends State<ForYouFeed>
    with AutomaticKeepAliveClientMixin {
  /// Survives being swiped away from.
  ///
  /// The home shell pages between feeds, and a `PageView` disposes whichever
  /// child is off-screen. Without this, coming back rebuilds the State, re-runs
  /// [_load] and lands the reader at the top. That is worse here than in a plain
  /// list: the ranking is recomputed and seen posts are dropped, so the feed
  /// comes back genuinely *different*, not merely scrolled to the top.
  @override
  bool get wantKeepAlive => true;

  final _entries = <FeedEntry>[];

  ScoreCursor? _cursor;
  var _loading = true;
  var _loadingMore = false;
  var _reachedEnd = false;
  var _started = false;
  Object? _error;

  /// Held so dispose can flush without a BuildContext.
  ForYouRepository? _forYou;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final forYou = AppScope.forYouOf(context);
    _forYou = forYou;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Scores go stale as the window slides, so a pass runs before the first
      // read rather than trusting whatever the last backfill left behind.
      await forYou.recomputeScores();
      final page =
          await forYou.page(limit: ChronologicalFeed.firstPageSize);

      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page);
        _cursor = ForYouRepository.cursorFrom(page);
        _reachedEnd = page.length < ChronologicalFeed.firstPageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd || _cursor == null || _error != null) return;
    setState(() => _loadingMore = true);

    try {
      final page = await AppScope.forYouOf(context).page(
        after: _cursor,
        limit: ChronologicalFeed.pageSize,
      );

      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _cursor = ForYouRepository.cursorFrom(page) ?? _cursor;
        _reachedEnd = page.length < ChronologicalFeed.pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = e;
      });
    }
  }

  /// Pull-to-refresh fetches new posts for the pool, rescores, and restarts from
  /// the top — a ranked feed has no meaningful "insert at the head".
  Future<void> _refresh() async {
    final channels = AppScope.channelsOf(context);
    final messages = AppScope.messagesOf(context);

    try {
      final ids = await channels.channelIdsIn(ChannelList.forYou);
      await messages.refreshChannels(ids);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    await _load();
  }

  @override
  void dispose() {
    // Flush the tail, or the last few cards of a session would come back.
    if (_pendingSeen.isNotEmpty) {
      _forYou?.markSeen(List<FeedEntry>.of(_pendingSeen));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Required by AutomaticKeepAliveClientMixin.
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _Empty(error: _error),
            ),
          ],
        ),
      );
    }

    final items = groupFeedEntries(_entries, mayHaveMore: !_reachedEnd);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index >= items.length) return _footer();

          if (index >= items.length - ChronologicalFeed.prefetchThreshold) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }

          final item = items[index];
          // Recorded on build rather than on a visibility threshold: the exclusion
          // applies when the *next* page is queried, so nothing vanishes under the
          // reader's finger mid-scroll.
          _markSeen(item.lead);
          return FeedItemEntrance(
            key: ValueKey(item.key),
            index: index,
            child: PostCard(item: item, reason: _reasonFor(item.lead)),
          );
        },
      ),
    );
  }

  final _pendingSeen = <FeedEntry>[];

  /// Batched so a fast scroll does not issue one insert per card.
  void _markSeen(FeedEntry entry) {
    _pendingSeen.add(entry);
    if (_pendingSeen.length < 8) return;
    final batch = List<FeedEntry>.of(_pendingSeen);
    _pendingSeen.clear();
    _forYou?.markSeen(batch);
  }

  /// Explains the ranking on the card. A recommendation feed that cannot say why
  /// it chose something is impossible to tune, and this phase's checkpoint is
  /// precisely a judgement about its choices.
  String? _reasonFor(FeedEntry entry) {
    final views = entry.message.viewCount;
    final likes = entry.message.reactionCount;
    if (views <= 0) return null;
    final rate = likes / views * 100;
    return '${rate.toStringAsFixed(rate >= 1 ? 1 : 2)}% liked '
        '· ${_compact(likes)} of ${_compact(views)}';
  }

  Widget _footer() {
    final theme = Theme.of(context);

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Could not load more', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _error = null);
                _loadMore();
              },
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
            'You have seen everything ranked here',
            textAlign: TextAlign.center,
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

String _compact(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}

class _Empty extends StatelessWidget {
  const _Empty({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              error != null ? 'Could not rank posts' : 'Nothing ranks yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error != null
                  ? '$error'
                  : 'Add channels to For You on the Channels screen, then pull to refresh.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
