import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/app_database.dart';
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

  /// How much of the header is currently pushed off the top, in pixels.
  ///
  /// Tracks the scroll one-to-one rather than flipping between shown and hidden:
  /// the content pushes the header out of the way as it comes up and drags it
  /// back down as it goes, so it moves with your finger instead of deciding to
  /// vanish. Scroll up two pixels and two pixels of header come back.
  ///
  /// A [ValueNotifier] rather than state, because this changes on every frame of
  /// a scroll. Rebuilding the whole shell — header, page view and both feeds —
  /// sixty times a second to move one widget would cost more than the effect is
  /// worth; only the transform listens.
  final _hidden = ValueNotifier<double>(0);

  /// Measured rather than assumed. It is the feeds' top inset, so a wrong number
  /// shows up as either a gap above the first post or a post hiding under the
  /// pills — and the real height moves with text scale and the status bar.
  final _headerKey = GlobalKey();
  var _headerHeight = 0.0;

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height;
    if (height == null || height == _headerHeight) return;
    setState(() => _headerHeight = height);
  }

  @override
  void dispose() {
    _pages.dispose();
    _hidden.dispose();
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

  /// One listener for two jobs, told apart by depth: the page view is depth 0,
  /// the feeds scrolling inside it are deeper.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) {
      if (notification is ScrollStartNotification) {
        _dragging = notification.dragDetails != null;
      } else if (notification is ScrollEndNotification) {
        // Cleared here too: a drag that ends back on the page it started from
        // never fires onPageChanged, and leaving the flag set would let the
        // next programmatic move be mistaken for a swipe.
        _dragging = false;
      }
      return false;
    }

    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      // Positive delta is content coming up, which pushes the header out.
      _hidden.value = (_hidden.value + delta).clamp(0.0, _headerHeight);
    }

    // Overscrolling past the top always brings the whole header back, whatever
    // the deltas added up to on the way.
    if (notification.metrics.pixels <= 0) _hidden.value = 0;

    return false;
  }

  void _onPageChanged(int index) {
    if (!_dragging) return;
    _dragging = false;
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Measured after layout so the feeds' top inset matches the header exactly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Scaffold(
      body: Stack(
        children: [
          // The feeds run the full height and scroll *under* the header. That is
          // what makes the blur mean anything: with the header sitting in a
          // Column above them there would be nothing behind it to blur.
          Positioned.fill(
            child: MediaQuery(
              // A vertical ListView with no explicit padding adopts the
              // MediaQuery padding, so this is all it takes to inset both feeds
              // and their empty states by exactly the header's height.
              data: MediaQuery.of(context).copyWith(
                padding: MediaQuery.paddingOf(context)
                    .copyWith(top: _headerHeight),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _hidden,
              // The header is passed as `child` so it is built once per state
              // change, not once per scrolled pixel — only the translation is
              // rebuilt as it moves.
              builder: (context, hidden, child) => Transform.translate(
                offset: Offset(0, -hidden),
                child: child,
              ),
              child: _Header(
                key: _headerKey,
                selected: feedOrder[_tabIndex],
                onSelected: _select,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating title bar and feed pills.
///
/// Frosted rather than solid: the feed passing underneath stays legible as
/// motion and colour without competing with the controls on top of it.
class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ChannelList selected;
  final ValueChanged<ChannelList> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          // Translucent white, not opaque: the blur alone would still read as a
          // frosted pane, but without a wash behind it dark photos scrolling
          // under make the title unreadable.
          color: theme.colorScheme.surface.withValues(alpha: 0.72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Feedgram'),
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
                // Nothing on the right. Backfill, the images toggle, channels
                // and the debug screens live in Settings, and Settings is the
                // Profile tab in the bar below — a second way in from up here
                // was one too many.
              ),
              FeedSelector(selected: selected, onSelected: onSelected),
            ],
          ),
        ),
      ),
    );
  }
}

