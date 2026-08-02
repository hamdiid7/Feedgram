import 'package:flutter/material.dart';

/// Motion vocabulary for the app.
///
/// Centralised for two reasons. First, the OS reduce-motion setting has to be
/// honoured everywhere or not at all — scattering the check across widgets is how
/// one animation gets missed. Second, this feed's animations run *during scroll*,
/// so their cost is not theoretical: anything here has to be cheap enough to
/// survive a fast flick through a hundred cards.
abstract final class Motion {
  /// M3 emphasised-decelerate. Fast out of the gate, gentle arrival — this is
  /// what makes entering content read as arriving rather than sliding.
  static const enter = Curves.easeOutCubic;

  /// Standard easing for state changes that are not entrances.
  static const standard = Curves.easeInOutCubicEmphasized;

  /// Feed items. Deliberately under the spec's 200 ms ceiling: a list item that
  /// takes longer than a scroll gesture feels laggy rather than animated.
  static const itemEnter = Duration(milliseconds: 180);

  /// Per-item delay in a staggered run.
  static const stagger = Duration(milliseconds: 28);

  /// The most items that stagger before the delay is capped.
  ///
  /// Without a cap, item 40 would wait over a second — and on a fast scroll it is
  /// already off-screen by then, so it would animate to nobody.
  static const maxStaggered = 6;

  static const fade = Duration(milliseconds: 220);
  static const bounce = Duration(milliseconds: 260);

  /// Container transform, opening a page from the thing you tapped.
  ///
  /// Long by list-item standards, and deliberately so: the transform is carrying
  /// the explanation of where the new screen came from, and at 200 ms the eye
  /// cannot follow the morph — it just flashes.
  static const container = Duration(milliseconds: 400);

  /// A bottom sheet sliding up.
  static const sheet = Duration(milliseconds: 300);

  /// Content growing or collapsing in place.
  static const expand = Duration(milliseconds: 425);

  /// Overshoot for something appearing from nothing. The 0.5 period is a soft
  /// bounce — enough to register, not enough to wobble.
  static const springIn = ElasticOutCurve(0.5);

  /// Deceleration for content sliding into position.
  static const slide = Curves.decelerate;

  /// Numbers counting to a new value. Almost all the distance is covered up
  /// front, so a large jump still settles quickly.
  static const count = Curves.easeOutQuint;

  /// Whether decorative animation should run at all.
  ///
  /// `MediaQuery.disableAnimations` is the OS accessibility switch. Motion that
  /// conveys *state* (a spinner) stays; motion that is purely decorative goes.
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);
}

/// Fades and lifts a feed item into place the first time it is built.
///
/// One-shot by design: it keys off first build, not every rebuild, so scrolling
/// back over an item does not replay it. That matters for the checkpoint —
/// re-animating on rebuild is exactly the thing that costs frames mid-scroll.
class FeedItemEntrance extends StatefulWidget {
  const FeedItemEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  /// Position in the list, used only to stagger the first screenful.
  final int index;

  final Widget child;

  @override
  State<FeedItemEntrance> createState() => _FeedItemEntranceState();
}

class _FeedItemEntranceState extends State<FeedItemEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.itemEnter,
  );

  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!Motion.enabled(context)) {
      _controller.value = 1;
      return;
    }

    // Only the first screenful staggers. Later items animate immediately, because
    // by the time they build the user is already scrolling and a delay just makes
    // the list feel unresponsive.
    final steps = widget.index.clamp(0, Motion.maxStaggered);
    final delay = Motion.stagger * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Motion.enter);

    return AnimatedBuilder(
      animation: curved,
      // The subtree is built once and reused across ticks — animating a whole
      // post card's widget tree every frame would be ruinous.
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A soft sweep over a loading placeholder, so pending reads as active.
///
/// Only paints while something is actually loading; a shimmer left running on
/// resolved content is a permanent repaint for no information.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didUpdateWidget(Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final shouldRun = widget.enabled && Motion.enabled(context);
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !Motion.enabled(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final t = _controller.value * 2 - 0.5;
          return LinearGradient(
            begin: Alignment(t - 0.6, -0.4),
            end: Alignment(t + 0.6, 0.4),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x22FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

/// Springs in from nothing, optionally after a delay.
///
/// For things that *arrive* — an empty-state icon, a badge — rather than things
/// that were always going to be there. The elastic overshoot is what separates
/// the two readings.
class ScaleIn extends StatefulWidget {
  const ScaleIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Motion.springIn,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final Duration delay;

  @override
  State<ScaleIn> createState() => _ScaleInState();
}

class _ScaleInState extends State<ScaleIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!Motion.enabled(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: widget.curve),
      child: widget.child,
    );
  }
}

