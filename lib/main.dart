import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'data/settings_store.dart';
import 'ui/app_scope.dart';
import 'ui/auth/auth_gate.dart';
import 'ui/feed/playback_coordinator.dart';
import 'ui/theme.dart';

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

  /// Also above the scope, for the same reason: `themeMode` is a `MaterialApp`
  /// argument, and the scope is built in its `builder`. A store created down
  /// there could never reach the widget that has to act on it.
  SettingsStore? _settings;

  @override
  void initState() {
    super.initState();
    // Opened before the first real frame so the app starts in the saved theme
    // rather than starting in one and visibly correcting itself.
    SettingsStore.open().then((store) {
      if (mounted) setState(() => _settings = store);
    });
  }

  @override
  void dispose() {
    _playback.dispose();
    _settings?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      // One frame at most, on the platform brightness. Deliberately not the
      // seeded light theme: guessing light and then switching to dark is the
      // flash this ordering exists to avoid.
      return const MaterialApp(
        home: ColoredBox(color: Color(0xFF000000), child: SizedBox.expand()),
      );
    }

    // Wallpaper-derived palette on Android 12+, seeded fallback everywhere else.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => AnimatedBuilder(
        // Rebuilds MaterialApp when the theme choice changes.
        animation: settings,
        builder: (context, _) => MaterialApp(
      title: 'Feedgram',
      theme: buildTheme(
        dynamicScheme: lightDynamic,
        brightness: Brightness.light,
      ),
      darkTheme: buildTheme(
        dynamicScheme: darkDynamic,
        brightness: Brightness.dark,
      ),
      // The saved choice, defaulting to the system setting.
      themeMode: settings.themeMode,
      // Anything pushed over the feed — Channels, the debug screens, fullscreen
      // media — must stop inline playback. `VisibilityDetector` does not help
      // here: a covered route keeps its geometry, so items still report as
      // visible while nobody can see them.
      navigatorObservers: [_FeedVisibilityObserver(_playback)],
      // AppScope goes in `builder`, not `home`. `builder` inserts above the
      // Navigator; `home` would put it inside, making every pushed route a
      // sibling rather than a descendant — so anything navigated to would fail
      // its AppScope lookup.
      builder: (context, child) => AppScope(
        playback: _playback,
        settings: settings,
        builder: (_) => child!,
      ),
      home: const AuthGate(),
        ),
      ),
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
