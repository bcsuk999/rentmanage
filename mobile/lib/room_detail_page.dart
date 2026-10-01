import 'package:flutter/material.dart';

import 'api.dart';
import 'member_form_page.dart';
import 'payment_sheet.dart';
import 'status_colors.dart';

/// Full room details: header totals, per-member rent rows, vacated history.
class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({
    super.key,
    required this.api,
    required this.roomId,
    required this.roomNumber,
    required this.isAdmin,
  });

  final ApiClient api;
  final String roomId;
  final String roomNumber;
  final bool isAdmin;

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  late Future<RoomDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.roomDetail(widget.roomId);
  }

  Future<void> _refresh() async {
    final detail = await widget.api.roomDetail(widget.roomId);
    if (mounted) setState(() => _future = Future.value(detail));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Room ${widget.roomNumber}')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<RoomDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load room details.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton(
                      onPressed: () => setState(() => _future = widget.api.roomDetail(widget.roomId)),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final detail = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SummaryCard(detail: detail),
                const SizedBox(height: 12),
                Text('Members (${detail.rows.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (detail.rows.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No active members.'))),
                for (final row in detail.rows) ...[
                  MemberTile(
                    name: row.name,
                    status: row.status,
                    rent: row.rent,
                    paid: row.paid,
                    pending: row.pending,
                    subtitle: row.mobile,
                  ),
                  const SizedBox(height: 8),
                ],
                if (detail.historical.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Vacated (${detail.historical.length})', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final h in detail.historical)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history_outlined),
                            title: Text(h.name),
                            subtitle: Text(h.mobile),
                            trailing: Text(h.vacatedOn, style: Theme.of(context).textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = roomStatusColor(detail.room.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Room ${detail.room.roomNumber}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(detail.room.status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${detail.memberCount}/${detail.capacity} occupied',
                style: theme.textTheme.titleMedium),
            if (detail.isFull)
              const Text('Full', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(label: 'Rent', value: inr(detail.totalRent)),
                _Stat(label: 'Paid', value: inr(detail.totalPaid), color: Colors.green.shade700),
                _Stat(label: 'Due', value: inr(detail.totalPending), color: Colors.red.shade700),
              ],
            ),
            if (detail.paymentState.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail.paymentState, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// Shared member row: colored name, status pill, rent progress bar, amounts.
/// Overdue rows get a glowing red border.
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.name,
    required this.status,
    required this.rent,
    required this.paid,
    required this.pending,
    this.subtitle,
  });

  final String name;
  final String status;
  final double rent;
  final double paid;
  final double pending;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = memberStatusColor(status);
    final overdue = isOverdueStatus(status);
    final progress = rent <= 0 ? 0.0 : (paid / rent).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue ? Colors.red.shade600 : theme.dividerColor,
          width: overdue ? 1.6 : 1,
        ),
        boxShadow: memberGlow(status),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(status,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: color,
              backgroundColor: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text('${inr(paid)} of ${inr(rent)} paid · ${inr(pending)} due',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
