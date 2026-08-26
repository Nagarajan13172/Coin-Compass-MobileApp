import 'package:coincompass/features/upi/domain/upi_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.7 — a QR is untrusted input.**
///
/// It was printed by someone else, it can be stuck over another shop's code,
/// and nothing in the format is signed. So the parser is strict about the one
/// field that decides where money goes (`pa`), lenient about everything that
/// only affects convenience, and explicit about *why* it rejected a code —
/// a scanner that silently ignores what it dislikes leaves someone pointing a
/// camera at a wall wondering if it is broken.
void main() {
  group('a real merchant QR', () {
    test('with a fixed amount', () {
      final result = UpiQr.parse(
        'upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&am=250.00&cu=INR'
        '&tn=Tea%20and%20snacks&mc=5812&tr=TXN123',
      );

      expect(result.isUsable, isTrue);
      final payload = result.payload!;
      expect(payload.payeeVpa.value, 'chaikada@okhdfcbank');
      expect(payload.payeeName, 'Chai Kada');
      expect(payload.amount, 250.00);
      expect(payload.hasAmount, isTrue);
      expect(payload.note, 'Tea and snacks');
      expect(payload.merchantCode, '5812');
      expect(payload.isMerchant, isTrue);
      expect(payload.transactionRef, 'TXN123');
    });

    test('with an open amount — the shop-counter shape', () {
      // No `am`: the payer types what they owe. This is the common case and
      // must not be confused with an amount of zero.
      final payload = UpiQr.parse('upi://pay?pa=shop@ybl&pn=Kirana').payload!;
      expect(payload.hasAmount, isFalse);
      expect(payload.amount, isNull);
      expect(payload.payeeName, 'Kirana');
    });

    test("a person's QR has no merchant code", () {
      final payload = UpiQr.parse('upi://pay?pa=hari@oksbi&pn=Hari').payload!;
      expect(payload.isMerchant, isFalse);
    });

    test('percent-encoding is decoded', () {
      final payload = UpiQr.parse(
        'upi://pay?pa=shop@ybl&pn=Ram%20%26%20Co.&tn=Bill%20%2312',
      ).payload!;
      expect(payload.payeeName, 'Ram & Co.');
      expect(payload.note, 'Bill #12');
    });

    test('uppercase keys and scheme still read', () {
      // The spec is lowercase; printed codes are not always.
      final payload = UpiQr.parse('UPI://PAY?PA=shop@ybl&PN=Shop&AM=99').payload!;
      expect(payload.payeeVpa.value, 'shop@ybl');
      expect(payload.amount, 99);
    });

    test('a collect (request-to-pay) code is accepted', () {
      expect(UpiQr.parse('upi://collect?pa=hari@oksbi&am=50').isUsable, isTrue);
    });
  });

  group('the payee decides where money goes, so it is strict', () {
    test('no payee is refused', () {
      final result = UpiQr.parse('upi://pay?pn=Shop&am=250');
      expect(result.isUsable, isFalse);
      expect(result.problem, contains('no payee'));
    });

    test('an unreadable payee is refused, and says so differently', () {
      final result = UpiQr.parse('upi://pay?pa=not-a-vpa&pn=Shop');
      expect(result.isUsable, isFalse);
      expect(result.problem, contains('cannot read'));
    });

    test('the name falls back to the VPA account, never replaces the VPA', () {
      final payload = UpiQr.parse('upi://pay?pa=chaikada@ybl').payload!;
      expect(payload.payeeName, 'chaikada');
      expect(payload.payeeVpa.value, 'chaikada@ybl');
    });

    test('control characters in a name are stripped', () {
      final payload = UpiQr.parse('upi://pay?pa=shop@ybl&pn=Sh%00op%1F').payload!;
      expect(payload.payeeName, 'Shop');
    });

    test('an absurd name is truncated rather than breaking the row', () {
      final payload =
          UpiQr.parse('upi://pay?pa=shop@ybl&pn=${'X' * 300}').payload!;
      expect(payload.payeeName.length, lessThanOrEqualTo(60));
    });
  });

  group('a bad amount does not condemn a good code', () {
    // A counter QR with a junk `am` is still perfectly payable once the user
    // types what they owe.
    test('zero, negative and unreadable all read as an open amount', () {
      for (final raw in ['0', '0.00', '-50', 'abc', '']) {
        final result = UpiQr.parse('upi://pay?pa=shop@ybl&am=$raw');
        expect(result.isUsable, isTrue, reason: 'am=$raw');
        expect(result.payload!.hasAmount, isFalse, reason: 'am=$raw');
      }
    });

    test('an amount over the UPI ceiling reads as open, not as payable', () {
      final payload = UpiQr.parse('upi://pay?pa=shop@ybl&am=250000').payload!;
      expect(payload.hasAmount, isFalse);
    });

    test('a decimal amount survives exactly', () {
      expect(UpiQr.parse('upi://pay?pa=shop@ybl&am=1234.56').payload!.amount, 1234.56);
    });
  });

  group('what it refuses, and how clearly', () {
    test('names what a non-UPI code actually is', () {
      expect(UpiQr.parse('https://example.com').problem, contains('web link'));
      expect(UpiQr.parse('WIFI:S:home;T:WPA;P:x;;').problem, contains('Wi-Fi'));
      expect(UpiQr.parse('tel:+919876543210').problem, contains('phone number'));
      expect(UpiQr.parse('mailto:a@b.com').problem, contains('email'));
    });

    test('plain text is not a payment code', () {
      final result = UpiQr.parse('just some text');
      expect(result.isUsable, isFalse);
      expect(result.problem, contains('plain text'));
    });

    test('an empty scan is refused', () {
      expect(UpiQr.parse(null).isUsable, isFalse);
      expect(UpiQr.parse('   ').isUsable, isFalse);
    });

    test('an unknown UPI action is refused rather than guessed at', () {
      final result = UpiQr.parse('upi://mandate?pa=shop@ybl&am=500');
      expect(result.isUsable, isFalse);
      expect(result.problem, contains('mandate'));
    });

    test('a foreign currency is refused, not read as rupees', () {
      // Importing a USD amount as rupees would misstate what was paid.
      final result = UpiQr.parse('upi://pay?pa=shop@ybl&am=50&cu=USD');
      expect(result.isUsable, isFalse);
      expect(result.problem, contains('USD'));
    });

    test('an explicit INR is fine', () {
      expect(UpiQr.parse('upi://pay?pa=shop@ybl&cu=inr').isUsable, isTrue);
    });
  });
}
