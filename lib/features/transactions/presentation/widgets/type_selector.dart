import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';

Color typeTint(AppColors c, TransactionType type) => switch (type) {
  TransactionType.expense => c.expense,
  TransactionType.income => c.income,
  TransactionType.transfer => c.primary,
};

/// Expense / Income / Transfer, each pill filled with its own token.
class TransactionTypeSelector extends StatelessWidget {
  const TransactionTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  static const List<TransactionType> _order = [
    TransactionType.expense,
    TransactionType.income,
    TransactionType.transfer,
  ];

  static IconData _icon(TransactionType type) => switch (type) {
    TransactionType.expense => LucideIcons.arrowUpRight,
    TransactionType.income => LucideIcons.arrowDownLeft,
    TransactionType.transfer => LucideIcons.arrowRightLeft,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: _order.map((type) {
          final selected = type == value;
          final foreground = selected ? Colors.white : c.mutedForeground;
          return Expanded(
            child: GestureDetector(
              onTap: selected ? null : () => onChanged(type),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? typeTint(c, type) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icon(type), size: 15, color: foreground),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
