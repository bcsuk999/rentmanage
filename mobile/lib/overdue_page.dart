import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'payment_sheet.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Overdue tab: red summary, days-overdue buckets, per-period quick payment.
class OverduePage extends StatefulWidget {
  const OverduePage({
    super.key,
    required this.api,
    required this.isAdmin,
    required this.onAuthExpired,
    this.initialReport,
    this.onLoaded,
  });

  final ApiClient api;
  final bool isAdmin;
  final VoidCallback onAuthExpired;

  /// Last known report, shown instantly so the skeleton only ever appears on
  /// the very first load.
  final OverdueReport? initialReport;

  /// Called with fresh data after every successful background fetch so the
  /// parent can cache it for the next visit.
  final ValueChanged<OverdueReport>? onLoaded;

  @override
  State<OverduePage> createState() => _OverduePageState();
}

class _OverduePageState extends State<OverduePage> {
  OverdueReport? _report;
  Object? _error;
  bool _loading = false;
  String _bucket = 'All';

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport;
    // Skeleton only when there is nothing cached to show yet.
    _loading = _report == null;
    _load();
  }

  Future<OverdueReport> _fetch() async {
    try {
      return await widget.api.overdue();
    } on ApiException catch (e) {
      if (e.statusCode == 401) widget.onAuthExpired();
      rethrow;
    }
  }

  /// Fetches fresh data. When a report is already on screen this is silent:
  /// no skeleton, no spinner, just an in-place swap once the data arrives.
  Future<void> _load() async {
    try {
      final report = await _fetch();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _error = null;
      });
      widget.onLoaded?.call(report);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() {
        _loading = false;
        if (_report == null) _error = e;
      });
      if (_report != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline — showing saved overdue data.')),
        );
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
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
    if (recorded && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final report = _report;
    if (report == null) {
      if (_loading) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Row(
              children: [
                Expanded(child: SkeletonBlock(height: 64)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBlock(height: 64)),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBlock(height: 120),
            SizedBox(height: 12),
            SkeletonBlock(height: 120),
          ],
        );
      }
      if (_error != null) {
        final message = _error is ApiException
            ? (_error as ApiException).message
            : 'Unable to load the latest data. Check your internet connection and try again.';
        return ListView(
          children: [ErrorPanel(message: message, onRetry: _retry)],
        );
      }
      return const SizedBox.shrink();
    }
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCards(context, report),
                _bucketRow(context),
                for (final m in members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OverdueCard(
                      member: m,
                      days: _daysOverdue(m),
                      isAdmin: widget.isAdmin,
                      onRecord: _record,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCards(BuildContext context, OverdueReport report) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
        children: [
          SummaryMetric(
            icon: Icons.error_outline,
            value: inr(report.totalOverdue),
            label: 'Total overdue',
            color: AppColors.danger,
          ),
          SummaryMetric(
            icon: Icons.people_outline,
            value: '${report.memberCount}',
            label: 'Overdue members',
            color: AppColors.danger,
          ),
        ],
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

class _OverdueCard extends StatefulWidget {
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
  State<_OverdueCard> createState() => _OverdueCardState();
}

class _OverdueCardState extends State<_OverdueCard> {
  bool _expanded = false;

  OverdueMember get member => widget.member;
  int get days => widget.days;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget detail(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondaryText)),
              ),
              Text(':',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ribbon sits flush against the card's top-left corner.
            Row(
              children: [
                // Expanded (not Flexible + Spacer) so the ribbon slot takes all
            // the leftover width and the amount stays pinned to the right edge.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.danger,
                        AppColors.danger.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Text(
                    member.name.isEmpty ? '?' : member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Overdue :',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    inr(member.totalOverdue),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Room ${member.roomNumber} · $days day${days == 1 ? '' : 's'} overdue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondaryText),
                        ),
                      ),
                      IconButton(
                        tooltip: _expanded ? 'Hide details' : 'Show details',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: AppColors.secondaryText,
                        ),
                        onPressed: _toggle,
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    detail('Room', member.roomNumber),
                    if (member.mobile.isNotEmpty) detail('Phone', member.mobile),
                    detail('Days overdue', '$days day${days == 1 ? '' : 's'}'),
                    const SizedBox(height: 6),
                    for (final p in member.periods)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined,
                                    size: 16, color: AppColors.secondaryText),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${p.start == null ? '?' : fmtDateShort(p.start!)} – ${p.end == null ? '?' : fmtDateShort(p.end!)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  inr(p.pending),
                                  style: const TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (widget.isAdmin && p.pending > 0)
                                  TextButton(
                                    onPressed: () => widget.onRecord(member, p),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: const Size(0, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Record'),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 22),
                              child: Text(
                                'Rent ${inr(p.rent)} · Paid ${inr(p.paid)}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.secondaryText),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
