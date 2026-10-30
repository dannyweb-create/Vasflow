import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasflow/screens/settings_screen.dart';
import 'package:vasflow/services/auth_service.dart';
import 'package:vasflow/theme/app_theme.dart';
import 'package:vasflow/theme/brand.dart';
import 'package:vasflow/theme/theme_controller.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('all three themes use the brand green and Liquid Glass is marked', () {
    for (final choice in AppThemeChoice.values) {
      expect(buildTheme(choice).colorScheme.primary, Brand.green);
    }
    expect(buildTheme(AppThemeChoice.glass).extension<GlassStyle>(), isNotNull);
    expect(buildTheme(AppThemeChoice.light).extension<GlassStyle>(), isNull);
    expect(buildTheme(AppThemeChoice.dark).brightness, Brightness.dark);
  });

  test('text is readable on every theme background', () {
    final light = buildTheme(AppThemeChoice.light).colorScheme;
    final dark = buildTheme(AppThemeChoice.dark).colorScheme;
    final glass = buildTheme(AppThemeChoice.glass).colorScheme;
    expect(contrast(light.onSurface, light.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(dark.onSurface, dark.surface), greaterThanOrEqualTo(4.5));
    // Glass text sits on the pale mint backdrop.
    expect(
      contrast(glass.onSurface, const Color(0xFFD3F0DE)),
      greaterThanOrEqualTo(4.5),
    );
    // Labels on the brand-green buttons.
    expect(contrast(light.onPrimary, light.primary), greaterThanOrEqualTo(4.5));
  });

  test('the chosen theme is saved and loaded again', () async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.select(AppThemeChoice.glass);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_choice'), 'glass');

    await ThemeController.instance.select(AppThemeChoice.light);
    SharedPreferences.setMockInitialValues({'theme_choice': 'dark'});
    await ThemeController.instance.load();
    expect(ThemeController.instance.choice, AppThemeChoice.dark);

    SharedPreferences.setMockInitialValues({'theme_choice': 'not-a-theme'});
    await ThemeController.instance.load();
    expect(ThemeController.instance.choice, AppThemeChoice.light);
  });

  testWidgets('choosing Liquid Glass in Settings changes the theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(auth: AuthService())),
    );
    await tester.tap(find.text('Liquid Glass'));
    await tester.pump();
    expect(ThemeController.instance.choice, AppThemeChoice.glass);
  });
}
