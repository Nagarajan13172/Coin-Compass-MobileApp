/// Phase 7.4 — deciding which notifications the *phone* should announce.
///
/// The backend has no push. It has `GET /notifications`, an in-app feed the
/// bell already renders. 7.4 turns that into device notifications by checking
/// the feed and raising anything new — so the answer to "what should ring?" is
/// a pure function of the feed and what has already been announced, and can be
/// tested without a plugin, a network or a phone.
///
/// ## The rule that matters most: silence on the first run
///
/// A feed that has been accumulating for weeks is not news. The owner's account
/// had six unread notifications sitting in it before this feature existed;
/// announcing all six the first time the app checks would be six buzzes for
/// things they already knew about, and the feature would be uninstalled before
/// it ever showed anything useful.
///
/// So the first check **adopts** the feed instead of announcing it: everything
/// present is recorded as already-seen, and nothing rings. Only what arrives
/// *after* that is new.
library;

import 'app_notification.dart';

/// What one check concluded.
class SurfaceDecision {
  const SurfaceDecision({required this.toAnnounce, required this.seen});

  /// Newest last — the order they should be posted, so the most recent
  /// notification is the one left on top of the shade.
  final List<AppNotification> toAnnounce;

  /// The complete set of ids to persist. Always superset-or-equal of the
  /// previous set, already trimmed to [maxRemembered].
  final Set<String> seen;

  bool get isSilent => toAnnounce.isEmpty;
}

/// How many ids to keep. The feed itself is server-capped and small, but the
/// remembered set would otherwise grow for the life of the install. 200 is far
/// more than any feed returns, so an id can never fall out of memory while it
/// is still in the feed — which is what would make it ring twice.
const int maxRemembered = 200;

/// Never announce more than this in one check. A burst — the server catching up
/// after an outage, or a month of recurring rules posting at once — should be a
/// few notifications and a summary, not forty separate buzzes.
const int maxPerCheck = 5;

/// Decides what to announce.
///
/// [seen] is what previous checks recorded. Pass an **empty set with
/// [isFirstCheck] true** to adopt the feed silently; the two are separate
/// because an empty set is also what a user with a genuinely empty feed has,
/// and that user's *next* notification must still ring.
SurfaceDecision decideSurface({
  required NotificationFeed feed,
  required Set<String> seen,
  required bool isFirstCheck,
}) {
  final ids = feed.items.map((n) => n.id).where((id) => id.isNotEmpty);

  if (isFirstCheck) {
    // Adopt everything, announce nothing.
    return SurfaceDecision(
      toAnnounce: const [],
      seen: _trim({...seen, ...ids}, feed),
    );
  }

  final fresh = [
    for (final item in feed.items)
      // Unread only: a notification the user has already opened in the app —
      // or on another device — is not news either. `read` is server state, so
      // this also stops the phone announcing something they just dismissed on
      // the web.
      if (item.id.isNotEmpty && !item.read && !seen.contains(item.id)) item,
  ];

  // Oldest first, so the newest is posted last and sits on top.
  fresh.sort((a, b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null || bt == null) return 0;
    return at.compareTo(bt);
  });

  // Everything fresh is recorded as seen, including anything trimmed by
  // [maxPerCheck] — those were deliberately not announced, and announcing them
  // on the next check would be the burst arriving one buzz at a time.
  final announce = fresh.length > maxPerCheck
      ? fresh.sublist(fresh.length - maxPerCheck)
      : fresh;

  return SurfaceDecision(
    toAnnounce: List.unmodifiable(announce),
    seen: _trim({...seen, ...fresh.map((n) => n.id)}, feed),
  );
}

/// Keeps the set bounded, and never evicts an id that is still in [feed] —
/// evicting a live id is exactly how a notification rings a second time.
Set<String> _trim(Set<String> ids, NotificationFeed feed) {
  if (ids.length <= maxRemembered) return Set.unmodifiable(ids);

  final live = feed.items.map((n) => n.id).toSet();
  final kept = <String>{...ids.where(live.contains)};
  // Fill the remainder from the tail of the existing set, which is insertion
  // ordered — so the ids dropped are the ones added longest ago.
  for (final id in ids.toList().reversed) {
    if (kept.length >= maxRemembered) break;
    kept.add(id);
  }
  return Set.unmodifiable(kept);
}
