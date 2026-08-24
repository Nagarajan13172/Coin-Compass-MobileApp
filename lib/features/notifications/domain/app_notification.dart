import '../../../core/api/json.dart';

/// `GET /notifications` -> `{items, unread}`
class NotificationFeed {
  const NotificationFeed({this.items = const [], this.unread = 0});

  final List<AppNotification> items;
  final int unread;

  factory NotificationFeed.fromJson(Object? json) {
    if (json is List) {
      final items = J.list(json, AppNotification.fromJson);
      return NotificationFeed(
        items: items,
        unread: items.where((e) => !e.read).length,
      );
    }
    final map = J.map(json);
    return NotificationFeed(
      items: J.list(map['items'], AppNotification.fromJson),
      unread: J.integer(map['unread']),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.link,
    this.params = const {},
    this.read = false,
    this.readAt,
    this.dedupeKey,
    this.createdAt,
  });

  final String id;

  /// e.g. `recurring.posted`, `budget.exceeded`
  final String type;
  final String? link;
  final Map<String, dynamic> params;
  final bool read;
  final DateTime? readAt;
  final String? dedupeKey;
  final DateTime? createdAt;

  /// The backend sends structured params rather than rendered copy, so the
  /// client composes the text. Falls back to a humanised type.
  String get title {
    final ruleTitle = params['ruleTitle'];
    if (ruleTitle is String && ruleTitle.isNotEmpty) return ruleTitle;
    return type
        .split('.')
        .last
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
  }

  num? get amount => J.numberOrNull(params['amount']);
  String? get currency => J.strOrNull(params['currency']);
  int? get countParam =>
      params['count'] == null ? null : J.integer(params['count']);

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: J.id(json['_id']),
        type: J.str(json['type']),
        link: J.strOrNull(json['link']),
        params: J.map(json['params']),
        read: J.boolean(json['read']),
        readAt: J.date(json['readAt']),
        dedupeKey: J.strOrNull(json['dedupeKey']),
        createdAt: J.date(json['createdAt']),
      );
}
