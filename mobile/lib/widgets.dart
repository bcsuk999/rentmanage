import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'status_colors.dart';

/// Shared PRD components: pills, progress, skeletons, state panels, toasts.

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color, required this.soft});

  final String text;
  final Color color;
  final Color soft;

  factory StatusPill.member(String status) => StatusPill(
        text: status,
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
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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
    final overdue = isOverdueStatus(status);
    final progress = rent <= 0 ? 0.0 : (paid / rent).clamp(0.0, 1.0);
    final empty = rent <= 0 && paid <= 0 && pending <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: overdue ? AppColors.danger : AppColors.border,
          width: overdue ? 1.5 : 1,
        ),
        boxShadow: memberGlow(status),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: memberStatusSoft(status),
                  child: Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.secondaryText)),
                    ],
                  ),
                ),
                StatusPill.member(status),
              ],
            ),
            const SizedBox(height: 8),
            ThinProgress(value: progress, color: color),
            const SizedBox(height: 6),
            if (empty)
              Text('No rent period for this month yet.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText))
            else
              Row(
                children: [
                  Expanded(
                    child: Text('${inr(paid)} of ${inr(rent)} paid',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondaryText)),
                  ),
                  if (dueDate != null)
                    Text('Due ${fmtDateShort(dueDate!)} · ',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondaryText)),
                  Text('${inr(pending)} due',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class SummaryMetric extends StatelessWidget {
  const SummaryMetric(
      {super.key, required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: AppColors.mainText)),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondaryText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, required this.height, this.width = double.infinity, this.radius = 12});

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(color: AppColors.skeleton, borderRadius: BorderRadius.circular(radius)),
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
  const EmptyPanel(
      {super.key, required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

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
              child: const Icon(Icons.meeting_room_outlined, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry, this.onUseCached});

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
              child: const Icon(Icons.wifi_off_outlined, size: 36, color: AppColors.danger),
            ),
            const SizedBox(height: 14),
            Text('Connection Error',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            if (onUseCached != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onUseCached,
                child: const Text('Use Cached Data'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Short green success toast, only after server-confirmed writes.
void toastOk(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 2),
    ),
  );
}
