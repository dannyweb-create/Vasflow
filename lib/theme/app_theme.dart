import 'package:flutter/material.dart';

import 'brand.dart';
import 'glass_widgets.dart';

ThemeData buildTheme(AppThemeChoice choice) {
  return switch (choice) {
    AppThemeChoice.light => _light(),
    AppThemeChoice.dark => _dark(),
    AppThemeChoice.glass => _glass(),
  };
}

ThemeData _light() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: Brightness.light,
  ).copyWith(
    primary: Brand.green,
    onPrimary: Brand.onGreen,
    secondary: Brand.deepGreen,
    onSecondary: Brand.white,
    primaryContainer: Brand.mint,
    onPrimaryContainer: Brand.deepGreen,
    surface: Brand.lightBackground,
    onSurface: Brand.text,
    surfaceContainerLowest: Brand.white,
    surfaceContainerLow: Brand.white,
    surfaceContainer: const Color(0xFFF1F6F2),
    surfaceContainerHigh: Brand.white,
    surfaceContainerHighest: const Color(0xFFE9F0EB),
    outline: const Color(0xFF6B8176),
    outlineVariant: const Color(0xFFD8E5DC),
  );
  return _finish(
    scheme,
    scaffold: Brand.lightBackground,
    cardColor: Brand.white,
    cardBorder: scheme.outlineVariant,
  );
}

ThemeData _dark() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Brand.green,
    onPrimary: Brand.onGreen,
    secondary: const Color(0xFF6FD39A),
    onSecondary: Brand.onGreen,
    primaryContainer: const Color(0xFF14412C),
    onPrimaryContainer: Brand.mint,
    surface: Brand.darkBackground,
    onSurface: const Color(0xFFE6F2EA),
    surfaceContainerLowest: const Color(0xFF0B100D),
    surfaceContainerLow: const Color(0xFF18241D),
    surfaceContainer: const Color(0xFF1B2A22),
    surfaceContainerHigh: const Color(0xFF203228),
    surfaceContainerHighest: const Color(0xFF25382D),
    outline: const Color(0xFF7E9A8B),
    outlineVariant: const Color(0xFF2C4136),
  );
  return _finish(
    scheme,
    scaffold: Brand.darkBackground,
    cardColor: const Color(0xFF18241D),
    cardBorder: scheme.outlineVariant,
  );
}

ThemeData _glass() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: Brightness.light,
  ).copyWith(
    primary: Brand.green,
    onPrimary: Brand.onGreen,
    secondary: Brand.deepGreen,
    onSecondary: Brand.white,
    primaryContainer: Brand.mint,
    onPrimaryContainer: Brand.deepGreen,
    // Translucent: app bars show the glass backdrop through them.
    surface: Colors.white.withValues(alpha: 0.35),
    onSurface: Brand.text,
    // Dialogs and menus stay almost opaque so text is always readable.
    surfaceContainerLowest: Brand.white,
    surfaceContainerLow: const Color(0xFFF4FBF6),
    surfaceContainer: const Color(0xFFF1F9F4),
    surfaceContainerHigh: const Color(0xFFF4FBF6),
    surfaceContainerHighest: const Color(0xFFE6F3EA),
    outline: const Color(0xFF5F7A6D),
    outlineVariant: Colors.white.withValues(alpha: 0.8),
  );
  return _finish(
    scheme,
    scaffold: Colors.transparent,
    cardColor: Colors.white.withValues(alpha: 0.58),
    cardBorder: Colors.white.withValues(alpha: 0.8),
    extensions: const <ThemeExtension<dynamic>>[GlassStyle()],
    transitions: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: GlassPageTransitionsBuilder(),
        TargetPlatform.iOS: GlassPageTransitionsBuilder(),
      },
    ),
  );
}

ThemeData _finish(
  ColorScheme scheme, {
  required Color scaffold,
  required Color cardColor,
  required Color cardBorder,
  List<ThemeExtension<dynamic>> extensions = const <ThemeExtension<dynamic>>[],
  PageTransitionsTheme transitions = const PageTransitionsTheme(),
}) {
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    canvasColor: scheme.surfaceContainerHigh,
    extensions: extensions,
    pageTransitionsTheme: transitions,
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cardBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: buttonShape,
        textStyle: buttonText,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );

  final applied = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final textTheme = applied.copyWith(
    displaySmall: applied.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    headlineMedium: applied.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    headlineSmall: applied.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
    titleLarge: applied.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: applied.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyMedium: applied.bodyMedium?.copyWith(height: 1.35),
  );
  return base.copyWith(textTheme: textTheme);
}
