import '../../../core/api/json.dart';

class Person {
  const Person({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.note,
    this.groupId,
    this.avatarColor,
    this.balance,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? note;
  final String? groupId;
  final String? avatarColor;

  /// Net position with this person when the server computes it.
  final num? balance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    phone: J.strOrNull(json['phone']),
    email: J.strOrNull(json['email']),
    note: J.strOrNull(json['note']),
    groupId: J.refId(json['group']),
    avatarColor: J.strOrNull(json['color']),
    balance: J.numberOrNull(json['balance']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    if (note != null) 'note': note,
    if (groupId != null) 'group': groupId,
    if (avatarColor != null) 'color': avatarColor,
  };
}

class PersonGroup {
  const PersonGroup({
    required this.id,
    required this.name,
    this.note,
    this.color,
    this.memberIds = const [],
    this.memberCount,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? note;
  final String? color;
  final List<String> memberIds;
  final int? memberCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PersonGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['members'];
    return PersonGroup(
      id: J.id(json['_id']),
      name: J.str(json['name']),
      note: J.strOrNull(json['note']),
      color: J.strOrNull(json['color']),
      memberIds: raw is List
          ? raw.map(J.refId).whereType<String>().toList()
          : const [],
      memberCount: raw is List ? raw.length : J.integer(json['memberCount']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    if (note != null) 'note': note,
    if (color != null) 'color': color,
    if (memberIds.isNotEmpty) 'members': memberIds,
  };
}
