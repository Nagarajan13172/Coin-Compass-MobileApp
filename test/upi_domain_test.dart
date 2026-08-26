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

  group('a scanned QR is translated into an intent, not forwarded as one', () {
    // Three real failures shaped this, each teaching the same lesson from a
    // different side: a QR and an intent are different things that happen to
    // share some field names.
    //
    // 1. The link was REBUILT from five fields, dropping `mc` — so a merchant
    //    payment arrived as person-to-person and merchants refuse that.
    // 2. The whole string was REPLAYED — so a stale `sign` and `mode=02` came
    //    with it, and a signature over content that had since gained an amount
    //    is invalid by construction.
    // 3. A BLOCKLIST banned `sign`/`mode` and let everything else through — so
    //    a Google Pay personal QR forwarded `mc=0000`, `orgid` and `purpose`,
    //    asserting a merchant category on a P2P transfer. ₹1 to
    //    prithivi2804raj@okicici was declined with "you've exceeded the bank
    //    limit for this payment".
    //
    // Hence an allowlist: nothing leaks through one.

    /// A Google Pay personal QR — the exact shape of failure 3.
    const personalQr =
        'upi://pay?pa=prithivi2804raj@okicici&pn=Prithiviraj%20B&cu=INR'
        '&mc=0000&mode=02&purpose=00&orgid=159761&sign=MEUCIQDxyz789';

    /// A real merchant QR — the shape of failure 1.
    const merchantQr =
        'upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&am=250.00&cu=INR'
        '&mc=5812&tr=TXN0099&sign=MEUCIQDabc123&orgid=159761&mode=01';

    UpiQrPayload scan(String raw) => UpiQr.parse(raw).payload!;
    Map<String, String> sentFor(String qr, num amount) =>
        UpiRequest.fromScan(scan(qr), amount: amount).toUri().queryParameters;

    test('a personal QR sends only the payee, amount and currency', () {
      final sent = sentFor(personalQr, 1);
      expect(sent, {
        'pa': 'prithivi2804raj@okicici',
        'pn': 'Prithiviraj B',
        'cu': 'INR',
        'am': '1.00',
      });
    });

    test('mc=0000 means NOT a merchant, so it is not forwarded', () {
      // Sending it asserts a merchant category on a P2P transfer.
      expect(sentFor(personalQr, 1).containsKey('mc'), isFalse);
    });

    test('QR-origin fields never reach the intent', () {
      final sent = sentFor(personalQr, 1);
      for (final field in ['sign', 'mode', 'orgid', 'purpose']) {
        expect(sent.containsKey(field), isFalse, reason: field);
      }
    });

    test('a real merchant keeps its category and reference', () {
      final sent = sentFor(merchantQr, 250);
      expect(sent['mc'], '5812', reason: 'what stops P2M being metered as P2P');
      expect(sent['tr'], 'TXN0099');
      expect(sent['pa'], 'chaikada@okhdfcbank');
      expect(sent['am'], '250.00');
    });

    test('a merchant QR still sheds its QR-origin fields', () {
      final sent = sentFor(merchantQr, 250);
      expect(sent.containsKey('sign'), isFalse);
      expect(sent.containsKey('mode'), isFalse);
      expect(sent.containsKey('orgid'), isFalse);
    });

    test('an unknown future field cannot leak through', () {
      // The blocklist's failure mode, pinned so it cannot return.
      const odd = 'upi://pay?pa=shop@ybl&pn=Shop&somethingNew=1&mtid=xyz';
      final sent = sentFor(odd, 50);
      expect(sent.keys.toSet(), {'pa', 'pn', 'am', 'cu'});
    });

    test('the amount is always the one being paid, not the QR\'s', () {
      expect(sentFor(merchantQr, 500)['am'], '500.00');
      expect(sentFor(personalQr, 340.5)['am'], '340.50');
    });

    test('a note on the QR survives, since it describes the payment', () {
      const withNote = 'upi://pay?pa=shop@ybl&pn=Shop&tn=Bill%2012&mc=5411';
      final sent = sentFor(withNote, 60);
      expect(sent['tn'], 'Bill 12');
      expect(sent['mc'], '5411');
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
  });

  group('the VPA keeps its @ — the defect that broke every payment', () {
    // Google Pay showed the right payee and the right ₹1, then ICICI declined
    // with "you've exceeded the bank limit for this payment". On every phone,
    // on every linked bank account, while the same QR scanned inside Google Pay
    // worked. Captured from the device, the link this app actually sent was:
    //
    //   upi://pay?pa=prithivi2804raj%40okicici&pn=…&am=1.00&cu=INR
    //
    // `Uri(queryParameters:)` percent-encodes `@`. A VPA without a literal `@`
    // is not a VPA — the payment app decodes it for DISPLAY, which is why the
    // screen always looked right, and the network gets a malformed address.

    test('a hand-typed payee sends a literal @', () {
      final uri = UpiRequest(
        payeeVpa: vpa('prithivi2804raj@okicici'),
        payeeName: 'Prithiviraj B',
        amount: 1,
      ).toUri().toString();

      expect(uri, contains('pa=prithivi2804raj@okicici'));
      expect(uri, isNot(contains('%40')));
    });

    test('a scanned payee sends a literal @', () {
      const qr = 'upi://pay?pa=prithivi2804raj@okicici&pn=Prithiviraj%20B'
          '&cu=INR&mc=0000&mode=02&sign=abc';
      final uri = UpiRequest.fromScan(UpiQr.parse(qr).payload!, amount: 1)
          .toUri()
          .toString();

      expect(uri, contains('pa=prithivi2804raj@okicici'));
      expect(uri, isNot(contains('%40')));
    });

    test('it still reads back correctly as a URI', () {
      final uri = UpiRequest(
        payeeVpa: vpa('prithivi2804raj@okicici'),
        payeeName: 'Prithiviraj B',
        amount: 1,
      ).toUri();
      expect(uri.queryParameters['pa'], 'prithivi2804raj@okicici');
      expect(uri.queryParameters['pn'], 'Prithiviraj B');
      expect(uri.queryParameters['am'], '1.00');
    });

    test('everything else is still escaped — a note cannot inject a param', () {
      final uri = UpiRequest(
        payeeVpa: vpa('shop@ybl'),
        payeeName: 'Ram & Co.',
        amount: 50,
        note: 'rent & water',
      ).toUri();

      expect(uri.toString(), contains('%26'));
      expect(uri.queryParameters['tn'], 'rent & water');
      expect(uri.queryParameters['pn'], 'Ram & Co.');
      expect(uri.queryParameters.containsKey('water'), isFalse);
    });

    test('a space is %20, never +', () {
      // `Uri.encodeQueryComponent` uses `+` for spaces, which UPI reads
      // literally.
      final uri = UpiRequest(
        payeeVpa: vpa('shop@ybl'),
        payeeName: 'Chai Kada',
        amount: 10,
      ).toUri().toString();
      expect(uri, contains('pn=Chai%20Kada'));
      expect(uri, isNot(contains('+')));
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
