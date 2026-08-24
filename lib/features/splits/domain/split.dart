import '../../../core/api/json.dart';

/// A bill shared with other people.
///
/// The write keys here are exactly the ones `POST /splits` declares — see
/// `docs/WRITE_SCHEMAS.md`. `group`, `currency` and `settled` are not among
/// them: the server strips them without an error, so the model does not carry
/// them and the form does not offer them.
class Split {
  const Split({
    required this.id,
    required this.description,
    required this.totalAmount,
    required this.yourShare,
    this.participantIds = const [],
    this.date,
    this.note,
    this.categoryId,
    this.accountId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String description;
  final num totalAmount;
  final num yourShare;
  final List<String> participantIds;
  final DateTime? date;
  final String? note;

  /// References arrive as either an id string or a populated object; only the
  /// id is kept — the pickers resolve it against the categories / accounts
  /// lists they already load.
  final String? categoryId;
  final String? accountId;

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
      participantIds: raw is List
          ? raw.map(J.refId).whereType<String>().toList()
          : const [],
      date: J.date(json['date']),
      note: J.strOrNull(json['note']),
      categoryId: J.refId(json['category']),
      accountId: J.refId(json['account']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'description': description,
    'totalAmount': totalAmount,
    'yourShare': yourShare,
    if (participantIds.isNotEmpty) 'participants': participantIds,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (note != null) 'note': note,
    if (categoryId != null) 'category': categoryId,
    if (accountId != null) 'account': accountId,
  };
}
