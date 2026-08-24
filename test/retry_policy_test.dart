import 'dart:math';

import 'package:coincompass/core/api/api_exception.dart';
import 'package:coincompass/core/api/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6.3 — the retry schedule.
///
/// Pure Dart, no widget binding, **and nothing sleeps**: both the clock and the
/// delay are injected, so a test that asserts a 12-second budget runs in
/// microseconds.
void main() {
  ApiException offline() => ApiException(
    message: 'No connection. Check your internet and try again.',
    code: 'NO_CONNECTION',
  );

  ApiException timeout() => ApiException(
    message: 'The server took too long to respond. Please try again.',
    code: 'TIMEOUT',
  );

  ApiException status(int code) =>
      ApiException(message: 'boom', statusCode: code);

  /// A deterministic "random" so jitter is exactly 1.0×.
  Random fixedJitter() => _FixedRandom(0.5);

  // ── the predicate ─────────────────────────────────────────────────────────

  group('isRetryable', () {
    test('retries transport failures', () {
      expect(isRetryable(offline()), isTrue);
      expect(isRetryable(timeout()), isTrue);
    });

    test('retries the three gateway statuses and nothing else in 5xx', () {
      expect(isRetryable(status(502)), isTrue);
      expect(isRetryable(status(503)), isTrue);
      expect(isRetryable(status(504)), isTrue);
      // A server exception is deterministic often enough that three of them is
      // just three stack traces in someone's log.
      expect(isRetryable(status(500)), isFalse);
    });

    test('never retries a 4xx, and 429 least of all', () {
      for (final code in const [400, 401, 403, 404, 409, 422, 429]) {
        expect(isRetryable(status(code)), isFalse, reason: '$code');
      }
    });

    test('never retries a cancelled request', () {
      expect(
        isRetryable(ApiException(message: 'cancelled', code: 'CANCELLED')),
        isFalse,
      );
    });
  });

  group('isCacheFallbackEligible', () {
    test('a transport failure or a 5xx may fall back to cache', () {
      expect(isCacheFallbackEligible(offline()), isTrue);
      expect(isCacheFallbackEligible(timeout()), isTrue);
      expect(isCacheFallbackEligible(status(500)), isTrue);
      expect(isCacheFallbackEligible(status(503)), isTrue);
    });

    test('a 4xx never does — it is a real answer from the server', () {
      // Replacing "your session has expired" or "that request was not valid"
      // with 14-minute-old figures is exactly the false statement 6.3 exists
      // to prevent.
      for (final code in const [400, 401, 403, 404, 409, 422, 429]) {
        expect(isCacheFallbackEligible(status(code)), isFalse, reason: '$code');
      }
    });
  });

  // ── the schedule ──────────────────────────────────────────────────────────

  group('the backoff schedule', () {
    test('is exponential from the base delay', () {
      final policy = RetryPolicy(random: fixedJitter());
      expect(
        policy.delayFor(retryIndex: 0, elapsed: Duration.zero),
        const Duration(milliseconds: 400),
      );
      expect(
        policy.delayFor(retryIndex: 1, elapsed: Duration.zero),
        const Duration(milliseconds: 800),
      );
    });

    test('stops after kRetryAttempts', () {
      final policy = RetryPolicy(random: fixedJitter());
      expect(kRetryAttempts, 2);
      expect(policy.delayFor(retryIndex: 2, elapsed: Duration.zero), isNull);
    });

    test('jitter stays inside [0.5, 1.5] of the base', () {
      // Seven dashboard cards firing at once must not re-collide in lockstep
      // three times running.
      for (final factor in const [0.0, 0.25, 0.5, 0.75, 0.999]) {
        final policy = RetryPolicy(random: _FixedRandom(factor));
        final delay = policy.delayFor(
          retryIndex: 0,
          elapsed: Duration.zero,
        )!;
        expect(delay.inMicroseconds, greaterThanOrEqualTo(200 * 1000));
        expect(delay.inMicroseconds, lessThanOrEqualTo(600 * 1000));
      }
    });

    test('the total budget cuts the sequence short', () {
      final policy = RetryPolicy(random: fixedJitter());
      expect(
        policy.delayFor(retryIndex: 0, elapsed: kRetryTotalBudget),
        isNull,
      );
      // Not enough budget left for the delay itself.
      expect(
        policy.delayFor(
          retryIndex: 0,
          elapsed: kRetryTotalBudget - const Duration(milliseconds: 100),
        ),
        isNull,
      );
    });
  });

  // ── the runner ────────────────────────────────────────────────────────────

  group('RetryPolicy.run', () {
    test('sends three times in total on a retryable failure', () async {
      final policy = RetryPolicy(random: fixedJitter());
      final slept = <Duration>[];
      var sends = 0;

      await expectLater(
        policy.run<int>(
          () async {
            sends++;
            throw offline();
          },
          elapsed: () => Duration.zero,
          sleep: (d) async => slept.add(d),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(sends, 3, reason: 'one send plus kRetryAttempts retries');
      expect(slept, const [
        Duration(milliseconds: 400),
        Duration(milliseconds: 800),
      ]);
    });

    test('stops the moment a send succeeds', () async {
      final policy = RetryPolicy(random: fixedJitter());
      var sends = 0;

      final result = await policy.run<String>(
        () async {
          sends++;
          if (sends < 2) throw timeout();
          return 'ok';
        },
        elapsed: () => Duration.zero,
        sleep: (_) async {},
      );

      expect(result, 'ok');
      expect(sends, 2);
    });

    test('does not retry a 4xx at all', () async {
      final policy = RetryPolicy(random: fixedJitter());
      var sends = 0;

      await expectLater(
        policy.run<int>(
          () async {
            sends++;
            throw status(401);
          },
          elapsed: () => Duration.zero,
          sleep: (_) async => fail('a 401 must reach AuthController at once'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sends, 1);
    });

    test('does not retry a 429 — that IS the retry storm', () async {
      final policy = RetryPolicy(random: fixedJitter());
      var sends = 0;
      await expectLater(
        policy.run<int>(
          () async {
            sends++;
            throw status(429);
          },
          elapsed: () => Duration.zero,
          sleep: (_) async => fail('the server asked us to stop'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sends, 1);
    });

    test('a spent budget stops the sequence early', () async {
      final policy = RetryPolicy(random: fixedJitter());
      var sends = 0;
      // The clock is already past the budget when the first failure lands.
      await expectLater(
        policy.run<int>(
          () async {
            sends++;
            throw offline();
          },
          elapsed: () => kRetryTotalBudget + const Duration(seconds: 1),
          sleep: (_) async => fail('budget was already spent'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sends, 1);
    });

    test('a mid-sequence budget overrun stops before the second retry',
        () async {
      final policy = RetryPolicy(random: fixedJitter());
      var sends = 0;
      const elapsedSteps = <Duration>[Duration.zero, kRetryTotalBudget];
      var reads = 0;

      Duration nextElapsed() {
        final index = reads < elapsedSteps.length ? reads : 1;
        reads++;
        return elapsedSteps[index];
      }

      await expectLater(
        policy.run<int>(
          () async {
            sends++;
            throw status(503);
          },
          elapsed: nextElapsed,
          sleep: (_) async {},
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sends, 2, reason: 'first retry allowed, second budgeted out');
    });
  });

  // ── the boundary that keeps writes out ────────────────────────────────────

  test('the connect timeout came down to 8s', () {
    // Three attempts at the old 20s connect timeout is a sixty-second spinner.
    expect(kConnectTimeout, const Duration(seconds: 8));
  });
}

/// Returns the same `nextDouble` every time, so jitter is deterministic.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
