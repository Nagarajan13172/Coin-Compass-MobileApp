import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/lucide_map.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../data/accounts_repository.dart';
import '../domain/account.dart';

/// Icons offered for an account. Every name resolves in `lucide_map.dart`, and
/// the set covers the account types the API knows about.
const List<String> accountIconNames = [
  'wallet',
  'landmark',
  'credit-card',
  'banknote',
  'piggy-bank',
  'coins',
  'trending-up',
];

/// Swatches for an account's colour. The first entry is the server's own
/// default, so "untouched" and "explicitly default" look the same on screen.
const List<String> accountColorHexes = [
  '#2563EB',
  '#0EA5E9',
  '#14B8A6',
  '#22C55E',
  '#F59E0B',
  '#F97316',
  '#EF4444',
  '#EC4899',
  '#8B5CF6',
  '#64748B',
];

/// Create / edit an account. The native stand-in for the web app's account
/// modal — same fields, same order.
///
/// Every input here maps to a key POST/PATCH `/accounts` actually accepts
/// (`name, type, initialBalance, currency, color, icon, includeInTotal`); the
/// server strips anything else, so a control for an unsupported key would look
/// like it saved and quietly throw the value away.
///
/// Pops `true` when the account list changed (created, updated or deleted).
class AccountFormSheet extends ConsumerStatefulWidget {
  const AccountFormSheet({super.key, this.account});

  /// Null creates a new account; non-null edits that one.
  final Account? account;

