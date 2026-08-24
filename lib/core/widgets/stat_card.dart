import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_card.dart';
import 'money_text.dart';

/// The Income / Expense / Net tiles on the dashboard: a tinted rounded-square
/// icon, a muted label, and a large value.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    this.amount,
    this.valueText,
    this.subtitle,
    this.tone = MoneyTone.neutral,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final num? amount;
  final String? valueText;
  final String? subtitle;
  final MoneyTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: c.mutedForeground),
                ),
                const SizedBox(height: 2),
                if (valueText != null)
                  Text(
                    valueText!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  MoneyText(
                    amount ?? 0,
                    tone: tone,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: c.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
