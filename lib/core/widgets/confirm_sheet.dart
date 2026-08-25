import '../ui.dart';

import '../theme/app_colors.dart';
import 'app_button.dart';

/// Destructive confirmation as a bottom sheet — the native equivalent of the
/// web app's confirm dialog.
class ConfirmSheet {
  const ConfirmSheet._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    bool destructive = true,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(fontSize: 14.5, color: c.mutedForeground),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: destructive ? c.destructive : c.primary,
                  ),
                  child: Text(confirmLabel),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: cancelLabel,
                  variant: AppButtonVariant.text,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}
