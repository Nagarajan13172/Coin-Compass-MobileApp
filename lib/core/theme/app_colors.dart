import 'package:flutter/material.dart';

/// Design tokens extracted verbatim from the deployed CoinCompass web CSS
/// (shadcn/ui HSL token model). See docs/SPEC.md section 2.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.destructive,
    required this.income,
    required this.expense,
    required this.border,
    required this.input,
    required this.ring,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color destructive;
  final Color income;
  final Color expense;
  final Color border;
  final Color input;
  final Color ring;

  /// hsl(210 40% 98%) etc. — converted to hex, see the token table in the spec.
  static const AppColors light = AppColors(
    background: Color(0xFFF8FAFC),
    foreground: Color(0xFF0F172A),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0F172A),
    popover: Color(0xFFFFFFFF),
    primary: Color(0xFF2563EB),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFF1F5F9),
    secondaryForeground: Color(0xFF0F172A),
    muted: Color(0xFFF1F5F9),
    mutedForeground: Color(0xFF64748B),
    accent: Color(0xFFE7EDF4),
    destructive: Color(0xFFDC2626),
    income: Color(0xFF089268),
    expense: Color(0xFFDC2626),
    border: Color(0xFFE2E8F0),
    input: Color(0xFFE2E8F0),
    ring: Color(0xFF2563EB),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0F172A),
    foreground: Color(0xFFF8FAFC),
    card: Color(0xFF19212F),
    cardForeground: Color(0xFFF8FAFC),
    popover: Color(0xFF19212F),
    primary: Color(0xFF3B82F6),
    primaryForeground: Color(0xFF0F172A),
    secondary: Color(0xFF1E293B),
    secondaryForeground: Color(0xFFF8FAFC),
    muted: Color(0xFF1E293B),
    mutedForeground: Color(0xFF94A3B8),
    accent: Color(0xFF26313F),
    destructive: Color(0xFFEF4444),
    income: Color(0xFF11C58A),
    expense: Color(0xFFF26A6A),
    border: Color(0xFF2F3B4E),
    input: Color(0xFF2F3B4E),
    ring: Color(0xFF3B82F6),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? popover,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? destructive,
    Color? income,
    Color? expense,
    Color? border,
    Color? input,
    Color? ring,
  }) {
    return AppColors(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      card: card ?? this.card,
      cardForeground: cardForeground ?? this.cardForeground,
      popover: popover ?? this.popover,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      secondary: secondary ?? this.secondary,
      secondaryForeground: secondaryForeground ?? this.secondaryForeground,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      accent: accent ?? this.accent,
      destructive: destructive ?? this.destructive,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      border: border ?? this.border,
      input: input ?? this.input,
      ring: ring ?? this.ring,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
      popover: Color.lerp(popover, other.popover, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryForeground: Color.lerp(
        secondaryForeground,
        other.secondaryForeground,
        t,
      )!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  /// Theme-aware access to the CoinCompass design tokens.
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

/// Parses a `#RRGGBB` / `#AARRGGBB` string from the API (categories, goals) into a Color.
Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
