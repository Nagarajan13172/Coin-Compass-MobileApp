/// Envelope returned by `GET /transactions`:
/// `{items, page, limit, total, pages, hasMore}`.
class Paginated<T> {
  const Paginated({
    required this.items,
    this.page = 1,
    this.limit = 50,
    this.total = 0,
    this.pages = 1,
    this.hasMore = false,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final int pages;
  final bool hasMore;

  bool get isEmpty => items.isEmpty;

  static int _int(Object? v, int fallback) =>
      v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

  factory Paginated.fromJson(
    Object? json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    // Some endpoints return a bare array instead of an envelope.
    if (json is List) {
      final items = json
          .whereType<Map>()
          .map((e) => itemFromJson(e.cast<String, dynamic>()))
          .toList();
      return Paginated<T>(
        items: items,
        total: items.length,
        pages: 1,
        hasMore: false,
      );
    }

    final map = (json as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = map['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => itemFromJson(e.cast<String, dynamic>()))
              .toList()
        : <T>[];

    return Paginated<T>(
      items: items,
      page: _int(map['page'], 1),
      limit: _int(map['limit'], 50),
      total: _int(map['total'], items.length),
      pages: _int(map['pages'], 1),
      hasMore: map['hasMore'] == true,
    );
  }

  Paginated<T> merge(Paginated<T> next) => Paginated<T>(
    items: [...items, ...next.items],
    page: next.page,
    limit: next.limit,
    total: next.total,
    pages: next.pages,
    hasMore: next.hasMore,
  );
}
