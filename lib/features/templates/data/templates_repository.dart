import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../domain/template.dart';

/// The "Quick add" chips on the Transactions screen.
class TemplatesRepository {
  const TemplatesRepository(this._api);

  final ApiClient _api;

  Future<List<Template>> list() async {
    final json = await _api.getJson(Endpoints.templates);
    return _rows(json).map(Template.fromJson).toList();
  }

  /// [body] uses wire field names — see `Template.toWriteJson()`.
  Future<Template> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.templates, body: body);
    return Template.fromJson(_document(json));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.template(id));

  /// `GET /templates` returns a bare array; tolerate an `{items:[…]}` envelope.
  static List<Map<String, dynamic>> _rows(Object? json) {
    if (json is List) {
      return json
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    final map = J.map(json);
    for (final key in const ['items', 'templates', 'data']) {
      final nested = map[key];
      if (nested is List) {
        return nested
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  static Map<String, dynamic> _document(Object? json) {
    final map = J.map(json);
    for (final key in const ['template', 'item', 'data']) {
      final nested = map[key];
      if (nested is Map) return J.map(nested);
    }
    return map;
  }
}

final templatesRepositoryProvider = Provider<TemplatesRepository>(
  (ref) => TemplatesRepository(ref.watch(apiClientProvider)),
);

/// Cached for the whole session (not autoDispose) — the chips row is on the
/// hot path. Invalidate after a write with `ref.invalidate(templatesProvider)`.
final templatesProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(templatesRepositoryProvider).list(),
);
