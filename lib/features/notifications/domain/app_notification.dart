import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';

/// `GET /notifications` -> `{items: [...], unread: 6}`
///
/// Not a bare array, and the count is **server-supplied**: the bell badge reads
/// `unread` rather than counting unread items, because the list is capped and
/// the count is not. Takes no parameters at all — no limit, skip, cursor or
/// page exists on this endpoint.
class NotificationFeed {
  const NotificationFeed({this.items = const [], this.unread = 0});

  final List<AppNotification> items;
  final int unread;

  bool get isEmpty => items.isEmpty;

  factory NotificationFeed.fromJson(Object? json) {
    // A bare array is not a shape this endpoint returns, but tolerating it
    // costs one branch and saves a crash if it ever changes.
    if (json is List) {
      final items = J.list(json, AppNotification.fromJson);
      return NotificationFeed(
        items: items,
        unread: items.where((e) => !e.read).length,
      );
    }
    final map = J.map(json);
    return NotificationFeed(
      items: J.list(map['items'], AppNotification.fromJson),
      unread: J.integer(map['unread']),
    );
  }
}

/// The six `type` values the backend emits. The web has exactly these and no
/// more (the icon map `KE` and the i18n `types` object agree), so anything
/// else is a server-side addition this build predates.
enum NotificationKind {
  recurringPosted('recurring.posted', NotificationTone.income, 'repeat'),
  recurringEnded('recurring.ended', NotificationTone.primary, 'circle-check'),
  recurringDueSoon('recurring.due_soon', NotificationTone.primary, 'clock'),
  recurringOverdue('recurring.overdue', NotificationTone.warning, 'alarm-clock'),
  budgetExceeded('budget.exceeded', NotificationTone.expense, 'chart-pie'),
  balanceLow('balance.low', NotificationTone.warning, 'wallet'),

  /// Anything the server adds later. The web would render the raw i18n key
  /// here; we humanise the type instead.
  unknown('', NotificationTone.primary, 'bell');

  const NotificationKind(this.api, this.tone, this.icon);

  final String api;
  final NotificationTone tone;

  /// A lucide name for `lucideIcon()`.
  final String icon;

  static NotificationKind fromApi(String? value) =>
      NotificationKind.values.firstWhere(
        (e) => e.api == value && e != NotificationKind.unknown,
        orElse: () => NotificationKind.unknown,
      );

  /// The fixed heading for this kind. It is **not** the rule's title: the web
  /// shows "Recurring posted" and interpolates `ruleTitle` into the body.
  String get title => switch (this) {
    NotificationKind.recurringPosted => 'Recurring posted',
    NotificationKind.recurringEnded => 'Recurring ended',
    NotificationKind.recurringDueSoon => 'Coming up',
    NotificationKind.recurringOverdue => 'Overdue',
    NotificationKind.budgetExceeded => 'Budget exceeded',
    NotificationKind.balanceLow => 'Low balance',
    NotificationKind.unknown => 'Notification',
  };
}

/// Which colour the row's icon chip takes. `warning` maps to the shared
/// `AppColors.warning` amber (the web's amber-600 / amber-500), not to
/// `destructive` — an overdue reminder is not a failure.
enum NotificationTone { primary, income, expense, warning }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.link,
    this.params = const {},
    this.read = false,
    this.readAt,
    this.dedupeKey,
    this.createdAt,
  });

  final String id;

  /// The raw wire value, e.g. `recurring.posted`. [kind] is the parsed form.
  final String type;

  /// An in-app path to open on tap, e.g. `/recurring`, `/accounts/{id}`.
  /// Null for a notification with nowhere to go — the row still marks itself
  /// read.
  final String? link;

  /// Structured values the copy interpolates. The backend sends these instead
  /// of rendered sentences, so the client composes the text — see
  /// [NotificationCopy.of].
  final Map<String, dynamic> params;
  final bool read;
  final DateTime? readAt;

  /// The server's idempotency key. Nothing renders it; the web never reads it.
  final String? dedupeKey;
  final DateTime? createdAt;

  NotificationKind get kind => NotificationKind.fromApi(type);

  /// "20 days ago" — date-fns `formatDistanceToNow`, matching the web.
  String timeAgo({DateTime? now}) => DateX.timeAgo(createdAt, now: now);

  num? get amount => J.numberOrNull(params['amount']);
  String? get currency => J.strOrNull(params['currency']);
  int? get countParam =>
      params['count'] == null ? null : J.integer(params['count']);

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: J.id(json['_id']),
        type: J.str(json['type']),
        link: J.strOrNull(json['link']),
        params: J.map(json['params']),
        read: J.boolean(json['read']),
        readAt: J.date(json['readAt']),
        dedupeKey: J.strOrNull(json['dedupeKey']),
        createdAt: J.date(json['createdAt']),
      );
}

/// The rendered title and body of one notification.
///
/// Composed here rather than on screen because the rules are fiddly and shared
/// with the app-bar bell popover. Transcribed from the web's composer (`NY`):
/// the params are spread raw, then `amount`, `spent` and `balance` are replaced
/// by money formatted in the notification's OWN currency, and `date` by
/// `dd MMM yyyy`. A missing value interpolates as an **empty string**, not as
/// "null" and not by dropping the sentence — so
/// `"Recurring is scheduled for  ()."` is what the web shows for a malformed
/// payload, and matching that is more honest than inventing a fallback.
class NotificationCopy {
  const NotificationCopy({required this.title, required this.body});

  final String title;
  final String body;

  static NotificationCopy of(AppNotification notification) {
    final kind = notification.kind;
    final params = notification.params;
    final symbol = Money.symbolFor(J.strOrNull(params['currency']));

    String money(String key) {
      final value = J.numberOrNull(params[key]);
      return value == null ? '' : Money.format(value, symbol: symbol);
    }

    String text(String key) => J.str(params[key]);

    String date() {
      final at = J.date(params['date']);
      return at == null ? '' : DateX.dateLabel(at);
    }

    final count = notification.countParam ?? 0;
    final rule = text('ruleTitle');

    final body = switch (kind) {
      NotificationKind.recurringPosted =>
        '$rule posted $count '
            '${count == 1 ? 'transaction' : 'transactions'} '
            '(${money('amount')}).',
      NotificationKind.recurringEnded =>
        '$rule reached its end date and has stopped.',
      NotificationKind.recurringDueSoon =>
        '$rule is scheduled for ${date()} (${money('amount')}).',
      NotificationKind.recurringOverdue =>
        '$rule was due ${date()} (${money('amount')}) and '
            "hasn't posted yet.",
      NotificationKind.budgetExceeded =>
        '${text('category')} — spent ${money('spent')} of ${money('amount')}.',
      NotificationKind.balanceLow =>
        '${text('account')} is overdrawn (${money('balance')}).',
      NotificationKind.unknown => '',
    };

    return NotificationCopy(
      title: kind == NotificationKind.unknown
          ? _humanise(notification.type)
          : kind.title,
      body: body,
    );
  }

  /// `budget.something_new` -> `Something new`, so an unrecognised type reads
  /// as a sentence instead of as the i18n key the web would print.
  static String _humanise(String type) {
    final last = type.split('.').last.replaceAll('_', ' ').trim();
    if (last.isEmpty) return 'Notification';
    return last[0].toUpperCase() + last.substring(1);
  }
}
