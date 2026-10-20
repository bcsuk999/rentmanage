import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_detail_page.dart';
import 'member_form_page.dart';
import 'motion.dart';
import 'payment_drawer.dart';
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
          _error =
              'Unable to load the latest data. Check your internet connection and try again.';
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
    final recorded = await showPaymentDrawer(
      context,
      api: widget.api,
      roomId: widget.roomId,
      roomNumber: detail.room.roomNumber,
    );
    if (recorded && mounted) _refresh();
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
                  decoration: const InputDecoration(labelText: 'Room name'),
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
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            PressScale(
              enabled: !busy,
              child: TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            PressScale(
              enabled: !busy,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final cap = int.tryParse(capacity.text.trim()) ?? 0;
                        if (roomNumber.text.trim().isEmpty || cap < 1) {
                          setState(
                            () => error =
                                'Enter a room name and a capacity of at least 1.',
                          );
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
                            notes: notes.text.trim().isEmpty
                                ? null
                                : notes.text.trim(),
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
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
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
    final roomNumber = detail?.room.roomNumber ?? widget.roomNumber;
    return Scaffold(
      appBar: AppBar(
        // Same shadowed header as the dashboard: the list scrolls beneath it.
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: const PressScale(child: BackButton()),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Room $roomNumber',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            if (detail != null) ...[
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: roomStatusColor(detail.room.status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_statusLabel(detail.room.status)} · ${detail.memberCount}/${detail.capacity}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: roomStatusColor(detail.room.status),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (detail != null)
            PressScale(
              child: IconButton(
                tooltip: 'Edit room',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditRoomDialog(detail),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
      bottomNavigationBar:
          detail == null ? null : _bottomActions(context, detail),
    );
  }

  /// 'occupied' reads better as 'Occupied' in the header.
  String _statusLabel(String status) =>
      status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

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
          _MoneyCards(detail: detail),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Members (${detail.rows.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              PressScale(
                enabled: !detail.isFull,
                child: TextButton.icon(
                  onPressed: detail.isFull ? null : _openAddMember,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: SwapText(detail.isFull ? 'Full' : 'Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (detail.rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No active members.'),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < detail.rows.length; i++) ...[
                    Reveal(
                      key: ValueKey('member-${detail.rows[i].memberId}'),
                      delay: MotionDuration.stagger * (i % 8),
                      child: MemberRow(
                        name: detail.rows[i].name,
                        status: detail.rows[i].status,
                        rent: detail.rows[i].rent,
                        paid: detail.rows[i].paid,
                        // Balance, not just this cycle: carry-over from ended
                        // cycles belongs on the row too.
                        pending: detail.rows[i].totalDue,
                        subtitle: detail.rows[i].mobile,
                        dueDate: detail.rows[i].periodEnd,
                        onTap: () => _openMember(detail.rows[i]),
                      ),
                    ),
                    if (i < detail.rows.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 56,
                        color: AppColors.border,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomActions(BuildContext context, RoomDetail detail) {
    return Container(
      // A bar that matches the header: white surface with a shadow thrown
      // upwards onto the content it floats over.
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: AppColors.mainText.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 50,
            child: PressScale(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  // Squarer than the default pill, and full width so it reads as
                  // the bar's single action.
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _openRecordFlow(detail),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Record Rent Payment'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same tiles as the dashboard, so money reads identically on both screens.
class _MoneyCards extends StatelessWidget {
  const _MoneyCards({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        SummaryMetric(
          icon: Icons.receipt_outlined,
          value: inr(detail.totalRent),
          label: 'Expected',
          color: AppColors.mainText,
        ),
        SummaryMetric(
          icon: Icons.wallet_outlined,
          value: inr(detail.totalPaid),
          label: 'Collected',
          color: AppColors.success,
        ),
        SummaryMetric(
          icon: Icons.pending_actions_outlined,
          value: inr(detail.totalDue),
          label: 'Remaining',
          color: AppColors.danger,
        ),
      ],
    );
  }
}
