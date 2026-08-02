import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/ui/widgets/pull_to_dismiss.dart';

/// The profile header's pull-to-go-back.
///
/// Exercises the real [PullToDismiss] widget, not a copy of it — the whole point
/// is its interaction with the scroll view underneath, and a duplicated copy
/// could keep passing here long after the app's version had drifted.
/// A profile screen shaped like the real one: a collapsing header whose detail
/// is wrapped in the gesture, over a long scrollable body.
Widget _profile({required GlobalKey<NavigatorState> navigator}) {
  return MaterialApp(
    navigatorKey: navigator,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      expandedHeight: 172,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Align(
                          alignment: Alignment.bottomLeft,
                          child: PullToDismiss(
                            child: Container(
                              height: 56,
                              width: double.infinity,
                              color: const Color(0xFFEEEEFF),
                              child: const Text('profile card'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: 40,
                      itemBuilder: (context, i) =>
                          SizedBox(height: 120, child: Text('post $i')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('profile card'), findsOneWidget);
}

void main() {
  testWidgets('pulling down on the profile card goes back', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    await tester.drag(find.text('profile card'), const Offset(0, 140));
    await tester.pumpAndSettle();

    expect(find.text('profile card'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a short pull is not enough', (tester) async {
    // The slop in a tap or a hesitant scroll must not throw you off the screen.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    await tester.drag(find.text('profile card'), const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(find.text('profile card'), findsOneWidget);
  });

  testWidgets('dragging up on the card still scrolls the feed',
      (tester) async {
    // The reason this is a Listener and not a GestureDetector: a detector would
    // claim every vertical drag on the card, including upward ones, and the
    // header would become a dead zone you cannot scroll from.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    final before =
        Scrollable.of(tester.element(find.text('post 0'))).position.pixels;

    await tester.drag(find.text('profile card'), const Offset(0, -160));
    await tester.pumpAndSettle();

    final after =
        Scrollable.of(tester.element(find.text('post 1'))).position.pixels;
    expect(after, greaterThan(before), reason: 'the header must still scroll');
    expect(find.text('open'), findsNothing, reason: 'and must not go back');
  });

  testWidgets('a downward drag on a post does not go back', (tester) async {
    // Posts keep pull-to-refresh; only the card dismisses.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    await tester.drag(find.text('post 1'), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(find.text('profile card'), findsOneWidget);
    expect(find.text('open'), findsNothing);
  });

  testWidgets('a tap on the card is not a pull', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    await tester.tapAt(tester.getCenter(find.text('profile card')));
    await tester.pumpAndSettle();

    expect(find.text('profile card'), findsOneWidget);
  });

  testWidgets('a slow drag past the threshold still counts', (tester) async {
    // Distance, not velocity: a deliberate slow pull is the same intent as a
    // flick, and a velocity test would reject it.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_profile(navigator: navigator));
    await _openProfile(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('profile card')));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('profile card'), findsNothing);
  });
}
