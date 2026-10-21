import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'motion.dart';
import 'status_colors.dart';

/// Shared PRD components: pills, progress, skeletons, state panels, toasts.

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.text,
    required this.color,
    required this.soft,
  });

  final String text;
  final Color color;
  final Color soft;

  factory StatusPill.member(String status) => StatusPill(
        text: displayStatus(status),
        color: memberStatusColor(status),
        soft: memberStatusSoft(status),
      );

  factory StatusPill.room(String status) => StatusPill(
        text: status,
        color: roomStatusColor(status),
        soft: roomStatusSoft(status),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class ThinProgress extends StatelessWidget {
  const ThinProgress({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 6,
        color: color,
        backgroundColor: AppColors.border,
      ),
    );
  }
}

/// Compact member rent row used on room cards and detail screens.
/// A single customer row in the Khata-style list: soft initial avatar, name with
/// a quiet meta line, and the balance pinned right with a small caption above it.
///
/// Deliberately has no background or border of its own — the caller supplies the
/// white surface and the hairline dividers, so a group of rows reads as one list
/// (rooms) or as a standalone ledger (room details) without changing the widget.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.name,
    required this.status,
    required this.rent,
    required this.paid,
    required this.pending,
    this.subtitle,
    this.dueDate,
    this.onTap,
  });

  final String name;
  final String status;
  final double rent;
  final double paid;
  final double pending;
  final String? subtitle;
  final DateTime? dueDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = memberStatusColor(status);
    final empty = rent <= 0 && paid <= 0 && pending <= 0;
    final amountColor = empty
        ? AppColors.secondaryText
        : (pending > 0 ? color : AppColors.success);
    final caption = empty
        ? 'No period'
        : (pending <= 0 ? '' : displayStatus(status));
    // No "paid of rent" line: the amount on the right already says what is
    // owed, so the row keeps only the phone number (when given) and the date.
    final meta = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (empty) 'No rent period this month',
    ].join(' · ');

    return PressScale(
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.skySoft,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.sky,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.mainText,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondaryText,
                          fontSize: 10.5,
                          height: 1.15,
                        ),
                      ),
                    if (dueDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Due date : ${fmtDateMedium(dueDate!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondaryText,
                          fontSize: 9.5,
                          height: 1.15,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (caption.isNotEmpty) ...[
                    Text(
                      caption,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondaryText,
                        fontSize: 9.5,
                        height: 1.1,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                  ],
                  Text(
                    empty
                        ? '—'
                        : (pending <= 0 ? 'Paid' : inr(pending)),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.secondaryText,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryMetric extends StatelessWidget {
  const SummaryMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  /// Small corner icon with lighter, tighter text (home page tiles).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: PopInValue(
            value: value,
            style: (compact
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.titleSmall)
                ?.copyWith(
              fontWeight: compact ? FontWeight.w500 : FontWeight.w800,
              fontSize: compact ? 14 : null,
              color: AppColors.mainText,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondaryText,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );

    if (!compact) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                // Value + label centred on both axes inside the card.
                child: text,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              child: Icon(icon, size: 20, color: color),
            ),
            Center(child: text),
          ],
        ),
      ),
    );
  }
}

class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.radius = 12,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final x = -1.5 + _c.value * 3;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [
                    AppColors.skeleton,
                    Color(0xFFF1F4FA),
                    AppColors.skeleton,
                  ],
                  stops: const [0.15, 0.5, 0.85],
                  begin: Alignment(x, 0),
                  end: Alignment(x + 1, 0),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Rooms-shaped loading placeholders (no layout shift vs real content).
class SkeletonRooms extends StatelessWidget {
  const SkeletonRooms({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBlock(height: 48),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBlock(height: 96)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBlock(height: 96)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBlock(height: 96)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBlock(height: 96)),
          ],
        ),
        SizedBox(height: 12),
        SkeletonBlock(height: 150),
        SizedBox(height: 12),
        SkeletonBlock(height: 150),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.meeting_room_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              PressScale(
                enabled: onAction != null,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.message,
    required this.onRetry,
    this.onUseCached,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onUseCached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_outlined,
                size: 36,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Connection Error',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            PressScale(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
            if (onUseCached != null) ...[
              const SizedBox(height: 8),
              PressScale(
                child: OutlinedButton(
                  onPressed: onUseCached,
                  child: const Text('Use Cached Data'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// App-wide toast. It paints above the navigator (see [TopToastHost] in
/// main.dart), so a message raised on any page — including sign-in — drops in
/// from the top of the screen instead of appearing under the page chrome.
class _Toast {
  const _Toast({
    required this.message,
    required this.error,
    required this.seq,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool error;
  final int seq;
  final String? actionLabel;
  final VoidCallback? onAction;
}

final ValueNotifier<_Toast?> _toast = ValueNotifier<_Toast?>(null);
int _toastSeq = 0;

void _showToast(
  BuildContext context,
  String message, {
  required bool error,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _toast.value = _Toast(
    message: message,
    error: error,
    seq: ++_toastSeq,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Green success toast, only after server-confirmed writes.
void toastOk(BuildContext context, String message) {
  _showToast(context, message, error: false);
}

/// Red toast for failed requests and blocked actions.
void toastError(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _showToast(
    context,
    message,
    error: true,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Sits above the app's navigator and renders the current toast as a black
/// banner that slides and fades in from the top, then fades out again.
class TopToastHost extends StatefulWidget {
  const TopToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<TopToastHost> createState() => _TopToastHostState();
}

class _TopToastHostState extends State<TopToastHost> {
  Timer? _hideTimer;
  _Toast? _visible;

  @override
  void initState() {
    super.initState();
    _toast.addListener(_onToast);
  }

  void _onToast() {
    final next = _toast.value;
    if (next == null) return;
    _hideTimer?.cancel();
    setState(() => _visible = next);
    _hideTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _visible = null);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _toast.removeListener(_onToast);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = _visible;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: MotionDuration.fast,
              switchInCurve: MotionCurve.smoothOut,
              switchOutCurve: MotionCurve.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.45),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: toast == null
                  ? const SizedBox.shrink()
                  : _ToastBanner(key: ValueKey(toast.seq), toast: toast),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastBanner extends StatelessWidget {
  const _ToastBanner({super.key, required this.toast});

  final _Toast toast;

  @override
  Widget build(BuildContext context) {
    final tint = toast.error
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF4ADE80);
    // Material gives the banner text a proper ancestor (no debug yellow
    // underline) and paints the full-width black band flush with the top edge.
    return Material(
      color: const Color(0xF2000000),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  toast.error
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: tint,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    toast.message,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tint,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                if (toast.actionLabel != null) const SizedBox(width: 8),
                if (toast.actionLabel != null)
                  TextButton(
                    onPressed: toast.onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: tint,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      toast.actionLabel!,
                      style: TextStyle(
                        color: tint,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
