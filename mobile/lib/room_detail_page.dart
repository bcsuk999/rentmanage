import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_detail_page.dart';
import 'member_form_page.dart';
import 'motion.dart';
import 'record_payment_page.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Room Details: overview, rent totals and the member list. Tapping a member
/// opens their own details page. The room itself is edited from the app bar.
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
  /// Last known detail. Held here instead of in a FutureBuilder so a refresh
  /// swaps the data in place instead of throwing the page back to a skeleton.
  RoomDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [soft] keeps the current detail on screen: no skeleton, no spinner, the
  /// new numbers simply replace the old ones when they arrive.
  Future<void> _load({bool soft = false}) async {
    if (_inFlight) return;
    _inFlight = true;
    if (!soft && mounted) {
      setState(() => _loading = true);
    }
    try {
      final detail = await widget.api.roomDetail(widget.roomId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_detail == null) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_detail == null) {
          _error = 'Unable to load the latest data. Check your internet connection and try again.';
        }
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _refresh() => _load(soft: _detail != null);

  Future<void> _openAddMember() async {
    final created = await Navigator.of(context).push<bool>(
      smoothRoute(
        MemberFormPage(
          api: widget.api,
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
        ),
      ),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _openMember(RoomDetailRow row) async {
    await Navigator.of(context).push(
      smoothRoute(
        MemberDetailPage(
          api: widget.api,
          memberId: row.memberId,
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openRecordFlow(RoomDetail detail) async {
    if (detail.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active members to collect from.')),
      );
      return;
    }
    await Navigator.of(context).push(
      smoothRoute(
        RecordPaymentPage(
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

  Future<void> _showEditRoomDialog(RoomDetail detail) async {
    final room = detail.room;
    final roomNumber = TextEditingController(text: room.roomNumber);
    final capacity = TextEditingController(text: room.capacity.toString());
    final notes = TextEditingController(text: room.notes ?? '');
    String status = room.status;
    bool busy = false;
    String? error;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Edit Room'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) ...[
                  ShakeOnError(
                    trigger: error,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(error!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: roomNumber,
                  decoration: const InputDecoration(labelText: 'Room number'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacity,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const ['Empty', 'Occupied', 'Maintenance']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => status = v ?? 'Empty'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cap = int.tryParse(capacity.text.trim()) ?? 0;
                      if (roomNumber.text.trim().isEmpty || cap < 1) {
                        setState(() =>
                            error = 'Enter a room number and a capacity of at least 1.');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.api.updateRoom(
                          roomId: widget.roomId,
                          roomNumber: roomNumber.text.trim(),
                          capacity: cap,
                          status: status,
                          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop(true);
                      } on ApiException catch (e) {
                        setState(() => error = e.message);
                      } catch (_) {
                        setState(() => error = 'Could not reach the server.');
                      } finally {
                        if (ctx.mounted) setState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('Room Details'),
        actions: [
          if (detail != null)
            IconButton(
              tooltip: 'Edit room',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showEditRoomDialog(detail),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
      bottomNavigationBar: detail == null ? null : _bottomActions(context, detail),
    );
  }

  Widget _body(BuildContext context) {
    // Skeleton only while there is nothing to show yet.
    if (_loading && _detail == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBlock(height: 64),
          SizedBox(height: 12),
          SkeletonBlock(height: 120),
          SizedBox(height: 12),
          SkeletonBlock(height: 150),
        ],
      );
    }
    final error = _error;
    if (error != null && _detail == null) {
      return ListView(
        children: [ErrorPanel(message: error, onRetry: () => _load())],
      );
    }
    final detail = _detail!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _OverviewCard(detail: detail),
          const SizedBox(height: 12),
          _MoneyCards(detail: detail),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Members (${detail.rows.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: detail.isFull ? null : _openAddMember,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: SwapText(detail.isFull ? 'Full' : 'Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (detail.rows.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16), child: Text('No active members.')))
          else
            for (var i = 0; i < detail.rows.length; i++) ...[
              Reveal(
                key: ValueKey('member-${detail.rows[i].memberId}'),
                delay: MotionDuration.stagger * (i % 8),
                child: MemberRow(
                  name: detail.rows[i].name,
                  status: detail.rows[i].status,
                  rent: detail.rows[i].rent,
                  paid: detail.rows[i].paid,
                  pending: detail.rows[i].pending,
                  subtitle: detail.rows[i].mobile,
                  dueDate: detail.rows[i].periodEnd,
                  onTap: () => _openMember(detail.rows[i]),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
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
            Expanded(
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
                PopInValue(
                  value: value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
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
