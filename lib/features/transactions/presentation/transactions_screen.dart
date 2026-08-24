import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/month_pager.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';
import 'transaction_form_sheet.dart';
import 'transactions_providers.dart';
import 'widgets/quick_add_row.dart';
import 'widgets/transaction_filters.dart';
import 'widgets/transaction_row.dart';
import '../../../core/router/route_refresh.dart';

// The month the ledger is showing now lives beside the query it seeds, in
// transactions_providers.dart. It is re-exported here because the calendar
// screen drives the ledger's month and imports it from this library.
export 'transactions_providers.dart' show transactionsMonthProvider;

/// `/transactions` — the ledger, grouped by day with a per-day net and an
/// end-of-day running balance. Body only: [AppScaffold] supplies the chrome.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  /// Mirrors "is there text in the search box" so the clear button can appear
  /// without rebuilding anything but itself.
  final ValueNotifier<bool> _hasSearchText = ValueNotifier<bool>(false);

  /// Built once and reused on every rebuild. Handing the same instance back
  /// makes `Element.updateChild` skip the whole header subtree, so a query
  /// change repaints the rows without touching the search box, the filters or
  /// the quick-add chips. Everything inside it that *does* move with a
  /// provider watches that provider itself.
  late final Widget _header = _TransactionsHeader(
    searchController: _search,
    hasSearchText: _hasSearchText,
    onSearchChanged: _onSearchChanged,
    onAdd: _openSheet,
    onMonthChanged: _onMonthChanged,
    onPickMonth: _pickMonth,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // The query is already stamped with the current month (see
    // `transactionQueryProvider`), so the box only has to be seeded from
    // whatever search survived the last visit.
    _search.text = ref.read(transactionQueryProvider).search ?? '';
    _hasSearchText.value = _search.text.isNotEmpty;
    // …but another screen can have moved the month while we were away — the
    // calendar's "open ledger" sets it and navigates here. Re-stamp it on
    // mount, off the build phase because a provider may not be written during
    // it. An unchanged month is a no-op all the way down: `applyQuery` bails
    // on an equal query, so nothing refetches.
    Future.microtask(() {
      if (!mounted) return;
      _applyMonth(ref.read(transactionsMonthProvider));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    _hasSearchText.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(transactionsListProvider.notifier).loadMore();
    }
  }

  void _setQuery(TransactionQuery Function(TransactionQuery query) update) {
    final current = ref.read(transactionQueryProvider);
    ref.read(transactionQueryProvider.notifier).state = update(
      current,
    ).firstPage();
  }

  void _applyMonth(DateTime month) => _setQuery(
    (query) => query.copyWith(from: month.startOfMonth, to: month.endOfMonth),
  );

  void _onMonthChanged(DateTime month) {
    ref.read(transactionsMonthProvider.notifier).state = month.startOfMonth;
    _applyMonth(month);
  }

  void _onSearchChanged(String value) {
    _hasSearchText.value = value.isNotEmpty;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final text = value.trim();
      _setQuery(
        (query) => text.isEmpty
            ? query.copyWith(clearSearch: true)
            : query.copyWith(search: text),
      );
    });
  }

  Future<void> _refresh() => refreshCurrentRoute(ref, '/transactions');

  /// The sheet resolves to the saved row (null when dismissed or deleted), and
  /// leaves reconciliation to us — so we place it optimistically, or drop it
  /// when an edit moved it outside the window the list is showing.
  Future<void> _openSheet({Transaction? existing}) async {
    final saved = await showTransactionSheet(context, ref, existing: existing);
    if (saved == null || !mounted) return;

    final query = ref.read(transactionQueryProvider);
    final controller = ref.read(transactionsListProvider.notifier);
    final date = saved.date ?? saved.createdAt;
    final visible =
        date == null ||
        ((query.from == null || !date.isBefore(query.from!)) &&
            (query.to == null || !date.isAfter(query.to!)));

    if (existing != null) {
      if (visible) {
        controller.updateLocal(saved);
      } else {
        controller.deleteLocal(saved.id);
      }
    } else if (visible) {
      controller.insertLocal(saved);
    }
  }

  Future<void> _pickMonth(DateTime current) async {
    var year = current.year;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final c = context.colors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setSheetState(() => year -= 1),
                        icon: const Icon(LucideIcons.chevronLeft, size: 20),
                      ),
                      Expanded(
                        child: Text(
                          '$year',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setSheetState(() => year += 1),
                        icon: const Icon(LucideIcons.chevronRight, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (var month = 1; month <= 12; month++)
                        _MonthCell(
                          label: _monthNames[month - 1],
                          selected:
                              year == current.year && month == current.month,
                          onTap: () =>
                              Navigator.of(context).pop(DateTime(year, month)),
                          colors: c,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked != null) _onMonthChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final month = ref.watch(transactionsMonthProvider);
    final state = ref.watch(transactionsListProvider);
    final query = ref.watch(transactionQueryProvider);
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];

    // A type / category / tag / one-off / search filter hides movements that
    // still moved the balance, so a running total rolled back over what is
    // left would be wrong on every day but the newest. The web app drops the
    // end-of-day footers in exactly that case, and so do we. An account filter
    // is fine: its rollback is over that account's own rows.
    final restrictive =
        query.type != null ||
        query.categoryId != null ||
        query.tag != null ||
        query.oneoff != null ||
        (query.search?.trim().isNotEmpty ?? false);

    // Seeded from the balance as it stood at the END of the window on screen,
    // not from today's — otherwise every month but the current one starts its
    // rollback from the wrong number.
    final snapshot = restrictive
        ? null
        : ref.watch(transactionBalanceAsOfProvider(query.to)).valueOrNull;

    final accountId = query.accountId;
    final account = _findAccount(accounts, accountId);
    // `query.hasFilters` counts the month window itself, which is always set —
    // so it would call every empty month "filtered". Only a filter the user
    // actually chose counts here.
    final filtered = restrictive || accountId != null;
    final startBalance = snapshot == null
        ? null
        : (accountId == null
              ? snapshot.balance
              : (snapshot.byAccount[accountId] ?? 0));

    final entries = _buildEntries(
      groupTransactionsByDay(state.items),
      startBalance: startBalance,
      accountId: accountId,
      accountLabel: account?.name ?? 'All accounts',
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      color: c.primary,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverToBoxAdapter(child: _header),
          ),
          if (state.isInitialLoad)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _LoadingList()),
            )
          else if (state.hasError && state.isEmpty)
            SliverToBoxAdapter(
              child: ErrorRetry(
                error: state.error!,
                onRetry: () =>
                    ref.read(transactionsListProvider.notifier).refresh(),
              ),
            )
          else if (state.showEmptyState)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.receipt,
                title: 'No transactions yet',
                message: filtered
                    ? 'Nothing matches these filters in ${DateX.monthLabel(month)}.'
                    : 'Log your first one and it shows up here.',
                actionLabel: 'Add transaction',
                onAction: _openSheet,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _entryWidget(context, entries[index]),
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              loadingMore: state.loadingMore,
              error: state.hasError && !state.isEmpty
                  ? state.errorMessage
                  : null,
              onRetry: () =>
                  ref.read(transactionsListProvider.notifier).loadMore(),
              bottomInset: MediaQuery.paddingOf(context).bottom + 96,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryWidget(BuildContext context, _Entry entry) {
    return switch (entry) {
      _DayHeaderEntry(:final day, :final net) => _DayHeader(day: day, net: net),
      _TransactionEntry(:final transaction) => TransactionRow(
        key: ValueKey(transaction.id),
        transaction: transaction,
        onTap: () => _openSheet(existing: transaction),
      ),
      _DayFooterEntry(:final balance, :final label) => _DayFooter(
        balance: balance,
        label: label,
      ),
    };
  }
}

