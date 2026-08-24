import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// The block every list screen opens with: a 28sp title, a muted one-line
/// description, and the screen's call-to-action buttons — the same composition
/// the web app puts at the top of Budgets, Goals, Credits and Recurring.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<ScreenHeaderAction> actions;

  /// Renders a back row above the title — set on the screens reached from
  /// another screen rather than from the nav (People, Splits).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, onBack == null ? 16 : 6, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(LucideIcons.chevronLeft, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                  foregroundColor: c.mutedForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 15, color: c.mutedForeground),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            // Wrap, not Row: two labelled buttons don't always fit 360dp.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final action in actions) _ActionButton(action)],
            ),
          ],
        ],
      ),
    );
  }
}

class ScreenHeaderAction {
  const ScreenHeaderAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Primary renders filled, secondary outlined — matching the web CTAs.
  final bool primary;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.action);

  final ScreenHeaderAction action;

  @override
  Widget build(BuildContext context) {
    // The shared button themes set `minimumSize: Size.fromHeight(48)`, i.e. an
    // infinite minimum width, which would stretch each CTA across the row. The
    // web buttons hug their label, so only the sizing is overridden — every
    // colour, shape and text token still comes from the theme.
    const size = Size(0, 46);
    const padding = EdgeInsets.symmetric(horizontal: 18);
    final icon = Icon(action.icon, size: 18);
    final label = Text(action.label);

    return action.primary
        ? FilledButton.icon(
            onPressed: action.onPressed,
            icon: icon,
            label: label,
            style: FilledButton.styleFrom(minimumSize: size, padding: padding),
          )
        : OutlinedButton.icon(
            onPressed: action.onPressed,
            icon: icon,
            label: label,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: padding,
            ),
          );
  }
}
