import 'package:flutter/material.dart';

import 'motion.dart';

/// Design tokens from the UI redesign PRD (light theme, violet accents).
class AppColors {
  static const background = Color(0xFFF5F7FB);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF635BDB);
  static const primaryPressed = Color(0xFF5148C8);
  static const mainText = Color(0xFF172033);
  static const secondaryText = Color(0xFF64748B);
  static const border = Color(0xFFE5E9F2);
  static const skeleton = Color(0xFFE6EAF1);
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFDCFCE7);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFEF3C7);
  static const neutralChip = Color(0xFFEEF2F7);
  // Member avatars use one calm blue for everyone: the balance to their right
  // already carries the paid/overdue colour, so the avatar must not repeat it.
  static const sky = Color(0xFF0284C7);
  static const skySoft = Color(0xFFE0F2FE);
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.mainText,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    // Interaction feedback is the press-scale animation only: no ripples,
    // hover wash, focus tint or pressed-state colour anywhere in the app.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    // Every MaterialPageRoute - including ones pushed by the SDK and by any
    // screen that forgets to opt in - gets the app's side-by-side slide.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: MotionPageTransitionsBuilder(),
        TargetPlatform.iOS: MotionPageTransitionsBuilder(),
        TargetPlatform.macOS: MotionPageTransitionsBuilder(),
        TargetPlatform.windows: MotionPageTransitionsBuilder(),
        TargetPlatform.linux: MotionPageTransitionsBuilder(),
        TargetPlatform.fuchsia: MotionPageTransitionsBuilder(),
      },
    ),
    // Times New Roman ships with iOS/Windows/macOS but not Android, so the
    // fallback list keeps Android on a serif face instead of dropping to
    // Roboto. Bundling Times New Roman itself is not an option: it is a
    // proprietary Microsoft font.
    fontFamily: 'Times New Roman',
    fontFamilyFallback: const ['Liberation Serif', 'Noto Serif', 'serif'],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.mainText,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.secondaryText),
      labelStyle: const TextStyle(color: AppColors.secondaryText),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ).copyWith(overlayColor: WidgetStateProperty.all(Colors.transparent)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ).copyWith(overlayColor: WidgetStateProperty.all(Colors.transparent)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
      ).copyWith(overlayColor: WidgetStateProperty.all(Colors.transparent)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.primary.withValues(alpha: 0.14),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary);
        }
        return const IconThemeData(color: AppColors.secondaryText);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12);
        }
        return const TextStyle(color: AppColors.secondaryText, fontSize: 12);
      }),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.secondaryText,
      indicatorColor: AppColors.primary,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    snackBarTheme: SnackBarThemeData(
      // Fixed, not floating: the dashboard's FAB plus bottom nav leave too
      // little room for a floating bar on short viewports (keyboard open), which
      // trips "Floating SnackBar presented off screen".
      behavior: SnackBarBehavior.fixed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerColor: AppColors.border,
  );
}
