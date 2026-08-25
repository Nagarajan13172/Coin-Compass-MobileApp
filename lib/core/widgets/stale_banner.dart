/// Phase 6.3 — the honesty surface.
///
/// Cached figures presented as live are a false statement about the owner's
/// money, so every screen served from disk has to say so **and say when**.
///
/// ## The rule, written down so seventeen screens cannot drift
///
/// A screen never writes its own staleness copy. It gets [StaleBanner] for free
/// from `AppScaffold`. It adds a [StaleStamp] if and only if it paints a
/// headline figure that can be stale while a sibling on the same screen is
/// fresh. Nothing else.
///
/// [ErrorRetry], [EmptyState] and [LoadingCard] are untouched: this is an
/// additive fourth member of that vocabulary, not a replacement. Crucially a
/// screen served from cache shows its **normal content** plus the marker —
/// never `ErrorRetry`. That swap is the entire point of 6.3.
library;

import '../ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/response_cache.dart';
import '../api/stale_ledger.dart';
import '../theme/app_colors.dart';
import '../utils/date_x.dart';


/// Copy prefix, kept here so the test and the widget cannot disagree.
///
/// "showing figures saved 14m ago" is a claim about the bytes on screen, which
/// is true. A bare "Offline" would be a claim about the network, which this app
/// cannot verify — a captive portal is "connected".
const String kStaleBannerPrefix = 'Offline — showing figures saved ';
const String kStaleBannerSuffix = '. Not live.';

/// The shell strip. One edit in `AppScaffold`, all seventeen screens.
///
/// Deliberately **not dismissible** and not a toast: it must not be swiped away
/// while wrong numbers are still on screen. It disappears by itself the instant
/// the ledger empties — which happens on the first live read that gets through.
class StaleBanner extends ConsumerWidget {
  const StaleBanner({super.key, this.onRetry});

  /// Wired to `refreshCurrentRoute` by the shell, which is the only thing that
  /// knows which route is on screen.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(staleSnapshotProvider);
    final oldest = snapshot.oldestFetchedAt;
    if (!snapshot.anyStale || oldest == null) return const SizedBox.shrink();

    final c = context.colors;
    // The OLDEST stamp, never the newest: understating freshness is safe,
    // overstating it is the lie.
    final when = DateX.relative(oldest);

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.secondary,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(LucideIcons.cloudOff, size: 16, color: c.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$kStaleBannerPrefix$when$kStaleBannerSuffix',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color: c.foreground,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: () => onRetry!.call(),
                style: TextButton.styleFrom(
                  foregroundColor: c.primary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The per-card marker, for the one case where a screen mixes fresh and stale.
///
/// Cards do not know cache keys, so the ledger is keyed by a coarse [StaleTag]
/// that `ResponseCache` derives from the same path table the allow-list is.
/// Renders nothing at all when that area is live.
class StaleStamp extends ConsumerWidget {
  const StaleStamp(this.tag, {super.key});

  final StaleTag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetchedAt = ref.watch(staleTagProvider(tag));
    if (fetchedAt == null) return const SizedBox.shrink();

    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.cloudOff, size: 12, color: c.mutedForeground),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Saved ${DateX.relative(fetchedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: c.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}
