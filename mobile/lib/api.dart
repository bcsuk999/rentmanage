import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_cache.dart';

/// Base URL of the rentmanage API.
///
/// Production (Render): https://rentmanage.onrender.com
/// Local dev: `http://10.0.2.2:3000` on the Android emulator,
/// `http://localhost:3000` on iOS simulator/desktop, or
/// `http://LAN-IP:3000` on a physical phone.
const String apiBaseUrl = 'https://rentmanage.onrender.com';

class ApiException implements Exception {
  ApiException(this.message, {this.errors = const [], this.statusCode});

  final String message;
  final List<dynamic> errors;

  /// HTTP status when the server answered, null on network failures.
  final int? statusCode;

  @override
  String toString() => message;
}

/// One member's current-cycle rent snapshot inside a room card.
class RoomMember {
  RoomMember({
    required this.id,
    required this.name,
    required this.rent,
    required this.paid,
    required this.pending,
    required this.status,
    this.dueDate,
  });

  final String id;
  final String name;
  final double rent;
  final double paid;
  final double pending;
  final String status;

  /// End of the member's current rent cycle (null when the backend predates it).
  final DateTime? dueDate;

  /// 0..1 fraction of rent collected. Safe when rent is 0.
  double get progress => rent <= 0 ? 0 : (paid / rent).clamp(0.0, 1.0);

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return RoomMember(
      id: '${json['id']}',
      name: '${json['name']}',
      rent: asDouble(json['rent']),
      paid: asDouble(json['paid']),
      pending: asDouble(json['pending']),
      status: '${json['status']}',
      dueDate: json['dueDate'] == null ? null : DateTime.tryParse('${json['dueDate']}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rent': rent,
        'paid': paid,
        'pending': pending,
        'status': status,
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
      };
}

class Room {
  Room({
    required this.id,
    required this.roomNumber,
    required this.status,
    required this.capacity,
    required this.memberCount,
    required this.isFull,
    required this.paymentState,
    required this.totalPending,
    required this.totalRent,
    required this.totalPaid,
    required this.members,
    this.notes,
  });

  final String id;
  final String roomNumber;
  final String status;
  final int capacity;
  final int memberCount;
  final bool isFull;
  final String paymentState;
  final double totalPending;
  final double totalRent;
  final double totalPaid;
  final List<RoomMember> members;
  final String? notes;

  factory Room.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rawMembers = (json['members'] as List? ?? []);
    return Room(
      id: '${json['_id']}',
      roomNumber: '${json['roomNumber']}',
      status: '${json['status']}',
      capacity: asInt(json['capacity']),
      memberCount: asInt(json['memberCount']),
      isFull: json['isFull'] == true,
      paymentState: '${json['paymentState']}',
      totalPending: asDouble(json['totalPending']),
      totalRent: asDouble(json['totalRent']),
      totalPaid: asDouble(json['totalPaid']),
      notes: json['notes'] == null ? null : '${json['notes']}',
      members: rawMembers.map((e) => RoomMember.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'roomNumber': roomNumber,
        'status': status,
        'capacity': capacity,
        'memberCount': memberCount,
        'isFull': isFull,
        'paymentState': paymentState,
        'totalPending': totalPending,
        'totalRent': totalRent,
        'totalPaid': totalPaid,
        'notes': notes,
        'members': members.map((m) => m.toJson()).toList(),
      };
}

/// One row of the room details screen: member + their period for the range.
class RoomDetailRow {
  RoomDetailRow({
    required this.memberId,
    required this.name,
    required this.mobile,
    required this.monthlyRent,
    required this.rent,
    required this.paid,
    required this.pending,
    required this.status,
    this.periodId,
    this.periodStart,
    this.periodEnd,
  });

  final String memberId;
  final String name;
  final String mobile;
  final double monthlyRent;
  final double rent;
  final double paid;
  final double pending;
  final String status;
  final String? periodId;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  double get progress => rent <= 0 ? 0 : (paid / rent).clamp(0.0, 1.0);

