import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/ui/motion.dart';
import 'package:feedgram/ui/theme.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('reduce motion', () {
    testWidgets('feed items appear instantly, fully opaque', (tester) async {
      await tester.pumpWidget(_wrap(
        const FeedItemEntrance(index: 3, child: Text('post')),
        disableAnimations: true,
      ));
      // One pump only: with the OS switch on there must be no transition to wait
      // for, and no staggered delay either.
      await tester.pump();

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('shimmer does not paint', (tester) async {
      await tester.pumpWidget(_wrap(
        const Shimmer(child: SizedBox(width: 100, height: 100)),
        disableAnimations: true,
      ));
      await tester.pump();

      // The child is returned unwrapped rather than being masked by a shader that
      // repaints every frame.
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('a reaction does not bounce', (tester) async {
      Widget build(bool active) => _wrap(
            TapBounce(active: active, child: const Icon(Icons.favorite)),
            disableAnimations: true,
          );

      await tester.pumpWidget(build(false));
      await tester.pumpWidget(build(true));
      await tester.pump();

      // Scoped: Material's own internals contribute ScaleTransitions too.
      final scale = tester.widget<ScaleTransition>(find.descendant(
        of: find.byType(TapBounce),
        matching: find.byType(ScaleTransition),
      ));
      expect(scale.scale.value, 1.0, reason: 'no overshoot when motion is off');
    });
  });

  group('entrance animation', () {
    testWidgets('starts transparent and settles opaque', (tester) async {
      await tester.pumpWidget(_wrap(
        const FeedItemEntrance(index: 0, child: Text('post')),
      ));
      await tester.pump();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.0);

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('does not replay when the widget rebuilds', (tester) async {
      // The checkpoint's real requirement: nothing may re-animate during scroll.
      // A ListView rebuilds items constantly, so a per-build animation would
      // flicker and burn frames.
      await tester.pumpWidget(_wrap(
        const FeedItemEntrance(index: 0, child: Text('post')),
      ));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(
        const FeedItemEntrance(index: 0, child: Text('post changed')),
      ));
      await tester.pump();

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    testWidgets('the stagger is capped so late items are not left waiting',
        (tester) async {
      // Item 400 must not queue behind a ten-second delay; by then it is long
      // gone off-screen.
      await tester.pumpWidget(_wrap(
        const FeedItemEntrance(index: 400, child: Text('post')),
      ));
      await tester.pump(Motion.stagger * Motion.maxStaggered);
      await tester.pumpAndSettle();

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    });

    test('entrance stays under the 200ms budget', () {
      expect(Motion.itemEnter.inMilliseconds, lessThanOrEqualTo(200));
      // Worst-case total for a staggered item still has to feel immediate.
      final worst = Motion.itemEnter + Motion.stagger * Motion.maxStaggered;
      expect(worst.inMilliseconds, lessThan(400));
    });
  });

  group('theme', () {
    test('falls back to the seeded scheme when the platform offers none', () {
      // Below Android 12 dynamic_color returns null, which is the normal path on
      // plenty of devices rather than an error.
      for (final brightness in Brightness.values) {
        final theme = buildTheme(dynamicScheme: null, brightness: brightness);
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.brightness, brightness);
      }
    });

    test('uses the wallpaper palette when there is one', () {
      final wallpaper = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00A040),
        brightness: Brightness.dark,
      );
      final theme =
          buildTheme(dynamicScheme: wallpaper, brightness: Brightness.dark);

      expect(theme.colorScheme.primary, isNot(seedColor));
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('cards are flat', () {
      // A feed of elevated cards is a field of drop shadows.
      final theme = buildTheme(dynamicScheme: null, brightness: Brightness.dark);
      expect(theme.cardTheme.elevation, 0);
    });
  });
}
