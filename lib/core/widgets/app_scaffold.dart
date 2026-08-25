import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../api/stale_ledger.dart';
import '../i18n/locale_controller.dart';
import '../router/destinations.dart';
import '../router/route_refresh.dart';
import '../theme/app_colors.dart';
import 'more_sheet.dart';
import 'stale_banner.dart';

/// Height of the shell's bottom nav bar, excluding the system inset below it.
const double kShellNavBarHeight = 62;

/// The raised FAB's 18dp overhang plus 10dp of breathing room.
const double kShellFabClearance = 28;

/// Space the shell's chrome occupies *over* the body, which renders with
/// `extendBody: true`: the nav bar, the system inset under it, and the raised
/// FAB's overhang. Every scrollable screen in the shell must pad its tail by
/// this much, or its last row ends up under the FAB.
///
/// Uses `viewPaddingOf`, not `paddingOf`: inside a `extendBody: true` Scaffold
/// body, Flutter rewrites `MediaQuery.padding.bottom` to include the nav bar,
/// so `paddingOf` would count it twice.
double shellBottomInset(BuildContext context) =>
    kShellNavBarHeight +
    MediaQuery.viewPaddingOf(context).bottom +
    kShellFabClearance;

/// The persistent chrome: CoinCompass app bar on top, five-slot bottom nav with
/// a raised centre FAB below. Mirrors the web app's mobile layout.
class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  /// When the last automatic recovery refresh ran. Phase 6.3's guard against a
  /// flapping connection turning into a refresh loop: every live read that
  /// lands while something stale is on screen bumps `onlineRevisionProvider`,
  /// and without this a screenful of recovering cards would each trigger a
  /// fresh round of invalidations.
  DateTime? _lastRecoveryAt;

  void _recover() {
    final now = DateTime.now();
    final last = _lastRecoveryAt;
    if (last != null && now.difference(last) < kRecoveryCooldown) return;
    _lastRecoveryAt = now;
    unawaited(refreshCurrentRoute(ref, widget.location));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Keeps the resume re-read of GET /auth/me alive for as long as the shell
    // is on screen — and no longer. The shell exists only while signed in, so
    // nothing polls the session from the login form. `.notifier` rather than
    // the value: this needs the controller constructed, not a rebuild every
    // time it counts a refresh.
    ref.watch(sessionRefreshControllerProvider.notifier);

    // The recovery path. A successful request to the API is the only reliable
    // evidence the API is reachable, so the signal comes from `ResponseCache`
    // rather than from a connectivity plugin — see `stale_ledger.dart`. Only
    // the visible route is refreshed; hammering all seventeen on every
    // reconnect is exactly what the brief warns against.
    ref.listen<int>(onlineRevisionProvider, (previous, next) {
      if (previous == null || next <= previous) return;
      _recover();
    });

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          const _AppTopBar(),
          const _UnverifiedSessionStrip(),
          // One slot, seventeen screens, and none of them can invent its own
          // staleness copy.
          StaleBanner(
            onRetry: () => refreshCurrentRoute(ref, widget.location),
          ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: _BottomNav(location: widget.location),
      extendBody: true,
    );
  }
}

