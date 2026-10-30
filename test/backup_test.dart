import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vasflow/services/backup_models.dart';
import 'package:vasflow/services/backup_repository.dart';

void main() {
  test('sha256 helper matches the known "abc" vector', () {
    final bytes = Uint8List.fromList(utf8.encode('abc'));
    expect(
      BackupManifest.fileChecksum(bytes),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('manifest round trip keeps every row type', () {
    const manifest = BackupManifest(
      workspace: {'id': 'ws-1', 'name': 'Alpha'},
      members: [
        {'workspace_id': 'ws-1', 'user_id': 'u1', 'role': 'admin'},
      ],
      clients: [
        {
          'id': 'c1',
          'workspace_id': 'ws-1',
          'full_name': 'Ann',
          'profile': {'dob': '1990-02-02'},
          'archived': true,
        },
      ],
      applications: [
        {'id': 'a1', 'client_id': 'c1', 'status': 'Offer received'},
      ],
      payments: [
        {'id': 'p1', 'client_id': 'c1', 'amount': 1200},
      ],
      documents: [
        {
          'id': 'd1',
          'client_id': 'c1',
          'file_path': 'ws-1/c1/e9-acceptance.pdf',
        },
      ],
      tasks: [
        {'id': 't1', 'title': 'Book visa slot', 'done': false},
      ],
      fileChecksums: {'files/c1/d1-e9-acceptance.pdf': 'abc123'},
      missingFiles: ['files/c1/d2-x'],
      createdAt: '2026-01-01T00:00:00.000Z',
      createdByEmail: 'admin@example.com',
    );

    final decoded = BackupManifest.decode(manifest.encode());
    expect(decoded.workspace['name'], 'Alpha');
    expect(decoded.clients.single['profile']['dob'], '1990-02-02');
    expect(decoded.clients.single['archived'], true);
    expect(decoded.fileChecksums, manifest.fileChecksums);
    expect(decoded.missingFiles, manifest.missingFiles);
    expect(decoded.counts['clients'], 1);
    expect(decoded.counts['documents'], 1);
    expect(decoded.counts['tasks'], 1);
  });

  test('manifest decode rejects other formats and newer versions', () {
    expect(
      () => BackupManifest.decode('{"format":"other","version":1}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => BackupManifest.decode('{"format":"vasflow-backup","version":99}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('document keys are stable and path-resistant on both sides', () {
    const clientId = 'c1';
    const docId = 'd1';
    const filePath = 'ws-1/c1/a1b2-passport scan.pdf';
    final key = BackupManifest.documentKeyForPath(clientId, docId, filePath);
    expect(key, 'files/c1/d1-a1b2-passport scan.pdf');
    expect(key.contains('../'), false);

    final fromSlashes = BackupManifest.documentKeyForPath(
      clientId,
      docId,
      'ws-1/c1/../c3/file.jpeg',
    );
    expect(fromSlashes.startsWith('files/c1/d1-'), true);
    expect(
      BackupManifest.documentKey(clientId, docId, 'bad/name.jpeg'),
      'files/c1/d1-bad_name.jpeg',
    );
  });

  test('restore planner retargets workspace ids without other changes', () {
    final row = {
      'id': 'c1',
      'workspace_id': 'ws-old',
      'full_name': 'Ann',
      'archived': false,
    };
    final retargeted = BackupPlanner.retarget(row, 'ws-new');
    expect(retargeted['workspace_id'], 'ws-new');
    expect(retargeted['full_name'], 'Ann');
    expect(row['workspace_id'], 'ws-old'); // original untouched
    expect(BackupPlanner.retargetAll([row, row], 'ws-new').length, 2);
  });

  test('soft foreign keys are stripped only on demand', () {
    final row = {
      'id': 'p1',
      'owner_id': 'user-a',
      'created_by': 'user-a',
      'uploaded_by': 'user-a',
      'workspace_id': 'ws-1',
    };
    final stripped = BackupPlanner.stripSoftForeignKeys(row);
    expect(stripped.containsKey('owner_id'), false);
    expect(stripped.containsKey('uploaded_by'), false);
    expect(stripped['workspace_id'], 'ws-1');
    expect(row.containsKey('uploaded_by'), true);
  });

  test('task merge is idempotent and never deletes device rows', () {
    final existing = [
      {'id': 't0', 'title': 'Local note', 'done': false},
      {'id': 't1', 'title': 'Renamed on device', 'done': true},
    ];
    final restored = [
      {'id': 't1', 'title': 'Older copy from backup', 'done': false},
      {'id': 't2', 'title': 'From backup', 'done': false},
      {'id': '', 'title': 'invalid row', 'done': false},
    ];
    final merged = BackupPlanner.mergeTasks(existing, restored);
    expect(merged.length, 3);
    final t1 = merged.firstWhere((e) => e['id'] == 't1');
    expect(t1['title'], 'Renamed on device'); // device wins
    expect(merged.any((e) => e['id'] == 't2'), true);
    final mergedAgain = BackupPlanner.mergeTasks(merged, restored);
    expect(mergedAgain.length, 3); // retry adds nothing new
  });

  test('target document paths keep the 3-folder shape', () {
    final path = BackupPlanner.targetDocumentPath(
      workspaceId: 'ws-new',
      clientId: 'c1',
      rowFilePath: 'ws-old/c1/a1b2-visa.pdf',
      documentRowIdFallback: 'd1',
    );
    expect(path, 'ws-new/c1/a1b2-visa.pdf');
    expect(path.split('/').length, 3);

    final fallback = BackupPlanner.targetDocumentPath(
      workspaceId: 'ws-new',
      clientId: 'c1',
      rowFilePath: '',
      documentRowIdFallback: 'd1',
    );
    expect(fallback.split('/').length, 3);
  });

  test('backup entry parsing tolerates messy row values', () {
    final entry = BackupEntry.fromRow({
      'id': 'b1',
      'workspace_id': 'ws-1',
      'kind': null,
      'status': 'completed',
      'manifest_sha256': 'abc',
      'size_bytes': '1234',
      'file_count': 3,
      'created_at': '2026-01-02T03:04:05Z',
      'error': null,
    });
    expect(entry.kind, 'manual'); // default for null
    expect(entry.sizeBytes, 1234);
    expect(entry.completed, true);
    expect(entry.createdAt, isNotNull);
    expect(
      BackupEntry.fromRow({'id': 'x', 'workspace_id': 'ws-1'}).failed,
      false,
    );
  });

  test('error text is trimmed below the 2000-char column limit', () {
    final long = 'x' * 5000;
    final text = BackupRepository.errorText('Exception: $long');
    expect(text.length <= 2000, true);
    expect(text.startsWith('Exception:'), false);
    expect(BackupRepository.errorText('RpcException: message: short'), 'short');
  });

  test('zip round trip: manifest plus files extract with same bytes', () {
    final manifestBytes = Uint8List.fromList(
      utf8.encode(json.encode({'format': 'vasflow-backup', 'version': 1})),
    );
    final docBytes = Uint8List.fromList(List.generate(500, (i) => i % 251));
    final archive = Archive();
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    archive.addFile(
      ArchiveFile('files/c1/d1-scan.jpg', docBytes.length, docBytes),
    );
    final zipBytes = ZipEncoder().encode(archive)!;

    final decoded = ZipDecoder().decodeBytes(zipBytes);
    final outManifest = decoded.findFile('manifest.json')!;
    final outDoc = decoded.findFile('files/c1/d1-scan.jpg')!;
    expect(
      utf8.decode(List<int>.from(outManifest.content as List<int>)),
      utf8.decode(manifestBytes),
    );
    final actualChecksum = BackupManifest.fileChecksum(
      Uint8List.fromList(List<int>.from(outDoc.content as List<int>)),
    );
    expect(actualChecksum, BackupManifest.fileChecksum(docBytes));
  });

  test('restore preview refuses on checksum problems', () {
    const manifest = BackupManifest(
      workspace: {},
      members: [],
      clients: [],
      applications: [],
      payments: [],
      documents: [
        {'id': 'd1', 'client_id': 'c1', 'file_path': 'ws/c1/x.jpg'},
      ],
      tasks: [],
      fileChecksums: {'files/c1/d1-x.jpg': 'deadbeef'},
      missingFiles: [],
      createdAt: '',
      createdByEmail: '',
    );
    const ok = RestorePreview(
      manifest: manifest,
      backupId: 'b1',
      manifestVerified: true,
      fileProblems: [],
      currentCounts: {'clients': 2},
    );
    const bad = RestorePreview(
      manifest: manifest,
      backupId: 'b1',
      manifestVerified: true,
      fileProblems: ['Checksum mismatch: files/c1/d1-x.jpg'],
      currentCounts: {},
    );
    expect(ok.ready, true);
    expect(bad.ready, false);
  });
}
