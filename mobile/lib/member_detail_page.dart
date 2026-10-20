import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_form_page.dart';
import 'motion.dart';
import 'payment_drawer.dart';
import 'payment_history_page.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Member details: profile, rent facts, action buttons and payment records.
class MemberDetailPage extends StatefulWidget {
  const MemberDetailPage({
    super.key,
    required this.api,
    required this.memberId,
    required this.roomId,
    required this.roomNumber,
  });

  final ApiClient api;
  final String memberId;
  final String roomId;
  final String roomNumber;

  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  /// Last known profile, kept out of a FutureBuilder so a reload swaps the data
  /// in place instead of flashing the skeleton over content we already have.
  MemberProfile? _profile;
  bool _loading = true;
  String? _error;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [soft] keeps the current profile on screen: no skeleton, just a quiet
  /// background refresh that replaces the numbers when it lands.
  Future<void> _load({bool soft = false}) async {
    if (_inFlight) return;
    _inFlight = true;
    if (!soft && mounted) {
      setState(() => _loading = true);
    }
    try {
      final profile = await widget.api.memberProfile(widget.memberId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_profile == null) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_profile == null) {
          _error = 'Unable to load the latest data. Check your internet connection and try again.';
        }
      });
    } finally {
      _inFlight = false;
    }
  }

  void _reload() => _load(soft: _profile != null);

  Future<void> _refresh() => _load(soft: _profile != null);

  Future<void> _edit(MemberProfile profile) async {
    final updated = await Navigator.of(context).push<bool>(
      smoothRoute(
        MemberFormPage(
          api: widget.api,
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
          member: RoomMemberFormData(
            id: profile.id,
            name: profile.name,
            mobile: profile.mobile,
            monthlyRent: profile.monthlyRent,
            rentStartDate: profile.rentStartDate ?? DateTime.now(),
            aadhaarNumber: profile.aadhaar,
          ),
        ),
      ),
    );
    if (updated == true && mounted) _reload();
  }

  Future<void> _recordPayment(MemberProfile profile) async {
    final recorded = await showPaymentDrawer(
      context,
      api: widget.api,
      roomId: widget.roomId,
      roomNumber: widget.roomNumber,
      memberId: profile.id,
      memberName: profile.name,
      periodId: profile.current?.id,
    );
    if (recorded && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        // Same shadowed header as the dashboard and room details.
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('Member Details',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          if (profile != null)
            IconButton(
              tooltip: 'Edit member',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(profile),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context),
      bottomNavigationBar: profile == null ? null : _bottomActions(profile),
    );
  }

  Widget _body(BuildContext context) {
    // Skeleton only while there is nothing to show yet.
    if (_loading && _profile == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBlock(height: 90),
          SizedBox(height: 12),
          SkeletonBlock(height: 220),
          SizedBox(height: 12),
          SkeletonBlock(height: 150),
        ],
      );
    }
    final error = _error;
    if (error != null && _profile == null) {
      return ListView(children: [ErrorPanel(message: error, onRetry: () => _load())]);
    }
    final profile = _profile!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Reveal(child: _profileCard(profile)),
          const SizedBox(height: 12),
          Reveal(
            delay: MotionDuration.stagger,
            child: _infoCard(context, profile),
          ),
          const SizedBox(height: 18),
          // The ledger starts here, so it gets its own rule and a centred
          // heading instead of hanging off the facts card.
          Divider(height: 1, thickness: 1, color: AppColors.border),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Text('Payment records',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          PaymentHistoryList(
            api: widget.api,
            isAdmin: true,
            memberId: widget.memberId,
            memberName: profile.name,
            embedded: true,
            showFilters: false,
          ),
        ],
      ),
    );
  }

  Widget _profileCard(MemberProfile profile) {
    final theme = Theme.of(context);
    final active = profile.isActive;
    final color = active ? AppColors.success : AppColors.secondaryText;
    final soft = active ? AppColors.successSoft : AppColors.neutralChip;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: soft,
              child: Text(
                profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
                  if (profile.mobile.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('+91 ${profile.mobile}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondaryText,
                            fontSize: 10.5,
                            height: 1.15)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status reads as a bare dot plus its word: the coloured chip made
            // a small card feel crowded.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(active ? 'Active' : 'Vacated',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Facts as form-like fields in a two-column grid: each box carries its own
  /// label above the value, which scans faster than a label/value table.
  Widget _infoCard(BuildContext context, MemberProfile profile) {
    final theme = Theme.of(context);
    final period = profile.current;

    Widget field(String label, String value, {Color? valueColor}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText, fontSize: 9.5, height: 1.1)),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? AppColors.mainText)),
          ],
        ),
      );
    }

    final fields = <Widget>[
      field('Name', profile.name),
      if (profile.mobile.isNotEmpty) field('Mobile', '+91 ${profile.mobile}'),
      field('Aadhaar no', profile.aadhaar.isEmpty ? '—' : profile.aadhaar),
      field('Joined on',
          profile.joiningDate == null
              ? '—'
              : fmtDateIso(profile.joiningDate!.toIso8601String())),
      field('Rent amount', '${inr(profile.monthlyRent)} / month'),
      field('Rent period',
          period == null
              ? 'No period yet'
              : '${fmtDateIso(period.startIso)} – ${fmtDateIso(period.endIso)}'),
      // Exactly three money figures, and they never double count: due and
      // overdue are disjoint cycles, and the total is their sum. A cycle whose
      // due date is still in the future is in none of them.
      field('Due amt', inr(profile.due),
          valueColor: profile.due > 0 ? AppColors.warning : AppColors.success),
      field('Overdue amt', inr(profile.overdue),
          valueColor: profile.overdue > 0 ? AppColors.danger : AppColors.success),
      field('Total due amt', inr(profile.totalDue),
          valueColor: profile.totalDue > 0 ? AppColors.danger : AppColors.success),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Member facts',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final half = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final f in fields) SizedBox(width: half, child: f),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom bar matching the header: white surface, upward shadow, square
  /// full-width action.
  Widget _bottomActions(MemberProfile profile) {
    return Container(
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
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _recordPayment(profile),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record Payment'),
            ),
          ),
        ),
      ),
    );
  }
}
