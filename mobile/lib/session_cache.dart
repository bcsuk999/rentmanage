import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// On-device cache: auth token + user (auto sign-in) and the last room list
/// (instant, offline-first home screen). Backed by SharedPreferences, so it
/// works on mobile, desktop and web.
class SessionCache {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _roomsKey = 'rooms_cache_json';

  /// Returns the saved token (null when signed out) and user map.
  static Future<({String? token, Map<String, dynamic>? user})> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    Map<String, dynamic>? user;
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null) {
      try {
        user = (jsonDecode(rawUser) as Map).cast<String, dynamic>();
      } catch (_) {
        user = null;
      }
    }
    if (token == null || token.isEmpty) return (token: null, user: null);
    return (token: token, user: user);
  }

  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_roomsKey);
  }

  /// Saved room list (unfiltered query only), newest last-write wins.
  static Future<List<Room>?> loadRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_roomsKey);
    if (raw == null) return null;
    try {
      final list = (jsonDecode(raw) as List).cast<Map>();
      return list.map((e) => Room.fromJson(e.cast<String, dynamic>())).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRooms(List<Room> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomsKey, jsonEncode(rooms.map((r) => r.toJson()).toList()));
  }
}
