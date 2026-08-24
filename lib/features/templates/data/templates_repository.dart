import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/state/optimistic.dart';
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

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
///
/// Cached for the whole session (not autoDispose) — the chips row is on the
/// hot path.
final templatesFetchProvider = FutureProvider<List<Template>>(
  (ref) => ref.watch(templatesRepositoryProvider).list(),
);

/// In-flight optimistic deletes on `/templates`.
///
/// There is no `PATCH /templates/:id` in this app — a chip is created or
/// removed, never edited — so this collection only ever carries a
/// [RemoveWrite]. Creating one stays synchronous with the sheet open, like
/// every other create.
final templatesWritesProvider =
    StateNotifierProvider<
      OptimisticCollection<Template>,
      PendingWrites<Template>
    >((ref) => OptimisticCollection<Template>(idOf: (template) => template.id));

final templatesProvider = Provider<AsyncValue<List<Template>>>(
  (ref) => ref
      .watch(templatesWritesProvider)
      .applyTo(ref.watch(templatesFetchProvider)),
);

/// The settle step for a templates write.
Future<void> settleTemplates(ProviderContainer container) =>
    settleFetch(container, templatesFetchProvider);
