import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/upi/data/upi_service.dart';
import 'package:coincompass/features/upi/domain/upi_qr.dart';
import 'package:coincompass/features/upi/domain/upi_request.dart';
import 'package:coincompass/features/upi/domain/upi_result.dart';
import 'package:coincompass/features/upi/presentation/upi_pay_sheet.dart';
import 'package:coincompass/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 7.8 — **the amount goes with the payment**, and what happens when a
/// PSP will not take it.
///
/// 7.7 gave up on the pre-filled amount after the bank declined every attempt,
/// and left the app opening a payment screen with an empty amount box. That
/// traded away the whole point of scanning: whether a particular PSP honours a
/// pre-filled intent is *that PSP's policy*, and it is not a reason to stop
/// asking every one of them.
///
/// So the sheet asks first and falls back second, and these tests pin both
/// halves — that the first attempt really does carry `am`, and that a refusal
/// is met with the next rung rather than a dead end.
///
/// Nothing here touches a method channel: [FakeUpiService] records what it was
/// handed and answers with whatever the test scripted.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A Google Pay personal QR — no amount of its own, so the sheet supplies it.
  const personalQr =
      'upi://pay?pa=prithivi2804raj@okicici&pn=Prithiviraj%20B&cu=INR'
      '&mc=0000&mode=02&purpose=00&orgid=159761&sign=MEUCIQDxyz789';

  UpiQrPayload scan(String raw) => UpiQr.parse(raw).payload!;

  /// Pumps the sheet already open, and hands back the fake it is talking to.
  Future<FakeUpiService> open(
    WidgetTester tester, {
    required List<UpiResult> script,
    UpiQrPayload? scanned,
    num amount = 250,
    String payeeName = 'Prithiviraj B',
    // Distinguishes a second sheet in the same test from the first. Without
    // it Flutter reuses the element — and with it the sheet's State, which
    // would still be showing the previous payment's outcome.
    String slot = 'a',
  }) async {
    final service = FakeUpiService(script);
    final container = ProviderContainer(
      overrides: [upiServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: Scaffold(
            body: UpiPaySheet(
              key: ValueKey(slot),
              amount: amount,
              payeeName: payeeName,
              scanned: scanned,
            ),
          ),
        ),
      ),
    );
    // Lets the payee lookup settle — the chooser stays disabled until it has.
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> tapApp(WidgetTester tester) async {
    await tester.tap(find.text('Google Pay'));
    await tester.pumpAndSettle();
  }

  group('the first attempt carries the amount', () {
    testWidgets('a scanned QR is paid pre-filled, not payee-only', (
      tester,
    ) async {
      final service = await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.success)],
      );
      await tapApp(tester);

      expect(service.attempts, hasLength(1));
      expect(service.attempts.single.handover, UpiHandover.prefilled);

      // The link itself, not just the enum: this is the field 7.7 removed.
      final sent = service.attempts.single.uri.queryParameters;
      expect(sent['am'], '250.00');
      expect(sent['pa'], 'prithivi2804raj@okicici');
      // P2P, so no merchant reference — mc=0000 says this is not a merchant.
      expect(sent.containsKey('tr'), isFalse);
    });

    testWidgets('the chooser says the amount will be in it', (tester) async {
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.success)],
      );
      expect(find.textContaining('already in it'), findsOneWidget);
    });

    testWidgets('the VPA is on screen before anything is tapped', (
      tester,
    ) async {
      // A typo does not fail, it pays someone else, and the VPA is the only
      // field money follows. It is the whole reason this sheet exists.
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.success)],
      );
      expect(find.text('prithivi2804raj@okicici'), findsOneWidget);
    });
  });

  group('a refusal drops one rung instead of stopping', () {
    testWidgets('a reported failure offers the payee-only retry', (
      tester,
    ) async {
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.failure)],
      );
      await tapApp(tester);

      expect(find.text('The payment did not go through'), findsOneWidget);
      expect(
        find.textContaining('I will type the amount there'),
        findsOneWidget,
      );
    });

    testWidgets('taking the retry sends the same payee with no amount', (
      tester,
    ) async {
      final service = await open(
        tester,
        scanned: scan(personalQr),
        script: [
          const UpiResult(status: UpiStatus.failure),
          const UpiResult(status: UpiStatus.success),
        ],
      );
      await tapApp(tester);
      await tester.tap(find.textContaining('I will type the amount there'));
      await tester.pumpAndSettle();

      expect(service.attempts, hasLength(2));
      expect(service.attempts.last.handover, UpiHandover.payeeOnly);

      final sent = service.attempts.last.uri.queryParameters;
      expect(sent.containsKey('am'), isFalse, reason: 'the point of the rung');
      expect(sent['pa'], 'prithivi2804raj@okicici');
    });

    testWidgets('a success is never offered a retry — that is a second payment', (
      tester,
    ) async {
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.success)],
      );
      await tapApp(tester);

      expect(find.text('The app reported success'), findsOneWidget);
      expect(find.textContaining('I will type the amount'), findsNothing);
    });

    testWidgets('pending is not offered a retry either', (tester) async {
      // The money has probably left. Sending it again would be the one mistake
      // this feature cannot recover from.
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.pending)],
      );
      await tapApp(tester);

      expect(find.textContaining('I will type the amount'), findsNothing);
    });
  });

  group('silence is a question, never an answer', () {
    testWidgets('an app that returns nothing is asked about, not assumed', (
      tester,
    ) async {
      await open(
        tester,
        scanned: scan(personalQr),
        // What a back press produces, and what several apps produce after a
        // perfectly successful payment.
        script: [UpiResult.parse(null)],
      );
      await tapApp(tester);

      expect(find.textContaining('Did you pay in'), findsOneWidget);
      expect(find.textContaining('Yes — record'), findsOneWidget);
      // And the rung below is offered here too, because "nothing came back"
      // is the shape a refused link most often takes.
      expect(
        find.textContaining('I will type the amount there'),
        findsOneWidget,
      );
    });

    testWidgets('an unreadable status is asked about too', (tester) async {
      await open(
        tester,
        scanned: scan(personalQr),
        script: [UpiResult.parse('Status=WHO_KNOWS&txnId=X1')],
      );
      await tapApp(tester);
      expect(find.textContaining('Did you pay in'), findsOneWidget);
    });
  });

  group('with no payee at all', () {
    testWidgets('nothing was scanned, so the app is only opened', (
      tester,
    ) async {
      final service = await open(tester, script: const []);
      await tapApp(tester);

      expect(service.attempts, isEmpty, reason: 'no VPA to build a link from');
      expect(service.opened, ['com.google.android.apps.nbu.paisa.user']);
      expect(find.textContaining('Did you pay in'), findsOneWidget);
    });

    testWidgets('the chooser does not promise a pre-filled amount', (
      tester,
    ) async {
      await open(tester, script: const []);
      expect(find.textContaining('already in it'), findsNothing);
      expect(find.textContaining('Opens the app so you can pay there'), findsOneWidget);
    });

    testWidgets('and it is not offered "just open the app" as a remedy', (
      tester,
    ) async {
      // It already did that. There is no rung below the bottom one, and
      // offering the action just taken as the fix for it having not worked is
      // the shape of a dead end.
      await open(tester, script: const []);
      await tapApp(tester);

      expect(find.textContaining('Just open the app'), findsNothing);
      expect(find.textContaining('I will type the amount'), findsNothing);
    });
  });

  group('the payee book', () {
    testWidgets('a scanned payee is remembered, and pays pre-filled next time', (
      tester,
    ) async {
      // First payment: scanned.
      await open(
        tester,
        scanned: scan(personalQr),
        script: [const UpiResult(status: UpiStatus.success)],
      );
      await tapApp(tester);

      // Second payment to the same payee name, with nothing scanned.
      final service = await open(
        tester,
        slot: 'b',
        amount: 40,
        script: [const UpiResult(status: UpiStatus.success)],
      );
      await tapApp(tester);

      expect(service.attempts, hasLength(1));
      final sent = service.attempts.single.uri.queryParameters;
      expect(sent['pa'], 'prithivi2804raj@okicici');
      expect(sent['am'], '40.00');
    });
  });
}

