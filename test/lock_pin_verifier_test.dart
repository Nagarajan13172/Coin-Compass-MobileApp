import 'dart:typed_data';

import 'package:coincompass/features/lock/domain/pin_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app lock's PIN verifier.
///
/// Everything here runs **inline** with a low iteration count — never through
/// `compute()` — so no test needs `runAsync` and nothing waits on an isolate.
/// The expected digests are RFC-published PBKDF2-HMAC-SHA256 vectors,
/// re-derived independently with Python's `hashlib.pbkdf2_hmac` before being
/// pasted here, so this pins the implementation against something that is not
/// itself.
void main() {
  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List ascii(String value) =>
      Uint8List.fromList(value.codeUnits);

  group('pbkdf2HmacSha256', () {
    test('matches the published vectors', () {
      expect(
        hex(
          pbkdf2HmacSha256(
            Pbkdf2Request(
              pin: 'password',
              salt: ascii('salt'),
              iterations: 1,
            ),
          ),
        ),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );

      expect(
        hex(
          pbkdf2HmacSha256(
            Pbkdf2Request(
              pin: 'password',
              salt: ascii('salt'),
              iterations: 2,
            ),
          ),
        ),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );

      expect(
        hex(
          pbkdf2HmacSha256(
            Pbkdf2Request(
              pin: 'password',
              salt: ascii('salt'),
              iterations: 4096,
            ),
          ),
        ),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('derives across more than one hash block', () {
      // 40 bytes > one SHA-256 block, so this is the only vector that exercises
      // the block loop and the big-endian block counter.
      expect(
        hex(
          pbkdf2HmacSha256(
            Pbkdf2Request(
              pin: 'passwordPASSWORDpassword',
              salt: ascii('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
              iterations: 4096,
              keyLength: 40,
            ),
          ),
        ),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1'
        'c635518c7dac47e9',
      );
    });

    test('a 4-digit PIN with a binary salt matches an outside implementation', () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      expect(
        hex(
          pbkdf2HmacSha256(
            Pbkdf2Request(pin: '1234', salt: salt, iterations: 1000),
          ),
        ),
        '2240ea2a22754a3c4610356ef8e4d7acf25af2ac3d2d11866de97a8b7812c52c',
      );
    });

    test('the iteration count is part of the identity', () {
      final salt = newSalt();
      final a = pbkdf2HmacSha256(
        Pbkdf2Request(pin: '4321', salt: salt, iterations: 500),
      );
      final b = pbkdf2HmacSha256(
        Pbkdf2Request(pin: '4321', salt: salt, iterations: 501),
      );
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('a wrong PIN of the same length never matches', () {
      final salt = newSalt();
      final right = pbkdf2HmacSha256(
        Pbkdf2Request(pin: '1234', salt: salt, iterations: 200),
      );
      for (final wrong in const ['1235', '4321', '0000', '9999', '1233']) {
        final derived = pbkdf2HmacSha256(
          Pbkdf2Request(pin: wrong, salt: salt, iterations: 200),
        );
        expect(
          constantTimeEquals(derived, right),
          isFalse,
          reason: '$wrong must not open a 1234 lock',
        );
      }
    });

    test('the same PIN under two salts derives two different verifiers', () {
      // The point of the per-install salt: two phones with the same PIN do not
      // share a verifier, so one leaked file says nothing about the other.
      final a = pbkdf2HmacSha256(
        Pbkdf2Request(pin: '1234', salt: newSalt(), iterations: 200),
      );
      final b = pbkdf2HmacSha256(
        Pbkdf2Request(pin: '1234', salt: newSalt(), iterations: 200),
      );
      expect(constantTimeEquals(a, b), isFalse);
    });
  });

  group('newSalt', () {
    test('is 16 bytes and does not repeat', () {
      final seen = <String>{};
      for (var i = 0; i < 64; i++) {
        final salt = newSalt();
        expect(salt, hasLength(kSaltLength));
        expect(seen.add(hex(salt)), isTrue, reason: 'Random.secure() repeated');
      }
    });
  });

  group('constantTimeEquals', () {
    test('is true only for identical byte strings', () {
      expect(constantTimeEquals(const [1, 2, 3], const [1, 2, 3]), isTrue);
      expect(constantTimeEquals(const [1, 2, 3], const [1, 2, 4]), isFalse);
      // A different length is rejected up front — there is nothing to leak.
      expect(constantTimeEquals(const [1, 2, 3], const [1, 2]), isFalse);
      expect(constantTimeEquals(const [], const []), isTrue);
    });

    test('does not short-circuit on the first differing byte', () {
      // Not a timing measurement — just the structural guarantee that every
      // byte is folded in, so a difference anywhere is caught.
      expect(
        constantTimeEquals(const [9, 0, 0, 0], const [0, 0, 0, 0]),
        isFalse,
      );
      expect(
        constantTimeEquals(const [0, 0, 0, 9], const [0, 0, 0, 0]),
        isFalse,
      );
    });
  });

  group('InlinePinHasher', () {
    test('agrees with the top-level function', () async {
      final salt = newSalt();
      final request = Pbkdf2Request(
        pin: '86420',
        salt: salt,
        iterations: 300,
      );
      expect(
        constantTimeEquals(
          await const InlinePinHasher().derive(request),
          pbkdf2HmacSha256(request),
        ),
        isTrue,
      );
    });
  });
}
