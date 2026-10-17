import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'payment_allocation.dart';
import 'status_colors.dart';
import 'widgets.dart';

String _dateInput(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _pretty(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Bottom sheet to record a payment against one rent period.
/// Returns true when a payment was recorded.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.api,
    required this.rentPeriodId,
    required this.memberName,
    required this.pending,
    required this.totalOverdue,
    required this.totalCurrentDue,
    this.cycles = const [],
    this.periodStart,
    this.periodEnd,
  });

  final ApiClient api;
  final String rentPeriodId;
  final String memberName;
  final double pending;
  final double totalOverdue;
  final double totalCurrentDue;

  /// Every cycle this member still owes, in allocation order (lapsed cycles
  /// oldest-first). Drives the per-period split preview; empty falls back to
  /// the two scalar totals above.
  final List<PaymentCycle> cycles;

  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final TextEditingController _amount;
  final _notes = TextEditingController();
  late DateTime _date;
  String _method = paymentMethods.first;
  bool _busy = false;
  bool _popping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.pending > 0 ? widget.pending.toStringAsFixed(0) : '',
    );
    final now = DateTime.now();
    final start = widget.periodStart;
    final end = widget.periodEnd;
    if (start != null && now.isBefore(start)) {
      _date = start;
    } else if (end != null && now.isAfter(end)) {
      _date = end;
    } else {
      _date = now;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Overdue figure shown in the header. Derived from the waterfall so it
  /// always matches the per-period split below it.
  double get _overdueTotal =>
      widget.cycles.isEmpty ? widget.totalOverdue : overdueTotal(widget.cycles);

  double get _currentTotal =>
      widget.cycles.isEmpty ? widget.totalCurrentDue : currentTotal(widget.cycles);

  double get _outstandingTotal => _overdueTotal + _currentTotal;

  /// The cycle this payment is booked against, when the waterfall knows it.
  PaymentCycle? get _selectedCycle {
    for (final c in widget.cycles) {
      if (c.selected) return c;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.periodStart ?? DateTime(2000),
      lastDate: widget.periodEnd ?? DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.recordPayment(
        rentPeriodId: widget.rentPeriodId,
        amount: _amount.text.trim(),
        paymentDate: _dateInput(_date),
        paymentMethod: _method,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      _popping = true;
      toastOk(context, 'Payment of ₹${_amount.text.trim()} recorded for ${widget.memberName}.');
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Record payment · ${widget.memberName}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_outstandingTotal > 0) _summaryCard(context, theme),
            const SizedBox(height: 12),
            _dueLine(context, theme),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₹) *'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_amount.text.trim().isNotEmpty && _outstandingTotal > 0)
              _allocationPreview(context, theme),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Payment date'),
              subtitle: Text(_pretty(_date)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _method = v ?? paymentMethods.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context, ThemeData theme) {
    return Card(
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
                  child: _metric(theme, 'Overdue', _overdueTotal, AppColors.danger,
                      CrossAxisAlignment.start),
                ),
                Expanded(
                  child: _metric(theme, 'Current Due', _currentTotal, AppColors.primary,
                      CrossAxisAlignment.start),
                ),
                Expanded(
                  child: _metric(theme, 'Total Outstanding', _outstandingTotal,
                      AppColors.mainText, CrossAxisAlignment.end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    ThemeData theme,
    String label,
    double value,
    Color color,
    CrossAxisAlignment align,
  ) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
        Text(inr(value),
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  /// The cycle this payment lands on, named with its date range.
  Widget _dueLine(BuildContext context, ThemeData theme) {
    final selected = _selectedCycle;
    final label = selected?.label;
    return Row(
      children: [
        Expanded(
          child: Text(
            label == null
                ? 'Due: ${inr(widget.pending)}'
                : 'Due: ${inr(widget.pending)}  ·  $label',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// Per-period split of the typed amount. One line per rent period, oldest
  /// overdue cycle first, so it reads the same way the server allocates it.
  Widget _allocationPreview(BuildContext context, ThemeData theme) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final lines = widget.cycles.isEmpty
        ? _fallbackLines(amount)
        : previewAllocation(widget.cycles, amount);
    final applied = lines.fold(0.0, (s, l) => s + l.applied);
    final unallocated = amount - applied;

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
                  child: Text('Payment Allocation',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(inr(amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.mainText)),
              ],
            ),
            const SizedBox(height: 2),
            Text('Oldest dues are cleared first.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondaryText)),
            const SizedBox(height: 10),
            if (lines.isEmpty)
              Text('Nothing outstanding to allocate this against.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText))
            else
              for (final line in lines) _allocationRow(context, theme, line),
            if (unallocated > 0.004) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${inr(unallocated)} more than the outstanding balance - the server will reject this.',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One period line: the date range on the left, what it gets on the right.
  Widget _allocationRow(BuildContext context, ThemeData theme, AllocationLine line) {
    final overdue = line.cycle.overdue;
    final color = overdue ? AppColors.danger : AppColors.primary;
    final tag = overdue
        ? 'Overdue period'
        : line.cycle.advance
            ? 'Advance period'
            : 'Current period';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            overdue ? Icons.error_outline : Icons.schedule_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.cycle.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: color)),
                Text(
                  line.clears
                      ? '$tag · cleared'
                      : '$tag · ${inr(line.left)} left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(inr(line.applied),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  /// Two-line split used when the period list could not be loaded, so the
  /// sheet still says something useful instead of going blank.
  List<AllocationLine> _fallbackLines(double amount) {
    final lines = <AllocationLine>[];
    var remaining = amount;
    if (widget.totalOverdue > 0) {
      final take = math.min(remaining, widget.totalOverdue);
      if (take > 0) {
        lines.add(AllocationLine(
          cycle: PaymentCycle(
            id: 'overdue',
            label: 'Overdue dues',
            pending: widget.totalOverdue,
            overdue: true,
          ),
          applied: take,
        ));
        remaining -= take;
      }
    }
    if (remaining > 0 && widget.totalCurrentDue > 0) {
      final take = math.min(remaining, widget.totalCurrentDue);
      lines.add(AllocationLine(
        cycle: PaymentCycle(
          id: 'current',
          label: 'Current due',
          pending: widget.totalCurrentDue,
          overdue: false,
        ),
        applied: take,
      ));
    }
    return lines;
  }
}

/// Opens the payment sheet; returns true when a payment was recorded.
Future<bool> showPaymentSheet(
  BuildContext context, {
  required ApiClient api,
  required String rentPeriodId,
  required String memberName,
  required double pending,
  required double totalOverdue,
  required double totalCurrentDue,
  List<PaymentCycle> cycles = const [],
  DateTime? periodStart,
  DateTime? periodEnd,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PaymentSheet(
      api: api,
      rentPeriodId: rentPeriodId,
      memberName: memberName,
      pending: pending,
      totalOverdue: totalOverdue,
      totalCurrentDue: totalCurrentDue,
      cycles: cycles,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ),
  );
  return result == true;
}
