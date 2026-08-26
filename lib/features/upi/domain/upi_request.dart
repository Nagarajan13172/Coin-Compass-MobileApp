/// Phase 7.6 — building a `upi://pay` link that a payment app will accept.
///
/// The NPCI deep-link spec is a query string and nothing more, which makes it
/// deceptively easy to get wrong: every field is a string, so a bad amount, an
/// unescaped note or a malformed payee produce a link that *opens* the payment
/// app and then fails inside it — or worse, opens it with the wrong number.
///
/// So this validates before it builds, and refuses rather than guessing. It is
/// pure: no channel, no plugin, no phone.
library;

import 'upi_qr.dart';

/// A payee's UPI address — `name@bank`.
///
/// Deliberately strict. A VPA is not free text: it is the thing money is sent
/// to, and a typo here does not fail, it pays someone else. Nothing about the
/// deep link protects against that, so the only defence is refusing anything
/// that is not shaped like a VPA and showing the user exactly what they are
/// about to pay.
class Vpa {
  const Vpa._(this.value);

  final String value;

  /// The handle side (`@oksbi`), for showing which bank/app backs it.
  String get handle => value.split('@').last;
  String get account => value.split('@').first;

  /// NPCI allows letters, digits and `.-_` either side of a single `@`.
  /// Case is preserved — some PSPs are case-sensitive — but whitespace is not
  /// tolerated anywhere, because a trailing space from a paste is the single
  /// most common way a VPA arrives broken.
  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9.]{1,63}$');

  /// Null when [raw] is not a usable VPA.
  static Vpa? tryParse(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!_pattern.hasMatch(trimmed)) return null;
    return Vpa._(trimmed);
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is Vpa && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Everything one payment needs.
class UpiRequest {
  const UpiRequest({
    required this.payeeVpa,
    required this.payeeName,
    required this.amount,
    this.note,
    this.transactionRef,
    this.scannedRaw,
    this.scannedAmount,
  });

  /// A payment that came from a scanned QR.
  ///
  /// Carries the scanned string so [toUri] can replay it rather than rebuild
  /// it — see [scannedRaw] for why that distinction decides whether a merchant
  /// payment succeeds at all.
  /// Takes no note on purpose: adding `tn` to a scanned link changes the bytes
  /// a signed QR was signed over, and the merchant's own `tn` is already in the
  /// string. The form's note still reaches the *ledger* — it just does not
  /// reach the payment.
  UpiRequest.fromScan(
    UpiQrPayload payload, {
    required this.amount,
  })  : note = null,
        payeeVpa = payload.payeeVpa,
        payeeName = payload.payeeName,
        transactionRef = payload.transactionRef,
        scannedRaw = payload.raw,
        scannedAmount = payload.amount;

  final Vpa payeeVpa;

  /// Shown by the payment app as who is being paid. Not verified by anything —
  /// the VPA is what money follows — so it is a label, never a guarantee.
  final String payeeName;

  /// Rupees. Must be positive; the spec has no notion of a refund here.
  final num amount;

  final String? note;

  /// The app's own reference, echoed back in the result so a return can be
  /// matched to the request that caused it.
  final String? transactionRef;

  /// The scanned QR verbatim, when this payment came from one.
  ///
  /// A merchant QR carries `mc`, `sign`, `orgid`, `mode` and merchant ids that
  /// this app neither understands nor needs to. Rebuilding a link from the few
  /// fields it does understand drops all of them, and the payment app then
  /// treats a *merchant* payment as person-to-person — which merchants refuse,
  /// and which is metered against the wrong limits. Replaying the original
  /// avoids the whole question.
  final String? scannedRaw;

  /// The amount the QR itself fixed, if any. Used to tell "the user accepted
  /// the QR's amount" from "the user typed a different one".
  final num? scannedAmount;

  bool get isFromScan => scannedRaw != null;

  /// Exactly two decimals, no grouping, no symbol — `1234.50`.
  ///
  /// `Money.format` is deliberately *not* used: it produces `₹1,234.50` for
  /// human eyes, and a payment app handed that either refuses the link or, on
  /// some builds, parses the digits it recognises. This is the one place in the
  /// app where a number must not be formatted for reading.
  String get formattedAmount => amount.toStringAsFixed(2);

  /// Notes are truncated rather than rejected: a long note is a nuisance, and
  /// failing the whole payment over one would be worse. 50 characters is the
  /// conservative limit across PSPs.
  static const int maxNoteLength = 50;

  /// The `upi://pay?…` link.
  ///
  /// Built with [Uri] rather than string concatenation so every value is
  /// percent-encoded — a note containing `&` would otherwise inject a
  /// parameter, and a payee name with a space would break the link outright.
  Uri toUri() {
    final raw = scannedRaw;
    if (raw != null) return _scannedUri(raw);

    final trimmedNote = note?.trim();
    return _upiUri({
      'pa': payeeVpa.value,
      'pn': payeeName.trim().isEmpty ? payeeVpa.account : payeeName.trim(),
      'am': formattedAmount,
      'cu': 'INR',
      if (trimmedNote != null && trimmedNote.isNotEmpty)
        'tn': trimmedNote.length > maxNoteLength
            ? trimmedNote.substring(0, maxNoteLength)
            : trimmedNote,
      if (transactionRef != null && transactionRef!.isNotEmpty)
        'tr': transactionRef!,
    });
  }

