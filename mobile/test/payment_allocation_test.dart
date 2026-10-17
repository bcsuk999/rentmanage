import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanage/api.dart';
import 'package:rentmanage/payment_allocation.dart';

/// Anchor every fixture to today so the test holds whenever it runs.
final _today = DateTime.now();
DateTime _day(int offset) =>
    DateTime(_today.year, _today.month, _today.day).add(Duration(days: offset));

String _iso(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).toIso8601String();

MemberPeriod _period({
  required String id,
  required int startOffset,
  required int endOffset,
  required double pending,
  String status = 'Pending',
  bool isClosed = false,
}) =>
    MemberPeriod(
      id: id,
      startIso: _iso(_day(startOffset)),
      endIso: _iso(_day(endOffset)),
      rent: 1000,
      paid: 0,
      pending: pending,
      status: status,
      isClosed: isClosed,
    );

void main() {
  group('buildAllocationOrder', () {
    final periods = <MemberPeriod>[
      // Lapsed cycles, oldest first on input too.
      _period(id: 'ov2', startOffset: -38, endOffset: -7, pending: 2000, status: 'Overdue'),
      _period(id: 'ov1', startOffset: -70, endOffset: -39, pending: 1000, status: 'Overdue'),
      // Current cycle, then a future advance cycle.
      _period(id: 'cur', startOffset: -6, endOffset: 24, pending: 1500),
      _period(id: 'adv', startOffset: 25, endOffset: 55, pending: 1500),
      // Neither of these can take money, so neither may appear.
      _period(id: 'paid', startOffset: -100, endOffset: -69, pending: 0, status: 'Paid'),
      _period(id: 'closed', startOffset: -6, endOffset: 24, pending: 500, isClosed: true),
    ];

    test('puts lapsed cycles first, oldest first', () {
      final order = buildAllocationOrder(periods, 'ov1');
      expect(order.map((c) => c.id).toList(), ['ov1', 'ov2', 'cur', 'adv']);
    });

    test('drops closed cycles and cycles with nothing outstanding', () {
      final ids = buildAllocationOrder(periods, 'ov1').map((c) => c.id).toSet();
      expect(ids, isNot(contains('closed')));
      expect(ids, isNot(contains('paid')));
    });

    test('marks the selected cycle and the lapsed ones', () {
      final order = buildAllocationOrder(periods, 'ov1');
      expect(order.first.selected, isTrue);
      expect(order.first.overdue, isTrue);
      expect(order[2].overdue, isFalse);
      expect(order[2].selected, isFalse);
    });

    test('labels the cycle date range', () {
      final order = buildAllocationOrder(periods, 'ov1');
      expect(order.first.label, matches(RegExp(r'^\d{2} \w{3} - \d{2} \w{3}$')));
    });

    test('flags only the cycle that has not started yet as advance', () {
      final order = buildAllocationOrder(periods, 'ov1');
      expect(order.map((c) => c.advance).toList(), [false, false, false, true]);
    });

    test('a not-yet-lapsed selected cycle moves ahead of the other open ones', () {
      final order = buildAllocationOrder(periods, 'cur');
      // Lapsed cycles still lead; the selected current cycle comes next.
      expect(order.map((c) => c.id).toList(), ['ov1', 'ov2', 'cur', 'adv']);
      expect(order[2].selected, isTrue);
    });

    test('totals split into overdue and the rest', () {
      final order = buildAllocationOrder(periods, 'ov1');
      expect(overdueTotal(order), 3000);
      expect(currentTotal(order), 3000);
    });
  });

  group('previewAllocation', () {
    final cycles = buildAllocationOrder(<MemberPeriod>[
      _period(id: 'ov2', startOffset: -38, endOffset: -7, pending: 2000, status: 'Overdue'),
      _period(id: 'ov1', startOffset: -70, endOffset: -39, pending: 1000, status: 'Overdue'),
      _period(id: 'cur', startOffset: -6, endOffset: 24, pending: 1500),
    ], 'ov1');

    test('clears the oldest cycle before touching the next', () {
      final lines = previewAllocation(cycles, 1000);
      expect(lines.map((l) => l.cycle.id).toList(), ['ov1']);
      expect(lines.single.applied, 1000);
      expect(lines.single.clears, isTrue);
    });

    test('spills across cycles and reports what is left on each', () {
      final lines = previewAllocation(cycles, 2500);
      expect(lines.map((l) => l.cycle.id).toList(), ['ov1', 'ov2']);
      expect(lines[0].applied, 1000);
      expect(lines[0].clears, isTrue);
      expect(lines[1].applied, 1500);
      expect(lines[1].left, 500);
      expect(lines[1].clears, isFalse);
    });

    test('reaches the current cycle only once every lapsed one is cleared', () {
      final lines = previewAllocation(cycles, 4500);
      expect(lines.map((l) => l.cycle.id).toList(), ['ov1', 'ov2', 'cur']);
      expect(lines.last.applied, 1500);
      expect(lines.last.clears, isTrue);
    });

    test('a zero amount allocates nothing', () {
      expect(previewAllocation(cycles, 0), isEmpty);
    });

    test('an amount past the balance stops at the last cycle', () {
      final lines = previewAllocation(cycles, 99999);
      expect(lines.length, 3);
      final allocated = lines.fold<double>(0, (s, l) => s + l.applied);
      expect(allocated, 4500);
    });
  });
}