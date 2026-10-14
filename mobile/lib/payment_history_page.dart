import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Payment history with backend-supported filters: method, date range,
/// member and room scoping, newest-first paging.
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({
    super.key,
    required this.api,
    required this.isAdmin,
    this.memberId,
    this.memberName,
    this.roomId,
    this.roomNumber,
  });

  final ApiClient api;
  final bool isAdmin;
  final String? memberId;
  final String? memberName;
  final String? roomId;
  final String? roomNumber;

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  @override
  Widget build(BuildContext context) {
    final scope = [
      if (widget.roomNumber != null) 'Room ${widget.roomNumber}',
      if (widget.memberName != null) widget.memberName!,
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(title: const Text('Payment History')),
      body: PaymentHistoryList(
        api: widget.api,
        isAdmin: widget.isAdmin,
        memberId: widget.memberId,
        memberName: widget.memberName,
        roomId: widget.roomId,
        roomNumber: widget.roomNumber,
        scopeLabel: scope,
      ),
    );
  }
}

/// Embeddable history list (also used inside the Room Details History tab).
class PaymentHistoryList extends StatefulWidget {
  const PaymentHistoryList({
    super.key,
    required this.api,
    required this.isAdmin,
    this.memberId,
    this.memberName,
    this.roomId,
    this.roomNumber,
    this.scopeLabel,
    this.embedded = false,
  });

  final ApiClient api;
  final bool isAdmin;
  final String? memberId;
  final String? memberName;
  final String? roomId;
  final String? roomNumber;
  final String? scopeLabel;

  /// When true: shrink-wrapped, no pull-to-refresh (parent scrolls).
  final bool embedded;

  @override
  State<PaymentHistoryList> createState() => _PaymentHistoryListState();
}

class _PaymentHistoryListState extends State<PaymentHistoryList> {
  final List<PaymentRecord> _rows = [];
  int _page = 1;
  int _pages = 1;
  double _totalAmount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _method = 'All';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  String? _dateInput(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _pages = 1;
        _rows.clear();
      });
    }
    try {
      final result = await widget.api.payments(
        roomId: widget.roomId,
        memberId: widget.memberId,
        paymentMethod: _method == 'All' ? null : _method,
        from: _dateInput(_from),
        to: _dateInput(_to),
        page: reset ? 1 : _page + 1,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _rows.clear();
        }
        _rows.addAll(result.rows);
        _page = result.page;
        _pages = result.pages;
        _totalAmount = result.totalAmount;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your internet connection and try again.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    if (!mounted) return;
    if (isFrom && _to != null && picked.isAfter(_to!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start date cannot be after end date.')),
      );
      return;
    }
    if (!isFrom && _from != null && picked.isBefore(_from!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date.')),
      );
      return;
    }
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterBar(context),
          const SizedBox(height: 8),
          _body(context),
        ],
      );
    }
    return Column(
      children: [
        _filterBar(context),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _filterBar(BuildContext context) {
    final scope = widget.scopeLabel ??
        [
          if (widget.roomNumber != null) 'Room ${widget.roomNumber}',
          if (widget.memberName != null) widget.memberName!,
        ].join(' · ');
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scope.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(scope,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _methodChip(context),
                const SizedBox(width: 8),
                _dateChip(context, true),
                const SizedBox(width: 8),
                _dateChip(context, false),
                if (_method != 'All' || _from != null || _to != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Clear'),
                    onPressed: () {
                      setState(() {
                        _method = 'All';
                        _from = null;
                        _to = null;
                      });
                      _load(reset: true);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodChip(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Payment method',
      onSelected: (v) {
        setState(() => _method = v);
        _load(reset: true);
      },
      itemBuilder: (_) => [
        'All',
        ...paymentMethods,
      ].map((m) => PopupMenuItem(value: m, child: Text(m))).toList(),
      child: Chip(
        label: Text(_method == 'All' ? 'Method' : _method),
        avatar: const Icon(Icons.payments_outlined, size: 16),
        side: BorderSide(
            color: _method == 'All' ? AppColors.border : AppColors.primary),
      ),
    );
  }

  Widget _dateChip(BuildContext context, bool isFrom) {
    final value = isFrom ? _from : _to;
    return ActionChip(
      label: Text(value == null
          ? (isFrom ? 'From' : 'To')
          : '${isFrom ? 'From ' : 'To '}${fmtDateShort(value)}'),
      avatar: const Icon(Icons.calendar_month_outlined, size: 16),
      onPressed: () => _pickDate(isFrom),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      if (widget.embedded) {
        return const Column(
          children: [
            SkeletonBlock(height: 84),
            SizedBox(height: 10),
            SkeletonBlock(height: 84),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBlock(height: 84),
          SizedBox(height: 12),
          SkeletonBlock(height: 84),
          SizedBox(height: 12),
          SkeletonBlock(height: 84),
        ],
      );
    }
    if (_error != null && _rows.isEmpty) {
      final panel = ErrorPanel(message: _error!, onRetry: () => _load(reset: true));
      return widget.embedded ? panel : ListView(children: [panel]);
    }
    if (_rows.isEmpty) {
      const panel = EmptyPanel(
        icon: Icons.receipt_long_outlined,
        title: 'No payments yet',
        body: 'Recorded payments for this filter will appear here.',
      );
      return widget.embedded ? panel : ListView(children: const [panel]);
    }
    final list = ListView.builder(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 12, 16, 24),
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      itemCount: _rows.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_rows.length} payment${_rows.length == 1 ? '' : 's'}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Text(inr(_totalAmount),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ),
              ),
            ),
          );
        }
        if (index == _rows.length + 1) {
          if (_page >= _pages) return const SizedBox(height: 8);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () {
                        setState(() => _loadingMore = true);
                        _load();
                      },
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _PaymentCard(record: _rows[index - 1]),
        );
      },
    );
    if (widget.embedded) return list;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: list,
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _PaymentDetailDialog(record: record),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(record.memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text('+${inr(record.amount)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800, color: AppColors.success)),
                ],
              ),
              const SizedBox(height: 2),
              Text('Room ${record.roomNumber} · ${record.method}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
              const SizedBox(height: 8),
              Row(
                children: [
                  StatusPill(
                    text: 'Paid',
                    color: AppColors.success,
                    soft: AppColors.successSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fmtDateIso(record.dateIso),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondaryText),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.secondaryText),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentDetailDialog extends StatelessWidget {
  const _PaymentDetailDialog({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 110,
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
    return AlertDialog(
      title: const Text('Payment details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Amount', inr(record.amount)),
            row('Date', fmtDateIso(record.dateIso)),
            row('Member', record.memberName),
            if (record.memberMobile.isNotEmpty) row('Phone', record.memberMobile),
            row('Room', record.roomNumber),
            if (record.periodStartIso.isNotEmpty)
              row('Period',
                  '${fmtDateShortIso(record.periodStartIso)} – ${fmtDateShortIso(record.periodEndIso)}'),
            row('Method', record.method),
            if (record.reference.isNotEmpty) row('Reference', record.reference),
            if (record.notes.isNotEmpty) row('Notes', record.notes),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
