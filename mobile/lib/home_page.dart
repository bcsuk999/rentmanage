import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'room_detail_page.dart';
import 'status_colors.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.user, required this.onSignOut});

  final ApiClient api;
  final Map<String, dynamic> user;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  late Future<List<Room>> _future;
  final _search = TextEditingController();
  Timer? _debounce;

  bool get _isAdmin => widget.user['role'] == 'admin';

  @override
  void initState() {
    super.initState();
    _future = widget.api.rooms();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _future = widget.api.rooms(search: value));
    });
  }

  Future<void> _refresh() async {
    final rooms = await widget.api.rooms(search: _search.text);
    if (mounted) setState(() => _future = Future.value(rooms));
  }

  void _signOut() {
    widget.api.token = null;
    widget.onSignOut();
  }

  void _openDetails(Room room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomDetailPage(api: widget.api, roomId: room.id, roomNumber: room.roomNumber),
      ),
    );
  }

  Future<void> _showAddRoom() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddRoomDialog(api: widget.api),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 480;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rent Manager'),
            if (!narrow)
              Text('${widget.user['name'] ?? widget.user['username'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
                      )),
          ],
        ),
        actions: [
          if (_isAdmin && _tab == 0)
            IconButton(tooltip: 'Add room', icon: const Icon(Icons.add), onPressed: _showAddRoom),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          if (!narrow)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(label: Text(_isAdmin ? 'Admin' : 'Viewer')),
            ),
          if (narrow)
            PopupMenuButton<String>(
              tooltip: 'Menu',
              onSelected: (v) {
                if (v == 'logout') _signOut();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'role',
                  enabled: false,
                  child: Text(_isAdmin ? 'Admin' : 'Viewer'),
                ),
                const PopupMenuItem(value: 'logout', child: Text('Sign out')),
              ],
            )
          else
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: _tab == 0 ? _roomsTab(context) : _accountTab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.meeting_room_outlined), label: 'Rooms'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }

  Widget _roomsTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Room>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Could not load rooms.';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 40),
                        const SizedBox(height: 8),
                        Text(message, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          final rooms = snapshot.data ?? [];
          return LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final cardWidth = maxW < 620 ? maxW : 380.0;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _searchRow(context),
                    const SizedBox(height: 12),
                    if (rooms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Text('No rooms found.'),
                      )
                    else
                      Center(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final room in rooms)
                              SizedBox(
                                width: cardWidth,
                                child: _RoomCard(
                                  room: room,
                                  onOpen: () => _openDetails(room),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _searchRow(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refresh(),
            decoration: InputDecoration(
              hintText: 'Search rooms or members…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _future = widget.api.rooms());
                      },
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        if (_isAdmin) ...[
          const SizedBox(width: 8),
          narrow
              ? IconButton.filled(
                  tooltip: 'Add room',
                  icon: const Icon(Icons.add),
                  onPressed: _showAddRoom,
                )
              : FilledButton.icon(
                  onPressed: _showAddRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('Add room'),
                ),
        ],
      ],
    );
  }

  Widget _accountTab(BuildContext context) {
    final theme = Theme.of(context);
    final name = '${widget.user['name'] ?? widget.user['username'] ?? 'Account'}';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: theme.textTheme.titleLarge),
                  Text('${widget.user['username'] ?? ''}', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Chip(label: Text(_isAdmin ? 'Admin' : 'Viewer')),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onOpen});

  final Room room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = roomStatusColor(room.status);
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top: room name + status.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Room ${room.roomNumber}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      room.status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${room.memberCount}/${room.capacity} occupied${room.isFull ? ' · Full' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              // Members with colored names + progress bars.
              if (room.members.isEmpty)
                Text('No active members.', style: theme.textTheme.bodySmall)
              else
                for (final m in room.members) ...[
                  MemberTile(
                    name: m.name,
                    status: m.status,
                    rent: m.rent,
                    paid: m.paid,
                    pending: m.pending,
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 4),
              // Bottom: totals + eye action.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Due ${inr(room.totalPending)} · ${room.paymentState}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'View room details',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: onOpen,
                  ),
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
      if (mounted) Navigator.of(context).pop(true);
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
              Container(
                width: double.infinity,
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
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add room'),
        ),
      ],
    );
  }
}
