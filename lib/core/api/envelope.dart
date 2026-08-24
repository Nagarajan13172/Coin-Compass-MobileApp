import 'json.dart';

/// The API is inconsistent about wrapping: most list endpoints return a bare
/// array, a few wrap it as `{items: […]}`, and write endpoints return either the
/// bare document or `{<resource>: {…}}`. Rather than repeat that tolerance in
/// every repository, both shapes are unwrapped here.
class Envelope {
  const Envelope._();

  /// Rows from a list response, whichever shape it arrived in. [keys] are the
  /// resource-specific wrappers to look inside, tried before `items`/`data`.
  static List<Map<String, dynamic>> rows(
    Object? json, [
    List<String> keys = const [],
  ]) {
    if (json is List) return _cast(json);

    final map = J.map(json);
    for (final key in [...keys, 'items', 'data']) {
      final nested = map[key];
      if (nested is List) return _cast(nested);
    }
    return const [];
  }

  /// The document from a create/update response. [keys] are the wrappers to
  /// look inside, tried before `item`/`data`.
  static Map<String, dynamic> document(
    Object? json, [
    List<String> keys = const [],
  ]) {
    final map = J.map(json);
    for (final key in [...keys, 'item', 'data']) {
      final nested = map[key];
      if (nested is Map) return J.map(nested);
    }
    return map;
  }

  static List<Map<String, dynamic>> _cast(List<dynamic> list) =>
      list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}
