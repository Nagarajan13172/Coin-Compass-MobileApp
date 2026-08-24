import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Hue offsets from the theme's primary, in degrees. The 60°-100° band is
/// skipped — yellow at the primary's saturation reads badly on the light
/// background.
const List<double> _hueOffsets = [0, 30, 60, 90, 120, 150, 180, 270, 300, 330];

/// A stable tint per person, so the same person keeps the same colour on every
/// screen. The server stores no colour for people (`color` is stripped by the
/// write schema), so it is derived from [seed] — the person's id where there is
/// one, else their name.
///
/// Derived by rotating the theme's primary hue rather than from a fixed
/// palette, so the tints stay in the token palette in both themes.
Color personTint(BuildContext context, String seed) {
  final primary = context.colors.primary;
  final trimmed = seed.trim();
  if (trimmed.isEmpty) return primary;

  final hash = trimmed.codeUnits.fold<int>(
    7,
    (acc, unit) => (acc * 31 + unit) & 0x1fffffff,
  );
  final base = HSLColor.fromColor(primary);
  final hue = (base.hue + _hueOffsets[hash % _hueOffsets.length]) % 360;
  return base.withHue(hue).toColor();
}

/// Initials in a tinted circle — people have no icon or colour of their own, so
/// the avatar is built entirely from the name.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.seed,
    this.size = 40,
  });

  final String name;

  /// What the tint is derived from. Defaults to [name]; pass the person's id so
  /// two people with the same name still differ.
  final String? seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = personTint(context, seed ?? name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