// ─── header ────────────────────────────────────────────────────────────────

/// Everything above the ledger. The screen holds one instance of this and
/// hands the same one back on every rebuild, so a new page of rows — or a whole
/// new query — never repaints the search box (which would drop the caret) or
/// re-runs the filter dropdowns. The two pieces that do move with state watch
/// their own provider.
class _TransactionsHeader extends StatelessWidget {
  const _TransactionsHeader({
    required this.searchController,
    required this.hasSearchText,
    required this.onSearchChanged,
    required this.onAdd,
    required this.onMonthChanged,
    required this.onPickMonth,
  });

  final TextEditingController searchController;
  final ValueListenable<bool> hasSearchText;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAdd;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onPickMonth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transactions',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const _HeaderSubtitle(),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add',
            icon: LucideIcons.plus,
            expand: false,
            onPressed: onAdd,
          ),
        ),
        const SizedBox(height: 20),
        const QuickAddRow(),
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, _) {
            final month = ref.watch(transactionsMonthProvider);
            return MonthPager(
              month: month,
              onChanged: onMonthChanged,
              onPick: () => onPickMonth(month),
            );
          },
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: hasSearchText,
          builder: (context, hasText, _) => AppTextField(
            controller: searchController,
            hint: 'Filter this list by note, payee, or tag...',
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            prefix: Icon(
              LucideIcons.search,
              size: 18,
              color: c.mutedForeground,
            ),
            suffix: !hasText
                ? null
                : IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 17,
                      color: c.mutedForeground,
                    ),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        const TransactionFilters(),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// "12 transactions · August 2026" — but only once the count belongs to the
/// month beside it. While a window is loading the count is either stale or
/// zero, so the label drops it rather than pairing a new month with an old
/// total. A failed window drops it for the same reason and a stronger one:
/// `total` is 0 there because nothing arrived, and "0 transactions" over an
/// ErrorRetry states as fact something the app does not know.
class _HeaderSubtitle extends ConsumerWidget {
  const _HeaderSubtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final month = ref.watch(transactionsMonthProvider);
    final (loading, failed, count) = ref.watch(
      transactionsListProvider.select(
        (state) => (state.loading, state.hasError, state.total),
      ),
    );

