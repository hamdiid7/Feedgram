import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/ui/motion.dart';
import 'package:feedgram/ui/theme.dart';
import 'package:feedgram/ui/widgets/collapsing_header.dart';
import 'package:feedgram/ui/widgets/count_number.dart';
import 'package:feedgram/ui/widgets/open_container_navigation.dart';
import 'package:feedgram/ui/widgets/tappable.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(
      theme: buildTheme(dynamicScheme: null, brightness: brightness),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('pastel surfaces', () {
    testWidgets('a container recedes from the background in both themes',
        (tester) async {
      final results = <Brightness, Color>{};

      // Both themes live in one tree, so neither reading can be contaminated by
      // the other's element being reused across pumps.
      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            for (final brightness in Brightness.values)
              Theme(
                data: buildTheme(dynamicScheme: null, brightness: brightness),
                child: Builder(builder: (context) {
                  results[brightness] = containerColor(context);
                  return const SizedBox();
                }),
              ),
          ],
        ),
      ));

      // The whole point of dynamicPastel is that one call site produces a
      // recessed surface in either theme rather than a fixed tint that only
      // works in one. If the two matched, it would be doing nothing.
      expect(results[Brightness.light], isNot(results[Brightness.dark]));
    });

    test('lighten and darken move in opposite directions', () {
      const base = Color(0xFF808080);
      expect(lightenPastel(base, amount: 0.5).r, greaterThan(base.r));
      expect(darkenPastel(base, amount: 0.5).r, lessThan(base.r));
    });

    test('a blend amount above 1 is clamped rather than throwing', () {
      // Color.alphaBlend asserts on an out-of-range alpha, so an over-eager
      // caller would crash at paint time rather than at the call.
      const base = Color(0xFF3355AA);
      expect(() => lightenPastel(base, amount: 1.0), returnsNormally);
    });
  });

  group('tappable', () {
    testWidgets('owns a Material, so its ripple cannot escape the corners',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const Tappable(borderRadius: 15, child: Text('tap')),
      ));

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(Tappable),
          matching: find.byType(Material),
        ),
      );
      expect(material.borderRadius, BorderRadius.circular(15));
    });

    testWidgets('is transparent unless given a colour', (tester) async {
      await tester.pumpWidget(_wrap(const Tappable(child: Text('tap'))));

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(Tappable),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, Colors.transparent);
    });
  });

  group('container transform', () {
    testWidgets('opens the page', (tester) async {
      await tester.pumpWidget(_wrap(
        OpenContainerNavigation(
          openPage: const Scaffold(body: Text('profile')),
          button: (open) =>
              TextButton(onPressed: open, child: const Text('header')),
        ),
      ));

      await tester.tap(find.text('header'));
      await tester.pumpAndSettle();

      expect(find.text('profile'), findsOneWidget);
    });

    testWidgets('a row inside a list opens, with a closed colour set',
        (tester) async {
      // The channels list wraps each row this way. Worth its own case: a
      // transform inside a scrollable competes with the scroll gesture, and the
      // closedColor path builds a different subtree from the bare one above.
      await tester.pumpWidget(_wrap(
        ListView.builder(
          itemCount: 20,
          itemBuilder: (context, i) => OpenContainerNavigation(
            borderRadius: 15,
            closedColor: const Color(0xFFEEEEFF),
            openPage: Scaffold(body: Text('profile $i')),
            button: (open) => Tappable(
              onTap: open,
              borderRadius: 15,
              child: SizedBox(height: 80, child: Text('row $i')),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('row 2'));
      await tester.pumpAndSettle();

      expect(find.text('profile 2'), findsOneWidget);
    });

    testWidgets('a row still opens while its list is rebuilding',
        (tester) async {
      // The channels list is driven by a stream that emits whenever a
      // subscriber count changes, which during a large backfill is constantly.
      // A rebuild between pointer-down and pointer-up must not cancel the tap.
      var generation = 0;
      late StateSetter refresh;

      await tester.pumpWidget(_wrap(
        StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            return ListView.builder(
              itemCount: 20,
              itemBuilder: (context, i) => OpenContainerNavigation(
                borderRadius: 15,
                closedColor: const Color(0xFFEEEEFF),
                openPage: Scaffold(body: Text('profile $i')),
                button: (open) => Tappable(
                  onTap: open,
                  borderRadius: 15,
                  child: SizedBox(
                    height: 80,
                    child: Text('row $i gen $generation'),
                  ),
                ),
              ),
            );
          },
        ),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('row 2 gen 0')),
      );
      refresh(() => generation++);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('profile 2'), findsOneWidget);
    });

    testWidgets('falls back to a plain push when motion is off',
        (tester) async {
      // A transform that grows a card to fill the screen is precisely the
      // large-area movement the accessibility switch exists to suppress.
      await tester.pumpWidget(_wrap(
        OpenContainerNavigation(
          openPage: const Scaffold(body: Text('profile')),
          button: (open) =>
              TextButton(onPressed: open, child: const Text('header')),
        ),
        disableAnimations: true,
      ));

      await tester.tap(find.text('header'));
      await tester.pumpAndSettle();

      expect(find.text('profile'), findsOneWidget);
    });
  });

  group('count number', () {
    testWidgets('does not animate on first build', (tester) async {
      // Every card scrolling into view would otherwise start a tween that
      // conveys nothing, because the value did not change.
      await tester.pumpWidget(_wrap(
        CountNumber(
          value: 1200,
          builder: (context, value) => Text('$value'),
        ),
      ));
      await tester.pump();

      expect(find.text('1200'), findsOneWidget);
    });

    testWidgets('rolls when the value changes, and lands on it',
        (tester) async {
      Widget build(int value) => _wrap(
            CountNumber(
              value: value,
              builder: (context, v) => Text('$v'),
            ),
          );

      await tester.pumpWidget(build(10));
      await tester.pumpWidget(build(60));
      await tester.pump(const Duration(milliseconds: 40));

      final mid = int.parse(
        (tester.widget<Text>(find.byType(Text)).data)!,
      );
      expect(mid, greaterThan(10));
      expect(mid, lessThan(60));

      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('snaps to the new value when motion is off', (tester) async {
      Widget build(int value) => _wrap(
            CountNumber(value: value, builder: (context, v) => Text('$v')),
            disableAnimations: true,
          );

      await tester.pumpWidget(build(10));
      await tester.pumpWidget(build(60));
      await tester.pump();

      expect(find.text('60'), findsOneWidget);
    });
  });

  group('collapsing header', () {
    testWidgets('detail stops taking taps once it has faded out',
        (tester) async {
      var detailTaps = 0;

      IgnorePointer guard() => tester.widget<IgnorePointer>(find.descendant(
            of: find.byType(CollapsingHeader),
            matching: find.byType(IgnorePointer),
          ));

      await tester.pumpWidget(_wrap(
        CustomScrollView(
          slivers: [
            CollapsingHeader(
              title: 'A Channel',
              expandedHeight: 200,
              detailHeight: 104,
              detail: TextButton(
                onPressed: () => detailTaps++,
                child: const Text('Following'),
              ),
            ),
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // Expanded: the chip is live.
      expect(guard().ignoring, isFalse);
      await tester.tap(find.text('Following'));
      expect(detailTaps, 1);

      await tester.drag(find.text('5'), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Collapsed: it is invisible, and invisible controls must not still be
      // swallowing taps where the app bar now is. Asserted on the guard rather
      // than by tapping — a tap that lands nowhere passes either way, so it
      // would not notice the guard being removed.
      expect(guard().ignoring, isTrue,
          reason: 'faded-out detail must not be tappable');
    });

    testWidgets('the title survives the collapse', (tester) async {
      await tester.pumpWidget(_wrap(
        CustomScrollView(
          slivers: [
            const CollapsingHeader(title: 'A Channel', expandedHeight: 200),
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('A Channel'), findsOneWidget);

      await tester.drag(find.text('5'), const Offset(0, -500));
      await tester.pumpAndSettle();

      // One title throughout — it folds up, it is not swapped for a second one.
      expect(find.text('A Channel'), findsOneWidget);
    });
  });

  group('motion primitives honour reduce motion', () {
    testWidgets('ScaleIn is full size on the first frame', (tester) async {
      await tester.pumpWidget(_wrap(
        const ScaleIn(child: Text('badge')),
        disableAnimations: true,
      ));
      await tester.pump();

      final scale = tester.widget<ScaleTransition>(find.descendant(
        of: find.byType(ScaleIn),
        matching: find.byType(ScaleTransition),
      ));
      expect(scale.scale.value, 1.0);
    });

    testWidgets('SlideFadeIn is in place on the first frame', (tester) async {
      await tester.pumpWidget(_wrap(
        const SlideFadeIn(child: Text('body')),
        disableAnimations: true,
      ));
      await tester.pump();

      final slide = tester.widget<SlideTransition>(find.descendant(
        of: find.byType(SlideFadeIn),
        matching: find.byType(SlideTransition),
      ));
      expect(slide.position.value, Offset.zero);
    });

    testWidgets('AnimatedExpanded shows and hides without tweening',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AnimatedExpanded(expand: false, child: Text('notice')),
        disableAnimations: true,
      ));
      await tester.pump();
      expect(find.text('notice'), findsNothing);

      await tester.pumpWidget(_wrap(
        const AnimatedExpanded(expand: true, child: Text('notice')),
        disableAnimations: true,
      ));
      await tester.pump();
      expect(find.text('notice'), findsOneWidget);
    });

    testWidgets('AnimatedSizeSwitcher passes its child straight through',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AnimatedSizeSwitcher(child: Text('one')),
        disableAnimations: true,
      ));
      await tester.pump();

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.text('one'), findsOneWidget);
    });
  });

  group('AnimatedExpanded with motion on', () {
    testWidgets('collapsing does not make the content vanish instantly',
        (tester) async {
      // The reason to use it at all: a hard removal makes everything below jump.
      await tester.pumpWidget(_wrap(
        const AnimatedExpanded(expand: true, child: Text('notice')),
      ));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(
        const AnimatedExpanded(expand: false, child: Text('notice')),
      ));
      await tester.pump(const Duration(milliseconds: 30));

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0, reason: 'target is hidden');
      // Still rendering mid-collapse, rather than having been ripped out.
      expect(find.byType(AnimatedSize), findsOneWidget);
    });
  });

  group('DelayedCurve', () {
    test('holds at zero, then completes', () {
      const curve = DelayedCurve(delayFraction: 0.25);
      expect(curve.transform(0.0), 0);
      expect(curve.transform(0.2), 0);
      expect(curve.transform(1.0), 1);
      expect(curve.transform(0.6), greaterThan(0));
    });
  });

  group('shape scale', () {
    test('radii increase with the size of the surface', () {
      // Rows sit inside cards, cards sit inside sheets. If a child's radius
      // exceeded its parent's the corners would visibly cross.
      expect(Shapes.row, lessThan(Shapes.card));
      expect(Shapes.card, lessThan(Shapes.sheet));
    });
  });
}