/// Shown while `AuthState.unverifiedSession` — a cold start that could not
/// reach `GET /auth/me` and is running on an unconfirmed cookie.
///
/// The app must never present an unconfirmed session as live; that is the
/// actual harm the never-cache-`/auth/me` rule exists to prevent, and no
/// `/auth/me` body touches disk either way.
class _UnverifiedSessionStrip extends ConsumerWidget {
  const _UnverifiedSessionStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unverified = ref.watch(
      authControllerProvider.select((s) => s.unverifiedSession),
    );
    if (!unverified) return const SizedBox.shrink();

    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.secondary,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 16, color: c.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Offline — we haven't been able to confirm your session.",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: c.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTopBar extends ConsumerWidget {
  const _AppTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final locale = ref.watch(localeControllerProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.compass,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 9),
                // Flexible so a long title can never push the actions off-screen.
                const Flexible(
                  child: Text(
                    'CoinCompass',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _BarIcon(
                  icon: LucideIcons.search,
                  onTap: () => context.go('/transactions'),
                ),
                _BellIcon(onTap: () => context.go('/notifications')),
                // Phase 7.1. Renders only once there is a second dictionary to
                // switch to. It used to render always: tapping it relabelled
                // the bar `த`, persisted a Tamil locale and then went on
                // painting English, with a "Tamil is coming soon" snackbar
                // that explained the intent but left the app claiming a
                // language it was not in. `canChoose` reads the Tamil map
                // itself, so this comes back on its own when 7.1 fills it.
                if (SupportedLocales.canChoose)
                  _LanguagePill(
                    label: SupportedLocales.shortLabel(locale),
                    onTap: () => ref
                        .read(localeControllerProvider.notifier)
                        .toggle(),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => context.go('/settings'),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      user?.initials ?? '·',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A bare IconButton reserves 48dp each, which overflows a 360dp-wide
    // device once the logo, title, language pill and avatar are added.
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 38,
        height: 40,
        child: Icon(icon, size: 21, color: context.colors.foreground),
      ),
    );
  }
}

/// The bell, with the feed's unread count on it. The count is the server's own
/// `unread` — not a tally of the rows on screen, which the endpoint caps —
/// capped for display at "9+", and hidden entirely at zero, matching the web.
///
/// This watches the same session-cached [notificationFeedProvider] the
/// Notifications screen reads, so opening that screen costs no extra request
/// and marking something read updates the badge on the next invalidation.
class _BellIcon extends ConsumerWidget {
  const _BellIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final badge = ref.watch(unreadBadgeLabelProvider);
    final bell = _BarIcon(icon: LucideIcons.bell, onTap: onTap);
    if (badge.isEmpty) return bell;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        bell,
        // Ignores pointers so the badge never steals a tap from the bell.
        Positioned(
          right: 2,
          top: 3,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.background, width: 1.5),
              ),
              child: Text(
                badge,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(LucideIcons.languages, size: 18, color: c.foreground),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav({required this.location});

  final String location;

  bool _isActive(String path) {
    if (path == '/') return location == '/';
    return location == path || location.startsWith('$path/');
  }

  /// "More" lights up whenever we're on a destination that lives in its sheet.
  bool get _moreActive => moreDestinations.any((d) => _isActive(d.path));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kShellNavBarHeight,
          // The FAB overhangs the bar, so the Stack must not clip.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Row(
                children: [
                  for (final d in tabDestinations.take(2))
                    Expanded(
                      child: _NavItem(
                        destination: d,
                        active: _isActive(d.path),
                        onTap: () => context.go(d.path),
                      ),
                    ),
                  const Expanded(child: SizedBox.shrink()),
                  Expanded(
                    child: _NavItem(
                      destination: tabDestinations[2],
                      active: _isActive(tabDestinations[2].path),
                      onTap: () => context.go(tabDestinations[2].path),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      destination: const Destination(
                        '',
                        'More',
                        LucideIcons.ellipsis,
                      ),
                      active: _moreActive,
                      onTap: () => MoreSheet.show(context),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -18,
                child: GestureDetector(
                  onTap: () => AddSheet.show(context, ref, location: location),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.background, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      LucideIcons.plus,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final Destination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.primary : c.mutedForeground;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(destination.icon, size: 21, color: color),
          const SizedBox(height: 3),
          // The slot is 72dp wide inside a 62dp-tall bar. Left bare, a scaled
          // "Transactions" wraps to two lines and overflows the bar on every
          // shell screen. maxLines/softWrap stop the wrap, FittedBox shrinks
          // the word instead of ellipsising it, Flexible caps the Column, and
          // the explicit height drops bodyMedium's inherited 1.45 leading.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                destination.label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
