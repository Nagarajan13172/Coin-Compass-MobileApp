import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/lock_state.dart';
import 'lock_controller.dart';
import 'lock_screen.dart';

/// Wraps the whole app from `MaterialApp.builder`, which is the only place a
/// lock can be painted with no leaked frame.
///
/// ## Why the builder and not the router, an overlay, or a wrapper
///
/// The builder sits **inside** MaterialApp — `Theme`, `Directionality`,
/// `MediaQuery` and `Localizations` are already ancestors, so the lock is a
/// normal themed `Scaffold` — but **outside** the `Router`. The `child` it is
/// handed is the un-mounted Router *widget*, and constructing a widget is not
/// building it. So on a cold start this returns [LockScreen] alone: no screen
/// builds, no provider fires a GET, and there is no pixel of the owner's net
/// worth to leak.
///
/// The alternatives all leak:
///  * a **go_router redirect** is evaluated a frame after the state that
///    triggers it and *pushes a route*, so the page transition animates and the
///    dashboard is visibly underneath the sliding lock for ~300ms. It also
///    destroys the navigation stack and cannot cover a modal sheet already up.
///  * an **OverlayEntry** takes effect on the next frame (one leaked frame),
///    and any route pushed afterwards — a dialog, a modal sheet, a snackbar
///    route — renders above it.
///  * a **wrapper above MaterialApp** has no Directionality, Theme, MediaQuery
///    or Localizations, so the lock screen would need a second MaterialApp,
///    with two Navigators and double-initialised theming.
///
/// When the lock is off — the default, and what every existing test sees — this
/// is a pure pass-through: one enum comparison and the child, unchanged.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget? child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  /// False until the app has been shown at least once this process.
  ///
  /// This is what separates a **cold start** from a **warm lock**. Cold: the
  /// child widget is never put in the tree at all, so the Router never mounts
  /// and nothing behind the lock can request, build or paint. Warm: the child
  /// is already mounted and stays mounted, frozen under an opaque curtain, so a
  /// half-typed form survives being locked.
  bool _everShown = false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider);
    final signedOut = ref.watch(
      authControllerProvider.select((s) => s.status == AuthStatus.signedOut),
    );
    final content = widget.child ?? const SizedBox.shrink();

    // Nothing to hide behind a login form, and it keeps the offline cold start
    // sane: AuthController.restore() swallows network failures and resolves to
    // signedOut.
    if (signedOut || !lock.isGating) {
      _everShown = true;
      return content;
    }

    final overlay = lock.phase == LockPhase.shielded
        // Backgrounded, or the single frame between resume and the grace
        // decision. Opaque, no controls, nothing readable.
        ? const LockShield()
        : const LockScreen();

    if (!_everShown) return overlay;
    return _Curtain(overlay: overlay, child: content);
  }
}

/// Keeps the app mounted underneath — a half-typed transaction sheet survives a
/// lock — but frozen, unfocusable, unreadable to TalkBack, and covered by an
/// opaque surface painted in the same frame the lock is raised.
///
/// `ExcludeSemantics` matters as much as the paint: a screen reader must not
/// announce the net worth from behind the curtain.
class _Curtain extends StatelessWidget {
  const _Curtain({required this.overlay, required this.child});

  final Widget child;
  final Widget overlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        TickerMode(
          enabled: false,
          child: ExcludeFocus(child: ExcludeSemantics(child: child)),
        ),
        Positioned.fill(child: overlay),
      ],
    );
  }
}

/// The opaque cover: the app's background and the compass mark, nothing else.
class LockShield extends StatelessWidget {
  const LockShield({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(LucideIcons.compass, color: c.primaryForeground),
        ),
      ),
    );
  }
}
