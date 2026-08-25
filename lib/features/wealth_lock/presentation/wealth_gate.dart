import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../domain/wealth_lock.dart';
import 'wealth_lock_providers.dart';
import 'wealth_unlock_sheet.dart';

/// The render-level half of the Net Worth lock.
///
/// The router redirect is the first line and this is the second, for the same
/// reason 6.1 put the app lock in `MaterialApp.builder` rather than trusting a
/// redirect: a redirect acts a frame late. `WealthGate` decides *before* its
/// child is built, so on a deep link straight to `/net-worth` the screen widget
/// never mounts, its providers never fire a GET, and there is no frame of the
/// owner's net worth to leak.
///
/// [child] is a closure, not a widget, precisely so that a locked build never
/// constructs the gated subtree at all.
class WealthGate extends ConsumerWidget {
  const WealthGate({
    super.key,
    required this.builder,
    this.locked,
    this.checking,
  });

  /// Built only when the figures may be shown.
  final WidgetBuilder builder;

  /// Shown while the lock is on. Defaults to [WealthLockedPanel] — pass
  /// `SizedBox.shrink()` for a card the web *removes* rather than replaces.
  final Widget? locked;

  /// Shown while `GET /auth/me` is being re-read and the answer is not known
  /// yet. Never a value, never a zero. Defaults to a shimmering card.
  final Widget? checking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(wealthVisibilityProvider);
    return switch (visibility) {
      WealthVisibility.visible => builder(context),
      WealthVisibility.checking => checking ?? const _CheckingPlaceholder(),
      WealthVisibility.locked => locked ?? const WealthLockedPanel(),
    };
  }
}

/// A card-shaped stand-in that carries no figure.
class _CheckingPlaceholder extends StatelessWidget {
  const _CheckingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checking whether Net Worth is unlocked…',
      child: const LoadingCard(lines: 2),
    );
  }
}

/// The `checking` state for a whole gated **screen**, as opposed to a card.
///
/// A resume after 30 seconds away re-reads `GET /auth/me`, and until it lands
/// the app does not know whether the owner locked their net worth from a
/// browser in the meantime. One line and a spinner — never the previous
/// figure, and never a zero standing in for it.
class WealthCheckingScreen extends StatelessWidget {
  const WealthCheckingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: c.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Checking whether Net Worth is unlocked…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a gated **screen** shows if it is ever reached while locked.
///
/// Belt-and-braces: the router redirects `/net-worth`, `/stocks` and
/// `/net-worth/holdings` home while the lock is on, so in practice this is not
/// on screen. It exists because "the redirect will have run by then" is exactly
/// the assumption 6.1's review found to be false a frame at a time.
///
/// Deliberately says nothing about *what* is hidden beyond the name of the
/// screen: no totals, no counts, no "you have N holdings".
class WealthLockedPanel extends ConsumerWidget {
  const WealthLockedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(LucideIcons.lockKeyhole, size: 24, color: c.primary),
            ),
            const SizedBox(height: 14),
            const Text(
              'Net Worth is locked.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Net Worth, Savings & Investments and Stocks are hidden until '
              'you enter the passcode. Unlocking here unlocks them in this '
              'app only.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Unlock',
              expand: false,
              onPressed: () => unlockWealthFlow(context),
            ),
          ],
        ),
      ),
    );
  }
}
