/// Metadata about one client document stored in the private Supabase Storage
/// bucket 'client-documents' (path: workspace_id/client_id/uuid-filename).
/// The file bytes never live inside the database; only this row does.
class DocumentRecord {
  final String id;
  final String clientId;
  final String name;
  final String category;
  final String filePath;
  final String mimeType;
  final int sizeBytes;
  final String uploadedBy;
  final String status;
  final String adminNotes;
  final DateTime updatedAt;

  const DocumentRecord({
    required this.id,
    required this.clientId,
    required this.name,
    this.category = 'Other supporting documents',
    required this.filePath,
    this.mimeType = '',
    this.sizeBytes = 0,
    this.uploadedBy = '',
    this.status = 'Uploaded',
    this.adminNotes = '',
    required this.updatedAt,
  });

  DocumentRecord copyWith({
    String? name,
    String? category,
    String? filePath,
    String? mimeType,
    int? sizeBytes,
    String? uploadedBy,
    String? status,
    String? adminNotes,
    DateTime? updatedAt,
  }) => DocumentRecord(
    id: id,
    clientId: clientId,
    name: name ?? this.name,
    category: category ?? this.category,
    filePath: filePath ?? this.filePath,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    status: status ?? this.status,
    adminNotes: adminNotes ?? this.adminNotes,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  static int _int(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'name': name,
    'category': category,
    'file_path': filePath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'uploaded_by': uploadedBy,
    'status': status,
    'admin_notes': adminNotes,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory DocumentRecord.fromJson(Map<String, dynamic> j) => DocumentRecord(
    id: '${j['id']}',
    clientId: '${j['client_id'] ?? ''}',
    name: '${j['name'] ?? 'Document'}',
    category: '${j['category'] ?? 'Other supporting documents'}',
    filePath: '${j['file_path'] ?? ''}',
    mimeType: '${j['mime_type'] ?? ''}',
    sizeBytes: _int(j['size_bytes']),
    uploadedBy: '${j['uploaded_by'] ?? ''}',
    status: '${j['status'] ?? 'Uploaded'}',
    adminNotes: '${j['admin_notes'] ?? ''}',
    updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}') ?? DateTime.now(),
  );
}
