import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';

/// The web app ships English + Tamil. The mobile app carries the same toggle;
/// the Tamil dictionary is a follow-up (see docs/ROADMAP.md phase 7.1), so `ta`
/// currently falls back to the English map.
class SupportedLocales {
  const SupportedLocales._();

  static const Locale english = Locale('en');
  static const Locale tamil = Locale('ta');
  static const List<Locale> all = [english, tamil];

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
    return code == 'ta' ? SupportedLocales.tamil : SupportedLocales.english;
  }

  Future<void> set(Locale locale) async {
    if (locale.languageCode == state.languageCode) return;
    state = locale;
    await _prefs.setString(_key, locale.languageCode);
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
