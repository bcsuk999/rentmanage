import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'payment_allocation.dart';
import 'status_colors.dart';
import 'widgets.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One room member in the drawer's member picker.
class _MemberOption {
  const _MemberOption({
    required this.id,
    required this.name,
    required this.pending,
  });

  final String id;
  final String name;
  final double pending;
}

/// Global record-payment drawer. Open it from anywhere: with no presets it
/// walks room -> member; the member's outstanding rent period is picked
/// automatically. Returns true when a payment was saved.
class PaymentDrawer extends StatefulWidget {
  const PaymentDrawer({
    super.key,
    required this.api,
    this.roomId,
    this.roomNumber,
    this.memberId,
    this.memberName,
    this.periodId,
  });

  final ApiClient api;
  final String? roomId;
  final String? roomNumber;
  final String? memberId;
  final String? memberName;
  final String? periodId;

  @override
  State<PaymentDrawer> createState() => _PaymentDrawerState();
}

class _PaymentDrawerState extends State<PaymentDrawer> {
  List<Room> _rooms = const [];
  bool _roomsLoading = false;

  List<_MemberOption> _members = const [];
  bool _membersLoading = false;

  List<MemberPeriod> _periods = const [];
  bool _dueLoading = true;

  late final TextEditingController _amount;
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String? _roomId;
  String? _memberId;
  String _memberName = '';
  String? _periodId;
  String? _presetPeriodId;

  String _method = paymentMethods.first;
  bool _busy = false;
  bool _popping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _roomId = widget.roomId;
    _memberId = widget.memberId;
    _memberName = widget.memberName ?? '';
    _presetPeriodId = widget.periodId;

