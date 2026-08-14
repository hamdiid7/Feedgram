import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home shell's push-away header, reproduced without its repositories.
///
/// The behaviour under test is that the header *tracks* the scroll rather than
/// deciding to vanish: content coming up pushes it out by the same number of
/// pixels, and content going down drags it back by the same number.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final _hidden = ValueNotifier<double>(0);
  final _headerKey = GlobalKey();
  var _headerHeight = 0.0;

  static const headerHeight = 130.0;

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height;
    if (height == null || height == _headerHeight) return;
    setState(() => _headerHeight = height);
  }

  var _switchingFeed = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) {
      if (notification is ScrollStartNotification) {
        _switchingFeed = true;
      } else if (notification is ScrollEndNotification) {
        _switchingFeed = false;
      }
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_switchingFeed) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _hidden.value = (_hidden.value + delta).clamp(0.0, _headerHeight);
    }
    if (notification.metrics.pixels <= 0) _hidden.value = 0;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding:
                    MediaQuery.paddingOf(context).copyWith(top: _headerHeight),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: PageView(
                  children: [
                    ListView.builder(
                      itemCount: 40,
                      itemBuilder: (context, i) =>
                          SizedBox(height: 120, child: Text('post $i')),
                    ),
                    ListView.builder(
                      itemCount: 40,
                      itemBuilder: (context, i) =>
                          SizedBox(height: 120, child: Text('other $i')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _hidden,
              builder: (context, hidden, child) => Transform.translate(
                offset: Offset(0, -hidden),
                child: child,
              ),
              child: Container(
                key: _headerKey,
                height: headerHeight,
                color: const Color(0xCCFFFFFF),
                child: const Text('Feedgram'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How far the header has been pushed off the top, read from where it is drawn.
double _hidden(WidgetTester tester) =>
    -tester.getTopLeft(find.text('Feedgram')).dy;

/// How far the feed itself has scrolled.
double _scrolled(WidgetTester tester) =>
    Scrollable.of(tester.element(find.text('post 1'))).position.pixels;

Future<void> _dragFeed(WidgetTester tester, double dy) async {
  // A hand-driven gesture rather than `drag`, so nothing flings on after release
  // and the assertions can describe exactly the distance dragged.
  final slop = dy.sign * 20;
  // Well inside the 800x600 test surface: starting at its very edge grabs
  // nothing and every assertion below silently reads "no movement".
  final gesture = await tester.startGesture(const Offset(400, 300));
  await gesture.moveBy(Offset(0, slop));
  await gesture.moveBy(Offset(0, dy - slop));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts fully shown', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    expect(_hidden(tester), 0);
  });

  testWidgets('the feed is inset by the measured header height',
      (tester) async {
    // Not a hardcoded guess: a wrong number is either a gap above the first post
    // or a post permanently hidden behind the pills.
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('post 0')).top,
      moreOrLessEquals(_ShellState.headerHeight, epsilon: 1),
    );
  });

  testWidgets('a short scroll moves it by that much, not all the way',
      (tester) async {
    // The point of the change. All-or-nothing is what made it read as the header
    // "disappearing"; moving 40 pixels for a 40 pixel scroll is what makes it
    // read as being pushed out of the way.
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await _dragFeed(tester, -40);

    // Compared against what the content actually did, not against the finger:
    // the drag recognizer eats the touch slop before any of it becomes scroll,
    // and the claim being made here is that the header keeps pace with the
    // content, whatever distance that turns out to be.
    final scrolled = _scrolled(tester);
    expect(scrolled, greaterThan(0), reason: 'the feed really moved');
    expect(scrolled, lessThan(_ShellState.headerHeight),
        reason: 'and by less than a full header, so this is the partial case');
    expect(_hidden(tester), moreOrLessEquals(scrolled, epsilon: 1));
  });

  testWidgets('scrolling back up brings it back by the same amount',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await _dragFeed(tester, -200);
    final pushed = _hidden(tester);
    final scrolledDown = _scrolled(tester);
    expect(pushed, greaterThan(50));

    await _dragFeed(tester, 30);

    final cameBack = scrolledDown - _scrolled(tester);
    expect(cameBack, greaterThan(0), reason: 'the feed really came back up');
    expect(_hidden(tester), moreOrLessEquals(pushed - cameBack, epsilon: 1));
  });

  testWidgets('it never pushes further than its own height', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await _dragFeed(tester, -1200);

    expect(_hidden(tester), _ShellState.headerHeight);
  });

  testWidgets('it never pulls down past its resting place', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await _dragFeed(tester, 300);

    expect(_hidden(tester), 0, reason: 'no gap above the header');
  });

  testWidgets('returning to the top restores it in full', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await _dragFeed(tester, -600);
    expect(_hidden(tester), greaterThan(0));

    Scrollable.of(tester.element(find.text('post 3'))).position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(_hidden(tester), 0);
  });

  testWidgets('a horizontal page swipe does not move it', (tester) async {
    // The page view between feeds scrolls too, and its notifications pass
    // through the same listener.
    await tester.pumpWidget(const MaterialApp(home: _Shell()));
    await tester.pumpAndSettle();

    await tester.drag(find.text('post 1'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(_hidden(tester), 0);
  });
}
