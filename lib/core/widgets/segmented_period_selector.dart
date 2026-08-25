import '../ui.dart';

import '../theme/app_colors.dart';

/// The Week / Month / Year pill group from the dashboard: a `secondary` track
/// with the selected pill lifted onto a `card` surface.
class SegmentedPeriodSelector<T> extends StatelessWidget {
  const SegmentedPeriodSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final selected = option.value == value;
          return GestureDetector(
            onTap: selected ? null : () => onChanged(option.value),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? c.card : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.foreground : c.mutedForeground,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption(this.value, this.label);
  final T value;
  final String label;
}
