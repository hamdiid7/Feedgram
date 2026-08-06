import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/tappable.dart';

/// Display order of the feeds, left to right.
///
/// For You first because that is where the app opens — a default that is not the
/// leftmost option reads as the app having lost your place.
///
/// Single source of truth: the pills and the `TabBarView` children are both
/// built from this, so an index can never mean one feed in the selector and a
/// different one in the body.
const feedOrder = [ChannelList.forYou, ChannelList.following];

/// The fill that marks the current feed.
///
/// Shared with the tests so an assertion about "which pill is selected" cannot
/// quietly drift from what the widget actually paints.
Color selectedPillFill(BuildContext context) =>
    Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5);

/// The two feeds as a pill group.
///
/// Left-aligned and sized to its content rather than stretched across the width:
/// a segmented control that fills the screen reads as two buttons, whereas a
/// compact group reads as one control with a current value.
class FeedSelector extends StatelessWidget {
  const FeedSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ChannelList selected;
  final ValueChanged<ChannelList> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // No fill of its own: the strip sits inside the frosted header, which
      // supplies the translucent white and the blur behind these pills.
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final list in feedOrder) ...[
            _FeedPill(
              list: list,
              selected: selected == list,
              onTap: () => onSelected(list),
            ),
            if (list != feedOrder.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FeedPill extends StatelessWidget {
  const _FeedPill({
    required this.list,
    required this.selected,
    required this.onTap,
  });

  final ChannelList list;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (list) {
        ChannelList.following => 'Following',
        ChannelList.forYou => 'For You',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Both states are filled — the difference is which fill. An outline-only
    // unselected pill would put a hard edge next to a soft one and make the pair
    // look like two unrelated controls.
    //
    // The unselected fill is a step *away* from the page rather than a named
    // surface role: `surfaceContainerHighest` under this desaturated navy scheme
    // came out all but identical to the background, so the pill vanished and
    // only the selected one looked like a control at all. Stepping off the
    // actual background colour is guaranteed to show up in either theme.
    //
    // Both at half opacity, so the tinted strip shows through and the pills read
    // as glass rather than solid chips laid on top. The unselected pill steps
    // *toward* the page surface rather than away from it, because the strip
    // behind it is now tinted — stepping the same direction as the tint would
    // leave the two almost indistinguishable.
    final fill = selected
        ? selectedPillFill(context)
        : theme.colorScheme.surface.withValues(alpha: 0.5);
    final ink = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: Motion.fade,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Shapes.pill),
      ),
      // Tappable inside the fill, not around it: its Material is transparent, so
      // the ripple paints above the colour rather than underneath it.
      child: Tappable(
        onTap: onTap,
        borderRadius: Shapes.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          child: AnimatedDefaultTextStyle(
            duration: Motion.fade,
            curve: Motion.standard,
            style: theme.textTheme.labelLarge!.copyWith(
              color: ink,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(_label),
          ),
        ),
      ),
    );
  }
}
