import 'package:flutter_test/flutter_test.dart';
import 'package:vasflow/models/client_record.dart';
import 'package:vasflow/models/client_record_extensions.dart';

void main() {
  test('ClientRecord survives a toJson/fromJson round trip', () {
    final original = ClientRecord(
      id: 'abc-123',
      fullName: 'Ada Obi',
      email: 'ada@example.com',
      phone: '+15550100',
      country: 'Canada',
      university: 'Example University',
      visaStatus: 'In progress',
      passportNumber: 'A1234567',
      notes: 'Follow up on Monday',
      stage: 'Documents',
      updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    final copy = ClientRecord.fromJson(original.toJson());

    expect(copy.id, original.id);
    expect(copy.fullName, original.fullName);
    expect(copy.email, original.email);
    expect(copy.phone, original.phone);
    expect(copy.country, original.country);
    expect(copy.university, original.university);
    expect(copy.visaStatus, original.visaStatus);
    expect(copy.passportNumber, original.passportNumber);
    expect(copy.notes, original.notes);
    expect(copy.stage, original.stage);
    expect(copy.updatedAt.isAtSameMomentAs(original.updatedAt), isTrue);
  });

  test('fromJson fills safe defaults for missing fields', () {
    final record = ClientRecord.fromJson({'id': '1'});

    expect(record.fullName, '');
    expect(record.visaStatus, 'Not started');
    expect(record.stage, 'New lead');
  });

  test('copyWithStage changes only the stage', () {
    final original = ClientRecord(
      id: '1',
      fullName: 'Ada Obi',
      country: 'Canada',
      stage: 'New lead',
      updatedAt: DateTime(2020),
    );

    final moved = original.copyWithStage('Consultation');

    expect(moved.stage, 'Consultation');
    expect(moved.id, original.id);
    expect(moved.fullName, original.fullName);
    expect(moved.country, original.country);
    expect(moved.updatedAt.isAfter(original.updatedAt), isTrue);
  });
}
