import '../../../l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/lucide_map.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/screen_header.dart';
import '../../wealth_lock/domain/wealth_lock.dart';
import '../../wealth_lock/presentation/wealth_lock_providers.dart';
import '../data/notifications_repository.dart';
import '../domain/app_notification.dart';
import '../../../core/router/route_refresh.dart';

/// `/notifications` — the activity feed: what posted, what is coming up, and
/// what went wrong while the app was closed. Body only; `AppScaffold` supplies
/// the chrome and the bell that carries this screen's unread count.
///
/// Divergences from the web, all deliberate:
///   * the web renders one flat list in server order; this groups by calendar
///     day, because a phone shows four rows at a time and "20 days ago" on its
///     own does not say which of those days,
///   * the web's per-row Dismiss is `opacity-0 group-hover:opacity-100`, i.e.
///     unreachable on touch — here it is an always-visible button,
///   * "Mark all read" and "Clear all" go through a [ConfirmSheet]. Both are
///     irreversible and the web fires them on a single tap.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Rows with a mutation in flight — the dismiss button swaps for a spinner
  /// and stops accepting taps.
  final Set<String> _busyIds = <String>{};

  /// True while "Mark all read" or "Clear all" is running; disables both.
  bool _bulkBusy = false;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationFeedProvider);
    final loaded = feed.valueOrNull;
    final items = loaded?.items ?? const <AppNotification>[];
    final unread = loaded?.unread ?? 0;
    final canBulk = loaded != null && !_bulkBusy;

    final c = context.colors;

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.card,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // `shellBottomInset` is the shared measure of the nav bar + FAB
        // overhang; the extra 12 keeps the last card off the FAB's shadow.
        padding: EdgeInsets.only(bottom: shellBottomInset(context) + 12),
        children: [
          ScreenHeader(
            title: 'Notifications',
            subtitle:
                'Everything that happened while you were away — recurring '
                'posts, reminders and alerts.',
            actions: [
              ScreenHeaderAction(
                label: 'Mark all read',
                icon: LucideIcons.checkCheck,
                primary: false,
                onPressed: canBulk && unread > 0 ? _markAllRead : null,
              ),
              ScreenHeaderAction(
                label: 'Clear all',
                icon: LucideIcons.trash2,
                primary: false,
                onPressed: canBulk && items.isNotEmpty ? _clearAll : null,
              ),
            ],
          ),
          if (loaded != null && items.isNotEmpty)
            _CountLine(total: items.length, unread: unread),
          switch (feed) {
            AsyncData(:final value) when value.items.isEmpty =>
              const _EmptyFeed(),
            AsyncData(:final value) => _Feed(
              items: value.items,
              busyIds: _busyIds,
              onOpen: _open,
              onDismiss: _dismiss,
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(notificationFeedProvider),
              ),
            ),
            _ => const _FeedSkeleton(),
          },
        ],
      ),
    );
  }

  // ── reads ────────────────────────────────────────────────────────────────

  Future<void> _refresh() => refreshCurrentRoute(ref, '/notifications');

  // ── writes ───────────────────────────────────────────────────────────────
  //
  // Every one of these hits the owner's real feed and none of them can be
  // undone, so none was fired against the live API — see the file's test.

  /// Row tap. Two independent effects, in the web's order: mark read if it is
  /// unread, then follow the link if this app has a screen for it. An unread
  /// notification with nowhere to go is still marked read.
  void _open(AppNotification notification) {
    if (!notification.read) unawaited(_markRead(notification.id));

    final route = notificationRoute(
      notification.link,
      wealthVisible:
          ref.read(wealthVisibilityProvider) != WealthVisibility.locked,
    );
    if (route != null) context.go(route);
  }

  Future<void> _markRead(String id) async {
    if (_busyIds.contains(id)) return;
    // Resolve the container BEFORE the await. A row tap marks read and
    // navigates in the same frame, so by the time the POST returns this widget
    // may be gone — and `ref.invalidate` on a disposed ConsumerState does
    // nothing, leaving the top-bar bell showing a stale unread count for the
    // rest of the session and the row still unread on the way back.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(notificationsRepositoryProvider);
    setState(() => _busyIds.add(id));
    try {
      await repository.markRead(id);
      container.invalidate(notificationFeedProvider);
    } catch (error) {
      if (mounted) _toast(error);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _dismiss(AppNotification notification) async {
    if (_busyIds.contains(notification.id)) return;

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Dismiss this notification?',
      message:
          'It is deleted from the feed for good — there is no archive to '
          'recover it from.',
      confirmLabel: 'Dismiss',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyIds.add(notification.id));
    try {
      await ref.read(notificationsRepositoryProvider).delete(notification.id);
      ref.invalidate(notificationFeedProvider);
    } catch (error) {
      _toast(error);
    } finally {
      if (mounted) setState(() => _busyIds.remove(notification.id));
    }
  }

  Future<void> _markAllRead() async {
    final unread = ref.read(unreadNotificationsProvider);
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Mark all as read?',
      message:
          '${_count(unread, 'notification')} will be marked read across every '
          'device. This cannot be undone.',
      confirmLabel: 'Mark all read',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkBusy = true);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      ref.invalidate(notificationFeedProvider);
    } catch (error) {
      _toast(error);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _clearAll() async {
    final total =
        ref.read(notificationFeedProvider).valueOrNull?.items.length ?? 0;
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete every notification?',
      message:
          'All ${_count(total, 'notification')} are permanently deleted, read '
          'or not. This cannot be undone.',
      confirmLabel: 'Delete all',
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkBusy = true);
    try {
      await ref.read(notificationsRepositoryProvider).clearAll();
      ref.invalidate(notificationFeedProvider);
    } catch (error) {
      _toast(error);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  void _toast(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ApiException.from(error).message)));
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

