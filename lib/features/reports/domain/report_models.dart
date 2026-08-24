import '../../../core/api/json.dart';

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
  final String? group;
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

/// One slice of `GET /reports/by-account`
class AccountSlice {
  const AccountSlice({
    required this.name,
    this.accountId,
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.total = 0,
    this.count = 0,
    this.type,
  });

  final String name;
  final String? accountId;
  final num income;
  final num expense;
  final num net;
  final num total;
  final int count;
  final String? type;

  factory AccountSlice.fromJson(Map<String, dynamic> json) => AccountSlice(
    name: J.str(json['name']),
    accountId: J.refId(json['accountId'] ?? json['account']),
    income: J.number(json['income']),
    expense: J.number(json['expense']),
    net: J.number(json['net']),
    total: J.number(json['total']),
    count: J.integer(json['count']),
    type: J.strOrNull(json['type']),
  );
}

/// One bucket of `GET /reports/trend`. `bucket` is a `yyyy-MM-dd` label.
class TrendPoint {
  const TrendPoint({
    required this.bucket,
    this.income = 0,
    this.expense = 0,
    this.net = 0,
  });

  final String bucket;
  final num income;
  final num expense;
  final num net;

  DateTime? get date => J.date(bucket);

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    bucket: J.str(json['bucket']),
    income: J.number(json['income']),
    expense: J.number(json['expense']),
    net: J.number(json['net']),
  );
}

/// A period-over-period metric: `{current, previous, delta, pct}`.
/// `pct` is null when the previous period was zero.
class Delta {
  const Delta({this.current = 0, this.previous = 0, this.delta = 0, this.pct});

  final num current;
  final num previous;
  final num delta;
  final num? pct;

  bool get isUp => delta > 0;

  factory Delta.fromJson(Map<String, dynamic> json) => Delta(
    current: J.number(json['current']),
    previous: J.number(json['previous']),
    delta: J.number(json['delta']),
    pct: J.numberOrNull(json['pct']),
  );
}

/// `pace` block of `GET /reports/insights`
class Pace {
  const Pace({
    this.isCurrent = false,
    this.daysElapsed = 0,
    this.daysInPeriod = 0,
    this.avgPerDay = 0,
    this.projected = 0,
    this.previousToDate = 0,
  });

  final bool isCurrent;
  final int daysElapsed;
  final int daysInPeriod;
  final num avgPerDay;
  final num projected;
  final num previousToDate;

  double get progress => daysInPeriod <= 0
      ? 0
      : (daysElapsed / daysInPeriod).clamp(0, 1).toDouble();

  factory Pace.fromJson(Map<String, dynamic> json) => Pace(
    isCurrent: J.boolean(json['isCurrent']),
    daysElapsed: J.integer(json['daysElapsed']),
    daysInPeriod: J.integer(json['daysInPeriod']),
    avgPerDay: J.number(json['avgPerDay']),
    projected: J.number(json['projected']),
    previousToDate: J.number(json['previousToDate']),
  );
}

/// A category that moved the most between periods.
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
  final String? categoryId;
  final String? color;
  final String? icon;
  final num current;
  final num previous;
  final num delta;
  final num? pct;

  bool get isUp => delta > 0;

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

/// `GET /reports/insights`
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
  });

  final String period;
  final DateTime? currentStart;
  final DateTime? currentEnd;
  final DateTime? previousStart;
  final DateTime? previousEnd;
  final Delta expense;
  final Delta income;
  final Delta net;
  final num? savingsRateCurrent;
  final num? savingsRatePrevious;
  final Pace pace;
  final List<Mover> movers;

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
    );
  }
}
