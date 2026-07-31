import 'package:flutter/foundation.dart';

/// Decides which feed items may hold a video player.
///
/// This exists because of a hard Android limit, not for tidiness: a device has a
/// small, fixed number of hardware video decoders — often 2 to 4 in total, shared
/// across the whole system. Exceeding it does not degrade gracefully; it throws
/// decoder-initialisation errors and can leave the codec in a state that needs an
/// app restart. So the number of live players is capped and centrally granted
/// rather than left to individual widgets.
///
/// The rules, in order:
///
/// 1. Nothing plays while the app is backgrounded, the feed tab is not visible,
///    or fullscreen playback is open — the fullscreen player takes the budget.
/// 2. Only items at least [minVisibleFraction] on screen are eligible.
/// 3. The most-visible eligible items win, up to [maxPlayers].
///
/// Ties are broken by registration order so the result is stable, which matters:
/// a coordinator that flip-flops between two equally-visible videos would create
/// and destroy decoders on every scroll frame.
class PlaybackCoordinator extends ChangeNotifier {
  PlaybackCoordinator({
    this.maxPlayers = 2,
    this.minVisibleFraction = 0.5,
  });

  /// Never more than this many players alive at once, fullscreen included.
  final int maxPlayers;

  /// A post must be at least this visible before it autoplays. Half the card is
  /// the point where playback reads as intentional rather than incidental.
  final double minVisibleFraction;

  final _visibility = <String, double>{};
  final _order = <String>[];

  var _appForeground = true;
  var _feedVisible = true;
  var _fullscreen = false;
  var _autoplayEnabled = true;

  Set<String> _granted = const {};

  /// Keys currently allowed to hold a player.
  Set<String> get granted => _granted;

  bool isGranted(String key) => _granted.contains(key);

  /// Reports how much of an item is on screen. `0` removes it.
  void report(String key, double fraction) {
    if (fraction <= 0) {
      if (_visibility.remove(key) != null) {
        _order.remove(key);
        _recompute();
      }
      return;
    }

    final previous = _visibility[key];
    if (previous == null) _order.add(key);
    // Ignore sub-pixel jitter: recomputing on every frame of a scroll would churn
    // decoders for no visible benefit.
    if (previous != null && (previous - fraction).abs() < 0.05) return;

    _visibility[key] = fraction;
    _recompute();
  }

  void forget(String key) => report(key, 0);

  set appForeground(bool value) {
    if (_appForeground == value) return;
    _appForeground = value;
    _recompute();
  }

  set feedVisible(bool value) {
    if (_feedVisible == value) return;
    _feedVisible = value;
    _recompute();
  }

  /// Fullscreen playback owns the whole budget while it is open.
  set fullscreen(bool value) {
    if (_fullscreen == value) return;
    _fullscreen = value;
    _recompute();
  }

  /// Mirrors the cheap-mode image toggle: turning auto-load off must stop video
  /// autoplay too, or the setting would still burn data.
  set autoplayEnabled(bool value) {
    if (_autoplayEnabled == value) return;
    _autoplayEnabled = value;
    _recompute();
  }

  bool get isPlaybackAllowed =>
      _appForeground && _feedVisible && !_fullscreen && _autoplayEnabled;

  void _recompute() {
    final next = <String>{};

    if (isPlaybackAllowed) {
      final eligible = _order
          .where((key) => (_visibility[key] ?? 0) >= minVisibleFraction)
          .toList()
        // Descending visibility, stable within equal values because `_order` is
        // the tiebreaker and List.sort is not stable — so compare keys' positions
        // explicitly.
        ..sort((a, b) {
          final byVisibility =
              (_visibility[b] ?? 0).compareTo(_visibility[a] ?? 0);
          if (byVisibility != 0) return byVisibility;
          return _order.indexOf(a).compareTo(_order.indexOf(b));
        });

      next.addAll(eligible.take(maxPlayers));
    }

    if (setEquals(next, _granted)) return;
    _granted = next;
    notifyListeners();
  }

  @visibleForTesting
  double? visibilityOf(String key) => _visibility[key];
}