  factory RoomDetailRow.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    DateTime? asDate(dynamic v) => v == null ? null : DateTime.tryParse('$v');
    final member = (json['member'] as Map? ?? {}).cast<String, dynamic>();
    final period = (json['period'] as Map?)?.cast<String, dynamic>();
    return RoomDetailRow(
      memberId: '${member['_id']}',
      name: '${member['name']}',
      mobile: '${member['mobile'] ?? '-'}',
      monthlyRent: asDouble(member['monthlyRent']),
      rent: period == null ? 0 : asDouble(period['rentAmount']),
      paid: period == null ? 0 : asDouble(period['paidAmount']),
      pending: period == null ? 0 : asDouble(period['pendingAmount']),
      status: '${json['status'] ?? 'No period'}',
      periodId: period == null ? null : '${period['_id']}',
      periodStart: period == null ? null : asDate(period['startDate']),
      periodEnd: period == null ? null : asDate(period['endDate']),
    );
  }
}

class VacatedEntry {
  VacatedEntry({required this.name, required this.mobile, required this.vacatedOn});

  final String name;
  final String mobile;
  final String vacatedOn;

  factory VacatedEntry.fromJson(Map<String, dynamic> json) {
    return VacatedEntry(
      name: '${json['name']}',
      mobile: '${json['mobile'] ?? '-'}',
      vacatedOn: '${json['vacatingDate'] ?? '-'}',
    );
  }
}

class RoomDetail {
  RoomDetail({
    required this.room,
    required this.rows,
    required this.totalRent,
    required this.totalPaid,
    required this.totalPending,
    required this.paymentState,
    required this.capacity,
    required this.isFull,
    required this.memberCount,
    required this.historical,
    required this.rangeStartIso,
    required this.rangeEndIso,
    required this.ranges,
  });

  final Room room;
  final List<RoomDetailRow> rows;
  final double totalRent;
  final double totalPaid;
  final double totalPending;
  final String paymentState;
  final int capacity;
  final bool isFull;
  final int memberCount;
  final List<VacatedEntry> historical;

  /// Active date range, ISO strings; null when the room has no periods yet.
  final String? rangeStartIso;
  final String? rangeEndIso;

  /// All known ranges (newest first) for the month switcher.
  final List<DateRange> ranges;

  factory RoomDetail.fromJson(Map<String, dynamic> json, Room room) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final summary = (json['summary'] as Map? ?? {}).cast<String, dynamic>();
    final rows = ((json['members'] as List? ?? []).cast<Map>()).map((e) => RoomDetailRow.fromJson(e.cast<String, dynamic>())).toList();
    final historical = ((json['historical'] as List? ?? []).cast<Map>()).map((e) => VacatedEntry.fromJson(e.cast<String, dynamic>())).toList();
    final range = (json['range'] as Map?)?.cast<String, dynamic>();
    final ranges = ((json['ranges'] as List? ?? []).cast<Map>())
        .map((e) => DateRange.fromJson(e.cast<String, dynamic>()))
        .toList();
    return RoomDetail(
      room: room,
      rows: rows,
      totalRent: asDouble(summary['totalRent']),
      totalPaid: asDouble(summary['totalPaid']),
      totalPending: asDouble(summary['totalPending']),
      paymentState: '${summary['paymentState'] ?? ''}',
      capacity: asInt(json['capacity']),
      isFull: json['isFull'] == true,
      memberCount: asInt(summary['memberCount']),
      historical: historical,
      rangeStartIso: range == null ? null : '${range['start']}',
      rangeEndIso: range == null ? null : '${range['end']}',
      ranges: ranges,
    );
  }
}

/// One selectable rental month on the details screen.
class DateRange {
  DateRange({required this.startIso, required this.endIso});

