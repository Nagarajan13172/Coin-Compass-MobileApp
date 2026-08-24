import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/api/write_body.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../networth/data/networth_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/holdings_repository.dart';
import '../domain/holding.dart';
import 'widgets/holding_tile.dart' show subtypeIcon;

/// Create / edit a saving or investment. Pops `true` when the list changed.
///
/// Every control maps to a key `POST /holdings` declares — name, class,
/// subtype, value, maturityDate, startDate, note, currency.
///
/// There is deliberately **no invested / institution / roi input**. Phase 1
/// guessed those three from the web UI; the probe in docs/WRITE_SCHEMAS.md
/// shows the server's Zod schema strips all three silently, so a user who
/// filled them in would watch the values vanish with no error. The fields were
/// removed from the model too, so there is nothing left to bind to.
class HoldingFormSheet extends ConsumerStatefulWidget {
  const HoldingFormSheet({super.key, this.holding});

  /// Null creates a holding; non-null edits that one.
  final Holding? holding;

  static Future<bool?> show(BuildContext context, {Holding? holding}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HoldingFormSheet(holding: holding),
    );
  }

  @override
  ConsumerState<HoldingFormSheet> createState() => _HoldingFormSheetState();
}

class _HoldingFormSheetState extends ConsumerState<HoldingFormSheet> {
  late final Holding? _existing = widget.holding;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );
  late final TextEditingController _value = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.value),
  );
  late final TextEditingController _note = TextEditingController(
    text: _existing?.note ?? '',
  );

  late HoldingClass _class = _existing?.holdingClass ?? HoldingClass.saving;
  late HoldingSubtype _subtype =
      _existing?.subtype ?? HoldingSubtype.fixedDeposit;
  late DateTime? _startDate = _existing?.startDate;
  late DateTime? _maturityDate = _existing?.maturityDate;
  String? _currency;

  bool _saving = false;
  bool _deleting = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;
  String? _valueError;

  bool get _isEdit => _existing != null;
  bool get _busy => _saving || _deleting;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final symbol = ref.watch(currencySymbolProvider);
    final options = ref.watch(settingsProvider).valueOrNull?.currencies ??
        const [];
    // A currency control only earns its place when there is a choice to make.
    // The wallet this app ships against has one currency, and a select with a
    // single option is a control that cannot be used.
    final showCurrency = options.length > 1;

    return FormSheetScaffold(
      title: _isEdit ? 'Edit holding' : 'New holding',
      submitLabel: _isEdit ? 'Save changes' : 'Add holding',
      submitting: _saving,
      deleting: _deleting,
      onSubmit: _submit,
      deleteLabel: _isEdit ? 'Delete holding' : null,
      onDelete: _isEdit ? _delete : null,
      formError: _formError,
      footnote: 'A holding records what it is worth today — there is no cost '
          'basis or interest rate to track.',
      children: [
        AppTextField(
          label: 'Name',
          controller: _name,
          hint: 'e.g. HDFC fixed deposit',
          autofocus: !_isEdit,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          errorText: _nameError ?? _apiError?.fieldError('name'),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 14),
        AppSelect<HoldingClass>(
          label: 'Class',
          value: _class,
          enabled: !_busy,
          errorText: _apiError?.fieldError('class'),
          items: [
            SelectItem(
              HoldingClass.saving,
              HoldingClass.saving.label,
              icon: LucideIcons.piggyBank,
            ),
            SelectItem(
              HoldingClass.investment,
              HoldingClass.investment.label,
              icon: LucideIcons.trendingUp,
            ),
          ],
          onChanged: (next) {
            if (next == null) return;
            setState(() {
              _class = next;
              // The Type list below is filtered by class, so a subtype that
              // does not belong to the new class has to go — otherwise the
              // select holds a value its own options no longer offer, and the
              // holding files under the wrong half of the split.
              final allowed = HoldingSubtype.forClass(next);
              if (!allowed.contains(_subtype)) _subtype = allowed.first;
            });
          },
        ),
        const SizedBox(height: 14),
        AppSelect<HoldingSubtype>(
          label: 'Type',
          value: _subtype,
          enabled: !_busy,
          errorText: _apiError?.fieldError('subtype'),
          items: [
            for (final subtype in HoldingSubtype.forClass(_class))
              SelectItem(subtype, subtype.label, icon: subtypeIcon(subtype)),
          ],
          onChanged: (next) {
            if (next == null) return;
            setState(() {
              _subtype = next;
              // Keep the pair legal from whichever side the user edits.
              _class = next.holdingClass;
            });
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Current value',
          controller: _value,
          hint: '${symbol}0',
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          errorText: _valueError ?? _apiError?.fieldError('value'),
          onChanged: (_) {
            if (_valueError != null) setState(() => _valueError = null);
          },
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Start date',
          hint: 'Optional',
          value: _startDate == null ? null : DateX.shortDay(_startDate!),
          errorText: _apiError?.fieldError('startDate'),
          onTap: _busy ? null : () => _pickDate(isMaturity: false),
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _startDate == null
              ? null
              : _ClearButton(
                  onPressed: () => setState(() => _startDate = null),
                ),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Maturity date',
          hint: 'Optional — deposits and bonds',
          value: _maturityDate == null
              ? null
              : DateX.shortDay(_maturityDate!),
          errorText: _apiError?.fieldError('maturityDate'),
          onTap: _busy ? null : () => _pickDate(isMaturity: true),
          leading: Icon(
            LucideIcons.calendarClock,
            size: 18,
            color: c.mutedForeground,
          ),
          trailing: _maturityDate == null
              ? null
              : _ClearButton(
                  onPressed: () => setState(() => _maturityDate = null),
                ),
        ),
        if (showCurrency) ...[
          const SizedBox(height: 14),
          AppSelect<String>(
            label: 'Currency',
            value: _currency ?? _existing?.currency ?? options.first.code,
            enabled: !_busy,
            errorText: _apiError?.fieldError('currency'),
            items: [
              for (final option in options)
                SelectItem(option.code, '${option.code} · ${option.name}'),
            ],
            onChanged: (next) {
              if (next == null) return;
              setState(() => _currency = next);
            },
          ),
        ],
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          enabled: !_busy,
          maxLines: 3,
          errorText: _apiError?.fieldError('note'),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isMaturity}) async {
    final now = DateTime.now();
    final current = isMaturity ? _maturityDate : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current ?? (isMaturity ? DateTime(now.year + 1, now.month, now.day) : now),
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 50, 12, 31),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isMaturity) {
        _maturityDate = day;
      } else {
        _startDate = day;
      }
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final value = parseAmount(_value.text);

    if (name.isEmpty || value == null) {
      setState(() {
        _nameError = name.isEmpty ? 'Name is required' : null;
        _valueError = value == null ? 'Enter the current value' : null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    try {
      final repository = ref.read(holdingsRepositoryProvider);
      final body = _buildBody(name, value);
      if (_isEdit) {
        await repository.update(_existing!.id, body);
      } else {
        await repository.create(body);
      }
      _invalidate();
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
    final holding = _existing;
    if (holding == null) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${holding.name}?',
      message: 'The holding is removed from your assets.',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref.read(holdingsRepositoryProvider).delete(holding.id);
      _invalidate();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final api = ApiException.from(error);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _apiError = api;
        _formError = api.message;
      });
    }
  }

  /// Holdings feed the asset half of net worth, so the snapshot series has to
  /// be refetched alongside the list.
  void _invalidate() {
    ref
      ..invalidate(holdingsProvider)
      ..invalidate(netWorthHistoryProvider)
      ..invalidate(netWorthHistoryRangeProvider);
  }

  /// Only keys `POST /holdings` declares. Guarded by
  /// test/write_schema_test.dart, which reads this method's source.
  Map<String, dynamic> _buildBody(String name, num value) {
    final body = <String, dynamic>{
      'name': name,
      'class': _class.api,
      'subtype': _subtype.api,
      'value': value,
      'currency': _currency ?? _existing?.currency ?? 'INR',
    };
    WriteBody.putText(body, 'note', _note.text, _existing?.note);
    WriteBody.putNullable(
      body,
      'startDate',
      _startDate == null ? null : _apiDay(_startDate!),
      _existing?.startDate,
    );
    WriteBody.putNullable(
      body,
      'maturityDate',
      _maturityDate == null ? null : _apiDay(_maturityDate!),
      _existing?.maturityDate,
    );
    return body;
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

/// A calendar day as the API stores it: UTC midnight of that day. `toUtc()` on
/// a local midnight would move an IST date back a day, drifting a maturity
/// date by one.
String _apiDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).toIso8601String();

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      tooltip: 'Clear date',
      icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
    );
  }
}
