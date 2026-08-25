import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';
import 'tamil_readiness.dart';

/// The web app ships English + Tamil. The mobile app carries the same toggle —
/// but only once there is something to toggle *to*.
///
/// ## Why the toggle hides itself
///
/// Until phase 7.1 lands a dictionary, `ta` resolved to the English map, so
/// switching to Tamil relabelled the app bar `த`, **persisted a Tamil locale**,
/// and then rendered English underneath. A snackbar said "Tamil is coming
/// soon", which was honest about the intent but did not undo the state: the app
/// went on claiming to be in Tamil.
///
/// So availability is gated on Tamil being *complete*, and the gate is held to
/// the generator's own `untranslated.json` report by a test — see
/// [kTamilReady]. Nobody can flip it early, and nobody can finish the
/// translation and forget to flip it, because the test fails both ways.
class SupportedLocales {
  const SupportedLocales._();

  static const Locale english = Locale('en');
  static const Locale tamil = Locale('ta');

  /// Every locale the app knows how to *name* — what `MaterialApp` advertises.
  static const List<Locale> all = [english, tamil];

  /// True once Tamil is complete — see [kTamilReady], which a test holds to
  /// `lib/l10n/untranslated.json` in both directions.
  ///
  /// Coverage, not "are there any Tamil strings at all", and that distinction
  /// is the whole safeguard. Offering Tamil on a partial dictionary would
  /// recreate the bug this file exists to fix: a `த` label over
  /// mostly-English text, now with a handful of Tamil words scattered through
  /// it, which reads as broken rather than as pending.
  static bool get hasTamil => kTamilReady;

  /// The locales a person can actually choose right now.
  static List<Locale> get available => <Locale>[english, if (hasTamil) tamil];

  /// True when there is a real choice to offer — the app bar's language pill
  /// renders on this and nothing else.
  static bool get canChoose => available.length > 1;

  /// Clamps [locale] to something that has a dictionary.
  ///
  /// Matters for a real phone: someone who tapped the toggle while Tamil was
  /// a stub has `locale: ta` in SharedPreferences already. Without this they
  /// would come back to a `த`-labelled English app with no visible control to
  /// escape it, because the control is now hidden.
  static Locale resolve(Locale locale) =>
      available.any((l) => l.languageCode == locale.languageCode)
      ? locale
      : english;

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
    return SupportedLocales.resolve(stored);
  }

  /// Ignores a locale with no dictionary rather than half-applying it.
  Future<void> set(Locale locale) async {
    final target = SupportedLocales.resolve(locale);
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
