import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class VasFlowApp extends StatelessWidget {
  const VasFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'VasFlow',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(ThemeController.instance.choice),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AuthGate(),
      ),
    );
  }
}
