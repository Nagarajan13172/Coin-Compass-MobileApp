import '../ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// `[‹]  August 2026  [›]` — the period stepper on Reports and Insights.
///
/// Both screens were built in parallel and each grew its own copy: one packed
/// the arrows inside a single bordered pill, the other used three separate
/// boxes, and the two disagreed on arrow size and label weight. This is the
/// surviving one, shaped like [MonthPager] (the ledger's month stepper) so all
/// three steppers in the app read as the same control.
///
/// Label text is [PeriodRange.periodLabel]'s job, not this widget's — it
/// renders whatever string it is handed, scaled down rather than ellipsised so
/// `04 Aug – 10 Aug` never loses an end.
///
/// Deliberately **not** clamped to today: the web lets you page into the
/// future, where the server simply answers an empty period.
class PeriodPager extends StatelessWidget {
  const PeriodPager({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.expand = true,
    this.labelWidth = 150,
  });

  /// The window's own name — 'August 2026', '04 Aug – 10 Aug', '2026'.
  final String label;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// True (the default) fills the row: the label takes whatever is left over.
  /// False makes the whole control [labelWidth]-bounded and intrinsically
  /// sized, which is what lets Reports put it in a `Wrap` beside the
  /// Week/Month/Year selector.
  final bool expand;

  /// Width of the label box when [expand] is false.
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    Widget arrow(IconData icon, String semanticLabel, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: semanticLabel,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: radius,
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 18, color: c.foreground),
            ),
          ),
        );

    final labelBox = Container(
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: radius,
        border: Border.all(color: c.border),
      ),
      // Scale down rather than truncate: a clipped '04 Aug – 10 Au' reads as
      // a bug, a slightly smaller one does not.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        arrow(LucideIcons.chevronLeft, 'Previous period', onPrevious),
        const SizedBox(width: 8),
        if (expand)
          Expanded(child: labelBox)
        else
          SizedBox(width: labelWidth, child: labelBox),
        const SizedBox(width: 8),
        arrow(LucideIcons.chevronRight, 'Next period', onNext),
      ],
    );
  }
}
