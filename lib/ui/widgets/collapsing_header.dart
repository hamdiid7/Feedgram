import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

/// A [SliverAppBar] that collapses the budget app's way: the title slides right
/// past the back arrow and shrinks as the header shrinks, while the detail
/// underneath fades out well before it reaches the top.
///
/// The point of the geometry is that the title never *moves out* and a new one
/// moves in — the same text travels from a large heading to the compact app-bar
/// label, so the header reads as one object folding up rather than two states
/// swapping.
class CollapsingHeader extends StatelessWidget {
  const CollapsingHeader({
    super.key,
    required this.title,
    required this.expandedHeight,
    this.detail,
    this.detailHeight = 0,
    this.actions,
    this.hasBackButton = true,
  });

  final String title;

  /// Shown below the title while expanded, gone by the halfway point.
  final Widget? detail;

  /// How tall [detail] is.
  ///
  /// Needed because the title and the detail both sit at the bottom of the
  /// header: the title is lifted by this much while expanded so the two do not
  /// land on top of each other, and set back down as it collapses. Measuring it
  /// at runtime would mean a layout pass per frame during the scroll.
  final double detailHeight;

  final double expandedHeight;
  final List<Widget>? actions;
  final bool hasBackButton;

  /// The height of a Material app bar. Not read from the theme deliberately —
  /// this number has to match what [SliverAppBar] actually collapses to, and
  /// that is the constant, not a themed value.
  static const collapsedHeight = kToolbarHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SliverAppBar(
      pinned: true,
      expandedHeight: expandedHeight,
      collapsedHeight: collapsedHeight,
      actions: actions,
      // Matches the app bars everywhere else, which are plain surface. A tinted
      // band here would make the profile the one screen with a coloured header.
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final top = MediaQuery.paddingOf(context).top;
          final travel = expandedHeight - collapsedHeight;

          // 0 fully expanded, 1 fully collapsed.
          final collapsed = travel <= 0
              ? 1.0
              : clampDouble(
                  1 - (constraints.biggest.height - collapsedHeight - top) /
                      travel,
                  0,
                  1,
                );

          // Room the collapsed title must not stray into: the horizontal shift
          // that clears the back arrow, plus the action buttons on the right.
          // Reserved through padding rather than by clipping, so the title
          // ellipsises instead of sliding under an icon. Over-reserved a little
          // because the title is also scaled up 15% at this end, and the scale
          // is applied after layout.
          final reserved = 60 + (actions?.length ?? 0) * 52.0;

          return FlexibleSpaceBar(
            titlePadding: EdgeInsetsDirectional.only(
              start: 18,
              end: 18 + reserved * collapsed,
              bottom: 15,
            ),
            title: MediaQuery.withNoTextScaling(
              child: Transform.translate(
                // FlexibleSpaceBar lays the collapsed title out from the very
                // left edge — it knows nothing about the leading widget — so
                // without this the title slides under the back arrow.
                offset: Offset(
                  (hasBackButton ? 46 : 10) * collapsed,
                  -detailHeight * (1 - collapsed) - 0.5 * collapsed,
                ),
                child: Transform.scale(
                  alignment: Alignment.bottomLeft,
                  // FlexibleSpaceBar already scales the title 1.5x→1.0x on its
                  // own. This adds 15% at the collapsed end only, which lands the
                  // final size close to a title style rather than body text.
                  scale: collapsed * 0.15 + 1,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            background: detail == null
                ? null
                : Align(
                    alignment: Alignment.bottomLeft,
                    child: Transform.translate(
                      // Drifts up faster than the header shrinks, so it clears
                      // the title's path instead of colliding with it.
                      offset: Offset(0, -40 * collapsed),
                      child: Opacity(
                        // Gone by the halfway point: past that the header is too
                        // short to hold it, and fading right to the end would
                        // leave a ghost of it under the collapsed title.
                        opacity: 1 - clampDouble(collapsed, 0, 0.5) * 2,
                        // Detail can hold real controls — membership chips, in
                        // this app. Invisible is not the same as gone, and a
                        // collapsed header that still swallows taps where the
                        // chips used to be is a genuinely baffling bug.
                        child: IgnorePointer(
                          ignoring: collapsed >= 0.5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                            child: detail,
                          ),
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
