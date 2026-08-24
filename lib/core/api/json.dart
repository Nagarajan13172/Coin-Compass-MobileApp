import '../utils/date_x.dart';

/// Shared parsing helpers. Mongo payloads are loosely typed — numbers arrive as
/// both int and double, references arrive as either an id string or a populated
/// object — so every model funnels through these.
class J {
  const J._();

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : const {};

  static String id(Object? v) {
    if (v is Map) return '${v['_id'] ?? v['id'] ?? ''}';
    return v == null ? '' : '$v';
  }

  /// A reference field that may be a plain id string OR a populated document.
  /// Returns the id in both cases, or null when absent.
  static String? refId(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final raw = v['_id'] ?? v['id'];
      return raw == null ? null : '$raw';
    }
    final s = '$v';
    return s.isEmpty ? null : s;
  }

  /// The populated object, or null when the field was just an id string.
  static Map<String, dynamic>? refObject(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  static String str(Object? v, [String fallback = '']) =>
      v == null ? fallback : '$v';

  static String? strOrNull(Object? v) {
    if (v == null) return null;
    final s = '$v';
    return s.isEmpty ? null : s;
  }

  /// Money and rates are always `num` — the API mixes int and double freely.
  static num number(Object? v, [num fallback = 0]) {
    if (v is num) return v;
    return num.tryParse('$v') ?? fallback;
  }

  static num? numberOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse('$v');
  }

  static int integer(Object? v, [int fallback = 0]) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  static bool boolean(Object? v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return fallback;
  }

  static DateTime? date(Object? v) => DateX.parse(v);

  static List<String> stringList(Object? v) => v is List
      ? v.map((e) => '$e').where((e) => e.isNotEmpty).toList()
      : const [];

  static List<T> list<T>(Object? v, T Function(Map<String, dynamic>) from) =>
      v is List
      ? v.whereType<Map>().map((e) => from(e.cast<String, dynamic>())).toList()
      : <T>[];
}
