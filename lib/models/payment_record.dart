/// One fee/payment row for a client (consultation, application fee, etc).
/// Stored in the `client_payments` table (see phase4_features.sql).
/// outstandingFor = amount - paidAmount.
class PaymentRecord {
  final String id;
  final String clientId;
  final String feeType;
  final String description;

  /// Money amounts use plain doubles; currency is whatever the practice uses.
  final double amount;
  final double paidAmount;

  final DateTime? paidDate;
  final String reference;
  final DateTime updatedAt;

  const PaymentRecord({
    required this.id,
    required this.clientId,
    this.feeType = 'Consultation fee',
    this.description = '',
    this.amount = 0,
    this.paidAmount = 0,
    this.paidDate,
    this.reference = '',
    required this.updatedAt,
  });

  double get outstanding => amount - paidAmount;

  bool get fullyPaid => outstanding <= 0.0001;

  static double _num(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  PaymentRecord copyWith({
    String? clientId,
    String? feeType,
    String? description,
    double? amount,
    double? paidAmount,
    DateTime? paidDate,
    String? reference,
  }) => PaymentRecord(
    id: id,
    clientId: clientId ?? this.clientId,
    feeType: feeType ?? this.feeType,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    paidAmount: paidAmount ?? this.paidAmount,
    paidDate: paidDate ?? this.paidDate,
    reference: reference ?? this.reference,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'fee_type': feeType,
    'description': description,
    'amount': amount,
    'paid_amount': paidAmount,
    'paid_date': paidDate?.toIso8601String().substring(0, 10),
    'reference': reference,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
    id: '${j['id']}',
    clientId: '${j['client_id'] ?? ''}',
    feeType: '${j['fee_type'] ?? 'Consultation fee'}',
    description: '${j['description'] ?? ''}',
    amount: _num(j['amount']),
    paidAmount: _num(j['paid_amount']),
    paidDate:
        '${j['paid_date'] ?? ''}'.isEmpty
            ? null
            : DateTime.tryParse('${j['paid_date']}'),
    reference: '${j['reference'] ?? ''}',
    updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}') ?? DateTime.now(),
  );
}
