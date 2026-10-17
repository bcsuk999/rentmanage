import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'payment_history_page.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Full record-payment flow: member -> outstanding period -> amount chips ->
/// date/method/reference/notes -> server-confirmed confirmation screen.
class RecordPaymentPage extends StatefulWidget {
  const RecordPaymentPage({
    super.key,
    required this.api,
    this.roomId,
    this.roomNumber,
    this.members,
  });

  final ApiClient api;

  /// Optional preselected room. When null the page starts empty and the
  /// landlord picks room -> member here.
  final String? roomId;
  final String? roomNumber;

  /// [{memberId, name, pending}] snapshots from the details screen.
  final List<Map<String, dynamic>>? members;

  @override
  State<RecordPaymentPage> createState() => _RecordPaymentPageState();
}

class _RecordPaymentPageState extends State<RecordPaymentPage> {
  String? _memberId;
  List<MemberPeriod> _periods = [];
  bool _periodsLoading = false;
  String? _periodId;
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = paymentMethods.first;
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _customAmount = false;

  double _totalOverdue = 0;
  double _totalCurrentDue = 0;

  List<Room> _rooms = [];
  bool _roomsLoading = false;
  bool _roomsInFlight = false;
  bool _periodsInFlight = false;
  String? _roomId;
  late String _roomNumber;
  late List<Map<String, dynamic>> _members;

