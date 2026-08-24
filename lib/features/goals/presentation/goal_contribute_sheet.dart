import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/goals_repository.dart';
import '../domain/goal.dart';

/// Adds to a goal's saved amount via `POST /goals/:id/contribute`.
/// Pops `true` when the goal moved.
class GoalContributeSheet extends ConsumerStatefulWidget {
  const GoalContributeSheet({super.key, required this.goal});

  final Goal goal;

  static Future<bool?> show(BuildContext context, {required Goal goal}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GoalContributeSheet(goal: goal),
    );
  }

  @override
  ConsumerState<GoalContributeSheet> createState() =>
      _GoalContributeSheetState();
}

class _GoalContributeSheetState extends ConsumerState<GoalContributeSheet> {
  final TextEditingController _amount = TextEditingController();

  bool _saving = false;
  String? _formError;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final goal = widget.goal;
    final suggestions = <num>{
      if (goal.monthlyContribution > 0) goal.monthlyContribution,
      if (goal.remainingOrComputed > 0) goal.remainingOrComputed,
    };

    return FormSheetScaffold(
      title: 'Add to ${goal.name}',
      submitLabel: 'Add contribution',
      submitting: _saving,
      onSubmit: _submit,
      formError: _formError,
      footnote:
          'Moves the goal only — it does not post a transaction to an account.',
      children: [
        Text(
          '${Money.format(goal.savedAmount)} of ${Money.format(goal.targetAmount)} saved'
          '${goal.remainingOrComputed > 0 ? ' · ${Money.format(goal.remainingOrComputed)} to go' : ''}',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Amount',
          controller: _amount,
          hint: '₹0',
          autofocus: true,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _amountError,
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in suggestions)
                ActionChip(
                  label: Text(Money.compact(amount)),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _amount.text = amount % 1 == 0
                              ? amount.toInt().toString()
                              : amount.toString();
                          _amountError = null;
                        }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount');
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      await ref
          .read(goalsRepositoryProvider)
          .contribute(widget.goal.id, amount);
      ref.invalidate(goalsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = api.message;
      });
    }
  }
}
