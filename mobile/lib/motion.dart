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

class MotionDistance {
  static const micro = 4.0;
  static const small = 6.0;
  static const base = 8.0;
  static const medium = 12.0;
  static const large = 30.0;
}

class MotionScale {
  static const large = 0.96;
  static const medium = 0.97;
  static const small = 0.98;
  static const tiny = 0.99;
}

/// Smooth page slide + fade, using the page side-by-side tokens.
/// Forward navigation rises slightly; the reverse mirrors it.
Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionDuration.fast,
    reverseTransitionDuration: MotionDuration.quick,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: MotionCurve.smoothOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, MotionDistance.base / 100),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
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

/// Number pop-in: re-enters the value with a blurred slide whenever it changes.
class PopInValue extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MotionDuration.verySlow,
      switchInCurve: MotionCurve.digit,
      switchOutCurve: MotionCurve.smoothOut,
      transitionBuilder: (child, animation) {
        final curved =
            CurvedAnimation(parent: animation, curve: MotionCurve.digit);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, MotionDistance.base / 100),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: Text(
        value,
        key: ValueKey(value),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
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
