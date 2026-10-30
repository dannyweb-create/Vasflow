import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vasflow/screens/backup_screen.dart';
import 'package:vasflow/screens/settings_screen.dart';
import 'package:vasflow/services/auth_service.dart';
import 'package:vasflow/services/backup_models.dart';

BackupEntry entry({
  String status = 'completed',
  String kind = 'manual',
  String? storagePath,
}) {
  return BackupEntry(
    id: '00000000-0000-0000-0000-000000000001',
    workspaceId: '11111111-1111-1111-1111-111111111111',
    createdAt: DateTime.utc(2026, 3, 15, 10, 30),
    kind: kind,
    status: status,
    storagePath: storagePath,
  );
}

void main() {
  group('BackupUi helpers', () {
    test('formats sizes for the history cards', () {
      expect(BackupUi.formatBytes(0), '0 B');
      expect(BackupUi.formatBytes(1023), '1023 B');
      expect(BackupUi.formatBytes(2048), '2.0 KB');
      expect(BackupUi.formatBytes(1536 * 1024), '1.5 MB');
    });

    test('maps every status to a human label', () {
      expect(BackupUi.statusLabel(entry(status: 'completed')), 'Completed');
      expect(BackupUi.statusLabel(entry(status: 'failed')), 'Failed');
      expect(BackupUi.statusLabel(entry(status: 'running')), 'Running');
      expect(BackupUi.statusLabel(entry(status: 'pending')), 'Pending');
    });

    test('labels kind and gates the new-workspace strategy', () {
      expect(BackupUi.kindLabel(entry(kind: 'manual')), 'Manual');
      expect(BackupUi.kindLabel(entry(kind: 'auto')), 'Automatic');
      expect(BackupUi.canRestoreToNewWorkspace(false), isTrue);
      expect(BackupUi.canRestoreToNewWorkspace(true), isFalse);
    });

    test('download file names are stable and start with vasflow-backup-', () {
      expect(
        BackupUi.historyFileName(entry()),
        'vasflow-backup-20260315-1030-00000000.zip',
      );
    });
  });

  testWidgets('backup screen shows the offline notice without Supabase', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: BackupScreen(auth: AuthService())),
    );
    expect(find.text(BackupUi.offlineNote), findsOneWidget);
  });

  testWidgets('Settings exposes the Backups & recovery entry point', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(auth: AuthService())),
    );
    expect(find.text('Backups & recovery'), findsOneWidget);

    await tester.tap(find.text('Backups & recovery'));
    await tester.pumpAndSettle();
    expect(find.text('Backups & recovery'), findsOneWidget);
    expect(find.text(BackupUi.offlineNote), findsOneWidget);
  });
}
