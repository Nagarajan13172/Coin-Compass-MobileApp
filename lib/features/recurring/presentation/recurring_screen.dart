import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../data/recurring_repository.dart';
import '../domain/recurring_rule.dart';
import 'recurring_form_sheet.dart';
import 'recurring_history_sheet.dart';
import 'widgets/recurring_tile.dart';
import '../../../core/router/route_refresh.dart';

/// `/recurring` — the rules that post transactions on a schedule, what they
/// come to per month, and the controls to run, skip or pause them.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  /// Rules with an action in flight — the row swaps its menu for a spinner.
  ///
  /// 6.4: only the three *unpredictable* actions still fill this — run, skip
  /// and post-one. The edit, the pause/resume toggle and the delete repaint
  /// at once and never spin.
  final Set<String> _busyIds = {};

  bool _runningDue = false;

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(recurringRulesProvider);
    final due = rules.valueOrNull?.where(_isDue).length ?? 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          ScreenHeader(
            title: 'Recurring',
            subtitle:
                'Automatically post rent, salary, subscriptions and other regular transactions.',
            actions: [
              ScreenHeaderAction(
                label: _runningDue
                    ? 'Running…'
                    : (due == 0 ? 'Run due' : 'Run due ($due)'),
                icon: LucideIcons.refreshCw,
                primary: false,
                onPressed: _runningDue || due == 0 ? null : _runDue,
              ),
              ScreenHeaderAction(
                label: 'New rule',
                icon: LucideIcons.plus,
                onPressed: () => RecurringFormSheet.show(context),
              ),
            ],
          ),
          switch (rules) {
            AsyncData(:final value) when value.isEmpty => _EmptyRules(
              onAdd: () => RecurringFormSheet.show(context),
            ),
            AsyncData(:final value) => _RuleList(
              rules: value,
              busyIds: _busyIds,
              onAction: _handleAction,
              onEdit: (rule) => RecurringFormSheet.show(context, rule: rule),
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(recurringRulesFetchProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 2),
                  SizedBox(height: 12),
                  LoadingCard(lines: 2),
                  SizedBox(height: 12),
                  LoadingCard(lines: 2),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }

  Future<void> _refresh() => refreshCurrentRoute(ref, '/recurring');

  static bool _isDue(RecurringRule rule) =>
      rule.active &&
      rule.nextRun != null &&
      !rule.nextRun!.isAfter(DateTime.now());

  Future<void> _handleAction(RecurringRule rule, RecurringAction action) async {
    switch (action) {
      case RecurringAction.run:
        await _perform(
          rule,
          (repository) => repository.run(rule.id),
          done: (result) => result.posted == null
              ? 'Ran ${rule.title}'
              : 'Posted ${result.posted} from ${rule.title}',
        );
      case RecurringAction.postOne:
        await _perform(
          rule,
          (repository) => repository.postOne(rule.id),
          done: (_) => 'Posted one ${rule.title}',
        );
      case RecurringAction.skip:
        await _perform(
          rule,
          (repository) => repository.skip(rule.id),
          done: (_) => 'Skipped the next ${rule.title}',
          posts: false,
        );
      case RecurringAction.toggleActive:
        _setActive(rule, active: !rule.active);
      case RecurringAction.history:
        await RecurringHistorySheet.show(context, rule: rule);
      case RecurringAction.edit:
        await RecurringFormSheet.show(context, rule: rule);
      case RecurringAction.delete:
        await _delete(rule);
    }
  }

  /// Runs one rule action, keeping the row spinning until it lands and telling
  /// the ledger to reload when the action posted something.
  ///
  /// **Deliberately synchronous (6.4).** `/recurring/:id/run`, `/skip` and
  /// `/post-one` are the three mutations on this screen whose result the client
  /// cannot predict: the server decides how many occurrences post, which
  /// transactions they become, and where `nextRun` lands. Painting a guess here
  /// would put a schedule the server owns on screen as if it were fact. The
  /// rule's own `{active}` PATCH *is* optimistic — see [_setActive] — because
  /// that one is a flag the client sent. Do not "fix" this by routing it
  /// through `OptimisticCollection`.
  Future<void> _perform(
    RecurringRule rule,
    Future<RecurringRunResult> Function(RecurringRepository repository)
    action, {
    required String Function(RecurringRunResult result) done,
    bool posts = true,
  }) async {
    if (_busyIds.contains(rule.id)) return;
    setState(() => _busyIds.add(rule.id));

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await action(ref.read(recurringRepositoryProvider));
      ref.invalidate(recurringRulesFetchProvider);
      ref.invalidate(recurringHistoryProvider(rule.id));
      if (posts) _refreshLedger();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done(result))));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ApiException.from(error).message)),
        );
    } finally {
      if (mounted) setState(() => _busyIds.remove(rule.id));
    }
  }

  /// Pause / resume. 6.4 — this is the one action on this screen the client can
  /// predict: it is a `PATCH` with `{active}` and nothing else, and
  /// `RecurringRule.predictActive` nulls the schedule the server recomputes, so
  /// the tile drops its "Next …" line rather than showing a stale date.
  void _setActive(RecurringRule rule, {required bool active}) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(recurringRepositoryProvider);
    final predicted = rule.predictActive(active);

    unawaited(
      container
          .read(recurringWritesProvider.notifier)
          .run<RecurringRule>(
            paint: predicted == null ? null : PendingWrite.upsert(predicted),
            send: () => repository.update(rule.id, {'active': active}),
            confirm: (saved) => saved,
            settle: () => settleRecurring(container),
            messenger: messenger,
            noun: rule.title,
            successMessage: active
                ? 'Resumed ${rule.title}'
                : 'Paused ${rule.title}',
          ),
    );
  }

  Future<void> _delete(RecurringRule rule) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${rule.title}?',
      message:
          'It stops posting from now on. Transactions it already posted are kept.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a rule. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(recurringRepositoryProvider);

    unawaited(
      container
          .read(recurringWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(rule.id),
            send: () => repository.delete(rule.id),
            settle: () => settleRecurring(container),
            messenger: messenger,
            noun: rule.title,
            successMessage: 'Deleted ${rule.title}',
          ),
    );
  }

  /// The backend has no bulk endpoint, so "Run due" is every due rule run in
  /// turn. One failure doesn't stop the rest; the snackbar reports the tally.
  ///
  /// **Deliberately synchronous (6.4)**, for the same reason as [_perform]: the
  /// server decides what each run posts and where each rule's `nextRun` lands.
  Future<void> _runDue() async {
    final rules = ref.read(recurringRulesProvider).valueOrNull ?? const [];
    final due = rules.where(_isDue).toList();
    if (due.isEmpty) return;

    setState(() => _runningDue = true);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(recurringRepositoryProvider);

    var ran = 0;
    var posted = 0;
    String? failure;

    for (final rule in due) {
      try {
        final result = await repository.run(rule.id);
        ran++;
        posted += result.posted ?? 0;
      } catch (error) {
        failure ??= ApiException.from(error).message;
      }
    }

    ref.invalidate(recurringRulesFetchProvider);
    _refreshLedger();
    if (!mounted) return;
    setState(() => _runningDue = false);

    final summary = ran == 0
        ? (failure ?? 'Nothing was posted')
        : 'Ran $ran ${ran == 1 ? 'rule' : 'rules'}'
              '${posted > 0 ? ' · $posted posted' : ''}'
              '${failure == null ? '' : ' · some failed'}';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(summary)));
  }

  /// A posted occurrence is a new transaction, so every ledger read is stale.
  void _refreshLedger() {
    final container = ProviderScope.containerOf(context, listen: false);
    container
      ..invalidate(transactionBalanceProvider)
      ..invalidate(transactionsPageProvider);
    if (container.exists(transactionsListProvider)) {
      container.read(transactionsListProvider.notifier).refresh();
    }
  }
}