// ─── link mapping ───────────────────────────────────────────────────────────

/// Every path this app can actually navigate to. The three beyond the nav's
/// seventeen destinations are sub-screens mounted under a parent so the bottom
/// nav keeps the right entry lit.
final Set<String> _knownRoutes = <String>{
  for (final d in appDestinations) d.path,
  '/credits/people',
  '/credits/splits',
  '/net-worth/holdings',
};

/// Web paths with no mobile route of their own, redirected to the screen that
/// carries the same content here.
const Map<String, String> _routeAliases = <String, String>{
  '/dashboard': '/',
  '/people': '/credits/people',
  '/splits': '/credits/splits',
  '/holdings': '/net-worth/holdings',
};

/// Translates a notification's `link` — a **web** route — into a route this
/// app has, or null when there is nowhere sensible to go.
///
/// The two links the live feed actually carries are `/recurring`, which exists
/// here verbatim, and `/accounts/{id}`, which does not: mobile has no account
/// detail screen, so it falls back to the accounts list rather than dropping
/// the tap. Anything unrecognised returns null and the row becomes read-only —
/// never a 404 screen and never a crash.
///
/// Query strings are dropped on purpose. No notification link carries one, and
/// the screens here do not all read route queries yet; sending a stray `?tab=`
/// into `context.go` would be a guess.
///
/// [wealthVisible] is false while the Net Worth lock is on, and the three gated
/// routes then resolve to null — the row keeps its title and its Dismiss
/// button, loses the "Net Worth" label that promises a screen, and a tap marks
/// it read without navigating. Without this a `/net-worth` notification would
/// tap straight into the router's redirect and dump the user back on the
/// dashboard with no explanation.
///
/// Required, not defaulted: a call site that forgets the gate should not
/// compile.
String? notificationRoute(String? link, {required bool wealthVisible}) {
  final raw = link?.trim();
  if (raw == null || raw.isEmpty || !raw.startsWith('/')) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return '/';

  final resolved = _resolve(segments);
  if (resolved == null) return null;
  if (!wealthVisible && isWealthGatedPath(resolved)) return null;
  return resolved;
}

