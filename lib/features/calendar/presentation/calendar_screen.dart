import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../reports/presentation/period.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/transaction_form_sheet.dart';
import '../../transactions/presentation/transactions_screen.dart'
    show transactionsMonthProvider;
import '../../transactions/presentation/widgets/transaction_row.dart';
import 'calendar_providers.dart';
import 'widgets/month_grid.dart';
import '../../../core/router/route_refresh.dart';

/// `/calendar` — the month at a glance with a per-day drill-down.
/// Body only; [AppScaffold] supplies the chrome.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(calendarMonthAnchorProvider);
    final selected = ref.watch(calendarSelectedDayProvider);
    final data = ref.watch(calendarMonthProvider(month));
    final settings = ref.watch(settingsProvider).valueOrNull;
    final firstDayOfWeek = PeriodRange.normaliseFirstDayOfWeek(
      settings?.firstDayOfWeek ?? DateTime.monday,
    );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref, month),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          const ScreenHeader(
            title: 'Calendar',
            subtitle: 'Spending day by day',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AppCard(
              child: Column(
                children: [
                  _MonthBar(
                    month: month,
                    onChanged: (next) => _showMonth(ref, next),
                    onToday: () {
                      final now = DateTime.now();
                      _showMonth(ref, now.startOfMonth);
                      ref.read(calendarSelectedDayProvider.notifier).state =
                          now.startOfDay;
                    },
                  ),
                  const SizedBox(height: 10),
                  MonthGrid(
                    month: month,
                    selected: selected,
                    totals: data.valueOrNull?.byDay ?? const {},
                    firstDayOfWeek: firstDayOfWeek,
                    loading: data.isLoading,
                    onSelect: (day) =>
                        ref.read(calendarSelectedDayProvider.notifier).state =
                            day,
                  ),
                  if (data.valueOrNull?.truncated ?? false) ...[
                    const SizedBox(height: 8),
                    Text(
                      'This month has more transactions than the calendar loads; '
                      'day totals may be understated.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (data case AsyncError(:final error))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ErrorRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(calendarMonthProvider(month)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _DayCard(
                day: selected,
                month: month,
                items: data.valueOrNull?.itemsFor(selected) ?? const [],
                totals: data.valueOrNull?.totalsFor(selected),
                loading: data.isLoading,
              ),
            ),
        ],
      ),
    );
  }

  void _showMonth(WidgetRef ref, DateTime month) {
    ref.read(calendarMonthAnchorProvider.notifier).state = month.startOfMonth;
    // Keep the detail card on a day that is actually in view.
    final selected = ref.read(calendarSelectedDayProvider);
    if (selected.year != month.year || selected.month != month.month) {
      final now = DateTime.now();
      ref
          .read(calendarSelectedDayProvider.notifier)
          .state = (now.year == month.year && now.month == month.month)
          ? now.startOfDay
          : month.startOfMonth;
    }
  }

  Future<void> _refresh(WidgetRef ref, DateTime month) =>
      refreshCurrentRoute(ref, '/calendar');
}

/// `August 2026        ‹  Today  ›`
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.onChanged,
    required this.onToday,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            DateX.monthLabel(month),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(month.addMonths(-1)),
          visualDensity: VisualDensity.compact,
          tooltip: tr(context, 'Previous month'),
          icon: const Icon(LucideIcons.chevronLeft, size: 20),
        ),
        TextButton(
          onPressed: onToday,
          style: TextButton.styleFrom(
            foregroundColor: c.foreground,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('Today'),
        ),
        IconButton(
          onPressed: () => onChanged(month.addMonths(1)),
          visualDensity: VisualDensity.compact,
          tooltip: tr(context, 'Next month'),
          icon: const Icon(LucideIcons.chevronRight, size: 20),
        ),
      ],
    );
  }
}

/// The card under the grid: the selected day's in / out / net, its rows, and
/// the two things you can do from there.
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.month,
    required this.items,
    required this.totals,
    required this.loading,
  });

  final DateTime day;
  final DateTime month;
  final List<Transaction> items;
  final DayTotals? totals;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final figures = totals ?? const DayTotals();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateX.dayLabel(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (day.isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'In',
                      amount: figures.income,
                      tone: MoneyTone.income,
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.border),
                  Expanded(
                    child: _Figure(
                      label: 'Out',
                      amount: -figures.expense,
                      tone: MoneyTone.expense,
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.border),
                  Expanded(
                    child: _Figure(
                      label: 'Net',
                      amount: figures.net,
                      tone: MoneyTone.auto,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Transactions',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                loading ? 'Loading…' : 'Nothing logged on this day.',
                style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
              ),
            )
          else
            for (final transaction in items)
              TransactionRow(
                transaction: transaction,
                onTap: () => _edit(context, ref, transaction),
              ),
          const SizedBox(height: 12),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Add on this day'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _openLedger(context, ref),
                tooltip: tr(context, 'View in Transactions'),
                style: IconButton.styleFrom(
                  minimumSize: const Size(46, 46),
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                ),
                icon: const Icon(LucideIcons.arrowRight, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    await showTransactionSheet(context, ref, initialDate: day);
    // The sheet drops the transaction page cache, which the calendar month is
    // built from, so there is nothing else to refresh here.
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) => showTransactionSheet(context, ref, existing: transaction);

  /// The ledger is month-scoped, so it opens on the month being viewed.
  void _openLedger(BuildContext context, WidgetRef ref) {
    ref.read(transactionsMonthProvider.notifier).state = month.startOfMonth;
    context.go('/transactions');
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.tone,
  });

  final String label;
  final num amount;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.mutedForeground)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(
              amount,
              tone: tone,
              signed: true,
              compactAbove: Money.crore,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
