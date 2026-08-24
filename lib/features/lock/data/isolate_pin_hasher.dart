import 'package:flutter/foundation.dart';

import '../domain/pin_verifier.dart';

/// Runs PBKDF2 on a background isolate.
///
/// The work factor is deliberately in the hundreds of milliseconds, which is
/// long enough to drop frames on the keypad's tap ripple if it ran on the UI
/// isolate. `compute` spawns, runs and tears down — fine for something that
/// happens once per unlock.
class IsolatePinHasher extends PinHasher {
  const IsolatePinHasher();

  @override
  Future<Uint8List> derive(Pbkdf2Request request) =>
      compute(pbkdf2HmacSha256, request);
}
