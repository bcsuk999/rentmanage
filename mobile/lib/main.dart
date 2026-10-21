import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'app_update_page.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'motion.dart';
import 'payment_history_page.dart';
import 'session_cache.dart';
import 'update_service.dart';
import 'widgets.dart';

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

  /// The splash is guaranteed to stay up for two seconds, then it fades away
  /// once the real screen has painted underneath it.
  static const _minimumSplash = Duration(seconds: 2);
  Timer? _splashTimer;
  bool _splashTimerDone = false;
  bool _splashVisible = true;
  bool _splashGone = false;

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    // Any 401 from any screen signs out centrally (expired/revoked token).
    _api.onAuthExpired = _handleSignOut;
    _splashTimer = Timer(_minimumSplash, () {
      if (!mounted) return;
      setState(() => _splashTimerDone = true);
      _maybeFinishSplash();
    });
    _restore();
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
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

  /// The real screen has painted. Keep the splash up for its minimum run, then
  /// fade it out; the update prompt waits until the fade finishes.
  void _onPagePainted() {
    if (!mounted || _pagePainted) return;
    setState(() => _pagePainted = true);
    _maybeFinishSplash();
  }

  /// The splash leaves only once both the 2s timer has elapsed and the real
  /// screen has painted underneath it.
  void _maybeFinishSplash() {
    if (!_splashTimerDone || !_pagePainted || !_splashVisible) return;
    setState(() => _splashVisible = false);
  }

  void _onSplashGone() {
    if (!_splashVisible && !_splashGone && mounted) {
      setState(() => _splashGone = true);
      _maybeOfferUpdate();
    }
  }

  /// Once per launch, quietly ask whether a newer build exists and offer it
  /// before the user starts working. Failures stay silent: a slow network must
  /// never get in the way of opening the app.
  Future<void> _maybeOfferUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    AppUpdateStatus status;
    try {
      status = await AppUpdateService().checkStatus();
    } catch (_) {
      return;
    }
    if (!mounted || !status.updateAvailable) return;
    final navContext = _navKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    final go = await showDialog<bool>(
      context: navContext,
      builder: (context) => _UpdateAvailableDialog(status: status),
    );
    if (go == true && mounted) {
      _navKey.currentState?.push(smoothRoute(const AppUpdatePage()));
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
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      // The reference design is light-only.
      themeMode: ThemeMode.light,
      // The toast host lives above the navigator, so toasts show on every
      // screen (including dialogs and the sign-in page).
      builder: (context, child) =>
          TopToastHost(child: child ?? const SizedBox.shrink()),
      // The splash is a sibling of the shell, not a replacement for it, so the
      // real screen keeps its state while the splash paints over it.
      home: Stack(
        fit: StackFit.expand,
        children: [
          shell,
          if (!_splashGone)
            IgnorePointer(
              ignoring: !_splashVisible,
              child: AnimatedOpacity(
                opacity: _splashVisible ? 1 : 0,
                duration: MotionDuration.slow,
                curve: MotionCurve.easeOut,
                onEnd: _onSplashGone,
                child: const SplashScreen(),
              ),
            ),
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
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -90 + t * 20,
                  right: -70 - t * 16,
                  child: _blob(240, AppColors.primary.withValues(alpha: 0.20)),
                ),
                Positioned(
                  bottom: -110 - t * 18,
                  left: -80 + t * 16,
                  child: _blob(280, AppColors.primary.withValues(alpha: 0.16)),
                ),
                Positioned(
                  top: 150 + t * 12,
                  left: -50 - t * 10,
                  child: _blob(150, AppColors.primary.withValues(alpha: 0.12)),
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
                      color: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      elevation: 16,
                      shadowColor: AppColors.primary.withValues(alpha: 0.30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'logo.png',
                            width: 148,
                            height: 148,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 148,
                                  height: 148,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(
                                    Icons.home_work_outlined,
                                    size: 54,
                                    color: Colors.white,
                                  ),
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
                  child: Text(
                    'Rent Manager',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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

/// Launch-time prompt: a compact card that names the new build, shows the
/// first few release notes, and hands off to the full update page.
class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({required this.status});

  final AppUpdateStatus status;

  List<String> get _lines {
    final raw = status.update?.message.trim() ?? '';
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim())
        .where((l) => l.isNotEmpty)
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = status.latestVersion;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.rocket_launch_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Update available',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'A newer Rent Manager build is ready to install.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'v${status.currentVersion}  →  v$version',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  "WHAT'S NEW",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in _lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            height: 5,
                            width: 5,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  AppColors.mainText.withValues(alpha: 0.82),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Update now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
