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
  final DateTime updatedAt;

  const ClientRecord({
    required this.id, required this.fullName, this.email = '', this.phone = '',
    this.country = '', this.university = '', this.visaStatus = 'Not started',
    this.passportNumber = '', this.notes = '', this.stage = 'New lead',
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'full_name': fullName, 'email': email, 'phone': phone,
    'country': country, 'university': university, 'visa_status': visaStatus,
    'passport_number': passportNumber, 'notes': notes, 'stage': stage,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ClientRecord.fromJson(Map<String, dynamic> j) => ClientRecord(
    id: '${j['id']}', fullName: '${j['full_name'] ?? ''}',
    email: '${j['email'] ?? ''}', phone: '${j['phone'] ?? ''}',
    country: '${j['country'] ?? ''}', university: '${j['university'] ?? ''}',
    visaStatus: '${j['visa_status'] ?? 'Not started'}',
    passportNumber: '${j['passport_number'] ?? ''}', notes: '${j['notes'] ?? ''}',
    stage: '${j['stage'] ?? 'New lead'}',
    updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}') ?? DateTime.now(),
  );
}
