import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected in main() so controllers can read/write prefs synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider was not overridden'),
);

/// Mirrors the backend's `settings.theme` values: light | dark | system.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_read(_prefs));

  static const String _key = 'themeMode';
  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String toApi(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_key, toApi(mode));
  }

  /// Applies the value coming back from `GET /settings` without clobbering a
  /// choice the user just made locally.
  Future<void> adoptFromServer(String? value) async {
    if (_prefs.containsKey(_key)) return;
    final mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    state = mode;
  }

  Future<void> toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
      return ThemeController(ref.watch(sharedPreferencesProvider));
    });