    final label = DateX.monthLabel(month);
    return Text(
      loading || failed
          ? label
          : '$count transaction${count == 1 ? '' : 's'} · $label',
      style: TextStyle(fontSize: 15, color: c.mutedForeground),
    );
  }
}

// ─── flattened list model ──────────────────────────────────────────────────

sealed class _Entry {
  const _Entry();
}

class _DayHeaderEntry extends _Entry {
  const _DayHeaderEntry(this.day, this.net);
  final DateTime day;
  final num net;
}

class _TransactionEntry extends _Entry {
  const _TransactionEntry(this.transaction);
  final Transaction transaction;
}

class _DayFooterEntry extends _Entry {
  const _DayFooterEntry(this.balance, this.label);
  final num balance;
  final String label;
}

/// Day header → rows → end-of-day balance, oldest day last.
///
/// The running balance is rolled *backwards* from [startBalance] — the
/// `/transactions/balance?asOf=` figure for the end of the window on screen:
/// the newest visible day ends on it, and each older day ends on that minus
/// the newer day's movements. Rows with no account (recurring stubs, notes)
/// never move a balance. A null [startBalance] means the caller could not
/// produce an honest one, and no end-of-day rows are emitted at all.
List<_Entry> _buildEntries(
  List<TransactionDayGroup> groups, {
  required num? startBalance,
  required String? accountId,
  required String accountLabel,
}) {
  final entries = <_Entry>[];
  var running = startBalance;
  for (final group in groups) {
    entries.add(_DayHeaderEntry(group.day, group.net));
    for (final transaction in group.items) {
      entries.add(_TransactionEntry(transaction));
    }
    if (running != null) {
      entries.add(_DayFooterEntry(running, accountLabel));
      running = running - _accountDelta(group.items, accountId);
    }
  }
  return entries;
}

Account? _findAccount(List<Account> accounts, String? id) {
  if (id == null) return null;
  for (final account in accounts) {
    if (account.id == id) return account;
  }
  return null;
}

num _accountDelta(List<Transaction> items, String? accountId) {
  num delta = 0;
  for (final transaction in items) {
    if (accountId == null) {
      // Across every account a transfer nets to zero, and a row with no
      // account attached never touched a balance at all.
      if (transaction.accountId == null) continue;
      if (transaction.type == TransactionType.income) {
        delta += transaction.amount;
      } else if (transaction.type == TransactionType.expense) {
        delta -= transaction.amount;
      }
    } else {
      if (transaction.accountId == accountId) {
        delta += transaction.type == TransactionType.income
            ? transaction.amount
            : -transaction.amount;
      }
      if (transaction.toAccountId == accountId) delta += transaction.amount;
    }
  }
  return delta;
}

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// ─── pieces ────────────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.net});

  final DateTime day;
  final num net;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = net > 0
        ? MoneyTone.income
        : (net < 0 ? MoneyTone.expense : MoneyTone.muted);
    final color = net > 0
        ? c.income
        : (net < 0 ? c.expense : c.mutedForeground);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Net ',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              MoneyText(
                net,
                tone: tone,
                signed: true,
                compactAbove: Money.crore,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: c.border),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _DayFooter extends StatelessWidget {
  const _DayFooter({required this.balance, required this.label});

  final num balance;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = TextStyle(fontSize: 12.5, color: c.mutedForeground);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashedRule(color: c.border),
          const SizedBox(height: 8),
          Text('End of day', style: muted),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: Text(label, style: muted)),
              MoneyText(
                balance,
                compactAbove: Money.crore,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The hairline above the end-of-day row, dashed exactly like the web app's.
class _DashedRule extends StatelessWidget {
  const _DashedRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashes = (constraints.maxWidth / 7).floor().clamp(1, 200);
        return Row(
          children: [
            for (var i = 0; i < dashes; i++)
              Expanded(
                child: Container(
                  height: 1,
                  color: i.isEven ? color : Colors.transparent,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius);
    return Material(
      color: selected ? colors.primary : colors.card,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.primary : colors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: selected ? colors.primaryForeground : colors.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        LoadingCard(lines: 2),
        SizedBox(height: 10),
        LoadingCard(lines: 2),
        SizedBox(height: 10),
        LoadingCard(lines: 2),
        SizedBox(height: 10),
        LoadingCard(lines: 2),
      ],
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loadingMore,
    required this.error,
    required this.onRetry,
    required this.bottomInset,
  });

  final bool loadingMore;
  final String? error;
  final VoidCallback onRetry;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: 16, bottom: bottomInset),
      child: Column(
        children: [
          if (loadingMore)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          if (!loadingMore && error != null) ...[
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
            const SizedBox(height: 6),
            AppButton(
              label: 'Try again',
              variant: AppButtonVariant.text,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
