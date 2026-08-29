import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/core/theme/app_theme.dart';
import 'package:coincompass/features/accounts/data/accounts_repository.dart';
import 'package:coincompass/features/accounts/domain/account.dart';
import 'package:coincompass/features/categories/data/categories_repository.dart';
import 'package:coincompass/features/categories/domain/category.dart';
import 'package:coincompass/features/transactions/presentation/transaction_form_sheet.dart';
import 'package:coincompass/features/upi/data/upi_service.dart';
import 'package:coincompass/features/upi/domain/upi_qr.dart';
import 'package:coincompass/features/upi/domain/upi_request.dart';
import 'package:coincompass/features/upi/domain/upi_result.dart';
import 'package:coincompass/features/upi/presentation/scan_pay_flow.dart';
import 'package:coincompass/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7.8 — the two steps either side of the payment.
///
/// The scan itself needs a camera and cannot be exercised here, so what is
/// pinned is everything the camera hands on to: the amount step that stands
/// between reading a code and paying it, the note that ties a ledger row back
/// to the payment, and the transaction form arriving already filled in.
///
/// The last one is the point of the feature. A payment that leaves no row
/// behind is a payment the owner has to remember and retype, which is exactly
/// what scanning was meant to remove.
void main() {
  UpiQrPayload scan(String raw) => UpiQr.parse(raw).payload!;

  const counterQr = 'upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&mc=5812';
  const billQr =
      'upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&am=250.00&cu=INR'
      '&mc=5812&tn=Table%204';

  group('the note ties the row to the payment', () {
    test('the shop note and the UPI reference, in that order', () {
      expect(
        upiNote(
          payload: scan(billQr),
          result: const UpiResult(
            status: UpiStatus.success,
            transactionId: 'AXI9912',
          ),
        ),
        'Table 4 · UPI AXI9912',
      );
    });

    test('either half can be missing', () {
      expect(
        upiNote(payload: scan(counterQr), result: null),
        isNull,
        reason: 'nothing to say, so nothing is invented',
      );
      expect(upiNote(payload: scan(billQr), result: null), 'Table 4');
      expect(
        upiNote(
          payload: scan(counterQr),
          result: const UpiResult(
            status: UpiStatus.success,
            transactionId: 'AXI9912',
          ),
        ),
        'UPI AXI9912',
      );
    });

    test('a result that reported no id leaves only the shop note', () {
      // The common case for the payee-only rung: the app comes back with
      // nothing at all, and the owner is the one who said it went through.
      expect(
        upiNote(
          payload: scan(billQr),
          result: const UpiResult(status: UpiStatus.unknown),
        ),
        'Table 4',
      );
    });

    test('it never says the word paid', () {
      // UpiResult is advisory. The note is not the place to assert what the
      // rest of the app is careful not to.
      final note = upiNote(
        payload: scan(billQr),
        result: const UpiResult(
          status: UpiStatus.success,
          transactionId: 'AXI9912',
        ),
      )!;
      expect(note.toLowerCase(), isNot(contains('paid')));
    });
  });

  group('the amount step', () {
    Future<num?> ask(WidgetTester tester, UpiQrPayload payload) async {
      num? answer;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L.localizationsDelegates,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  answer = await UpiAmountSheet.show(context, payload: payload);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(closed, isFalse, reason: 'the sheet is up');
      return answer;
    }

    testWidgets('a counter code with no amount asks for one', (tester) async {
      await ask(tester, scan(counterQr));

      expect(find.text('How much?'), findsOneWidget);
      expect(find.textContaining('sets no amount'), findsOneWidget);
      // And it shows who is about to be paid — name AND the VPA under it,
      // which is the last screen the standard sticker-over-the-QR fraud can
      // be spotted on.
      expect(find.text('Chai Kada'), findsOneWidget);
      expect(find.text('chaikada@okhdfcbank'), findsOneWidget);
    });

    testWidgets("a bill code prefills its own figure, and says it's the code's", (
      tester,
    ) async {
      await ask(tester, scan(billQr));

      expect(find.widgetWithText(TextField, '250'), findsOneWidget);
      expect(find.textContaining('The code asks for'), findsOneWidget);
    });

    testWidgets('the prefilled figure can be overridden', (tester) async {
      // A static code at a till is printed once and the bill changes daily.
      await ask(tester, scan(billQr));
      await tester.enterText(find.byType(TextField), '310.50');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('How much?'), findsNothing, reason: 'sheet closed');
    });

    testWidgets('zero is refused, and says why', (tester) async {
      await ask(tester, scan(counterQr));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('above zero'), findsOneWidget);
      expect(find.text('How much?'), findsOneWidget, reason: 'still open');
    });

    testWidgets('an amount UPI cannot carry is caught before an app opens', (
      tester,
    ) async {
      await ask(tester, scan(counterQr));
      await tester.enterText(find.byType(TextField), '200000');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1,00,000'), findsOneWidget);
      expect(find.text('How much?'), findsOneWidget);
    });
  });

  group('the row the payment leaves behind', () {
    /// The transaction form with its pickers fed from memory — nothing here
    /// reaches the API.
    Future<void> pumpForm(
      WidgetTester tester, {
      required num amount,
      required String payee,
      required String? note,
      UpiQrPayload? scanned,
    }) async {
      final container = ProviderContainer(
        overrides: [
          accountsFetchProvider.overrideWith((ref) async => const <Account>[]),
          categoriesFetchProvider.overrideWith(
            (ref) async => const <Category>[],
          ),
          upiServiceProvider.overrideWithValue(_UnsupportedUpi()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            theme: AppTheme.light(),
            home: Scaffold(
              body: TransactionFormSheet(
                initialType: TransactionType.expense,
                initialAmount: amount,
                initialPayee: payee,
                initialNote: note,
                initialScanned: scanned,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the amount, payee and note the payment produced', (
      tester,
    ) async {
      await pumpForm(
        tester,
        amount: 250,
        payee: 'Chai Kada',
        note: 'Table 4 · UPI AXI9912',
        scanned: scan(billQr),
      );

      expect(find.widgetWithText(TextField, '250'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Chai Kada'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Table 4 · UPI AXI9912'),
        findsOneWidget,
      );
    });

    testWidgets('it is an expense, and it is not saved yet', (tester) async {
      await pumpForm(
        tester,
        amount: 250,
        payee: 'Chai Kada',
        note: null,
        scanned: scan(billQr),
      );

      // An account is required by the API and a category is worth choosing, so
      // the owner still presses Save — which is also the only confirmation
      // this app is entitled to that the payment happened at all.
      expect(find.text('Add transaction'), findsWidgets);
      expect(find.text('Choose an account'), findsNothing, reason: 'not yet submitted');
    });

    testWidgets('a paise figure survives the round trip', (tester) async {
      await pumpForm(
        tester,
        amount: 310.5,
        payee: 'Chai Kada',
        note: null,
      );
      expect(find.widgetWithText(TextField, '310.5'), findsOneWidget);
    });
  });
}

/// A platform with no UPI, so the form's payment section stays out of the way
/// of the fields under test.
class _UnsupportedUpi implements UpiService {
  const _UnsupportedUpi();

  @override
  bool get isSupported => false;

  @override
  Future<List<UpiApp>> installedApps() async => const [];

  @override
  Future<UpiResult> pay({
    required UpiApp app,
    required UpiRequest request,
    UpiHandover handover = UpiHandover.prefilled,
  }) async => throw StateError('no payment can be made on this platform');

  @override
  Future<void> openApp(UpiApp app) async =>
      throw StateError('no payment app on this platform');
}
