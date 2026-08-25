import '../ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import 'app_button.dart';

/// The chrome every create/edit sheet shares: title row with a close button, a
/// scrollable body that stays clear of the keyboard, and a pinned footer with
/// the primary action and — when editing — a destructive one.
///
/// Sheets supply only their fields; the sizing, insets and busy handling live
/// here so they behave identically across features.
class FormSheetScaffold extends StatelessWidget {
  const FormSheetScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
    this.submitting = false,
    this.deleteLabel,
    this.onDelete,
    this.deleting = false,
    this.formError,
    this.footnote,
  });

  final String title;

  /// The form's fields, laid out in a ListView.
  final List<Widget> children;

  final String submitLabel;
  final VoidCallback? onSubmit;
  final bool submitting;

  /// Renders a destructive text button under the primary action.
  final String? deleteLabel;
  final VoidCallback? onDelete;
  final bool deleting;

  /// Whole-form failure, normally `ApiException.message`.
  final String? formError;

  /// Optional muted line under the primary action.
  final String? footnote;

  bool get _busy => submitting || deleting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  children: [
                    ...children,
                    if (formError != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        formError!,
                        style: TextStyle(fontSize: 13.5, color: c.destructive),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    AppButton(
                      label: submitLabel,
                      busy: submitting,
                      onPressed: deleting ? null : onSubmit,
                    ),
                    if (footnote != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        footnote!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                    if (deleteLabel != null && onDelete != null) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _busy ? null : onDelete,
                        icon: const Icon(LucideIcons.trash2, size: 17),
                        label: Text(deleting ? 'Deleting…' : deleteLabel!),
                        style: TextButton.styleFrom(
                          foregroundColor: c.destructive,
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
