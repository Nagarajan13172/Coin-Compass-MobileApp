import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../domain/app_notification.dart';

/// `/notifications` — the activity feed behind the screen and the app-bar bell.
///
/// ⚠️ EVERY WRITE ON THIS CLASS TOUCHES THE OWNER'S REAL, IRREVERSIBLE STATE.
/// The account has six genuinely unread notifications going back to July; there
/// is no undo for any of the four mutations below and no staging copy to try
/// them against. They exist so the screen has something to call — **do not
/// invoke them during development**, and wire the two bulk ones behind a
/// confirmation.
///
/// Contracts recovered from the deployed web bundle, not probed:
///
///   POST   /notifications/{id}/read   no body   (SPEC.md says PATCH — wrong)
///   POST   /notifications/read-all    no body
///   DELETE /notifications/{id}        no body
///   DELETE /notifications             no body   (absent from SPEC.md entirely)
///
/// None of the four takes a body, so there is no write schema to get wrong
/// here — only a verb and a path.
class NotificationsRepository {
  const NotificationsRepository(this._api);

  final ApiClient _api;

  /// The whole feed plus the server's own unread count. Takes no parameters —
  /// there is no paging on this endpoint.
  Future<NotificationFeed> list() async {
    final json = await _api.getJson(Endpoints.notifications);
    return NotificationFeed.fromJson(json);
  }

  /// Marks one notification read. POST, not PATCH.
  ///
  /// Called on row tap when the row is unread; independent of the row's link,
  /// so an unread notification with nowhere to navigate still gets marked.
  Future<void> markRead(String id) =>
      _api.postJson(Endpoints.notificationRead(id));

  /// Marks the whole feed read. Irreversible — see the class note.
  Future<void> markAllRead() => _api.postJson(Endpoints.notificationsReadAll);

  /// Dismisses one notification. Irreversible.
  Future<void> delete(String id) =>
      _api.deleteJson(Endpoints.notification(id));

  /// Deletes every notification. Irreversible, and undocumented in SPEC.md —
  /// it was found in the web bundle's "Clear all" button.
  Future<void> clearAll() => _api.deleteJson(Endpoints.notificationsClearAll);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Cached for the session, not autoDispose: the app-bar bell reads the same
/// feed as the screen, and a per-screen refetch would double every request.
/// Invalidate after any mutation — the web has no optimistic update either,
/// it just refetches.
final notificationFeedProvider = FutureProvider<NotificationFeed>(
  (ref) => ref.watch(notificationsRepositoryProvider).list(),
);

/// The badge count. Reads the server's `unread`, which is authoritative;
/// 0 while the feed is loading or failed, so a cold start shows no badge
/// rather than a wrong one.
final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationFeedProvider).valueOrNull?.unread ?? 0,
);

/// `9+` past nine, empty when there is nothing to show — the web's cap.
final unreadBadgeLabelProvider = Provider<String>((ref) {
  final unread = ref.watch(unreadNotificationsProvider);
  if (unread <= 0) return '';
  return unread > 9 ? '9+' : '$unread';
});
