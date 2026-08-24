import '../../../core/api/json.dart';

/// `people.relation` — the only field besides `name` the write schema declares.
/// See docs/WRITE_SCHEMAS.md. Follows the `fromApi` / `api` / `label` shape of
/// lib/core/api/enums.dart; it lives here rather than there because this
/// vocabulary belongs to a single feature.
enum PersonRelation {
  family('family'),
  friend('friend'),
  colleague('colleague'),
  other('other');

  const PersonRelation(this.api);
  final String api;

  /// Tolerant like every other `fromApi`: an unknown value falls back to the
  /// server's own default rather than throwing.
  static PersonRelation fromApi(String? value) => PersonRelation.values
      .firstWhere((e) => e.api == value, orElse: () => PersonRelation.other);

  String get label => switch (this) {
    PersonRelation.family => 'Family',
    PersonRelation.friend => 'Friend',
    PersonRelation.colleague => 'Colleague',
    PersonRelation.other => 'Other',
  };
}

/// Someone in the address book.
///
/// `POST /people` accepts `name` and `relation` and nothing else — every other
/// key is stripped by the server's Zod schema without an error, so no other
/// writable field is modelled here. `key` is a server-computed slug.
class Person {
  const Person({
    required this.id,
    required this.name,
    this.key,
    this.relation = PersonRelation.other,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Server-computed slug (`"Karthik"` -> `"karthik"`). Read-only.
  final String? key;
  final PersonRelation relation;
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
    key: J.strOrNull(json['key']),
    relation: PersonRelation.fromApi(J.strOrNull(json['relation'])),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  /// The complete accepted body for `POST`/`PATCH /people`.
  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'relation': relation.api,
  };
}

/// A household, a trip, a team. `POST /people/groups` accepts `name` and
/// `members` only.
class PersonGroup {
  const PersonGroup({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.memberCount,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> memberIds;
  final int? memberCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PersonGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['members'];
    return PersonGroup(
      id: J.id(json['_id']),
      name: J.str(json['name']),
      memberIds: raw is List
          ? raw.map(J.refId).whereType<String>().toList()
          : const [],
      memberCount: raw is List ? raw.length : J.integer(json['memberCount']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }

  /// The complete accepted body for `POST`/`PATCH /people/groups`.
  Map<String, dynamic> toWriteJson() => {
    'name': name,
    if (memberIds.isNotEmpty) 'members': memberIds,
  };
}
