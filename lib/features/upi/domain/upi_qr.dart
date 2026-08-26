/// Phase 7.7 — reading a UPI QR code.
///
/// A UPI QR encodes exactly the link this app already builds:
///
///     upi://pay?pa=merchant@bank&pn=Chai%20Kada&am=250.00&cu=INR&tn=…
///
/// so scanning is the inverse of [UpiRequest.toUri], and the same rule governs
/// both: **a QR is untrusted input.** It was printed by someone else, it can be
/// stuck over another shop's code, and nothing in the format is signed. The
/// payee name in particular is a label the printer chose — it is not verified by
/// anyone, so it is shown verbatim beside the VPA and never used in its place.
library;

import 'upi_request.dart';

/// A QR that this app can pay from.
class UpiQrPayload {
  const UpiQrPayload({
    required this.payeeVpa,
    required this.payeeName,
    this.amount,
    this.note,
    this.merchantCode,
    this.transactionRef,
    this.currency = 'INR',
    required this.raw,
  });

  final Vpa payeeVpa;

  /// As printed on the QR. **Unverified** — see the library note.
  final String payeeName;

  /// Null when the QR fixes no amount, which is the common shape for a shop
  /// counter: the payer types what they owe. Distinguished from zero so the
  /// form knows whether to prefill or to ask.
  final num? amount;

  final String? note;

  /// `mc` — present on merchant QRs, absent on a person's. Kept because it is
  /// the one hint that this is a business rather than an individual.
  final String? merchantCode;

  final String? transactionRef;
  final String currency;

  /// **The scanned string, byte for byte.**
  ///
  /// This is the field that matters most, and the one the first version did not
  /// keep. A merchant QR carries far more than a payee and an amount — `mc`
  /// (merchant category), `sign`, `orgid`, `mode`, `mid`/`msid` — and
  /// reconstructing a link from the handful of fields this app understands
  /// throws all of it away. What reaches the payment app is then a bare
  /// person-to-person transfer to a *merchant* VPA, which merchants routinely
  /// refuse ("payment failed") and which is metered against P2P limits rather
  /// than merchant ones ("exceeded for this account").
  ///
  /// So paying from a scan replays this string instead of rebuilding one. See
  /// `UpiRequest.fromScan`.
  final String raw;

  bool get hasAmount => amount != null;
  bool get isMerchant => merchantCode != null && merchantCode!.isNotEmpty;
}

/// What came of scanning one code.
class UpiQrResult {
  const UpiQrResult._({this.payload, this.problem});

  const UpiQrResult.usable(UpiQrPayload payload) : this._(payload: payload);
  const UpiQrResult.rejected(String problem) : this._(problem: problem);

  final UpiQrPayload? payload;

  /// Why this code cannot be paid, phrased for the scanner overlay. Non-null
  /// exactly when [payload] is null.
  final String? problem;

  bool get isUsable => payload != null;
}

abstract final class UpiQr {
  /// Reads the text a scanner produced.
  ///
  /// Deliberately explicit about *why* something was rejected. A scanner that
  /// silently ignores every code it does not like leaves the user pointing a
  /// camera at a wall wondering whether it is broken — so a Wi-Fi QR, a link
  /// and a malformed UPI code each say something different.
  static UpiQrResult parse(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) {
      return const UpiQrResult.rejected('That code is empty.');
    }

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.isEmpty) {
      return const UpiQrResult.rejected(
        'That is not a payment code — it is plain text.',
      );
    }

    if (uri.scheme.toLowerCase() != 'upi') {
      // Naming what it *is* beats "invalid": the user then knows to look for a
      // different code rather than rescanning the same one.
      final what = switch (uri.scheme.toLowerCase()) {
        'http' || 'https' => 'a web link',
        'wifi' => 'a Wi-Fi code',
        'tel' => 'a phone number',
        'mailto' => 'an email address',
        'bitcoin' || 'ethereum' => 'a crypto address',
        _ => 'a ${uri.scheme} code',
      };
      return UpiQrResult.rejected('That is $what, not a UPI payment code.');
    }

    // `upi://pay`, and the `upi://collect` a request-to-pay QR uses. Anything
    // else in that slot is a shape this build does not know, and guessing at
    // an unknown UPI verb is guessing about money.
    final action = (uri.host.isNotEmpty ? uri.host : uri.path)
        .replaceAll('/', '')
        .toLowerCase();
    if (action.isNotEmpty && action != 'pay' && action != 'collect') {
      return UpiQrResult.rejected(
        'That UPI code asks for "$action", which this app cannot do.',
      );
    }

    // Keys are lowercased: the spec is lowercase but printed codes are not
    // always, and a QR that says `PA=` is otherwise read as having no payee.
    final fields = <String, String>{
      for (final entry in uri.queryParameters.entries)
        entry.key.trim().toLowerCase(): entry.value.trim(),
    };

    final vpa = Vpa.tryParse(fields['pa']);
    if (vpa == null) {
      return UpiQrResult.rejected(
        fields['pa'] == null
            ? 'That UPI code has no payee in it.'
            : 'That UPI code has a payee this app cannot read.',
      );
    }

    final currency = (fields['cu'] ?? 'INR').toUpperCase();
    if (currency != 'INR') {
      // The whole app is rupees; importing a foreign-currency amount as though
      // it were rupees would misstate what was paid.
      return UpiQrResult.rejected(
        'That code is in $currency. This app only pays in rupees.',
      );
    }

    return UpiQrResult.usable(
      UpiQrPayload(
        raw: text,
        payeeVpa: vpa,
        payeeName: _cleanName(fields['pn']) ?? vpa.account,
        amount: _amount(fields['am']),
        note: _clean(fields['tn']),
        merchantCode: _clean(fields['mc']),
        transactionRef: _clean(fields['tr']),
        currency: currency,
      ),
    );
  }

  /// A fixed amount, or null for an open one.
  ///
  /// Zero, negative and unreadable all become null rather than an error: a
  /// counter QR with a junk `am` is still perfectly payable once the user types
  /// what they owe, and refusing the whole code over it would be unhelpful.
  static num? _amount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value <= 0) return null;
    if (UpiRequest.amountBlocker(value) != null) return null;
    return value;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Merchant names arrive padded, and occasionally with control characters
  /// from a badly generated code.
  static String? _cleanName(String? value) {
    final cleaned = _clean(value)?.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    if (cleaned == null || cleaned.isEmpty) return null;
    // Long enough for a real trading name, short enough not to break a row.
    return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  }
}
