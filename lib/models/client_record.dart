class ClientRecord {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String country;
  final String university;
  final String visaStatus;
  final String passportNumber;
  final String notes;
  final String stage;
  final bool archived;

  /// Extended profile collected by the full client form and stored in the
  /// `profile` JSONB column. Date values (birth, passport, deadline, travel)
  /// are 'YYYY-MM-DD' strings; `docs_received` lists document names on file.
  final Map<String, dynamic> details;

  final DateTime updatedAt;

  const ClientRecord({
    required this.id,
    required this.fullName,
    this.email = '',
    this.phone = '',
    this.country = '',
    this.university = '',
    this.visaStatus = 'Not started',
    this.passportNumber = '',
    this.notes = '',
    this.stage = 'New lead',
    this.archived = false,
    this.details = const {},
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'country': country,
    'university': university,
    'visa_status': visaStatus,
    'passport_number': passportNumber,
    'notes': notes,
    'stage': stage,
    'archived': archived,
    'profile': details,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ClientRecord.fromJson(Map<String, dynamic> j) => ClientRecord(
    id: '${j['id']}',
    fullName: '${j['full_name'] ?? ''}',
    email: '${j['email'] ?? ''}',
    phone: '${j['phone'] ?? ''}',
    country: '${j['country'] ?? ''}',
    university: '${j['university'] ?? ''}',
    visaStatus: '${j['visa_status'] ?? 'Not started'}',
    passportNumber: '${j['passport_number'] ?? ''}',
    notes: '${j['notes'] ?? ''}',
    stage: '${j['stage'] ?? 'New lead'}',
    archived: j['archived'] == true,
    details:
        j['profile'] is Map
            ? Map<String, dynamic>.from(j['profile'] as Map)
            : const {},
    updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}') ?? DateTime.now(),
  );

  /// A date stored in `details` as 'YYYY-MM-DD'.
  static DateTime? dateFromDetails(Map<String, dynamic> details, String key) {
    final raw = details[key];
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// The names of documents marked as received on file.
  static List<String> receivedDocuments(Map<String, dynamic> details) =>
      (details['docs_received'] as List? ?? [])
          .map((e) => '$e')
          .where((s) => s.isNotEmpty)
          .toList();
}
