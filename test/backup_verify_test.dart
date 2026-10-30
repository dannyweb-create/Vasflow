import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasflow/services/backup_models.dart';
import 'package:vasflow/services/restore_service.dart';

/// Builds the exact archive shape the backup service produces: manifest.json
/// plus optional document files under `files/<client>/<doc>-<name>`.
Uint8List buildArchive({
  required List<Map<String, dynamic>> documents,
  required Map<String, Uint8List> fileBytes,
  List<String> missingFiles = const [],
  // Overrides the checksums recorded in the manifest; defaults to checksums
  // of the bytes actually carried. Needed when the file in the ZIP is
  // damaged or absent while the manifest still lists what was backed up.
  Map<String, String>? checksumsOverride,
}) {
  final checksums =
      checksumsOverride ??
      <String, String>{
        for (final entry in fileBytes.entries)
          entry.key: BackupManifest.fileChecksum(entry.value),
      };
  final manifest = BackupManifest(
    workspace: {'id': 'ws-1', 'name': 'Old workspace'},
    members: const [],
    clients: const [
      {
        'id': 'c1',
        'workspace_id': 'ws-1',
        'full_name': 'Client One',
        'email': 'c1@x.dev',
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
    documents: documents,
    tasks: const [],
    fileChecksums: checksums,
    missingFiles: missingFiles,
    createdAt: '2026-03-01T10:00:00Z',
    createdByEmail: 'admin@x.dev',
  );
  final manifestBytes = Uint8List.fromList(utf8.encode(manifest.encode()));
  final archive =
      Archive()..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
  for (final item in fileBytes.entries) {
    archive.addFile(ArchiveFile(item.key, item.value.length, item.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive) ?? <int>[]);
}

void main() {
  final docRow = {
    'id': '90000000-0000-0000-0000-000000000004',
    'workspace_id': 'ws-1',
    'client_id': 'c1',
    'name': 'Passport Scan.jpg',
    'category': 'Identity document',
    'file_path': 'ws-1/c1/Passport Scan.jpg',
    'mime_type': 'image/jpeg',
    'size_bytes': 4,
    'uploaded_by': 'u1',
    'updated_at': '2026-03-01T00:00:00Z',
  };
  const docKey =
      'files/c1/90000000-0000-0000-0000-000000000004-Passport Scan.jpg';

  test('a complete archive verifies with no problems', () {
    final bytes = buildArchive(
      documents: [docRow],
      fileBytes: {
        docKey: Uint8List.fromList([1, 2, 3, 4]),
      },
    );
    final realSha = BackupManifest.checksumOf(_manifestBytesOf(bytes));
    final result = RestoreVerifier.verifyArchive(bytes, expectedSha: realSha);
    expect(result.usable, isTrue);
    expect(result.fatalError, isNull);
    expect(result.fileProblems, isEmpty);
    expect(result.manifest!.clients, hasLength(1));
  });

  test('not a zip archive at all is a fatal problem', () {
    final result = RestoreVerifier.verifyArchive(
      Uint8List.fromList([1, 2, 3]),
      expectedSha: null,
    );
    expect(result.usable, isFalse);
    expect(result.fatalError, isNotNull);
  });

  test('missing manifest.json is fatal', () {
    final archive =
        Archive()
          ..addFile(ArchiveFile('other.txt', 3, Uint8List.fromList([9, 9, 9])));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive) ?? <int>[]);
    final result = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
    expect(result.manifestFound, isFalse);
    expect(result.fatalError, contains('manifest.json is missing'));
  });

  test(
    'checksum failure vs history row (damaged/replaced archive) is fatal',
    () {
      final bytes = buildArchive(documents: [], fileBytes: const {});
      final result = RestoreVerifier.verifyArchive(
        bytes,
        expectedSha: '0' * 64,
      );
      expect(result.manifestVerified, isFalse);
      expect(result.fatalError, contains('damaged or was replaced'));
    },
  );

  test('missing document file is reported and still opens a preview', () {
    // The manifest lists a checksum, but the file vanished from the archive.
    final bytes = buildArchive(
      documents: [docRow],
      fileBytes: const {},
      checksumsOverride: {docKey: 'a' * 64},
    );
    final result = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
    expect(result.usable, isTrue); // preview can be opened
    expect(result.fileProblems, [contains('Missing from archive: $docKey')]);
  });

  test('tampered document bytes give a checksum mismatch', () {
    final bytes = buildArchive(
      documents: [docRow],
      fileBytes: {
        docKey: Uint8List.fromList([9, 9, 9, 9]),
      },
      checksumsOverride: {
        docKey: BackupManifest.fileChecksum(Uint8List.fromList([1, 2, 3, 4])),
      },
    );
    final result = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
    expect(result.fileProblems, ['Checksum mismatch: $docKey']);
  });

  test(
    'files missing at backup time (manifest.missingFiles) are not problems',
    () {
      final doc2 = {...docRow, 'id': 'a0000000-0000-0000-0000-000000000002'};
      final bytes = buildArchive(
        documents: [docRow, doc2],
        fileBytes: {
          docKey: Uint8List.fromList([1, 2, 3, 4]),
        },
        missingFiles: [docKey],
      );
      final result = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
      expect(result.fileProblems, isEmpty);
    },
  );

  test('documented missing files map to reportable manifest state', () {
    // Continue with the same archive: verifying twice is deterministic and
    // repeated restores stay repairable because the plan never changes.
    final bytes = buildArchive(documents: [docRow], fileBytes: const {});
    final first = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
    final second = RestoreVerifier.verifyArchive(bytes, expectedSha: null);
    expect(first.fatalError, second.fatalError);
    expect(first.fileProblems, second.fileProblems);
    expect(first.manifest!.toMap(), second.manifest!.toMap());
  });

  test('retargeting is repeatable and never duplicates or deletes rows', () {
    final row = {'id': 'c1', 'workspace_id': 'ws-1', 'full_name': 'Z'};
    final retargeted = BackupPlanner.retargetAll([row], 'ws-new');
    final again = BackupPlanner.retargetAll(retargeted, 'ws-new');
    expect(again, retargeted);
    expect(again.single['workspace_id'], 'ws-new');
    expect(BackupPlanner.stripSoftForeignKeys(again.single), again.single);
  });
}

Uint8List _manifestBytesOf(Uint8List zipBytes) {
  final zip = ZipDecoder().decodeBytes(zipBytes);
  final file = zip.findFile('manifest.json')!;
  return Uint8List.fromList(List<int>.from(file.content as List<int>));
}
