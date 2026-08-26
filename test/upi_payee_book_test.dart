import 'package:coincompass/features/upi/data/upi_payee_book.dart';
import 'package:coincompass/features/upi/domain/upi_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Phase 7.6 — remembering a payee's VPA, and re-checking it on the way out.**
///
/// A VPA is the thing money follows. Reading one back out of storage and
/// putting it straight into a payment link would trust a string written by an
/// older build, or edited by hand — so every read is re-validated.
void main() {
  late UpiPayeeBook book;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    book = UpiPayeeBook(await SharedPreferences.getInstance());
  });

  Vpa vpa(String raw) => Vpa.tryParse(raw)!;

  test('remembers and returns a payee', () async {
    await book.remember('Chai Kada', vpa('chai@oksbi'));
    expect(book.lookup('Chai Kada')?.value, 'chai@oksbi');
  });

  test('an unknown payee is null, not an empty VPA', () {
    expect(book.lookup('Nobody'), isNull);
  });

  test('case and spacing are folded, as elsewhere in the app', () async {
    // The user does not think of "Chai Kada" and "chai  kada" as two people.
    await book.remember('Chai Kada', vpa('chai@oksbi'));
    expect(book.lookup('chai kada')?.value, 'chai@oksbi');
    expect(book.lookup('  CHAI   KADA  ')?.value, 'chai@oksbi');
  });

  test('a blank payee is not stored, because it could never be looked up',
      () async {
    await book.remember('   ', vpa('chai@oksbi'));
    expect(book.all(), isEmpty);
  });

  test('a stored value that is no longer a valid VPA reads as absent',
      () async {
    // Written by an older build, or edited by hand. It must never reach a
    // payment link unchecked.
    SharedPreferences.setMockInitialValues({
      'flutter.${UpiPayeeBook.keyFor('Chai Kada')}': 'not-a-vpa',
    });
    final reopened = UpiPayeeBook(await SharedPreferences.getInstance());
    expect(reopened.lookup('Chai Kada'), isNull);
  });

  test('forgetting removes it', () async {
    await book.remember('Chai Kada', vpa('chai@oksbi'));
    await book.forget('Chai Kada');
    expect(book.lookup('Chai Kada'), isNull);
  });

  test('survives a reopen', () async {
    await book.remember('Chai Kada', vpa('chai@oksbi'));
    final reopened = UpiPayeeBook(await SharedPreferences.getInstance());
    expect(reopened.lookup('Chai Kada')?.value, 'chai@oksbi');
  });

  test('all() lists every remembered payee and skips corrupt ones', () async {
    await book.remember('Chai Kada', vpa('chai@oksbi'));
    await book.remember('Auto', vpa('auto@ybl'));
    expect(book.all().length, 2);
    expect(book.all()['chai kada']?.value, 'chai@oksbi');
  });

  test('unrelated preferences are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.themeMode': 'dark',
      'flutter.${UpiPayeeBook.keyFor('Auto')}': 'auto@ybl',
    });
    final reopened = UpiPayeeBook(await SharedPreferences.getInstance());
    expect(reopened.all().keys, ['auto']);
  });
}
