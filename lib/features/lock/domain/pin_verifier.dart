/// PBKDF2-HMAC-SHA256, plus the salt generator and the constant-time compare
/// the app lock verifies a PIN with.
///
/// ## What the KDF is actually for
///
/// Stated plainly, because pretending otherwise would be theatre: a 4-digit PIN
/// is ~10,000 candidates, and anyone who can read this app's SharedPreferences
/// file has already got the `mt_session` cookie sitting next to it, which reads
/// the whole account straight from the API without needing the PIN at all. The
/// KDF does not stop that person.
///
/// What it does buy is real but modest:
///  1. the PIN is not sitting in plaintext in an XML file that a device backup,
///     a bug report or a screenshot of `adb shell run-as` would carry off, and
///  2. people reuse PINs — the same four digits are often a bank card — so this
///     app must not be the thing that leaks one.
///
/// Everything here is a top-level function so it can be handed to `compute()`.
/// This is the only file in the app that imports `package:crypto`.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One PBKDF2 job. Plain data so it can cross an isolate boundary.
class Pbkdf2Request {
  const Pbkdf2Request({
    required this.pin,
    required this.salt,
    required this.iterations,
    this.keyLength = 32,
  });

  final String pin;
  final Uint8List salt;
  final int iterations;
  final int keyLength;
}

/// The default work factor. Persisted per install alongside the verifier so it
/// can be raised later without invalidating a PIN anyone already set.
const int kDefaultPbkdf2Iterations = 120000;

/// 16 bytes, the usual PBKDF2 salt width.
const int kSaltLength = 16;

/// Derives [Pbkdf2Request.keyLength] bytes from the PIN.
///
/// Top-level and synchronous: `compute()` requires exactly this shape.
Uint8List pbkdf2HmacSha256(Pbkdf2Request request) {
  assert(request.iterations > 0, 'iterations must be positive');
  final hmac = Hmac(sha256, utf8.encode(request.pin));
  const hashLength = 32; // SHA-256 output
  final blocks = (request.keyLength + hashLength - 1) ~/ hashLength;
  final out = Uint8List(blocks * hashLength);

  for (var block = 1; block <= blocks; block++) {
    // U1 = HMAC(P, S || INT_BE(i))
    final seed = Uint8List(request.salt.length + 4)
      ..setRange(0, request.salt.length, request.salt);
    final offset = request.salt.length;
    seed[offset] = (block >> 24) & 0xff;
    seed[offset + 1] = (block >> 16) & 0xff;
    seed[offset + 2] = (block >> 8) & 0xff;
    seed[offset + 3] = block & 0xff;

    var u = Uint8List.fromList(hmac.convert(seed).bytes);
    final accumulator = Uint8List.fromList(u);
    for (var round = 1; round < request.iterations; round++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var i = 0; i < hashLength; i++) {
        accumulator[i] ^= u[i];
      }
    }
    out.setRange((block - 1) * hashLength, block * hashLength, accumulator);
  }

  return Uint8List.sublistView(out, 0, request.keyLength);
}

/// Compares without leaking the position of the first differing byte through
/// timing. Costs nothing, so there is no reason not to.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// A fresh per-install salt from the platform CSPRNG.
Uint8List newSalt([int length = kSaltLength]) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// How the derivation is run. The app runs it in an isolate so the ~300ms does
/// not jank the keypad; tests run it inline so no test needs `runAsync`.
abstract class PinHasher {
  const PinHasher();

  Future<Uint8List> derive(Pbkdf2Request request);
}

/// Runs PBKDF2 on the calling isolate. Used by tests (with a low iteration
/// count) and as the fallback anywhere `compute` is unavailable.
class InlinePinHasher extends PinHasher {
  const InlinePinHasher();

  @override
  Future<Uint8List> derive(Pbkdf2Request request) async =>
      pbkdf2HmacSha256(request);
}
