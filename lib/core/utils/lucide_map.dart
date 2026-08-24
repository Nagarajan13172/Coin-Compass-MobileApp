import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The backend stores category/goal icons as **lucide** kebab-case names
/// (`shopping-cart`, `heart-pulse`, …). This maps them to the Flutter package's
/// camelCase constants. Every identifier below was verified against
/// lucide_icons_flutter 3.1.17.
const Map<String, IconData> _lucideByName = <String, IconData>{
  // the 26 names actually in use by the seeded categories
  'banknote': LucideIcons.banknote,
  'briefcase': LucideIcons.briefcase,
  'car': LucideIcons.car,
  'clapperboard': LucideIcons.clapperboard,
  'coffee': LucideIcons.coffee,
  'credit-card': LucideIcons.creditCard,
  'ellipsis': LucideIcons.ellipsis,
  'fuel': LucideIcons.fuel,
  'gamepad': LucideIcons.gamepad2,
  'gamepad-2': LucideIcons.gamepad2,
  'gift': LucideIcons.gift,
  'graduation-cap': LucideIcons.graduationCap,
  'heart-pulse': LucideIcons.heartPulse,
  'home': LucideIcons.house,
  'house': LucideIcons.house,
  'laptop': LucideIcons.laptop,
  'percent': LucideIcons.percent,
  'piggy-bank': LucideIcons.piggyBank,
  'pizza': LucideIcons.pizza,
  'plane': LucideIcons.plane,
  'receipt': LucideIcons.receipt,
  'repeat': LucideIcons.repeat,
  'rotate-ccw': LucideIcons.rotateCcw,
  'shopping-bag': LucideIcons.shoppingBag,
  'shopping-cart': LucideIcons.shoppingCart,
  'sparkles': LucideIcons.sparkles,
  'trending-up': LucideIcons.trendingUp,
  'utensils': LucideIcons.utensils,

  // app chrome + defaults used by goals, nav and empty states
  'goal': LucideIcons.goal,
  'target': LucideIcons.target,
  'wallet': LucideIcons.wallet,
  'compass': LucideIcons.compass,
  'landmark': LucideIcons.landmark,
  // every AccountType.icon must resolve here — 'smartphone' is UPI's glyph
  'smartphone': LucideIcons.smartphone,
  'coins': LucideIcons.coins,
  'chart-pie': LucideIcons.chartPie,
  'bell': LucideIcons.bell,
  'settings': LucideIcons.settings,
  'search': LucideIcons.search,
  'plus': LucideIcons.plus,
  'layout-grid': LucideIcons.layoutGrid,
  'arrow-right-left': LucideIcons.arrowRightLeft,
  'circle': LucideIcons.circle,
};

/// Resolves an API icon name, tolerating camelCase and snake_case variants.
/// Unknown names fall back rather than throwing — the backend may add icons.
IconData lucideIcon(String? name, {IconData fallback = LucideIcons.circle}) {
  if (name == null || name.trim().isEmpty) return fallback;
  final key = name.trim().toLowerCase();
  final direct = _lucideByName[key];
  if (direct != null) return direct;

  // shoppingCart / shopping_cart -> shopping-cart
  final normalised = key
      .replaceAll('_', '-')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .toLowerCase();
  return _lucideByName[normalised] ?? fallback;
}
