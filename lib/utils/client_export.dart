import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/application_record.dart';
import '../models/client_record.dart';
import '../models/document_record.dart';
import '../models/payment_record.dart';

/// A single client's data, ready to be written out in any export format.
///
/// Document names and their review statuses are always included, even when
/// the original files are not bundled into a ZIP.
class ClientExportData {
  final ClientRecord client;
  final List<ApplicationRecord> applications;
  final List<PaymentRecord> payments;
  final List<DocumentRecord> documents;

  const ClientExportData({
    required this.client,
    this.applications = const [],
    this.payments = const [],
    this.documents = const [],
  });
}

enum ClientExportFormat { pdf, xlsx, csv, json }

extension ClientExportFormatDetails on ClientExportFormat {
  String get label => switch (this) {
    ClientExportFormat.pdf => 'PDF',
    ClientExportFormat.xlsx => 'Excel (XLSX)',
    ClientExportFormat.csv => 'CSV',
    ClientExportFormat.json => 'JSON',
  };

  String get extension => switch (this) {
    ClientExportFormat.pdf => 'pdf',
    ClientExportFormat.xlsx => 'xlsx',
    ClientExportFormat.csv => 'csv',
    ClientExportFormat.json => 'json',
  };

  String get description => switch (this) {
    ClientExportFormat.pdf => 'A printable client report.',
    ClientExportFormat.xlsx => 'One workbook with a sheet per section.',
    ClientExportFormat.csv => 'Plain rows for spreadsheets and imports.',
    ClientExportFormat.json => 'Structured data for backups and tools.',
  };
}

/// Builds the requested export in memory. PDF and XLSX generation are async.
Future<Uint8List> buildClientExport(
  ClientExportData data,
  ClientExportFormat format, {
  DateTime? exportedAt,
}) {
  return switch (format) {
    ClientExportFormat.pdf => buildClientPdf(data, exportedAt: exportedAt),
    ClientExportFormat.xlsx => buildClientXlsx(data, exportedAt: exportedAt),
    ClientExportFormat.csv => Future.value(
      buildClientCsv(data, exportedAt: exportedAt),
    ),
    ClientExportFormat.json => Future.value(
      buildClientJson(data, exportedAt: exportedAt),
    ),
  };
}

/// Builds a ZIP containing the chosen data file plus every document whose
/// bytes were supplied in [documentFiles] (keyed by document id).
Future<Uint8List> buildClientExportZip(
  ClientExportData data,
  ClientExportFormat format,
  Map<String, Uint8List> documentFiles, {
  DateTime? exportedAt,
}) async {
  final at = exportedAt ?? DateTime.now();
  final dataBytes = await buildClientExport(data, format, exportedAt: at);
  final archive = Archive();
  final base = clientExportBaseName(data.client, at: at);
  final dataName = '$base.${format.extension}';
  archive.addFile(ArchiveFile(dataName, dataBytes.length, dataBytes));

  final used = <String>{};
  for (final document in data.documents) {
    final bytes = documentFiles[document.id];
    if (bytes == null || bytes.isEmpty) continue;
    final name = _uniqueZipName(_documentFileName(document), used);
    archive.addFile(ArchiveFile('documents/$name', bytes.length, bytes));
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null || encoded.isEmpty) {
    throw Exception('The ZIP archive could not be created.');
  }
  return Uint8List.fromList(encoded);
}

/// A safe, descriptive file name without the extension.
String clientExportBaseName(ClientRecord client, {DateTime? at}) {
  final date = at ?? DateTime.now();
  final stamp =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
  final slug = _slug(client.fullName);
  return 'vasflow-client${slug.isEmpty ? '' : '-$slug'}-$stamp';
}

/// The file name to offer in the save dialog.
String clientExportFileName(
  ClientExportData data,
  ClientExportFormat format, {
  bool zip = false,
  DateTime? at,
}) {
  final base = clientExportBaseName(data.client, at: at);
  return zip ? '$base.zip' : '$base.${format.extension}';
}

Map<String, dynamic> buildClientExportJson(
  ClientExportData data, {
  DateTime? exportedAt,
}) {
  final client = data.client;
  return {
    'format': 'vasflow-client',
    'version': 1,
    'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
    'client': {
      'id': client.id,
      'name': client.fullName,
      'email': client.email,
      'phone': client.phone,
      'country': client.country,
      'university': client.university,
      'visa_status': client.visaStatus,
      'passport_number': client.passportNumber,
      'notes': client.notes,
      'stage': client.stage,
      'archived': client.archived,
      'updated_at': client.updatedAt.toIso8601String(),
      'profile': client.details,
    },
    'applications': [
      for (final application in data.applications)
        {
          'id': application.id,
          'type': application.type,
          'institution': application.institution,
          'course': application.course,
          'country': application.country,
          'intake': application.intake,
          'status': application.status,
          'submitted': _dateOnly(application.submissionDate),
          'deadline': _dateOnly(application.deadline),
          'updated_at': application.updatedAt.toIso8601String(),
        },
    ],
    'payments': [
      for (final payment in data.payments)
        {
          'id': payment.id,
          'fee_type': payment.feeType,
          'description': payment.description,
          'amount': payment.amount,
          'paid': payment.paidAmount,
          'outstanding': payment.outstanding,
          'paid_date': _dateOnly(payment.paidDate),
          'reference': payment.reference,
          'updated_at': payment.updatedAt.toIso8601String(),
        },
    ],
    'documents': [
      for (final document in data.documents)
        {
          'id': document.id,
          'name': document.name,
          'category': document.category,
          'status': document.status,
          'size_bytes': document.sizeBytes,
          'uploaded_by': document.uploadedBy,
          'admin_notes': document.adminNotes,
          'updated_at': document.updatedAt.toIso8601String(),
        },
    ],
  };
}

