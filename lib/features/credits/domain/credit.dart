import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../people/domain/person.dart';

/// One entry in the lending ledger.
///
/// The write keys here are exactly the ones `POST /credits` declares —
/// see `docs/WRITE_SCHEMAS.md`. `dueDate`, `currency`, `settled` and
/// `settledAt` are not among them: the server strips them without an error,
/// so the model does not carry them and the form does not offer them.
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
    this.accountId,
    this.categoryId,
    this.outstanding,
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

  /// References arrive as either an id string or a populated object; only the
  /// id is kept — the pickers resolve it against the accounts / categories
  /// lists they already load.
  final String? accountId;
  final String? categoryId;

  final num? outstanding;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => person?.name ?? personName ?? 'Unknown';
  num get outstandingOrAmount => outstanding ?? amount;

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
      accountId: J.refId(json['account']),
      categoryId: J.refId(json['category']),
      outstanding: J.numberOrNull(json['outstanding']),
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
    if (accountId != null) 'account': accountId,
    if (categoryId != null) 'category': categoryId,
  };

  /// 6.4 — this row as the client claims the server will return it.
  ///
  /// [outstanding] is the one server-computed field a credit carries, and both
  /// the amount and the direction move it, so it is nulled; [outstandingOrAmount]
  /// then falls back to the amount the owner just typed, which is what the row
  /// shows. [person] is carried when the id is unchanged and dropped when the
  /// form named someone else, so no row ever shows the previous person's name
  /// beside the new one's id. Never null.
  ///
  /// See `lib/core/state/optimistic.dart`.
  Credit? predict({
    required num amount,
    required CreditDirection direction,
    required DateTime date,
    String? personId,
    String? personName,
    Person? person,
    String? note,
    String? accountId,
    String? categoryId,
  }) => Credit(
    id: id,
    amount: amount,
    direction: direction,
    personId: personId,
    person:
        person ??
        (personId != null && personId == this.personId ? this.person : null),
    personName: personName,
    note: note,
    date: date,
    accountId: accountId,
    categoryId: categoryId,
    outstanding: null,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
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

  /// What is still owed to you: what you gave out, less what came back.
  num get owedToYou => given - received;

  /// What you still owe: what you borrowed, less what you have repaid.
  num get youOwe => borrowed - repaid;

  factory CreditsSummary.fromJson(Map<String, dynamic> json) => CreditsSummary(
    given: J.number(json['given']),
    received: J.number(json['received']),
    borrowed: J.number(json['borrowed']),
    repaid: J.number(json['repaid']),
    net: J.number(json['net']),
  );

  /// Client-side totals, used when `/credits/summary` sends nothing usable —
  /// on an account with no credits it answers with an empty array. Every entry
  /// counts: the API has no settled flag, so a closed loan is recorded as the
  /// matching `received` / `repaid` entry, which nets the original out.
  factory CreditsSummary.fromCredits(List<Credit> credits) {
    num given = 0;
    num received = 0;
    num borrowed = 0;
    num repaid = 0;

    for (final credit in credits) {
      final amount = credit.outstandingOrAmount;
      switch (credit.direction) {
        case CreditDirection.given:
          given += amount;
        case CreditDirection.received:
          received += amount;
        case CreditDirection.borrowed:
          borrowed += amount;
        case CreditDirection.repaid:
          repaid += amount;
      }
    }

    return CreditsSummary(
      given: given,
      received: received,
      borrowed: borrowed,
      repaid: repaid,
      net: (given - received) - (borrowed - repaid),
    );
  }
}
