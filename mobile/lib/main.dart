import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'motion.dart';
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

  /// True until the cached session has been read. Nothing can be built yet, so
  /// the splash is all the user sees.
  bool _restoring = true;

  /// True once the real screen has painted its first frame. The splash stays on
  /// top until then, which is why it is a sibling of the page rather than a
  /// replacement for it.
  bool _pagePainted = false;

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
    if (mounted) {
      setState(() {
        _user = session.user;
        _initialRooms = cachedRooms;
        _restoring = false;
      });
    }
  }

  /// The real screen has painted. Take the splash away.
  void _onPagePainted() {
    if (!mounted || _pagePainted) return;
    setState(() => _pagePainted = true);
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
    // The page is built as soon as the session is known; the splash is drawn
    // over it until it reports its first frame. Nothing waits on the network,
    // so a cold backend delays the data, never the splash.
    final Widget page;
    if (_restoring) {
      page = const SizedBox.shrink();
    } else if (_user != null) {
      page = HomePage(
        api: _api,
        user: _user!,
        initialRooms: _initialRooms,
        onSignOut: _handleSignOut,
        onFirstFrame: _onPagePainted,
      );
    } else {
      page = LoginPage(
        api: _api,
        onSignedIn: _handleSignedIn,
        onFirstFrame: _onPagePainted,
      );
    }

    // Sign-in and sign-out swap the root screen. Keyed by auth state, the
    // switcher fades the old screen out while the new one rises into place, so
    // the same motion language carries the user across the auth boundary.
    final Widget shell = AnimatedSwitcher(
      duration: MotionDuration.slow,
      switchInCurve: MotionCurve.smoothOut,
      switchOutCurve: MotionCurve.easeInOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, MotionDistance.small / 100),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(
          _restoring
              ? 'restoring'
              : _user != null
                  ? 'home'
                  : 'login',
        ),
        child: page,
      ),
    );

    return MaterialApp(
      title: 'Rent Manager',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      // The reference design is light-only.
      themeMode: ThemeMode.light,
      // The splash is a sibling of the shell, not a replacement for it, so the
      // real screen keeps its state while the splash paints over it.
      home: Stack(
        fit: StackFit.expand,
        children: [
          shell,
          if (!_pagePainted) const SplashScreen(),
        ],
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
