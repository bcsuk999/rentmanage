import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'app_theme.dart';
import 'motion.dart';

/// A single label/value row on a success screen.
class SuccessDetail {
  const SuccessDetail({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;
}

/// One filled primary action, outlined secondary actions, and a text-only way
/// out — with the same styling on every success screen.
enum SuccessActionStyle { filled, outlined, text }

class SuccessAction {
  const SuccessAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style = SuccessActionStyle.outlined,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final SuccessActionStyle style;
}

/// Compact confirmation layout: the Lottie check plays first, then the outcome,
/// a one-line next step and the details card fade in. Everything is sized to
/// stay within the viewport; no scrolling on a normal phone screen.
class SuccessView extends StatelessWidget {
  const SuccessView({
    super.key,
    required this.title,
    required this.message,
    required this.details,
    this.detailsTitle = 'Details',
    this.nextStep,
    this.animationAsset = 'assets/success.json',
  });

  final String title;
  final String message;
  final List<SuccessDetail> details;
  final String detailsTitle;
  final String? nextStep;
  final String animationAsset;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // The panel is centred above the sticky action bar, so size the animation
    // from the screen height instead of an unbounded scroll viewport.
    final available = MediaQuery.sizeOf(context).height - 150;
    final animationSize = available < 430
        ? 76.0
        : available < 540
        ? 96.0
        : 116.0;
    final showNext = nextStep != null && available >= 470;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Semantics(
            label: 'Success',
            container: true,
            child: _SuccessAnimation(
              asset: animationAsset,
              reduceMotion: reduceMotion,
              size: animationSize,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _reveal(
          context,
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.mainText,
              ),
            ),
          ),
          const Duration(milliseconds: 450),
        ),
        const SizedBox(height: 4),
        _reveal(
          context,
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: AppColors.secondaryText,
            ),
          ),
          const Duration(milliseconds: 550),
        ),
        if (showNext) ...[
          const SizedBox(height: 10),
          _reveal(
            context,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Next: $nextStep',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
            const Duration(milliseconds: 650),
          ),
        ],
        const SizedBox(height: 12),
        if (details.isNotEmpty)
          _reveal(
            context,
            Card(
              surfaceTintColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      detailsTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < details.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            if (details[i].icon != null) ...[
                              Icon(
                                details[i].icon,
                                size: 15,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                details[i].label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                details[i].value,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.mainText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Duration(milliseconds: 750),
          ),
      ],
    );
  }

  /// Reduced-motion users get the content immediately, without the stagger.
  Widget _reveal(BuildContext context, Widget child, Duration delay) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return Reveal(delay: delay, child: child);
  }
}

class _SuccessAnimation extends StatelessWidget {
  const _SuccessAnimation({
    required this.asset,
    required this.reduceMotion,
    required this.size,
  });

  final String asset;
  final bool reduceMotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.successSoft.withValues(alpha: 0.5),
      ),
      alignment: Alignment.center,
      child: reduceMotion
          ? Icon(
              Icons.check_circle_rounded,
              size: size * 0.62,
              color: AppColors.success,
            )
          : Lottie.asset(asset, fit: BoxFit.contain, repeat: false),
    );
  }
}

/// All actions sit in one compact row at the bottom: the primary gets a
/// slightly wider share, then the outlined and text actions.
class SuccessActions extends StatelessWidget {
  const SuccessActions({super.key, required this.actions});

  final List<SuccessAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.mainText.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: actions[i].style == SuccessActionStyle.filled ? 3 : 2,
                    child: _SuccessButton(action: actions[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-page confirmation shell used by every saved form: no title bar, a
/// floating back arrow at the top-left, compact content and one action row
/// pinned to the bottom.
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({
    super.key,
    required this.title,
    required this.message,
    required this.details,
    required this.actions,
    required this.onBack,
    this.detailsTitle = 'Details',
    this.nextStep,
  });

  final String title;
  final String message;
  final List<SuccessDetail> details;
  final List<SuccessAction> actions;
  final VoidCallback onBack;
  final String detailsTitle;
  final String? nextStep;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Centred white panel: it floats above the action bar with a soft
          // bottom shadow so the confirmation reads as one focused card.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 52, 16, 16),
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.mainText.withValues(
                                  alpha: 0.10,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: SuccessView(
                            title: title,
                            message: message,
                            details: details,
                            detailsTitle: detailsTitle,
                            nextStep: nextStep,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Back arrow keeps the same inset as the panel, with a circular
          // white surface so it stays legible over any content.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PressScale(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.mainText.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: onBack,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SuccessActions(actions: actions),
    );
  }
}

class _SuccessButton extends StatelessWidget {
  const _SuccessButton({required this.action});

  final SuccessAction action;

  @override
  Widget build(BuildContext context) {
    switch (action.style) {
      case SuccessActionStyle.filled:
        return PressScale(
          child: FilledButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 15),
            label: Text(
              action.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      case SuccessActionStyle.outlined:
        return PressScale(
          child: OutlinedButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 15),
            label: Text(
              action.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              // Neutral styling keeps the filled primary as the only accent.
              foregroundColor: AppColors.mainText,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      case SuccessActionStyle.text:
        return PressScale(
          child: TextButton.icon(
            onPressed: action.onPressed,
            icon: Icon(action.icon, size: 14),
            label: Text(
              action.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                decoration: TextDecoration.underline,
                decorationThickness: 1.2,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryText,
              padding: const EdgeInsets.symmetric(horizontal: 2),
            ),
          ),
        );
    }
  }
}
