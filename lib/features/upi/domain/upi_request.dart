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
  });

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
    final trimmedNote = note?.trim();
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
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
      },
    );
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
