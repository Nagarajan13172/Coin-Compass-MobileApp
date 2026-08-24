import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../../core/widgets/money_text.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';
import 'stocks_providers.dart';

/// Records a sale — `POST /stocks/sell`.
///
/// The server sells FIFO and books the realized gain; [computeSellPreview]
/// mirrors that arithmetic locally so the sheet can show what the sale realises
/// — and warn when waiting a few more days would move part of the gain into the
/// long-term bracket — before anything is written.
///
/// As with the buy sheet, the body is built inside [StocksRepository.sell] from
/// typed arguments: the schema takes `symbol, demat, qty, sellPrice, sellDate,
/// note` and strips everything else, charges included.
class StockSellSheet extends ConsumerStatefulWidget {
  const StockSellSheet({super.key, required this.position});

  final StockPosition position;

  /// Pops `true` when a sale was recorded.
  static Future<bool?> show(
    BuildContext context, {
    required StockPosition position,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockSellSheet(position: position),
    );
  }

  @override
  ConsumerState<StockSellSheet> createState() => _StockSellSheetState();
}

class _StockSellSheetState extends ConsumerState<StockSellSheet> {
  late final StockPosition _position = widget.position;

  final TextEditingController _qty = TextEditingController();
  late final TextEditingController _price = TextEditingController(
    text: _position.price > 0 ? _plain(_position.price) : '',
  );
  final TextEditingController _note = TextEditingController();

  late String? _dematId = _position.demat;
  DateTime _sellDate = DateTime.now();

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _qtyError;
  String? _priceError;
  String? _dematError;

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final demats = ref.watch(dematAccountsProvider);
    final demat = _resolveDemat(demats);
    final preview = _preview();

