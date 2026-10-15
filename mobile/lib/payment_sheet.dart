import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
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
    this.periodStart,
    this.periodEnd,
  });

  final ApiClient api;
  final String rentPeriodId;
  final String memberName;
  final double pending;
  final double totalOverdue;
  final double totalCurrentDue;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final TextEditingController _amount;
  late DateTime _date;
  String _method = paymentMethods.first;
  bool _busy = false;
  String? _error;

  Map<String, double> _getAllocationBreakdown(double amount) {
    final overduePaid = amount.clamp(0.0, widget.totalOverdue);
    final currentPaid = (amount - overduePaid).clamp(0.0, widget.totalCurrentDue);
    final remainingOverdue = widget.totalOverdue - overduePaid;
    final remainingCurrent = widget.totalCurrentDue - currentPaid;
    return {
      'overduePaid': overduePaid,
      'currentPaid': currentPaid,
      'remainingOverdue': remainingOverdue,
      'remainingCurrent': remainingCurrent,
    };
  }

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
    super.dispose();
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
      );
      if (!mounted) return;
      toastOk(context, 'Payment of ₹${_amount.text.trim()} recorded for ${widget.memberName}.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            if (widget.totalOverdue > 0 || widget.totalCurrentDue > 0)
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
                                Text('₹${widget.totalOverdue.toStringAsFixed(0)}',
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
                                Text('₹${widget.totalCurrentDue.toStringAsFixed(0)}',
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
                                Text('₹${(widget.totalOverdue + widget.totalCurrentDue).toStringAsFixed(0)}',
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
            Text('Due: ₹${widget.pending.toStringAsFixed(0)}', style: theme.textTheme.bodySmall),
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
            if (_amount.text.isNotEmpty && (widget.totalOverdue > 0 || widget.totalCurrentDue > 0))
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

  Widget _allocRow(String label, double value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
            Text('₹${value.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
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
      periodStart: periodStart,
      periodEnd: periodEnd,
    ),
  );
  return result == true;
}
