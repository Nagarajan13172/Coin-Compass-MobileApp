import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/report_models.dart';
import '../reports_providers.dart';

/// "By account" — money in vs out per account, as a list rather than a chart
/// (`GZ`, bundle offset 1019028).
///
/// This owner has **no accounts**, so the live response is `[]` and this card
/// renders its empty state every time. That is the shape it has to look right
/// in first; a populated list is the rarer case here.
class ByAccountCard extends ConsumerWidget {
  const ByAccountCard({super.key, required this.onOpenAccount});

  final ValueChanged<String> onOpenAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportsRangeProvider);
    final accounts = ref.watch(reportsByAccountProvider(range));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'By account',
            subtitle: 'Money in vs out per account',
          ),
          accounts.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LoadingCard(lines: 3),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(reportsByAccountProvider(range)),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: EmptyState(
                      icon: LucideIcons.wallet,
                      // The owner has zero accounts, so this is the normal
                      // case, not an edge case — it says what to do about it
                      // rather than reporting "No data".
                      title: 'No account activity yet',
                      message:
                          'Money moves through an account once you have one '
                          'set up.',
                      compact: true,
                    ),
                  )
                : _List(rows: rows, onOpenAccount: onOpenAccount),
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.rows, required this.onOpenAccount});

  final List<AccountSlice> rows;
  final ValueChanged<String> onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One shared scale across every row, so two accounts' bars are comparable.
    // Floored at 1 so an all-zero window divides by something.
    final peak = rows.fold<double>(
      1,
      (best, row) => math.max(
        best,
        math.max(row.moneyIn.toDouble(), row.moneyOut.toDouble()),
      ),
    );

    return Column(
      children: [
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.border),
          _Row(
            row: rows[i],
            peak: peak,
            onTap: () => onOpenAccount(rows[i].accountId),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.peak, required this.onTap});

  final AccountSlice row;
  final double peak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final net = row.net;
    final accent = colorFromHex(row.color) ?? c.primary;

    return Semantics(
      button: true,
      label: 'View ${row.name} transactions',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(
                    net,
                    signed: true,
                    tone: net < 0 ? MoneyTone.expense : MoneyTone.income,
                    compactAbove: Money.crore,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _Bar(label: 'In', value: row.moneyIn, peak: peak, color: c.income),
              const SizedBox(height: 6),
              _Bar(
                label: 'Out',
                value: row.moneyOut,
                peak: peak,
                color: c.expense,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.peak,
    required this.color,
  });

  final String label;
  final num value;
  final double peak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = peak <= 0 ? 0.0 : (value.toDouble() / peak).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 26,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: c.mutedForeground,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              // The web floors the fill at 2% so a tiny-but-real amount still
              // shows; a genuine zero stays empty.
              value: value <= 0 ? 0 : math.max(0.02, share),
              minHeight: 7,
              backgroundColor: c.muted,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Fixed, right-aligned and compacted past a crore: a nine-figure
        // balance here would otherwise squeeze the bar out of existence.
        SizedBox(
          width: 82,
          child: Align(
            alignment: Alignment.centerRight,
            child: MoneyText(
              value,
              tone: MoneyTone.muted,
              compactAbove: Money.crore,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}
