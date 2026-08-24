import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'en.dart';
import 'locale_controller.dart';

/// Tiny lookup layer with `{{var}}` interpolation.
///
/// Deliberately not `flutter gen-l10n` — the web app's dictionary is a flat
/// key/value map and porting it later is a straight drop-in this way.
class Strings {
  const Strings(this.locale, this._map);

  final Locale locale;
  final Map<String, String> _map;

  static Strings of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Strings(locale, _mapFor(locale));
  }

  static Map<String, String> _mapFor(Locale locale) {
    // 'ta' intentionally falls back to English until the Tamil dictionary lands.
    switch (locale.languageCode) {
      case 'ta':
        return enStrings;
      default:
        return enStrings;
    }
  }

  /// Returns the key itself when missing, so gaps are obvious in the UI rather
  /// than rendering an empty space.
  String t(String key, [Map<String, Object?>? vars]) {
    var out = _map[key] ?? key;
    if (vars != null) {
      vars.forEach((name, value) {
        out = out.replaceAll('{{$name}}', '${value ?? ''}');
      });
    }
    return out;
  }

  String call(String key, [Map<String, Object?>? vars]) => t(key, vars);
}

final stringsProvider = Provider<Strings>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return Strings(locale, Strings._mapFor(locale));
});

extension StringsX on BuildContext {
  Strings get s => Strings.of(this);
}
