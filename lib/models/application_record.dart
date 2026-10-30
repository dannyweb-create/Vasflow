/// One university/visa application for a client.
/// Stored in the `client_applications` table (see phase4_features.sql).
class ApplicationRecord {
  final String id;
  final String clientId;
  final String country;
  final String institution;
  final String course;
  final String intake;
  final String status;
  final String type;

  /// Dates stored as ISO date strings ('YYYY-MM-DD').
  final DateTime? submissionDate;
  final DateTime? deadline;

  final DateTime updatedAt;

  const ApplicationRecord({
    required this.id,
    required this.clientId,
    this.country = '',
    this.institution = '',
    this.course = '',
    this.intake = '',
    this.status = 'Draft',
    this.type = 'University admission',
    this.submissionDate,
    this.deadline,
    required this.updatedAt,
  });

  ApplicationRecord copyWith({
    String? clientId,
    String? country,
    String? institution,
    String? course,
    String? intake,
    String? status,
    String? type,
    DateTime? submissionDate,
    DateTime? deadline,
  }) => ApplicationRecord(
    id: id,
    clientId: clientId ?? this.clientId,
    country: country ?? this.country,
    institution: institution ?? this.institution,
    course: course ?? this.course,
    intake: intake ?? this.intake,
    status: status ?? this.status,
    type: type ?? this.type,
    submissionDate: submissionDate ?? this.submissionDate,
    deadline: deadline ?? this.deadline,
    updatedAt: DateTime.now(),
  );

  static DateTime? _date(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  Map<String, dynamic> toJson() => {
    'application_type': type,
    'client_id': clientId,
    'country': country,
    'institution': institution,
    'course': course,
    'intake': intake,
    'status': status,
    'submission_date': submissionDate?.toIso8601String().substring(0, 10),
    'deadline': deadline?.toIso8601String().substring(0, 10),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ApplicationRecord.fromJson(Map<String, dynamic> j) =>
      ApplicationRecord(
        id: '${j['id']}',
        clientId: '${j['client_id'] ?? ''}',
        country: '${j['country'] ?? ''}',
        institution: '${j['institution'] ?? ''}',
        course: '${j['course'] ?? ''}',
        intake: '${j['intake'] ?? ''}',
        status: '${j['status'] ?? 'Draft'}',
        type: '${j['application_type'] ?? 'University admission'}',
        submissionDate: _date(j['submission_date']),
        deadline: _date(j['deadline']),
        updatedAt:
            DateTime.tryParse('${j['updated_at'] ?? ''}') ?? DateTime.now(),
      );
}
