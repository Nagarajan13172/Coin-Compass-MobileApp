import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.group,
    this.parentId,
    this.order = 0,
    this.isDefault = false,
    this.usageCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String? icon;
  final String? color;
  final String? group;
  final String? parentId;
  final int order;
  final bool isDefault;
  final int usageCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isIncome => type == CategoryType.income;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: J.id(json['_id']),
    name: J.str(json['name']),
    type: CategoryType.fromApi(J.strOrNull(json['type'])),
    icon: J.strOrNull(json['icon']),
    color: J.strOrNull(json['color']),
    group: J.strOrNull(json['group']),
    parentId: J.refId(json['parent']),
    order: J.integer(json['order']),
    isDefault: J.boolean(json['isDefault']),
    usageCount: J.integer(json['usageCount']),
    createdAt: J.date(json['createdAt']),
    updatedAt: J.date(json['updatedAt']),
  );

  Map<String, dynamic> toWriteJson() => {
    'name': name,
    'type': type.api,
    if (icon != null) 'icon': icon,
    if (color != null) 'color': color,
    if (group != null) 'group': group,
    if (parentId != null) 'parent': parentId,
  };
}

/// Human labels for the 14 `group` values the API seeds.
///
/// Both the wording and the *declaration order* are load-bearing: this is the
/// only label source in the app, and its key order drives the section order on
/// the Categories screen, the category picker and the spending donut's Groups
/// mode. Keep it identical to the web dictionary — expense groups in seed order
/// 1-10, then income in seed order (earnings, returns, inflows), then `other`.
const Map<String, String> categoryGroupLabels = {
  'food': 'Food',
  'transport': 'Transport',
  'home': 'Home',
  'bills': 'Bills & Subscriptions',
  'health': 'Health',
  'education': 'Education',
  'lifestyle': 'Lifestyle',
  'family_giving': 'Family & Giving',
  'savings': 'Savings & Deposits',
  'debt_transfers': 'Loans & Transfers',
  'earnings': 'Earnings',
  'returns': 'Returns & Interest',
  'inflows': 'Other Inflows',
  'other': 'Other',
};
