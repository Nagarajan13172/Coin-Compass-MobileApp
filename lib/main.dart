import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/i18n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/auth_providers.dart';

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
    final auth = ref.watch(authControllerProvider);

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
        home: const SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'CoinCompass',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: SupportedLocales.all,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
