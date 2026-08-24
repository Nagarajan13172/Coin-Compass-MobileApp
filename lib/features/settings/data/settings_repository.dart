import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/json.dart';
import '../../../core/utils/money.dart';
import '../domain/app_settings.dart';

/// `GET|PATCH /settings` — the single wallet-settings document
/// (`baseCurrency`, `theme`, `locale`, `firstDayOfWeek`, currency table, …).
class SettingsRepository {
  const SettingsRepository(this._api);

  final ApiClient _api;

  Future<AppSettings> get() async {
    final json = await _api.getJson(Endpoints.settings);
    return AppSettings.fromJson(_unwrap(json));
  }

  /// Partial update — send only the keys that changed, e.g.
  /// `patch({'theme': 'dark'})`. Returns the settings document as saved.
  Future<AppSettings> patch(Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.settings, body: body);
    return AppSettings.fromJson(_unwrap(json));
  }

  /// The live GET returns the document bare; PATCH is unverified against this
  /// deployment, so tolerate a `{settings: {...}}` wrapper too.
  static Map<String, dynamic> _unwrap(Object? json) {
    final map = J.map(json);
    final nested = map['settings'];
    if (nested is Map) return nested.cast<String, dynamic>();
    return map;
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(apiClientProvider)),
);

/// Cached on purpose (no autoDispose): settings drive the theme, the currency
/// symbol and the week start, so every screen reads them and a refetch per
/// screen would be wasteful. Call `ref.invalidate(settingsProvider)` after a
/// successful [SettingsRepository.patch].
final settingsProvider = FutureProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).get(),
);

/// Symbols for the currencies the backend seeds, used only when the settings
/// document has not loaded yet or its `currencies[]` is missing the base code.
const Map<String, String> _fallbackSymbols = {
  'INR': Money.rupee,
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
};

/// The base-currency symbol, so no screen has to re-derive it. Defaults to `₹`
/// while settings are loading (or if they fail), which matches the account this
/// app ships against.
final currencySymbolProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (settings == null) return Money.rupee;

  for (final currency in settings.currencies) {
    if (currency.code == settings.baseCurrency && currency.symbol.isNotEmpty) {
      return currency.symbol;
    }
  }
  return _fallbackSymbols[settings.baseCurrency] ?? Money.rupee;
});
