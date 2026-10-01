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
