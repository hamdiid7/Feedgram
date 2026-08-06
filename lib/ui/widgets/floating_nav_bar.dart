import 'package:flutter/material.dart';

import '../theme.dart';

/// One destination in the bar.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;

  /// Filled when current. The switch from outline to filled is what carries the
  /// selection at a glance, before the indicator or the label register.
  final IconData selectedIcon;
}

/// The app's bottom navigation, in the budget app's style: a tinted bar with a
/// pastel pill behind the current icon and labels always visible.
///
/// Floating rather than edge-to-edge — inset, rounded and shadowed, so it reads
/// as a control resting on the feed rather than a strip welded to the bottom of
/// the screen. That matches the rest of this app, where everything is a rounded
/// card on a tinted background.
///
/// Built by hand rather than with Material's [NavigationBar]. That widget forces
/// its own height, its own edge-to-edge shape and its own indicator geometry, and
/// fighting all three to get a floating pill costs more code than drawing four
/// items in a row.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// The bar's own height, excluding the system inset below it. Exposed so the
  /// screens underneath can pad their scroll views by exactly this much and stop
  /// the last item hiding behind it.
  static const barHeight = 64.0;
  static const margin = 12.0;

  /// What a scrollable underneath should add to its bottom padding.
  static double spaceFor(BuildContext context) =>
      barHeight + margin * 2 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        0,
        margin,
        margin + MediaQuery.paddingOf(context).bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Shapes.sheet),
          // The budget app's sharp shadow: tight blur, small spread, very low
          // alpha. Enough to lift the bar off the feed without the soft grey
          // halo a large blur radius gives.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 2,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Shapes.sheet),
          child: Material(
            color: dynamicPastel(
              context,
              theme.colorScheme.secondaryContainer,
              amountLight: 0.4,
              amountDark: 0.45,
            ),
            child: SizedBox(
              height: barHeight,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _NavItem(
                        destination: destinations[i],
                        selected: i == currentIndex,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final ink = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      // No splash radius fiddling: the item fills its share of the row, so the
      // ripple covering that share is the correct target size.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The pill grows behind the icon rather than the icon moving, so
          // nothing shifts position when the selection changes.
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubicEmphasized,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? dynamicPastel(
                      context,
                      theme.colorScheme.primary,
                      amount: 0.6,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Shapes.pill),
            ),
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              // Bold when current, like the budget app. Weight rather than
              // colour alone, so it survives a low-contrast palette.
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
