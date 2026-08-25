import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/api/response_cache.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/stale_banner.dart';
import '../../../networth/data/networth_repository.dart';
import '../dashboard_screen.dart';

/// The gradient net-worth hero. Reads the newest `/networth/history` snapshot
/// and falls back to `/reports/summary`'s `netWorth` when that history is empty
/// (a brand-new wallet has no snapshot yet).
class NetWorthCard extends ConsumerWidget {
  const NetWorthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final history = ref.watch(netWorthHistoryProvider);
    final summary = ref.watch(dashboardSummaryProvider);

    final points = history.valueOrNull;
    num? value = (points != null && points.isNotEmpty)
        ? points.last.netWorth
        : null;
    value ??= summary.valueOrNull?.netWorth;

    if (value == null) {
      if (history.isLoading || summary.isLoading) {
        return const LoadingCard();
      }
      final error = history.error ?? summary.error;
      if (error != null) {
        return ErrorRetry(
          error: error,
          compact: true,
          onRetry: () {
            ref.invalidate(netWorthHistoryProvider);
            ref.invalidate(dashboardSummaryProvider);
          },
        );
      }
      value = 0;
    }

    return AppCard(
      // A whisper of primary on the leading edge — the same tint the web app
      // paints behind this card, blended into `card` so it stays opaque.
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.card),
          c.card,
        ],
      ),
      borderColor: c.primary.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Net worth',
                  style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/net-worth'),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Breakdown',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MoneyText(
            value,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Found on the owner's phone during the 6.10 device pass. This
              // used to read "Sum of N accounts", which is not what the figure
              // above it is: net worth is accounts + holdings + stocks MINUS
              // loans. On the owner's own account it printed
              //
              //     −₹2,00,00,000
              //     Sum of 0 accounts
              //
              // and the sum of zero accounts is ₹0 — the −₹2Cr is entirely a
              // loan. A caption that misdescribes a money figure is the exact
              // failure this project cares most about, so it now states what
              // the number IS. It was wrong with accounts too, just less
              // visibly: any holding, stock or loan made the label a lie.
              // The account count belongs on the Accounts card; the full
              // derivation is one tap away behind "Breakdown".
              Flexible(
                child: Text(
                  'Everything you own, minus what you owe',
                  // Two lines since 7.1: Tamil runs up to 173% of the English
                  // width (measured, docs/PHASE7_1_REPORT.md), and on the
                  // device this caption ellipsised mid-word.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ),
              const SizedBox(width: 5),
              Icon(LucideIcons.info, size: 13, color: c.mutedForeground),
            ],
          ),
          // Phase 6.3 — the one card on the dashboard that earns a per-card
          // marker. `/networth/history` fails independently of the metals,
          // accounts and reports reads beside it, so this figure can be hours
          // old while its siblings are live, and the shell banner alone would
          // not say WHICH number is the stale one. Renders nothing at all when
          // net worth is live.
          const StaleStamp(StaleTag.netWorth),
        ],
      ),
    );
  }
}