  final String startIso;
  final String endIso;

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(startIso: '${json['start']}', endIso: '${json['end']}');
  }
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;
  String? token;

  /// Fired once per 401 answer (expired/revoked token) so every screen
  /// returns to sign-in instead of error-looping. Set by the app shell.
  /// Never throws: _throw still raises the ApiException for local handling.
  void Function()? onAuthExpired;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Never _throw(http.Response res) {
    String message = 'Request failed (${res.statusCode}).';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is String) message = body['error'] as String;
    } catch (_) {
      // Keep the default message when the body is not JSON.
    }
    if (res.statusCode == 401) {
      try {
        onAuthExpired?.call();
      } catch (_) {
        // Sign-out routing must never break error reporting.
      }
    }
    throw ApiException(message, statusCode: res.statusCode);
  }

  /// Returns the signed-in landlord map and stores the token.
  /// [mobile] is the 10-digit landlord mobile number.
  Future<Map<String, dynamic>> login(String mobile, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'mobile': mobile, 'password': password}),
    );
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    token = body['token'] as String?;
    return (body['user'] as Map).cast<String, dynamic>();
  }

  /// Registers a landlord with mobile + password. Returns the new user map
  /// and stores the token, same shape as [login].
  Future<Map<String, dynamic>> register({
    required String mobile,
    required String password,
    String? name,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'mobile': mobile,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    if (res.statusCode != 201) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    token = body['token'] as String?;
    return (body['user'] as Map).cast<String, dynamic>();
  }

  /// Room list. [search] matches room numbers and member name/mobile;
  /// [status] is a room status (Occupied/Empty/Maintenance), [paymentState]
  /// is Fully Paid/Partial/Pending/Overdue. 'All'/empty means no filter.
  /// [from]/[to] ('YYYY-MM-DD') scope every snapshot to that rental range
  /// instead of the current cycle. The plain current-month list is cached
  /// on-device for offline-first startup.
  Future<List<Room>> rooms(
      {String? search, String? status, String? paymentState, String? from, String? to}) async {
    final q = (search ?? '').trim();
    final params = <String, String>{};
    if (q.isNotEmpty) params['search'] = q;
    if (status != null && status != 'All') params['status'] = status;
    if (paymentState != null && paymentState != 'All') params['paymentState'] = paymentState;
    if (from != null && from.isNotEmpty) params['from'] = from;
    if (to != null && to.isNotEmpty) params['to'] = to;
    final uri =
        Uri.parse('$baseUrl/api/rooms').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['rooms'] as List? ?? []);
    final rooms = list.map((e) => Room.fromJson((e as Map).cast<String, dynamic>())).toList();
    if (_isCacheable(search: q, status: status, paymentState: paymentState, from: from, to: to)) {
      // Best-effort cache; never fail the request because of storage.
      try {
        await SessionCache.saveRooms(rooms);
      } catch (_) {
        // ignore cache write failures
      }
    }
    return rooms;
  }

  /// Only the default current-month list is cached: filtered or historical
  /// months always come fresh from the server.
  bool _isCacheable(
      {required String search, String? status, String? paymentState, String? from, String? to}) {
    if (search.isNotEmpty) return false;
    if (status != null && status != 'All') return false;
    if (paymentState != null && paymentState != 'All') return false;
    if ((from == null) != (to == null)) return false;
    if (from == null) return true;
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final last = DateTime(now.year, now.month + 1, 0);
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return from == day(first) && to == day(last);
  }

  /// Full room details. Pass [from]/[to] ('YYYY-MM-DD') to view another month.
  Future<RoomDetail> roomDetail(String id, {String? from, String? to}) async {
    final uri = Uri.parse('$baseUrl/api/rooms/$id').replace(
      queryParameters: (from != null && to != null) ? {'from': from, 'to': to} : null,
    );
    final detailRes = await http.get(uri, headers: _headers);
    if (detailRes.statusCode != 200) _throw(detailRes);
    final body = jsonDecode(detailRes.body) as Map<String, dynamic>;
    final roomJson = (body['room'] as Map).cast<String, dynamic>();
    // Reuse the list endpoint shape for the header card by merging totals.
    final room = Room(
      id: id,
      roomNumber: '${roomJson['roomNumber']}',
      status: '${roomJson['status']}',
      capacity: 0,
      memberCount: 0,
      isFull: false,
      paymentState: '',
      totalPending: 0,
      totalRent: 0,
      totalPaid: 0,
      members: const [],
    );
    return RoomDetail.fromJson(body, room);
  }

  /// Create a room (admin only).
  Future<Map<String, dynamic>> createRoom({
    required String roomNumber,
    required int capacity,
    required String status,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms'),
      headers: _headers,
      body: jsonEncode({'roomNumber': roomNumber, 'capacity': capacity, 'status': status}),
    );
    if (res.statusCode != 201) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Update a room (admin only).
  Future<Map<String, dynamic>> updateRoom({
    required String roomId,
    required String roomNumber,
    required int capacity,
    required String status,
    String? notes,
  }) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/rooms/$roomId'),
      headers: _headers,
      body: jsonEncode({
        'roomNumber': roomNumber,
        'capacity': capacity,
        'status': status,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }),
    );
    if (res.statusCode != 200) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Add a member to a room (admin only). Throws [ApiException] when full.
  Future<Map<String, dynamic>> addMember(String roomId, Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/$roomId/members'),
      headers: _headers,
      body: jsonEncode(data),
    );
    if (res.statusCode != 201) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Update a member (name, mobile, rent, aadhaar, dates, notes).
  Future<Map<String, dynamic>> updateMember(String memberId, Map<String, dynamic> data) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/members/$memberId'),
      headers: _headers,
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Record a payment against a rent period (admin only).
  Future<Map<String, dynamic>> recordPayment({
    required String rentPeriodId,
    required String amount,
    required String paymentDate,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/payments'),
      headers: _headers,
      body: jsonEncode({
        'rentPeriodId': rentPeriodId,
        'amount': amount,
        'paymentDate': paymentDate,
        'paymentMethod': paymentMethod,
        if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }),
    );
    if (res.statusCode != 201) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Members holding overdue rent, with each overdue period.
  Future<OverdueReport> overdue() async {
    final res = await http.get(Uri.parse('$baseUrl/api/overdue'), headers: _headers);
    if (res.statusCode != 200) _throw(res);
    return OverdueReport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Reporting totals for a date range (rooms summary cards).
  Future<ReportTotals> report({String? from, String? to, String? roomId}) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    if (roomId != null && roomId.isNotEmpty) params['roomId'] = roomId;
    final uri =
        Uri.parse('$baseUrl/api/reports').replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) _throw(res);
    return ReportTotals.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Paged payment history. Filters mirror the backend query params.
  Future<PaymentsPage> payments({
    String? roomId,
    String? memberId,
    String? paymentMethod,
    String? from,
    String? to,
    int page = 1,
  }) async {
    final params = <String, String>{'page': '$page'};
    if (roomId != null && roomId.isNotEmpty) params['roomId'] = roomId;
    if (memberId != null && memberId.isNotEmpty) params['memberId'] = memberId;
    if (paymentMethod != null && paymentMethod.isNotEmpty) params['paymentMethod'] = paymentMethod;
    if (from != null && from.isNotEmpty) params['from'] = from;
    if (to != null && to.isNotEmpty) params['to'] = to;
    final uri = Uri.parse('$baseUrl/api/payments').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) _throw(res);
    return PaymentsPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// A member's rent periods (for choosing which obligation is being paid).
  Future<List<MemberPeriod>> memberPeriods(String memberId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/members/$memberId'), headers: _headers);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['periods'] as List? ?? []);
    return list.map((e) => MemberPeriod.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Full member profile (info + periods + totals) for the Member Details page.
  Future<MemberProfile> memberProfile(String memberId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/members/$memberId'), headers: _headers);
    if (res.statusCode != 200) _throw(res);
    return MemberProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Change the signed-in account password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/change-password'),
      headers: _headers,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );
    if (res.statusCode != 200) _throw(res);
  }
}

/// Payment methods accepted by the API.
const List<String> paymentMethods = ['Cash', 'UPI', 'Bank Transfer', 'Other'];

/// One overdue rent period of a member.
class OverduePeriod {
  OverduePeriod({
    required this.id,
    required this.start,
    required this.end,
    required this.rent,
    required this.paid,
    required this.pending,
  });

  final String id;
  final DateTime? start;
  final DateTime? end;
  final double rent;
  final double paid;
  final double pending;

  factory OverduePeriod.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return OverduePeriod(
      id: '${json['id']}',
      start: json['startDate'] == null ? null : DateTime.tryParse('${json['startDate']}'),
      end: json['endDate'] == null ? null : DateTime.tryParse('${json['endDate']}'),
      rent: asDouble(json['rentAmount']),
      paid: asDouble(json['paidAmount']),
      pending: asDouble(json['pendingAmount']),
    );
  }
}

