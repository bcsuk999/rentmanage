import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'session_cache.dart';

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

  @override
  void initState() {
    super.initState();
    // Any 401 from any screen signs out centrally (expired/revoked token).
    _api.onAuthExpired = _handleSignOut;
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
    // Brief branded moment; never an indefinite splash.
    await Future<void>.delayed(const Duration(milliseconds: 700));
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
      theme: buildLightTheme(),
      // The reference design is light-only.
      themeMode: ThemeMode.light,
      home: !_ready
          ? const SplashScreen()
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

/// Branded loading while startup/auth resolves. Light, brief, with retry
/// handled by callers once real screens take over.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.home_work_outlined, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text('Rent Manager',
                  style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: AppColors.mainText)),
              const SizedBox(height: 6),
              Text('Manage your rooms, collect rent, stay organized.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.secondaryText)),
              const SizedBox(height: 28),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
