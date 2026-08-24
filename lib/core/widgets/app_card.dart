import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The surface every screen is built from: `card` background, 1px `border`,
/// 12px radius, whisper-soft shadow. Matches the web app's card treatment.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? c.card : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    final wrapped = onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(onTap: onTap, borderRadius: radius, child: content),
          );

    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}
