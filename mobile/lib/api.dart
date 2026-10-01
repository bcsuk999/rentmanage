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
  });

  final String id;
  final String roomNumber;
  final String status;
  final int capacity;
  final int memberCount;
  final bool isFull;
  final String paymentState;
  final double totalPending;

  factory Room.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return Room(
      id: '${json['_id']}',
      roomNumber: '${json['roomNumber']}',
      status: '${json['status']}',
      capacity: asInt(json['capacity']),
      memberCount: asInt(json['memberCount']),
      isFull: json['isFull'] == true,
      paymentState: '${json['paymentState']}',
      totalPending: asDouble(json['totalPending']),
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

  Future<List<Room>> rooms() async {
    final res = await http.get(Uri.parse('$baseUrl/api/rooms'), headers: _headers);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['rooms'] as List? ?? []);
    return list.map((e) => Room.fromJson((e as Map).cast<String, dynamic>())).toList();
  }
}
