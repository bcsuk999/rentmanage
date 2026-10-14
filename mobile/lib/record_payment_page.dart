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
    required this.roomId,
    required this.roomNumber,
    required this.members,
  });

  final ApiClient api;
  final String roomId;
  final String roomNumber;

  /// [{memberId, name, pending}] snapshots from the details screen.
  final List<Map<String, dynamic>> members;

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

  @override
  void initState() {
    super.initState();
    final firstOwed = widget.members.where((m) => (m['pending'] as num? ?? 0) > 0);
    final first = firstOwed.isNotEmpty ? firstOwed.first : widget.members.firstOrNull;
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
    for (final m in widget.members) {
      if ('${m['memberId']}' == _memberId) return '${m['name']}';
    }
    return '';
  }

  Future<void> _loadPeriods() async {
    final id = _memberId;
    if (id == null) return;
    setState(() {
      _periodsLoading = true;
      _periods = [];
      _periodId = null;
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
        _periodId = (firstOwed ?? periods.firstOrNull)?.id;
        if (_periodId != null) _applyFullAmount();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _periodsLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _periodsLoading = false;
        _error = 'Could not reach the server.';
      });
    }
  }

  void _applyFullAmount() {
    final p = _period;
    if (p == null) return;
    _customAmount = false;
    _amount.text = p.pending > 0 ? p.pending.toStringAsFixed(0) : '';
  }

  void _applyChip(double value) {
    _customAmount = false;
    _amount.text = value.toStringAsFixed(0);
  }

  String _dateInput(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final period = _period;
    if (_memberId == null || period == null) {
      setState(() => _error = 'Choose a member and a rent period first.');
      return;
    }
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (amount > period.pending) {
      setState(() => _error =
          'Amount exceeds the outstanding balance (${inr(period.pending)}) for this period.');
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
      );
      if (!mounted) return;
      final snapshot = PaymentConfirmationData(
        amount: amount,
        memberName: _memberName(),
        roomNumber: widget.roomNumber,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = _period;
    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_outline, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_memberName().isEmpty ? 'Choose member' : _memberName(),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Room ${widget.roomNumber}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.secondaryText)),
                        ],
                      ),
                    ),
                    if (period != null)
                      Text(inr(period.pending),
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800, color: AppColors.danger)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            Text('Member', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              items: [
                for (final m in widget.members)
                  DropdownMenuItem(
                    value: '${m['memberId']}',
                    child: Text('${m['name']} · due ${inr((m['pending'] as num? ?? 0).toDouble())}'),
                  ),
              ],
              onChanged: (v) {
                setState(() => _memberId = v);
                _loadPeriods();
              },
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
                    label: Text('Full ${inr(period.pending)}'),
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
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Payment Date *'),
              subtitle: Text(fmtDateIso(_dateInput(_date))),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDate,
            ),
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
