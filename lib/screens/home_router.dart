import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

/// Picks the first screen after sign-in: the dashboard if the person already
/// belongs to a workspace, otherwise the workspace setup screen.
Widget homeFor(AuthService auth, ValueChanged<bool> onThemeChanged) {
  if (auth.hasWorkspace) {
    return DashboardScreen(auth: auth, onThemeChanged: onThemeChanged);
  }
  return OnboardingScreen(auth: auth, onThemeChanged: onThemeChanged);
}