/// One launch, as the fake saw it.
typedef UpiAttempt = ({UpiApp app, Uri uri, UpiHandover handover});

/// A payment app that never exists. Answers from [script] in order, and keeps
/// the **built link** rather than the request, so a test can assert on what a
/// payment app would actually receive.
class FakeUpiService implements UpiService {
  FakeUpiService(this._script);

  final List<UpiResult> _script;
  var _next = 0;

  final List<UpiAttempt> attempts = [];
  final List<String> opened = [];

  @override
  bool get isSupported => true;

  @override
  Future<List<UpiApp>> installedApps() async => const [
    UpiApp(
      packageName: 'com.google.android.apps.nbu.paisa.user',
      label: 'Google Pay',
    ),
  ];

  @override
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
    UpiHandover handover = UpiHandover.prefilled,
  }) async {
    final uri = switch (handover) {
      UpiHandover.prefilled => request.toUri(),
      UpiHandover.payeeOnly || UpiHandover.appOnly => request.payeeOnlyUri(),
    };
    attempts.add((app: app, uri: uri, handover: handover));
    return _next < _script.length
        ? _script[_next++]
        : const UpiResult(status: UpiStatus.cancelled);
  }

  @override
  Future<void> openApp(UpiApp app) async => opened.add(app.packageName);
}
