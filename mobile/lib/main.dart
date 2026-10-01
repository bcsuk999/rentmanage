import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'session_cache.dart';

/// Brand palette: black + white + deep cobalt blue.
const Color cobaltDeep = Color(0xFF2C3480);

void main() {
  runApp(const RentManageApp());
}

class RentManageApp extends StatefulWidget {
  const RentManageApp({super.key});

  @override
  State<RentManageApp> createState() => _RentManageAppState();
}

class _RentManageAppState extends State<RentManageApp> {
  final ApiClient _api = ApiClient(apiBaseUrl);
  Map<String, dynamic>? _user;
  List<Room>? _initialRooms;
  bool _ready = false;

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(seedColor: cobaltDeep, brightness: Brightness.light).copyWith(
    primary: cobaltDeep,
    onPrimary: Colors.white,
    secondary: Colors.black,
  );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(seedColor: cobaltDeep, brightness: Brightness.dark).copyWith(
    primary: const Color(0xFF8F96DC),
    onPrimary: Colors.black,
    secondary: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Restore cached token/user/rooms so sign-in and data survive restarts.
  Future<void> _restore() async {
    final session = await SessionCache.loadSession();
    List<Room>? cachedRooms;
    if (session.token != null) {
      _api.token = session.token;
      cachedRooms = await SessionCache.loadRooms();
    }
    if (mounted) {
      setState(() {
        _user = session.user;
        _initialRooms = cachedRooms;
        _ready = true;
      });
    }
  }

  Future<void> _handleSignedIn(Map<String, dynamic> user) async {
    final token = _api.token;
    if (token != null) {
      try {
        await SessionCache.saveSession(token, user);
      } catch (_) {
        // Sign-in still succeeds; caching is best-effort.
      }
    }
    if (mounted) {
      setState(() {
        _user = user;
        _initialRooms = null;
      });
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await SessionCache.clearSession();
    } catch (_) {
      // ignore
    }
    if (mounted) {
      setState(() {
        _user = null;
        _initialRooms = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _user != null;
    return MaterialApp(
      title: 'Rent Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: _lightScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: cobaltDeep,
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: cobaltDeep.withValues(alpha: 0.15),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: _darkScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.black,
        ),
      ),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : signedIn
              ? HomePage(
                  api: _api,
                  user: _user!,
                  initialRooms: _initialRooms,
                  onSignOut: _handleSignOut,
                )
              : LoginPage(
                  api: _api,
                  onSignedIn: _handleSignedIn,
                ),
    );
  }
}
