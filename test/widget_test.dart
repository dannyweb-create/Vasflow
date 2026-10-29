import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasflow/app.dart';

void main() {
  testWidgets('shows setup notice and disabled login when Supabase is not configured',
      (tester) async {
    await tester.pumpWidget(const VasFlowApp());

    expect(find.text('VasFlow'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.byKey(const Key('setup-notice')), findsOneWidget);
  });
}
