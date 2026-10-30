import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vasflow/services/auth_service.dart';
import 'package:vasflow/services/backup_models.dart';
import 'package:vasflow/services/backup_repository.dart';
import 'package:vasflow/services/backup_scheduler.dart';
import 'package:vasflow/services/backup_service.dart';
import 'package:vasflow/services/local_store.dart';

/// In-memory stand-in for BackupRepository. Extends the real class so the
/// service's exact public contract is exercised; unmocked methods are not
/// reached by BackupService.run for these scenarios.
class FakeRepo extends BackupRepository {
  final rows = <BackupEntry>[];
  final statuses = <Map<String, String>>[];
  final uploaded = <String>[];
  Object? uploadError;

  @override
  Future<List<BackupEntry>> list(String workspaceId) async => rows;

  @override
  Future<BackupEntry> createPending({
    required String workspaceId,
    required String kind,
  }) async {
    final entry = BackupEntry(
      id: 'row-1',
      workspaceId: workspaceId,
      kind: kind,
      status: 'pending',
      createdAt: DateTime.now().toUtc(),
    );
    rows.add(entry);
    return entry;
  }

  @override
  Future<void> updateStatus(
    String id, {
    required String status,
    String? storagePath,
    int? sizeBytes,
    int? recordCount,
    int? fileCount,
    String? manifestSha256,
    String? error,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    statuses.add({
      'status': status,
      'storagePath': storagePath ?? '',
      'error': error ?? '',
    });
    final index = rows.indexWhere((r) => r.id == id);
    if (index >= 0) {
      final old = rows[index];
      rows[index] = BackupEntry(
        id: old.id,
        workspaceId: old.workspaceId,
        kind: old.kind,
        status: status,
        storagePath: storagePath,
        sizeBytes: sizeBytes,
        recordCount: recordCount,
        fileCount: fileCount,
        createdAt: old.createdAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );
    }
  }

  @override
  Future<int> countCompleted(String workspaceId) async =>
      rows.where((r) => r.status == 'completed').length;

  @override
  Future<BackupEntry?> oldestCompleted(String workspaceId) async {
    final completed =
        rows
            .where((r) => r.status == 'completed' && r.storagePath != null)
            .toList();
    if (completed.isEmpty) return null;
    completed.sort(
      (a, b) => (a.createdAt ?? DateTime(2020)).compareTo(
        b.createdAt ?? DateTime(2020),
      ),
    );
    return completed.first;
  }

  @override
  Future<void> deleteFileThenRow(BackupEntry entry) async {
    uploaded.remove(entry.storagePath);
    rows.removeWhere((r) => r.id == entry.id);
  }

  @override
  Future<void> uploadZip(String path, Uint8List bytes) async {
    if (uploadError != null) throw uploadError!;
    uploaded.add(path);
  }
}

class FakeService extends BackupService {
  FakeService({required super.repo, required super.auth})
    : super(local: LocalStore());

  @override
  bool get ready => true;

  @override
  bool get isAdmin => true;

  @override
  String? get workspaceId => 'ws-1';

  WorkspaceSnapshot Function(String wsId)? snapshot;

  @override
  Future<WorkspaceSnapshot> snapshotFor(String wsId) async => snapshot!(wsId);
}

WorkspaceSnapshot emptySnapshot() {
  const manifest = BackupManifest(
    workspace: {'id': 'ws-1', 'name': 'Somewhere'},
    members: [],
    clients: const [
      {
        'id': 'c1',
        'workspace_id': 'ws-1',
        'full_name': 'Client One',
        'email': '',
        'phone': '',
        'country': '',
        'university': '',
        'visa_status': '',
        'passport_number': '',
        'notes': '',
        'stage': 'pipeline_created',
        'updated_at': '2026-03-01T00:00:00Z',
      },
    ],
    applications: const [],
    payments: const [],
    documents: const [],
    tasks: const [],
    fileChecksums: const {},
    missingFiles: [],
    createdAt: '2026-03-01T10:00:00Z',
    createdByEmail: 'admin@x.dev',
  );
  return WorkspaceSnapshot(manifest, const {});
}

void main() {
  late FakeRepo repo;
  late FakeService service;

  setUp(() {
    repo = FakeRepo();
    service = FakeService(auth: AuthService(), repo: repo)
      ..snapshot = (_) => emptySnapshot();
  });

  test(
    'successful run reports the result and never fabricates counts',
    () async {
      final result = await service.run(automatic: true);
      expect(result.entry.status, 'completed');
      expect(result.entry.storagePath, contains('ws-1/'));
      expect(result.counts['clients'], 1);
      expect(result.fileCount, 0);
      expect(repo.uploaded, hasLength(1));
      final statuses = repo.statuses;
      // pending and running first, completed last, and nothing failed.
      expect(statuses.first['status'], anyOf('pending', 'running'));
      expect(statuses.last['status'], 'completed');
      expect(repo.rows.single.status, 'completed');
    },
  );

  test('onStep reports real stages', () async {
    final steps = <String>[];
    await service.run(automatic: true, onStep: steps.add);
    expect(steps, contains('Collecting workspace data...'));
    expect(steps.last, 'Finishing...');
  });

  test(
    'failed upload: the row is marked failed with the real error and is never completed',
    () async {
      repo.uploadError = Exception('upload exploded');
      await expectLater(service.run(automatic: true), throwsException);
      final failed = repo.statuses.last;
      expect(failed['status'], 'failed');
      expect(failed['error'], 'upload exploded');
      expect(repo.rows.any((r) => r.status == 'completed'), isFalse);
      // And the scheduler retries a failed attempt on the next open: it is due.
      expect(
        BackupScheduler.shouldRun(
          cadence: BackupCadence.daily,
          history: repo.rows,
          now: DateTime.now().toUtc(),
        ),
        isTrue,
      );
    },
  );

  test('snapshot failure also records failed, never completed', () async {
    service.snapshot = (_) => throw Exception('read failed');
    await expectLater(service.run(automatic: true), throwsException);
    expect(repo.statuses.last['status'], 'failed');
    expect(repo.rows.any((r) => r.status == 'completed'), isFalse);
  });
}
