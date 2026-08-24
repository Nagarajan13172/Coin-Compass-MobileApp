import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../people/domain/person.dart';

class Credit {
  const Credit({
    required this.id,
    required this.amount,
    required this.direction,
    this.personId,
    this.person,
    this.personName,
    this.note,
    this.date,
    this.dueDate,
    this.settled = false,
    this.settledAt,
    this.outstanding,
    this.currency = 'INR',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final num amount;
  final CreditDirection direction;
  final String? personId;
  final Person? person;

  /// The API accepts `person` as a free-text name on create.
  final String? personName;
  final String? note;
  final DateTime? date;
  final DateTime? dueDate;
  final bool settled;
  final DateTime? settledAt;
  final num? outstanding;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => person?.name ?? personName ?? 'Unknown';
  num get outstandingOrAmount => outstanding ?? amount;
  bool get isOverdue =>
      !settled && dueDate != null && dueDate!.isBefore(DateTime.now());

  factory Credit.fromJson(Map<String, dynamic> json) {
    final personObject = J.refObject(json['person']);
    return Credit(
      id: J.id(json['_id']),
      amount: J.number(json['amount']),
      direction: CreditDirection.fromApi(J.strOrNull(json['direction'])),
      personId: J.refId(json['person']),
      person: personObject == null ? null : Person.fromJson(personObject),
      personName: personObject == null ? J.strOrNull(json['person']) : null,
      note: J.strOrNull(json['note']),
      date: J.date(json['date']),
      dueDate: J.date(json['dueDate']),
      settled: J.boolean(json['settled']),
      settledAt: J.date(json['settledAt']),
      outstanding: J.numberOrNull(json['outstanding']),
      currency: J.str(json['currency'], 'INR'),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'person': personId ?? personName,
    'direction': direction.api,
    'amount': amount,
    if (note != null) 'note': note,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (dueDate != null) 'dueDate': dueDate!.toUtc().toIso8601String(),
    'currency': currency,
  };
}

/// `GET /credits/summary`
class CreditsSummary {
  const CreditsSummary({
    this.given = 0,
    this.received = 0,
    this.borrowed = 0,
    this.repaid = 0,
    this.net = 0,
  });

  final num given;
  final num received;
  final num borrowed;
  final num repaid;
  final num net;

  factory CreditsSummary.fromJson(Map<String, dynamic> json) => CreditsSummary(
    given: J.number(json['given']),
    received: J.number(json['received']),
    borrowed: J.number(json['borrowed']),
    repaid: J.number(json['repaid']),
    net: J.number(json['net']),
  );
}
