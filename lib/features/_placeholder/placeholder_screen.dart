import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';

/// Stands in for a screen that hasn't been built yet, so every route in the
/// shell is navigable from day one. Replaced feature-by-feature in phases 2–5.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.icon = LucideIcons.circleDashed,
    this.phase,
  });

  final String title;
  final IconData icon;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Expanded(
          child: EmptyState(
            icon: icon,
            title: 'Coming next',
            message: phase == null
                ? '$title is being built.'
                : '$title arrives in $phase.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'CoinCompass · connected to your live account',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ),
      ],
    );
  }
}
