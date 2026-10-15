import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'app_update_page.dart';
import 'change_password_page.dart';
import 'motion.dart';
import 'overdue_page.dart';
import 'payment_history_page.dart';
import 'room_detail_page.dart';
import 'session_cache.dart';
import 'status_colors.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.user, this.initialRooms, required this.onSignOut});

  final ApiClient api;
  final Map<String, dynamic> user;
  final List<Room>? initialRooms;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  late Future<List<Room>> _future;
  ReportTotals? _summary;
  bool _summaryLoading = true;
  final _search = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _searching = false;
  DateTime _period = DateTime(DateTime.now().year, DateTime.now().month);
  String? _chip; // single-select chip; null = custom (from sheet) or none
  String _statusFilter = 'All';
  String _payFilter = 'All';

  /// Single-role system: every signed-in landlord has full access.
  bool get _isAdmin => true;
  bool get _filtered =>
      _search.text.trim().isNotEmpty || _statusFilter != 'All' || _payFilter != 'All';

  @override
  void initState() {
    super.initState();
    // Rebuild so the clear (X) button tracks the typed text.
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialRooms != null) {
      // Show the cached list instantly, then refresh quietly in background.
      _future = Future.value(widget.initialRooms!);
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(silent: true));
    } else {
      _future = _loadRooms('');
    }
    _loadSummary();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  /// Search fetch that keeps the current list on screen with an inline loader,
  /// and ignores responses that a newer keystroke has superseded.
  Future<void> _runSearch(String value) async {
    final id = ++_requestId;
    if (mounted) setState(() => _searching = true);
    try {
      final rooms = await _loadRooms(value);
      if (!mounted || id != _requestId) return;
      setState(() {
        _future = Future.value(rooms);
        _searching = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() {
        _future = Future.error(e);
        _searching = false;
      });
    }
  }

  /// Fetch rooms for the selected month; an expired/revoked token signs
  /// out instead of error-looping.
  Future<List<Room>> _loadRooms(String query) async {
    try {
      return await widget.api.rooms(
        search: query,
        status: _statusFilter,
        paymentState: _payFilter,
        from: monthStart(_period),
        to: monthEnd(_period),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) _signOut();
      rethrow;
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final id = ++_requestId;
    if (!silent && mounted) setState(() => _searching = true);
    try {
      final rooms = await _loadRooms(_search.text);
      if (!mounted || id != _requestId) return;
      setState(() {
        _future = Future.value(rooms);
        _searching = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() => _searching = false);
      if (silent) {
        // Cached list stays on screen; mention the stale data quietly.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline — showing saved rooms.')),
        );
      } else {
        setState(() => _future = Future.error(e));
      }
    }
  }

  Future<void> _loadSummary() async {
    if (mounted) setState(() => _summaryLoading = true);
    try {
      final totals = await widget.api.report(
        from: monthStart(_period),
        to: monthEnd(_period),
      );
      if (mounted) {
        setState(() {
          _summary = totals;
          _summaryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  void _movePeriod(int delta) {
    setState(() => _period = DateTime(_period.year, _period.month + delta));
    _refresh();
    _loadSummary();
  }

  void _goThisMonth() {
    final now = DateTime.now();
    setState(() => _period = DateTime(now.year, now.month));
    _refresh();
    _loadSummary();
  }

  void _applyChip(String? chip) {
    setState(() {
      _chip = chip;
      _statusFilter = 'All';
      _payFilter = 'All';
      switch (chip) {
        case 'Occupied':
          _statusFilter = 'Occupied';
        case 'Vacant':
          _statusFilter = 'Empty';
        case 'Partial':
          _payFilter = 'Partial';
        case 'Overdue':
          _payFilter = 'Overdue';
        case 'Paid':
          _payFilter = 'Fully Paid';
        case 'Due':
          _payFilter = 'Pending';
      }
    });
    _runSearch(_search.text);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_RoomFilters>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        status: _statusFilter,
        payment: _payFilter,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _statusFilter = result.status;
        _payFilter = result.payment;
        _chip = result.chip;
      });
      _runSearch(_search.text);
    }
  }

  Future<void> _useCached() async {
    List<Room>? cached;
    try {
      cached = await SessionCache.loadRooms();
    } catch (_) {
      cached = null;
    }
    if (!mounted) return;
    if (cached != null) {
      setState(() => _future = Future.value(cached!));
    } else {
      _refresh();
    }
  }

  void _signOut() {
    widget.api.token = null;
    widget.onSignOut();
  }

  void _openDetails(Room room) async {
    await Navigator.of(context).push(
      smoothRoute(
        RoomDetailPage(
          api: widget.api,
          roomId: room.id,
          roomNumber: room.roomNumber,
          isAdmin: _isAdmin,
        ),
      ),
    );
    // Members/payments may have changed inside details — reload so the
    // cards behind never show stale occupancy or totals.
    if (mounted) {
      _refresh();
      _loadSummary();
    }
  }

  Future<void> _showAddRoom() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddRoomDialog(api: widget.api),
    );
    if (created == true) {
      _refresh();
      _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: Image.asset(
            'logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.home_work_outlined,
              color: AppColors.primary,
            ),
          ),
        ),
        centerTitle: true,
        title: const Text('Dashboard',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            tooltip: 'Overdue dues',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => setState(() => _tab = 1),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _tab == 0
          ? _roomsTab(context)
          : _tab == 1
              ? OverduePage(api: widget.api, isAdmin: _isAdmin, onAuthExpired: _signOut)
              : _accountTab(context),
      floatingActionButton: (_tab == 0 && _isAdmin)
          ? FloatingActionButton(
              tooltip: 'Add room',
              onPressed: _showAddRoom,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.meeting_room_outlined),
              selectedIcon: Icon(Icons.meeting_room),
              label: 'Rooms'),
          NavigationDestination(
              icon: Icon(Icons.event_busy_outlined),
              selectedIcon: Icon(Icons.event_busy),
              label: 'Overdue'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account'),
        ],
      ),
    );
  }

  Widget _roomsTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _refresh();
        await _loadSummary();
      },
      child: FutureBuilder<List<Room>>(
        future: _future,
        builder: (context, snapshot) {
          final hasData = snapshot.hasData && snapshot.data!.isNotEmpty;
          Widget child;
          if (snapshot.connectionState == ConnectionState.waiting && !hasData) {
            child = const SkeletonRooms(key: ValueKey('rooms-skeleton'));
          } else if (snapshot.hasError && !hasData) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Unable to load the latest data. Check your internet connection and try again.';
            child = ListView(
              key: const ValueKey('rooms-error'),
              padding: const EdgeInsets.all(20),
              children: [
                ErrorPanel(
                  message: message,
                  onRetry: _refresh,
                  onUseCached: _useCached,
                ),
              ],
            );
          } else {
            final rooms = snapshot.data ?? [];
            // Mobile viewport everywhere: one centered phone-width column,
            // even on desktop.
            child = SingleChildScrollView(
              key: const ValueKey('rooms-content'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _periodRow(context),
                      const SizedBox(height: 12),
                      _summaryGrid(context),
                      const SizedBox(height: 12),
                      _searchRow(context),
                      const SizedBox(height: 8),
                      _chipRow(context),
                      if (_searching) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 12),
                      if (rooms.isEmpty)
                        _emptyState(context)
                      else
                        for (var i = 0; i < rooms.length; i++) ...[
                          Reveal(
                            key: ValueKey('room-${rooms[i].id}'),
                            delay: MotionDuration.stagger * (i % 8),
                            child: _RoomCard(
                              room: rooms[i],
                              onOpen: () => _openDetails(rooms[i]),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
            );
          }
          return AnimatedSwitcher(
            duration: MotionDuration.slow,
            switchInCurve: MotionCurve.smoothOut,
            switchOutCurve: MotionCurve.easeInOut,
            child: child,
          );
        },
      ),
    );
  }

  Widget _periodRow(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent =
        _period.year == DateTime.now().year && _period.month == DateTime.now().month;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _movePeriod(-1),
            ),
            Expanded(
              child: Text(monthLabel(_period),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (!isCurrent)
              TextButton(onPressed: _goThisMonth, child: const Text('This month'))
            else
              TextButton(
                  onPressed: null,
                  child: Text('This month',
                      style: TextStyle(color: AppColors.secondaryText.withValues(alpha: 0.5)))),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _movePeriod(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryGrid(BuildContext context) {
    if (_summaryLoading && _summary == null) {
      return const Row(
        children: [
          Expanded(child: SkeletonBlock(height: 62)),
          SizedBox(width: 10),
          Expanded(child: SkeletonBlock(height: 62)),
        ],
      );
    }
    final s = _summary;
    if (s == null) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        SummaryMetric(
          icon: Icons.wallet_outlined,
          value: inr(s.receivedInRange),
          label: 'Collected · ${monthLabel(_period)}',
          color: AppColors.success,
        ),
        SummaryMetric(
          icon: Icons.pending_actions_outlined,
          value: inr(s.totalPending),
          label: 'Outstanding',
          color: AppColors.danger,
        ),
        SummaryMetric(
          icon: Icons.meeting_room_outlined,
          value: '${s.totalRooms}',
          label: 'Total rooms',
          color: AppColors.primary,
        ),
        SummaryMetric(
          icon: Icons.people_outline,
          value: '${s.totalMembers}',
          label: 'Active members',
          color: AppColors.primary,
        ),
      ],
    );
  }

  Widget _searchRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refresh(),
            decoration: InputDecoration(
              hintText: 'Search rooms or members...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _runSearch('');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Filters',
          icon: Badge(
            isLabelVisible: _statusFilter != 'All' || _payFilter != 'All',
            child: const Icon(Icons.tune_outlined),
          ),
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _openFilters,
        ),
      ],
    );
  }

  Widget _chipRow(BuildContext context) {
    const chips = ['All', 'Occupied', 'Vacant', 'Partial', 'Overdue', 'Paid', 'Due'];
    final selected = _chip ?? 'All';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c),
                selected: selected == c,
                onSelected: (_) => _applyChip(c == 'All' ? null : c),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                checkmarkColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected == c ? AppColors.primary : AppColors.secondaryText,
                  fontWeight: selected == c ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                  color: selected == c ? AppColors.primary : AppColors.border,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    if (_filtered) {
      return EmptyPanel(
        icon: Icons.search_off_outlined,
        title: 'No matches',
        body: 'Try a different search or clear the filters.',
        actionLabel: 'Clear filters',
        onAction: () {
          _search.clear();
          setState(() {
            _statusFilter = 'All';
            _payFilter = 'All';
            _chip = null;
          });
          _runSearch('');
        },
      );
    }
    return EmptyPanel(
      icon: Icons.meeting_room_outlined,
      title: 'No rooms yet',
      body: 'Start by adding your first room to manage rent and members.',
      actionLabel: _isAdmin ? 'Add Room' : null,
      onAction: _isAdmin ? _showAddRoom : null,
    );
  }

  Widget _accountTab(BuildContext context) {
    final theme = Theme.of(context);
    final name = '${widget.user['name'] ?? widget.user['mobile'] ?? 'Account'}';
    final mobile = '${widget.user['mobile'] ?? widget.user['username'] ?? ''}';
    final isAdmin = _isAdmin;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text('Account', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            if (mobile.isNotEmpty)
                              Text('+91 $mobile',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.secondaryText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: StatusPill(
                      text: 'Landlord · Active',
                      color: AppColors.primary,
                      soft: AppColors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _menuTile(
            context,
            icon: Icons.receipt_long_outlined,
            color: AppColors.primary,
            title: 'Payment History',
            subtitle: 'Every saved payment, newest first',
            onTap: () => Navigator.of(context).push(
              smoothRoute(
                PaymentHistoryPage(api: widget.api, isAdmin: isAdmin),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _menuTile(
            context,
            icon: Icons.lock_outline,
            color: AppColors.warning,
            title: 'Change Password',
            subtitle: 'Update your sign-in password',
            onTap: () => Navigator.of(context).push(
              smoothRoute(
                ChangePasswordPage(api: widget.api),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _menuTile(
            context,
            icon: Icons.system_update_outlined,
            color: AppColors.primary,
            title: 'App Updates',
            subtitle: 'Check for and install new versions',
            onTap: () => Navigator.of(context).push(
              smoothRoute(
                const AppUpdatePage(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 200,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, color: AppColors.danger, size: 18),
                label: const Text('Log out', style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger, width: 1.5),
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuTile(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondaryText)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.secondaryText),
      ),
    );
  }
}

class _RoomFilters {
  _RoomFilters({required this.status, required this.payment, required this.chip});

  final String status;
  final String payment;
  final String? chip;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.status, required this.payment});

  final String status;
  final String payment;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _status;
  late String _payment;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _payment = widget.payment;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Filters',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _status = 'All';
                    _payment = 'All';
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Room status',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ['All', 'Occupied', 'Empty', 'Maintenance'])
                  FilterChip(
                    label: Text(s == 'Empty' ? 'Vacant' : s),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Payment status',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  {'label': 'All', 'value': 'All'},
                  {'label': 'Fully Paid', 'value': 'Fully Paid'},
                  {'label': 'Partial', 'value': 'Partial'},
                  {'label': 'Due', 'value': 'Pending'},
                  {'label': 'Overdue', 'value': 'Overdue'},
                ])
                  FilterChip(
                    label: Text(entry['label']!),
                    selected: _payment == entry['value'],
                    onSelected: (_) => setState(() => _payment = entry['value']!),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_RoomFilters(
                  status: _status,
                  payment: _payment,
                  chip: null,
                )),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onOpen});

  final Room room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Room ${room.roomNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${room.memberCount}/${room.capacity}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill.room(room.status),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (room.members.isEmpty)
                Text('No active members.', style: theme.textTheme.bodySmall)
              else
                for (final m in room.members) ...[
                  MemberRow(
                    name: m.name,
                    status: m.status,
                    rent: m.rent,
                    paid: m.paid,
                    pending: m.pending,
                    dueDate: m.dueDate,
                  ),
                  const SizedBox(height: 8),
                ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.paymentState.isEmpty || displayStatus(room.paymentState) == 'Due'
                          ? 'Due ${inr(room.totalPending)}'
                          : 'Due ${inr(room.totalPending)} · ${displayStatus(room.paymentState)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800, color: AppColors.danger),
                    ),
                  ),
                  const Icon(Icons.visibility_outlined,
                      size: 20, color: AppColors.secondaryText),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog({required this.api});

  final ApiClient api;

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final _number = TextEditingController();
  final _capacity = TextEditingController(text: '2');
  String _status = 'Empty';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final capacity = int.tryParse(_capacity.text.trim()) ?? 0;
    if (_number.text.trim().isEmpty || capacity < 1) {
      setState(() => _error = 'Enter a room number and a capacity of at least 1.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.createRoom(
        roomNumber: _number.text.trim(),
        capacity: capacity,
        status: _status,
      );
      if (!mounted) return;
      toastOk(context, 'Room ${_number.text.trim()} added.');
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
    return AlertDialog(
      title: const Text('Add room'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              ShakeOnError(
                trigger: _error,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Room number'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              decoration: const InputDecoration(labelText: 'Capacity'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const ['Empty', 'Occupied', 'Maintenance']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'Empty'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: AnimatedSwitcher(
            duration: MotionDuration.quick,
            child: _busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add room', key: ValueKey('idle')),
          ),
        ),
      ],
    );
  }
}
