import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/lucide_map.dart';

/// Tinted circle + lucide glyph, coloured from the category's `color` hex.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    this.icon,
    this.colorHex,
    this.size = 40,
    this.fallbackColor,
  });

  final String? icon;
  final String? colorHex;
  final double size;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final accent =
        colorFromHex(colorHex) ?? fallbackColor ?? context.colors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(lucideIcon(icon), size: size * 0.5, color: accent),
    );
  }
}
