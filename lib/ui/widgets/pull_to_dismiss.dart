import 'package:flutter/material.dart';

/// Pulling down on this widget goes back.
///
/// A [Listener] rather than a [GestureDetector] on purpose: a gesture detector
/// would join the arena and win every vertical drag over it, including upward
/// ones, so dragging up on a profile card would stop scrolling the feed
/// underneath. A listener only watches the raw pointer and never claims it,
/// leaving the scroll untouched.
///
/// Distance, not velocity. A deliberate slow pull is the same intent as a flick,
/// and a velocity test would reject it.
class PullToDismiss extends StatefulWidget {
  const PullToDismiss({super.key, required this.child, this.threshold = 90});

  final Widget child;

  /// Far enough that the slop in a tap or a hesitant scroll cannot trigger it,
  /// short enough to still feel like a flick.
  final double threshold;

  @override
  State<PullToDismiss> createState() => _PullToDismissState();
}

class _PullToDismissState extends State<PullToDismiss> {
  var _start = 0.0;
  var _travelled = 0.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _start = event.position.dy;
        _travelled = 0;
      },
      onPointerMove: (event) => _travelled = event.position.dy - _start,
      onPointerUp: (_) {
        if (_travelled > widget.threshold) Navigator.of(context).maybePop();
      },
      child: widget.child,
    );
  }
}
