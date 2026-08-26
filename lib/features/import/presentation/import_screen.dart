import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../categories/data/categories_repository.dart';
import '../data/csv_file_source.dart';
import '../data/import_runner.dart';
import '../domain/import_parser.dart';
import '../domain/import_plan.dart';
import 'import_controller.dart';

const double _navBarHeight = 62;
const double _fabClearance = 28;

double _shellBottomInset(BuildContext context) =>
    _navBarHeight + MediaQuery.viewPaddingOf(context).bottom + _fabClearance;

/// Phase 7.3 — import a CSV of transactions.
///
/// The screen is one long confirmation. Every state before [ImportRunning] is
/// reversible and writes nothing, and the only way into the writing state is a
/// button that names the exact number of rows it will create. That shape is the
/// feature: an importer that is quick to run and hard to run *by accident*.
///
/// Mounted at `/reports/import` so the bottom nav keeps Reports lit, the same
/// arrangement `/credits/people` uses.
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  static const String routePath = '/reports/import';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _shellBottomInset(context)),
      children: [
        switch (state) {
          ImportIdle() => const _Intro(),
          ImportBusy(:final label) => _Busy(label: label),
          ImportFailed(:final message) => _Failed(message: message),
          ImportPreview() => _Preview(state: state),
          ImportRunning() => _Running(state: state),
          ImportDone() => _Report(state: state),
        },
      ],
    );
  }
}

/// User data, rendered exactly as the user's file spelled it.
///
/// ## Why this exists
///
/// `core/ui.dart` swaps Flutter's `Text` for one that sends its content to ML
/// Kit, which is right for UI copy and wrong for *data*. On the device walk in
/// Tamil this screen displayed:
///
///   * the chosen file as `சரிபார்க்கவும் 73.csv` — the filename `verify-73.csv`
///     machine-translated, so it no longer matched anything the user could see
///     in their file manager;
///   * `ZZTest Alpha` as `Zztest ஆல்பா`, while `ZZTest Gamma` came back merely
///     lower-cased — the same column rendered three different ways;
///   * the account the import was about to create as `இறக்குமதி சோதனை`, when the
///     record it actually creates is named `Import Test`.
///
/// The last one is the dangerous shape: the *data* was always correct — drafts
/// carry `row.payee` and `ref.name` from the parsed model, never the rendered
/// string, and the device confirmed the stored payee is `ZZTest Gamma` — but a
/// preview whose job is "see exactly what will be added" was showing something
/// other than what would be added.
///
/// `Text.rich` is the documented bypass: `TranslatedText` passes a span tree
/// through untouched, because translating assembled spans separately would
/// reorder them.
///
/// This is a general problem — every screen that renders a payee, account,
/// category or note has it — and this local widget only fixes this screen.
class _Verbatim extends StatelessWidget {
  const _Verbatim(
    this.text, {
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(text: text),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
  );
}

// ── idle ───────────────────────────────────────────────────────────────────

class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(
          icon: LucideIcons.fileUp,
          title: 'Import transactions',
          message:
              'Pick a CSV and see exactly what will be added before anything '
              'is saved.',
          actionLabel: 'Choose a file',
          onAction: () => ref.read(importControllerProvider.notifier).pick(),
        ),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'What the file should look like'),
              const SizedBox(height: 8),
              Text(
                'A CSV exported from CoinCompass imports as it is. The first '
                'row has to name the columns:',
                style: TextStyle(fontSize: 13, color: c.mutedForeground),
              ),
              const SizedBox(height: 10),
              _CodeBlock(
                text: 'Date,Type,Amount,Currency,Account,'
                    'To Account,Category,Payee,Note,Tags',
              ),
              const SizedBox(height: 12),
              _Bullet(
                text: 'Only Amount and Account are required. Type can be '
                    'income, expense or transfer.',
              ),
              _Bullet(
                text: 'A bank statement works too — Date, Narration, '
                    'Withdrawal and Deposit columns are understood.',
              ),
              _Bullet(
                text: 'Accounts and categories are matched by name. Anything '
                    'that does not match, you decide about before importing.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(AppTheme.radius - 4),
      ),
      // The header is a literal the user has to reproduce exactly, so it is
      // shown in mono and never translated — see `translation_policy`.
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: c.mutedForeground,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

// ── transient states ───────────────────────────────────────────────────────

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(label, style: TextStyle(color: context.colors.mutedForeground)),
      ],
    ),
  );
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          borderColor: c.destructive,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.circleAlert, size: 18, color: c.destructive),
                  const SizedBox(width: 8),
                  Text(
                    'That file cannot be imported',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.destructive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Choose another file',
          icon: LucideIcons.fileUp,
          onPressed: () => ref.read(importControllerProvider.notifier).pick(),
        ),
      ],
    );
  }
}

