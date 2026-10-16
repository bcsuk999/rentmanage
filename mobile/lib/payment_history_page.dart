import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'record_payment_page.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Payment records with backend-supported filters: method, date range,
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
  final _listKey = GlobalKey<PaymentHistoryListState>();
  bool _recording = false;

  Future<void> _openRecordFlow() async {
    if (_recording) return;
    setState(() => _recording = true);
    try {
      await Navigator.of(context).push(
        smoothRoute(
          RecordPaymentPage(
            api: widget.api,
            roomId: widget.roomId,
            roomNumber: widget.roomNumber,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _recording = false);
    }
    if (mounted) await _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scope = [
      if (widget.roomNumber != null) 'Room ${widget.roomNumber}',
      if (widget.memberName != null) widget.memberName!,
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text(
          'Payment Records',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          _RecordActionButton(busy: _recording, onPressed: _openRecordFlow),
          const SizedBox(width: 10),
        ],
      ),
      body: PaymentHistoryList(
        key: _listKey,
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

/// Header action: raised "Record" pill, shadowed so it reads as tappable.
class _RecordActionButton extends StatelessWidget {
  const _RecordActionButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

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
                  const Icon(Icons.add_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 3),
                Text(
                  'Record',
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


/// Embeddable records list (also used inside the Member Details page).
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
  State<PaymentHistoryList> createState() => PaymentHistoryListState();
}

class PaymentHistoryListState extends State<PaymentHistoryList> {
  /// In-memory first-page cache keyed by scope. Lets the list paint instantly
  /// on revisit while a silent background fetch refreshes it - no skeleton
  /// flash after the very first load.
  static final Map<String, List<PaymentRecord>> _cache = {};

  /// Drops every cached page (called on sign-out).
  static void clearCache() => _cache.clear();

  final List<PaymentRecord> _rows = [];
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _method = 'All';
  DateTime? _from;
  DateTime? _to;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _searchFocus = FocusNode();

  String get _cacheKey => '${widget.roomId ?? ''}|${widget.memberId ?? ''}';

  /// Only the default, unfiltered first page is cached.
  bool get _cacheableQuery =>
      _method == 'All' && _from == null && _to == null && _searchQuery.isEmpty;

  @override
  void initState() {
    super.initState();
    final cached = _cache[_cacheKey];
    if (cached != null && cached.isNotEmpty) {
      // Show the cached page immediately, then refresh silently.
      _rows.addAll(cached);
      _loading = false;
      _load(reset: true, soft: true);
    } else {
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Public so the page header can refresh after a payment is recorded.
  Future<void> reload() => _load(reset: true, soft: _rows.isNotEmpty);

  String? _dateInput(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _hasFilters => _method != 'All' || _from != null || _to != null;

  void _runSearch([String? value]) {
    _searchFocus.unfocus();
    setState(() => _searchQuery = (value ?? _searchController.text).trim());
    _load(reset: true, soft: _rows.isNotEmpty);
  }

  Future<void> _load({bool reset = false, bool soft = false}) async {
    if (reset) {
      setState(() {
        // Keep the current rows on screen when soft: no skeleton flashes over
        // data we already have.
        if (!soft) {
          _loading = true;
          _rows.clear();
        }
        _error = null;
        _page = 1;
        _pages = 1;
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
      var filtered = result.rows;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        filtered = filtered.where((r) =>
            r.memberName.toLowerCase().contains(q) ||
            r.memberMobile.contains(q) ||
            r.reference.toLowerCase().contains(q)).toList();
      }
      setState(() {
        if (reset) {
          _rows.clear();
        }
        _rows.addAll(filtered);
        _page = result.page;
        _pages = result.pages;
        _loading = false;
        _loadingMore = false;
      });
      if (reset && _cacheableQuery) {
        _cache[_cacheKey] = List<PaymentRecord>.of(_rows);
      }
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
    _load(reset: true, soft: _rows.isNotEmpty);
  }

  Future<void> _openMethodPicker() async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Payment method',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            for (final m in ['All', ...paymentMethods])
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(m,
                    style: TextStyle(
                      fontWeight: m == _method ? FontWeight.w700 : FontWeight.w500,
                      color: m == _method ? AppColors.primary : AppColors.mainText,
                    )),
                trailing: m == _method
                    ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                    : null,
                onTap: () => Navigator.of(context).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _method = picked);
    _load(reset: true, soft: _rows.isNotEmpty);
  }

  void _clearFilters() {
    setState(() {
      _method = 'All';
      _from = null;
      _to = null;
    });
    _load(reset: true, soft: _rows.isNotEmpty);
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
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card 1: search input with the search button on its right.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _runSearch,
                        decoration: InputDecoration(
                          hintText: 'Search name, phone, reference...',
                          hintMaxLines: 1,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 34, minHeight: 34),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _runSearch('');
                                  },
                                ),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppColors.primary.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SearchButton(onPressed: _runSearch),
                  ],
                ),
              ),
            ),
          ),
          if (scope.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(scope,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
            ),
          const SizedBox(height: 8),
          // Cards 2, 3, 4: method and the two date pickers, each its own card.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _filterCard(
                      context,
                      label: 'Method',
                      value: _method == 'All' ? 'All' : _method,
                      icon: Icons.payments_outlined,
                      active: _method != 'All',
                      onTap: _openMethodPicker,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _filterCard(
                      context,
                      label: 'From',
                      value: _from == null ? 'Any date' : fmtDateShort(_from!),
                      icon: Icons.calendar_month_outlined,
                      active: _from != null,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _filterCard(
                      context,
                      label: 'To',
                      value: _to == null ? 'Any date' : fmtDateShort(_to!),
                      icon: Icons.event_available_outlined,
                      active: _to != null,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasFilters)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One filter control, always rendered as its own card.
  Widget _filterCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active ? AppColors.primary : AppColors.border,
          width: active ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 13,
                      color: active ? AppColors.primary : AppColors.secondaryText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 10, color: AppColors.secondaryText)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: active ? AppColors.primary : AppColors.mainText,
                ),
              ),
            ],
          ),
        ),
      ),
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
      final panel = EmptyPanel(
        icon: Icons.receipt_long_outlined,
        title: 'No payments yet',
        body: _hasFilters
            ? 'No records match these filters. Try clearing them.'
            : 'Recorded payments for this filter will appear here.',
      );
      return widget.embedded ? panel : ListView(children: [panel]);
    }
    final list = ListView.builder(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 0 : 12, 16, 24),
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      itemCount: _rows.length + 1,
      itemBuilder: (context, index) {
        if (index == _rows.length) {
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
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PaymentCard(record: _rows[index]),
            ),
          ),
        );
      },
    );
    if (widget.embedded) return list;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true, soft: true),
      child: list,
    );
  }
}

