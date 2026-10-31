import 'client_record.dart';

extension ClientRecordStageCopy on ClientRecord {
  ClientRecord copyWithStage(String next) => ClientRecord(
    id: id,
    fullName: fullName,
    email: email,
    phone: phone,
    country: country,
    university: university,
    visaStatus: visaStatus,
    passportNumber: passportNumber,
    notes: notes,
    stage: next,
    updatedAt: DateTime.now(),
    archived: archived,
    photoPath: photoPath,
    details: details,
  );

  ClientRecord copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? country,
    String? university,
    String? visaStatus,
    String? passportNumber,
    String? notes,
    String? stage,
    bool? archived,
    String? photoPath,
    DateTime? updatedAt,
    Map<String, dynamic>? details,
  }) => ClientRecord(
    id: id,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    country: country ?? this.country,
    university: university ?? this.university,
    visaStatus: visaStatus ?? this.visaStatus,
    passportNumber: passportNumber ?? this.passportNumber,
    notes: notes ?? this.notes,
    stage: stage ?? this.stage,
    archived: archived ?? this.archived,
    photoPath: photoPath ?? this.photoPath,
    details: details ?? this.details,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