String? _resolve(List<String> segments) {
  // Deepest match first, so `/net-worth/holdings` does not collapse to
  // `/net-worth`.
  final full = '/${segments.join('/')}';
  if (_knownRoutes.contains(full)) return full;
  if (_routeAliases.containsKey(full)) return _routeAliases[full];

  final first = '/${segments.first}';
  if (_knownRoutes.contains(first)) return first;
  return _routeAliases[first];
}

/// "Recurring", "Accounts" — what the row promises the tap will open. Null for
/// a route with no nav label, which is not a case the feed produces today.
String? _routeLabel(L l, String route) {
  for (final d in appDestinations) {
    if (d.path == route) return d.label(l);
  }
  return switch (route) {
    '/credits/people' => 'People',
    '/credits/splits' => 'Splits',
    '/net-worth/holdings' => 'Savings & Investments',
    _ => null,
  };
}

// ─── day grouping ───────────────────────────────────────────────────────────

/// One calendar day of the feed. [day] is null for rows the server sent with
/// no `createdAt` — they are kept rather than dropped, under "Earlier".
class NotificationDay {
  const NotificationDay(this.day, this.items);

  final DateTime? day;
  final List<AppNotification> items;

  int get unread => items.where((e) => !e.read).length;
}

/// Buckets by local calendar day, preserving the server's order both between
/// and within days. The server sorts newest first and this does not re-sort:
/// if that ever changes, the screen should follow the server, not argue.
List<NotificationDay> groupNotificationsByDay(List<AppNotification> items) {
  final days = <NotificationDay>[];
  final undated = <AppNotification>[];

  DateTime? currentKey;
  var current = <AppNotification>[];

  for (final item in items) {
    final at = item.createdAt;
    if (at == null) {
      undated.add(item);
      continue;
    }
    final key = DateTime(at.year, at.month, at.day);
    if (currentKey == null || key != currentKey) {
      if (currentKey != null) days.add(NotificationDay(currentKey, current));
      currentKey = key;
      current = <AppNotification>[];
    }
    current.add(item);
  }
  if (currentKey != null) days.add(NotificationDay(currentKey, current));
  if (undated.isNotEmpty) days.add(NotificationDay(null, undated));

  return days;
}

/// "Today" / "Yesterday" / "04 Aug 2026". The year is always kept — a feed
/// going back two months is normal on this account, and "04 Aug" alone would
/// not say which August.
String notificationDayLabel(DateTime? day, {DateTime? now}) {
  if (day == null) return 'Earlier';
  final today = now ?? DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);
  final diff = midnight
      .difference(DateTime(day.year, day.month, day.day))
      .inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateX.dateLabel(day);
}

// ─── pieces ─────────────────────────────────────────────────────────────────

class _CountLine extends StatelessWidget {
  const _CountLine({required this.total, required this.unread});

