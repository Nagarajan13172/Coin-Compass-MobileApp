/// Phase 7.6 — remembering who a payee is, so the second payment is one tap.
///
/// ## Why this is on the phone and not on the server
///
/// A VPA is the thing money follows. Sending the owner's payee list to a
/// backend that has no field for it would mean inventing storage for the most
/// sensitive string in the feature, on an API this app does not control and
/// cannot change. Kept local, a lost phone loses a convenience; nothing about
/// anyone's payment addresses leaves the device or reaches the network.
///
/// The trade is stated plainly in the sheet: these are remembered on this phone
/// only, and a new phone starts empty.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/upi_request.dart';

class UpiPayeeBook {
  const UpiPayeeBook(this._prefs);

  final SharedPreferences _prefs;

  /// One key per payee rather than a serialised map: a corrupt entry then
  /// costs one payee instead of the whole book.
  static const String _prefix = 'upi.payee.';

  /// Case and spacing folded, so `Chai Kada` and `chai  kada` are one payee —
  /// the same rule `ImportPlan.fold` uses for account names, and for the same
  /// reason: the user does not think of those as two people.
  static String keyFor(String payeeName) =>
      '$_prefix${payeeName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

  /// The VPA remembered for [payeeName], or null.
  ///
  /// Re-validated on read rather than trusted: a value written by an older
  /// build, or edited by hand, must not reach a payment link unchecked.
  Vpa? lookup(String payeeName) {
    if (payeeName.trim().isEmpty) return null;
    return Vpa.tryParse(_prefs.getString(keyFor(payeeName)));
  }

  /// Remembers [vpa] for [payeeName]. A blank name is not stored — there would
  /// be no way to look it up again.
  Future<void> remember(String payeeName, Vpa vpa) async {
    if (payeeName.trim().isEmpty) return;
    await _prefs.setString(keyFor(payeeName), vpa.value);
  }

  Future<void> forget(String payeeName) async {
    await _prefs.remove(keyFor(payeeName));
  }

  /// Every remembered payee, for a future management screen. Names are the folded
  /// form, which is what was stored.
  Map<String, Vpa> all() {
    final out = <String, Vpa>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final vpa = Vpa.tryParse(_prefs.getString(key));
      if (vpa != null) out[key.substring(_prefix.length)] = vpa;
    }
    return out;
  }
}

final upiPayeeBookProvider = FutureProvider<UpiPayeeBook>((ref) async {
  return UpiPayeeBook(await SharedPreferences.getInstance());
});
