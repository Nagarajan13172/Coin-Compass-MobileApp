import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'en.dart';
import 'locale_controller.dart';
import 'ta.dart';

/// Tiny lookup layer with `{{var}}` interpolation.
///
/// Deliberately not `flutter gen-l10n` — the web app's dictionary is a flat
/// key/value map and porting it later is a straight drop-in this way.
class Strings {
  const Strings(this.locale, this._map, {Map<String, String>? fallback})
    : _fallback = fallback ?? enStrings;

  final Locale locale;
  final Map<String, String> _map;

  /// Always English. A Tamil dictionary that is only half-filled must render
  /// the English sentence for the keys it has not reached yet — never the raw
  /// key, and never a blank.
  final Map<String, String> _fallback;

  static Strings of(BuildContext context) =>
      forLocale(Localizations.localeOf(context));

  static Strings forLocale(Locale locale) =>
      Strings(locale, _mapFor(locale), fallback: enStrings);

  static Map<String, String> _mapFor(Locale locale) => switch (locale
      .languageCode) {
    'ta' => taStrings,
    _ => enStrings,
  };

  /// Resolution order: this locale → English → the key itself.
  ///
  /// The key is a deliberate last resort: it renders as something obviously
  /// wrong (`dash.netWorth`) rather than an empty space, so a missing entry is
  /// visible in a screenshot instead of silently collapsing a layout. In
  /// practice English catches it first.
  String t(String key, [Map<String, Object?>? vars]) {
    final value = _pick(key);
    if (vars == null || vars.isEmpty) return value;
    var out = value;
    vars.forEach((name, replacement) {
      out = out.replaceAll('{{$name}}', '${replacement ?? ''}');
    });
    return out;
  }

  String _pick(String key) {
    final mine = _map[key];
    if (mine != null && mine.isNotEmpty) return mine;
    final english = _fallback[key];
    if (english != null && english.isNotEmpty) return english;
    return key;
  }

  String call(String key, [Map<String, Object?>? vars]) => t(key, vars);
}

final stringsProvider = Provider<Strings>((ref) {
  return Strings.forLocale(ref.watch(localeControllerProvider));
});

extension StringsX on BuildContext {
  Strings get s => Strings.of(this);
}