Uint8List buildClientJson(ClientExportData data, {DateTime? exportedAt}) {
  final json = const JsonEncoder.withIndent(
    '  ',
  ).convert(buildClientExportJson(data, exportedAt: exportedAt));
  return Uint8List.fromList(utf8.encode(json));
}

/// A sectioned CSV: profile, applications, payments, documents and details.
Uint8List buildClientCsv(ClientExportData data, {DateTime? exportedAt}) {
  final rows = <List<dynamic>>[
    ['VasFlow client export'],
    ['Exported', _dateTime(exportedAt ?? DateTime.now())],
    [],
    ['Client'],
    ['Field', 'Value'],
    ..._overviewRows(data),
    [],
    ['Applications'],
    [
      'Type',
      'Institution',
      'Course',
      'Country',
      'Intake',
      'Status',
      'Submitted',
      'Deadline',
      'Updated',
    ],
    for (final application in data.applications)
      [
        application.type,
        application.institution,
        application.course,
        application.country,
        application.intake,
        application.status,
        _dateOnly(application.submissionDate),
        _dateOnly(application.deadline),
        _dateTime(application.updatedAt),
      ],
    [],
    ['Payments'],
    [
      'Fee type',
      'Description',
      'Amount',
      'Paid',
      'Outstanding',
      'Paid date',
      'Reference',
      'Updated',
    ],
    for (final payment in data.payments)
      [
        payment.feeType,
        payment.description,
        _money(payment.amount),
        _money(payment.paidAmount),
        _money(payment.outstanding),
        _dateOnly(payment.paidDate),
        payment.reference,
        _dateTime(payment.updatedAt),
      ],
    [],
    ['Documents'],
    [
      'Name',
      'Category',
      'Status',
      'Size (bytes)',
      'Uploaded by',
      'Updated',
      'Admin notes',
    ],
    for (final document in data.documents)
      [
        document.name,
        document.category,
        document.status,
        document.sizeBytes,
        document.uploadedBy,
        _dateTime(document.updatedAt),
        document.adminNotes,
      ],
    [],
    ['Profile details'],
    ['Field', 'Value'],
    ..._detailRows(data.client),
  ];

  final csv = const ListToCsvConverter().convert(rows);
  return Uint8List.fromList(utf8.encode(csv));
}

Future<Uint8List> buildClientPdf(
  ClientExportData data, {
  DateTime? exportedAt,
}) async {
  final at = exportedAt ?? DateTime.now();
  final document = pw.Document();
  final client = data.client;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header:
          (context) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'VasFlow client export',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  client.fullName.isEmpty ? 'Unnamed client' : client.fullName,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Exported ${_dateTime(at)}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
      footer:
          (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
      build:
          (context) => [
            _pdfKeyValueSection('Client', _overviewRows(data)),
            _pdfTableSection(
              'Applications',
              ['Type', 'Institution', 'Course', 'Status', 'Deadline'],
              [
                for (final application in data.applications)
                  [
                    application.type,
                    application.institution,
                    application.course,
                    application.status,
                    _dateOnly(application.deadline),
                  ],
              ],
              empty: 'No applications recorded.',
            ),
            _pdfTableSection(
              'Payments',
              ['Fee type', 'Amount', 'Paid', 'Outstanding', 'Reference'],
              [
                for (final payment in data.payments)
                  [
                    payment.feeType,
                    _money(payment.amount),
                    _money(payment.paidAmount),
                    _money(payment.outstanding),
                    payment.reference,
                  ],
              ],
              empty: 'No payments recorded.',
            ),
            _pdfTableSection(
              'Documents',
              ['Name', 'Category', 'Status', 'Updated'],
              [
                for (final item in data.documents)
                  [
                    item.name,
                    item.category,
                    item.status,
                    _dateOnly(item.updatedAt),
                  ],
              ],
              empty: 'No documents recorded.',
            ),
            if (client.notes.trim().isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Notes',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(client.notes.trim()),
                  pw.SizedBox(height: 14),
                ],
              ),
            _pdfKeyValueSection('Profile details', _detailRows(client)),
          ],
    ),
  );

  return Uint8List.fromList(await document.save());
}

