import 'dart:async';
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

/// Unpaid rent carried over from cycles that have already ended.
class MemberOverdue {
  MemberOverdue({required this.period, required this.amount});

  /// Human label for the lapsed span, e.g. '12 Sep to 11 Oct'.
  final String period;
  final double amount;

  factory MemberOverdue.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return MemberOverdue(period: '${json['period']}', amount: asDouble(json['amt']));
  }

  Map<String, dynamic> toJson() => {'period': period, 'amt': amount};
}

/// A member of a room, with their own details and the rent snapshot for the
/// cycle running today.
class RoomMember {
  RoomMember({
    required this.id,
    required this.name,
    required this.rent,
    required this.paid,
    required this.pending,
    required this.status,
    required this.mobile,
    this.aadhaarNumber = '',
    this.monthlyRent = 0,
    this.rentStartDate,
    this.joiningDate,
    this.overdue,
    this.dueDate,
  });

  final String id;
  final String name;
  final double rent;
  final double paid;
  final double pending;
  final String status;

  final String mobile;
  final String aadhaarNumber;
  final double monthlyRent;
  final DateTime? rentStartDate;
  final DateTime? joiningDate;

  /// Rent still unpaid from cycles that already ended, or null when there is
  /// none. Separate from [pending], which is only the running cycle.
  final MemberOverdue? overdue;

  /// End of the member's current rent cycle (null when the backend predates it).
  final DateTime? dueDate;