/// A member holding overdue rent, with each overdue period.
class OverdueMember {
  OverdueMember({
    required this.memberId,
    required this.name,
    required this.mobile,
    required this.roomNumber,
    required this.periodCount,
    required this.totalOverdue,
    required this.periods,
  });

  final String memberId;
  final String name;
  final String mobile;
  final String roomNumber;
  final int periodCount;
  final double totalOverdue;
  final List<OverduePeriod> periods;

  factory OverdueMember.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rows = (json['periods'] as List? ?? []);
    return OverdueMember(
      memberId: '${json['memberId']}',
      name: '${json['name']}',
      mobile: '${json['mobile'] ?? ''}',
      roomNumber: '${json['roomNumber'] ?? '-'}',
      periodCount: asInt(json['periodCount']),
      totalOverdue: asDouble(json['totalOverdue']),
      periods: rows.map((e) => OverduePeriod.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }
}

class OverdueReport {
  OverdueReport({required this.members, required this.memberCount, required this.totalOverdue});

  final List<OverdueMember> members;
  final int memberCount;
  final double totalOverdue;

  factory OverdueReport.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map? ?? {}).cast<String, dynamic>();
    final rows = (json['members'] as List? ?? []);
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return OverdueReport(
      members: rows.map((e) => OverdueMember.fromJson((e as Map).cast<String, dynamic>())).toList(),
      memberCount: asInt(summary['memberCount']),
      totalOverdue: asDouble(summary['totalOverdue']),
    );
  }
}