Future<Uint8List> buildClientXlsx(
  ClientExportData data, {
  DateTime? exportedAt,
}) async {
  final at = exportedAt ?? DateTime.now();
  final excel = Excel.createExcel();

  final overview = excel['Overview'];
  _appendRows(overview, [
    ['VasFlow client export'],
    ['Exported', _dateTime(at)],
    [],
    ['Field', 'Value'],
    ..._overviewRows(data),
  ]);

  final applications = excel['Applications'];
  _appendRows(applications, [
    [
      'Type',
      'Institution',
      'Course',
      'Country',
      'Intake',
      'Status',
      'Submitted',
      'Deadline',
      'Updated',
    ],
    for (final application in data.applications)
      [
        application.type,
        application.institution,
        application.course,
        application.country,
        application.intake,
        application.status,
        _dateOnly(application.submissionDate),
        _dateOnly(application.deadline),
        _dateTime(application.updatedAt),
      ],
  ]);

  final payments = excel['Payments'];
  _appendRows(payments, [
    [
      'Fee type',
      'Description',
      'Amount',
      'Paid',
      'Outstanding',
      'Paid date',
      'Reference',
      'Updated',
    ],
    for (final payment in data.payments)
      [
        payment.feeType,
        payment.description,
        _money(payment.amount),
        _money(payment.paidAmount),
        _money(payment.outstanding),
        _dateOnly(payment.paidDate),
        payment.reference,
        _dateTime(payment.updatedAt),
      ],
  ]);

  final documents = excel['Documents'];
  _appendRows(documents, [
    [
      'Name',
      'Category',
      'Status',
      'Size (bytes)',
      'Uploaded by',
      'Updated',
      'Admin notes',
    ],
    for (final document in data.documents)
      [
        document.name,
        document.category,
        document.status,
        '${document.sizeBytes}',
        document.uploadedBy,
        _dateTime(document.updatedAt),
        document.adminNotes,
      ],
  ]);

  final profile = excel['Profile details'];
  _appendRows(profile, [
    ['Field', 'Value'],
    ..._detailRows(data.client),
  ]);

  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null &&
      defaultSheet != 'Overview' &&
      excel.tables.containsKey(defaultSheet)) {
    excel.delete(defaultSheet);
  }
  excel.setDefaultSheet('Overview');

  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw Exception('The XLSX workbook could not be created.');
  }
  return Uint8List.fromList(encoded);
}

List<List<String>> _overviewRows(ClientExportData data) {
  final client = data.client;
  return [
    ['Name', client.fullName],
    ['Email', client.email],
    ['Phone', client.phone],
    ['Country', client.country],
    ['University', client.university],
    ['Visa status', client.visaStatus],
    ['Passport number', client.passportNumber],
    ['Stage', client.stage],
    ['Archived', client.archived ? 'Yes' : 'No'],
    ['Updated', _dateTime(client.updatedAt)],
  ];
}

List<List<String>> _detailRows(ClientRecord client) {
  final keys = client.details.keys.toList()..sort();
  return [
    for (final key in keys) [key, _displayValue(client.details[key])],
  ];
}

String _displayValue(dynamic value) {
  if (value == null) return '';
  if (value is List) return value.map((item) => '$item').join(', ');
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
  }
  final text = '$value';
  return text == 'null' ? '' : text;
}

void _appendRows(Sheet sheet, List<List<String>> rows) {
  for (final row in rows) {
    sheet.appendRow(
      row.map<CellValue>((value) => TextCellValue(value)).toList(),
    );
  }
}

pw.Widget _pdfKeyValueSection(String title, List<List<String>> rows) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 5),
      if (rows.isEmpty)
        pw.Text('No details recorded.')
      else
        pw.TableHelper.fromTextArray(
          headers: const ['Field', 'Value'],
          data: rows,
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 3,
          ),
        ),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _pdfTableSection(
  String title,
  List<String> headers,
  List<List<String>> rows, {
  required String empty,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 5),
      if (rows.isEmpty)
        pw.Text(empty)
      else
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
        ),
      pw.SizedBox(height: 14),
    ],
  );
}

String _documentFileName(DocumentRecord document) {
  var name = _safeFileName(document.name);
  if (name.isEmpty) name = 'document';
  final extension =
      _extensionOf(document.name).isNotEmpty
          ? _extensionOf(document.name)
          : _extensionOf(document.filePath);
  if (extension.isNotEmpty &&
      !name.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
    name = '$name.$extension';
  }
  return name;
}

String _uniqueZipName(String desired, Set<String> used) {
  var candidate = desired;
  var counter = 2;
  while (used.contains(candidate.toLowerCase())) {
    final dot = desired.lastIndexOf('.');
    candidate =
        dot > 0
            ? '${desired.substring(0, dot)} ($counter)${desired.substring(dot)}'
            : '$desired ($counter)';
    counter++;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

String _safeFileName(String value) {
  return value
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _extensionOf(String value) {
  final name = value.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  final extension = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : '';
}

String _dateOnly(DateTime? value) {
  if (value == null) return '';
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _dateTime(DateTime value) {
  return '${_dateOnly(value)} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _money(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
