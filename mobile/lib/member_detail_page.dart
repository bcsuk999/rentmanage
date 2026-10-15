import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_form_page.dart';
import 'motion.dart';
import 'payment_history_page.dart';
import 'payment_sheet.dart';
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
  late Future<MemberProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.memberProfile(widget.memberId);
  }

  void _reload() {
    setState(() => _future = widget.api.memberProfile(widget.memberId));
  }

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
    final period = profile.current;
    if (period == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rent period to record against yet.')),
      );
      return;
    }
    final totalOverdue = profile.overdue;
    final totalCurrentDue = profile.outstanding - profile.overdue;
    final recorded = await showPaymentSheet(
      context,
      api: widget.api,
      rentPeriodId: period.id,
      memberName: profile.name,
      pending: period.pending,
      totalOverdue: totalOverdue,
      totalCurrentDue: totalCurrentDue,
      periodStart: DateTime.tryParse(period.startIso),
      periodEnd: DateTime.tryParse(period.endIso),
    );
    if (recorded && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: const Text('Member Details'),
      ),
      body: FutureBuilder<MemberProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
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
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Unable to load the latest data. Check your internet connection and try again.';
            return ListView(children: [ErrorPanel(message: message, onRetry: _reload)]);
          }
          final profile = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Reveal(child: _profileCard(profile)),
                const SizedBox(height: 12),
                Reveal(
                  delay: MotionDuration.stagger,
                  child: _infoCard(context, profile),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: MotionDuration.stagger * 2,
                  child: _actions(context, profile),
                ),
                const SizedBox(height: 18),
                Text('Payment records',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                PaymentHistoryList(
                  api: widget.api,
                  isAdmin: true,
                  memberId: widget.memberId,
                  memberName: profile.name,
                  embedded: true,
                ),
              ],
            ),
          );
        },
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: soft,
                  child: Text(
                    profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (profile.mobile.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('+91 ${profile.mobile}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.secondaryText)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _edit(profile),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                StatusPill(
                  text: active ? 'Active' : 'Vacated',
                  color: color,
                  soft: soft,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, MemberProfile profile) {
    final theme = Theme.of(context);
    final period = profile.current;
    Widget row(String label, String value, {Color? valueColor}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 140,
                  child: Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondaryText))),
              Expanded(
                  child: Text(value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600, color: valueColor))),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Member facts',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            row('Name', profile.name),
            if (profile.mobile.isNotEmpty) row('Mobile', '+91 ${profile.mobile}'),
            row('Aadhaar no', profile.aadhaar.isEmpty ? '—' : profile.aadhaar),
            row(
                'Rent period',
                period == null
                    ? 'No period yet'
                    : '${fmtDateIso(period.startIso)} – ${fmtDateIso(period.endIso)}'),
            row('Joined on',
                profile.joiningDate == null
                    ? '—'
                    : fmtDateIso(profile.joiningDate!.toIso8601String())),
            row('Rent amount', '${inr(profile.monthlyRent)} / month'),
            row('Due amount', inr(profile.outstanding),
                valueColor:
                    profile.outstanding > 0 ? AppColors.danger : AppColors.success),
            row('Overdue amount', inr(profile.overdue),
                valueColor: profile.overdue > 0 ? AppColors.danger : AppColors.success),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, MemberProfile profile) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _recordPayment(profile),
        icon: const Icon(Icons.payments_outlined, size: 18),
        label: const Text('Record Payment'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
    );
  }
}
