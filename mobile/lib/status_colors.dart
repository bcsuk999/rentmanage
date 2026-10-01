import 'package:flutter/material.dart';

/// Rent status -> member name color.
///
/// green  = fully paid, orange = partial, red = due (pending) / overdue.
/// Overdue additionally gets a glowing red border (see [memberGlow]).
Color memberStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'paid':
    case 'fully paid':
      return Colors.green.shade700;
    case 'partial':
      return Colors.orange.shade800;
    case 'no period':
      return Colors.grey.shade600;
    case 'overdue':
    case 'pending':
    default:
      return Colors.red.shade700;
  }
}

bool isOverdueStatus(String status) => status.toLowerCase() == 'overdue';

/// Red glow used around overdue member rows.
List<BoxShadow>? memberGlow(String status) {
  if (!isOverdueStatus(status)) return null;
  final glow = Colors.red.shade600;
  return [
    BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1),
  ];
}

Color roomStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'occupied':
      return Colors.green.shade700;
    case 'maintenance':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade700;
  }
}

String inr(double value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d\d)+\d$)'),
    (m) => '${m[1]},',
  );
  return '₹$text';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// '2026-10-01T00:00:00.000Z' -> '01 Oct 2026'. Falls back to raw text.
String fmtDateIso(String iso) {
  try {
    final d = DateTime.parse(iso).toUtc();
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
  } catch (_) {
    return iso;
  }
}

/// ISO datetime -> 'YYYY-MM-DD' for API query params.
String toDateOnlyIso(String iso) {
  try {
    return DateTime.parse(iso).toUtc().toIso8601String().substring(0, 10);
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}
