import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';
import 'en.dart';
import 'ta.dart';

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
/// So availability is derived from the data instead of asserted by a flag:
/// [hasTamil] is "Tamil covers every English key" ([tamilGaps] is empty).
/// Finish `ta.dart` and the toggle reappears on the next build; let a key slip
/// and it goes away again. There is no separate switch anyone can forget to
/// flip, in either direction — and because 7.1b keeps *adding* English keys,
/// the bar rises with the work rather than being passed once and forgotten.
class SupportedLocales {
  const SupportedLocales._();

  static const Locale english = Locale('en');
  static const Locale tamil = Locale('ta');

  /// Every locale the app knows how to *name* — what `MaterialApp` advertises.
  static const List<Locale> all = [english, tamil];

  /// English keys with no usable Tamil string — the work 7.1 has left.
  ///
  /// A blank counts as a gap, not a translation: an empty string renders as
  /// English via `Strings.t`'s fallback, so treating it as "done" would let the
  /// toggle go live over English text.
  static List<String> get tamilGaps => <String>[
    for (final key in enStrings.keys)
      if ((taStrings[key] ?? '').isEmpty) key,
  ];

  /// True once Tamil covers **every** English key.
  ///
  /// Coverage, not "is it non-empty" — and that distinction is the whole
  /// safeguard. Offering Tamil on a partial dictionary would recreate exactly
  /// the bug this file exists to fix: a `த` label over mostly-English text,
  /// only now with a handful of Tamil words scattered through it, which reads
  /// as broken rather than as pending.
  ///
  /// It is also self-correcting in the direction that matters. Phase 7.1b will
  /// add hundreds of keys to `en.dart` as it extracts hardcoded strings; each
  /// one re-opens a gap until Tamil catches up, so the toggle cannot go live
  /// half-way through by accident.
  ///
  /// Computed once — both maps are `const`, so the answer cannot change within
  /// a run, and this is read on every app-bar build.
  static bool get hasTamil =>
      _hasTamil ??= enStrings.isNotEmpty && tamilGaps.isEmpty;
  static bool? _hasTamil;

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