  /// Percent-encoding that leaves `@` alone.
  ///
  /// **This is what three "the bank declined" fixes were chasing.**
  /// `Uri(queryParameters: …)` — and `Uri.encodeComponent` — encode `@` as
  /// `%40`, so a payee address went out as
  ///
  ///     pa=prithivi2804raj%40okicici
  ///
  /// A VPA without a literal `@` is not a VPA. The payment app decodes it
  /// happily *for display*, which is why the payee and amount always looked
  /// right on screen, and then hands the network a malformed address — which
  /// comes back as a generic decline, rendered by Google Pay as "you've
  /// exceeded the bank limit for this payment" on a payment of ₹1.
  ///
  /// RFC 3986 permits `@` unescaped in a query; Dart is simply stricter than
  /// the grammar. Everything else is encoded normally, so a note containing
  /// `&` still cannot inject a parameter.
  static String _encodeValue(String value) =>
      Uri.encodeComponent(value).replaceAll('%40', '@');

  /// Builds `upi://pay?…` by hand, for the reason above. `Uri` cannot express
  /// this, so the string is assembled and only then parsed back.
  static Uri _upiUri(Map<String, String> params) => Uri.parse(
    'upi://pay?${params.entries.map((e) => '${e.key}=${_encodeValue(e.value)}').join('&')}',
  );

  /// The only fields an **intent** carries.
  ///
  /// An allowlist, not a blocklist. The blocklist version of this banned
  /// `sign` and `mode` and let everything else through — which meant a Google
  /// Pay *personal* QR forwarded `mc=0000`, `orgid=159761` and `purpose=00`
  /// into a person-to-person payment. Anything not thought of leaks through a
  /// blocklist; nothing leaks through an allowlist.
  ///
  /// This is the set NPCI's linking spec defines for intent flows. Everything
  /// else in a QR describes **the QR** — how it was generated, by whom, and a
  /// signature over its bytes — and none of that survives being read by one app
  /// and handed to another.
  static const Set<String> _intentFields = {
    'pa', // payee address — the only field money follows
    'pn', // payee name
    'am', // amount
    'cu', // currency
    'tn', // note
    'tr', // transaction reference
    'mc', // merchant category — see below, only for real merchants
  };

  /// `mc=0000` is a QR's way of saying **"not a merchant"**.
  ///
  /// Forwarding it as an intent parameter says the opposite: it asserts a
  /// merchant category on what is a person-to-person transfer, and the bank
  /// declines — in ICICI's words, *"you've exceeded the bank limit for this
  /// payment"*, on a payment of **₹1**.
  static bool _isRealMerchant(String? mc) {
    final code = mc?.trim();
    if (code == null || code.isEmpty) return false;
    // "0000" and any all-zero variant mean no category.
    return int.tryParse(code) != 0;
  }

  /// The scanned code, reduced to an intent.
  ///
  /// A QR and an intent are different things carrying overlapping data. Reading
  /// a QR and handing a payment app an intent means **translating** between
  /// them, not forwarding one as the other:
  ///
  ///  * `sign` signs the QR's own bytes, and filling in an amount changes them,
  ///    so any signature is invalid by construction — and a signature that does
  ///    not match is a validation failure where none at all is merely an
  ///    unsigned intent;
  ///  * `mode=02` claims the paying app scanned this itself, which stopped
  ///    being true the moment CoinCompass read it;
  ///  * `orgid` and `purpose` describe the QR's origin, not this payment;
  ///  * `mc=0000` says "no merchant", so sending it asserts the opposite.
  ///
  /// What is left is the payee, the amount, and — for an actual merchant — the
  /// category and reference that keep it from being metered as P2P.
  Uri _scannedUri(String raw) {
    final existing = Uri.parse(raw);

    final params = <String, String>{};
    for (final entry in existing.queryParameters.entries) {
      final key = entry.key.toLowerCase();
      if (!_intentFields.contains(key)) continue;
      if (key == 'mc' && !_isRealMerchant(entry.value)) continue;
      if (key == 'am') continue; // set below, from what the user is paying
      params[key] = entry.value;
    }

    params['am'] = formattedAmount;
    params['cu'] = 'INR';

    return _upiUri(params);
  }

  /// Why an amount cannot be sent over UPI, or null when it can.
  ///
  /// **Static, and independent of the payee.** The sheet has to say "that
  /// amount is too large" before a VPA has been typed, and an earlier version
  /// that only offered this on a built request made the sheet fabricate a
  /// placeholder VPA to ask — which crashed on the device the first time it
  /// opened, because the placeholder did not satisfy [Vpa]'s own rules. A check
  /// that needs a payee to validate an amount was the wrong shape.
  static String? amountBlocker(num amount) {
    if (amount <= 0) return 'Enter an amount above zero.';
    // UPI's per-transaction ceiling is ₹1,00,000 for most banks. Over it the
    // payment app rejects the link after opening, which reads to the user as
    // this app being broken.
    if (amount > 100000) {
      return 'UPI usually caps a single payment at ₹1,00,000. '
          'Pay this one from your bank instead.';
    }
    return null;
  }

  /// Why this request cannot be sent, or null when it can.
  ///
  /// Returned rather than thrown so the sheet can disable its button and say
  /// why, instead of launching a payment app that fails on arrival.
  String? get blocker => amountBlocker(amount);

  bool get isSendable => blocker == null;
}
