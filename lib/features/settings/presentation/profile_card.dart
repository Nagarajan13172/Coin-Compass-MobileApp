import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/data/categories_repository.dart';
import '../../goals/data/goals_repository.dart';
import '../../loans/data/loans_repository.dart';
import '../../../l10n/app_localizations.dart';

/// Who is signed in, plus the four counts the web puts in the same card.
///
/// Nothing here is editable: `GET /auth/me` has no companion write in the whole
/// deployed client — no name, no email, no avatar upload. The editable "Wallet
/// name" on the Settings screen is `settings.name`, a different field entirely.
class SettingsProfileCard extends ConsumerWidget {
  const SettingsProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    if (user == null) {
      return auth.isResolved
          ? AppCard(
              child: EmptyState(
                compact: true,
                icon: LucideIcons.userRound,
                title: L.of(context).settingsProfileSigned,
                message: L.of(context).settingsProfileSignAgainSeeAccount,
              ),
            )
          : const LoadingCard(lines: 4);
    }

    final c = context.colors;
    return AppCard(
      // The web's `surface-gradient`: primary from the top-left, income from
      // the top-right, both fading out.
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.card),
          c.card,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(user: user),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName.isEmpty
                          ? L.of(context).settingsProfileAccount
                          : user.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    // Wrapped, never ellipsized: half an email address is
                    // worse than two lines of one.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            LucideIcons.mail,
                            size: 14,
                            color: c.mutedForeground,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            user.email,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                label: user.emailVerified ? L.of(context).settingsProfileVerified : L.of(context).settingsProfileUnverified,
                icon: user.emailVerified
                    ? LucideIcons.badgeCheck
                    : LucideIcons.circleAlert,
                tone: user.emailVerified ? c.income : c.mutedForeground,
              ),
              if (user.mode == 'superadmin')
                _Badge(
                  label: L.of(context).settingsProfileWealthView,
                  icon: LucideIcons.eye,
                  tone: c.primary,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _memberLine(L.of(context), user),
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 14),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 14),
          const _CountGrid(),
        ],
      ),
    );
  }

  // Takes the locale rather than reaching for a context it does not have:
  // this is static, so there is none in scope (7.1b).
  static String _memberLine(L l, AppUser user) {
    final method = user.hasPassword
        ? l.settingsProfileEmailPassword
        : l.settingsProfileGoogleAccount;
    final created = user.createdAt;
    if (created == null) return method;
    return l.settingsProfileMemberSince(method, DateX.monthLabel(created));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Initials only. `avatarUrl` is a remote image and this screen must render
    // identically offline and in a widget test — no network fetch on a settings
    // page is worth a broken-image box.
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        user.initials,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: c.primary,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// Accounts / Categories / Goals / Loans, two per row at 360dp.
///
/// Each tile prints an em dash until its list resolves — and keeps printing one
/// if that request failed, rather than claiming zero. On this account the real
/// answer is 0 / 33 / 0 / 1, so "0" has to mean 0.
class _CountGrid extends ConsumerWidget {
  const _CountGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = <_CountTile>[
      _CountTile(
        label: L.of(context).navAccounts,
        icon: LucideIcons.wallet,
        value: _count(ref.watch(accountsProvider)),
      ),
      _CountTile(
        label: L.of(context).navCategories,
        icon: LucideIcons.tags,
        value: _count(ref.watch(categoriesProvider)),
      ),
      _CountTile(
        label: L.of(context).navGoals,
        icon: LucideIcons.target,
        value: _count(ref.watch(goalsProvider)),
      ),
      _CountTile(
        label: L.of(context).navLoans,
        icon: LucideIcons.landmark,
        value: _count(ref.watch(loansProvider)),
      ),
    ];

    return Column(
      children: [
        // No `CrossAxisAlignment.stretch` here: this Row sits in an unbounded
        // Column, and stretch would hand its children an infinite height.
        // The two tiles have identical structure, so they match anyway.
        Row(
          children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 10),
            Expanded(child: tiles[1]),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: tiles[2]),
            const SizedBox(width: 10),
            Expanded(child: tiles[3]),
          ],
        ),
      ],
    );
  }

  static String _count(AsyncValue<List<Object?>> value) =>
      value.valueOrNull?.length.toString() ?? '—';
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.icon,
    required this.value,
  });

  final String label;
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.secondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: c.mutedForeground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
