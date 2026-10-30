import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'onboarding_screen.dart';
import 'workspace_shell.dart';

/// Picks the first screen after sign-in: the four-tab workspace if the person
/// already belongs to a workspace, otherwise the workspace setup screen.
Widget homeFor(AuthService auth) {
  if (auth.hasWorkspace) {
    return WorkspaceShell(auth: auth);
  }
  return OnboardingScreen(auth: auth);
}
