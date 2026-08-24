import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../domain/metal_price.dart';

/// `GET /metals/latest` — today's gold and silver prices.
///
/// `configured` is false when the deployment has no metals provider wired up;
/// in that case `gold` and `silver` are null and the UI shows an empty state
/// rather than an error.
class MetalsRepository {
  const MetalsRepository(this._api);

  final ApiClient _api;

  Future<MetalsLatest> latest() async {
    final json = await _api.getJson(Endpoints.metalsLatest);
    return MetalsLatest.fromJson(J.map(json));
  }
}

final metalsRepositoryProvider = Provider<MetalsRepository>(
  (ref) => MetalsRepository(ref.watch(apiClientProvider)),
);

/// Prices refresh server-side once a day, so this is cached for the session.
final metalsLatestProvider = FutureProvider<MetalsLatest>(
  (ref) => ref.watch(metalsRepositoryProvider).latest(),
);