/// Square primary search trigger sitting to the right of the search field.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onPressed});

  final void Function([String?]) onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onPressed(),
        child: const SizedBox(
          height: 38,
          width: 38,
          child: Icon(Icons.search, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatefulWidget {
  const _PaymentCard({required this.record});

  final PaymentRecord record;

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _expanded = false;

  PaymentRecord get record => widget.record;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = fmtTimeIso(record.createdAtIso);
    final time = clock.isEmpty
        ? fmtDateIso(record.dateIso)
        : '$clock  ·  ${fmtDateIso(record.dateIso)}';
    final rentPeriod = record.periodStartIso.isEmpty
        ? '-'
        : '${fmtDateShortIso(record.periodStartIso)} – ${fmtDateShortIso(record.periodEndIso)}';
    Widget detail(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondaryText)),
              ),
              Text(':',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondaryText)),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ribbon sits flush against the card's top-left corner.
            Row(
              children: [
                // Expanded (not Flexible + Spacer) so the ribbon slot takes all
            // the leftover width and the amount stays pinned to the right edge.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Text(
                    record.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Paid :',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    inr(record.amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondaryText),
                        ),
                      ),
                      IconButton(
                        tooltip: _expanded ? 'Hide details' : 'Show details',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: AppColors.secondaryText,
                        ),
                        onPressed: _toggle,
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    detail('Room', record.roomNumber),
                    if (record.memberMobile.isNotEmpty)
                      detail('Phone', record.memberMobile),
                    detail('Rent period', rentPeriod),
                    if (record.allocations.isNotEmpty) ...[
                      for (final a in record.allocations.where((a) => a.overdue))
                        detail(
                            'Overdue · ${fmtDateShortIso(a.periodStartIso)} – ${fmtDateShortIso(a.periodEndIso)}',
                            inr(a.amount)),
                      if (record.allocations.any((a) => !a.overdue))
                        detail(
                            'Due',
                            inr(record.allocations
                                .where((a) => !a.overdue)
                                .fold<double>(0, (s, a) => s + a.amount))),
                    ] else if (record.allocOverdue != null)
                      detail(
                          'Allocation',
                          'Overdue ${inr(record.allocOverdue!)} · Current ${inr(record.allocCurrent ?? 0)}'),
                    detail('Method', record.method),
                    if (record.notes.isNotEmpty) detail('Note', record.notes),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