class _EmptyRules extends StatelessWidget {
  const _EmptyRules({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DashedBox(
        child: EmptyState(
          icon: LucideIcons.repeat,
          title: 'No recurring rules yet',
          message:
              'Set up rent, salary or a subscription once and let it post itself.',
          actionLabel: 'New rule',
          onAction: onAdd,
        ),
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  const _RuleList({
    required this.rules,
    required this.busyIds,
    required this.onAction,
    required this.onEdit,
  });

  final List<RecurringRule> rules;
  final Set<String> busyIds;
  final void Function(RecurringRule rule, RecurringAction action) onAction;
  final ValueChanged<RecurringRule> onEdit;

  @override
  Widget build(BuildContext context) {
    final active = rules.where((rule) => rule.active).toList()
      ..sort(_byNextRun);
    final paused = rules.where((rule) => !rule.active).toList();

    Widget tile(RecurringRule rule) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: RecurringTile(
        rule: rule,
        busy: busyIds.contains(rule.id),
        onAction: (action) => onAction(rule, action),
        onTap: () => onEdit(rule),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: _MonthlyCard(rules: rules),
        ),
        for (final rule in active) tile(rule),
        if (paused.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PAUSED',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: context.colors.mutedForeground,
                ),
              ),
            ),
          ),
          for (final rule in paused) tile(rule),
        ],
      ],
    );
  }

  /// Soonest first; a rule with no next run sorts last.
  static int _byNextRun(RecurringRule a, RecurringRule b) {
    final left = a.nextRun;
    final right = b.nextRun;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }
}

/// What the active rules come to per month, the same three figures the web app
/// shows above the list.
class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.rules});

  final List<RecurringRule> rules;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    num income = 0;
    num expense = 0;
    for (final rule in rules) {
      if (!rule.active) continue;
      switch (rule.type) {
        case TransactionType.income:
          income += monthlyEquivalent(rule);
        case TransactionType.expense:
          expense += monthlyEquivalent(rule);
        // Transfers move money between the user's own accounts, so they change
        // no monthly total.
        case TransactionType.transfer:
          break;
      }
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Cell(
                label: 'Monthly income',
                amount: income,
                tone: MoneyTone.income,
              ),
            ),
            VerticalDivider(width: 1, color: c.border),
            Expanded(
              child: _Cell(
                label: 'Monthly expenses',
                amount: -expense,
                tone: MoneyTone.expense,
              ),
            ),
            VerticalDivider(width: 1, color: c.border),
            Expanded(
              child: _Cell(
                label: 'Net / month',
                amount: income - expense,
                tone: MoneyTone.auto,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One rule's amount expressed per month, so daily, weekly and yearly rules can
/// be summed together. Months average 30.44 days, so a daily rule lands on the
/// same figure the web app shows.
num monthlyEquivalent(RecurringRule rule) {
  final interval = rule.interval < 1 ? 1 : rule.interval;
  final perPeriod = rule.amount / interval;
  return switch (rule.frequency) {
    Frequency.daily => perPeriod * 30.4375,
    Frequency.weekly => perPeriod * (52 / 12),
    Frequency.monthly => perPeriod,
    Frequency.yearly => perPeriod / 12,
  };
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.amount, required this.tone});

  final String label;
  final num amount;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(
              amount,
              tone: tone,
              signed: true,
              compactAbove: 100000,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