  @override
  void initState() {
    super.initState();
    _members = List.of(widget.members ?? const []);
    _roomNumber = widget.roomNumber ?? '';
    _roomId = widget.roomId;
    if (_roomId == null) {
      _loadRooms();
      return;
    }
    final firstOwed = _members.where((m) => (m['pending'] as num? ?? 0) > 0);
    final first = firstOwed.isNotEmpty ? firstOwed.first : _members.firstOrNull;
    if (first != null) {
      _memberId = '${first['memberId']}';
      _loadPeriods();
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

  String _memberName() {
    for (final m in _members) {
      if ('${m['memberId']}' == _memberId) return '${m['name']}';
    }
    return '';
  }

  /// [soft] keeps the current room list on screen so a background refresh never
  /// collapses the dropdown back into a skeleton.
  Future<void> _loadRooms({bool soft = false}) async {
    if (_roomsInFlight) return;
    _roomsInFlight = true;
    if (!soft || _rooms.isEmpty) {
      setState(() {
        _roomsLoading = true;
        _error = null;
      });
    }
    try {
      final rooms = await widget.api.rooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _roomsLoading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        if (_rooms.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _roomsLoading = false;
        if (_rooms.isEmpty) _error = 'Could not reach the server.';
      });
    } finally {
      _roomsInFlight = false;
    }
  }

  /// Silent re-read of the selected room's members and their periods, used when
  /// the page is shown again: keeps the form filled in while the dues refresh.
  Future<void> refreshSilently() async {
    final memberId = _memberId;
    if (memberId == null) {
      if (_rooms.isEmpty) await _loadRooms();
      return;
    }
    await _loadPeriods(soft: true);
  }

  /// Room chosen inside this page: pull its active members, then auto-select
  /// the first one who owes something.
  Future<void> _selectRoom(String roomId) async {
    var roomNumber = roomId;
    for (final r in _rooms) {
      if (r.id == roomId) {
        roomNumber = r.roomNumber;
        break;
      }
    }
    setState(() {
      _roomId = roomId;
      _roomNumber = roomNumber;
      _memberId = null;
      _members = [];
      _periodId = null;
      _periods = [];
      _totalOverdue = 0;
      _totalCurrentDue = 0;
      _error = null;
    });
    try {
      final detail = await widget.api.roomDetail(roomId);
      if (!mounted) return;
      final members = [
        for (final r in detail.rows)
          {'memberId': r.memberId, 'name': r.name, 'pending': r.pending},
      ];
      setState(() => _members = members);
      final owed = members.where((m) => (m['pending'] as num? ?? 0) > 0);
      final first = owed.isNotEmpty ? owed.first : members.firstOrNull;
      if (first != null) {
        setState(() => _memberId = '${first['memberId']}');
        _loadPeriods();
      } else {
        setState(() => _error = 'No active members in this room.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    }
  }

  void _calculateDues() {
    final now = DateTime.now();
    _totalOverdue = 0;
    _totalCurrentDue = 0;
    for (final p in _periods) {
      if (p.pending <= 0) continue;
      final periodEnd = DateTime.tryParse(p.endIso);
      if (periodEnd != null && periodEnd.isBefore(now)) {
        _totalOverdue += p.pending;
      } else {
        _totalCurrentDue += p.pending;
      }
    }
  }

  /// [soft] keeps the already loaded periods on screen (silent refresh) instead
  /// of emptying the dropdown and flashing its skeleton.
  Future<void> _loadPeriods({bool soft = false}) async {
    final id = _memberId;
    if (id == null) return;
    if (_periodsInFlight) return;
    _periodsInFlight = true;
    final memberChanged = !soft;
    setState(() {
      _periodsLoading = true;
      if (memberChanged) {
        _periods = [];
        _periodId = null;
      }
    });
    try {
      final periods = await widget.api.memberPeriods(id);
      if (!mounted) return;
      MemberPeriod? firstOwed;
      for (final p in periods) {
        if (p.pending > 0) {
          firstOwed ??= p;
        }
      }
      setState(() {
        _periods = periods;
        _periodsLoading = false;
        _error = null;
        // A soft refresh keeps the user's chosen period if it still exists.
        final keepSoft =
            soft && _periodId != null && periods.any((p) => p.id == _periodId);
        _periodId = keepSoft
            ? _periodId
            : (firstOwed ?? periods.firstOrNull)?.id;
        _calculateDues();
        _ensureDateValid();
        if (!keepSoft && _periodId != null) _applyFullAmount();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _periodsLoading = false;
        if (_periods.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _periodsLoading = false;
        if (_periods.isEmpty) _error = 'Could not reach the server.';
      });
    } finally {
      _periodsInFlight = false;
    }
  }

  void _applyFullAmount() {
    final total = _totalOverdue + _totalCurrentDue;
    _customAmount = false;
    _amount.text = total > 0 ? total.toStringAsFixed(0) : '';
  }

  void _applyChip(double value) {
    _customAmount = false;
    _amount.text = value.toStringAsFixed(0);
  }

  /// Payments are always stamped with the current date - there is no picker.
  /// The server only rejects a date that predates the cycle, which can happen
  /// for an advance cycle that has not started yet; clamp that one case to the
  /// cycle start.
  void _ensureDateValid() {
    final p = _period;
    if (p == null) return;
    final start = DateTime.tryParse(p.startIso);
    if (start != null && _date.isBefore(start)) _date = start;
  }

  Map<String, double> _getAllocationBreakdown(double amount) {
    final overduePaid = amount.clamp(0.0, _totalOverdue);
    final currentPaid = (amount - overduePaid).clamp(0.0, _totalCurrentDue);
    final remainingOverdue = _totalOverdue - overduePaid;
    final remainingCurrent = _totalCurrentDue - currentPaid;
    return {
      'overduePaid': overduePaid,
      'currentPaid': currentPaid,
      'remainingOverdue': remainingOverdue,
      'remainingCurrent': remainingCurrent,
    };
  }

String _dateInput(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final period = _period;
    if (_memberId == null || period == null) {
      setState(() => _error = _roomId == null
          ? 'Choose a room, a member and a rent period first.'
          : 'Choose a member and a rent period first.');
      return;
    }
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (amount > _totalOverdue + _totalCurrentDue + 0.01) {
      setState(() => _error =
          'Amount exceeds the outstanding balance (${inr(_totalOverdue + _totalCurrentDue)}).');
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
        paymentDate: _dateInput(_date),
        paymentMethod: _method,
        reference: _reference.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      final snapshot = PaymentConfirmationData(
        amount: amount,
        memberName: _memberName(),
        roomNumber: _roomNumber,
        memberId: _memberId!,
        date: _date,
        periodLabel: '${fmtDateIso(period.startIso)} – ${fmtDateIso(period.endIso)}',
        method: _method,
        reference: _reference.text.trim(),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentConfirmationScreen(api: widget.api, data: snapshot),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Nothing was saved — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _allocRow(String label, double value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
            Text(inr(value),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = _period;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text(
          'Record Payment',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          _SaveActionButton(busy: _busy, onPressed: _submit),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.roomId == null) ...[
              Text('Room *', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (_roomsLoading)
                const SkeletonBlock(height: 56)
              else if (_rooms.isEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text('No rooms found.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondaryText)),
                    ),
                    TextButton(onPressed: _loadRooms, child: const Text('Retry')),
                  ],
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _roomId,
                  items: [
                    for (final r in _rooms)
                      DropdownMenuItem(value: r.id, child: Text('Room ${r.roomNumber}')),
                  ],
                  onChanged: (v) {
                    if (v != null) _selectRoom(v);
                  },
                ),
              const SizedBox(height: 12),
            ],
            Text('Member', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              items: [
                for (final m in _members)
                  DropdownMenuItem(
                    value: '${m['memberId']}',
                    child: Text('${m['name']} · due ${inr((m['pending'] as num? ?? 0).toDouble())}'),
                  ),
              ],
              onChanged: _members.isEmpty
                  ? null
                  : (v) {
                      setState(() => _memberId = v);
                      _loadPeriods();
                    },
            ),
            const SizedBox(height: 12),
            if (_totalOverdue > 0 || _totalCurrentDue > 0)
              Card(
                color: AppColors.primary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Outstanding Breakdown',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Overdue',
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                                Text(inr(_totalOverdue),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800, color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Current Due',
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary)),
                                Text(inr(_totalCurrentDue),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Total Outstanding',
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
                                Text(inr(_totalOverdue + _totalCurrentDue),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800, color: AppColors.mainText)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text('Rent Period', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_periodsLoading)
              const SkeletonBlock(height: 56)
            else if (_periods.isEmpty)
              Text('No rent periods found for this member.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText))
            else
              DropdownButtonFormField<String>(
                initialValue: _periodId,
                items: [
                  for (final p in _periods)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                          '${fmtDateShortIso(p.startIso)} – ${fmtDateShortIso(p.endIso)} · due ${inr(p.pending)}'),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _periodId = v;
                  _ensureDateValid();
                  _applyFullAmount();
                }),
              ),
            const SizedBox(height: 12),
            Text('Payment Amount', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (period != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in [500.0, 1000.0])
                    ActionChip(
                      label: Text(inr(chip)),
                      onPressed: () => setState(() => _applyChip(chip)),
                    ),
                  ActionChip(
                    label: Text('Full ${inr(_totalOverdue + _totalCurrentDue)}'),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    onPressed: () => setState(_applyFullAmount),
                  ),
                  ActionChip(
                    label: const Text('Custom'),
                    backgroundColor: _customAmount
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : null,
                    onPressed: () => setState(() {
                      _customAmount = true;
                      _amount.clear();
                    }),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _customAmount = true),
            ),
            const SizedBox(height: 8),
            if (_amount.text.isNotEmpty && (_totalOverdue > 0 || _totalCurrentDue > 0))
              Builder(builder: (context) {
                final amount = double.tryParse(_amount.text.trim()) ?? 0;
                final breakdown = _getAllocationBreakdown(amount);
                return Card(
                  color: AppColors.successSoft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment Allocation Preview',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (breakdown['overduePaid']! > 0)
                          _allocRow('Overdue', breakdown['overduePaid']!, AppColors.danger),
                        if (breakdown['currentPaid']! > 0)
                          _allocRow('Current Due', breakdown['currentPaid']!, AppColors.primary),
                        const Divider(height: 12),
                        _allocRow('Remaining Overdue', breakdown['remainingOverdue']!, AppColors.danger),
                        _allocRow('Remaining Current Due', breakdown['remainingCurrent']!, AppColors.primary),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method *'),
              items: [
                for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _method = v ?? paymentMethods.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Transaction Reference (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header action: raised "Save" pill that submits the payment.
class _SaveActionButton extends StatelessWidget {
  const _SaveActionButton({required this.busy, required this.onPressed});

  final bool busy;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.38),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    height: 11,
                    width: 11,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
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

class PaymentConfirmationData {
  PaymentConfirmationData({
    required this.amount,
    required this.memberName,
    required this.roomNumber,
    required this.memberId,
    required this.date,
    required this.periodLabel,
    required this.method,
    required this.reference,
  });

  final double amount;
  final String memberName;
  final String roomNumber;
  final String memberId;
  final DateTime date;
  final String periodLabel;
  final String method;
  final String reference;
}

/// Shown only after the server confirms the payment persisted.
class PaymentConfirmationScreen extends StatelessWidget {
  const PaymentConfirmationScreen({super.key, required this.api, required this.data});

  final ApiClient api;
  final PaymentConfirmationData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Confirmation')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: AppColors.successSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 44, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            Text('Payment Recorded!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${inr(data.amount)} from ${data.memberName} · Room ${data.roomNumber}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _kv(context, 'Amount', inr(data.amount)),
                    _kv(context, 'Date',
                        '${data.date.day.toString().padLeft(2, '0')} ${_month(data.date.month)} ${data.date.year}'),
                    _kv(context, 'Member', data.memberName),
                    _kv(context, 'Room', data.roomNumber),
                    _kv(context, 'Rent Period', data.periodLabel),
                    _kv(context, 'Method', data.method),
                    if (data.reference.isNotEmpty) _kv(context, 'Reference', data.reference),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Done'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentHistoryPage(
                    api: api,
                    isAdmin: true,
                    memberId: data.memberId,
                    memberName: data.memberName,
                  ),
                ),
              ),
              child: const Text('View Payment History'),
            ),
          ],
        ),
      ),
    );
  }

  static String _month(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  Widget _kv(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.secondaryText))),
            Expanded(
                child: Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