// ── preview ────────────────────────────────────────────────────────────────

class _Preview extends ConsumerWidget {
  const _Preview({required this.state});
  final ImportPreview state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = state.plan;
    final controller = ref.read(importControllerProvider.notifier);
    final ready = plan.ready;
    final blocked = plan.blocked;
    final skipped = plan.skipped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FileBar(file: state.file, onChange: controller.pick),
        const SizedBox(height: 12),
        _Tally(ready: ready.length, blocked: blocked.length, skipped: skipped.length),

        if (plan.parse.fileWarnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Warnings(warnings: plan.parse.fileWarnings),
        ],

        if (!plan.parse.dateOrder.certain) ...[
          const SizedBox(height: 12),
          _DateOrderCard(
            reading: plan.parse.dateOrder,
            onChanged: controller.setDateOrder,
          ),
        ],

        if (plan.needsFallbackAccount) ...[
          const SizedBox(height: 12),
          _FallbackAccountCard(
            rowCount: plan.rowsNeedingFallbackAccount,
            onChanged: controller.setFallbackAccount,
          ),
        ],

        if (plan.refs.any((r) => !r.isMatched)) ...[
          const SizedBox(height: 12),
          _UnmatchedCard(plan: plan, onDecide: controller.decide),
        ],

        if (blocked.isNotEmpty) ...[
          const SizedBox(height: 12),
          _BlockedCard(rows: blocked),
        ],

        if (ready.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReadyPreviewCard(rows: ready),
        ],

        const SizedBox(height: 16),
        _RunButton(plan: plan),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: controller.reset,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _FileBar extends StatelessWidget {
  const _FileBar({required this.file, required this.onChange});
  final PickedCsv file;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(LucideIcons.fileText, size: 18, color: c.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Verbatim(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${(file.byteCount / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// Ready / needs attention / skipped, at a glance.
class _Tally extends StatelessWidget {
  const _Tally({required this.ready, required this.blocked, required this.skipped});
  final int ready;
  final int blocked;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: _Pill(count: ready, label: 'ready', color: c.income)),
        if (blocked > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(count: blocked, label: 'need attention', color: c.destructive),
          ),
        ],
        if (skipped > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _Pill(count: skipped, label: 'skipped', color: c.mutedForeground),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.count, required this.label, required this.color});
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    child: Column(
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: context.colors.mutedForeground),
        ),
      ],
    ),
  );
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      borderColor: c.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 16, color: c.warning),
              const SizedBox(width: 8),
              Text(
                'About this file',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.warning),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final warning in warnings) _Bullet(text: warning),
        ],
      ),
    );
  }
}

/// Only shown when the file cannot settle its own date order. Getting this
/// wrong silently moves months of history, so it is a question rather than a
/// default.
class _DateOrderCard extends StatelessWidget {
  const _DateOrderCard({required this.reading, required this.onChanged});
  final DateOrderReading reading;
  final ValueChanged<DateOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      borderColor: c.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: reading.conflicting
                ? 'These dates do not agree'
                : 'How should the dates be read?',
            subtitle: reading.conflicting
                ? 'Some rows can only be day-first and others can only be '
                    'month-first, so at least one will be wrong whichever you '
                    'pick. Check the file if the dates matter.'
                : 'Every date in this file reads either way — 03/04 could be '
                    '3 April or 4 March.',
          ),
          const SizedBox(height: 10),
          AppSelect<DateOrder>(
            value: reading.order,
            onChanged: (order) => order == null ? null : onChanged(order),
            items: [
              for (final order in DateOrder.values)
                SelectItem(order, order.label),
            ],
          ),
        ],
      ),
    );
  }
}

