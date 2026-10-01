import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL of the rentmanage API.
///
/// Production (Render): https://rentmanage.onrender.com
/// Local dev: `http://10.0.2.2:3000` on the Android emulator,
/// `http://localhost:3000` on iOS simulator/desktop, or
/// `http://LAN-IP:3000` on a physical phone.
const String apiBaseUrl = 'https://rentmanage.onrender.com';

class ApiException implements Exception {
  ApiException(this.message, {this.errors = const []});

  final String message;
  final List<dynamic> errors;

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
  });

  final String id;
  final String name;
  final double rent;
  final double paid;
  final double pending;
  final String status;

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
    );
  }
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
      members: rawMembers.map((e) => RoomMember.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }
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
  });

  final String memberId;
  final String name;
  final String mobile;
  final double monthlyRent;
  final double rent;
  final double paid;
  final double pending;
  final String status;

  double get progress => rent <= 0 ? 0 : (paid / rent).clamp(0.0, 1.0);

  factory RoomDetailRow.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
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

  factory RoomDetail.fromJson(Map<String, dynamic> json, Room room) {
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    final summary = (json['summary'] as Map? ?? {}).cast<String, dynamic>();
    final rows = ((json['members'] as List? ?? []).cast<Map>()).map((e) => RoomDetailRow.fromJson(e.cast<String, dynamic>())).toList();
    final historical = ((json['historical'] as List? ?? []).cast<Map>()).map((e) => VacatedEntry.fromJson(e.cast<String, dynamic>())).toList();
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
    );
  }
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;
  String? token;

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
    throw ApiException(message);
  }

  /// Returns the signed-in user map and stores the token.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    token = body['token'] as String?;
    return (body['user'] as Map).cast<String, dynamic>();
  }

  /// Room list. [search] matches room numbers and member name/mobile.
  Future<List<Room>> rooms({String? search}) async {
    final q = (search ?? '').trim();
    final uri = Uri.parse('$baseUrl/api/rooms')
        .replace(queryParameters: q.isEmpty ? null : {'search': q});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['rooms'] as List? ?? []);
    return list.map((e) => Room.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Full room details for the current rental period.
  Future<RoomDetail> roomDetail(String id) async {
    final detailRes = await http.get(Uri.parse('$baseUrl/api/rooms/$id'), headers: _headers);
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
}