/// Reporting totals backing the Rooms summary cards.
class ReportTotals {
  ReportTotals({
    required this.totalRent,
    required this.totalPaid,
    required this.totalPending,
    required this.overduePending,
    required this.receivedInRange,
    required this.totalRooms,
    required this.totalMembers,
    required this.from,
    required this.to,
  });

  final double totalRent;
  final double totalPaid;
  final double totalPending;
  final double overduePending;
  final double receivedInRange;
  final int totalRooms;
  final int totalMembers;
  final String from;
  final String to;

  /// Outstanding rent that is not yet past its due date (current cycle).
  double get duePending {
    final due = totalPending - overduePending;
    return due < 0 ? 0 : due;
  }

  factory ReportTotals.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    // Route wraps buildReport() as { report: { totals, ... }, filters }.
    final report = (json['report'] as Map? ?? json).cast<String, dynamic>();
    final totals = (report['totals'] as Map? ?? {}).cast<String, dynamic>();
    final filters = (json['filters'] as Map? ?? {}).cast<String, dynamic>();
    return ReportTotals(
      totalRent: asDouble(totals['totalRent']),
      totalPaid: asDouble(totals['totalPaid']),
      totalPending: asDouble(totals['totalPending']),
      overduePending: asDouble(totals['overduePending']),
      receivedInRange: asDouble(totals['receivedInRange']),
      totalRooms: asInt(totals['totalRooms']),
      totalMembers: asInt(totals['totalMembers']),
      from: '${filters['from'] ?? ''}',
      to: '${filters['to'] ?? ''}',
    );
  }
}

/// One saved payment transaction.
class PaymentRecord {
  PaymentRecord({
    required this.id,
    required this.amount,
    required this.dateIso,
    required this.method,
    required this.reference,
    required this.notes,
    required this.memberName,
    required this.memberMobile,
    required this.roomNumber,
    required this.periodStartIso,
    required this.periodEndIso,
    this.createdAtIso = '',
    this.allocOverdue,
    this.allocCurrent,
  });

  final String id;
  final double amount;
  final String dateIso;
  final String method;
  final String reference;
  final String notes;
  final String memberName;
  final String memberMobile;
  final String roomNumber;
  final String periodStartIso;
  final String periodEndIso;

  /// When the record was saved; [dateIso] alone carries no clock time.
  final String createdAtIso;

  /// Split of [amount] into oldest dues and the current cycle; null when the
  /// payment predates allocation tracking.
  final double? allocOverdue;
  final double? allocCurrent;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    // Populated docs are Maps; dangling refs arrive as id strings.
    Map<String, dynamic>? asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;
    final member = asMap(json['memberId']);
    final room = asMap(json['roomId']);
    final period = asMap(json['rentPeriodId']);
    return PaymentRecord(
      id: '${json['_id']}',
      amount: asDouble(json['amount']),
      dateIso: '${json['paymentDate']}',
      method: '${json['paymentMethod']}',
      reference: '${json['reference'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      memberName: member == null ? '-' : '${member['name'] ?? '-'}',
      memberMobile: member == null ? '' : '${member['mobile'] ?? ''}',
      roomNumber: room == null ? '-' : '${room['roomNumber'] ?? '-'}',
      periodStartIso: period == null ? '' : '${period['startDate'] ?? ''}',
      periodEndIso: period == null ? '' : '${period['endDate'] ?? ''}',
      createdAtIso: '${json['createdAt'] ?? ''}',
      allocOverdue: json['allocOverdue'] == null ? null : asDouble(json['allocOverdue']),
      allocCurrent: json['allocCurrent'] == null ? null : asDouble(json['allocCurrent']),
    );
  }
}

