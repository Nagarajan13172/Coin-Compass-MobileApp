import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_x.dart';

/// `[<]  [ 🗓 August 2026 ⌄ ]  [>]` — the month stepper on Transactions.
class MonthPager extends StatelessWidget {
  const MonthPager({
    super.key,
    required this.month,
    required this.onChanged,
    this.onPick,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    Widget arrow(IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        width: 44,
        height: 46,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: radius,
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 18, color: c.foreground),
      ),
    );

    return Row(
      children: [
        arrow(LucideIcons.chevronLeft, () => onChanged(month.addMonths(-1))),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: onPick,
            borderRadius: radius,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: radius,
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 17,
                    color: c.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateX.monthLabel(month),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (onPick != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: c.mutedForeground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        arrow(LucideIcons.chevronRight, () => onChanged(month.addMonths(1))),
      ],
    );
  }
}
