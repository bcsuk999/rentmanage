import 'package:flutter/material.dart';

import 'api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.user, required this.onSignOut});

  final ApiClient api;
  final Map<String, dynamic> user;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Room>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.rooms();
  }

  Future<void> _refresh() async {
    final rooms = await widget.api.rooms();
    if (mounted) setState(() => _future = Future.value(rooms));
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'occupied':
        return Colors.green.shade700;
      case 'maintenance':
        return Colors.orange.shade800;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user['role'] == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(label: Text(isAdmin ? 'Admin' : 'Viewer')),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.api.token = null;
              widget.onSignOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
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
                            onPressed: () => setState(() => _future = widget.api.rooms()),
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
            if (rooms.isEmpty) {
              return const Center(child: Text('No rooms yet.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rooms.length,
              itemBuilder: (context, index) => _RoomCard(room: rooms[index], statusColor: _statusColor(rooms[index].status)),
            );
          },
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.statusColor});

  final Room room;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 8),
            Text(
              '${room.memberCount}/${room.capacity} occupied',
              style: theme.textTheme.titleMedium,
            ),
            if (room.isFull)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Full', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pending: ₹${room.totalPending.toStringAsFixed(0)}'),
                Text(room.paymentState, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: null, // Room details screen comes next.
                child: const Text('Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
