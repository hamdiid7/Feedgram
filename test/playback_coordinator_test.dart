import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/ui/feed/playback_coordinator.dart';

/// The decoder cap is a hard Android limit, not a preference: exceeding the
/// device's small pool of hardware video decoders throws initialisation errors
/// rather than degrading. These tests pin the rules that keep it bounded.
void main() {
  group('grants', () {
    test('nothing plays below the visibility threshold', () {
      final c = PlaybackCoordinator();
      addTearDown(c.dispose);

      c.report('a', 0.4);
      expect(c.granted, isEmpty, reason: 'half the card is the bar');

      c.report('a', 0.6);
      expect(c.granted, {'a'});
    });

    test('never grants more than maxPlayers', () {
      final c = PlaybackCoordinator(maxPlayers: 2);
      addTearDown(c.dispose);

      c.report('a', 0.9);
      c.report('b', 0.8);
      c.report('c', 0.7);
      c.report('d', 1.0);

      expect(c.granted, hasLength(2));
      // The two most visible win.
      expect(c.granted, {'d', 'a'});
    });

    test('the most visible item takes the slot as scrolling changes', () {
      final c = PlaybackCoordinator(maxPlayers: 1);
      addTearDown(c.dispose);

      c.report('a', 0.9);
      c.report('b', 0.6);
      expect(c.granted, {'a'});

      // 'a' scrolls off, 'b' fills the screen.
      c.report('a', 0.2);
      c.report('b', 1.0);
      expect(c.granted, {'b'});
    });

    test('an item scrolled fully off is forgotten', () {
      final c = PlaybackCoordinator(maxPlayers: 1);
      addTearDown(c.dispose);

      c.report('a', 0.9);
      expect(c.granted, {'a'});

      c.report('a', 0);
      expect(c.granted, isEmpty);
      expect(c.visibilityOf('a'), isNull, reason: 'no stale bookkeeping');
    });

    test('sub-pixel jitter does not churn grants', () {
      final c = PlaybackCoordinator(maxPlayers: 1);
      addTearDown(c.dispose);

      var notifications = 0;
      c.addListener(() => notifications++);

      c.report('a', 0.90);
      final afterFirst = notifications;

      // A scroll frame nudging visibility by a hair must not tear down and
      // rebuild a decoder.
      c.report('a', 0.91);
      c.report('a', 0.92);
      c.report('a', 0.93);

      expect(notifications, afterFirst);
      expect(c.granted, {'a'});
    });

    test('ties resolve stably rather than flip-flopping', () {
      final c = PlaybackCoordinator(maxPlayers: 1);
      addTearDown(c.dispose);

      c.report('a', 0.8);
      c.report('b', 0.8);
      final first = c.granted;

      // Re-reporting identical values must not hand the slot back and forth,
      // which would create and destroy a decoder on every frame.
      c.report('a', 0.8);
      c.report('b', 0.8);
      expect(c.granted, first);
    });
  });

  group('playback is suspended when it should be', () {
    test('backgrounding the app stops everything', () {
      final c = PlaybackCoordinator();
      addTearDown(c.dispose);

      c.report('a', 1.0);
      expect(c.granted, {'a'});

      c.appForeground = false;
      expect(c.granted, isEmpty);
      expect(c.isPlaybackAllowed, isFalse);

      c.appForeground = true;
      expect(c.granted, {'a'}, reason: 'and resumes on return');
    });

    test('a covered route stops everything', () {
      final c = PlaybackCoordinator();
      addTearDown(c.dispose);

      c.report('a', 1.0);
      c.feedVisible = false;
      expect(c.granted, isEmpty);
    });

    test('fullscreen takes the whole budget', () {
      final c = PlaybackCoordinator(maxPlayers: 2);
      addTearDown(c.dispose);

      c.report('a', 1.0);
      c.report('b', 0.9);
      expect(c.granted, hasLength(2));

      // Inline decoders must be released so the fullscreen player can have one.
      c.fullscreen = true;
      expect(c.granted, isEmpty);

      c.fullscreen = false;
      expect(c.granted, hasLength(2));
    });

    test('cheap mode disables video autoplay too', () {
      final c = PlaybackCoordinator();
      addTearDown(c.dispose);

      c.report('a', 1.0);
      expect(c.granted, {'a'});

      // Otherwise the image toggle would still let video burn data.
      c.autoplayEnabled = false;
      expect(c.granted, isEmpty);

      c.autoplayEnabled = true;
      expect(c.granted, {'a'});
    });

    test('visibility keeps updating while suspended', () {
      final c = PlaybackCoordinator(maxPlayers: 1);
      addTearDown(c.dispose);

      c.appForeground = false;
      c.report('a', 0.3);
      c.report('b', 0.95);
      expect(c.granted, isEmpty);

      // On resume the right item plays — not whatever was visible when we paused.
      c.appForeground = true;
      expect(c.granted, {'b'});
    });
  });
}
