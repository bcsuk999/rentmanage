import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_form_page.dart';
import 'payment_history_page.dart';
import 'payment_sheet.dart';
import 'record_payment_page.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Room Details: month switcher, overview, financial cards, and
/// Members / History / Info tabs with bottom record/add actions.
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
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    _future = widget.api.roomDetail(widget.roomId);
  }

  Future<void> _refresh() async {
    final detail = await widget.api.roomDetail(widget.roomId, from: _from, to: _to);
    if (mounted) setState(() => _future = Future.value(detail));
  }

  void _selectRange(DateRange range) {
    setState(() {
      _from = toDateOnlyIso(range.startIso);
      _to = toDateOnlyIso(range.endIso);
      _future = widget.api.roomDetail(widget.roomId, from: _from, to: _to);
    });
  }

  Future<void> _openAddMember() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemberFormPage(
          api: widget.api,
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
        ),
      ),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _openPayment(RoomDetailRow row) async {
    if (row.periodId == null) return;
    final recorded = await showPaymentSheet(
      context,
      api: widget.api,
      rentPeriodId: row.periodId!,
      memberName: row.name,
      pending: row.pending,
      periodStart: row.periodStart,
      periodEnd: row.periodEnd,
    );
    if (recorded && mounted) _refresh();
  }

  Future<void> _openRecordFlow(RoomDetail detail) async {
    if (detail.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active members to collect from.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordPaymentPage(
          api: widget.api,
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
          members: [
            for (final r in detail.rows)
              {'memberId': r.memberId, 'name': r.name, 'pending': r.pending},
          ],
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Room Details'),
      ),
      body: FutureBuilder<RoomDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonBlock(height: 60),
                SizedBox(height: 12),
                SkeletonBlock(height: 120),
                SizedBox(height: 12),
                SkeletonBlock(height: 150),
              ],
            );
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Unable to load the latest data. Check your internet connection and try again.';
            return ListView(
              children: [
                ErrorPanel(
                  message: message,
                  onRetry: () => setState(() => _future = widget.api
                      .roomDetail(widget.roomId, from: _from, to: _to)),
                ),
              ],
            );
          }
          final detail = snapshot.data!;
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _RangeSwitcher(detail: detail, onSelect: _selectRange),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        _OverviewCard(detail: detail),
                        const SizedBox(height: 12),
                        _MoneyCards(detail: detail),
                        const SizedBox(height: 12),
                        const TabBar(
                          tabs: [
                            Tab(text: 'Members'),
                            Tab(text: 'History'),
                            Tab(text: 'Info'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Builder(builder: (tabContext) {
                          return AnimatedBuilder(
                            animation: DefaultTabController.of(tabContext),
                            builder: (_, _) {
                              final index =
                                  DefaultTabController.of(tabContext).index;
                              if (index == 1) {
                                return PaymentHistoryList(
                                  api: widget.api,
                                  isAdmin: widget.isAdmin,
                                  roomId: widget.roomId,
                                  roomNumber: widget.roomNumber,
                                  embedded: true,
                                );
                              }
                              if (index == 2) return _infoTab(tabContext, detail);
                              return _membersTab(tabContext, detail);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                _bottomActions(context, detail),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _membersTab(BuildContext context, RoomDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.rows.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16), child: Text('No active members.')))
        else
          for (final row in detail.rows) ...[
            MemberRow(
              name: row.name,
              status: row.status,
              rent: row.rent,
              paid: row.paid,
              pending: row.pending,
              subtitle: row.mobile,
            ),
            if (widget.isAdmin && row.periodId != null && row.pending > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openPayment(row),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Record payment'),
                ),
              ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _infoTab(BuildContext context, RoomDetail detail) {
    final theme = Theme.of(context);
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 130,
                  child: Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondaryText))),
              Expanded(
                  child: Text(value,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room facts',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                fact('Room', detail.room.roomNumber),
                fact('Status', detail.room.status),
                fact('Capacity', '${detail.capacity}'),
                fact('Occupancy', '${detail.memberCount}/${detail.capacity}'),
                fact(
                    'Current range',
                    detail.rangeStartIso == null || detail.rangeEndIso == null
                        ? 'No period yet'
                        : '${fmtDateIso(detail.rangeStartIso!)} – ${fmtDateIso(detail.rangeEndIso!)}'),
                if (detail.paymentState.isNotEmpty)
                  fact('Payment state', displayStatus(detail.paymentState)),
              ],
            ),
          ),
        ),
        if (detail.historical.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Vacated (${detail.historical.length})',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final h in detail.historical)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_outlined,
                        color: AppColors.secondaryText),
                    title: Text(h.name),
                    subtitle: Text(h.mobile),
                    trailing: Text(fmtDateIso(h.vacatedOn),
                        style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomActions(BuildContext context, RoomDetail detail) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.card,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            if (widget.isAdmin) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: detail.isFull ? null : _openAddMember,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: Text(detail.isFull ? 'Full' : 'Add Member'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => _openRecordFlow(detail),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Record Rent Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSwitcher extends StatelessWidget {
  const _RangeSwitcher({required this.detail, required this.onSelect});

  final RoomDetail detail;
  final void Function(DateRange range) onSelect;

  @override
  Widget build(BuildContext context) {
    if (detail.ranges.isEmpty) return const SizedBox.shrink();
    DateRange current = detail.ranges.first;
    for (final r in detail.ranges) {
      if (r.startIso == detail.rangeStartIso) {
        current = r;
        break;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: DropdownButtonFormField<DateRange>(
          initialValue: current,
          decoration: const InputDecoration(
            labelText: 'Rental month (reporting filter)',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.calendar_month_outlined),
          ),
          items: [
            for (final r in detail.ranges)
              DropdownMenuItem(
                value: r,
                child: Text('${fmtDateIso(r.startIso)} – ${fmtDateIso(r.endIso)}'),
              ),
          ],
          onChanged: (r) {
            if (r != null) onSelect(r);
          },
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.meeting_room_outlined,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Room ${detail.room.roomNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${detail.memberCount}/${detail.capacity} occupied',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
            StatusPill.room(detail.room.status),
          ],
        ),
      ),
    );
  }
}

class _MoneyCards extends StatelessWidget {
  const _MoneyCards({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    Widget card(String label, String value, Color color, IconData icon) {
      final theme = Theme.of(context);
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 6),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondaryText, fontSize: 11)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card('Expected', inr(detail.totalRent), AppColors.mainText, Icons.receipt_outlined),
        const SizedBox(width: 10),
        card('Collected', inr(detail.totalPaid), AppColors.success, Icons.wallet_outlined),
        const SizedBox(width: 10),
        card('Remaining', inr(detail.totalPending), AppColors.danger,
            Icons.pending_actions_outlined),
      ],
    );
  }
}
