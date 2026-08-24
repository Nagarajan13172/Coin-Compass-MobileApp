import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../i18n/locale_controller.dart';
import '../router/destinations.dart';
import '../theme/app_colors.dart';
import 'more_sheet.dart';

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
class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          const _AppTopBar(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: _BottomNav(location: location),
      extendBody: true,
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
                _LanguagePill(
                  label: SupportedLocales.shortLabel(locale),
                  onTap: () async {
                    final controller = ref.read(
                      localeControllerProvider.notifier,
                    );
                    await controller.toggle();
                    if (!context.mounted) return;
                    if (ref.read(localeControllerProvider).languageCode ==
                        'ta') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tamil is coming soon.')),
                      );
                    }
                  },
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

/// The bell carries an unread badge once the notifications feature lands; the
/// count provider arrives in phase 5, so it renders bare for now.
class _BellIcon extends ConsumerWidget {
  const _BellIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _BarIcon(icon: LucideIcons.bell, onTap: onTap);
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
