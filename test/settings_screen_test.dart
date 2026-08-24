import 'dart:convert';
import 'dart:io';

import 'package:coincompass/core/api/api_client.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/core/theme/theme_controller.dart';
import 'package:coincompass/core/widgets/loading_shimmer.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/auth/presentation/auth_providers.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/goals/data/goals_repository.dart';
import 'package:coincompass/features/loans/data/loans_repository.dart';
import 'package:coincompass/features/settings/data/settings_repository.dart';
import 'package:coincompass/features/settings/presentation/security_sheets.dart';
import 'package:coincompass/features/settings/presentation/settings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SettingsScreen] at 360 × 800dp.
///
/// Two jobs. The first is layout: this screen stacks a profile hero, a 2×2
/// count grid, a three-up theme picker, two text fields, a currency table and
/// three security rows into 320dp of usable width, so every one of them is laid
/// out at the width a phone really gives it and the frame is asserted
/// exception-free — including against a hostile payload where the wallet name,
/// the email and the currency names are all far too long.
///
/// The second is the write contract. The backend uses Zod and **silently
/// strips unknown keys**, so a stray key does not fail — it loses the user's
/// change. Every write this screen can make is therefore captured by the fake
/// adapter and its body asserted key-for-key against what recon recovered from
/// the deployed bundle.
///
/// Nothing here reaches the network: the transport is a fixture adapter. And
/// nothing here submits a lock or a logout — the PIN and passcode sheets are
/// opened and laid out but never sent, and the sign-out test stops at the
/// confirmation, because `POST /auth/logout` kills the session this project
/// depends on.
void main() {
  const Size phone = Size(360, 800);
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cc_settings');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Mounts the screen with every read already resolved.
  ///
  /// Warming happens inside [WidgetTester.runAsync] because the cookie-manager
  /// interceptor touches the disk, and real IO does not progress under the
  /// tester's fake clock. Pass `warm: false` to see the screen's own loading
  /// state instead.
  Future<_Harness> pump(
    WidgetTester tester, {
    Map<String, String> payloads = const {},
    bool warm = true,
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});

    late ProviderContainer container;
    final adapter = _Adapter(payloads);

    // Swallowed on purpose: several tests point an endpoint at a 500 and the
    // screen's own error state is what is under test. `catchError` cannot be
    // used — its handler has to return the future's own type.
    Future<Object?> settled(Future<Object?> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    await tester.runAsync(() async {
      final api = await ApiClient.create();
      api.dio.httpClientAdapter = adapter;
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      // Hold the autoDispose reads open for the life of the test, so the
      // screen finds them already resolved rather than refetching.
      for (final p in <ProviderListenable<Object?>>[
        settingsProvider,
        twoFactorStatusProvider,
        accountsProvider,
        categoriesProvider,
        goalsProvider,
        loansProvider,
      ]) {
        container.listen<Object?>(p, (a, b) {});
      }
      if (!warm) return;

      // Never throws — AuthController turns a 401 into "signed out".
      await container.read(authControllerProvider.notifier).restore();
      await Future.wait(<Future<Object?>>[
        for (final f in <Future<Object?>>[
          container.read(settingsProvider.future),
          container.read(twoFactorStatusProvider.future),
          container.read(accountsFetchProvider.future),
          container.read(categoriesFetchProvider.future),
          container.read(goalsFetchProvider.future),
          container.read(loansFetchProvider.future),
        ])
          settled(f),
      ]);

      // 6.4: the lists a screen watches are now composed `Provider`s over their
      // `<x>FetchProvider`. A composed provider whose dependency resolved is
      // *dirty*, not recomputed — Riverpod flushes it on the scheduler, which
      // does not run inside `runAsync`. Reading each one here flushes it before
      // the widget mounts, so the first build is not also the first flush.
      for (final p in <ProviderListenable<Object?>>[
        accountsProvider,
        categoriesProvider,
        goalsProvider,
        loansProvider,
      ]) {
        container.read<Object?>(p);
      }
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return _Harness(container, adapter);
  }

  /// The screen's own list — a bottom sheet's ListView is added later in the
  /// tree, so `firstWhere` still finds the page underneath it.
  ScrollableState verticalList(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((state) => state.position.axis == Axis.vertical);

  /// Slivers below the fold only lay out once scrolled into view, which is
  /// exactly where an overflow hides. Jump rather than drag: the currency rows
  /// and the theme tiles claim tap gestures across the viewport.
  Future<void> scrollThrough(WidgetTester tester) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 320) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      if (offset >= position.maxScrollExtent) break;
    }
    position.jumpTo(0);
    await tester.pump();
  }

  /// Brings [finder] fully into the viewport so it can be tapped or typed into.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final position = verticalList(tester).position;
    for (var offset = 0.0; ; offset += 100) {
      position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) {
        final rect = tester.getRect(finder.first);
        if (rect.top > 30 && rect.bottom < 740) return;
      }
      if (offset >= position.maxScrollExtent) {
        fail('could not bring $finder into view');
      }
    }
  }

  /// Lets the real async a tap kicked off run to completion, then rebuilds.
  ///
  /// It takes several rounds: the write itself needs real IO (Dio plus the
  /// on-disk cookie jar, neither of which progresses under the fake clock), and
  /// the `ref.invalidate` that follows it kicks off a *second* request on the
  /// next frame, whose Dio timer would still be pending when the test ends.
  ///
  /// Never `pumpAndSettle`: the busy states on this screen are indeterminate
  /// `CircularProgressIndicator`s and the loading state is a repeating shimmer,
  /// so settling would never return.
  Future<void> drain(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Asserts the SnackBar [text] is up, then lets its four-second dismissal
  /// timer expire — a live SnackBar timer at teardown fails the test with
  /// "A Timer is still pending".
  Future<void> expectSnackBar(WidgetTester tester, String text) async {
    expect(find.text(text), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> revealAndTap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder.first);
    await drain(tester);
  }

  /// A `ListView` disposes what scrolls off, so an assertion made after
  /// `scrollThrough` has returned to the top would look for a widget that no
  /// longer exists. Bring it back first.
  Future<void> expectVisible(WidgetTester tester, String text) async {
    await reveal(tester, find.text(text));
    expect(find.text(text), findsOneWidget, reason: 'missing "$text"');
  }

  // ── loaded ───────────────────────────────────────────────────────────────

  testWidgets('renders the recorded account end to end', (tester) async {
    await pump(tester);

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Preferences & data'), findsOneWidget);

    // Profile, straight off /auth/me.
    expect(find.text('Hari'), findsOneWidget);
    expect(find.text('haridiablo72@gmail.com'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(
      find.text('Email & password · Member since July 2026'),
      findsOneWidget,
    );

    // The owner's real counts: 0 accounts, 33 categories, 0 goals, 1 loan.
    // "0" has to mean zero here, not "still loading".
    expect(find.text('33'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));

    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    for (final text in const [
      'Appearance',
      'Wallet',
      'Currency',
      'INR — Indian Rupee',
      'Base currency',
      '1 USD = ₹83',
      'Email reports',
      'Security',
      'Sign out',
      'App info',
      'INR · en-IN',
    ]) {
      await expectVisible(tester, text);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('security reflects both locks off and 2FA off', (tester) async {
    await pump(tester);
    await reveal(tester, find.text('Security'));

    expect(find.text('App lock (this phone)'), findsOneWidget);
    expect(find.text('PIN lock (web)'), findsOneWidget);
    expect(find.text('Net Worth lock'), findsOneWidget);
    expect(find.text('Two-factor authentication'), findsOneWidget);
    // Four rows now: the app lock joined the two web locks and 2FA. The app
    // lock defaults OFF and nothing the server says can change that.
    expect(find.text('Off'), findsNWidgets(4));
    expect(find.text('Set up app lock'), findsOneWidget);
    expect(find.text('Set a PIN'), findsOneWidget);
    expect(find.text('Set a passcode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('security reflects both locks on', (tester) async {
    await pump(
      tester,
      payloads: {
        '/settings': _settingsWith(pin: true, wealth: true),
        '/auth/2fa/status':
            '{"enabled":true,"emailFallback":true,"backupCodesRemaining":1}',
      },
    );
    await reveal(tester, find.text('Security'));

    // Two "On" pills, not three: since 6.2 the Net Worth row reports
    // Locked / Unlocked / Off rather than On / Off, because "on" cannot say
    // whether the figures are showing right now.
    expect(find.text('On'), findsNWidgets(2));
    expect(find.text('Unlocked'), findsOneWidget);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Turn off'), findsNWidgets(2));
    // Singular, because there is exactly one code left.
    expect(find.textContaining('1 backup code left'), findsOneWidget);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  // ── loading / error / empty ──────────────────────────────────────────────

  testWidgets('loading shows skeletons, not a blank screen', (tester) async {
    // No warm-up: the reads stay in flight because real IO cannot progress
    // under the fake clock, which is exactly the first-frame state.
    await pump(tester, warm: false);

    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(LoadingCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a settings failure offers a retry and keeps the escape hatches',
    (tester) async {
      await pump(tester, payloads: {'/settings': _boom});

      expect(find.text('Retry'), findsOneWidget);
      // The profile, the theme picker and Sign out do not depend on /settings —
      // losing them would strand the user on a screen with no way out.
      expect(find.text('Hari'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      await expectVisible(tester, 'Sign out');
      // App info degrades to an em dash rather than inventing a region.
      await expectVisible(tester, 'App info');
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty currency table renders its own empty state', (
    tester,
  ) async {
    await pump(tester, payloads: {'/settings': _settingsNoCurrencies});
    await reveal(tester, find.text('Currency'));

    expect(find.text('No currencies'), findsOneWidget);
    expect(find.text('Base currency'), findsNothing);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 2FA failure degrades to Unknown with a retry', (tester) async {
    await pump(tester, payloads: {'/auth/2fa/status': _boom});
    await reveal(tester, find.text('Two-factor authentication'));

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text("Couldn't check the status just now."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session that 401s renders the signed-out card, not a crash', (
    tester,
  ) async {
    await pump(tester, payloads: {'/auth/me': _unauthorized});

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    // The rest of the screen still works — /settings answered fine.
    expect(find.text('Wallet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── layout ───────────────────────────────────────────────────────────────

  testWidgets('lays out at 360dp against a hostile payload', (tester) async {
    await pump(
      tester,
      payloads: {'/settings': _hostileSettings, '/auth/me': _hostileUser},
    );

    await scrollThrough(tester);
    expect(tester.takeException(), isNull);

    // The long strings must still be there in full, not silently trimmed — an
    // ellipsized email or build string is worse than two lines of text.
    await expectVisible(
      tester,
      'archibald.fitzwilliam.mountbatten@verylongdomainname.example',
    );
    await expectVisible(tester, 'Local build · Single user');
    // A Google account with an unverified address, in wealth-view mode.
    await expectVisible(tester, 'Unverified');
    await expectVisible(tester, 'Wealth view');
    expect(find.textContaining('Google account'), findsOneWidget);
  });

  testWidgets('lays out in dark mode', (tester) async {
    await pump(tester, dark: true, payloads: {'/settings': _hostileSettings});
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  // ── write contracts ──────────────────────────────────────────────────────
  //
  // The whole point of this block: the backend strips unknown keys silently,
  // so each body is asserted key-for-key, not just "a request happened".

  testWidgets('theme picker sends exactly {theme} and drives ThemeMode', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('Dark'));

    expect(harness.container.read(themeControllerProvider), ThemeMode.dark);
    expect(harness.adapter.writes, hasLength(1));
    final write = harness.adapter.writes.single;
    expect(write.method, 'PUT');
    expect(write.path, '/settings');
    expect(write.body, {'theme': 'dark'});
  });

  testWidgets('wallet Save sends exactly {name, description}', (tester) async {
    final harness = await pump(tester);

    final nameField = find.byType(TextField).first;
    await reveal(tester, nameField);
    await tester.enterText(nameField, '  Household  ');
    await tester.pump();

    await revealAndTap(tester, find.text('Save changes'));

    expect(harness.adapter.writes, hasLength(1));
    final write = harness.adapter.writes.single;
    expect(write.method, 'PUT');
    expect(write.path, '/settings');
    // Trimmed, both keys, and nothing else — no locale, no firstDayOfWeek, no
    // currencies, no whole-object write.
    expect(write.body, {'name': 'Household', 'description': ''});
    await expectSnackBar(tester, 'Wallet updated');
  });

  testWidgets('Save is inert while pristine and refuses a blank name', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('Save changes'));
    expect(harness.adapter.writes, isEmpty);

    // Clearing the name leaves the form dirty but invalid; the web toasts and
    // sends nothing, and so does this.
    final nameField = find.byType(TextField).first;
    await reveal(tester, nameField);
    await tester.enterText(nameField, '   ');
    await tester.pump();
    await revealAndTap(tester, find.text('Save changes'));
    expect(harness.adapter.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a currency sends exactly {baseCurrency}', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('USD — US Dollar'));

    expect(harness.adapter.writes, hasLength(1));
    expect(harness.adapter.writes.single.method, 'PUT');
    expect(harness.adapter.writes.single.body, {'baseCurrency': 'USD'});
    await expectSnackBar(tester, 'Base currency updated');
  });

  testWidgets('the current base currency is not tappable', (tester) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('INR — Indian Rupee'));

    expect(harness.adapter.writes, isEmpty);
  });

  testWidgets('the email-reports switch sends exactly {emailReports}', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.byType(Switch));

    expect(harness.adapter.writes, hasLength(1));
    expect(harness.adapter.writes.single.method, 'PUT');
    expect(harness.adapter.writes.single.body, {'emailReports': false});
  });

  testWidgets('a failed write surfaces the server message and keeps the row', (
    tester,
  ) async {
    final harness = await pump(tester, payloads: {'PUT /settings': _boom});

    await revealAndTap(tester, find.text('USD — US Dollar'));

    expect(harness.adapter.writes, hasLength(1));
    // Still INR — the failed write did not fake a success.
    expect(find.text('Base currency'), findsOneWidget);
    await expectSnackBar(tester, 'Server error');
    expect(tester.takeException(), isNull);
  });

  // ── the sheets and the never-call endpoints ──────────────────────────────

  testWidgets('the PIN sheet opens and lays out, and is never submitted', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('Set a PIN'));

    expect(find.byType(PinSheet), findsOneWidget);
    expect(find.text('New PIN'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(PinSheet),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));

    // Client-side validation runs before anything can leave the device.
    await tester.enterText(fields.first, '12');
    await tester.pump();
    await tester.tap(find.text('Turn on PIN lock'));
    await drain(tester);
    expect(find.text('The PIN must be 4 to 8 digits.'), findsOneWidget);
    expect(harness.adapter.writes, isEmpty);

    // A valid but mismatched pair is refused too. `POST /settings/pin` arms a
    // lock screen on the owner's real device, so no test may ever send it.
    await tester.enterText(fields.first, '1234');
    await tester.enterText(fields.at(1), '4321');
    await tester.pump();
    await tester.tap(find.text('Turn on PIN lock'));
    await drain(tester);
    expect(find.text("The two PINs don't match."), findsOneWidget);
    expect(harness.adapter.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the PIN sheet keeps out anything that is not a digit', (
    tester,
  ) async {
    await pump(tester);
    await revealAndTap(tester, find.text('Set a PIN'));

    final field = find
        .descendant(of: find.byType(PinSheet), matching: find.byType(TextField))
        .first;
    await tester.enterText(field, '12ab34!!5678999');
    await tester.pump();

    // Digits only, clamped to the API's 8-character ceiling.
    expect(tester.widget<TextField>(field).controller!.text, '12345678');
  });

  testWidgets('the wealth passcode sheet opens and lays out', (tester) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('Set a passcode'));

    expect(find.byType(WealthPasscodeSheet), findsOneWidget);
    expect(find.text('Wealth passcode'), findsOneWidget);
    expect(find.text('Confirm passcode'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(WealthPasscodeSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, 'abc');
    await tester.pump();
    await tester.tap(find.text('Lock Net Worth'));
    await drain(tester);

    expect(
      find.text('The passcode must be 4 to 32 characters.'),
      findsOneWidget,
    );
    expect(harness.adapter.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning a lock off asks first, and cancelling sends nothing', (
    tester,
  ) async {
    final harness = await pump(
      tester,
      payloads: {'/settings': _settingsWith(pin: true, wealth: true)},
    );

    await revealAndTap(tester, find.text('Turn off').first);

    // "web PIN", not "PIN lock": this row is the SERVER PIN, and the sheet used
    // to promise "the app will open without asking for a PIN" — false whenever
    // the app lock on this phone is on. The two locks are named apart now.
    expect(find.text('Turn off the web PIN?'), findsOneWidget);
    expect(
      find.textContaining('app lock on this phone is separate'),
      findsOneWidget,
      reason: 'the sheet must say what it does NOT turn off',
    );
    await tester.tap(find.text('Cancel'));
    await drain(tester);

    expect(harness.adapter.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sign out asks first, and cancelling sends nothing', (
    tester,
  ) async {
    final harness = await pump(tester);

    await revealAndTap(tester, find.text('Sign out'));

    expect(find.text('Sign out?'), findsOneWidget);
    expect(
      find.text("You'll need your email and password to get back in."),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await drain(tester);

    // `POST /auth/logout` kills the session the whole project depends on, so
    // the confirm path is deliberately never exercised here.
    expect(harness.adapter.writes, isEmpty);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// ─── harness ────────────────────────────────────────────────────────────────

class _Harness {
  const _Harness(this.container, this.adapter);
  final ProviderContainer container;
  final _Adapter adapter;
}

class _Write {
  const _Write(this.method, this.path, this.body);
  final String method;
  final String path;
  final Object? body;
}

/// Replays a fixture per GET path and **records** every non-GET instead of
/// letting one out, so a test can assert the exact body the screen built.
///
/// An override keyed `'<METHOD> <path>'` (e.g. `'PUT /settings'`) makes that
/// write fail; an override keyed by path alone replaces the GET body. An
/// unmapped GET answers 404, so a screen that starts reading something new
/// shows up as an error state rather than silently passing.
class _Adapter implements HttpClientAdapter {
  _Adapter(this._overrides);

  final Map<String, String> _overrides;
  final List<_Write> writes = [];

  static const Map<String, String> _fixtures = {
    '/settings': 'settings',
    '/auth/me': 'auth_me',
    '/auth/2fa/status': 'auth_2fa_status',
    '/accounts': 'accounts',
    '/categories': 'categories',
    '/goals': 'goals',
    '/loans': 'loans',
  };

  static ResponseBody _json(String body, int status) => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api', '');

    if (options.method != 'GET') {
      final data = options.data;
      writes.add(
        _Write(options.method, path, data is String ? jsonDecode(data) : data),
      );
      if (_overrides['${options.method} $path'] == _boom) {
        return _json('{"error":"Server error"}', 500);
      }
      // Every write this screen makes answers with the settings document.
      return _json(File('test/fixtures/settings.json').readAsStringSync(), 200);
    }

    final override = _overrides[path];
    if (override == _boom) return _json('{"error":"Server error"}', 500);
    if (override == _unauthorized) {
      return _json('{"error":"Unauthorized"}', 401);
    }

    final fixture = _fixtures[path];
    final body =
        override ??
        (fixture == null
            ? null
            : File('test/fixtures/$fixture.json').readAsStringSync());
    return _json(
      body ?? '{"error":"no fixture for $path"}',
      body == null ? 404 : 200,
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _boom = '__boom__';
const String _unauthorized = '__401__';

/// The recorded settings document with the two lock flags flipped. Editing the
/// values in place rather than prepending duplicate keys, because `jsonDecode`
/// keeps the *last* occurrence of a duplicated key.
String _settingsWith({bool pin = false, bool wealth = false}) =>
    File('test/fixtures/settings.json')
        .readAsStringSync()
        .replaceAll('"pinEnabled":false', '"pinEnabled":$pin')
        .replaceAll('"wealthLockEnabled":false', '"wealthLockEnabled":$wealth');

const String _settingsNoCurrencies =
    '{"_id":"s1","user":"u1","name":"My Wallet","description":"",'
    '"baseCurrency":"INR","theme":"system","locale":"en-IN","language":"en",'
    '"firstDayOfWeek":1,"monthStartDay":1,"pinEnabled":false,'
    '"emailReports":true,"wealthLockEnabled":false,"currencies":[]}';

/// Long everywhere it hurts: a wallet name at the 60-character limit, a label
/// at 120, a currency name that dwarfs its row, and a rate wide enough to fight
/// that name for the same line.
const String _hostileSettings =
    '{"_id":"s1","user":"u1",'
    '"name":"Household, savings and everything else — the joint wallet",'
    '"description":"Shared between Anna Nagar West and the Bengaluru flat, '
    'reconciled every Sunday evening without fail",'
    '"baseCurrency":"INR","theme":"dark","locale":"en-IN","language":"en",'
    '"firstDayOfWeek":1,"monthStartDay":1,"pinEnabled":true,'
    '"emailReports":true,"wealthLockEnabled":true,"currencies":['
    '{"code":"INR","symbol":"₹","name":"Indian Rupee","rateToBase":1},'
    '{"code":"VND","symbol":"₫",'
    '"name":"Socialist Republic of Viet Nam Dong (post-redenomination)",'
    '"rateToBase":123456789.75}]}';

const String _hostileUser =
    '{"user":{"id":"u1",'
    '"email":"archibald.fitzwilliam.mountbatten@verylongdomainname.example",'
    '"name":"Archibald Fitzwilliam Mountbatten-Chandrasekharan",'
    '"avatarUrl":"","emailVerified":false,'
    '"createdAt":"2026-07-02T13:39:04.074Z","hasPassword":false,'
    '"twoFactorEnabled":true,"mode":"superadmin","wealthLockEnabled":true}}';
