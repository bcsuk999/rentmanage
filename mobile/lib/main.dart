import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'payment_history_page.dart';
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
    PaymentHistoryListState.clearCache();
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
/// Ambient drifting circles behind a springy popup logo card.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _drift;
  late final AnimationController _pop;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
    );
    _fade = CurvedAnimation(parent: _pop, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _drift.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _drift,
          builder: (context, child) {
            final t = _drift.value;
            return Stack(
              children: [
                Positioned(
                  top: -70 + t * 18,
                  right: -60 - t * 14,
                  child: _blob(180, AppColors.primary.withValues(alpha: 0.12)),
                ),
                Positioned(
                  bottom: -80 - t * 16,
                  left: -70 + t * 14,
                  child: _blob(220, AppColors.primary.withValues(alpha: 0.10)),
                ),
                Positioned(
                  top: 120 + t * 10,
                  left: -40 - t * 8,
                  child: _blob(90, AppColors.primary.withValues(alpha: 0.08)),
                ),
                child!,
              ],
            );
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Card(
                      elevation: 12,
                      shadowColor: AppColors.primary.withValues(alpha: 0.30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'logo.png',
                            width: 132,
                            height: 132,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.home_work_outlined,
                                  size: 44, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _fade,
                  child: Text('Manage your rooms, collect rent, stay organized.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.secondaryText)),
                ),
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
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
