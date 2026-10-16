import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'payment_sheet.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Overdue tab: red summary, days-overdue buckets, per-period quick payment.
class OverduePage extends StatefulWidget {
  const OverduePage({super.key, required this.api, required this.isAdmin, required this.onAuthExpired});

  final ApiClient api;
  final bool isAdmin;
  final VoidCallback onAuthExpired;

  @override
  State<OverduePage> createState() => _OverduePageState();
}

class _OverduePageState extends State<OverduePage> {
  late Future<OverdueReport> _future;
  String _bucket = 'All';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OverdueReport> _load() async {
    try {
      return await widget.api.overdue();
    } on ApiException catch (e) {
      if (e.statusCode == 401) widget.onAuthExpired();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    try {
      final report = await _load();
      if (mounted) setState(() => _future = Future.value(report));
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() => _future = Future.error(e));
    }
  }

  /// Days since the member's earliest overdue period ended.
  int _daysOverdue(OverdueMember m) {
    DateTime? earliest;
    for (final p in m.periods) {
      final end = p.end;
      if (end == null) continue;
      if (earliest == null || end.isBefore(earliest)) earliest = end;
    }
    if (earliest == null) return 0;
    final now = DateTime.now();
    final days = now.difference(DateTime(earliest.year, earliest.month, earliest.day)).inDays;
    return days < 0 ? 0 : days;
  }

  bool _inBucket(OverdueMember m) {
    final d = _daysOverdue(m);
    switch (_bucket) {
      case '1–7 days':
        return d >= 1 && d <= 7;
      case '8–30 days':
        return d >= 8 && d <= 30;
      case '30+ days':
        return d > 30;
      default:
        return true;
    }
  }

  Future<void> _record(OverdueMember m, OverduePeriod p) async {
    // Fetch member's periods to calculate current due (non-overdue periods)
    double totalCurrentDue = 0;
    try {
      final periods = await widget.api.memberPeriods(m.memberId);
      if (!mounted) return;
      final now = DateTime.now();
      for (final period in periods) {
        if (period.pending <= 0) continue;
        final periodEnd = DateTime.tryParse(period.endIso);
        if (periodEnd != null && !periodEnd.isBefore(now)) {
          totalCurrentDue += period.pending;
        }
      }
    } catch (_) {
      // If fetch fails, default to 0
    }
    if (!mounted) return;

    final recorded = await showPaymentSheet(
      context,
      api: widget.api,
      rentPeriodId: p.id,
      memberName: m.name,
      pending: p.pending,
      totalOverdue: m.totalOverdue,
      totalCurrentDue: totalCurrentDue,
      periodStart: p.start,
      periodEnd: p.end,
    );
    if (recorded && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<OverdueReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonBlock(height: 96),
                SizedBox(height: 12),
                SkeletonBlock(height: 120),
                SizedBox(height: 12),
                SkeletonBlock(height: 120),
              ],
            );
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Unable to load the latest data. Check your internet connection and try again.';
            return ListView(
              children: [ErrorPanel(message: message, onRetry: _refresh)],
            );
          }
          final report = snapshot.data!;
          if (report.members.isEmpty) {
            return ListView(
              children: const [
                EmptyPanel(
                  icon: Icons.check_circle_outline,
                  title: 'No overdue rent',
                  body: 'Nothing is past its due date. All clear!',
                ),
              ],
            );
          }
          final members = report.members.where(_inBucket).toList();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: members.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) return _summaryCard(context, report);
              if (index == 1) return _bucketRow(context);
              return _OverdueCard(
                member: members[index - 2],
                days: _daysOverdue(members[index - 2]),
                isAdmin: widget.isAdmin,
                onRecord: _record,
              );
            },
          );
        },
      ),
    );
  }

  Widget _summaryCard(BuildContext context, OverdueReport report) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.dangerSoft.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inr(report.totalOverdue),
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.danger)),
                    Text(
                        '${report.memberCount} member${report.memberCount == 1 ? '' : 's'} overdue',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondaryText)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bucketRow(BuildContext context) {
    const buckets = ['All', '1–7 days', '8–30 days', '30+ days'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final b in buckets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(b),
                  selected: _bucket == b,
                  onSelected: (_) => setState(() => _bucket = b),
                  selectedColor: AppColors.danger.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.danger,
                  labelStyle: TextStyle(
                    color: _bucket == b ? AppColors.danger : AppColors.secondaryText,
                    fontWeight: _bucket == b ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: _bucket == b ? AppColors.danger : AppColors.border,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  const _OverdueCard({
    required this.member,
    required this.days,
    required this.isAdmin,
    required this.onRecord,
  });

  final OverdueMember member;
  final int days;
  final bool isAdmin;
  final Future<void> Function(OverdueMember m, OverduePeriod p) onRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: AppColors.dangerSoft,
          child: Text(
            member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Room ${member.roomNumber} · ${member.mobile}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              inr(member.totalOverdue),
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w800),
            ),
            Text('$days day${days == 1 ? '' : 's'} overdue',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondaryText, fontSize: 11)),
          ],
        ),
        children: [
          for (final p in member.periods)
            ListTile(
              dense: true,
              leading: const Icon(Icons.calendar_month_outlined,
                  color: AppColors.secondaryText),
              title: Text(
                  '${p.start == null ? '?' : fmtDateShort(p.start!)} – ${p.end == null ? '?' : fmtDateShort(p.end!)}'),
              subtitle: Text(
                  'Rent ${inr(p.rent)} · Paid ${inr(p.paid)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    inr(p.pending),
                    style: const TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.w700),
                  ),
                  if (isAdmin && p.pending > 0)
                    TextButton(
                      onPressed: () => onRecord(member, p),
                      child: const Text('Record'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
