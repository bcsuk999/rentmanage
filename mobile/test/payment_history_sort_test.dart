import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanage/api.dart';
import 'package:rentmanage/payment_history_page.dart';

PaymentRecord _record(String id, String dateIso, {String createdAtIso = ''}) =>
    PaymentRecord(
      id: id,
      amount: 1000,
      dateIso: dateIso,
      method: 'Cash',
      reference: '',
      notes: '',
      memberName: 'Test Member',
      memberMobile: '',
      roomNumber: '101',
      periodStartIso: '',
      periodEndIso: '',
      createdAtIso: createdAtIso,
    );

void main() {
  group('sortPaymentsNewestFirst', () {
    test('puts the most recent payment card on top', () {
      final rows = [
        _record('old', '2026-09-01T00:00:00.000Z'),
        _record('new', '2026-10-01T00:00:00.000Z'),
        _record('mid', '2026-09-15T00:00:00.000Z'),
      ];

      sortPaymentsNewestFirst(rows);

      expect(rows.map((r) => r.id).toList(), ['new', 'mid', 'old']);
    });

    test('same-day payments fall back to when they were saved', () {
      final rows = [
        _record(
          'first',
          '2026-10-01T00:00:00.000Z',
          createdAtIso: '2026-10-01T09:00:00.000Z',
        ),
        _record(
          'second',
          '2026-10-01T00:00:00.000Z',
          createdAtIso: '2026-10-01T18:00:00.000Z',
        ),
      ];

      sortPaymentsNewestFirst(rows);

      expect(rows.map((r) => r.id).toList(), ['second', 'first']);
    });

    test('keeps unparseable dates at the bottom without throwing', () {
      final rows = [
        _record('broken', ''),
        _record('dated', '2026-10-01T00:00:00.000Z'),
      ];

      sortPaymentsNewestFirst(rows);

      expect(rows.map((r) => r.id).toList(), ['dated', 'broken']);
    });
  });
}
