import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'app_config.dart';

class ClientPhotoService {
  static const bucket = 'client-photos';
  static final ImagePicker _picker = ImagePicker();

  Future<String?> signedUrl(String path, {int seconds = 60}) async {
    if (path.trim().isEmpty || !AppConfig.supabaseReady) return null;
    return Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(path, seconds);
  }

  Future<String> upload({
    required String workspaceId,
    required String clientId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (!AppConfig.supabaseReady) {
      throw Exception('Client photos need a Supabase connection to upload.');
    }
    final ext = _normaliseExtension(extension);
    if (!isSupportedExtension(ext)) {
      throw Exception('Client photos must be JPG or PNG.');
    }
    final fileName = '${const Uuid().v4()}.$ext';
    final path = '$workspaceId/$clientId/$fileName';
    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
    return path;
  }

  /// Uploads to a caller-chosen path in the same private bucket. Used for
  /// admin profile photos, which keep a stable path instead of a unique one.
  Future<void> uploadToPath({
    required String path,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (!AppConfig.supabaseReady) {
      throw Exception('Photos need a Supabase connection to upload.');
    }
    final cleanPath = path.trim();
    if (cleanPath.isEmpty) throw Exception('The photo path is missing.');
    final ext = _normaliseExtension(extension);
    if (!isSupportedExtension(ext)) {
      throw Exception('Photos must be JPG or PNG.');
    }
    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          cleanPath,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );
  }

  Future<void> remove(String path) async {
    if (path.trim().isEmpty || !AppConfig.supabaseReady) return;
    await Supabase.instance.client.storage.from(bucket).remove([path]);
  }

  static Future<XFile?> pick(ImageSource source) => _picker.pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
    requestFullMetadata: false,
  );

  static String _normaliseExtension(String extension) {
    final ext = extension.toLowerCase();
    return ext == 'jpeg' ? 'jpg' : ext;
  }

  static String extensionOf(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 2) return '';
    return _normaliseExtension(parts.last);
  }

  static bool isSupportedExtension(String extension) =>
      ['jpg', 'jpeg', 'png'].contains(extension.toLowerCase());
}
