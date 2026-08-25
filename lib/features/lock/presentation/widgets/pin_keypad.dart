import '../../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// The filled/empty dot row above the keypad.
///
/// Owns nothing but its shake: [shakeToken] is bumped by the controller on
/// every wrong PIN, so the animation replays without the screen holding
/// animation state of its own. 200ms, bounded, disposed — a test can pump past
/// it with an explicit duration.
class PinDots extends StatefulWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.shakeToken = 0,
    this.tone,
  });

  final int length;
  final int filled;
  final int shakeToken;
  final Color? tone;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void didUpdateWidget(PinDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shakeToken != oldWidget.shakeToken) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = widget.tone ?? c.primary;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Three quick passes either side, damped to nothing.
        final t = _shake.value;
        final offset = t == 0
            ? 0.0
            : 9.0 * (1 - t) * _sin3(t);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < widget.filled ? tone : Colors.transparent,
                  border: Border.all(
                    color: i < widget.filled ? tone : c.border,
                    width: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// sin(6π·t) without importing dart:math for one call — a cheap triangle
  /// wave reads the same at 200ms.
  double _sin3(double t) {
    final phase = (t * 3) % 1.0;
    return phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4);
  }
}

/// A 3×4 keypad: digits, a backspace, and an optional biometric key.
///
/// Deliberately **not** a `TextField`. No IME, so no keyboard-height reflow at
/// 360dp; no clipboard, no autofill, no password manager offering to fill the
/// owner's banking PIN into a lock screen. Every key is a 64dp target.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  /// Renders the fingerprint key in the bottom-left slot when non-null.
  final VoidCallback? onBiometric;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          _KeyRow(
            children: [
              for (final digit in row)
                _PinKey(
                  label: '$digit',
                  onTap: enabled ? () => onDigit(digit) : null,
                ),
            ],
          ),
        _KeyRow(
          children: [
            if (onBiometric != null)
              _PinKey(
                icon: LucideIcons.fingerprint,
                semanticLabel: tr(context, 'Unlock with fingerprint'),
                // Live even during a PIN cooldown: the OS counts fingerprint
                // failures separately, and the owner must not be punished for a
                // stranger's guesses at the keypad.
                onTap: onBiometric,
              )
            else
              const _PinKey(),
            _PinKey(label: '0', onTap: enabled ? () => onDigit(0) : null),
            _PinKey(
              icon: LucideIcons.delete,
              semanticLabel: tr(context, 'Delete'),
              onTap: enabled ? onBackspace : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({this.label, this.icon, this.semanticLabel, this.onTap});

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 3 × 72 + 4 × 9 gutters = 252dp — comfortably inside 360dp even at the
    // widest text scale, because nothing here scales with text.
    const double size = 72;

    if (label == null && icon == null) {
      return const SizedBox(width: size, height: 60);
    }

    final disabled = onTap == null;
    return SizedBox(
      width: size,
      height: 60,
      child: Material(
        color: c.secondary,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    size: 22,
                    semanticLabel: semanticLabel,
                    color: disabled
                        ? c.mutedForeground.withValues(alpha: 0.4)
                        : c.foreground,
                  )
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      color: disabled
                          ? c.mutedForeground.withValues(alpha: 0.5)
                          : c.foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
