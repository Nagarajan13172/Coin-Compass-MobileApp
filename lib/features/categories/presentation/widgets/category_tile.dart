import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../domain/category.dart';

/// One row of the Categories screen: tinted lucide avatar, the name, a
/// "Default" chip for the seeded categories, and a chevron into the edit sheet.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.onTap});

  final Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CategoryAvatar(icon: category.icon, colorHex: category.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (category.isDefault) ...[
            const _DefaultChip(),
            const SizedBox(width: 8),
          ],
          Icon(LucideIcons.chevronRight, size: 18, color: c.mutedForeground),
        ],
      ),
    );
  }
}

class _DefaultChip extends StatelessWidget {
  const _DefaultChip();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Default',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}