/// Slides in from an edge while fading up.
///
/// Used for content that has a direction to come from — a sheet's body rising,
/// a header settling down — where a plain fade would lose that.
class SlideFadeIn extends StatefulWidget {
  const SlideFadeIn({
    super.key,
    required this.child,
    this.offset = const Offset(0, 0.35),
    this.duration = Motion.fade,
    this.curve = Motion.slide,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Starting displacement, as a fraction of the child's own size.
  final Offset offset;

  final Duration duration;
  final Curve curve;
  final Duration delay;

  @override
  State<SlideFadeIn> createState() => _SlideFadeInState();
}

class _SlideFadeInState extends State<SlideFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!Motion.enabled(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Grows or collapses a child in place, fading as it goes.
///
/// Preferred over swapping the child for a [SizedBox]: removing a widget makes
/// everything below it jump, and in a feed that means content moving under the
/// reader's finger.
class AnimatedExpanded extends StatelessWidget {
  const AnimatedExpanded({
    super.key,
    required this.child,
    required this.expand,
    this.duration = Motion.expand,
    this.curve = Curves.fastOutSlowIn,
    this.axis = Axis.vertical,
  });

  final Widget child;
  final bool expand;
  final Duration duration;
  final Curve curve;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (!Motion.enabled(context)) {
      return expand ? child : const SizedBox.shrink();
    }

    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: AnimatedOpacity(
        duration: duration,
        curve: Curves.easeInOut,
        opacity: expand ? 1 : 0,
        child: expand
            ? child
            : SizedBox(
                width: axis == Axis.horizontal ? 0 : null,
                height: axis == Axis.vertical ? 0 : null,
              ),
      ),
    );
  }
}

/// Cross-fades between children *and* animates the size change.
///
/// A bare [AnimatedSwitcher] cross-fades two differently-sized children inside a
/// box that snaps to the new size on the first frame, so the layout jumps while
/// the fade is still running. Wrapping it in [AnimatedSize] makes the two agree.
class AnimatedSizeSwitcher extends StatelessWidget {
  const AnimatedSizeSwitcher({
    super.key,
    required this.child,
    this.sizeDuration = const Duration(milliseconds: 500),
    this.switchDuration = const Duration(milliseconds: 250),
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final Duration sizeDuration;
  final Duration switchDuration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!Motion.enabled(context)) return child;

    return AnimatedSize(
      duration: sizeDuration,
      curve: Motion.standard,
      alignment: alignment,
      clipBehavior: Clip.hardEdge,
      child: AnimatedSwitcher(duration: switchDuration, child: child),
    );
  }
}

/// Holds at zero for the first [delayFraction] of its span, then runs [inner].
///
/// For staggering *within* one controller instead of spawning a second — a
/// delayed [Future] cannot be driven backwards when the animation reverses,
/// which is how a half-open sheet ends up with content stuck invisible.
class DelayedCurve extends Curve {
  const DelayedCurve({this.delayFraction = 0.25, this.inner = Curves.easeInOut});

  final double delayFraction;
  final Curve inner;

  @override
  double transformInternal(double t) => t < delayFraction
      ? 0
      : inner.transform((t - delayFraction) / (1 - delayFraction));
}

/// Scale-bounce for a tapped control, e.g. a reaction.
class TapBounce extends StatefulWidget {
  const TapBounce({super.key, required this.child, required this.active});

  final Widget child;

  /// Bounces on the transition into `true`, so liking pops and unliking does not.
  final bool active;

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.bounce,
    value: 1,
  );

  @override
  void didUpdateWidget(TapBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && Motion.enabled(context)) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      // Overshoots past 1 and settles — a plain ease would read as a resize.
      scale: Tween(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
      ),
      child: widget.child,
    );
  }
}
