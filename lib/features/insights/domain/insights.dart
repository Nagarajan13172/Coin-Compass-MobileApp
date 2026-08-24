import '../../../core/api/json.dart';

/// A period-over-period metric: `{current, previous, delta, pct}`.
///
/// [pct] is **null**, not zero, whenever the previous period was 0 — there is
/// no percentage change from nothing. That is this account's normal state, so
/// every consumer needs the null branch: the web's delta pill falls back to a
/// compact money amount ("↗ ₹13K") rather than showing a percentage.
class Delta {
  const Delta({this.current = 0, this.previous = 0, this.delta = 0, this.pct});

  final num current;
  final num previous;

  /// `current − previous`, computed server-side.
  final num delta;

  /// Percentage change, already scaled (13 means 13%). Null when [previous]
  /// was 0. Never divide by [previous] yourself.
  final num? pct;

  bool get isUp => delta > 0;
  bool get isFlat => delta == 0;

  /// True when there is no baseline to compare against.
  bool get hasNoBaseline => pct == null;

  factory Delta.fromJson(Map<String, dynamic> json) => Delta(
    current: J.number(json['current']),
    previous: J.number(json['previous']),
    delta: J.number(json['delta']),
    pct: J.numberOrNull(json['pct']),
  );
}

/// The `pace` block: how fast this period is being spent.
class Pace {
  const Pace({
    this.isCurrent = false,
    this.daysElapsed = 0,
    this.daysInPeriod = 0,
    this.avgPerDay = 0,
    this.projected = 0,
    this.previousToDate = 0,
  });

  /// False for a period that has already closed. The progress bar and the
  /// "Projected" wording are only meaningful while it is true — a past period
  /// comes back with `daysElapsed == daysInPeriod`.
  final bool isCurrent;
  final int daysElapsed;
  final int daysInPeriod;

  /// Unrounded. The web rounds it to whole rupees for display (₹555), while
  /// the Reports screen's own avg-daily figure keeps its decimals (₹554.67).
  final num avgPerDay;

  /// What this period ends at if spending continues at [avgPerDay].
  final num projected;

  /// What had been spent by this point of the *previous* period. 0 means the
  /// faster/slower comparison line has nothing to say and is hidden.
  final num previousToDate;

  double get progress => daysInPeriod <= 0
      ? 0
      : (daysElapsed / daysInPeriod).clamp(0, 1).toDouble();

  /// 0–100, rounded, capped — the label next to the progress bar.
  int get percentElapsed => daysInPeriod <= 0
      ? 0
      : (daysElapsed / daysInPeriod * 100).round().clamp(0, 100);

  factory Pace.fromJson(Map<String, dynamic> json) => Pace(
    isCurrent: J.boolean(json['isCurrent']),
    daysElapsed: J.integer(json['daysElapsed']),
    daysInPeriod: J.integer(json['daysInPeriod']),
    avgPerDay: J.number(json['avgPerDay']),
    projected: J.number(json['projected']),
    previousToDate: J.number(json['previousToDate']),
  );
}

/// A category that moved the most between the two periods.
class Mover {
  const Mover({
    required this.name,
    this.categoryId,
    this.color,
    this.icon,
    this.current = 0,
    this.previous = 0,
    this.delta = 0,
    this.pct,
  });

  final String name;

  /// Null for uncategorised spending — the row still renders and still
  /// navigates, just without a `category` filter.
  final String? categoryId;
  final String? color;
  final String? icon;
  final num current;
  final num previous;
  final num delta;

  /// Null when this category had no spending last period: the web prints
  /// "New" in the percentage column instead of a number.
  final num? pct;

  bool get isUp => delta > 0;
  bool get isNew => pct == null;

  factory Mover.fromJson(Map<String, dynamic> json) => Mover(
    name: J.str(json['name']),
    categoryId: J.refId(json['categoryId']),
    color: J.strOrNull(json['color']),
    icon: J.strOrNull(json['icon']),
    current: J.number(json['current']),
    previous: J.number(json['previous']),
    delta: J.number(json['delta']),
    pct: J.numberOrNull(json['pct']),
  );
}

/// The `{name, color, icon}` stub `topExpenses[]` embeds for a category or an
/// account. Not a full document — there is no id to navigate with, which is
/// why those rows are not tappable on the web either.
class InsightRef {
  const InsightRef({required this.name, this.color, this.icon});

  final String name;
  final String? color;
  final String? icon;

