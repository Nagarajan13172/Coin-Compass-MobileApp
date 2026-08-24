/// Phase 6.3 — bounded retry, GET-only, transport-and-gateway-only.
///
/// Pure Dart: no Dio, no Flutter, no Riverpod, so it is unit-testable without a
/// widget binding — the precedent `wealth_lock.dart` and `lock_state.dart`
/// already set. Applied **only** in `ApiClient`'s GET path, never inside the
/// shared `_send` body, so no write can accidentally inherit it.
library;

import 'dart:async';
import 'dart:math';

import 'api_exception.dart';


/// Retries after the first send. Three sends total.
const int kRetryAttempts = 2;

/// First backoff step; doubled per retry, then jittered.
const Duration kRetryBaseDelay = Duration(milliseconds: 400);

/// Wall-clock budget measured from the first send.
///
/// Without this, three attempts against a dead network is three connect
/// timeouts back to back — a minute of spinner. When the budget is spent the
/// sequence stops and the request falls over to the cache.
const Duration kRetryTotalBudget = Duration(seconds: 12);

/// **A companion behaviour change for every request in the app, not just
/// cached ones.** A mobile TCP connect that has not completed in 8s will not
/// produce a useful response, and 3 × 20s is indefensible. A genuinely slow but
/// working 2G handshake can exceed this, which would turn a slow success into a
/// failure — one named constant, needs a device measurement before release.
const Duration kConnectTimeout = Duration(seconds: 8);

/// Whether a failed **GET** may be sent again.
///
/// Retryable, and only these:
///   * `NO_CONNECTION` — connectionError / SocketException;
///   * `TIMEOUT` — connect/send/receive timeout;
///   * 502 / 503 / 504 — the box in front of the app was busy.
///
/// Never retryable:
///   * every 4xx **including 429**. A 401 must reach `AuthController`
///     immediately; a 400/422 is a Zod rejection that will be identical next
///     time; a 429 is the server asking us to stop, and retrying it *is* the
///     retry storm;
///   * 500. A server exception is deterministic often enough that three of them
///     is just three stack traces in someone's log. Only the gateway-shaped
///     502/503/504 count;
///   * `CANCELLED`.
bool isRetryable(ApiException error) {
  if (error.code == 'CANCELLED') return false;
  final status = error.statusCode;
  if (status != null) {
    return status == 502 || status == 503 || status == 504;
  }
  return error.code == 'NO_CONNECTION' || error.code == 'TIMEOUT';
}

/// Whether a failed GET may fall over to a cached body.
///
/// **Deliberately narrower than "any failure".** A 4xx is a real answer from
/// the server: replacing "your session has expired" or "that request was not
/// valid" with 14-minute-old figures would be exactly the false statement 6.3
/// exists to prevent. A 500 is included because a broken server is the same
/// situation as an unreachable one from the owner's point of view.
bool isCacheFallbackEligible(ApiException error) {
  if (error.code == 'CANCELLED') return false;
  final status = error.statusCode;
  if (status != null) return status >= 500;
  return error.code == 'NO_CONNECTION' || error.code == 'TIMEOUT';
}

/// The jittered exponential schedule, and the runner that applies it.
///
/// Both the clock and the sleep are injectable so a test can assert the delays
/// without anything actually sleeping.
class RetryPolicy {
  RetryPolicy({
    this.attempts = kRetryAttempts,
    this.baseDelay = kRetryBaseDelay,
    this.totalBudget = kRetryTotalBudget,
    Random? random,
  }) : _random = random ?? Random();

  final int attempts;
  final Duration baseDelay;
  final Duration totalBudget;
  final Random _random;

  /// How long to wait before retry number [retryIndex] (0-based), or null when
  /// the sequence must stop.
  ///
  /// Jitter is a factor in [0.5, 1.5] so seven dashboard cards firing at once
  /// do not re-collide in lockstep three times running.
  Duration? delayFor({required int retryIndex, required Duration elapsed}) {
    if (retryIndex >= attempts) return null;
    if (elapsed >= totalBudget) return null;

    final base = baseDelay.inMicroseconds * pow(2, retryIndex).toInt();
    final factor = 0.5 + _random.nextDouble();
    final jittered = Duration(microseconds: (base * factor).round());

    if (elapsed + jittered >= totalBudget) return null;
    return jittered;
  }

  /// Sends, and re-sends while [isRetryable] and the schedule allows it.
  ///
  /// [elapsed] and [sleep] default to a real stopwatch and a real delay; a test
  /// injects both and nothing sleeps.
  Future<T> run<T>(
    Future<T> Function() send, {
    Duration Function()? elapsed,
    Future<void> Function(Duration)? sleep,
    void Function(Duration delay)? onRetry,
  }) async {
    final watch = elapsed == null ? (Stopwatch()..start()) : null;
    Duration read() => elapsed?.call() ?? watch!.elapsed;
    final wait = sleep ?? Future<void>.delayed;

    var retryIndex = 0;
    while (true) {
      try {
        return await send();
      } on ApiException catch (error) {
        if (!isRetryable(error)) rethrow;
        final delay = delayFor(retryIndex: retryIndex, elapsed: read());
        if (delay == null) rethrow;
        retryIndex++;
        onRetry?.call(delay);
        await wait(delay);
      }
    }
  }
}
