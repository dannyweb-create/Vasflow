import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Writes UTF-8 CSV rows to a chosen location on any platform.
/// Used by the Reports, Clients and Payments exports.
Future<void> exportCsv(
  BuildContext context,
  List<List<dynamic>> rows, {
  required String fileName,
  String dialogTitle = 'Export VasFlow data',
}) async {
  final content = const ListToCsvConverter().convert(rows);
  await saveBytes(
    context,
    Uint8List.fromList(utf8.encode(content)),
    fileName: fileName,
    dialogTitle: dialogTitle,
  );
}

/// Saves bytes to a user-chosen location, mirroring the clients CSV export.
Future<void> saveBytes(
  BuildContext context,
  Uint8List bytes, {
  required String fileName,
  String dialogTitle = 'Save file',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // On Android/iOS the file picker writes the file itself and needs the bytes.
  // On desktop it only returns a path and we write the file ourselves.
  final onMobile = Platform.isAndroid || Platform.isIOS;
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: onMobile ? bytes : null,
    );
    if (path == null) return; // person cancelled
    if (!onMobile) await File(path).writeAsBytes(bytes);
    messenger.showSnackBar(const SnackBar(content: Text('File saved')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save the file: $e')),
    );
  }
}

/// Formats a money amount without a forced currency: whole numbers stay whole,
/// fractional parts keep two sensible digits.
String moneyAmount(num value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
