import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

/// Picks the first screen after sign-in: the dashboard if the person already
/// belongs to a workspace, otherwise the workspace setup screen.
Widget homeFor(AuthService auth) {
  if (auth.hasWorkspace) {
    return DashboardScreen(auth: auth);
  }
  return OnboardingScreen(auth: auth);
}
