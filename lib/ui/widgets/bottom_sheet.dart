import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../theme.dart';

/// Shows a snapping bottom sheet in the budget app's style.
///
/// [builder] is handed the sheet's own [ScrollController]; giving it to the
/// scrollable inside is what links the two gestures, so dragging content that is
/// already scrolled to the top continues into dragging the sheet itself, with no
/// seam where the finger has to lift and start again.
Future<T?> openBottomSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
      builder,
  double initialSize = 0.6,
  double minSize = 0.35,
  double maxSize = 0.95,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Required, or the sheet is capped at half the screen and the snap to full
    // height has nowhere to go.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => _SnappingSheet(
      initialSize: initialSize,
      minSize: minSize,
      maxSize: maxSize,
      builder: builder,
    ),
  );
}

class _SnappingSheet extends StatefulWidget {
  const _SnappingSheet({
    required this.builder,
    required this.initialSize,
    required this.minSize,
    required this.maxSize,
  });

  final Widget Function(BuildContext context, ScrollController controller)
      builder;
  final double initialSize;
  final double minSize;
  final double maxSize;

  @override
  State<_SnappingSheet> createState() => _SnappingSheetState();
}

class _SnappingSheetState extends State<_SnappingSheet> {
  /// Latched so the impact fires on the *crossing* into full height, not on
  /// every notification while the sheet sits there.
  var _atFullHeight = false;

  bool _onExtentChanged(DraggableScrollableNotification notification) {
    final full = notification.extent >= widget.maxSize - 0.001;
    if (full != _atFullHeight) {
      _atFullHeight = full;
      // The budget app taps you on the wrist when a sheet bottoms out at the top
      // of its travel. It is the only feedback that the drag has run out of
      // room, since the sheet simply stops moving otherwise.
      if (full) HapticFeedback.heavyImpact();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtentChanged,
      child: DraggableScrollableSheet(
        initialChildSize: widget.initialSize,
        minChildSize: widget.minSize,
        maxChildSize: widget.maxSize,
        expand: false,
        snap: true,
        // Only the opening height is a snap point. Adding the extremes would let
        // a slow drag toward dismissal spring back up, which reads as the sheet
        // fighting the gesture.
        snapSizes: [widget.initialSize],
        builder: (context, controller) => DecoratedBox(
          decoration: BoxDecoration(
            color: containerColor(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Shapes.sheet),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Shapes.sheet),
            ),
            child: widget.builder(context, controller),
          ),
        ),
      ),
    );
  }
}

/// The header every sheet in the app shares: a large bold title, an optional
/// subtitle, and a close button in the corner.
///
/// The title size steps down for long strings. The budget app sets 29pt and
/// drops to 23pt past sixteen characters, which is the difference between a
/// title that anchors the sheet and one that wraps to three lines and pushes the
/// content off-screen.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: title.length > 16 ? 23 : 29,
                      height: 1.1,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 2),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ?trailing,
          IconButton(
            iconSize: 24,
            padding: const EdgeInsets.all(16),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The short bar at the top of a sheet that says it can be dragged.
///
/// The budget app's sheets are draggable anywhere on their surface, so they need
/// no handle. This one drags from its scroll view, which is a less obvious
/// affordance — hence the handle.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 34,
        height: 4,
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Shapes.pill),
        ),
      ),
    );
  }
}

/// Bottom padding for sheet content: the system inset, but never less than 10.
///
/// Gesture-navigation devices report a real inset here and three-button ones
/// report zero, so without a floor the last row of a sheet sits flush against
/// the screen edge on exactly the devices that have no bar to separate it from.
double sheetBottomPadding(BuildContext context) {
  const minimum = 10.0;
  final inset = MediaQuery.paddingOf(context).bottom;
  return inset < minimum ? minimum : inset;
}

/// A sheet's content: handle, header, then a scrollable body.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SheetHandle(),
        SheetHeader(title: title, subtitle: subtitle, trailing: trailing),
        Divider(
          height: 1,
          indent: 18,
          endIndent: 18,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        // Fades and lifts in behind the header, so the sheet does not arrive
        // with a block of text already fully drawn on it.
        Expanded(
          child: SlideFadeIn(
            offset: const Offset(0, 0.06),
            delay: const Duration(milliseconds: 60),
            child: child,
          ),
        ),
      ],
    );
  }
}