  static Future<bool?> show(BuildContext context, {Account? account}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountFormSheet(account: account),
    );
  }

  @override
  ConsumerState<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<AccountFormSheet> {
  late final Account? _existing = widget.account;

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );
  late final TextEditingController _openingBalance = TextEditingController(
    text: _existing == null ? '' : _plainNumber(_existing.openingBalance),
  );

  late AccountType _type = _existing?.type ?? AccountType.bank;
  late bool _excludeFromTotal = _existing?.excludeFromTotal ?? false;
  late String _icon = _defaultIconFor(_existing?.icon, _type);
  late String _color = _existing?.color ?? accountColorHexes.first;
  late final List<String> _swatches = _buildSwatches();

  /// Once the user picks an icon we stop re-deriving it from the type.
  bool _iconChosen = false;

  bool _saving = false;
  String? _formError;
  ApiException? _apiError;
  String? _nameError;

  bool get _isEdit => _existing != null;

  /// An account's icon defaults to its type's glyph when that glyph is one of
  /// the offered names, otherwise to the server's own default.
  static String _defaultIconFor(String? existing, AccountType type) {
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    return accountIconNames.contains(type.icon) ? type.icon : 'wallet';
  }

  /// Keeps an off-palette colour set elsewhere (the web app) visible.
  List<String> _buildSwatches() {
    final existing = _existing?.color?.toUpperCase();
    if (existing == null ||
        accountColorHexes.any((c) => c.toUpperCase() == existing)) {
      return accountColorHexes;
    }
    return [existing, ...accountColorHexes];
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 6.4: there is no separate `_deleting` flag any more — a delete pops the
    // sheet on the spot and reports from the list, so nothing here spins for it.
    final busy = _saving;

    return PopScope(
      // Belt and braces: a write already survives dismissal (the invalidation
      // goes through the container, not `ref`), but there is no reason to let
      // the back button race an in-flight request.
      canPop: !busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEdit ? 'Edit account' : 'New account',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    children: [
                      AppTextField(
                        label: 'Name',
                        controller: _name,
                        hint: 'e.g. HDFC Savings',
                        autofocus: !_isEdit,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        errorText: _nameError ?? _apiError?.fieldError('name'),
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      AppSelect<AccountType>(
                        label: 'Type',
                        value: _type,
                        enabled: !busy,
                        errorText: _apiError?.fieldError('type'),
                        items: [
                          for (final type in AccountType.values)
                            SelectItem(
                              type,
                              type.label,
                              icon: lucideIcon(type.icon),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _type = value;
                            if (!_iconChosen) {
                              _icon = _defaultIconFor(null, value);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Opening balance',
                        controller: _openingBalance,
                        hint: _amountHint,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        // The server keys this error `initialBalance`.
                        errorText: _apiError?.fieldError('initialBalance'),
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Icon'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final name in accountIconNames)
                            _IconOption(
                              name: name,
                              accent: colorFromHex(_color) ?? c.primary,
                              selected: name == _icon,
                              onTap: busy
                                  ? null
                                  : () => setState(() {
                                      _icon = name;
                                      _iconChosen = true;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Colour'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final hex in _swatches)
                            _ColorOption(
                              hex: hex,
                              selected:
                                  hex.toUpperCase() == _color.toUpperCase(),
                              onTap: busy
                                  ? null
                                  : () => setState(() => _color = hex),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ExcludeSwitch(
                        value: _excludeFromTotal,
                        enabled: !busy,
                        onChanged: (value) =>
                            setState(() => _excludeFromTotal = value),
                      ),
                      if (_formError != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _formError!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: c.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    children: [
                      AppButton(
                        label: _isEdit ? 'Save changes' : 'Create account',
                        busy: _saving,
                        onPressed: _submit,
                      ),
                      if (_isEdit) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: busy ? null : _delete,
                          icon: const Icon(LucideIcons.trash2, size: 17),
                          label: const Text('Delete account'),
                          style: TextButton.styleFrom(
                            foregroundColor: c.destructive,
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _currency => _existing?.currency ?? 'INR';

  String get _amountHint => _currency == 'INR' ? '₹0' : '0';

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }

    final body = _buildBody(name);
    final existing = _existing;

    // 6.4 — an edit whose result the client can predict repaints at once and
    // settles in the background. `Account.predict` returns null when the
    // opening balance moved, because the server's running balance then shifts
    // by an amount only the whole ledger could re-derive; that submission falls
    // through to the spinner below. A **create** always falls through too: the
    // server assigns `_id` and `createdAt`, a provisional row would have no id
    // to tap, and a failed create is the one failure that destroys typed input,
    // which only an open form can carry honestly.
    final predicted = existing?.predict(
      name: name,
      type: _type,
      openingBalance: _parseAmount(_openingBalance.text) ?? 0,
      currency: _currency,
      excludeFromTotal: _excludeFromTotal,
      color: _color,
      icon: _icon,
    );
    if (existing != null && predicted != null) {
      _runOptimistic(existing, predicted, body);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _apiError = null;
      _nameError = null;
    });

    // Captured while the element is alive: the write must refresh the account
    // list even if the sheet is dismissed mid-request, and `ref` throws once
    // disposed. `ProviderContainer.invalidate` has no such assertion.
    final container = ProviderScope.containerOf(context, listen: false);

    try {
      final repository = ref.read(accountsRepositoryProvider);
      if (existing != null) {
        await repository.update(existing.id, body);
      } else {
        await repository.create(body);
      }
      container.invalidate(accountsFetchProvider);
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

  /// Closes the sheet on the predicted row and hands the write to the one
  /// mechanism. Everything the rollback needs is captured before the pop,
  /// because `ref` and `context` die with this element.
  void _runOptimistic(
    Account existing,
    Account predicted,
    Map<String, dynamic> body,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(accountsRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(accountsWritesProvider.notifier)
          .run<Account>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settleAccounts(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              // The attempted row, not the stale one — nothing typed is lost.
              AccountFormSheet.show(messenger.context, account: predicted);
            },
          ),
    );
  }

  Future<void> _delete() async {
    final account = _existing;
    if (account == null) return;

    // Taken before the first await, for the same reason as in `_submit`.
    final container = ProviderScope.containerOf(context, listen: false);

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete ${account.name}?',
      message:
          'The account is removed from your list. Transactions that used it are kept.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — the client knows exactly what a delete does to the list, so the
    // row leaves now. There is no `/accounts/:id/restore`, so no Undo is
    // offered: re-POSTing would make a *new* account with a new id and nothing
    // referencing it. The ConfirmSheet above is the pre-flight guard instead.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(accountsRepositoryProvider);

    Navigator.of(context).pop(true);

    unawaited(
      container
          .read(accountsWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(account.id),
            send: () => repository.delete(account.id),
            settle: () => settleAccounts(container),
            messenger: messenger,
            noun: account.name,
            successMessage: 'Deleted ${account.name}',
          ),
    );
  }

  /// Wire body — exactly the keys the accounts schema accepts.
  Map<String, dynamic> _buildBody(String name) => {
    'name': name,
    'type': _type.api,
    'initialBalance': _parseAmount(_openingBalance.text) ?? 0,
    'currency': _currency,
    'color': _color,
    'icon': _icon,
    'includeInTotal': !_excludeFromTotal,
  };

  /// Accepts what a user actually types — `1,200`, `₹1200`, `-450.5`.
  static num? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return null;
    return num.tryParse(cleaned);
  }

  static String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.name,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : c.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Icon(
          lucideIcon(name),
          size: 20,
          color: selected ? accent : c.mutedForeground,
        ),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = colorFromHex(hex) ?? c.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _ExcludeSwitch extends StatelessWidget {
  const _ExcludeSwitch({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exclude from total',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Keep this account out of your balance and net worth.',
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
