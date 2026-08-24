import '../../../core/api/json.dart';

class Split {
  const Split({
    required this.id,
    required this.description,
    required this.totalAmount,
    required this.yourShare,
    this.groupId,
    this.participantIds = const [],
    this.date,
    this.settled = false,
    this.note,
    this.currency = 'INR',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String description;
  final num totalAmount;
  final num yourShare;
  final String? groupId;
  final List<String> participantIds;
  final DateTime? date;
  final bool settled;
  final String? note;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// What the others collectively owe.
  num get othersShare => totalAmount - yourShare;

  factory Split.fromJson(Map<String, dynamic> json) {
    final raw = json['participants'];
    return Split(
      id: J.id(json['_id']),
      description: J.str(json['description']),
      totalAmount: J.number(json['totalAmount']),
      yourShare: J.number(json['yourShare']),
      groupId: J.refId(json['group']),
      participantIds: raw is List
          ? raw.map(J.refId).whereType<String>().toList()
          : const [],
      date: J.date(json['date']),
      settled: J.boolean(json['settled']),
      note: J.strOrNull(json['note']),
      currency: J.str(json['currency'], 'INR'),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'description': description,
    'totalAmount': totalAmount,
    'yourShare': yourShare,
    if (groupId != null) 'group': groupId,
    if (participantIds.isNotEmpty) 'participants': participantIds,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (note != null) 'note': note,
    'currency': currency,
  };
}
