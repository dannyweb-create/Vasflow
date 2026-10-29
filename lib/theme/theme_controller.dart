import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';

/// Holds the selected theme and remembers it across app restarts.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_choice';

  AppThemeChoice _choice = AppThemeChoice.light;
  AppThemeChoice get choice => _choice;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      _choice = AppThemeChoice.values.firstWhere(
        (c) => c.name == saved,
        orElse: () => AppThemeChoice.light,
      );
    } catch (_) {
      // Keep the default theme if saved settings cannot be read.
    }
    notifyListeners();
  }

  Future<void> select(AppThemeChoice choice) async {
    if (choice == _choice) return;
    _choice = choice;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, choice.name);
    } catch (_) {
      // The theme still changes for this session even if saving fails.
    }
  }
}