  /// 0..1 fraction of rent collected. Safe when rent is 0.
  double get progress => rent <= 0 ? 0 : (paid / rent).clamp(0.0, 1.0);

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rawOverdue = json['overdue'];
    return RoomMember(
      id: '${json['id']}',
      name: '${json['name']}',
      rent: asDouble(json['rent']),
      paid: asDouble(json['paid']),
      pending: asDouble(json['pending']),
      status: '${json['status']}',
      mobile: '${json['mobile'] ?? ''}',
      aadhaarNumber: '${json['aadhaarNumber'] ?? ''}',
      monthlyRent: asDouble(json['monthlyRent']),
      rentStartDate:
          json['rentStartDate'] == null ? null : DateTime.tryParse('${json['rentStartDate']}'),
      joiningDate:
          json['joiningDate'] == null ? null : DateTime.tryParse('${json['joiningDate']}'),
      overdue: rawOverdue is Map
          ? MemberOverdue.fromJson(rawOverdue.cast<String, dynamic>())
          : null,
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
        'mobile': mobile,
        'aadhaarNumber': aadhaarNumber,
        'monthlyRent': monthlyRent,
        if (rentStartDate != null) 'rentStartDate': rentStartDate!.toIso8601String(),
        if (joiningDate != null) 'joiningDate': joiningDate!.toIso8601String(),
        if (overdue != null) 'overdue': overdue!.toJson(),
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

  /// Every request fails fast after this long. Without it a cold backend
  /// (Render spins down when idle) leaves the UI stuck on skeletons with the
  /// buttons disabled for a minute or more - which reads as a frozen app.
  static const Duration _requestTimeout = Duration(seconds: 25);

  /// Runs one HTTP call with a timeout, surfacing hangs and network failures as
  /// a normal [ApiException] so every screen shows its error panel.
  Future<http.Response> _send(Future<http.Response> Function() run) async {
    try {
      return await run().timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(
          'The server is taking too long to respond. Check your connection and try again.');
    } on http.ClientException {
      throw ApiException('Could not reach the server. Check your connection and try again.');
    }
  }

  Future<http.Response> _get(Uri uri) =>
      _send(() => http.get(uri, headers: _headers));

  Future<http.Response> _post(Uri uri, {Object? body}) =>
      _send(() => http.post(uri, headers: _headers, body: body));

  Future<http.Response> _patch(Uri uri, {Object? body}) =>
      _send(() => http.patch(uri, headers: _headers, body: body));

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
    final res = await _post(
      Uri.parse('$baseUrl/api/auth/login'),
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
    final res = await _post(
      Uri.parse('$baseUrl/api/auth/register'),
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

  /// Every room with its members, on the rent cycle running today. [status] is a
  /// room status (Occupied/Empty/Maintenance), [paymentState] is
  /// Fully Paid/Partial/Pending/Overdue. 'All'/empty means no filter.
  ///
  /// There is no text filter here: finding a room or member by name or number is
  /// [search]'s job, and historical figures come from [landlordSummary].
  ///
  /// The unfiltered list is cached on-device for offline-first startup.
  Future<List<Room>> rooms({String? status, String? paymentState}) async {
    final params = <String, String>{};
    if (status != null && status != 'All') params['status'] = status;
    if (paymentState != null && paymentState != 'All') params['paymentState'] = paymentState;
    final uri = Uri.parse('$baseUrl/api/landlord/rooms')
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await _get(uri);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['rooms'] as List? ?? []);
    final rooms = list.map((e) => Room.fromJson((e as Map).cast<String, dynamic>())).toList();
    if (_isCacheable(status: status, paymentState: paymentState)) {
      // Best-effort cache; never fail the request because of storage.
      try {
        await SessionCache.saveRooms(rooms);
      } catch (_) {
        // ignore cache write failures
      }
    }
    return rooms;
  }

  /// Portfolio totals for one period. Pass [from]/[to] ('YYYY-MM-DD'); both or
  /// neither, and with neither the server reports the current calendar month.
  Future<LandlordSummary> landlordSummary({String? from, String? to}) async {
    final params = <String, String>{};
    if (from != null && from.isNotEmpty) params['from'] = from;
    if (to != null && to.isNotEmpty) params['to'] = to;
    final uri = Uri.parse('$baseUrl/api/landlord/summary')
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await _get(uri);
    if (res.statusCode != 200) _throw(res);
    return LandlordSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Find rooms and members by one term, with no period: every hit carries
  /// whatever is current today. Matches room number (prefix), room notes, and
  /// member name / mobile / aadhaar. Rooms come first in the list, then members.
  /// [limit] caps each kind and sets [SearchResults.truncated] when hits drop.
  Future<SearchResults> search(String term, {int? limit}) async {
    final q = term.trim();
    final params = <String, String>{'search': q};
    if (limit != null) params['limit'] = '$limit';
    final uri = Uri.parse('$baseUrl/api/landlord/search').replace(queryParameters: params);
    final res = await _get(uri);
    if (res.statusCode != 200) _throw(res);
    return SearchResults.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Only the unfiltered list is cached: a filtered list always comes fresh
  /// from the server.
  bool _isCacheable({String? status, String? paymentState}) {
    if (status != null && status != 'All') return false;
    if (paymentState != null && paymentState != 'All') return false;
    return true;
  }

  /// Full room details. Pass [from]/[to] ('YYYY-MM-DD') to view another month.
  Future<RoomDetail> roomDetail(String id, {String? from, String? to}) async {
    final uri = Uri.parse('$baseUrl/api/landlord/room/$id').replace(
      queryParameters: (from != null && to != null) ? {'from': from, 'to': to} : null,
    );
    final detailRes = await _get(uri);
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
    final res = await _post(
      Uri.parse('$baseUrl/api/rooms'),
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
    final res = await _patch(
      Uri.parse('$baseUrl/api/rooms/$roomId'),
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
    final res = await _post(
      Uri.parse('$baseUrl/api/rooms/$roomId/members'),
      body: jsonEncode(data),
    );
    if (res.statusCode != 201) _throw(res);
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }

  /// Update a member (name, mobile, rent, aadhaar, dates, notes).
  Future<Map<String, dynamic>> updateMember(String memberId, Map<String, dynamic> data) async {
    final res = await _patch(
      Uri.parse('$baseUrl/api/members/$memberId'),
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
    final res = await _post(
      Uri.parse('$baseUrl/api/payments'),
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
    final res = await _get(Uri.parse('$baseUrl/api/overdue'));
    if (res.statusCode != 200) _throw(res);
    return OverdueReport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
    final res = await _get(uri);
    if (res.statusCode != 200) _throw(res);
    return PaymentsPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// A member's rent periods (for choosing which obligation is being paid).
  Future<List<MemberPeriod>> memberPeriods(String memberId) async {
    final res = await _get(Uri.parse('$baseUrl/api/landlord/member/$memberId'));
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['periods'] as List? ?? []);
    return list.map((e) => MemberPeriod.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Full member profile (info + periods + totals) for the Member Details page.
  Future<MemberProfile> memberProfile(String memberId) async {
    final res = await _get(Uri.parse('$baseUrl/api/landlord/member/$memberId'));
    if (res.statusCode != 200) _throw(res);
    return MemberProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Change the signed-in account password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/auth/change-password'),
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

/// One search hit. Rooms and members arrive in the same list, so [type] is
/// what tells them apart; [matchedOn] names the field that matched.
sealed class SearchHit {
  const SearchHit({required this.matchedOn});

  /// 'roomNumber', 'notes', 'name', 'mobile' or 'aadhaarNumber'.
  final String matchedOn;
}

/// A room whose number or notes matched.
class SearchRoomHit extends SearchHit {
  const SearchRoomHit({
    required super.matchedOn,
    required this.id,
    required this.roomNumber,
    required this.status,
    required this.capacity,
    required this.memberCount,
    required this.members,
    this.notes,
  });

  final String id;
  final String roomNumber;
  final String status;
  final int capacity;
  final String? notes;
  final int memberCount;

  /// Just enough to recognise who is in there; a room hit carries no rent
  /// figures, so open the room for those.
  final List<SearchRoomMember> members;

  factory SearchRoomHit.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final members = (json['members'] as List? ?? [])
        .map((e) => SearchRoomMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return SearchRoomHit(
      matchedOn: '${json['matchedOn'] ?? ''}',
      id: '${json['_id']}',
      roomNumber: '${json['roomNumber']}',
      status: '${json['status']}',
      capacity: asInt(json['capacity']),
      memberCount: asInt(json['memberCount']),
      notes: json['notes'] == null ? null : '${json['notes']}',
      members: members,
    );
  }
}

/// Who lives in a room hit.
class SearchRoomMember {
  SearchRoomMember({
    required this.id,
    required this.name,
    required this.mobile,
    required this.status,
  });

  final String id;
  final String name;
  final String mobile;

  /// 'active' or 'inactive'.
  final String status;

  factory SearchRoomMember.fromJson(Map<String, dynamic> json) => SearchRoomMember(
        id: '${json['id']}',
        name: '${json['name']}',
        mobile: '${json['mobile'] ?? ''}',
        status: '${json['status'] ?? 'active'}',
      );
}

/// A member whose name, mobile or aadhaar matched.
class SearchMemberHit extends SearchHit {
  const SearchMemberHit({
    required super.matchedOn,
    required this.id,
    required this.name,
    required this.mobile,
    required this.aadhaarNumber,
    required this.monthlyRent,
    required this.status,
    this.roomId,
    this.roomNumber,
    this.roomStatus,
    this.rent = 0,
    this.paid = 0,
    this.pending = 0,
    this.cycleStatus = 'No period',
    this.dueDate,
    this.vacatingDate,
    this.overdue,
  });

  final String id;
  final String name;
  final String mobile;
  final String aadhaarNumber;
  final double monthlyRent;

  /// 'active' or 'inactive'. Vacated members are still searchable.
  final String status;

  /// Null only if the member's room was deleted out from under them.
  final String? roomId;
  final String? roomNumber;
  final String? roomStatus;

  /// Rent snapshot for the cycle running today. A vacated member has none, so
  /// these stay 0 and [cycleStatus] reads 'No period'.
  final double rent;
  final double paid;
  final double pending;
  final String cycleStatus;
  final DateTime? dueDate;

  /// When they vacated, so the caller can label an inactive hit.
  final DateTime? vacatingDate;

  /// Unpaid rent from cycles that already ended.
  final MemberOverdue? overdue;

  /// True for someone who has left, whose figures are history not dues.
  bool get isVacated => status == 'inactive';

  /// 0..1 fraction of rent collected. Safe when rent is 0.
  double get progress => rent <= 0 ? 0 : (paid / rent).clamp(0.0, 1.0);

  factory SearchMemberHit.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final cycle = (json['currentCycle'] as Map?)?.cast<String, dynamic>();
    final room = (json['room'] as Map?)?.cast<String, dynamic>();
    final overdue = (json['overdue'] as Map?)?.cast<String, dynamic>();
    return SearchMemberHit(
      matchedOn: '${json['matchedOn'] ?? ''}',
      id: '${json['id']}',
      name: '${json['name']}',
      mobile: '${json['mobile'] ?? ''}',
      aadhaarNumber: '${json['aadhaarNumber'] ?? ''}',
      monthlyRent: asDouble(json['monthlyRent']),
      status: '${json['status'] ?? 'active'}',
      roomId: room == null ? null : '${room['_id']}',
      roomNumber: room == null ? null : '${room['roomNumber']}',
      roomStatus: room == null ? null : '${room['status']}',
      rent: asDouble(cycle?['rent']),
      paid: asDouble(cycle?['paid']),
      pending: asDouble(cycle?['pending']),
      cycleStatus: cycle == null ? 'No period' : '${cycle['status']}',
      dueDate: cycle == null || cycle['dueDate'] == null
          ? null
          : DateTime.tryParse('${cycle['dueDate']}'),
      vacatingDate: json['vacatingDate'] == null
          ? null
          : DateTime.tryParse('${json['vacatingDate']}'),
      overdue: overdue == null ? null : MemberOverdue.fromJson(overdue),
    );
  }
}

/// The response of /api/landlord/search: one flat list of hits, rooms first.
class SearchResults {
  SearchResults({
    required this.query,
    required this.results,
    required this.roomCount,
    required this.memberCount,
    required this.truncated,
  });

  final String query;
  final List<SearchHit> results;

  /// True totals, so they stay right even when [results] was capped.
  final int roomCount;
  final int memberCount;

  /// True when hits were dropped by the limit, so the caller can say so.
  final bool truncated;

  int get total => roomCount + memberCount;

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final hits = (json['results'] as List? ?? []).map((e) {
      final map = (e as Map).cast<String, dynamic>();
      return switch ('${map['type']}') {
        'room' => SearchRoomHit.fromJson(map),
        _ => SearchMemberHit.fromJson(map),
      };
    }).toList();
    return SearchResults(
      query: '${json['query'] ?? ''}',
      results: hits,
      roomCount: asInt(json['roomCount']),
      memberCount: asInt(json['memberCount']),
      truncated: json['truncated'] == true,
    );
  }
}

/// Portfolio totals for one period, as returned by /api/landlord/summary.
///
/// Rent figures cover one cycle per member - the one running in the reported
/// period - so a member whose cycle straddles the month boundary is counted
/// once. Outstanding money is split by whether the cycle has started, so a
/// cycle that has not begun yet (next month's rent) is never counted as due.
class LandlordSummary {
  LandlordSummary({
    required this.from,
    required this.to,
    required this.totalRent,
    required this.collected,
    required this.due,
    required this.overdue,
    required this.expense,
    required this.totalRooms,
    required this.totalMembers,
    required this.notYetDue,
    required this.receivedInRange,
    required this.paymentCount,
  });

  /// The period these figures describe, as 'YYYY-MM-DD'.
  final String from;
  final String to;

  /// Rent owed for this period.
  final double totalRent;

  /// Rent of this period that has been paid.
  final double collected;

  /// Unpaid rent on a cycle that has already started - owed now.
  final double due;

  /// Unpaid rent from cycles that already ended, carried over from earlier
  /// months. Separate from [due] because it is not this period's rent.
  final double overdue;

  /// Expenses booked in this period. Always 0 until expense tracking exists.
  final double expense;

  final int totalRooms;
  final int totalMembers;

  /// Unpaid rent on a cycle that has not started yet. Reported so [totalRent]
  /// reconciles; deliberately not part of [due].
  final double notYetDue;

  /// Cash received during the period, which is not the same as [collected]
  /// when someone pays an older cycle this month.
  final double receivedInRange;
  final int paymentCount;

  /// Everything still outstanding for this period: due plus rent not yet owed.
  double get outstanding => due + notYetDue;

  /// Collection progress for this period, 0..1. Safe when rent is 0.
  double get collectedFraction => totalRent <= 0 ? 0 : (collected / totalRent).clamp(0.0, 1.0);

  factory LandlordSummary.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return LandlordSummary(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      totalRent: asDouble(json['totalRent']),
      collected: asDouble(json['collected']),
      due: asDouble(json['due']),
      overdue: asDouble(json['overdue']),
      expense: asDouble(json['expense']),
      totalRooms: asInt(json['totalRooms']),
      totalMembers: asInt(json['totalMembers']),
      notYetDue: asDouble(json['notYetDue']),
      receivedInRange: asDouble(json['receivedInRange']),
      paymentCount: asInt(json['paymentCount']),
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
    this.allocations = const [],
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

  /// Per-cycle credit ledger (empty on payments recorded before it existed).
  /// A spanning payment lists each cycle it cleared, so the card can show the
  /// exact overdue cycle the money went to.
  final List<PaymentAllocation> allocations;

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
      allocations: (json['allocations'] as List? ?? [])
          .map((e) => PaymentAllocation.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// One cycle credited by a [PaymentRecord].
class PaymentAllocation {
  PaymentAllocation({
    required this.amount,
    required this.overdue,
    required this.periodStartIso,
    required this.periodEndIso,
  });

  final double amount;
  final bool overdue;
  final String periodStartIso;
  final String periodEndIso;

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PaymentAllocation(
      amount: asDouble(json['amount']),
      overdue: json['overdue'] == true,
      periodStartIso: '${json['periodStart'] ?? ''}',
      periodEndIso: '${json['periodEnd'] ?? ''}',
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
    this.isClosed = false,
  });

  final String id;
  final String startIso;
  final String endIso;
  final double rent;
  final double paid;
  final double pending;
  final String status;

  /// A closed cycle cannot accept payments, so it never appears in the
  /// allocation waterfall.
  final bool isClosed;

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
      isClosed: json['isClosed'] == true,
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