    if (_memberId != null) {
      _loadPeriods();
    } else if (_roomId != null) {
      _loadRoomMembers(_roomId!);
    } else {
      _loadRooms();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  MemberPeriod? get _period {
    for (final p in _periods) {
      if (p.id == _periodId) return p;
    }
    return null;
  }

  List<PaymentCycle> get _cycles =>
      buildAllocationOrder(_periods, _periodId ?? '');

  double get _outstandingTotal => overdueTotal(_cycles) + currentTotal(_cycles);

  Future<void> _loadRooms() async {
    setState(() {
      _roomsLoading = true;
      _dueLoading = true;
      _error = null;
    });
    try {
      final rooms = await widget.api.rooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _roomsLoading = false;
        _dueLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        _dueLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        _dueLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  Future<void> _selectRoom(String roomId) async {
    setState(() {
      _roomId = roomId;
      _memberId = null;
      _memberName = '';
      _members = const [];
      _periodId = null;
      _periods = const [];
      _amount.clear();
      _dueLoading = true;
      _error = null;
    });
    await _loadRoomMembers(roomId);
  }

  Future<void> _loadRoomMembers(String roomId) async {
    setState(() {
      _membersLoading = true;
      _dueLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.roomDetail(roomId);
      if (!mounted) return;
      final members = [
        for (final row in detail.rows)
          _MemberOption(id: row.memberId, name: row.name, pending: row.pending),
      ];
      final owed = members.where((m) => m.pending > 0);
      final first = owed.isNotEmpty ? owed.first : members.firstOrNull;
      setState(() {
        _members = members;
        _membersLoading = false;
        if (first == null) {
          _error = 'No active members in this room.';
          _memberId = null;
          _memberName = '';
          _dueLoading = false;
        } else {
          _memberId = first.id;
          _memberName = first.name;
        }
      });
      if (first != null) await _loadPeriods();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _dueLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _membersLoading = false;
        _dueLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  void _selectMember(String memberId) {
    var name = '';
    for (final m in _members) {
      if (m.id == memberId) {
        name = m.name;
        break;
      }
    }
    setState(() {
      _memberId = memberId;
      _memberName = name;
      _periodId = null;
      _periods = const [];
      _amount.clear();
      _dueLoading = true;
      _error = null;
    });
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    final memberId = _memberId;
    if (memberId == null) return;
    setState(() {
      _dueLoading = true;
      _error = null;
    });
    try {
      final periods = await widget.api.memberPeriods(memberId);
      if (!mounted) return;
      MemberPeriod? picked;
      final wanted = _presetPeriodId;
      if (wanted != null) {
        for (final p in periods) {
          if (p.id == wanted) {
            picked = p;
            break;
          }
        }
      }
      picked ??= periods.where((p) => p.pending > 0).firstOrNull;
      picked ??= periods.firstOrNull;
      _presetPeriodId = null;
      setState(() {
        _periods = periods;
        _periodId = picked?.id;
        _amount.clear();
        _dueLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _dueLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dueLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  DateTime _stampDate(MemberPeriod? period) {
    final now = DateTime.now();
    if (period == null) return now;
    final start = DateTime.tryParse(period.startIso);
    final end = DateTime.tryParse(period.endIso);
    if (start != null && now.isBefore(start)) return start;
    if (end != null && now.isAfter(end)) return end;
    return now;
  }

  Future<void> _submit() async {
    final period = _period;
    final memberId = _memberId;
    if (memberId == null) {
      setState(() => _error = 'Choose a member first.');
      return;
    }
    if (period == null) {
      setState(() => _error = 'No rent period is available for this member.');
      return;
    }
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (amount > _outstandingTotal + 0.01) {
      setState(
        () => _error =
            'Amount exceeds the outstanding balance (${inr(_outstandingTotal)}).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.recordPayment(
        rentPeriodId: period.id,
        amount: _amount.text.trim(),
        paymentDate: _dateInput(_stampDate(period)),
        paymentMethod: _method,
        reference: _reference.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      _popping = true;
      toastOk(context, 'Payment of ${inr(amount)} recorded for $_memberName.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted && !_popping) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _header(theme),
          Expanded(
            child: _dueLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                    child: _form(context, theme),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
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
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record Payment'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: AppColors.mainText.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 104),
                child: Text(
                  _memberName.isEmpty ? 'Record Payment' : _memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total due',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                      if (_dueLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 2),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Text(
                          inr(_outstandingTotal),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _outstandingTotal > 0
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.roomId == null && _memberId == null) ...[
          _label(theme, 'Room *'),
          const SizedBox(height: 6),
          if (_roomsLoading)
            const SkeletonBlock(height: 56)
          else if (_rooms.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No rooms found.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                TextButton(onPressed: _loadRooms, child: const Text('Retry')),
              ],
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _roomId,
              items: [
                for (final r in _rooms)
                  DropdownMenuItem(
                    value: r.id,
                    child: Text('Room ${r.roomNumber}'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _selectRoom(v);
              },
            ),
          const SizedBox(height: 12),
        ],
        if (widget.memberId == null) ...[
          _label(theme, 'Member *'),
          const SizedBox(height: 6),
          if (_membersLoading)
            const SkeletonBlock(height: 56)
          else
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              items: [
                for (final m in _members)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text('${m.name} · due ${inr(m.pending)}'),
                  ),
              ],
              onChanged: _members.isEmpty
                  ? null
                  : (v) {
                      if (v != null && v != _memberId) _selectMember(v);
                    },
            ),
          const SizedBox(height: 12),
        ],
        if (_memberId != null && _periodId != null) ...[
          _label(theme, 'Payment Amount *'),
          const SizedBox(height: 6),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              prefixText: '₹ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_amount.text.trim().isNotEmpty && _outstandingTotal > 0) ...[
            _allocationPreview(
              theme,
              double.tryParse(_amount.text.trim()) ?? 0,
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Method'),
            items: [
              for (final m in paymentMethods)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) =>
                setState(() => _method = v ?? paymentMethods.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Transaction Reference (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  );

  Widget _allocationPreview(ThemeData theme, double amount) {
    final lines = previewAllocation(_cycles, amount);
    final applied = lines.fold<double>(0, (sum, line) => sum + line.applied);
    final unallocated = amount - applied;
    final remaining = math.max(0.0, _outstandingTotal - applied);

    return Card(
      color: unallocated > 0.004 ? AppColors.dangerSoft : AppColors.successSoft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment Allocation',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  inr(amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.mainText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Oldest dues are cleared first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            if (lines.isEmpty)
              Text(
                'Nothing outstanding to allocate this against.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondaryText,
                ),
              )
            else
              for (final line in lines) _allocationRow(theme, line),
            if (unallocated > 0.004) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${inr(unallocated)} more than the outstanding balance - the server will reject this.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 18),
            Row(
              children: [
                Text(
                  'Remaining rent',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const Spacer(),
                Text(
                  inr(remaining),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: remaining > 0 ? AppColors.danger : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _allocationRow(ThemeData theme, AllocationLine line) {
    final tag = line.cycle.overdue
        ? 'Overdue period'
        : line.cycle.advance
        ? 'Advance period'
        : 'Current period';
    return AllocationPeriodRow(
      label: line.cycle.label,
      amount: line.applied,
      overdue: line.cycle.overdue,
      caption: line.clears ? '$tag · cleared' : '$tag · ${inr(line.left)} left',
    );
  }
}

/// Opens the global record-payment drawer and returns true when a payment was
/// saved. Safe to call from any screen.
Future<bool> showPaymentDrawer(
  BuildContext context, {
  required ApiClient api,
  String? roomId,
  String? roomNumber,
  String? memberId,
  String? memberName,
  String? periodId,
}) async {
  final result = await Navigator.of(context).push<bool>(
    _drawerRoute(
      PaymentDrawer(
        api: api,
        roomId: roomId,
        roomNumber: roomNumber,
        memberId: memberId,
        memberName: memberName,
        periodId: periodId,
      ),
    ),
  );
  return result == true;
}

/// Same bottom-up arrival as the add-room form, so every drawer in the app
/// opens the same way.
Route<bool> _drawerRoute(Widget page) {
  return PageRouteBuilder<bool>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: AppColors.mainText.withValues(alpha: 0.35),
    transitionDuration: MotionDuration.medium,
    reverseTransitionDuration: MotionDuration.fast,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: MotionCurve.smoothOut,
        reverseCurve: MotionCurve.easeInOut,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      );
    },
  );
}
