/// Phase 7.6 — reading what the payment app said, and refusing to over-read it.
///
/// ## This is not proof of payment
///
/// NPCI's own spec is explicit: the deep-link response is **advisory**, and
/// only a server-side check against the PSP is authoritative. The string comes
/// back through an `Intent` extra from an app this app did not write, on a
/// device the owner controls — a `SUCCESS` can be wrong or forged, and a
/// missing result does not mean the money stayed put.
///
/// The app therefore never records a transaction on the strength of this alone.
/// It reports what it was told and lets the owner confirm, which is the only
/// honest reading of a channel that cannot be trusted.
library;

enum UpiStatus {
  /// The app reported the payment went through. Still not proof — see above.
  success,

  /// Explicitly failed or declined.
  failure,

  /// **Accepted, outcome unknown.** Common for bank-account debits that settle
  /// asynchronously. It is emphatically *not* success, and treating it as such
  /// is how an app tells someone they paid when they may not have.
  pending,

  /// The user backed out before paying, or the app returned nothing at all.
  /// Not an error, and not worth an alarming message.
  cancelled,

  /// A response arrived that this build cannot read.
  unknown,
}

/// One payment attempt, as reported.
class UpiResult {
  const UpiResult({
    required this.status,
    this.transactionId,
    this.transactionRef,
    this.responseCode,
    this.approvalRef,
    this.raw,
  });

  final UpiStatus status;

  /// The PSP's own id for the transaction.
  final String? transactionId;

  /// Echo of the `tr` this app sent, so a return can be tied to its request.
  final String? transactionRef;

  final String? responseCode;
  final String? approvalRef;

  /// Kept verbatim. When a payment app returns something unreadable, the raw
  /// string is the only way anyone can work out what happened afterwards.
  final String? raw;

  /// True only for [UpiStatus.success] — provided so no call site has to
  /// remember that `pending` is not success.
  bool get isReportedPaid => status == UpiStatus.success;

  /// Whether it is worth offering to record an expense. Pending counts: the
  /// money has probably left, and the owner is the one who decides.
  bool get mayHavePaid =>
      status == UpiStatus.success || status == UpiStatus.pending;

  /// Parses the `response` extra a UPI app returns.
  ///
  /// The shape is a query string — `txnId=…&responseCode=00&Status=SUCCESS&
  /// txnRef=…` — but the details vary by app, so this is deliberately tolerant:
  ///
  ///  * **keys are matched case-insensitively**, because apps disagree about
  ///    `Status` vs `status` and about `txnId` vs `txnid`;
  ///  * an unrecognised status is [UpiStatus.unknown], never a default of
  ///    success or failure — guessing either way misinforms about money;
  ///  * `null` or empty is [UpiStatus.cancelled], which is what a back press
  ///    produces.
  factory UpiResult.parse(String? response) {
    if (response == null || response.trim().isEmpty) {
      return const UpiResult(status: UpiStatus.cancelled);
    }

    final fields = <String, String>{};
    for (final pair in response.split('&')) {
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      fields[pair.substring(0, index).trim().toLowerCase()] =
          pair.substring(index + 1).trim();
    }

    return UpiResult(
      status: _statusOf(fields['status']),
      transactionId: _clean(fields['txnid']),
      transactionRef: _clean(fields['txnref']),
      responseCode: _clean(fields['responsecode']),
      approvalRef: _clean(fields['approvalrefno']),
      raw: response,
    );
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    // Apps return the literal string "null" for absent fields more often than
    // they omit the key.
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }

  static UpiStatus _statusOf(String? raw) => switch (raw?.trim().toUpperCase()) {
    'SUCCESS' => UpiStatus.success,
    'FAILURE' || 'FAILED' => UpiStatus.failure,
    'SUBMITTED' || 'PENDING' => UpiStatus.pending,
    null || '' => UpiStatus.unknown,
    _ => UpiStatus.unknown,
  };
}