  factory InsightRef.fromJson(Map<String, dynamic> json) => InsightRef(
    name: J.str(json['name']),
    color: J.strOrNull(json['color']),
    icon: J.strOrNull(json['icon']),
  );
}

/// One row of `topExpenses[]` — the largest single transactions in the window.
class TopExpense {
  const TopExpense({
    required this.id,
    this.amount = 0,
    this.note = '',
    this.payee = '',
    this.date,
    this.category,
    this.account,
  });

  final String id;
  final num amount;
  final String note;
  final String payee;
  final DateTime? date;

  /// Null for an uncategorised expense; the row then reads "Uncategorized"
  /// with the neutral slate colour.
  final InsightRef? category;
  final InsightRef? account;

  /// payee, else note, else the category name, else "Expense" — the web's
  /// fallback chain, in that order.
  String get title {
    if (payee.isNotEmpty) return payee;
    if (note.isNotEmpty) return note;
    final categoryName = category?.name ?? '';
    return categoryName.isNotEmpty ? categoryName : 'Expense';
  }

  factory TopExpense.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final account = json['account'];
    return TopExpense(
      id: J.id(json['_id']),
      amount: J.number(json['amount']),
      note: J.str(json['note']),
      payee: J.str(json['payee']),
      date: J.date(json['date']),
      category: category is Map ? InsightRef.fromJson(J.map(category)) : null,
      account: account is Map ? InsightRef.fromJson(J.map(account)) : null,
    );
  }
}

/// `GET /reports/insights?period=week|month|year&ref=<ISO instant>`
///
/// One request drives the whole Insights screen. Unlike every other report it
/// takes a **period**, not a window: the server derives both ranges itself and
/// echoes them back as [currentStart]/[currentEnd] and
/// [previousStart]/[previousEnd], which are also the from/to of every
/// drill-through out of this screen.
class Insights {
  const Insights({
    this.period = 'month',
    this.currentStart,
    this.currentEnd,
    this.previousStart,
    this.previousEnd,
    this.expense = const Delta(),
    this.income = const Delta(),
    this.net = const Delta(),
    this.savingsRateCurrent,
    this.savingsRatePrevious,
    this.pace = const Pace(),
    this.movers = const [],
    this.topExpenses = const [],
    this.hasData = false,
  });

  /// `week` | `month` | `year`, echoed back from the request.
  final String period;
  final DateTime? currentStart;
  final DateTime? currentEnd;
  final DateTime? previousStart;
  final DateTime? previousEnd;
  final Delta expense;
  final Delta income;
  final Delta net;

  /// Both null when the corresponding period had no income. The web computes
  /// its own savings rate on the Reports screen and never renders these two —
  /// they are parsed for completeness, not for display.
  final num? savingsRateCurrent;
  final num? savingsRatePrevious;
  final Pace pace;

  /// Biggest category shifts, already sorted by the server. Can be empty.
  final List<Mover> movers;

  /// Largest single transactions in the window. Can be empty.
  final List<TopExpense> topExpenses;

  /// False when there is not enough history to say anything — the whole body
  /// of the screen is replaced by an empty state. Verified live: the owner's
  /// `?period=week` currently returns `hasData: false`.
  final bool hasData;

  /// The first mover that went up, which is the one the highlights line calls
  /// out. Null when nothing rose.
  Mover? get topRiser {
    for (final mover in movers) {
      if (mover.delta > 0) return mover;
    }
    return null;
  }

  factory Insights.fromJson(Map<String, dynamic> json) {
    final current = J.map(json['current']);
    final previous = J.map(json['previous']);
    final savings = J.map(json['savingsRate']);
    return Insights(
      period: J.str(json['period'], 'month'),
      currentStart: J.date(current['start']),
      currentEnd: J.date(current['end']),
      previousStart: J.date(previous['start']),
      previousEnd: J.date(previous['end']),
      expense: Delta.fromJson(J.map(json['expense'])),
      income: Delta.fromJson(J.map(json['income'])),
      net: Delta.fromJson(J.map(json['net'])),
      savingsRateCurrent: J.numberOrNull(savings['current']),
      savingsRatePrevious: J.numberOrNull(savings['previous']),
      pace: Pace.fromJson(J.map(json['pace'])),
      movers: J.list(json['movers'], Mover.fromJson),
      topExpenses: J.list(json['topExpenses'], TopExpense.fromJson),
      hasData: J.boolean(json['hasData']),
    );
  }
}
