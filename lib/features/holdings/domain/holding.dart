import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

/// Savings & investments that feed the Net Worth screen.
///
/// The model deliberately has **no `invested`, `institution` or `roi`**. Phase 1
/// guessed them from the web UI; the probe in docs/WRITE_SCHEMAS.md shows
/// `POST /holdings` strips all three, and no real payload has ever come back
/// carrying them. A holding is a single current [value] — cost basis and
/// gain/loss do not exist server-side, so nothing here may pretend they do.
class Holding {
  const Holding({
    required this.id,
    required this.name,
    required this.holdingClass,
    required this.subtype,
    required this.value,
    this.maturityDate,
    this.startDate,
    this.note,
    this.currency = 'INR',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final HoldingClass holdingClass;
  final HoldingSubtype subtype;

  /// Current worth. The only money field a holding has.
  final num value;
  final DateTime? maturityDate;
  final DateTime? startDate;
  final String? note;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSaving => holdingClass == HoldingClass.saving;

  /// True once [maturityDate] is in the past — deposits keep their row after
  /// maturing, so the list badges them rather than hiding them.
  bool get isMatured =>
      maturityDate != null && maturityDate!.isBefore(DateTime.now());

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    holdingClass: HoldingClass.fromApi(J.strOrNull(json['class'])),
    subtype: HoldingSubtype.fromApi(J.strOrNull(json['subtype'])),
    value: J.number(json['value']),
    maturityDate: J.date(json['maturityDate']),
    startDate: J.date(json['startDate']),
    note: J.strOrNull(json['note']),
    currency: J.str(json['currency'], 'INR'),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  /// Only the keys `POST /holdings` declares — see docs/WRITE_SCHEMAS.md.
  /// Guarded by test/write_schema_test.dart.
  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'class': holdingClass.api,
    'subtype': subtype.api,
    'value': value,
    if (maturityDate != null) 'maturityDate': _apiDay(maturityDate!),
    if (startDate != null) 'startDate': _apiDay(startDate!),
    if (note != null) 'note': note,
    'currency': currency,
  };

  /// 6.4 — this row as the client claims the server will return it.
  ///
  /// A holding is a single current [value] with no derived fields at all — no
  /// cost basis, no gain, no server arithmetic — so the prediction is a
  /// straight copy of what the form sent. Never null.
  ///
  /// The net-worth chart the value feeds is a separate server aggregate and is
  /// refetched, never guessed.
  ///
  /// See `lib/core/state/optimistic.dart`.
  Holding? predict({
    required String name,
    required HoldingClass holdingClass,
    required HoldingSubtype subtype,
    required num value,
    required String currency,
    DateTime? maturityDate,
    DateTime? startDate,
    String? note,
  }) => Holding(
    id: id,
    name: name,
    holdingClass: holdingClass,
    subtype: subtype,
    value: value,
    maturityDate: maturityDate,
    startDate: startDate,
    note: note,
    currency: currency,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// A calendar day as the API stores it: UTC midnight of that day. `toUtc()` on
/// a local midnight would move an IST date back to the previous day, drifting a
/// maturity date by one.
String _apiDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).toIso8601String();
