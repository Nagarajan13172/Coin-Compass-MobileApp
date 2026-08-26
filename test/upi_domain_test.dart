import 'package:coincompass/features/upi/domain/upi_qr.dart';
import 'package:coincompass/features/upi/domain/upi_request.dart';
import 'package:coincompass/features/upi/domain/upi_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 7.6 — the two places a payment link can lie.**
///
/// A deep link is just a query string, so every field is a string and nothing
/// validates it but this. A malformed link does not fail safely: it opens a
/// payment app with the wrong number in it. And the response that comes back is
/// **not proof of payment** — NPCI says only a server-side check is
/// authoritative — so the parser's job is to be exact about what it was told
/// and never to round it up into "paid".
void main() {
  Vpa vpa(String raw) => Vpa.tryParse(raw)!;

  group('a VPA is not free text', () {
    test('accepts the shapes real handles take', () {
      expect(Vpa.tryParse('hari@oksbi'), isNotNull);
      expect(Vpa.tryParse('hari.kumar@okhdfcbank'), isNotNull);
      expect(Vpa.tryParse('hari-kumar_1@ybl'), isNotNull);
      expect(Vpa.tryParse('9876543210@paytm'), isNotNull);
    });

    test('a pasted VPA with surrounding space still works', () {
      // The single most common way a VPA arrives broken.
      expect(Vpa.tryParse('  hari@oksbi  ')?.value, 'hari@oksbi');
    });

    test('refuses anything not shaped like a VPA', () {
      // A typo here does not fail — it pays someone else.
      expect(Vpa.tryParse('hari'), isNull);
      expect(Vpa.tryParse('@oksbi'), isNull);
      expect(Vpa.tryParse('hari@'), isNull);
      expect(Vpa.tryParse('hari@@oksbi'), isNull);
      expect(Vpa.tryParse('hari kumar@oksbi'), isNull, reason: 'inner space');
      expect(Vpa.tryParse('hari@oksbi extra'), isNull);
      expect(Vpa.tryParse(''), isNull);
      expect(Vpa.tryParse(null), isNull);
    });

    test('case is preserved, because some PSPs are case-sensitive', () {
      expect(Vpa.tryParse('Hari.Kumar@OKSBI')?.value, 'Hari.Kumar@OKSBI');
    });

    test('splits into account and handle for display', () {
      expect(vpa('hari@oksbi').account, 'hari');
      expect(vpa('hari@oksbi').handle, 'oksbi');
    });
  });

  group('the link', () {
    UpiRequest request({num amount = 250, String? note, String? ref}) =>
        UpiRequest(
          payeeVpa: vpa('hari@oksbi'),
          payeeName: 'Hari Kumar',
          amount: amount,
          note: note,
          transactionRef: ref,
        );

    test('carries the amount as plain decimals, never formatted money', () {
      // Money.format would produce ₹1,234.50 — a payment app either refuses
      // that or parses whatever digits it recognises.
      expect(request(amount: 1234.5).formattedAmount, '1234.50');
      expect(request(amount: 250).formattedAmount, '250.00');
      expect(request(amount: 0.5).formattedAmount, '0.50');
    });

    test('is a well-formed upi://pay link', () {
      final uri = request(amount: 250).toUri();
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'hari@oksbi');
      expect(uri.queryParameters['pn'], 'Hari Kumar');
      expect(uri.queryParameters['am'], '250.00');
      expect(uri.queryParameters['cu'], 'INR');
    });

    test('escapes a note that would otherwise inject a parameter', () {
      final uri = request(note: 'rent & water').toUri();
      // Read back through Uri, the note is intact and did not become a param.
      expect(uri.queryParameters['tn'], 'rent & water');
      expect(uri.toString(), contains('%26'));
      expect(uri.queryParameters.containsKey('water'), isFalse);
    });

    test('truncates a long note rather than failing the payment', () {
      final uri = request(note: 'x' * 200).toUri();
      expect(uri.queryParameters['tn']!.length, UpiRequest.maxNoteLength);
    });

    test('omits optional fields rather than sending empties', () {
      final uri = request().toUri();
      expect(uri.queryParameters.containsKey('tn'), isFalse);
      expect(uri.queryParameters.containsKey('tr'), isFalse);
    });

    test('falls back to the VPA account when no name is given', () {
      final uri = UpiRequest(
        payeeVpa: vpa('hari@oksbi'),
        payeeName: '   ',
        amount: 10,
      ).toUri();
      expect(uri.queryParameters['pn'], 'hari');
    });

    test('refuses amounts that cannot be paid', () {
      expect(request(amount: 0).isSendable, isFalse);
      expect(request(amount: -5).isSendable, isFalse);
      // Over the usual UPI ceiling the payment app opens and *then* rejects,
      // which reads to the user as this app being broken.
      expect(request(amount: 100001).isSendable, isFalse);
      expect(request(amount: 100000).isSendable, isTrue);
    });
  });

  group('the amount check does not need a payee', () {
    // Regression: the sheet has to say "too large" before a VPA is typed. An
    // earlier version only offered this on a built request, so the sheet
    // fabricated a placeholder VPA to ask — and crashed on the device the first
    // time it opened, because the placeholder failed Vpa's own rules.
    test('is answerable from the amount alone', () {
      expect(UpiRequest.amountBlocker(250), isNull);
      expect(UpiRequest.amountBlocker(0), isNotNull);
      expect(UpiRequest.amountBlocker(-1), isNotNull);
      expect(UpiRequest.amountBlocker(100000), isNull);
      expect(UpiRequest.amountBlocker(100001), contains('1,00,000'));
    });

    test('agrees with the instance form', () {
      final request = UpiRequest(
        payeeVpa: vpa('hari@oksbi'),
        payeeName: 'Hari',
        amount: 100001,
      );
      expect(request.blocker, UpiRequest.amountBlocker(100001));
    });
  });

  group('a scanned QR becomes an intent: descriptive fields kept, session fields dropped', () {
    // Two real failures shaped this, one after the other.
    //
    // FIRST: the link was rebuilt from the five fields the parser understood,
    // which dropped `mc` — so a merchant payment reached the app as
    // person-to-person, and merchants refuse that ("payment failed",
    // "exceeded for this account").
    //
    // SECOND: replaying the whole string fixed that but carried `sign` and
    // `mode=02` across. A ₹100 payment to a personal PhonePe QR then showed the
    // right payee and right amount in Google Pay and was declined by ICICI with
    // "you've exceeded the bank limit" — a generic decline. The same QR scanned
    // *inside* Google Pay worked, because there the signature still matched.
    //
    // A signature over content that has since changed is a validation failure;
    // no signature is merely an unsigned intent.
    const merchantQr =
        'upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&am=250.00&cu=INR'
        '&mc=5812&tr=TXN0099&sign=MEUCIQDabc123&orgid=159761&mode=01';

    /// A personal PhonePe QR: no amount, but signed and marked as scanned.
    const personalQr =
        'upi://pay?pa=9786452324@axl&pn=SATHISH%20KUMAR&mc=0000&mode=02'
        '&purpose=00&sign=MEUCIQDxyz789';

    UpiQrPayload scan(String raw) => UpiQr.parse(raw).payload!;

    Map<String, String> sentFor(String qr, num amount) =>
        UpiRequest.fromScan(scan(qr), amount: amount).toUri().queryParameters;

    test('the payee-describing fields all survive', () {
      final sent = sentFor(merchantQr, 250.00);
      // Exactly what the first version threw away.
      expect(sent['pa'], 'chaikada@okhdfcbank');
      expect(sent['pn'], 'Chai Kada');
      expect(sent['mc'], '5812');
      expect(sent['tr'], 'TXN0099');
      expect(sent['orgid'], '159761');
    });

    test('the QR-session fields do not', () {
      final sent = sentFor(merchantQr, 250.00);
      expect(sent.containsKey('sign'), isFalse);
      expect(sent.containsKey('mode'), isFalse);
    });

    test('a stale signature is never sent after the amount changes', () {
      // The exact shape of the ₹100 failure: an open QR, signed, amount added.
      final sent = sentFor(personalQr, 100);
      expect(sent['am'], '100.00');
      expect(sent.containsKey('sign'), isFalse,
          reason: 'the signature no longer covers this content');
      expect(sent.containsKey('mode'), isFalse,
          reason: 'this arrives as an intent, not as a scan');
    });

    test('an open QR still gets its amount and currency', () {
      final sent = sentFor(personalQr, 340.5);
      expect(sent['am'], '340.50');
      expect(sent['cu'], 'INR');
      expect(sent['pa'], '9786452324@axl');
      expect(sent['mc'], '0000', reason: 'still describes the payee');
      expect(sent['purpose'], '00');
    });

    test('an overridden amount replaces the QR\'s own', () {
      final sent = sentFor(merchantQr, 500);
      expect(sent['am'], '500.00');
      expect(sent['mc'], '5812');
    });

    test('an unsigned QR is unaffected by any of this', () {
      const plain = 'upi://pay?pa=kirana@ybl&pn=Kirana&mc=5411';
      final sent = sentFor(plain, 60);
      expect(sent['mc'], '5411');
      expect(sent['am'], '60.00');
      expect(sent['cu'], 'INR');
    });

    test('a hand-typed payee still builds a link, as before', () {
      final request = UpiRequest(
        payeeVpa: vpa('hari@oksbi'),
        payeeName: 'Hari',
        amount: 100,
      );
      expect(request.isFromScan, isFalse);
      expect(request.toUri().queryParameters['pa'], 'hari@oksbi');
    });

    test('a scanned request knows it came from a scan', () {
      expect(
        UpiRequest.fromScan(scan(merchantQr), amount: 250).isFromScan,
        isTrue,
      );
    });
  });

  group('the response is not proof', () {
    test('reads a normal success', () {
      final result = UpiResult.parse(
        'txnId=AXI0001&responseCode=00&Status=SUCCESS&txnRef=cc-42&approvalRefNo=9911',
      );
      expect(result.status, UpiStatus.success);
      expect(result.transactionId, 'AXI0001');
      expect(result.transactionRef, 'cc-42');
      expect(result.responseCode, '00');
      expect(result.approvalRef, '9911');
      expect(result.isReportedPaid, isTrue);
    });

    test('SUBMITTED is pending, and pending is NOT paid', () {
      // Bank-account debits settle asynchronously. Calling this success is how
      // an app tells someone they paid when they may not have.
      final result = UpiResult.parse('txnId=X&Status=SUBMITTED');
      expect(result.status, UpiStatus.pending);
      expect(result.isReportedPaid, isFalse);
      expect(result.mayHavePaid, isTrue, reason: 'worth offering to record');
    });

    test('failure is failure', () {
      expect(UpiResult.parse('Status=FAILURE').status, UpiStatus.failure);
      expect(UpiResult.parse('Status=FAILED').status, UpiStatus.failure);
      expect(UpiResult.parse('Status=FAILURE').mayHavePaid, isFalse);
    });

    test('backing out is cancelled, not an error', () {
      expect(UpiResult.parse(null).status, UpiStatus.cancelled);
      expect(UpiResult.parse('').status, UpiStatus.cancelled);
      expect(UpiResult.parse('   ').status, UpiStatus.cancelled);
    });

    test('keys are matched case-insensitively, because apps disagree', () {
      expect(UpiResult.parse('status=success&txnid=A1').status,
          UpiStatus.success);
      expect(UpiResult.parse('STATUS=SUCCESS').status, UpiStatus.success);
      expect(UpiResult.parse('status=success&TxnId=A1').transactionId, 'A1');
    });

    test('an unreadable status is unknown, never a guess either way', () {
      final result = UpiResult.parse('Status=WHO_KNOWS&txnId=A1');
      expect(result.status, UpiStatus.unknown);
      expect(result.isReportedPaid, isFalse);
      expect(result.mayHavePaid, isFalse);
    });

    test('the literal string "null" is an absent field', () {
      final result = UpiResult.parse('Status=SUCCESS&txnId=null&txnRef=');
      expect(result.transactionId, isNull);
      expect(result.transactionRef, isNull);
    });

    test('the raw response is kept for anything unreadable', () {
      const raw = 'Status=WEIRD&somethingNew=1';
      expect(UpiResult.parse(raw).raw, raw);
    });

    test('a value containing = survives', () {
      // base64 references are common and end in padding.
      final result = UpiResult.parse('Status=SUCCESS&txnId=YWJj==');
      expect(result.transactionId, 'YWJj==');
    });
  });
}
