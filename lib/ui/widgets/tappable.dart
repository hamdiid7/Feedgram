import 'package:flutter/material.dart';

import '../theme.dart';

/// A tappable surface with the budget app's feel: a filled, rounded Material
/// with the ripple clipped to the same radius.
///
/// The reason this exists rather than a bare [InkWell] is the clipping. An
/// `InkWell` paints its splash on the nearest [Material] ancestor, which in a
/// feed is the page background — so the ripple escapes past the rounded corners
/// of whatever was tapped and washes across neighbouring cards. Giving each
/// tappable its own `Material` with a matching `borderRadius` keeps the splash
/// inside the shape.
class Tappable extends StatelessWidget {
  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 0,
    this.color,
    this.type = MaterialType.canvas,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;

  /// Defaults to transparent, so a `Tappable` shows whatever it is laid over
  /// until it is deliberately given a surface.
  final Color? color;

  final MaterialType type;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return Material(
      color: color ?? Colors.transparent,
      type: type,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}

/// A [Tappable] on a tinted container — the app's standard card body.
class TappableCard extends StatelessWidget {
  const TappableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = Shapes.card,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.padding = EdgeInsets.zero,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Tappable(
        borderRadius: borderRadius,
        color: color ?? containerColor(context),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
