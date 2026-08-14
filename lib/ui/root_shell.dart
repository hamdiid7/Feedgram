import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'chats/chats_screen.dart';
import 'home_screen.dart';
import 'settings/settings_screen.dart';
import 'shorts/shorts_screen.dart';
import 'widgets/floating_nav_bar.dart';

/// The four top-level destinations, behind a floating bottom bar.
///
/// An [IndexedStack], not a `PageView`: these are destinations rather than a
/// sequence, and swiping sideways between a feed and a video player would fight
/// the horizontal swipe the feed already uses to move between For You and
/// Following. The stack also keeps all four mounted, so a half-scrolled feed and
/// a half-watched clip are still there when you come back.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  var _index = 0;

  /// How much of the nav bar is pushed off the bottom, in pixels.
  ///
  /// Mirrors the feed header: content coming up pushes the bar down by the same
  /// amount, so both edges of the screen give way to what you are reading and
  /// come back the moment you scroll up.
  ///
  /// A [ValueNotifier] because this changes every frame of a scroll — rebuilding
  /// the shell, and with it all four tabs, sixty times a second to move one bar
  /// would cost far more than the effect is worth.
  final _navHidden = ValueNotifier<double>(0);

  /// Measured, not assumed: the bar's height depends on text scale and the
  /// gesture inset, and a wrong number leaves it either peeking or overshooting.
  final _navKey = GlobalKey();
  var _navHeight = 0.0;

  /// True while a horizontal page view is moving — the feeds swipe sideways, and
  /// the incoming feed announcing itself is not the reader scrolling.
  var _pageMoving = false;

  var _syncStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_syncStarted) return;
    _syncStarted = true;

    // Deliberately not awaited. The feeds render from the local database
    // immediately; this fills in what is new behind them, and the watched head
    // pushes anything it finds into the list without a reload.
    _syncOnLaunch();
  }

  /// Discovery first, then posts.
  ///
  /// A feed only shows channels that are in a membership list, and the only thing
  /// that ever put them there was tapping Sync on the Channels screen. So a fresh
  /// login had nothing tracked, `syncOnLaunch` had no channels to refresh, and the
  /// app opened empty — which is why finding new content meant a trip to Channels
  /// every time.
  ///
  /// Both halves are sequential and sleep out FLOOD_WAIT in full, so this adds
  /// startup work but no new risk of being rate limited.
  Future<void> _syncOnLaunch() async {
    final channels = AppScope.channelsOf(context);
    final messages = AppScope.messagesOf(context);

    try {
      // Enumerates the account's subscribed channels and files them under
      // Following. Mostly answered from TDLib's local chat cache.
      final found = await channels.syncSubscribedChannels();
      debugPrint('launch sync: $found channels');
    } catch (e, stack) {
      // Discovery failing must not stop the refresh of whatever is already
      // tracked — that is the part with content behind it. But it must not fail
      // *quietly* either: a bare `catch (_)` here turned a throwing sync into an
      // app that simply showed fewer channels than the account has, with nothing
      // anywhere to say why.
      debugPrint('launch sync: discovery failed: $e\n$stack');
    }

    try {
      await messages.syncOnLaunch();
    } catch (e, stack) {
      // The feeds still have whatever was cached; pull-to-refresh retries.
      debugPrint('launch sync: refresh failed: $e\n$stack');
    }
  }

  @override
  void dispose() {
    _navHidden.dispose();
    super.dispose();
  }

  void _measureNav() {
    final box = _navKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height;
    if (height == null || height == _navHeight) return;
    setState(() => _navHeight = height);
  }

  /// Only the Feed pushes the bar away.
  ///
  /// Elsewhere it stays put: Messages and Profile are lists you navigate rather
  /// than read continuously, and Shorts is a full-screen pager whose every swipe
  /// is a full viewport of scroll delta — the bar would vanish on the first flick
  /// and never come back until you scrolled the other way.
  static const _hideOnTab = 0;

  bool _onScroll(ScrollNotification notification) {
    if (_index != _hideOnTab) return false;

    if (notification.metrics.axis == Axis.horizontal) {
      if (notification is ScrollStartNotification) {
        _pageMoving = true;
      } else if (notification is ScrollEndNotification) {
        _pageMoving = false;
      }
      return false;
    }

    // A fresh vertical drag means the reader is scrolling, whatever the page
    // view was doing. Clearing here rather than trusting the horizontal
    // ScrollEnd: a page settle is a second start/end pair after the drag, and if
    // either end notification goes missing the flag sticks true and the bar
    // stops responding to scrolling entirely.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pageMoving = false;
    }

    if (_pageMoving) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _navHidden.value = (_navHidden.value + delta).clamp(0.0, _navHeight);
    }

    // Settled back at the top: the bar comes back however you got there.
    if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 0) {
      _navHidden.value = 0;
    }

    return false;
  }

  static const _destinations = [
    NavDestination(
      label: 'Feed',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
    ),
    NavDestination(
      label: 'Messages',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
    ),
    NavDestination(
      label: 'Shorts',
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
    ),
    NavDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureNav());

    return Scaffold(
      // The bar floats over the content, so the body has to run the full height
      // behind it. Each screen adds `FloatingNavBar.spaceFor` to its own bottom
      // padding rather than being inset here, or the frosted feed header would
      // lose the content it blurs.
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            ChatsScreen(),
            ShortsScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<double>(
        valueListenable: _navHidden,
        // The bar is the builder's `child`, so it is built once per state change
        // rather than once per scrolled pixel.
        builder: (context, hidden, child) => Transform.translate(
          offset: Offset(0, hidden),
          child: child,
        ),
        child: FloatingNavBar(
          key: _navKey,
          destinations: _destinations,
          currentIndex: _index,
          onSelected: (index) {
            if (index == _index) return;
            // Always fully visible on arrival — both because reaching for the bar
            // means you want it, and because the other three tabs never move it,
            // so a half-hidden bar carried over from the Feed would be stuck
            // that way.
            _navHidden.value = 0;
            setState(() => _index = index);
          },
        ),
      ),
    );
  }
}
