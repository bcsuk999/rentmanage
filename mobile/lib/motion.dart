import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Motion system for the app, mirroring the transitions.dev motion tokens
/// (https://transitions.dev). Durations, easings, distances and scales are
/// named semantically so every animation in the app reads from one scale.
class MotionDuration {
  /// Per-item stagger offset.
  static const stagger = Duration(milliseconds: 40);

  /// Shake segment, large stagger.
  static const micro = Duration(milliseconds: 80);

  /// Modal/dropdown close, text swap, tooltip appear.
  static const quick = Duration(milliseconds: 150);

  /// Icon swap, dropdown/modal open, tabs sliding, page slide.
  static const fast = Duration(milliseconds: 250);

  /// Panel close, toast close.
  static const medium = Duration(milliseconds: 350);

  /// Panel open, skeleton content reveal, input clear.
  static const slow = Duration(milliseconds: 400);

  /// Emphasis moments, badge appear, text reveal, success check.
  static const verySlow = Duration(milliseconds: 500);

  /// Push: the incoming page travels the full viewport width.
  static const page = Duration(milliseconds: 320);

  /// Pop: the reverse is a touch quicker so back feels immediate.
  static const pageReverse = Duration(milliseconds: 280);
}

class MotionCurve {
  /// Modal/dropdown/panel open + close, page slide, resize.
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);
  static const easeInOut = Curves.easeInOut;
  static const easeOut = Curves.easeOut;
  static const linear = Curves.linear;

  /// Badge pop open.
  static const bounce = Cubic(0.34, 1.36, 0.64, 1);

  /// Bouncy hover-out (avatar return).
  static const bounceStrong = Cubic(0.34, 3.85, 0.64, 1);

  /// Number pop-in.
  static const digit = Cubic(0.34, 1.45, 0.64, 1);

  /// Success check bob.
  static const checkBob = Cubic(0.34, 1.35, 0.64, 1);
}

/// Spacing/travel distances used by the transitions below.
class MotionDistance {
  static const micro = 4.0;
  static const small = 6.0;
  static const base = 8.0;
  static const medium = 12.0;
  static const large = 30.0;
}

/// The app's page transition: a full-width side-by-side slide taken from the
/// reference app. The incoming page enters from the right while the page below
/// it is pushed left on the same curve, so the two read as one continuous
/// strip - exactly like the dashboard's tab band. Reduced-motion users get the
/// plain child with no travel.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _buildMotionPageTransition(context, animation, secondaryAnimation, child);
}

Widget _buildMotionPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

  // Curves are chained onto the tweens instead of wrapping the routes'
  // animations in a CurvedAnimation: the transitions builder runs every frame,
  // and a CurvedAnimation registers a status listener on its parent in its
  // constructor and only removes it in dispose(), so wrapping here would leak
  // one listener per frame for the life of the route.
  final curve = CurveTween(curve: MotionCurve.smoothOut);
  final outgoingSlide = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-1, 0),
  ).chain(curve).animate(secondaryAnimation);
  final incomingSlide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(curve).animate(animation);

  return SlideTransition(
    // The page being covered rides out to the left.
    position: outgoingSlide,
    child: SlideTransition(
      // The page being revealed enters from the right.
      position: incomingSlide,
      child: child,
    ),
  );
}

/// Explicit route using the same motion as [MotionPageTransitionsBuilder].
/// Push and pop get their own durations so going back never feels sluggish.
Route<T> smoothRoute<T>(Widget page, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: MotionDuration.page,
    reverseTransitionDuration: MotionDuration.pageReverse,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _buildMotionPageTransition(
      context,
      animation,
      secondaryAnimation,
      child,
    ),
  );
}

/// Staggered blurred rise for stacked items (list rows, cards, sections).
/// Wrap each item and give it an incremental [delay].
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = MotionDistance.medium,
    this.blur = 0,
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final double blur;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _blur;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: MotionDuration.verySlow,
    );
    final curved =
        CurvedAnimation(parent: _c, curve: MotionCurve.smoothOut);
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offset / 100),
      end: Offset.zero,
    ).animate(curved);
    _blur = Tween<double>(begin: widget.blur, end: 0)
        .animate(CurvedAnimation(parent: _c, curve: MotionCurve.easeInOut));
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SlideTransition(
      position: _slide,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
    if (widget.blur > 0) {
      child = AnimatedBuilder(
        animation: _blur,
        child: child,
        builder: (context, inner) => ImageFiltered(
          imageFilter:
              ui.ImageFilter.blur(sigmaX: _blur.value, sigmaY: _blur.value),
          child: inner,
        ),
      );
    }
    return child;
  }
}

/// Replays a horizontal shake whenever [trigger] changes, used for
/// form validation feedback (error state shake).
class ShakeOnError extends StatefulWidget {
  const ShakeOnError({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _x;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: MotionDuration.medium);
    _x = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -MotionDistance.small), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -MotionDistance.small, end: MotionDistance.small), weight: 2),
      TweenSequenceItem(tween: Tween(begin: MotionDistance.small, end: -MotionDistance.micro), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -MotionDistance.micro, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _c, curve: MotionCurve.smoothOut));
  }

  @override
  void didUpdateWidget(covariant ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger != null) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _x,
      builder: (context, child) => Transform.translate(
        offset: Offset(_x.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Number pop-in: the old value disappears at once and the new one scales in
/// from 80% to full size whenever it changes.
class PopInValue extends StatefulWidget {
  const PopInValue({
    super.key,
    required this.value,
    this.style,
    this.textAlign,
    this.maxLines = 1,
  });

  final String value;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;

  @override
  State<PopInValue> createState() => _PopInValueState();
}

class _PopInValueState extends State<PopInValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: MotionDuration.verySlow,
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.8, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: MotionCurve.smoothOut));

  late final Animation<double> _opacity =
      CurvedAnimation(parent: _c, curve: MotionCurve.easeOut);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(covariant PopInValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Text(
          widget.value,
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Text states swap: cross-blur in place when the label changes.
class SwapText extends StatelessWidget {
  const SwapText(this.value, {super.key, this.style, this.textAlign});

  final String value;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MotionDuration.quick,
      switchInCurve: MotionCurve.easeInOut,
      switchOutCurve: MotionCurve.easeInOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, MotionDistance.micro / 100),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(value,
          key: ValueKey(value),
          style: style,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }
}