class _FallbackAccountCard extends ConsumerWidget {
  const _FallbackAccountCard({required this.rowCount, required this.onChanged});
  final int rowCount;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    return AppCard(
      borderColor: context.colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Which account?',
            subtitle: '$rowCount ${rowCount == 1 ? 'row has' : 'rows have'} no '
                'account named. Every transaction has to belong to one.',
          ),
          const SizedBox(height: 10),
          AppSelect<String>(
            value: null,
            hint: 'Choose an account',
            onChanged: onChanged,
            items: [
              for (final account in accounts.where((a) => !a.archived))
                SelectItem(account.id, account.name),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every name that did not match, and what to do about it.
class _UnmatchedCard extends ConsumerWidget {
  const _UnmatchedCard({required this.plan, required this.onDecide});
  final ImportPlan plan;
  final void Function(String, RefDecision) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unmatched = plan.refs.where((r) => !r.isMatched).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Names not in your account',
            subtitle: 'Nothing is created until you say so.',
          ),
          for (final ref in unmatched) ...[
            const SizedBox(height: 12),
            _RefRow(
              nameRef: ref,
              decision: plan.decisions[ref.key],
              onDecide: (decision) => onDecide(ref.key, decision),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefRow extends ConsumerWidget {
  const _RefRow({
    required this.nameRef,
    required this.decision,
    required this.onDecide,
  });

  final NameRef nameRef;
  final RefDecision? decision;
  final ValueChanged<RefDecision> onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isAccount = nameRef.kind == RefKind.account;
    final options = isAccount
        ? (ref.watch(accountsProvider).valueOrNull ?? const [])
              .where((a) => !a.archived)
              .map((a) => SelectItem<String>(a.id, a.name))
              .toList()
        : (ref.watch(categoriesProvider).valueOrNull ?? const [])
              .where((cat) => cat.type == nameRef.categoryType)
              .map((cat) => SelectItem<String>(cat.id, cat.name))
              .toList();

    final kindLabel = isAccount
        ? 'account'
        : '${nameRef.categoryType == CategoryType.income ? 'income' : 'expense'} category';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(AppTheme.radius - 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Verbatim(
                  nameRef.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${nameRef.rowCount} ${nameRef.rowCount == 1 ? 'row' : 'rows'}',
                style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
              ),
            ],
          ),
          Text(
            'No $kindLabel with this name',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 10),
          AppSelect<String>(
            value: switch (decision) {
              UseExisting(:final id) => id,
              _ => null,
            },
            hint: 'Use an existing one…',
            onChanged: (id) => id == null ? null : onDecide(UseExisting(id)),
            items: options,
          ),
          const SizedBox(height: 8),
          // Stacked, not side by side. `AppButton` centres a `Row` of icon +
          // unconstrained `Text`, so a label wider than its half of a 360dp
          // card overflows rather than ellipsising — "Will be created" already
          // did by 5.4px. Tamil runs to 173% of English on labels this shape
          // (see PHASE7_1_REPORT), so a side-by-side pair here could not
          // survive the language toggle either.
          AppButton(
            label: decision is CreateNew ? 'Will be created' : 'Create it',
            icon: decision is CreateNew ? LucideIcons.check : LucideIcons.plus,
            variant: decision is CreateNew
                ? AppButtonVariant.primary
                : AppButtonVariant.outlined,
            onPressed: () => onDecide(const CreateNew()),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: isAccount ? 'Skip these rows' : 'Leave blank',
            icon: decision is SkipRef ? LucideIcons.check : null,
            variant: decision is SkipRef
                ? AppButtonVariant.primary
                : AppButtonVariant.outlined,
            onPressed: () => onDecide(const SkipRef()),
          ),
        ],
      ),
    );
  }
}

/// Rows that will not be imported, and why. Capped, because a badly-formed
/// file can produce thousands and the list is for diagnosis, not for reading
/// end to end.
class _BlockedCard extends StatelessWidget {
  const _BlockedCard({required this.rows});
  final List<PlannedRow> rows;

  static const int _shown = 12;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = rows.take(_shown).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Rows that will not be imported',
            subtitle: 'Everything else still imports. Fix these in the file '
                'and import it again if you need them.',
          ),
          const SizedBox(height: 4),
          for (final row in shown)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      // Line numbers are figures; `translation_policy` keeps
                      // them out of the translator.
                      'L${row.line}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.reasons.join(' '),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          if (rows.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'and ${rows.length - _shown} more',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// The first few rows exactly as they will be created — the last chance to
