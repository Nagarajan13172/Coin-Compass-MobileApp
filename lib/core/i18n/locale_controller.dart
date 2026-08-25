import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';

/// The web app ships English + Tamil. The mobile app carries the same toggle —
/// but only once there is something to toggle *to*.
///
/// ## Why the label follows the renderer, not the preference
///
/// Before 7.1a, tapping the pill relabelled the bar `த`, persisted a Tamil
/// locale, and then carried on painting English. The state claimed a language
/// the app was not in.
///
/// Runtime translation can reach that state a second way: the locale is Tamil
/// but ML Kit's language pack is missing or still downloading, so `lookup`
/// passes English straight through. So the pill renders only while Tamil is
/// genuinely available, and `shortLabel` is driven by what is actually on
/// screen — see `app_scaffold.dart`.
class SupportedLocales {
  const SupportedLocales._();

  static const Locale english = Locale('en');
  static const Locale tamil = Locale('ta');

  /// Every locale the app knows how to *name* — what `MaterialApp` advertises.
  static const List<Locale> all = [english, tamil];

  /// Every locale the app can render. Whether Tamil is *usable* right now is a
  /// separate question — it needs ML Kit's language pack — and that lives in
  /// `tamilAvailableProvider`, because it is device state rather than a
  /// constant.
  static const List<Locale> available = all;

  static String shortLabel(Locale locale) =>
      locale.languageCode == 'ta' ? 'த' : 'EN';

  static String nativeLabel(Locale locale) =>
      locale.languageCode == 'ta' ? 'தமிழ்' : 'English';
}

class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs) : super(_read(_prefs));

  static const String _key = 'locale';
  final SharedPreferences _prefs;

  static Locale _read(SharedPreferences prefs) {
    final code = prefs.getString(_key);
    final stored = code == 'ta'
        ? SupportedLocales.tamil
        : SupportedLocales.english;
    return stored;
  }

  Future<void> set(Locale locale) async {
    final target = locale;
    if (target.languageCode == state.languageCode) return;
    state = target;
    await _prefs.setString(_key, target.languageCode);
  }

  Future<void> toggle() => set(
    state.languageCode == 'en'
        ? SupportedLocales.tamil
        : SupportedLocales.english,
  );
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
      return LocaleController(ref.watch(sharedPreferencesProvider));
    });