class PaymentsPage {
  PaymentsPage({
    required this.rows,
    required this.total,
    required this.page,
    required this.pages,
    required this.totalAmount,
  });

  final List<PaymentRecord> rows;
  final int total;
  final int page;
  final int pages;
  final double totalAmount;

  factory PaymentsPage.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final rows = (json['rows'] as List? ?? []);
    return PaymentsPage(
      rows: rows.map((e) => PaymentRecord.fromJson((e as Map).cast<String, dynamic>())).toList(),
      total: asInt(json['total']),
      page: asInt(json['page']),
      pages: asInt(json['pages']),
      totalAmount: asDouble(json['totalAmount']),
    );
  }
}

/// One rent period of a member (payment target picker).
class MemberPeriod {
  MemberPeriod({
    required this.id,
    required this.startIso,
    required this.endIso,
    required this.rent,
    required this.paid,
    required this.pending,
    required this.status,
  });

  final String id;
  final String startIso;
  final String endIso;
  final double rent;
  final double paid;
  final double pending;
  final String status;

  factory MemberPeriod.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return MemberPeriod(
      id: '${json['_id']}',
      startIso: '${json['startDate']}',
      endIso: '${json['endDate']}',
      rent: asDouble(json['rentAmount']),
      paid: asDouble(json['paidAmount']),
      pending: asDouble(json['pendingAmount']),
      status: '${json['status']}',
    );
  }
}

/// Full member profile for the Member Details page: personal info,
/// rent periods and money totals (due + overdue computed on-device).
class MemberProfile {
  MemberProfile({
    required this.member,
    required this.periods,
    required this.outstanding,
    required this.paidTotal,
    required this.futurePending,
    required this.roomNumber,
  });

  final Map<String, dynamic> member;
  final List<MemberPeriod> periods;
  final double outstanding;
  final double paidTotal;
  final double futurePending;
  final String roomNumber;

  String get id => '${member['_id']}';
  String get name => '${member['name']}';
  String get mobile => '${member['mobile'] ?? ''}';
  String get aadhaar => '${member['aadhaarNumber'] ?? ''}';
  String get status => '${member['status'] ?? 'active'}';
  bool get isActive => status.toLowerCase() == 'active';

  double get monthlyRent {
    final v = member['monthlyRent'];
    return v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  }

  DateTime? get rentStartDate => _asDate(member['rentStartDate']);
  DateTime? get joiningDate => _asDate(member['joiningDate']) ?? rentStartDate;

  static DateTime? _asDate(dynamic v) => v == null ? null : DateTime.tryParse('$v');

  /// The period covering today, else the latest started one, else the newest.
  MemberPeriod? get current {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    for (final p in periods) {
      final s = DateTime.tryParse(p.startIso);
      final e = DateTime.tryParse(p.endIso);
      if (s == null || e == null) continue;
      if (!day.isBefore(DateTime(s.year, s.month, s.day)) &&
          !day.isAfter(DateTime(e.year, e.month, e.day))) {
        return p;
      }
    }
    final started = periods.where((p) {
      final s = DateTime.tryParse(p.startIso);
      return s != null && !DateTime(s.year, s.month, s.day).isAfter(day);
    }).toList();
    if (started.isNotEmpty) return started.first;
    return periods.isNotEmpty ? periods.first : null;
  }

  /// Pending rent on periods whose end date already passed.
  double get overdue {
    final now = DateTime.now();
    double sum = 0;
    for (final p in periods) {
      final e = DateTime.tryParse(p.endIso);
      if (e == null) continue;
      final endOfDay = DateTime(e.year, e.month, e.day, 23, 59, 59);
      if (endOfDay.isBefore(now) && p.pending > 0) sum += p.pending;
    }
    return sum;
  }

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final member = (json['member'] as Map? ?? {}).cast<String, dynamic>();
    final periods = ((json['periods'] as List? ?? []).cast<Map>())
        .map((e) => MemberPeriod.fromJson(e.cast<String, dynamic>()))
        .toList();
    final room = (json['room'] as Map?)?.cast<String, dynamic>();
    return MemberProfile(
      member: member,
      periods: periods,
      outstanding: asDouble(json['outstanding']),
      paidTotal: asDouble(json['paidTotal']),
      futurePending: asDouble(json['futurePending']),
      roomNumber: '${room?['roomNumber'] ?? ''}',
    );
  }
}