/// notice that the amounts or dates came out wrong.
class _ReadyPreviewCard extends StatelessWidget {
  const _ReadyPreviewCard({required this.rows});
  final List<PlannedRow> rows;

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'First rows, as they will be saved',
            subtitle: 'Check a date and an amount before importing.',
          ),
          for (final planned in rows.take(_shown))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The type label is app copy and *is* translated; the
                        // payee and note are the user's own words and are not.
                        if (planned.row.payee.isNotEmpty ||
                            planned.row.note.isNotEmpty)
                          _Verbatim(
                            planned.row.payee.isNotEmpty
                                ? planned.row.payee
                                : planned.row.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else
                          Text(
                            planned.row.type!.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        Text(
                          planned.row.date == null
                              ? 'Today'
                              : DateX.dateLabel(planned.row.date!),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Money.format(
                      planned.row.type == TransactionType.expense
                          ? -planned.row.amount!
                          : planned.row.amount!,
                      symbol: Money.symbolFor(planned.row.currency),
                      signed: true,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: planned.row.type == TransactionType.expense
                          ? c.expense
                          : c.income,
                    ),
                  ),
                ],
              ),
            ),
          if (rows.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'and ${rows.length - _shown} more',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// The only control that writes. It names the count on purpose — the number is
/// the confirmation.
class _RunButton extends ConsumerWidget {
  const _RunButton({required this.plan});
  final ImportPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = plan.ready.length;
    final undecided = plan.undecided.length;
    final creations = plan.pendingCreations.length;

    if (undecided > 0) {
      return AppButton(
        label: '$undecided ${undecided == 1 ? 'name needs' : 'names need'} a decision',
        icon: LucideIcons.circleAlert,
        onPressed: null,
      );
    }
    if (ready == 0) {
      return const AppButton(
        label: 'Nothing to import',
        icon: LucideIcons.circleAlert,
        onPressed: null,
      );
    }

    final container = ProviderScope.containerOf(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Import $ready ${ready == 1 ? 'transaction' : 'transactions'}',
          icon: LucideIcons.fileUp,
          onPressed: () =>
              ref.read(importControllerProvider.notifier).run(container),
        ),
        if (creations > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This will also create $creations new '
              '${creations == 1 ? 'record' : 'records'} in your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }
}

// ── running ────────────────────────────────────────────────────────────────

class _Running extends ConsumerWidget {
  const _Running({required this.state});
  final ImportRunning state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final progress = state.progress;
    final label = switch (progress.stage) {
      ImportStage.creating => 'Creating accounts and categories…',
      ImportStage.writing => 'Importing…',
      ImportStage.refreshing => 'Finishing up…',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? null : progress.fraction,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${progress.written} of ${progress.total} saved'
            '${progress.failed > 0 ? ' · ${progress.failed} failed' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: state.cancelling ? 'Stopping…' : 'Stop',
            variant: AppButtonVariant.outlined,
            onPressed: state.cancelling
                ? null
                : ref.read(importControllerProvider.notifier).cancel,
          ),
          const SizedBox(height: 8),
          Text(
            'Stopping keeps whatever has already been imported.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

// ── report ─────────────────────────────────────────────────────────────────

class _Report extends ConsumerWidget {
  const _Report({required this.state});
  final ImportDone state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final outcome = state.outcome;
    final ok = outcome.isClean;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          borderColor: ok ? c.income : c.warning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ok ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
                    size: 18,
                    color: ok ? c.income : c.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ok ? 'Imported' : 'Imported, with some left out',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${outcome.written} '
                '${outcome.written == 1 ? 'transaction' : 'transactions'} '
                'added from ${state.fileName}.',
                style: const TextStyle(fontSize: 13),
              ),
              // The label is app copy; the names are records the user now has
              // in their account, and must read as they were actually created.
              if (outcome.createdAccounts.isNotEmpty) ...[
                const SizedBox(height: 6),
                _CreatedLine(
                  label: 'New accounts',
                  names: outcome.createdAccounts,
                ),
              ],
              if (outcome.createdCategories.isNotEmpty) ...[
                const SizedBox(height: 4),
                _CreatedLine(
                  label: 'New categories',
                  names: outcome.createdCategories,
                ),
              ],
              if (outcome.stopReason != null) ...[
                const SizedBox(height: 10),
                Text(
                  outcome.stopReason!,
                  style: TextStyle(fontSize: 12.5, color: c.warning),
                ),
              ],
            ],
          ),
        ),
        if (outcome.failures.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FailureList(failures: outcome.failures),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: 'Import another file',
          icon: LucideIcons.fileUp,
          variant: AppButtonVariant.outlined,
          onPressed: () => ref.read(importControllerProvider.notifier).pick(),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: ref.read(importControllerProvider.notifier).reset,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

/// `New accounts: Import Test` — the label translated, the names verbatim.
class _CreatedLine extends StatelessWidget {
  const _CreatedLine({required this.label, required this.names});

  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12.5,
      color: context.colors.mutedForeground,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ', style: style),
        Expanded(child: _Verbatim(names.join(', '), style: style)),
      ],
    );
  }
}

class _FailureList extends StatelessWidget {
  const _FailureList({required this.failures});
  final List<ImportFailure> failures;

  static const int _shown = 15;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Rows the server rejected',
            subtitle: 'These were not saved. Nothing else was affected.',
          ),
          for (final failure in failures.take(_shown))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      'L${failure.line}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      failure.payee.isEmpty
                          ? failure.message
                          : '${failure.payee} — ${failure.message}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          if (failures.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'and ${failures.length - _shown} more',
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}
