import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

/// Savings & investments that feed the Net Worth screen.
class Holding {
  const Holding({
    required this.id,
    required this.name,
    required this.holdingClass,
    required this.subtype,
    required this.value,
    this.invested,
    this.institution,
    this.roi,
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
  final num value;
  final num? invested;
  final String? institution;
  final num? roi;
  final DateTime? maturityDate;
  final DateTime? startDate;
  final String? note;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  num get gain => invested == null ? 0 : value - invested!;
  num? get gainPct =>
      (invested == null || invested == 0) ? null : (gain / invested!) * 100;

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    holdingClass: HoldingClass.fromApi(J.strOrNull(json['class'])),
    subtype: HoldingSubtype.fromApi(J.strOrNull(json['subtype'])),
    value: J.number(json['value']),
    invested: J.numberOrNull(json['invested']),
    institution: J.strOrNull(json['institution']),
    roi: J.numberOrNull(json['roi']),
    maturityDate: J.date(json['maturityDate']),
    startDate: J.date(json['startDate']),
    note: J.strOrNull(json['note']),
    currency: J.str(json['currency'], 'INR'),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'class': holdingClass.api,
    'subtype': subtype.api,
    'value': value,
    if (invested != null) 'invested': invested,
    if (institution != null) 'institution': institution,
    if (roi != null) 'roi': roi,
    if (maturityDate != null)
      'maturityDate': maturityDate!.toUtc().toIso8601String(),
    if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
    if (note != null) 'note': note,
    'currency': currency,
  };
}
