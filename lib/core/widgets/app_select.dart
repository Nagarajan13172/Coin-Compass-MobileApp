import '../ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// Labelled dropdown that inherits the shared input decoration, used for the
/// API's many enum fields (account type, loan type, frequency, …).
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.enabled = true,
  });

  final List<SelectItem<T>> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        DropdownButtonFormField<T>(
          initialValue: value,
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 18,
            color: c.mutedForeground,
          ),
          dropdownColor: c.popover,
          borderRadius: BorderRadius.circular(12),
          decoration: InputDecoration(hintText: hint, errorText: errorText),
          style: TextStyle(fontSize: 15.5, color: c.foreground),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item.value,
                  child: Row(
                    children: [
                      if (item.icon != null) ...[
                        Icon(item.icon, size: 17, color: c.mutedForeground),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class SelectItem<T> {
  const SelectItem(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}
