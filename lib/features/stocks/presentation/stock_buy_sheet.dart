import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../../core/widgets/money_text.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/presentation/widgets/account_picker.dart'
    show PickerField;
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';
import 'stock_search_sheet.dart';
import 'stocks_providers.dart';

/// Records a purchase lot — `POST /stocks/buy`.
///
/// The body is assembled inside [StocksRepository.buy] from typed arguments, so
/// this sheet cannot widen it. That matters: the schema declares exactly
/// `symbol, demat, qty, buyPrice, buyDate, note` and silently drops anything
/// else. The web client sends a `charges` and a `recordCash` alongside them and
/// both vanish server-side, so there is deliberately no control for either
/// here — see docs/WRITE_SCHEMAS.md.
class StockBuySheet extends ConsumerStatefulWidget {
  const StockBuySheet({super.key, this.preset});

  /// Pre-selects the instrument — used by "Buy more" on an existing position.
  final StockQuote? preset;

  /// Pops `true` when a lot was recorded.
  static Future<bool?> show(BuildContext context, {StockQuote? preset}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockBuySheet(preset: preset),
    );
  }

  @override
  ConsumerState<StockBuySheet> createState() => _StockBuySheetState();
}

class _StockBuySheetState extends ConsumerState<StockBuySheet> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late StockQuote? _stock = widget.preset;
  String? _dematId;
  DateTime _buyDate = DateTime.now();

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _stockError;
  String? _dematError;
  String? _qtyError;
  String? _priceError;

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

    // Nothing on this form can be posted without a demat account, so the whole
    // form is replaced rather than shown in a state that cannot submit.
    if (demats.isEmpty) {
      return _NoDematSheet(onGoToAccounts: _goToAccounts);
    }

    final demat = _resolveDemat(demats);
    final total = _totalCost();

    return FormSheetScaffold(
      title: 'Add a purchase',
      submitLabel: 'Add purchase',
      submitting: _saving,
      onSubmit: _submit,
      formError: _formError,
      footnote:
          'Brokerage, STT and stamp duty are not stored — the server keeps the '
          'quantity and the price you paid.',
      children: [
        _StockField(
          value: _stock,
          errorText: _stockError ?? _apiError?.fieldError('symbol'),
          enabled: !_saving,
          onChanged: (quote) => setState(() {
            _stock = quote;
            _stockError = null;
          }),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Demat account',
          hint: 'Pick a demat account',
          value: demat == null
              ? null
              : '${demat.name} · ${Money.format(demat.balance ?? demat.openingBalance)}',
          errorText: _dematError ?? _apiError?.fieldError('demat'),
          leading: Icon(
            LucideIcons.landmark,
            size: 18,
            color: c.mutedForeground,
          ),
          onTap: _saving ? null : () => _pickDemat(demats),
        ),
        const SizedBox(height: 14),
        // Full width, not two columns: a half-row cannot hold "Price per
        // share" and its keypad-sized value on a 360dp phone.
        AppTextField(
          label: 'Quantity',
          controller: _qty,
          hint: '10',
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [const AmountInputFormatter(decimals: 4)],
          errorText: _qtyError ?? _apiError?.fieldError('qty'),
          onChanged: (_) => _clearFieldErrors(),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Price per share',
          controller: _price,
          hint: '1,322',
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [const AmountInputFormatter()],
          errorText: _priceError ?? _apiError?.fieldError('buyPrice'),
          onChanged: (_) => _clearFieldErrors(),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Purchase date',
          hint: 'Pick a date',
          value: DateX.shortDay(_buyDate),
          errorText: _apiError?.fieldError('buyDate'),
          leading: Icon(
            LucideIcons.calendar,
            size: 18,
            color: c.mutedForeground,
          ),
          onTap: _saving ? null : _pickDate,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Note',
          controller: _note,
          hint: 'Optional',
          enabled: !_saving,
          maxLines: 2,
          errorText: _apiError?.fieldError('note'),
        ),
        if (total != null) ...[
          const SizedBox(height: 16),
          _TotalRow(label: 'Total cost', amount: total),
        ],
      ],
    );
  }

  /// The chosen account, or the first demat account when nothing is chosen yet
  /// — a wallet with one demat account should not have to pick it.
  Account? _resolveDemat(List<Account> demats) {
    final id = _dematId;
    if (id != null) {
      for (final account in demats) {
        if (account.id == id) return account;
      }
    }
    return demats.first;
  }

  num? _totalCost() {
    final qty = parseAmount(_qty.text);
    final price = parseAmount(_price.text);
    if (qty == null || price == null || qty <= 0 || price < 0) return null;
    return qty * price;
  }

  void _clearFieldErrors() {
    // Unconditional: the total-cost line is computed in build, so every
    // keystroke has to rebuild whether or not an error was showing.
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
      builder: (_) => _DematPickerSheet(
        accounts: demats,
        selectedId: _resolveDemat(demats)?.id,
      ),
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
      initialDate: _buyDate,
      firstDate: DateTime(1990),
      // A lot cannot be bought in the future; the LTCG clock starts on this day.
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _buyDate = DateTime(picked.year, picked.month, picked.day));
  }

  void _goToAccounts() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.go('/accounts');
  }

  /// **Deliberately synchronous (6.4).** Positions, average cost and realised
  /// P&L are all derived server-side by FIFO lot matching, so an optimistic
  /// average cost would be a fabricated number about the owner's portfolio.
  /// See lib/core/state/optimistic.dart.
  Future<void> _submit() async {
    final stock = _stock;
    final demat = _resolveDemat(ref.read(dematAccountsProvider));
    final qty = parseAmount(_qty.text);
    final price = parseAmount(_price.text);

    if (stock == null ||
        demat == null ||
        qty == null ||
        qty <= 0 ||
        price == null ||
        price < 0) {
      setState(() {
        _stockError = stock == null ? 'Pick a stock first' : null;
        _dematError = demat == null ? 'Pick a demat account' : null;
        _qtyError = (qty == null || qty <= 0) ? 'Enter a quantity' : null;
        _priceError = (price == null || price < 0) ? 'Enter a price' : null;
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
          .buy(
            symbol: stock.symbol,
            demat: demat.id,
            qty: qty,
            buyPrice: price,
            buyDate: _buyDate,
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
}

/// The stock row: a search trigger while empty, the chosen instrument with a
/// "Change" action once picked.
class _StockField extends StatelessWidget {
  const _StockField({
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.errorText,
  });

  final StockQuote? value;
  final ValueChanged<StockQuote> onChanged;
  final bool enabled;
  final String? errorText;

  Future<void> _search(BuildContext context) async {
    final picked = await StockSearchSheet.show(context);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quote = value;

    if (quote == null) {
      return PickerField(
        label: 'Stock',
        hint: 'Search a stock by name or ticker',
        errorText: errorText,
        leading: Icon(LucideIcons.search, size: 18, color: c.mutedForeground),
        trailing: Icon(
          LucideIcons.chevronRight,
          size: 18,
          color: c.mutedForeground,
        ),
        onTap: enabled ? () => _search(context) : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Stock',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: c.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.circleCheck, size: 18, color: c.income),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        quote.ticker ?? quote.symbol,
                        ?quote.exchange,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: enabled ? () => _search(context) : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `Total cost   ₹13,220` — a computed line, never an input.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount});

  final String label;
  final num amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              label,
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
          ),
          MoneyText(
            amount,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DematPickerSheet extends StatelessWidget {
  const _DematPickerSheet({required this.accounts, this.selectedId});

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
                            MoneyText(
                              account.balance ?? account.openingBalance,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (account.id == selectedId) ...[
                              const SizedBox(width: 8),
                              Icon(
                                LucideIcons.check,
                                size: 18,
                                color: c.primary,
                              ),
                            ],
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

/// Shown instead of the form when the wallet has no demat account: there is no
/// value to put in `demat`, and the server requires it.
class _NoDematSheet extends StatelessWidget {
  const _NoDematSheet({required this.onGoToAccounts});

  final VoidCallback onGoToAccounts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add a purchase',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(LucideIcons.x, size: 20, color: c.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DashedBox(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.landmark,
                      size: 22,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No demat account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Every purchase is filed against a demat account. Create '
                      'one under Accounts before adding stocks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Go to Accounts',
              icon: LucideIcons.arrowRight,
              onPressed: onGoToAccounts,
            ),
          ],
        ),
      ),
    );
  }
}
