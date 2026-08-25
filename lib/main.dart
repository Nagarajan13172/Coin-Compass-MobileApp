import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/stale_ledger.dart';
import 'core/i18n/locale_controller.dart';
import 'core/i18n/translation_providers.dart';
import 'core/i18n/translated_text.dart';
import 'core/router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/lock/presentation/app_lock_gate.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/wealth_lock/presentation/wealth_lock_providers.dart';
import 'features/settings/domain/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both are cheap and required before the first frame: the cookie jar backs
  // session restore, prefs back theme + locale.
  final apiClient = await ApiClient.create();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CoinCompassApp(),
    ),
  );
}

class CoinCompassApp extends ConsumerStatefulWidget {
  const CoinCompassApp({super.key});

  @override
  ConsumerState<CoinCompassApp> createState() => _CoinCompassAppState();
}

class _CoinCompassAppState extends ConsumerState<CoinCompassApp> {
  @override
  void initState() {
    super.initState();
    // Validate the persisted mt_session cookie exactly once. AuthController
    // swallows 401s and network errors, so this can never block startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);
    // Phase 7.1 — reading this is what switches ML Kit on and off with the
    // locale, including a Tamil locale restored from prefs at launch.
    ref.watch(translationSyncProvider);
    final translator = ref.watch(translatorProvider);
    final auth = ref.watch(authControllerProvider);

    // ── Phase 6.3, kept alive from the root and nowhere else ────────────────
    //
    // `wealthCacheScopeProvider` pushes the Net Worth lock's visibility into
    // `ResponseCache.wealthScope`. Without a live subscription the cache sits
    // at its default `unknown` and refuses every wealth-sensitive body in both
    // directions — so forgetting this costs offline Net Worth, never a wrong
    // figure. It is watched here rather than in the shell because the shell
    // unmounts on sign-out, and the scope must be right before the first read
    // of the next session.
    //
    // `cacheEventBridgeProvider` connects the cache's hit/live events to the
    // stale ledger and the recovery counter.
    ref
      ..watch(wealthCacheScopeProvider)
      ..watch(cacheEventBridgeProvider);

    // The account's own `settings.theme`, adopted on a device that has never
    // made a local choice of its own — otherwise a signed-in user whose
    // account says "dark" would still get the system theme on a fresh
    // install, and the Settings screen's Light/Dark/System row would show a
    // state the server disagrees with. `adoptFromServer` no-ops the moment a
    // local choice exists, so this can never fight the user.
    //
    // Guarded on `isSignedIn` on purpose: `settingsProvider` is session-cached
    // with no autoDispose, so subscribing while signed out would park a 401 in
    // it that every later screen (currency symbol, week start) would then read
    // as its fallback. `ref.listen` re-subscribes on each build, so a
    // conditional listen is safe here — see ConsumerStatefulElement.build.
    if (auth.isSignedIn) {
      ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
        final serverTheme = next.valueOrNull?.theme;
        if (serverTheme != null) {
          ref
              .read(themeControllerProvider.notifier)
              .adoptFromServer(serverTheme);
        }
      });
    }

    final light = AppTheme.light();
    final dark = AppTheme.dark();

    // Keep the status bar icons legible against whichever theme is showing.
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && platformDark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark
            ? dark.scaffoldBackgroundColor
            : light.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    // Hold the splash until the session question is answered, otherwise the
    // router would briefly redirect a signed-in user to /login.
    if (!auth.isResolved) {
      return MaterialApp(
        title: 'CoinCompass',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: themeMode,
        // Same gate as below, so a locked cold start paints the lock instead of
        // the splash rather than flashing one and then the other.
        // TranslationScope sits INSIDE MaterialApp's builder, so it is below
      // Theme/Directionality but above every screen — which is what lets the
      // app's `Text` find it, and what makes one notifyListeners repaint only
      // the widgets currently showing text.
      builder: (context, child) => TranslationScope(
        translator: translator,
        child: AppLockGate(child: child),
      ),
        home: const SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'CoinCompass',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      // The app lock lives here and nowhere else. `builder` is inside
      // MaterialApp (so Theme, MediaQuery, Directionality and Localizations are
      // already ancestors) but *outside* the Router, and the `child` it hands
      // over is the un-mounted Router widget. On a locked cold start the gate
      // returns the lock alone and that child is never built, so no screen
      // mounts, no provider fires a GET and there is no frame of the owner's
      // net worth to leak. A go_router redirect or an Overlay could not make
      // that promise — both act a frame late, and a pushed route animates over
      // a visible dashboard. See AppLockGate for the full argument.
      // TranslationScope sits INSIDE MaterialApp's builder, so it is below
      // Theme/Directionality but above every screen — which is what lets the
      // app's `Text` find it, and what makes one notifyListeners repaint only
      // the widgets currently showing text.
      builder: (context, child) => TranslationScope(
        translator: translator,
        child: AppLockGate(child: child),
      ),
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: SupportedLocales.all,
      localizationsDelegates: L.localizationsDelegates,
    );
  }
}
