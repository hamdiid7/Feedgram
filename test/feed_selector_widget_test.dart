import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/ui/feed/feed_selector.dart';
import 'package:feedgram/ui/theme.dart';

Widget _wrap({
  required ChannelList selected,
  required ValueChanged<ChannelList> onSelected,
}) {
  return MaterialApp(
    theme: buildTheme(dynamicScheme: null, brightness: Brightness.light),
    home: Scaffold(
      body: FeedSelector(selected: selected, onSelected: onSelected),
    ),
  );
}

void main() {
  test('For You is the leftmost feed', () {
    // The app opens on For You, and a default that is not the first option reads
    // as the app having lost your place.
    expect(feedOrder.first, ChannelList.forYou);
  });

  testWidgets('shows a pill per feed', (tester) async {
    await tester.pumpWidget(
      _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('the group hugs its content instead of filling the width',
      (tester) async {
    // Stretched to full width it reads as two buttons; compact it reads as one
    // control with a current value.
    await tester.pumpWidget(
      _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    final row = tester.getSize(find.byType(Row).first);
    final screen = tester.getSize(find.byType(Scaffold));
    expect(row.width, lessThan(screen.width * 0.75));
  });

  testWidgets('sits against the leading edge', (tester) async {
    await tester.pumpWidget(
      _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
    );
    await tester.pumpAndSettle();

    final left = tester.getTopLeft(find.byType(Row).first).dx;
    expect(left, lessThanOrEqualTo(16), reason: 'left-aligned, not centred');
  });

  testWidgets('tapping a pill selects that feed', (tester) async {
    ChannelList? chosen;

    await tester.pumpWidget(
      _wrap(
        selected: ChannelList.forYou,
        onSelected: (list) => chosen = list,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();

    expect(chosen, ChannelList.following);
  });

  group('selection', () {
    Color? fillUnder(WidgetTester tester, String label) {
      final container = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    testWidgets('the two pills are filled differently', (tester) async {
      await tester.pumpWidget(
        _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(fillUnder(tester, 'For You'), isNot(fillUnder(tester, 'Following')));
    });

    testWidgets('both pills stay filled, only the colour differs',
        (tester) async {
      // An outline-only unselected pill would put a hard edge beside a soft one
      // and break the pair up visually.
      await tester.pumpWidget(
        _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      for (final label in ['For You', 'Following']) {
        final fill = fillUnder(tester, label);
        expect(fill, isNotNull);
        expect(fill!.a, greaterThan(0), reason: '$label must have a fill');
      }
    });

    testWidgets('the fill follows an externally driven selection',
        (tester) async {
      // A swipe moves the selection with no tap involved, so the pill has to
      // render whatever it is handed.
      await tester.pumpWidget(
        _wrap(selected: ChannelList.forYou, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();
      final forYouWhenSelected = fillUnder(tester, 'For You');

      await tester.pumpWidget(
        _wrap(selected: ChannelList.following, onSelected: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(fillUnder(tester, 'For You'), isNot(forYouWhenSelected));
      expect(fillUnder(tester, 'Following'), forYouWhenSelected);
    });
  });
}
