import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';

class VasFlowApp extends StatefulWidget {
  const VasFlowApp({super.key});

  @override
  State<VasFlowApp> createState() => VasFlowAppState();
}

class VasFlowAppState extends State<VasFlowApp> {
  ThemeMode mode = ThemeMode.light;

  void toggleTheme(bool dark) {
    setState(() => mode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  // Newer Flutter versions (3.29+) require CardThemeData here, not CardTheme.
  static const CardThemeData _cardTheme = CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VasFlow',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3478F6)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: _cardTheme,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B9BFF),
          brightness: Brightness.dark,
        ),
        cardTheme: _cardTheme,
      ),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: LoginScreen(onThemeChanged: toggleTheme),
    );
  }
}
