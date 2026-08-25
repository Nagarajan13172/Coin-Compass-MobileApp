import 'dart:async';

import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/color_swatch_picker.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../categories/presentation/category_form_sheet.dart'
    show categoryColorHexes;
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/goals_repository.dart';
import '../domain/goal.dart';

/// Create / edit a savings goal. Pops `true` when the list changed.
///
/// Every control maps to a key `POST /goals` declares — name, targetAmount,
/// savedAmount, targetDate, monthlyContribution, color, icon, currency. The
/// note field is gone: the schema never declared it, so it was typed and
/// silently dropped (docs/WRITE_SCHEMAS.md).
class GoalFormSheet extends ConsumerStatefulWidget {
  const GoalFormSheet({super.key, this.goal});

  /// Null creates a goal; non-null edits that one.
  final Goal? goal;

  static Future<bool?> show(BuildContext context, {Goal? goal}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GoalFormSheet(goal: goal),
    );
  }

  @override
  ConsumerState<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends ConsumerState<GoalFormSheet> {
  late final Goal? _existing = widget.goal;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );
  late final TextEditingController _target = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.targetAmount),
  );
  late final TextEditingController _saved = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.savedAmount),
  );
  late final TextEditingController _monthly = TextEditingController(
    text: _existing == null || _existing.monthlyContribution == 0
        ? ''
        : _plainNumber(_existing.monthlyContribution),
  );

  late DateTime? _targetDate = _existing?.targetDate;
  late String _color = _existing?.color ?? '#6366F1';

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;
  String? _targetError;

  bool get _isEdit => _existing != null;
  // 6.4: a delete pops the sheet on the spot, so there is no deleting state.
  bool get _busy => _saving;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    _monthly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return FormSheetScaffold(
      title: _isEdit ? 'Edit goal' : 'New goal',
      submitLabel: _isEdit ? 'Save changes' : 'Create goal',
      submitting: _saving,
      deleting: false,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete goal' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          hint: 'e.g. Japan trip',
          autofocus: !_isEdit,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _nameError ?? _apiError?.fieldError('name'),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Target amount',
          controller: _target,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _targetError ?? _apiError?.fieldError('targetAmount'),
          onChanged: (_) {
            if (_targetError != null) setState(() => _targetError = null);
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Saved so far',
          controller: _saved,
          hint: '₹0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _apiError?.fieldError('savedAmount'),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Target date',
          hint: 'Optional',
          value: _targetDate == null ? null : DateX.shortDay(_targetDate!),
          errorText: _apiError?.fieldError('targetDate'),
          onTap: _busy ? null : _pickDate,
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _targetDate == null
              ? null
              : IconButton(
                  onPressed: () => setState(() => _targetDate = null),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  tooltip: tr(context, 'Clear date'),
                  icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
                ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Monthly contribution',
          controller: _monthly,
          hint: 'Optional — what you plan to put aside',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _apiError?.fieldError('monthlyContribution'),
        ),
        const SizedBox(height: 18),
        ColorSwatchPicker(
          label: 'Colour',
          hexes: categoryColorHexes,
          value: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 30, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _targetDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final target = parseAmount(_target.text);

    if (name.isEmpty || target == null || target <= 0) {
      setState(() {
        _nameError = name.isEmpty ? 'Name is required' : null;
        _targetError = (target == null || target <= 0)
            ? 'Enter a target'
            : null;
      });
      return;
    }

    final body = _buildBody(name, target);
    final existing = _existing;

    // 6.4 — the form owns name, target, saved, monthly and colour, so an edit's
    // outcome is known. `remaining`, `percent`, `complete` and `monthsLeft` are
    // server-derived and all move here, so `Goal.predict` nulls them and the
    // model's own arithmetic takes over. A create keeps the spinner.
    //
    // `POST /goals/:id/contribute` is a different matter and is deliberately
    // NOT optimistic — see `GoalContributeSheet`.
    final predicted = existing?.predict(
      name: name,
      targetAmount: target,
      savedAmount: parseAmount(_saved.text) ?? 0,
      monthlyContribution: parseAmount(_monthly.text) ?? 0,
      color: _color,
      icon: existing.icon,
      targetDate: _targetDate,
    );
    if (existing != null && predicted != null) {
      _runOptimistic(existing, predicted, body);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repository = ref.read(goalsRepositoryProvider);
      await repository.create(body);
      container.invalidate(goalsFetchProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _apiError = api;
        _formError = api.message;
      });
    }
  }

  Future<void> _delete() async {
    final goal = _existing;
    if (goal == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${goal.name}?',
      message: 'The goal and its saved progress are removed.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a goal. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(goalsRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(goalsWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(goal.id),
            send: () => repository.delete(goal.id),
            settle: () => settleGoals(container),
            messenger: messenger,
            noun: goal.name,
            successMessage: 'Deleted ${goal.name}',
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    Goal existing,
    Goal predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(goalsRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(goalsWritesProvider.notifier)
          .run<Goal>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settleGoals(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              GoalFormSheet.show(messenger.context, goal: predicted);
            },
          ),
    );
  }

  Map<String, dynamic> _buildBody(String name, num target) {
    final body = <String, dynamic>{
      'name': name,
      'targetAmount': target,
      'savedAmount': parseAmount(_saved.text) ?? 0,
      'monthlyContribution': parseAmount(_monthly.text) ?? 0,
      'color': _color,
      'icon': _existing?.icon ?? 'goal',
      'currency': _existing?.currency ?? 'INR',
    };
    WriteBody.putNullable(
      body,
      'targetDate',
      _targetDate == null ? null : DateX.toApi(_targetDate!),
      _existing?.targetDate,
    );
    return body;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}
