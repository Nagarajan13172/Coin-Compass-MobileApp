import '../ui.dart';

/// Primary / outlined button with a built-in busy state, so callers don't
/// re-implement "disable and swap in a spinner" on every form.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              // 7.1/7.3 — `Flexible`, not a bare `Text`. A `Row` sized to its
              // children hands an unbounded width to an unconstrained `Text`,
              // so a label wider than the button *overflows* rather than
              // ellipsising. In English that almost never happens; the device
              // walk in Tamil overflowed three buttons on the import screen at
              // once (1.3px, 12px and 126px), because Tamil runs up to 173% of
              // the English width — see PHASE7_1_REPORT.
              //
              // Ellipsis rather than wrap: these buttons have a fixed 46-48px
              // height from the shared theme, so a second line would be clipped
              // instead of shown.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );

    final handler = busy ? null : onPressed;

    // The shared theme sets `minimumSize: Size.fromHeight(48)` — an *infinite*
    // minimum width — so ButtonStyleButton's ConstrainedBox clamps minWidth up
    // to the parent's maxWidth and an `expand: false` button still fills the
    // row. Override only the sizing here; colours, shape and textStyle keep
    // resolving from the theme, because a widget-level style merges per
    // property over `themeStyleOf`.
    final compact = expand
        ? null
        : const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 46)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );

    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: handler,
        style: compact,
        child: child,
      ),
      AppButtonVariant.outlined => OutlinedButton(
        onPressed: handler,
        style: compact,
        child: child,
      ),
      // TextButton is left alone: textButtonTheme sets no minimumSize, so it
      // already hugs its label at its own (smaller) default metrics.
      AppButtonVariant.text => TextButton(onPressed: handler, child: child),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum AppButtonVariant { primary, outlined, text }
