import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Status -> text color. Paid green, partial amber, due red, overdue red.
/// Always paired with a readable pill label, never color alone.
Color memberStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'paid':
    case 'fully paid':
      return AppColors.success;
    case 'partial':
      return AppColors.warning;
    case 'no period':
      return AppColors.secondaryText;
    case 'overdue':
    case 'pending':
    default:
      return AppColors.danger;
  }
}

bool isOverdueStatus(String status) => status.toLowerCase() == 'overdue';

/// Display label for a rent status. Backend values stay untouched;
/// users see "Due" instead of "Pending" everywhere.
String displayStatus(String status) =>
    status.toLowerCase() == 'pending' ? 'Due' : status;

/// Soft pill background for a status.
Color memberStatusSoft(String status) {
  switch (status.toLowerCase()) {
    case 'paid':
    case 'fully paid':
      return AppColors.successSoft;
    case 'partial':
      return AppColors.warningSoft;
    case 'no period':
      return AppColors.neutralChip;
    case 'overdue':
    case 'pending':
    default:
      return AppColors.dangerSoft;
  }
}

/// Red glow used around overdue member rows.
List<BoxShadow>? memberGlow(String status) {
  if (!isOverdueStatus(status)) return null;
  return [
    BoxShadow(color: AppColors.danger.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1),
  ];
}

Color roomStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'occupied':
      return AppColors.success;
    case 'maintenance':
      return AppColors.warning;
    default:
      return AppColors.secondaryText;
  }
}

Color roomStatusSoft(String status) {
  switch (status.toLowerCase()) {
    case 'occupied':
      return AppColors.successSoft;
    case 'maintenance':
      return AppColors.warningSoft;
    default:
      return AppColors.neutralChip;
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

/// '2026-10-01T00:00:00.000Z' -> '01 Oct'. Falls back to raw text.
String fmtDateShortIso(String iso) {
  try {
    final d = DateTime.parse(iso).toUtc();
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';
  } catch (_) {
    return iso;
  }
}

/// DateTime -> '01 Oct'.
String fmtDateShort(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';

/// ISO datetime -> 'YYYY-MM-DD' for API query params.
String toDateOnlyIso(String iso) {
  try {
    return DateTime.parse(iso).toUtc().toIso8601String().substring(0, 10);
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

/// First day of the month containing [d], as 'YYYY-MM-DD'.
String monthStart(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';

/// Last day of the month containing [d], as 'YYYY-MM-DD'.
String monthEnd(DateTime d) {
  final last = DateTime(d.year, d.month + 1, 0).day;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
}

/// '2026-10' style label for a month.
String monthLabel(DateTime d) => '${_months[d.month - 1]} ${d.year}';
