import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/app_database.dart';
import 'package:feedgram/ui/feed/feed_selector.dart';

/// Reproduces the home shell's feed switching without its repositories.
///
/// The shell decides which feed opens and keeps the pills in step with it, and
/// that is independent of anything the feeds load.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  // Mirrors HomeScreen: the index is authoritative, the page view follows it,
  // and a page change only counts when a finger caused it.
  var _tabIndex = 0;
  final _pages = PageController();
  var _dragging = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(ChannelList list) {
    final index = feedOrder.indexOf(list);
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  bool _watchForDrag(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _dragging = notification.dragDetails != null;
    } else if (notification is ScrollEndNotification) {
      _dragging = false;
    }
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
    return Scaffold(
      body: Column(
        children: [
          FeedSelector(selected: feedOrder[_tabIndex], onSelected: _select),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _watchForDrag,
              child: PageView(
                controller: _pages,
                onPageChanged: _onPageChanged,
                children: [
                  for (final list in feedOrder) _Page(label: list.name),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for a feed: loads once, then grows — the size change is what made
/// the old `TabBarView` drift to the other tab on its own.
class _Page extends StatefulWidget {
  const _Page({required this.label});

  final String label;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  var _started = false;
  var _loads = 0;
  var _items = 0;

  int get loads => _loads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loads++;
    // Deferred, like a real query resolving after the first frame.
    Future<void>.delayed(const Duration(milliseconds: 20), () {
      if (mounted) setState(() => _items = 40);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      children: [
        for (var i = 0; i < _items; i++)
          SizedBox(height: 80, child: Text('${widget.label} $i')),
      ],
    );
  }
}

String _labelOf(ChannelList list) =>
    list == ChannelList.forYou ? 'For You' : 'Following';

/// Which pill carries the selected fill.
///
/// Compared against the theme's `primaryContainer` rather than "whichever
/// differs" — the latter cannot tell the two apart and silently reports the
/// first pill whatever the state.
ChannelList _selectedPill(WidgetTester tester) {
  final selectedFill =
      selectedPillFill(tester.element(find.byType(FeedSelector)));

  final selected = <ChannelList>[];
  for (final list in feedOrder) {
    final container = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text(_labelOf(list)),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    if ((container.decoration as BoxDecoration).color == selectedFill) {
      selected.add(list);
    }
  }

  expect(selected, hasLength(1), reason: 'exactly one pill is current');
  return selected.single;
}

int _loadsOf(WidgetTester tester, ChannelList list) => tester
    .state<_PageState>(
      find.byWidgetPredicate(
        (w) => w is _Page && w.label == list.name,
        skipOffstage: false,
      ),
    )
    .loads;

void main() {
  testWidgets('opens on For You', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    expect(_selectedPill(tester), ChannelList.forYou);
    expect(find.text('forYou 0'), findsOneWidget);
  });

  testWidgets('stays on For You once the feeds finish loading',
      (tester) async {
    // The regression this replaces a real bug with: the old TabBarView derived
    // the current tab from a scroll offset, so a feed resizing after its query
    // resolved slid the app to the other tab, seconds after launch, untouched.
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pump();
    expect(_selectedPill(tester), ChannelList.forYou);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(
      _selectedPill(tester),
      ChannelList.forYou,
      reason: 'nothing but a tap may change the feed',
    );
  });

  testWidgets('tapping switches, and back again', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(_selectedPill(tester), ChannelList.following);
    expect(find.text('following 0'), findsOneWidget);

    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(_selectedPill(tester), ChannelList.forYou);
    expect(find.text('forYou 0'), findsOneWidget);
  });

  testWidgets('returning to For You does not reload it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();
    expect(_loadsOf(tester, ChannelList.forYou), 1);

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();

    expect(
      _loadsOf(tester, ChannelList.forYou),
      1,
      reason: 'For You must not re-rank and restart on every visit',
    );
  });

  group('swipe', () {
    testWidgets('swiping moves to the next feed and the pills follow',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Shell()));
      await tester.pumpAndSettle();

      await tester.drag(find.text('forYou 1'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(_selectedPill(tester), ChannelList.following);
      expect(find.text('following 0'), findsOneWidget);
    });

    testWidgets('swiping back returns without reloading', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Shell()));
      await tester.pumpAndSettle();

      await tester.drag(find.text('forYou 1'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.text('following 1'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(_selectedPill(tester), ChannelList.forYou);
      expect(_loadsOf(tester, ChannelList.forYou), 1);
    });

    testWidgets('a page change with no finger behind it is ignored',
        (tester) async {
      // The guard that lets the swipe exist at all. Layout can move a page
      // view's offset on its own — that is exactly how the old TabBarView slid
      // the app to the other feed seconds after launch — so a page change is
      // only honoured when a drag caused it.
      await tester.pumpWidget(const MaterialApp(home: _Shell()));
      await tester.pumpAndSettle();

      final state = tester.state<_ShellState>(find.byType(_Shell));
      state._onPageChanged(1);
      await tester.pumpAndSettle();

      expect(
        _selectedPill(tester),
        ChannelList.forYou,
        reason: 'only a finger may change the feed',
      );
    });
  });

  testWidgets('scroll position survives the round trip', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await tester.drag(find.text('forYou 1'), const Offset(0, -600));
    await tester.pumpAndSettle();
    final before =
        Scrollable.of(tester.element(find.text('forYou 9'))).position.pixels;
    expect(before, greaterThan(0), reason: 'the drag actually moved the list');

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();

    final after =
        Scrollable.of(tester.element(find.text('forYou 9'))).position.pixels;
    expect(after, before);
  });
}
