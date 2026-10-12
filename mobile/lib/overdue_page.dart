import 'package:flutter/material.dart';

import 'api.dart';

String _rangeLabel(DateTime? start, DateTime? end) {
  String fmt(DateTime? d) => d == null ? '?' : '${d.day}/${d.month}/${d.year}';
  return '${fmt(start)} – ${fmt(end)}';
}

/// Overdue tab: every member holding overdue rent with each overdue period.
class OverduePage extends StatefulWidget {
  const OverduePage({super.key, required this.api, required this.onAuthExpired});

  final ApiClient api;
  final VoidCallback onAuthExpired;

  @override
  State<OverduePage> createState() => _OverduePageState();
}

class _OverduePageState extends State<OverduePage> {
  late Future<OverdueReport> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OverdueReport> _load() async {
    try {
      return await widget.api.overdue();
    } on ApiException catch (e) {
      if (e.statusCode == 401) widget.onAuthExpired();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    try {
      final report = await _load();
      if (mounted) setState(() => _future = Future.value(report));
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 401) return; // signed out above
      setState(() => _future = Future.error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<OverdueReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Could not load overdue dues.';
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
          final report = snapshot.data!;
          if (report.members.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline, size: 40, color: Colors.green),
                        SizedBox(height: 8),
                        Text('No overdue rent. All clear!'),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: report.members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${report.memberCount} member${report.memberCount == 1 ? '' : 's'} overdue',
                                    style: Theme.of(context).textTheme.titleMedium),
                                Text('Tap a member to see each overdue period',
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Text(
                            '₹${report.totalOverdue.toStringAsFixed(0)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return _OverdueCard(member: report.members[index - 1]);
            },
          );
        },
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  const _OverdueCard({required this.member});

  final OverdueMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(
            member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
            style: theme.textTheme.titleMedium,
          ),
        ),
        title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Room ${member.roomNumber} · ${member.mobile}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${member.totalOverdue.toStringAsFixed(0)}',
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
            Text('${member.periodCount} period${member.periodCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall),
          ],
        ),
        children: [
          for (final p in member.periods)
            ListTile(
              dense: true,
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(_rangeLabel(p.start, p.end)),
              subtitle: Text('Rent ₹${p.rent.toStringAsFixed(0)} · Paid ₹${p.paid.toStringAsFixed(0)}'),
              trailing: Text(
                '₹${p.pending.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
