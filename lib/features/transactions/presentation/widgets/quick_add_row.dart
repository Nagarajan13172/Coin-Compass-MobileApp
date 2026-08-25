import 'dart:async';

import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/state/optimistic.dart';
import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/confirm_sheet.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account.dart';
import '../../../categories/data/categories_repository.dart';
import '../../../categories/domain/category.dart';
import '../../../templates/data/templates_repository.dart';
import '../../../templates/domain/template.dart';
import '../../data/transactions_repository.dart';
import '../../domain/transaction.dart';
import '../transaction_form_sheet.dart';
import '../transactions_providers.dart';

/// "Quick add" — one tap posts a saved template as a real transaction, with an
/// Undo snackbar. The trailing dashed chip creates a new template.
class QuickAddRow extends ConsumerWidget {
  const QuickAddRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final templates = ref.watch(templatesProvider);
    final rows = templates.valueOrNull ?? const <Template>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick add',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        // A Wrap hands its children unbounded width, so a chip has to be told
        // how wide the row is — a user can name a template anything.
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final template in rows)
                _TemplateChip(
                  template: template,
                  maxWidth: constraints.maxWidth,
                  onTap: () => _run(context, ref, template),
                  onLongPress: () => _remove(context, ref, template),
                ),
              if (templates.isLoading && rows.isEmpty)
                const LoadingShimmer(width: 120, height: 38, radius: 999),
              _NewChip(onTap: () => _create(context)),
            ],
          ),
        ),
      ],
    );
  }

  /// Posts the template. Anything the template leaves undecided (no amount, no
  /// account and none on file) hands off to the full add sheet instead.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Template template,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final accounts =
        ref.read(accountsProvider).valueOrNull ?? const <Account>[];
    final accountId =
        template.accountId ?? (accounts.isEmpty ? null : accounts.first.id);
    final amount = template.amount ?? 0;

    final repository = ref.read(transactionsRepositoryProvider);
    final controller = ref.read(transactionsListProvider.notifier);
    final query = ref.read(transactionQueryProvider);

    // A template with no amount (or nothing to charge it to) can't be posted
    // blind — hand it to the full sheet instead.
    if (accountId == null || amount <= 0) {
      final saved = await showTransactionSheet(context, ref);
      if (saved != null) {
        if (_withinWindow(query, saved.date ?? saved.createdAt)) {
          controller.insertLocal(saved);
        }
        invalidateTransactionDerived(container, tags: saved.tags.isNotEmpty);
      }
      return;
    }

    try {
      final created = await repository.create(
        TransactionDraft(
          type: template.type,
          amount: amount,
          accountId: accountId,
          categoryId: template.categoryId,
          date: DateTime.now(),
          note: template.note,
          payee: template.payee,
          tags: template.tags,
          currency: template.currency,
        ),
      );
      // The row is dated now, which may sit outside the month being browsed.
      if (_withinWindow(query, created.date ?? created.createdAt)) {
        controller.insertLocal(created);
      }
      invalidateTransactionDerived(container, tags: created.tags.isNotEmpty);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Added ${template.name} · ${Money.format(amount)}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                controller.deleteLocal(created.id);
                try {
                  await repository.delete(created.id);
                  invalidateTransactionDerived(
                    container,
                    tags: created.tags.isNotEmpty,
                  );
                } catch (error) {
                  controller.insertLocal(created);
                  // 6.4: one vocabulary for every rollback in the app.
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          rollbackMessage(
                            ApiException.from(error),
                            noun: template.name,
                          ),
                        ),
                      ),
                    );
                }
              },
            ),
          ),
        );
    } catch (error) {
      // 6.4: the quick-add create is not optimistic (the server assigns the
      // id), but its failure speaks the same vocabulary as every rollback.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              rollbackMessage(ApiException.from(error), noun: template.name),
            ),
          ),
        );
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Template template,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Remove “${template.name}”?',
      message: 'The quick-add chip goes away. Past transactions stay.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !context.mounted) return;

    // 6.4 — the chip's disappearance is exactly predictable, so it goes now.
    // There is no `PATCH /templates/:id` in this app (a chip is created or
    // removed, never edited) and no restore endpoint, so no Undo: the
    // ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(templatesRepositoryProvider);

    unawaited(
      container
          .read(templatesWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(template.id),
            send: () => repository.delete(template.id),
            settle: () => settleTemplates(container),
            messenger: messenger,
            noun: template.name,
          ),
    );
  }

  /// True when [date] falls inside the window the list is currently showing.
  static bool _withinWindow(TransactionQuery query, DateTime? date) {
    if (date == null) return true;
    final from = query.from;
    final to = query.to;
    return (from == null || !date.isBefore(from)) &&
        (to == null || !date.isAfter(to));
  }

  Future<void> _create(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _NewQuickAddSheet(),
  );
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.template,
    required this.maxWidth,
    required this.onTap,
    required this.onLongPress,
  });

  final Template template;

  /// Width of the row the chip sits in — the chip never grows past it.
  final double maxWidth;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint =
        colorFromHex(template.color) ??
        (template.type == TransactionType.income ? c.income : c.expense);
    final amount = template.amount;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: c.card,
        shape: StadiumBorder(side: BorderSide(color: c.border)),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  lucideIcon(template.icon, fallback: LucideIcons.zap),
                  size: 15,
                  color: tint,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    template.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (amount != null && amount > 0) ...[
                  const SizedBox(width: 6),
                  MoneyText(
                    amount,
                    tone: MoneyTone.muted,
                    compactAbove: Money.crore,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewChip extends StatelessWidget {
  const _NewChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: _DashedStadiumPainter(color: c.border),
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 15, color: c.mutedForeground),
                const SizedBox(width: 7),
                Text(
                  'New quick-add',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flutter has no dashed border, and the web chip is dashed — so we stroke the
/// stadium outline by hand, walking the path in 5px on / 4px off steps.
class _DashedStadiumPainter extends CustomPainter {
  const _DashedStadiumPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 5;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadiumPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Creates a template — `POST /templates`, the same shape the web app writes.
class _NewQuickAddSheet extends ConsumerStatefulWidget {
  const _NewQuickAddSheet();

  @override
  ConsumerState<_NewQuickAddSheet> createState() => _NewQuickAddSheetState();
}

class _NewQuickAddSheetState extends ConsumerState<_NewQuickAddSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String? _accountId;
  String? _categoryId;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(
        () => _error = ApiException(
          message: 'Give the quick-add a name.',
          fieldErrors: const {
            'name': ['Required'],
          },
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final amount = num.tryParse(_amount.text.trim());
    try {
      await ref.read(templatesRepositoryProvider).create({
        'name': name,
        'type': _type.api,
        if (amount != null && amount > 0) 'amount': amount,
        if (_accountId != null) 'account': _accountId,
        if (_categoryId != null) 'category': _categoryId,
        'currency': 'INR',
      });
      if (!mounted) return;
      ref.invalidate(templatesFetchProvider);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ApiException.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final categories =
        (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
            .where((category) => category.type.api == _type.api)
            .toList();
    final error = _error;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New quick-add',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'A one-tap chip on the Transactions screen.',
                style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
              ),
              const SizedBox(height: 18),
              AppTextField(
                label: 'Name',
                controller: _name,
                hint: 'Morning coffee',
                autofocus: true,
                textInputAction: TextInputAction.next,
                errorText: error?.fieldError('name'),
              ),
              const SizedBox(height: 14),
              AppSelect<TransactionType>(
                label: 'Type',
                value: _type,
                items: [
                  for (final type in TransactionType.values)
                    SelectItem<TransactionType>(type, type.label),
                ],
                onChanged: (value) => setState(() {
                  _type = value ?? TransactionType.expense;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Amount',
                controller: _amount,
                hint: '0',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                errorText: error?.fieldError('amount'),
              ),
              const SizedBox(height: 14),
              AppSelect<String?>(
                label: 'Account',
                value: accounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                items: [
                  const SelectItem<String?>(null, 'Ask each time'),
                  for (final account in accounts)
                    SelectItem<String?>(account.id, account.name),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
              const SizedBox(height: 14),
              AppSelect<String?>(
                label: 'Category',
                value: categories.any((item) => item.id == _categoryId)
                    ? _categoryId
                    : null,
                items: [
                  const SelectItem<String?>(null, 'No category'),
                  for (final category in categories)
                    SelectItem<String?>(category.id, category.name),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              if (error != null && error.fieldErrors.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  error.message,
                  style: TextStyle(fontSize: 13.5, color: c.destructive),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(label: 'Save', busy: _busy, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
