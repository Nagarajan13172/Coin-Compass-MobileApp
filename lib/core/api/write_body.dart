/// Helpers for the maps every create/edit sheet POSTs or PATCHes.
///
/// The backend's Zod schemas mark optional fields `optional()`, which accepts a
/// missing key but not always an explicit null. So "nothing to send" and
/// "clear what was there" are different payloads: the first omits the key, the
/// second sends null (or `''` for text). Getting that wrong either fails
/// validation on create or silently keeps a value the user just cleared.
class WriteBody {
  const WriteBody._();

  /// Optional text: trimmed and sent when present, sent as `''` only when it
  /// previously held a value, omitted otherwise.
  static void putText(
    Map<String, dynamic> body,
    String key,
    String raw,
    String? previous,
  ) {
    final value = raw.trim();
    if (value.isNotEmpty) {
      body[key] = value;
    } else if (previous != null && previous.trim().isNotEmpty) {
      body[key] = '';
    }
  }

  /// Optional reference or date: sent when present, sent as null only to clear
  /// a [previous] value, omitted otherwise.
  static void putNullable(
    Map<String, dynamic> body,
    String key,
    Object? value,
    Object? previous,
  ) {
    if (value != null) {
      body[key] = value;
    } else if (previous != null) {
      body[key] = null;
    }
  }
}