    return FormSheetScaffold(
      title: 'Sell ${_position.displayTicker}',
      submitLabel: 'Record sale',
      submitting: _saving,
      onSubmit: _submit,
      formError: _formError,
      footnote:
          'Charges are not stored — the server keeps the quantity and the '
          'price you sold at.',
      children: [
        _HoldingRow(position: _position),
        const SizedBox(height: 14),
        // Full width, not two columns — see the buy sheet.
        AppTextField(
          label: 'Quantity',
          controller: _qty,
          hint: _plain(_position.qty),
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [const AmountInputFormatter(decimals: 4)],
          errorText: _qtyError ?? _apiError?.fieldError('qty'),
          onChanged: (_) => _clearFieldErrors(),
          labelAction: TextButton(
            onPressed: _saving ? null : _sellAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Sell all', style: TextStyle(fontSize: 12.5)),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Price per share',
          controller: _price,
          hint: '1,400',
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [const AmountInputFormatter()],
          errorText: _priceError ?? _apiError?.fieldError('sellPrice'),
          onChanged: (_) => _clearFieldErrors(),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Sale date',
          hint: 'Pick a date',
          value: DateX.shortDay(_sellDate),
          errorText: _apiError?.fieldError('sellDate'),
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          onTap: _saving ? null : _pickDate,
        ),
        // The position already knows its demat account; the picker only appears
        // when it does not and more than one could be meant.
        if (demat == null || demats.length > 1) ...[
          const SizedBox(height: 14),
          PickerField(
            label: 'Demat account',
            hint: 'Pick a demat account',
            value: demat?.name,
            errorText: _dematError ?? _apiError?.fieldError('demat'),
            leading: Icon(
              LucideIcons.landmark,
              size: 18,
              color: c.mutedForeground,
            ),
            onTap: _saving || demats.isEmpty ? null : () => _pickDemat(demats),
          ),
        ],
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          enabled: !_saving,
          maxLines: 2,
          errorText: _apiError?.fieldError('note'),
        ),
        if (preview != null) ...[
          const SizedBox(height: 16),
          _PreviewCard(preview: preview),
        ],
      ],
    );
  }

  SellPreview? _preview() {
    final qty = parseAmount(_qty.text);
    final price = parseAmount(_price.text);
    if (qty == null || qty <= 0 || price == null || price < 0) return null;
    if (_position.lots.isEmpty) return null;
    return computeSellPreview(
      lots: _position.lots,
      qty: qty,
      price: price,
      sellDate: _sellDate,
    );
  }

  /// The position's own demat account when the payload named one, else the
  /// wallet's only demat account.
  Account? _resolveDemat(List<Account> demats) {
    final id = _dematId;
    if (id != null) {
      for (final account in demats) {
        if (account.id == id) return account;
      }
      // The id came off the position, so it is valid even when the accounts
      // list has not landed yet — the submit path uses it directly.
    }
    return demats.length == 1 ? demats.first : null;
  }

  String? _dematIdForSubmit(List<Account> demats) =>
      _dematId ?? (demats.length == 1 ? demats.first.id : null);

  void _sellAll() {
    setState(() {
      _qty.text = _plain(_position.qty);
      _qtyError = null;
    });
  }

  void _clearFieldErrors() {
    // The preview follows every keystroke, so this rebuild is not optional.
    setState(() {
      _qtyError = null;
      _priceError = null;
    });
  }

  Future<void> _pickDemat(List<Account> demats) async {
    final picked = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SellDematSheet(accounts: demats, selectedId: _dematId),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dematId = picked.id;
      _dematError = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _sellDate,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _sellDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final demats = ref.read(dematAccountsProvider);
    final dematId = _dematIdForSubmit(demats);
    final qty = parseAmount(_qty.text);
    final price = parseAmount(_price.text);

    if (qty == null ||
        qty <= 0 ||
        qty > _position.qty ||
        price == null ||
        price < 0 ||
        dematId == null) {
      final String? qtyError;
      if (qty == null || qty <= 0) {
        qtyError = 'Enter a quantity';
      } else if (qty > _position.qty) {
        qtyError = 'You only hold ${_plain(_position.qty)} share(s)';
      } else {
        qtyError = null;
      }

      setState(() {
        _qtyError = qtyError;
        _priceError = (price == null || price < 0) ? 'Enter a price' : null;
        _dematError = dematId == null ? 'Pick a demat account' : null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
    });

    try {
      await ref
          .read(stocksRepositoryProvider)
          .sell(
            symbol: _position.symbol,
            demat: dematId,
            qty: qty,
            sellPrice: price,
            sellDate: _sellDate,
            note: _note.text,
          );
      invalidateStocks(ref);
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

  static String _plain(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.position});

  final StockPosition position;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final qty = position.qty % 1 == 0
        ? position.qty.toInt().toString()
        : position.qty.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You hold',
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
          ),
          Flexible(
            child: Text(
              '$qty at ${Money.format(position.avgCost)} avg',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the sale realises, computed the way the server will compute it.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final SellPreview preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lots = preview.allocations.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What this sale realises',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 10),
          _Line(label: 'Proceeds', amount: preview.proceeds),
          const SizedBox(height: 6),
          _Line(label: 'Cost basis', amount: preview.costBasis),
          const SizedBox(height: 8),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 8),
          _Line(
            label: 'Realised P&L',
            amount: preview.realized,
            tone: MoneyTone.auto,
            signed: true,
            emphasis: true,
          ),
          if (preview.realizedLongTerm != 0) ...[
            const SizedBox(height: 6),
            _Line(
              label: 'Long-term',
              amount: preview.realizedLongTerm,
              tone: MoneyTone.auto,
              signed: true,
            ),
          ],
          if (preview.realizedShortTerm != 0) ...[
            const SizedBox(height: 6),
            _Line(
              label: 'Short-term',
              amount: preview.realizedShortTerm,
              tone: MoneyTone.auto,
              signed: true,
            ),
          ],
          if (preview.nearlyLongTermDays != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.clock, size: 14, color: c.mutedForeground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Waiting ${preview.nearlyLongTermDays} more day(s) would '
                    'make part of this gain long-term.',
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                ),
              ],
            ),
          ],
          if (preview.shortfall > 0) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: 14,
                  color: c.destructive,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'That is more than the open lots cover.',
                    style: TextStyle(fontSize: 12, color: c.destructive),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Sold from your $lots oldest lot(s) first, the way brokers report '
            'it.',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.amount,
    this.tone = MoneyTone.neutral,
    this.signed = false,
    this.emphasis = false,
  });

  final String label;
  final num amount;
  final MoneyTone tone;
  final bool signed;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: MoneyText(
            amount,
            tone: tone,
            signed: signed,
            compactAbove: Money.crore,
            style: TextStyle(
              fontSize: emphasis ? 14.5 : 13,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SellDematSheet extends StatelessWidget {
  const _SellDematSheet({required this.accounts, this.selectedId});

  final List<Account> accounts;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Demat account',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(LucideIcons.x, size: 20, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                for (final account in accounts)
                  Material(
                    color: account.id == selectedId
                        ? c.primary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: radius,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(account),
                      borderRadius: radius,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                account.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (account.id == selectedId)
                              Icon(
                                LucideIcons.check,
                                size: 18,
                                color: c.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
