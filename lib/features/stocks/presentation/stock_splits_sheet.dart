import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';
import 'stocks_providers.dart';

/// Corporate actions the server has detected on the book — `GET /stocks/splits`.
///
/// The client only confirms them: applying one goes to
/// `POST /stocks/splits/apply` with the split's `{symbol, date}`, echoed back
/// exactly as it arrived. **There is no `POST /stocks/splits`** — that path
/// 404s, which is why nothing here offers to create one.
class StockSplitsSheet extends ConsumerStatefulWidget {
  const StockSplitsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const StockSplitsSheet(),
    );
  }

  @override
  ConsumerState<StockSplitsSheet> createState() => _StockSplitsSheetState();
}

class _StockSplitsSheetState extends ConsumerState<StockSplitsSheet> {
  /// Splits with an apply in flight, keyed the way the API identifies them.
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final splits = ref.watch(stockSplitsProvider).valueOrNull ?? const [];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Corporate actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                children: [
                  if (splits.isEmpty)
                    Text(
                      'Nothing to apply. Splits show up here after the server '
                      'detects one on a stock you hold.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.mutedForeground,
                      ),
                    )
                  else
                    for (final split in splits)
                      _SplitCard(
                        split: split,
                        busy: _busy.contains(_keyOf(split)),
                        onApply: () => _apply(split),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _keyOf(StockSplit split) => '${split.symbol}-${split.date}';

  /// Immediate and irreversible: it restates every affected lot's quantity.
  Future<void> _apply(StockSplit split) async {
    final label = split.ticker ?? split.symbol;
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Apply the $label split?',
      message:
          'Your ${_plain(split.qtyBefore)} shares become '
          '${_plain(split.qtyAfter)}. What you paid does not change, so your '
          'net worth stays where it is.',
      confirmLabel: 'Apply split',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(_keyOf(split)));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(stocksRepositoryProvider).applySplit(split);
      invalidateStocks(ref);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$label lots adjusted')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _busy.remove(_keyOf(split)));
    }
  }

  static String _plain(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({
    required this.split,
    required this.busy,
    required this.onApply,
  });

  final StockSplit split;
  final bool busy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final day = split.day;
    final ticker = split.ticker ?? split.symbol;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: c.primary.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.split, size: 16, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$ticker had a ${split.label ?? 'stock'} split',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Effective ${day == null ? split.date : DateX.shortDay(day)}. '
                      'Your ${_plain(split.qtyBefore)} shares become '
                      '${_plain(split.qtyAfter)}.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'What you paid does not change, so your net worth will '
                      'not move.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Apply split',
            busy: busy,
            icon: LucideIcons.check,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }

  static String _plain(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// The screen's nudge: one row saying how many corporate actions are waiting,
/// opening [StockSplitsSheet]. Renders nothing when there are none — which is
/// the usual case.
class StockSplitsBanner extends ConsumerWidget {
  const StockSplitsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final splits = ref.watch(stockSplitsProvider).valueOrNull ?? const [];
    if (splits.isEmpty) return const SizedBox.shrink();

    final first = splits.first;
    final subtitle = splits.length == 1
        ? '${first.ticker ?? first.symbol} had a ${first.label ?? 'stock'} split'
        : '${splits.length} splits are waiting to be applied';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: c.primary.withValues(alpha: 0.35),
      onTap: () => StockSplitsSheet.show(context),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius - 2),
            ),
            child: Icon(LucideIcons.split, size: 16, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Corporate action to apply',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: c.mutedForeground),
        ],
      ),
    );
  }
}
