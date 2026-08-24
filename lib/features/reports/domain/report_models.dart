import '../../../core/api/json.dart';
import '../../../core/utils/date_x.dart';

/// `GET /reports/summary`
class ReportSummary {
  const ReportSummary({
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.incomeCount = 0,
    this.expenseCount = 0,
    this.oneoffIncome = 0,
    this.oneoffExpense = 0,
    this.consumption = 0,
    this.nonConsumption = 0,
    this.netWorth = 0,
    this.byCurrency = const {},
    this.rangeStart,
    this.rangeEnd,
  });

  final num income;
  final num expense;
  final num net;
  final int incomeCount;
  final int expenseCount;
  final num oneoffIncome;
  final num oneoffExpense;

  /// Spending that actually left the household — the web's savings rate is
  /// `(income − consumption) / income`, NOT `(income − expense) / income`.
  /// Money moved into a goal or a deposit lands in [nonConsumption] instead.
  final num consumption;
  final num nonConsumption;
  final num netWorth;
  final Map<String, num> byCurrency;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  int get count => incomeCount + expenseCount;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    final range = J.map(json['range']);
    final currencies = J.map(json['byCurrency']);
    return ReportSummary(
      income: J.number(json['income']),
      expense: J.number(json['expense']),
      net: J.number(json['net']),
      incomeCount: J.integer(json['incomeCount']),
      expenseCount: J.integer(json['expenseCount']),
      oneoffIncome: J.number(json['oneoffIncome']),
      oneoffExpense: J.number(json['oneoffExpense']),
      consumption: J.number(json['consumption']),
      nonConsumption: J.number(json['nonConsumption']),
      netWorth: J.number(json['netWorth']),
      byCurrency: {
        for (final e in currencies.entries) e.key: J.number(e.value),
      },
      rangeStart: J.date(range['start']),
      rangeEnd: J.date(range['end']),
    );
  }
}

/// One slice of `GET /reports/by-category`
class CategorySlice {
  const CategorySlice({
    required this.name,
    this.categoryId,
    this.total = 0,
    this.count = 0,
    this.color,
    this.icon,
    this.group,
    this.percent = 0,
  });

  final String name;
  final String? categoryId;
  final num total;
  final int count;
  final String? color;
  final String? icon;

  /// The category's group key (`food`, `transport`, …) or null. The donut's
  /// "Groups" mode buckets by this; rows without one fall under `ungrouped`.
  final String? group;

  /// Server-computed share of the window's total, already scaled 0–100.
  final num percent;

  factory CategorySlice.fromJson(Map<String, dynamic> json) => CategorySlice(
    name: J.str(json['name']),
    categoryId: J.refId(json['categoryId'] ?? json['category']),
    total: J.number(json['total']),
    count: J.integer(json['count']),
    color: J.strOrNull(json['color']),
    icon: J.strOrNull(json['icon']),
    group: J.strOrNull(json['group']),
    percent: J.number(json['percent']),
  );
}

/// One row of `GET /reports/by-account`.
///
/// The shape is `{_id, name, color, income, expense, transferIn, transferOut}`
/// — recovered from the deployed web bundle (`GZ`, offset 1019028, and the
/// identical `account.stats` block at 868106). There is **no** `net`, `total`,
/// `count` or `type`: the web derives money-in/out/net itself, which is what
/// [moneyIn], [moneyOut] and [net] do here.
///
/// The owner has no accounts, so the live response is `[]` — the field names
/// could not be confirmed against real rows and come from the bundle only.
class AccountSlice {
  const AccountSlice({
    required this.accountId,
    required this.name,
    this.color,
    this.income = 0,
    this.expense = 0,
    this.transferIn = 0,
    this.transferOut = 0,
  });

  final String accountId;
  final String name;
  final String? color;
  final num income;
  final num expense;
  final num transferIn;
  final num transferOut;

