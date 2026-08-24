import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../domain/category.dart';

class CategoriesRepository {
  const CategoriesRepository(this._api);

  final ApiClient _api;

  Future<List<Category>> list() async {
    final json = await _api.getJson(Endpoints.categories);
    return _rows(json).map(Category.fromJson).toList();
  }

  /// [body] uses wire field names — see `Category.toWriteJson()`
  /// (note `parent`, not `parentId`).
  Future<Category> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.categories, body: body);
    return Category.fromJson(_document(json));
  }

  Future<Category> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.category(id), body: body);
    return Category.fromJson(_document(json));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.category(id));

  /// `GET /categories` returns a bare array; tolerate an `{items:[…]}` envelope.
  static List<Map<String, dynamic>> _rows(Object? json) {
    if (json is List) {
      return json
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    final map = J.map(json);
    for (final key in const ['items', 'categories', 'data']) {
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
    for (final key in const ['category', 'item', 'data']) {
      final nested = map[key];
      if (nested is Map) return J.map(nested);
    }
    return map;
  }
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(ref.watch(apiClientProvider)),
);

/// Cached for the whole session (not autoDispose): 33 seeded categories feed
/// every picker, the donut rows and the categories screen.
/// Invalidate it after a write with `ref.invalidate(categoriesProvider)`.
final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).list(),
);
