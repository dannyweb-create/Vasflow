import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasflow/models/application_record.dart';
import 'package:vasflow/models/client_record.dart';
import 'package:vasflow/models/document_record.dart';
import 'package:vasflow/models/payment_record.dart';
import 'package:vasflow/utils/client_export.dart';

ClientExportData _fixture() {
  final at = DateTime(2026, 10, 31, 12, 30);
  return ClientExportData(
    client: ClientRecord(
      id: 'c1',
      fullName: 'Ada Obi',
      email: 'ada@example.com',
      country: 'Canada',
      stage: 'Documents',
      details: {
        'intake': 'Sep/Oct 2026',
        'docs_received': ['Passport', 'CV'],
      },
      updatedAt: at,
    ),
    applications: [
      ApplicationRecord(
        id: 'a1',
        clientId: 'c1',
        institution: 'Example University',
        status: 'Submitted',
        updatedAt: at,
      ),
    ],
    payments: [
      PaymentRecord(
        id: 'p1',
        clientId: 'c1',
        amount: 100,
        paidAmount: 40,
        updatedAt: at,
      ),
    ],
    documents: [
      DocumentRecord(
        id: 'd1',
        clientId: 'c1',
        name: 'passport.pdf',
        category: 'Passport',
        filePath: 'ws/c1/file-passport.pdf',
        status: 'Approved',
        sizeBytes: 1234,
        updatedAt: at,
      ),
      DocumentRecord(
        id: 'd2',
        clientId: 'c1',
        name: 'scan',
        category: 'CV',
        filePath: 'ws/c1/file-scan.jpg',
        status: 'Under review',
        updatedAt: at,
      ),
    ],
  );
}

void main() {
  test('JSON export includes the client, document names and statuses', () {
    final json =
        jsonDecode(
              utf8.decode(
                buildClientJson(_fixture(), exportedAt: DateTime(2026, 10, 31)),
              ),
            )
            as Map<String, dynamic>;

    expect(json['client']['name'], 'Ada Obi');
    expect(json['client']['stage'], 'Documents');
    expect(json['documents'][0]['name'], 'passport.pdf');
    expect(json['documents'][0]['status'], 'Approved');
    expect(json['documents'][1]['status'], 'Under review');
    expect(json['applications'][0]['status'], 'Submitted');
    expect(json['payments'][0]['outstanding'], 60);
  });

  test('CSV export contains every section and the document statuses', () {
    final csv = utf8.decode(buildClientCsv(_fixture()));

    expect(csv, contains('Client'));
    expect(csv, contains('Applications'));
    expect(csv, contains('Payments'));
    expect(csv, contains('Documents'));
    expect(csv, contains('Profile details'));
    expect(csv, contains('passport.pdf'));
    expect(csv, contains('Approved'));
    expect(csv, contains('Under review'));
  });

  test('XLSX export has one sheet per section, including documents', () async {
    final bytes = await buildClientXlsx(_fixture());
    final book = Excel.decodeBytes(bytes);

    expect(
      book.tables.keys,
      containsAll([
        'Overview',
        'Applications',
        'Payments',
        'Documents',
        'Profile details',
      ]),
    );
    final documents = book.tables['Documents']!;
    final values =
        documents.rows
            .expand((row) => row)
            .map(
              (cell) => switch (cell?.value) {
                TextCellValue(:final value) => value,
                _ => null,
              },
            )
            .whereType<String>()
            .toList();
    expect(values, contains('passport.pdf'));
    expect(values, contains('Approved'));
  });

  test('PDF export is a real PDF document', () async {
    final bytes = await buildClientPdf(_fixture());

    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test(
    'ZIP export bundles the data file and every available document',
    () async {
      final bytes = await buildClientExportZip(
        _fixture(),
        ClientExportFormat.json,
        {
          'd1': Uint8List.fromList([1, 2, 3]),
          'd2': Uint8List.fromList([4, 5]),
        },
        exportedAt: DateTime(2026, 10, 31),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((file) => file.name).toList();

      expect(names, contains('vasflow-client-ada-obi-20261031.json'));
      expect(names, contains('documents/passport.pdf'));
      expect(names, contains('documents/scan.jpg'));
    },
  );

  test('file names are safe and stable', () {
    final name = clientExportFileName(
      _fixture(),
      ClientExportFormat.xlsx,
      at: DateTime(2026, 1, 2),
    );

    expect(name, 'vasflow-client-ada-obi-20260102.xlsx');
    expect(
      clientExportFileName(
        _fixture(),
        ClientExportFormat.csv,
        zip: true,
        at: DateTime(2026, 1, 2),
      ),
      'vasflow-client-ada-obi-20260102.zip',
    );
  });
}
