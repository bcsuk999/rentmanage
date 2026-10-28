import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// On-device session and data cache.
///
/// Data is never cached permanently: all data caches use a 15-minute
/// session-based TTL. When the cache expires, or when the user signs out or the
/// token expires, the cached data is wiped immediately.
class SessionCache {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _roomsKey = 'rooms_cache_json';
  static const _roomsTimestampKey = 'rooms_cache_saved_at';
  static const _rememberedMobileKey = 'remembered_login_mobile';
  static const _rememberedPasswordKey = 'remembered_login_password';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Maximum lifetime for cached data: 15 minutes.
  static const Duration cacheTtl = Duration(minutes: 15);

  /// In-memory session cache for fast access during the active session.
  static List<Room>? _inMemoryRooms;
  static DateTime? _inMemoryRoomsTime;

  static bool _isCacheFresh(DateTime savedAt) {
    final age = DateTime.now().difference(savedAt);
    return !age.isNegative && age <= cacheTtl;
  }

  /// Decodes the JWT payload safely without external dependencies.
  /// Returns null when the token is missing or malformed.
  static Map<String, dynamic>? parseJwtPayload(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      return json is Map ? json.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the expiration date [DateTime] from a JWT token, or null if missing/invalid.
  static DateTime? getTokenExpiry(String? token) {
    final payload = parseJwtPayload(token);
    if (payload == null) return null;
    final exp = payload['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
    return null;
  }

  /// Returns true if the token is null, malformed, or past its expiration date.
  /// [buffer] allows checking if the token will expire within the buffer window.
  static bool isTokenExpired(String? token, {Duration buffer = Duration.zero}) {
    if (token == null || token.isEmpty) return true;
    final expiry = getTokenExpiry(token);
    if (expiry == null) {
      // Unparseable token is treated as expired
      return true;
    }
    return DateTime.now().isAfter(expiry.subtract(buffer));
  }

  /// Time remaining until token expires, or [Duration.zero] if already expired.
  static Duration timeUntilExpiry(String? token) {
    final expiry = getTokenExpiry(token);
    if (expiry == null) return Duration.zero;
    final diff = expiry.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Returns the saved token (null when signed out or expired) and user map.
  /// Automatically clears and returns null if the stored token has expired.
  static Future<({String? token, Map<String, dynamic>? user})>
  loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return (token: null, user: null);

      // Proactively check if the restored token is already expired
      if (isTokenExpired(token)) {
        await clearSession();
        return (token: null, user: null);
      }

      Map<String, dynamic>? user;
      final rawUser = prefs.getString(_userKey);
      if (rawUser != null) {
        try {
          user = (jsonDecode(rawUser) as Map).cast<String, dynamic>();
        } catch (_) {
          user = null;
        }
      }
      return (token: token, user: user);
    } catch (_) {
      return (token: null, user: null);
    }
  }

  static Future<void> saveSession(
    String token,
    Map<String, dynamic> user,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<({String mobile, String password})?>
  loadRememberedCredentials() async {
    final mobile = await _secureStorage.read(key: _rememberedMobileKey);
    final password = await _secureStorage.read(key: _rememberedPasswordKey);
    if (mobile == null || password == null) return null;
    return (mobile: mobile, password: password);
  }

  static Future<void> saveRememberedCredentials({
    required String mobile,
    required String password,
  }) async {
    await _secureStorage.write(key: _rememberedMobileKey, value: mobile);
    await _secureStorage.write(key: _rememberedPasswordKey, value: password);
  }

  static Future<void> clearRememberedCredentials() async {
    await _secureStorage.delete(key: _rememberedMobileKey);
    await _secureStorage.delete(key: _rememberedPasswordKey);
  }

  /// Clears only cached data (rooms), leaving user auth untouched.
  static Future<void> clearDataCache() async {
    _inMemoryRooms = null;
    _inMemoryRoomsTime = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_roomsKey);
      await prefs.remove(_roomsTimestampKey);
    } catch (_) {
      // ignore
    }
  }

  /// Clears all session credentials and data caches.
  static Future<void> clearSession() async {
    await clearDataCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (_) {
      // ignore
    }
  }

  /// Returns cached room list ONLY if saved within the 15-minute session cache TTL.
  /// If the cache is older than 15 minutes, it is automatically purged and returns null.
  static Future<List<Room>?> loadRooms() async {
    // 1. Check in-memory session cache
    if (_inMemoryRooms != null && _inMemoryRoomsTime != null) {
      if (_isCacheFresh(_inMemoryRoomsTime!)) {
        return List<Room>.of(_inMemoryRooms!);
      } else {
        _inMemoryRooms = null;
        _inMemoryRoomsTime = null;
      }
    }

    // 2. Check persistent storage with 15-minute expiration check
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_roomsTimestampKey);
      if (timestamp == null) {
        // No timestamp indicates old/permanent cache without TTL: purge it
        await clearDataCache();
        return null;
      }

      final savedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (!_isCacheFresh(savedAt)) {
        // Cache expired (> 15 minutes old): purge it
        await clearDataCache();
        return null;
      }

      final raw = prefs.getString(_roomsKey);
      if (raw == null) return null;

      try {
        final list = (jsonDecode(raw) as List).cast<Map>();
        final rooms = list
            .map((e) => Room.fromJson(e.cast<String, dynamic>()))
            .toList();
        _inMemoryRooms = rooms;
        _inMemoryRoomsTime = savedAt;
        return rooms;
      } catch (_) {
        await clearDataCache();
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Saves room list with a timestamp for 15-minute session expiration.
  static Future<void> saveRooms(List<Room> rooms) async {
    final now = DateTime.now();
    _inMemoryRooms = List<Room>.of(rooms);
    _inMemoryRoomsTime = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _roomsKey,
        jsonEncode(rooms.map((r) => r.toJson()).toList()),
      );
      await prefs.setInt(_roomsTimestampKey, now.millisecondsSinceEpoch);
    } catch (_) {
      // ignore
    }
  }
}
