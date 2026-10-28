import 'client_record.dart';
extension ClientRecordStageCopy on ClientRecord {
  ClientRecord copyWithStage(String next) => ClientRecord(
    id:id, fullName:fullName, email:email, phone:phone, country:country,
    university:university, visaStatus:visaStatus, passportNumber:passportNumber,
    notes:notes, stage:next, updatedAt:DateTime.now(),
  );
}
