import 'package:flutter/material.dart';

import 'ui/app_scope.dart';
import 'ui/auth/auth_gate.dart';
import 'ui/feed/playback_coordinator.dart';

void main() {
  runApp(const FeedgramApp());
}

class FeedgramApp extends StatefulWidget {
  const FeedgramApp({super.key});

  @override
  State<FeedgramApp> createState() => _FeedgramAppState();
}

class _FeedgramAppState extends State<FeedgramApp> {
  /// Created here rather than inside [AppScope] so the navigator observer below
  /// can reach it: the observer has to be given to `MaterialApp`, which sits
  /// above the scope.
  final _playback = PlaybackCoordinator();

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feedgram',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2AABEE),
        brightness: Brightness.dark,
      ),
      // Anything pushed over the feed — Channels, the debug screens, fullscreen
      // media — must stop inline playback. `VisibilityDetector` does not help
      // here: a covered route keeps its geometry, so items still report as
      // visible while nobody can see them.
      navigatorObservers: [_FeedVisibilityObserver(_playback)],
      // AppScope goes in `builder`, not `home`. `builder` inserts above the
      // Navigator; `home` would put it inside, making every pushed route a
      // sibling rather than a descendant — so anything navigated to would fail
      // its AppScope lookup.
      builder: (context, child) =>
          AppScope(playback: _playback, builder: (_) => child!),
      home: const AuthGate(),
    );
  }
}

/// Treats "the feed is the top route" as "the feed is visible".
class _FeedVisibilityObserver extends NavigatorObserver {
  _FeedVisibilityObserver(this._playback);

  final PlaybackCoordinator _playback;

  var _depth = 0;

  void _update() => _playback.feedVisible = _depth <= 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The first route *is* the feed, so it does not count as covering anything.
    if (previousRoute != null) {
      _depth++;
      _update();
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _depth--;
      _update();
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _depth--;
      _update();
    }
    super.didRemove(route, previousRoute);
  }
}
