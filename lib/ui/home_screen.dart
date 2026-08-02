import 'package:flutter/material.dart';

import '../data/app_database.dart';
import 'app_scope.dart';
import 'channels/channels_screen.dart';
import 'debug/td_debug_screen.dart';
import 'feed/chronological_feed.dart';
import 'feed/feed_selector.dart';
import 'feed/for_you_feed.dart';
import 'motion.dart';

/// The app shell. Phase 5's deliverable: a merged, scrolling, newest-first
/// timeline over every tracked channel.
///
/// "For You" arrives in Phase 7; its tab is present but empty so the structure
/// is visible.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Which feed is showing. Starts at 0, which [feedOrder] makes For You.
  ///
  /// This field is the source of truth; the page view follows it, rather than
  /// the current feed being read back out of a scroll offset the way
  /// `TabBarView` does it. Same visible behaviour, one less thing that can
  /// disagree with itself.
  var _tabIndex = 0;

  final _pages = PageController();

  /// Whether the page view is moving because a finger is dragging it.
  ///
  /// Only a drag may change the feed. A programmatic `animateToPage` has already
  /// set [_tabIndex] before it starts, so honouring its page change too would be
  /// redundant, and anything else that moves the offset — a layout correction,
  /// say — has no business switching feeds at all.
  var _dragging = false;

  var _backfilling = false;
  String? _progress;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(ChannelList list) {
    final index = feedOrder.indexOf(list);
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
    _pages.animateToPage(
      index,
      duration: Motion.container,
      curve: Motion.standard,
    );
  }

  bool _watchForDrag(ScrollNotification notification) {
    // depth 0 only: the feeds' own vertical lists sit inside this one and their
    // notifications bubble through here too.
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _dragging = notification.dragDetails != null;
    } else if (notification is ScrollEndNotification) {
      // Cleared here too: a drag that ends back on the page it started from
      // never fires onPageChanged, and leaving the flag set would let the next
      // programmatic move be mistaken for a swipe.
      _dragging = false;
    }
    return false;
  }

  void _onPageChanged(int index) {
    if (!_dragging) return;
    _dragging = false;
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
  }

  Future<void> _backfill() async {
    setState(() {
      _backfilling = true;
      _progress = 'Starting…';
    });

    try {
      final total = await AppScope.messagesOf(context).backfillAll(
        perChannel: 40,
        onProgress: (done, all) {
          if (mounted) setState(() => _progress = 'Channel $done of $all');
        },
      );
      if (mounted) setState(() => _progress = 'Pulled $total posts.');
    } catch (e) {
      if (mounted) setState(() => _progress = 'Backfill failed: $e');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedgram'),
        actions: [
          IconButton(
            icon: _backfilling
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Backfill posts',
            onPressed: _backfilling ? null : _backfill,
          ),
          IconButton(
            icon: Icon(
              AppScope.autoLoadImagesOf(context)
                  ? Icons.image_outlined
                  : Icons.image_not_supported_outlined,
            ),
            tooltip: AppScope.autoLoadImagesOf(context)
                ? 'Auto-load images: on'
                : 'Auto-load images: off (tap to load)',
            onPressed: () => AppScope.setAutoLoadImages(
              context,
              !AppScope.autoLoadImagesOf(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.rss_feed),
            tooltip: 'Channels',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ChannelsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'TDLib debug',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TdDebugScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          FeedSelector(selected: feedOrder[_tabIndex], onSelected: _select),
          // Grows in place: backfill emits a new line every second or two, and
          // a bare insert here would shove the whole feed down each time.
          AnimatedExpanded(
            expand: _progress != null,
            child: Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: AnimatedSizeSwitcher(
                child: Text(
                  _progress ?? '',
                  key: ValueKey(_progress),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _watchForDrag,
              child: PageView(
                controller: _pages,
                onPageChanged: _onPageChanged,
                // Order must match [feedOrder] — the pills and these children
                // are addressed by the same index.
                children: [
                  for (final list in feedOrder)
                    switch (list) {
                      ChannelList.forYou => const ForYouFeed(),
                      ChannelList.following => const ChronologicalFeed(),
                    },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
