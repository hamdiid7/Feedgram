import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../motion.dart';

/// Opens a page by growing the tapped widget into it — the container transform.
///
/// This is the budget app's navigation gesture, and it is doing something a
/// [Hero] cannot: a hero moves *one element* between two independently-composed
/// screens, whereas this cross-fades the entire tapped surface into the entire
/// destination while morphing the bounds between them. For a post header opening
/// a channel profile that is the honest description of what happens — the header
/// **is** a small version of the profile, not a page that happens to share an
/// avatar with one.
///
/// [button] is handed the callback that opens the page, rather than being wrapped
/// in a tap handler here, so the child keeps its own ripple and hit area.
class OpenContainerNavigation extends StatelessWidget {
  const OpenContainerNavigation({
    super.key,
    required this.openPage,
    required this.button,
    this.borderRadius = 0,
    this.closedColor,
    this.onOpen,
    this.onClosed,
  });

  final Widget openPage;
  final Widget Function(VoidCallback openContainer) button;
  final double borderRadius;
  final Color? closedColor;
  final VoidCallback? onOpen;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(borderRadius);

    // With the OS reduce-motion switch on, a transform that grows a card to fill
    // the screen is exactly the kind of large-area movement the setting exists to
    // suppress. Fall back to a plain push, which Flutter already renders without
    // animation in that mode.
    if (!Motion.enabled(context)) {
      return ClipRRect(
        borderRadius: shape,
        child: ColoredBox(
          color: closedColor ?? Colors.transparent,
          child: button(() async {
            onOpen?.call();
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => openPage),
            );
            onClosed?.call();
          }),
        ),
      );
    }

    return OpenContainer<void>(
      // Fade, not fadeThrough: the destination shares the source's content, so
      // cross-fading keeps the avatar and title visually continuous instead of
      // blanking to nothing between the two.
      transitionType: ContainerTransitionType.fade,
      transitionDuration: Motion.container,
      // The child supplies its own gesture — see the class comment.
      tappable: false,
      closedElevation: 0,
      openElevation: 0,
      closedColor: closedColor ?? Colors.transparent,
      openColor: closedColor ?? Colors.transparent,
      middleColor: closedColor ?? Colors.transparent,
      closedShape: RoundedRectangleBorder(borderRadius: shape),
      onClosed: (_) => onClosed?.call(),
      openBuilder: (context, _) => openPage,
      closedBuilder: (context, openContainer) => button(() {
        onOpen?.call();
        openContainer();
      }),
    );
  }
}