  /// Everything that arrived: income plus transfers in.
  num get moneyIn => income + transferIn;

  /// Everything that left: expense plus transfers out.
  num get moneyOut => expense + transferOut;

  num get net => moneyIn - moneyOut;

  factory AccountSlice.fromJson(Map<String, dynamic> json) => AccountSlice(
    accountId: J.refId(json['_id'] ?? json['accountId'] ?? json['account']) ?? '',
    name: J.str(json['name']),
    color: J.strOrNull(json['color']),
    income: J.number(json['income']),
    expense: J.number(json['expense']),
    transferIn: J.number(json['transferIn']),
    transferOut: J.number(json['transferOut']),
  );
}

/// The `granularity` **query** parameter of `GET /reports/trend`.
///
/// Note the asymmetry that has already cost this project a debugging session:
/// the query key is `granularity`, while the key on every row of the response
/// is `bucket`. Sending `?bucket=month` is not an error — it is ignored, and
/// the server quietly returns daily rows.
///
/// [week] is supported server-side but nothing sends it: its buckets come back
/// as ISO week strings (`2026-W32`) that no label formatter here or on the web
/// can parse. Reports uses [day] for a week/month window and [month] for a year.
enum TrendGranularity {
  day('day'),
  week('week'),
  month('month');

  const TrendGranularity(this.api);
  final String api;
}

/// One bucket of `GET /reports/trend`.
///
/// Rows are **sparse**: a whole year of the owner's data is a single row. Any
/// chart built on this has to survive one data point.
class TrendPoint {
  const TrendPoint({
    required this.bucket,
    this.income = 0,
    this.expense = 0,
    this.net = 0,
  });

  /// `2026-08-04` (day granularity), `2026-08` (month) or `2026-W32` (week).
  final String bucket;
  final num income;
  final num expense;
  final num net;

  /// Which shape [bucket] is in, or null when it is none of them.
  TrendGranularity? get granularity {
    if (_dayBucket.hasMatch(bucket)) return TrendGranularity.day;
    if (_monthBucket.hasMatch(bucket)) return TrendGranularity.month;
    if (_weekBucket.hasMatch(bucket)) return TrendGranularity.week;
    return null;
  }

  /// The first instant of the bucket, or null for a bucket we cannot place
  /// (an ISO week string, or anything unexpected). `DateTime.parse` alone is
  /// not enough — it rejects `2026-08` because it has no day.
  DateTime? get date => switch (granularity) {
    TrendGranularity.day => DateX.parse(bucket),
    TrendGranularity.month => DateX.parse('$bucket-01'),
    _ => null,
  };

  /// The half-open window this bucket covers, for the drill-through to
  /// `/transactions?from=&to=`. Null when [date] is — the web treats a tap on
  /// such a bucket as a no-op rather than navigating to a guessed range.
  ({DateTime from, DateTime to})? get window {
    final start = date;
    if (start == null) return null;
    return switch (granularity) {
      TrendGranularity.day => (
        from: start,
        to: DateTime(start.year, start.month, start.day + 1),
      ),
      TrendGranularity.month => (
        from: start,
        to: DateTime(start.year, start.month + 1),
      ),
      _ => null,
    };
  }

  /// The chart axis tick: `04 Aug` for a day, `Aug` for a month, and the raw
  /// bucket for anything else — matching the web's tick formatter.
  String get axisLabel {
    final at = date;
    if (at == null) return bucket;
    return granularity == TrendGranularity.month
        ? DateX.monthShort(at)
        : DateX.shortDay(at);
  }

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    bucket: J.str(json['bucket']),
    income: J.number(json['income']),
    expense: J.number(json['expense']),
    net: J.number(json['net']),
  );

  static final RegExp _dayBucket = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _monthBucket = RegExp(r'^\d{4}-\d{2}$');
  static final RegExp _weekBucket = RegExp(r'^\d{4}-W\d{2}$');
}
