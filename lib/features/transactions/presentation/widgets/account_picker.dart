import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/money_text.dart';
import '../../../accounts/data/accounts_repository.dart';
import '../../../accounts/domain/account.dart';
import '../../../settings/data/settings_repository.dart';
import '../transactions_providers.dart';

/// Tappable, input-styled row used by every picker in the transaction sheet
/// (account, category, date). It mirrors [AppTextField]'s label + filled input
/// so a picker never looks like a foreign control next to a real field.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.hint,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.errorText,
  });

  final String label;

  /// Shown in `mutedForeground` when [value] is null.
  final String hint;
  final String? value;
  final Widget? leading;

  /// Defaults to a chevron.
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);
    final filled = value != null && value!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        Material(
          color: c.secondary,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: errorText != null ? c.destructive : c.border,
                ),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      filled ? value! : hint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: filled ? FontWeight.w500 : FontWeight.w400,
                        color: filled ? c.foreground : c.mutedForeground,
                      ),
                    ),
                  ),
                  trailing ??
                      Icon(
                        LucideIcons.chevronDown,
                        size: 18,
                        color: c.mutedForeground,
                      ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: c.destructive),
            ),
          ),
      ],
    );
  }
}

/// Opens the account sheet. Resolves to the chosen account, or null when the
/// sheet is dismissed.
///
/// [excludeId] hides one account — the transfer form uses it so the same
/// account can never sit on both sides.
Future<Account?> showAccountPicker(
  BuildContext context, {
  String? selectedId,
  String? excludeId,
  String title = 'Select account',
}) {
  return showModalBottomSheet<Account>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountPickerSheet(
      selectedId: selectedId,
      excludeId: excludeId,
      title: title,
    ),
  );
}

/// A [PickerField] wired to [showAccountPicker].
class AccountPickerField extends StatelessWidget {
  const AccountPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Account',
    this.hint = 'Select account',
    this.excludeId,
    this.errorText,
  });

  final Account? value;
  final ValueChanged<Account> onChanged;
  final String label;
  final String hint;
  final String? excludeId;
  final String? errorText;

  Future<void> _open(BuildContext context) async {
    final picked = await showAccountPicker(
      context,
      selectedId: value?.id,
      excludeId: excludeId,
      title: label,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final account = value;
    return PickerField(
      label: label,
      hint: hint,
      value: account?.name,
      errorText: errorText,
      onTap: () => _open(context),
      leading: account == null
          ? null
          : CategoryAvatar(
              icon: account.type.icon,
              colorHex: account.color,
              size: 30,
              fallbackColor: context.colors.primary,
            ),
    );
  }
}

class _AccountPickerSheet extends ConsumerWidget {
  const _AccountPickerSheet({
    this.selectedId,
    this.excludeId,
    required this.title,
  });

  final String? selectedId;
  final String? excludeId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accounts = ref.watch(accountsProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
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
            child: accounts.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    LoadingShimmer(height: 52),
                    SizedBox(height: 10),
                    LoadingShimmer(height: 52),
                    SizedBox(height: 10),
                    LoadingShimmer(height: 52),
                  ],
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ErrorRetry(
                  error: error,
                  compact: true,
                  onRetry: () => ref.invalidate(accountsFetchProvider),
                ),
              ),
              data: (items) => _list(context, ref, items),
            ),
          ),
          SizedBox(height: 8 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<Account> all) {
    // An archived account stays visible while it is the current selection, so
    // editing an old row never silently drops its account.
    final visible = all
        .where((a) => a.id != excludeId)
        .where((a) => !a.archived || a.id == selectedId)
        .toList();

    if (visible.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.wallet,
        title: 'No accounts yet',
        message: 'Add an account first — every transaction needs one.',
        compact: true,
      );
    }

    final symbol = ref.watch(currencySymbolProvider);
    final balances =
        ref.watch(transactionBalanceProvider).valueOrNull?.byAccount ??
        const <String, num>{};

    final children = <Widget>[];
    for (final type in AccountType.values) {
      final rows = visible.where((a) => a.type == type).toList();
      if (rows.isEmpty) continue;
      children.add(_groupLabel(context, type.label));
      for (final account in rows) {
        children.add(
          _AccountRow(
            account: account,
            balance: balances[account.id] ?? account.balance,
            symbol: symbol,
            selected: account.id == selectedId,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: children,
    );
  }

  Widget _groupLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: context.colors.mutedForeground,
      ),
    ),
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balance,
    required this.symbol,
    required this.selected,
  });

  final Account account;
  final num? balance;
  final String symbol;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);
    final subtitle = account.institution?.isNotEmpty == true
        ? account.institution!
        : (account.last4 != null
              ? '•••• ${account.last4}'
              : account.type.label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? c.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(account),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                CategoryAvatar(
                  icon: account.type.icon,
                  colorHex: account.color,
                  size: 38,
                  fallbackColor: c.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (balance != null)
                  MoneyText(
                    balance!,
                    symbol: symbol,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(LucideIcons.check, size: 18, color: c.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