  final int total;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        unread == 0
            ? '${_count(total, 'notification')} · all read'
            : '$unread unread of ${_count(total, 'notification')}',
        style: TextStyle(fontSize: 13, color: c.mutedForeground),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: EmptyState(
        icon: LucideIcons.bellOff,
        title: "You're all caught up",
        message:
            'New activity — auto-posted recurring transactions, reminders and '
            'alerts — shows up here.',
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          LoadingShimmer(height: 78, radius: AppTheme.radius),
          SizedBox(height: 10),
          LoadingShimmer(height: 78, radius: AppTheme.radius),
          SizedBox(height: 10),
          LoadingShimmer(height: 78, radius: AppTheme.radius),
          SizedBox(height: 10),
          LoadingShimmer(height: 78, radius: AppTheme.radius),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({
    required this.items,
    required this.busyIds,
    required this.onOpen,
    required this.onDismiss,
  });

  final List<AppNotification> items;
  final Set<String> busyIds;
  final void Function(AppNotification) onOpen;
  final Future<void> Function(AppNotification) onDismiss;

  @override
  Widget build(BuildContext context) {
    final days = groupNotificationsByDay(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days) ...[
          _DayHeader(day: day),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _DayCard(
              items: day.items,
              busyIds: busyIds,
              onOpen: onOpen,
              onDismiss: onDismiss,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final NotificationDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unread = day.unread;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              notificationDayLabel(day.day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 10),
            Text(
              '$unread new',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.items,
    required this.busyIds,
    required this.onOpen,
    required this.onDismiss,
  });

  final List<AppNotification> items;
  final Set<String> busyIds;
  final void Function(AppNotification) onOpen;
  final Future<void> Function(AppNotification) onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            NotificationRow(
              key: ValueKey(items[i].id),
              notification: items[i],
              busy: busyIds.contains(items[i].id),
              onOpen: () => onOpen(items[i]),
              onDismiss: () => onDismiss(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// One feed row. Public so the app-bar bell popover can reuse it verbatim the
/// way the web's `YE` component does, if that ever lands.
class NotificationRow extends ConsumerWidget {
  const NotificationRow({
    super.key,
    required this.notification,
    required this.onOpen,
    required this.onDismiss,
    this.busy = false,
  });

  final AppNotification notification;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final copy = NotificationCopy.of(notification);
    final unread = !notification.read;
    final tone = _toneColor(context, notification.kind.tone);
    final route = notificationRoute(
      notification.link,
      wealthVisible:
          ref.watch(wealthVisibilityProvider) != WealthVisibility.locked,
    );
    final destination = route == null
        ? null
        : _routeLabel(L.of(context), route);

    return Material(
      // The unread tint the web paints as `bg-primary/[0.04]`. Composited on
      // `card` rather than left translucent so it reads the same in dark mode,
      // where a 4% white-blue wash over a dark card is otherwise invisible.
      color: unread
          ? Color.alphaBlend(c.primary.withValues(alpha: 0.06), c.card)
          : c.card,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _kindIcon(notification.kind),
                  size: 17,
                  color: tone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            copy.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: c.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (copy.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      // No maxLines: the body is the sentence the row exists to
                      // deliver, and clipping it would eat the amount or the
                      // date at the end of it.
                      Text(
                        copy.body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    _MetaLine(
                      timeAgo: notification.timeAgo(),
                      destination: destination,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              _DismissButton(busy: busy, onTap: onDismiss),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.timeAgo, required this.destination});

  final String timeAgo;
  final String? destination;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 11.5, color: c.mutedForeground);
    final label = destination;

    if (timeAgo.isEmpty && label == null) return const SizedBox.shrink();

    return Row(
      children: [
        if (timeAgo.isNotEmpty)
          Flexible(
            child: Text(
              timeAgo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        if (label != null) ...[
          if (timeAgo.isNotEmpty) Text(' · ', style: style),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      color: c.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 12, color: c.primary),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The web hides Dismiss behind a hover, which no phone can produce. Always
/// visible here, and behind a [ConfirmSheet] because the delete is permanent.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Dismiss notification',
      child: InkResponse(
        onTap: busy ? null : onTap,
        radius: 20,
        child: SizedBox(
          width: 34,
          height: 34,
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.mutedForeground,
                    ),
                  ),
                )
              : Icon(LucideIcons.x, size: 16, color: c.mutedForeground),
        ),
      ),
    );
  }
}

// ─── tone + icon ────────────────────────────────────────────────────────────

/// The kind's glyph. Resolved with a switch rather than through
/// All six `NotificationKind.icon` names now resolve through the shared table
/// in `core/utils/lucide_map.dart` (`circle-check`, `clock` and `alarm-clock`
/// were added there during integration — before that, half the feed fell back
/// to a bare circle). The bell is the fallback rather than the map's own
/// circle, so a type this build predates still looks like a notification.
IconData _kindIcon(NotificationKind kind) =>
    lucideIcon(kind.icon, fallback: LucideIcons.bell);

/// `c.warning` is the amber the web spells `text-amber-600` in light and
/// `text-amber-500` in dark. Deliberately not `destructive`: an overdue
/// reminder is not the same signal as a failure.
Color _toneColor(BuildContext context, NotificationTone tone) {
  final c = context.colors;
  return switch (tone) {
    NotificationTone.primary => c.primary,
    NotificationTone.income => c.income,
    NotificationTone.expense => c.expense,
    NotificationTone.warning => c.warning,
  };
}
