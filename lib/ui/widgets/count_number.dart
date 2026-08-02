import 'package:flutter/material.dart';

import '../motion.dart';

/// A number that rolls to its new value instead of snapping.
///
/// Ported from the budget app, with one deliberate change: it does **not** count
/// up on first build. There, a balance counting up from zero is the centrepiece
/// of a screen you open once. Here the same widget appears three times per card
/// in a scrolling list — counting on build would mean every card that scrolls
/// into view starts a 1-second tween, and the animation would carry no
/// information anyway, because nothing changed. So the roll is reserved for the
/// case where it means something: the value actually moved while you were
/// looking at it, as when a reaction lands.
class CountNumber extends StatefulWidget {
  const CountNumber({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Motion.count,
  });

  final int value;

  /// Renders the intermediate value. Takes a builder rather than a text style so
  /// callers keep control of formatting — compacting to "1.2K", say.
  final Widget Function(BuildContext context, int value) builder;

  final Duration duration;
  final Curve curve;

  @override
  State<CountNumber> createState() => _CountNumberState();
}

class _CountNumberState extends State<CountNumber> {
  late int _from = widget.value;

  @override
  void didUpdateWidget(CountNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start from wherever the last frame left off, so a second change arriving
    // mid-roll continues from the displayed number rather than snapping back.
    if (oldWidget.value != widget.value) _from = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.enabled(context) || _from == widget.value) {
      return widget.builder(context, widget.value);
    }

    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _from, end: widget.value),
      duration: widget.duration,
      curve: widget.curve,
      builder: (context, value, _) => widget.builder(context, value),
    );
  }
}
