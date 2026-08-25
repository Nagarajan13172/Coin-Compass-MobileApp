import '../ui.dart';

import '../theme/app_colors.dart';

/// A labelled row of colour swatches. The selected one is ringed in its own
/// colour, matching the picker in the category sheet.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    super.key,
    required this.hexes,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final List<String> hexes;

  /// Hex string, e.g. `#6366F1`. Compared case-insensitively.
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final hex in hexes)
              GestureDetector(
                onTap: () => onChanged(hex),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hex.toUpperCase() == value.toUpperCase()
                          ? (colorFromHex(hex) ?? c.primary)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorFromHex(hex) ?? c.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
