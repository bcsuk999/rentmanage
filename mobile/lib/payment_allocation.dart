import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'status_colors.dart';

/// One cycle in the payment waterfall, ordered exactly the way the backend
/// allocates a payment: lapsed cycles oldest-first, then the cycle the payment
/// is booked against, then any remaining open cycles.
class PaymentCycle {
  PaymentCycle({
    required this.id,
    required this.label,
    required this.pending,
    required this.overdue,
    this.selected = false,
    this.advance = false,
  });

  final String id;

  /// '12 Aug - 12 Sep'
  final String label;

  /// What this cycle still owes.
  final double pending;

  /// A lapsed cycle; cleared before anything else.
  final bool overdue;

  /// The cycle the payment is being booked against.
  final bool selected;

  /// A cycle that has not started yet. Money only reaches it once every
  /// started cycle is settled, so it is listed last and called out.
  final bool advance;
}

/// Builds the waterfall for [periods] when the money lands on [selectedId].
///
/// Mirrors `addPayment` in `src/services/paymentService.js` so the preview
/// matches what the server will actually do: lapsed cycles first (oldest
/// first), then the selected cycle, then the other open cycles. Closed cycles
/// and cycles with nothing outstanding are dropped - neither can take money.
List<PaymentCycle> buildAllocationOrder(
  List<MemberPeriod> periods,
  String selectedId,
) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);

  /// Lapsed the same way the server decides it: flagged overdue, or the cycle
  /// ended on a day strictly before today.
  bool lapsed(MemberPeriod p) {
    if (p.status.toLowerCase() == 'overdue') return true;
    final e = DateTime.tryParse(p.endIso);
    if (e == null) return false;
    return DateTime(e.year, e.month, e.day).isBefore(midnight);
  }

  /// A cycle that has not started yet.
  bool notYetStarted(MemberPeriod p) {
    final s = DateTime.tryParse(p.startIso);
    if (s == null) return false;
    return DateTime(s.year, s.month, s.day).isAfter(midnight);
  }

  final open = periods.where((p) => !p.isClosed && p.pending > 0).toList();
  /// Oldest cycle first, matching the server's `sort({ startDate: 1 })`.
  List<MemberPeriod> byStart(List<MemberPeriod> list) {
    list.sort((a, b) => a.startIso.compareTo(b.startIso));
    return list;
  }

  PaymentCycle toCycle(MemberPeriod p) => PaymentCycle(
        id: p.id,
        label: _label(p),
        pending: p.pending,
        overdue: lapsed(p),
        selected: p.id == selectedId,
        advance: notYetStarted(p),
      );

  final order = <PaymentCycle>[];
  MemberPeriod? selectedPeriod;
  final lapsedCycles = <MemberPeriod>[];
  final otherCycles = <MemberPeriod>[];
  for (final p in open) {
    if (lapsed(p)) {
      lapsedCycles.add(p);
    } else {
      otherCycles.add(p);
      if (p.id == selectedId) selectedPeriod = p;
    }
  }

  // 1. Lapsed cycles, oldest first.
  order.addAll(byStart(lapsedCycles).map(toCycle));
  // 2. The cycle the payment is booked against, when it is not a lapsed one.
  if (selectedPeriod != null) order.add(toCycle(selectedPeriod));
  // 3. Every other open cycle, oldest first.
  order.addAll(
    byStart(otherCycles.where((p) => p.id != selectedId).toList()).map(toCycle),
  );

  return order;
}

/// '12 Aug - 12 Sep', or just one end when the backend sent a partial range.
String _label(MemberPeriod p) => cycleRangeLabel(p.startIso, p.endIso);

/// '12 Aug - 12 Sep', or just one end when the backend sent a partial range.
String cycleRangeLabel(String startIso, String endIso) {
  final start = DateTime.tryParse(startIso);
  final end = DateTime.tryParse(endIso);
  if (start == null && end == null) return 'Rent period';
  if (start == null) return fmtDateShort(end!);
  if (end == null) return fmtDateShort(start);
  return '${fmtDateShort(start)} - ${fmtDateShort(end)}';
}

/// One period line in an allocation breakdown: the rent cycle on the left, the
/// money that landed on it on the right. Shared by the record-payment preview
/// and the payment-records card so both read exactly the same way.
class AllocationPeriodRow extends StatelessWidget {
  const AllocationPeriodRow({
    super.key,
    required this.label,
    required this.amount,
    required this.overdue,
    this.caption,
  });

  /// '12 Aug - 12 Sep'
  final String label;

  /// Money applied to this cycle.
  final double amount;

  /// A lapsed cycle (red) as opposed to a current or advance one (violet).
  final bool overdue;

  /// Optional second line, e.g. 'Overdue period · ₹500 left'.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = overdue ? AppColors.danger : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            overdue ? Icons.error_outline : Icons.schedule_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondaryText),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            inr(amount),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// One line of the preview: how much of [amount] lands on [cycle].
class AllocationLine {
  AllocationLine({required this.cycle, required this.applied});

  final PaymentCycle cycle;
  final double applied;

  /// What is still owed on this cycle once the payment lands.
  double get left => math.max(0, cycle.pending - applied);

  bool get clears => left <= 0.004;
}

/// Splits [amount] across [cycles], oldest dues first, exactly like the server.
List<AllocationLine> previewAllocation(List<PaymentCycle> cycles, double amount) {
  var remaining = amount;
  final lines = <AllocationLine>[];
  for (final cycle in cycles) {
    if (remaining <= 0.004) break;
    final take = math.min(remaining, cycle.pending);
    if (take <= 0) continue;
    lines.add(AllocationLine(cycle: cycle, applied: take));
    remaining -= take;
  }
  return lines;
}

/// Sum of every cycle in [cycles] marked overdue.
double overdueTotal(List<PaymentCycle> cycles) =>
    cycles.where((c) => c.overdue).fold(0.0, (s, c) => s + c.pending);

/// Sum of every cycle in [cycles] that has not lapsed yet.
double currentTotal(List<PaymentCycle> cycles) =>
    cycles.where((c) => !c.overdue).fold(0.0, (s, c) => s + c.pending);