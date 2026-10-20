import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'app_update_page.dart';
import 'change_password_page.dart';
import 'member_detail_page.dart';
import 'member_form_page.dart';
import 'motion.dart';
import 'overdue_page.dart';
import 'payment_history_page.dart';
import 'room_detail_page.dart';
import 'session_cache.dart';
import 'status_colors.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.user,
    this.initialRooms,
    required this.onSignOut,
    this.onFirstFrame,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final List<Room>? initialRooms;
  final VoidCallback onSignOut;

  /// Fired once the dashboard has painted its first frame - UI only, before any
  /// data has arrived - so the shell can drop the splash covering it.
  final VoidCallback? onFirstFrame;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _tab = 0;

  /// Tab being animated away; equals [_tab] once the band has settled.
  int _prevTab = 0;

  /// Drives the horizontal band: outgoing page travels left, incoming travels
  /// in from the right, both on the same curve so they read as one strip.
  /// Rests fully settled (value 1.0) so the current tab paints at rest.
  late final AnimationController _tabBand = AnimationController(
    vsync: this,
    duration: MotionDuration.fast,
  );

  /// Curve for the whole band. Created exactly once and reused: a
  /// [CurvedAnimation] registers a status listener on its parent in the
  /// constructor and only removes it in `dispose()`, so building one inside
  /// `build` leaks a listener on [_tabBand] on every rebuild and every frame.
  late final CurvedAnimation _bandCurve = CurvedAnimation(
    parent: _tabBand,
    curve: MotionCurve.smoothOut,
  );

  /// Incoming tab: parked a full width to the right, slides home.
  late final Animation<Offset> _inSlide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(_bandCurve);

  /// Outgoing tab: rides the band off to the left.
  late final Animation<Offset> _outSlide = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-1, 0),
  ).animate(_bandCurve);

  /// Parked tab: holds at the centre (hidden by [Offstage] in the slot).
  static final Animation<Offset> _parked = AlwaysStoppedAnimation<Offset>(
    Offset.zero,
  );

  /// Lets the shell ask a parked tab to refresh itself in the background.
  final _overdueKey = GlobalKey<OverduePageState>();

  List<Room>? _rooms;
  Object? _roomsError;
  bool _roomsLoading = true;

  /// Search hits while the search box has a term; null means "not searching",
  /// which is when the room cards below are shown instead.
  List<SearchHit>? _hits;
  String? _hitsFor;

  LandlordSummary? _summary;
  bool _summaryLoading = true;
  OverdueReport? _overdueCache;
  final _search = TextEditingController();

  /// Separate guards for the two endpoints: changing the month must not
  /// discard an in-flight room list, and a new search must not discard the tiles.
  int _roomsRequestId = 0;
  int _summaryRequestId = 0;

  bool _searching = false;

  /// Drives the add-room button: labelled at the top of the rooms list, icon
  /// only once the list has scrolled away from the top.
  final _roomsScroll = ScrollController();
  bool _atTop = true;

  /// Single-role system: every signed-in landlord has full access.
  bool get _isAdmin => true;

  /// True while the box holds a term, which is what narrows the list.
  bool get _filtered => _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // The band rests settled: at 0.0 the incoming slot would sit a full
    // viewport width off-screen and the home body would look frozen.
    _tabBand.value = 1.0;
    _tabBand.addStatusListener(_onBandStatus);
    // Rebuild so the clear (X) button tracks the typed text.
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    _roomsScroll.addListener(_onRoomsScroll);
    if (widget.initialRooms != null) {
      // Show the cached list instantly, then refresh quietly in background.
      _rooms = widget.initialRooms;
      _roomsLoading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(silent: widget.initialRooms != null);
    });
    // The dashboard is on screen from this frame, whatever the network is
    // doing, so the shell can take the splash away now.
    final first = widget.onFirstFrame;
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => first());
    }
  }

  @override
  void dispose() {
    _tabBand.removeStatusListener(_onBandStatus);
    _bandCurve.dispose();
    _tabBand.dispose();
    _search.dispose();
    _roomsScroll.dispose();
    super.dispose();
  }

  /// Collapses the add-room button while the rooms list is scrolled. Kept in a
  /// listener rather than a NotificationListener so the FAB, which lives in the
  /// Scaffold, rebuilds with it.
  void _onRoomsScroll() {
    if (!_roomsScroll.hasClients) return;
    final atTop = _roomsScroll.offset <= 4;
    if (atTop != _atTop && mounted) setState(() => _atTop = atTop);
  }

  /// Collapse the outgoing slot once the band settles. Without this
  /// [_prevTab] latches onto a stale tab, so its slot keeps rendering (and
  /// re-fetching) long after the switch that created it.
  void _onBandStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _prevTab == _tab) {
      return;
    }
    setState(() => _prevTab = _tab);
  }

  /// Search fetch that keeps the current content on screen with an inline
  /// loader, and ignores responses that a newer search has superseded.
  /// Searching never touches the month tiles, so only the body is re-fetched.
  Future<void> _runSearch(String value) => _refreshList(keepList: true);

  /// The current search term, or '' when the box is empty.
  String get _term => _search.text.trim();

  /// Every room, unfiltered. No date and no search term is sent: the list is
  /// always the rent cycle running today. An expired or revoked token signs out
  /// instead of error-looping.
  Future<List<Room>> _loadRooms() async {
    try {
      return await widget.api.rooms();
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) _signOut();
      rethrow;
    }
  }

  /// Search hits for the current term. Separate from the room list because the
  /// room list cannot filter by text any more.
  Future<SearchResults> _loadSearch(String term) async {
    try {
      return await widget.api.search(term);
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) _signOut();
      rethrow;
    }
  }

  /// Portfolio totals up to today. No period is sent: the tiles are a running
  /// total, so they do not change when the room list refreshes.
  Future<LandlordSummary> _loadSummary() async {
    try {
      return await widget.api.landlordSummary();
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) _signOut();
      rethrow;
    }
  }

  /// Loads the room list and the month tiles together, for the cases that want
  /// both: first paint, pull-to-refresh and returning to the tab.
  Future<void> _refresh({
    bool silent = false,
    bool keepList = false,
    bool quiet = false,
  }) async {
    await Future.wait([
      _refreshList(silent: silent, keepList: keepList, quiet: quiet),
      _refreshSummary(),
    ]);
  }

  /// Loads the room list, or search hits when the search box has a term.
  ///
  /// [keepList] keeps the current content on screen with an inline loader (used
  /// while typing/filtering). Otherwise the previous list is cleared first, so
  /// stale rooms never linger behind a newly selected filter.
  /// [silent] keeps a cached list on screen and reports offline failures with
  /// a snackbar instead of an error panel.
  /// [quiet] is [silent] for a background refresh nobody asked for (returning to
  /// the tab), so a failure stays invisible instead of popping a snackbar.
  ///
  /// Every call bumps [_roomsRequestId]; responses from superseded requests are
  /// dropped, so rapid typing can't race or overwrite newer data.
  Future<void> _refreshList({
    bool silent = false,
    bool keepList = false,
    bool quiet = false,
  }) async {
    final id = ++_roomsRequestId;
    final term = _term;
    if (mounted) {
      setState(() {
        if (keepList || silent) {
          _searching = !silent;
        } else {
          _roomsLoading = true;
          _roomsError = null;
          _rooms = null;
        }
      });
    }
    try {
      // One term drives two different endpoints: an empty box lists every room,
      // a non-empty one searches. [_rooms] is deliberately left intact while
      // searching so clearing the box again does not need another round trip.
      final results = term.isEmpty ? null : await _loadSearch(term);
      if (!mounted || id != _roomsRequestId) return;
      final rooms = term.isEmpty ? await _loadRooms() : null;
      if (!mounted || id != _roomsRequestId) return;
      setState(() {
        if (rooms != null) _rooms = rooms;
        _hits = results?.results;
        _hitsFor = term;
        _roomsError = null;
        _roomsLoading = false;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || id != _roomsRequestId) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() {
        _roomsLoading = false;
        _searching = false;
      });
      if (silent && !quiet) {
        // Cached list stays on screen; mention the stale data quietly.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline — showing saved rooms.')),
        );
      } else if (!silent) {
        setState(() {
          _roomsError = e;
          _rooms = null;
          _hits = null;
          _hitsFor = null;
        });
      }
    }
  }

  /// Loads the summary tiles. A failure here never blocks the room list: the grid
  /// keeps its last known figures rather than showing an error panel.
  Future<void> _refreshSummary() async {
    final id = ++_summaryRequestId;
    if (mounted) setState(() => _summaryLoading = true);
    try {
      final summary = await _loadSummary();
      if (!mounted || id != _summaryRequestId) return;
      setState(() {
        _summary = summary;
        _summaryLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _summaryRequestId) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() => _summaryLoading = false);
    }
  }

  /// Single entry point for tab changes. The band always runs the same way -
  /// whatever the index, the new page enters from the right and the old one
  /// leaves to the left - so every switch looks identical to the thumb.
  void _goToTab(int next) {
    if (next == _tab) return;
    setState(() {
      _prevTab = _tab;
      _tab = next;
    });
    _tabBand.forward(from: 0);
    // Refresh after the band settles so the fetch overlaps the slide instead of
    // competing with it. Parked data is already on screen, so it is invisible.
    Future<void>.delayed(MotionDuration.fast, () {
      if (!mounted) return;
      if (next == 1) {
        _overdueKey.currentState?.refreshSilently();
      } else if (next == 0) {
        // Same idea for the rooms list: keepList leaves the cards and the
        // summary tiles on screen while the numbers refresh underneath.
        _refresh(keepList: true, silent: true, quiet: true);
      }
    });
  }

  Future<void> _useCached() async {
    List<Room>? cached;
    try {
      cached = await SessionCache.loadRooms();
    } catch (_) {
      cached = null;
    }
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _rooms = cached;
        _roomsError = null;
        _roomsLoading = false;
      });
    } else {
      _refresh();
    }
  }

  void _signOut() {
    widget.api.token = null;
    widget.onSignOut();
  }

  void _openDetails(Room room) => _openRoom(room.id, room.roomNumber);

  /// Rooms are identified by id and number only, so a search hit can open the
  /// same page without a full [Room] to hand.
  void _openRoom(String roomId, String roomNumber) async {
    await Navigator.of(context).push(
      smoothRoute(
        RoomDetailPage(
          api: widget.api,
          roomId: roomId,
          roomNumber: roomNumber,
          isAdmin: _isAdmin,
        ),
      ),
    );
    // Members/payments may have changed inside details — reload so the
    // cards behind never show stale occupancy or totals.
    if (mounted) {
      _refreshList(keepList: true);
    }
  }

  /// Open a member straight from a search hit. Skipped when the hit has no
  /// room, since the member page needs one to scope its payments.
  Future<void> _openMember(SearchMemberHit hit) async {
    if (hit.roomId == null) return;
    await Navigator.of(context).push(
      smoothRoute(
        MemberDetailPage(
          api: widget.api,
          memberId: hit.id,
          roomId: hit.roomId!,
          roomNumber: hit.roomNumber ?? '',
        ),
      ),
    );
    if (mounted) _refreshList(keepList: true);
  }

  Future<void> _showAddRoom() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(_drawerRoute(_AddRoomPage(api: widget.api)));
    if (created == true && mounted) {
      _refresh(keepList: true);
    }
  }

  /// The add-room form arrives like a drawer: it rises from the bottom over the
  /// dimmed dashboard instead of popping up as a dialog.
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

  /// Add a member straight from a room card that has none yet.
  Future<void> _addMemberTo(Room room) async {
    final created = await Navigator.of(context).push<bool>(
      smoothRoute(
        MemberFormPage(
          api: widget.api,
          roomId: room.id,
          roomNumber: room.roomNumber,
        ),
      ),
    );
    if (created == true && mounted) _refreshList(keepList: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Soft shadow under the header so the scrolling list reads as content
        // passing beneath it instead of blending into the bar.
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: Image.asset(
            'logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.home_work_outlined, color: AppColors.primary),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          PressScale(
            child: IconButton(
              tooltip: 'Overdue dues',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => _goToTab(1),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [_bandSlot(0), _bandSlot(1), _bandSlot(2)],
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: MotionDuration.fast,
        switchInCurve: MotionCurve.smoothOut,
        switchOutCurve: MotionCurve.easeInOut,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: (_tab == 0 && _isAdmin)
            ? _AddRoomFab(
                key: const ValueKey('fab'),
                expanded: _atTop,
                onPressed: _showAddRoom,
              )
            : const SizedBox.shrink(key: ValueKey('no-fab')),
      ),
      bottomNavigationBar: _AnimatedBottomNavBar(
        index: _tab,
        onSelected: _goToTab,
      ),
    );
  }

  /// Slot for one tab. Every tab keeps a permanent slot so its state - and any
  /// data it already fetched - survives a switch; only the two involved in the
  /// switch are visible and translated.
  ///
  /// The shape is `Offstage > AnimatedBuilder > body` for all three slots, so
  /// the element at each index keeps its runtime types across a switch. Varying
  /// the wrapper type instead would make the framework deactivate and reinflate
  /// the slot, throwing away the parked tab's State and refetching it.
  Widget _bandSlot(int tab) {
    final outgoing = tab == _prevTab && _prevTab != _tab;
    final Animation<Offset> position = tab == _tab
        ? _inSlide
        : outgoing
            ? _outSlide
            : _parked;
    return Offstage(
      offstage: tab != _tab && !outgoing,
      child: AnimatedBuilder(
        animation: position,
        // Passed as `child` so the tab subtree is built once per home-page
        // build instead of once per animation frame.
        child: _tabBody(context, tab),
        builder: (context, child) =>
            FractionalTranslation(translation: position.value, child: child),
      ),
    );
  }

  Widget _tabBody(BuildContext context, int tab) {
    return switch (tab) {
      1 => OverduePage(
          key: _overdueKey,
          api: widget.api,
          isAdmin: _isAdmin,
          onAuthExpired: _signOut,
          initialReport: _overdueCache,
          onLoaded: (report) {
            if (mounted) setState(() => _overdueCache = report);
          },
        ),
      2 => _accountTab(context),
      _ => _roomsTab(context),
    };
  }

  Widget _roomsTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _refresh(keepList: true);
      },
      child: AnimatedSwitcher(
        duration: MotionDuration.slow,
        switchInCurve: MotionCurve.smoothOut,
        switchOutCurve: MotionCurve.easeInOut,
        child: _roomsBody(context),
      ),
    );
  }

  Widget _roomsBody(BuildContext context) {
    if (_roomsLoading && _rooms == null) {
      return const SkeletonRooms(key: ValueKey('rooms-skeleton'));
    }
    if (_roomsError != null && _rooms == null) {
      final message = _roomsError is ApiException
          ? (_roomsError as ApiException).message
          : 'Unable to load the latest data. Check your internet connection and try again.';
      return ListView(
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
    }
    final rooms = _rooms ?? const <Room>[];
    // [_hitsFor] records which term the hits belong to, so the previous term's
    // results never sit under a newly typed one while the request is in flight.
    final hits = _hitsFor == _term && _term.isNotEmpty
        ? _hits ?? const <SearchHit>[]
        : null;
    // Mobile viewport everywhere: one centered phone-width column, even on
    // desktop.
    return SingleChildScrollView(
      key: ValueKey(hits == null ? 'rooms-content' : 'hits-content'),
      controller: _roomsScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryGrid(context),
              const SizedBox(height: 12),
              _searchRow(context),
              if (_searching) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              if (hits != null)
                _searchResults(context, hits)
              else if (rooms.isEmpty)
                _emptyState(context)
              else
                for (var i = 0; i < rooms.length; i++) ...[
                  Reveal(
                    key: ValueKey('room-${rooms[i].id}'),
                    delay: MotionDuration.stagger * (i % 8),
                    child: _RoomCard(
                      room: rooms[i],
                      onOpen: () => _openDetails(rooms[i]),
                      onAddMember: () => _addMemberTo(rooms[i]),
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

  Widget _summaryGrid(BuildContext context) {
    if (_summaryLoading && _summary == null) {
      return const Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBlock(height: 64)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBlock(height: 64)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBlock(height: 64)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: SkeletonBlock(height: 64)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBlock(height: 64)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBlock(height: 64)),
            ],
          ),
        ],
      );
    }
    final s = _summary;
    if (s == null) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        SummaryMetric(
          icon: Icons.wallet_outlined,
          value: inr(s.collected),
          label: 'Collected',
          color: AppColors.success,
        ),
        SummaryMetric(
          icon: Icons.schedule_outlined,
          value: inr(s.due),
          label: 'Due',
          color: AppColors.warning,
        ),
        SummaryMetric(
          icon: Icons.error_outline,
          value: inr(s.overdue),
          label: 'Overdue',
          color: AppColors.danger,
        ),
        SummaryMetric(
          icon: Icons.receipt_long_outlined,
          value: inr(s.expense),
          label: 'Expenses',
          color: AppColors.secondaryText,
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
          label: 'Total members',
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
            textInputAction: TextInputAction.search,
            // No request while typing: the magnifier button (or the keyboard's
            // search key) is the trigger, so keystrokes no longer cost a round
            // trip.
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: 'Search rooms or members...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : PressScale(
                      child: IconButton(
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
        ),
        const SizedBox(width: 6),
        _SearchButton(busy: _searching, onPressed: _submitSearch),
      ],
    );
  }

  /// Fires the search for whatever is in the box right now. Nothing is sent
  /// while typing - this (or the keyboard's search key) is the trigger.
  void _submitSearch() {
    FocusScope.of(context).unfocus();
    _runSearch(_search.text);
  }

  /// Search results as one flat list, in the order the server sends them:
  /// rooms first, then members. Every card names the field that matched, so it
  /// is obvious why a row is on screen rather than a neighbouring one.
  Widget _searchResults(BuildContext context, List<SearchHit> hits) {
    final theme = Theme.of(context);
    if (hits.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 34, color: AppColors.secondaryText),
              const SizedBox(height: 10),
              Text(
                'No matches for "$_term"',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Try a room name, a member name, or part of a mobile number.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '${hits.length} result${hits.length == 1 ? '' : 's'} for "$_term"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
        ),
        for (var i = 0; i < hits.length; i++) ...[
          Reveal(
            key: ValueKey('hit-${hits[i].runtimeType}-$i'),
            delay: MotionDuration.stagger * (i % 8),
            child: switch (hits[i]) {
              final SearchRoomHit r => _RoomHitCard(
                  hit: r,
                  matchedLabel: _matchedLabel(r.matchedOn),
                  onOpen: () => _openRoom(r.id, r.roomNumber),
                ),
              final SearchMemberHit m => _MemberHitCard(
                  hit: m,
                  matchedLabel: _matchedLabel(m.matchedOn),
                  onOpen: m.roomId == null ? null : () => _openMember(m),
                ),
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// 'roomNumber' -> 'room number', for display.
  static String _matchedLabel(String field) => switch (field) {
        'roomNumber' => 'room name',
        'aadhaarNumber' => 'aadhaar number',
        'notes' => 'room notes',
        'mobile' => 'mobile',
        'name' => 'name',
        _ => field,
      };

  Widget _emptyState(BuildContext context) {
    if (_filtered) {
      return EmptyPanel(
        icon: Icons.search_off_outlined,
        title: 'No matches',
        body: 'Try a different search term.',
        actionLabel: 'Clear search',
        onAction: () {
          _search.clear();
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
          Text(
            'Account',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
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
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (mobile.isNotEmpty)
                              Text(
                                '+91 $mobile',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.secondaryText,
                                ),
                              ),
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
            onTap: () => Navigator.of(
              context,
            ).push(smoothRoute(ChangePasswordPage(api: widget.api))),
          ),
          const SizedBox(height: 8),
          _menuTile(
            context,
            icon: Icons.system_update_outlined,
            color: AppColors.success,
            title: 'App Updates',
            onTap: () =>
                Navigator.of(context).push(smoothRoute(const AppUpdatePage())),
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 200,
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(
                    Icons.logout,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  label: const Text(
                    'Log out',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger, width: 1.5),
                    backgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return PressScale(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// Filled magnifier button to the right of the search box. The request runs
/// when it is tapped, so typing alone never hits the network.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      // Muted while the request is in flight: no spinner, the button simply
      // reads as unavailable until the results land.
      opacity: busy ? 0.45 : 1,
      duration: MotionDuration.quick,
      child: PressScale(
        enabled: !busy,
        child: Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : onPressed,
            child: const SizedBox(
              height: 48,
              width: 48,
              child: Icon(Icons.search, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onOpen, this.onAddMember});

  final Room room;
  final VoidCallback onOpen;
  final VoidCallback? onAddMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ribbon sits flush against the card's top-left corner.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
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
                      'Room ${room.roomNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Row(
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
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                // Member rows sit on a grey panel so the list reads as one block,
                // separate from the room header above it.
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: AppColors.neutralChip,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (room.members.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Center(
                              child: PressScale(
                                enabled: onAddMember != null,
                                child: OutlinedButton.icon(
                                  onPressed: onAddMember,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    backgroundColor: AppColors.card,
                                    side: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Add member'),
                                ),
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < room.members.length; i++) ...[
                            MemberRow(
                              name: room.members[i].name,
                              status: room.members[i].status,
                              rent: room.members[i].rent,
                              paid: room.members[i].paid,
                              // Outstanding balance, not just the running cycle:
                              // carry-over belongs in the amount too.
                              pending: room.members[i].totalDue,
                              dueDate: room.members[i].dueDate,
                            ),
                            if (i < room.members.length - 1)
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A room that matched. A room hit carries no rent figures by design, so this
/// shows who lives there instead of money: the money needs the room's own page.
class _RoomHitCard extends StatelessWidget {
  const _RoomHitCard({
    required this.hit,
    required this.matchedLabel,
    required this.onOpen,
  });

  final SearchRoomHit hit;
  final String matchedLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.meeting_room_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Room ${hit.roomNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${hit.memberCount}/${hit.capacity}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill.room(hit.status),
                  ],
                ),
                if (hit.notes != null && hit.notes!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    hit.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
                if (hit.members.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // Names inline so a member who matched inside this room is
                  // visible without opening it. Vacated ones are marked so a
                  // former tenant is never read as a current one.
                  Text(
                    hit.members
                        .map(
                          (m) => m.status == 'active'
                              ? m.name
                              : '${m.name} (vacated)',
                        )
                        .join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Matched on $matchedLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
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

/// A member who matched, with what they owe right now. A vacated member is shown
/// in neutral grey and labelled, because their figures are history rather than
/// money the landlord is still owed.
class _MemberHitCard extends StatelessWidget {
  const _MemberHitCard({
    required this.hit,
    required this.matchedLabel,
    required this.onOpen,
  });

  final SearchMemberHit hit;
  final String matchedLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vacated = hit.isVacated;
    final color =
        vacated ? AppColors.secondaryText : memberStatusColor(hit.cycleStatus);
    final overdue = hit.overdue;
    return PressScale(
      enabled: onOpen != null,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: vacated
                          ? AppColors.neutralChip
                          : memberStatusSoft(hit.cycleStatus),
                      child: Text(
                        hit.name.isEmpty ? '?' : hit.name[0].toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              hit.roomNumber == null
                                  ? null
                                  : 'Room ${hit.roomNumber}',
                              hit.mobile,
                            ].whereType<String>().join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    vacated
                        ? const StatusPill(
                            text: 'Vacated',
                            color: AppColors.secondaryText,
                            soft: AppColors.neutralChip,
                          )
                        : StatusPill.member(hit.cycleStatus),
                  ],
                ),
                const SizedBox(height: 10),
                if (vacated)
                  Text(
                    hit.vacatingDate == null
                        ? 'No live rent cycle.'
                        : 'Left on ${fmtDateShort(hit.vacatingDate!)} · no live rent cycle.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  )
                else if (hit.rent <= 0)
                  Text(
                    'No rent cycle running today.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  )
                else ...[
                  ThinProgress(value: hit.progress, color: color),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${inr(hit.paid)} of ${inr(hit.rent)} paid',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                      if (hit.dueDate != null)
                        Text(
                          'Due ${fmtDateShort(hit.dueDate!)} · ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      Text(
                        '${inr(hit.pending)} due',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (overdue != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Overdue ${inr(overdue.amount)} · ${overdue.period}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Matched on $matchedLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
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

/// Add-room form, shown as a full page so the route can slide in like a drawer
/// instead of popping over the list as a dialog.
class _AddRoomPage extends StatefulWidget {
  const _AddRoomPage({required this.api});

  final ApiClient api;

  @override
  State<_AddRoomPage> createState() => _AddRoomPageState();
}

class _AddRoomPageState extends State<_AddRoomPage> {
  final _number = TextEditingController();
  final _capacity = TextEditingController(text: '2');
  String _status = 'Empty';
  bool _busy = false;
  String? _error;

  /// Set once the page is being popped, so the [finally] block does not
  /// rebuild a form that is on its way out.
  bool _popping = false;

  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final capacity = int.tryParse(_capacity.text.trim()) ?? 0;
    if (_number.text.trim().isEmpty || capacity < 1) {
      setState(
        () => _error = 'Enter a room name and a capacity of at least 1.',
      );
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
      _popping = true;
      toastOk(context, 'Room ${_number.text.trim()} added.');
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: PressScale(
          enabled: !_busy,
          child: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Add Room',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              decoration: const InputDecoration(labelText: 'Room name'),
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
              items: const [
                'Empty',
                'Occupied',
                'Maintenance',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'Empty'),
            ),
          ],
        ),
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
              child: PressScale(
                enabled: !_busy,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: AnimatedSwitcher(
                    duration: MotionDuration.quick,
                    child: _busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Room', key: ValueKey('idle')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Add-room button: a labelled pill while the rooms list rests at the top,
/// then just its icon once the list scrolls. Width, clip and fade all follow
/// one tween, so the two shapes flow into each other instead of snapping.
class _AddRoomFab extends StatelessWidget {
  const _AddRoomFab({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: Tooltip(
        message: 'Add room',
        child: Material(
          color: scheme.primary,
          elevation: 6,
          shadowColor: AppColors.mainText.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_home_outlined,
                    size: 24,
                    color: scheme.onPrimary,
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 1, end: expanded ? 1 : 0),
                    duration: MotionDuration.fast,
                    curve: MotionCurve.smoothOut,
                    builder: (context, t, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: t,
                        // Without an explicit height factor the Align would try to
                        // fill the FAB slot's unbounded height.
                        heightFactor: 1,
                        child: Opacity(opacity: t, child: child),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Add room',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation with a sliding indicator pill and cross-fading icons,
/// so switching tabs reads as one continuous motion.
class _AnimatedBottomNavBar extends StatelessWidget {
  const _AnimatedBottomNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _labels = <String>['Rooms', 'Overdue', 'Account'];
  static const _icons = <(IconData, IconData)>[
    (Icons.meeting_room_outlined, Icons.meeting_room),
    (Icons.event_busy_outlined, Icons.event_busy),
    (Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + bottomInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const pillWidth = 58.0;
          const pillHeight = 30.0;
          final slot = constraints.maxWidth / _labels.length;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              // Travels between slots instead of jumping, and lands exactly as
              // the page content finishes sliding in.
              AnimatedPositioned(
                duration: MotionDuration.fast,
                curve: MotionCurve.smoothOut,
                top: 0,
                left: slot * index + (slot - pillWidth) / 2,
                width: pillWidth,
                height: pillHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _labels.length; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _icons[i].$1,
                        selectedIcon: _icons[i].$2,
                        label: _labels[i],
                        selected: index == i,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.secondaryText;
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: AnimatedSwitcher(
                  duration: MotionDuration.quick,
                  switchInCurve: MotionCurve.smoothOut,
                  switchOutCurve: MotionCurve.easeInOut,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    key: ValueKey(selected),
                    size: 22,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: MotionDuration.quick,
              curve: MotionCurve.smoothOut,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
