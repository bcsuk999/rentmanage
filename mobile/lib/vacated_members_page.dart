import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'member_detail_page.dart';
import 'motion.dart';
import 'status_colors.dart';
import 'widgets.dart';

/// Former tenants and whatever they still owe after moving out.
class VacatedMembersPage extends StatefulWidget {
  const VacatedMembersPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<VacatedMembersPage> createState() => _VacatedMembersPageState();
}

class _VacatedMembersPageState extends State<VacatedMembersPage> {
  VacatedMembersReport? _report;
  bool _loading = true;
  bool _inFlight = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _load({bool soft = false}) async {
    if (_inFlight) return false;
    _inFlight = true;
    if (!soft && mounted) setState(() => _loading = true);
    try {
      final report = await widget.api.vacatedMembers();
      if (!mounted) return false;
      setState(() {
        _report = report;
        _loading = false;
        _error = null;
      });
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        if (_report == null) _error = e.message;
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        if (_report == null) {
          _error =
              'Unable to load the latest data. Check your internet connection and try again.';
        }
      });
      return false;
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _openMember(VacatedMember member) async {
    await Navigator.of(context).push(
      smoothRoute(
        MemberDetailPage(
          api: widget.api,
          memberId: member.id,
          roomId: member.roomId,
          roomNumber: member.roomNumber,
        ),
      ),
    );
    if (mounted) _load(soft: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 8,
        scrolledUnderElevation: 8,
        shadowColor: AppColors.mainText.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        leading: const PressScale(child: BackButton()),
        centerTitle: true,
        title: const Text(
          'Vacated Members',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _report == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBlock(height: 88),
          SizedBox(height: 12),
          SkeletonBlock(height: 72),
          SizedBox(height: 12),
          SkeletonBlock(height: 72),
        ],
      );
    }
    final error = _error;
    if (error != null && _report == null) {
      return ListView(
        children: [ErrorPanel(message: error, onRetry: () => _load())],
      );
    }
    final report = _report!;
    return RefreshIndicator(
      onRefresh: () async {
        final ok = await _load(soft: true);
        if (ok && context.mounted) toastOk(context, 'Vacated list updated.');
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _summaryCards(report),
          const SizedBox(height: 8),
          if (report.members.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No vacated members.'),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: AppColors.neutralChip,
                    child: Column(
                      children: [
                        for (var i = 0; i < report.members.length; i++) ...[
                          Reveal(
                            key: ValueKey('vacated-${report.members[i].id}'),
                            delay: MotionDuration.stagger * (i % 8),
                            child: MemberRow(
                              name: report.members[i].name,
                              status: report.members[i].stillToCollect > 0
                                  ? 'Overdue'
                                  : 'Paid',
                              rent: report.members[i].totalBilled,
                              paid: report.members[i].totalCollected,
                              pending: report.members[i].stillToCollect,
                              subtitle:
                                  'Room ${report.members[i].roomNumber}'
                                  '${report.members[i].mobile.isEmpty ? '' : ' · +91 ${report.members[i].mobile}'}',
                              dueDate: report.members[i].vacatingDate,
                              dateLabel: 'Vacate on',
                              onTap: () => _openMember(report.members[i]),
                            ),
                          ),
                          if (i < report.members.length - 1)
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
            ),
        ],
      ),
    );
  }

  Widget _summaryCards(VacatedMembersReport report) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
        children: [
          SummaryMetric(
            icon: Icons.account_balance_wallet_outlined,
            value: inr(report.totalStillToCollect),
            label: 'Still to collect',
            color: AppColors.danger,
          ),
          SummaryMetric(
            icon: Icons.people_outline,
            value: '${report.memberCount}',
            label: 'Vacated members',
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
