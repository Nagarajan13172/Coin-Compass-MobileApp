import '../../../core/api/enums.dart';
import '../../../core/api/json.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.accountId,
    this.account,
    this.toAccountId,
    this.toAccount,
    this.categoryId,
    this.category,
    this.note = '',
    this.payee = '',
    this.tags = const [],
    this.oneoff = false,
    this.currency = 'INR',
    this.recurringId,
    this.loanId,
    this.loanPrincipal = 0,
    this.loanInterest = 0,
    this.creditId,
    this.goalId,
    this.goalContribution = 0,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final TransactionType type;
  final num amount;
  final DateTime? date;

  // References arrive as either an id string or a populated object.
  final String? accountId;
  final Account? account;
  final String? toAccountId;
  final Account? toAccount;
  final String? categoryId;
  final Category? category;

  final String note;
  final String payee;
  final List<String> tags;
  final bool oneoff;
  final String currency;
  final String? recurringId;
  final String? loanId;
  final num loanPrincipal;
  final num loanInterest;
  final String? creditId;
  final String? goalId;
  final num goalContribution;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;
  bool get isTransfer => type == TransactionType.transfer;
  bool get isDeleted => deletedAt != null;
  bool get isRecurring => recurringId != null;

  /// Negative for expenses so lists and sums can use one number.
  num get signedAmount => isExpense ? -amount : amount;

  /// Falls back to the payee, then the category name, then the type label —
  /// mirrors how the web app titles a row.
  String get title {
    if (payee.isNotEmpty) return payee;
    if (category != null && category!.name.isNotEmpty) return category!.name;
    if (note.isNotEmpty) return note;
    return type.label;
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final categoryObject = J.refObject(json['category']);
    final accountObject = J.refObject(json['account']);
    final toAccountObject = J.refObject(json['toAccount']);

    return Transaction(
      id: J.id(json['_id']),
      type: TransactionType.fromApi(J.strOrNull(json['type'])),
      amount: J.number(json['amount']),
      date: J.date(json['date']),
      accountId: J.refId(json['account']),
      account: accountObject == null ? null : Account.fromJson(accountObject),
      toAccountId: J.refId(json['toAccount']),
      toAccount: toAccountObject == null
          ? null
          : Account.fromJson(toAccountObject),
      categoryId: J.refId(json['category']),
      category: categoryObject == null
          ? null
          : Category.fromJson(categoryObject),
      note: J.str(json['note']),
      payee: J.str(json['payee']),
      tags: J.stringList(json['tags']),
      oneoff: J.boolean(json['oneoff']),
      currency: J.str(json['currency'], 'INR'),
      recurringId: J.refId(json['recurring']),
      loanId: J.refId(json['loan']),
      loanPrincipal: J.number(json['loanPrincipal']),
      loanInterest: J.number(json['loanInterest']),
      creditId: J.refId(json['credit']),
      goalId: J.refId(json['goal']),
      goalContribution: J.number(json['goalContribution']),
      deletedAt: J.date(json['deletedAt']),
      createdAt: J.date(json['createdAt']),
      updatedAt: J.date(json['updatedAt']),
    );
  }
}

/// `POST /transactions` requires type, amount and account.
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.date,
    this.note,
    this.payee,
    this.tags = const [],
    this.oneoff = false,
    this.currency = 'INR',
  });

  final TransactionType type;
  final num amount;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final DateTime? date;
  final String? note;
  final String? payee;
  final List<String> tags;
  final bool oneoff;
  final String currency;

  Map<String, dynamic> toJson() => {
    'type': type.api,
    'amount': amount,
    'account': accountId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (categoryId != null) 'category': categoryId,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (note != null && note!.isNotEmpty) 'note': note,
    if (payee != null && payee!.isNotEmpty) 'payee': payee,
    if (tags.isNotEmpty) 'tags': tags,
    'oneoff': oneoff,
    'currency': currency,
  };
}

/// `GET /transactions/summary`
class TransactionSummary {
  const TransactionSummary({
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.incomeCount = 0,
    this.expenseCount = 0,
    this.count = 0,
  });

  final num income;
  final num expense;
  final num net;
  final int incomeCount;
  final int expenseCount;
  final int count;

  factory TransactionSummary.fromJson(Map<String, dynamic> json) =>
      TransactionSummary(
        income: J.number(json['income']),
        expense: J.number(json['expense']),
        net: J.number(json['net']),
        incomeCount: J.integer(json['incomeCount']),
        expenseCount: J.integer(json['expenseCount']),
        count: J.integer(json['count']),
      );
}

/// `GET /transactions/balance` -> `{balance, byAccount:{id: amount}}`
class BalanceSnapshot {
  const BalanceSnapshot({this.balance = 0, this.byAccount = const {}});

  final num balance;
  final Map<String, num> byAccount;

  factory BalanceSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = J.map(json['byAccount']);
    return BalanceSnapshot(
      balance: J.number(json['balance']),
      byAccount: {
        for (final entry in raw.entries) entry.key: J.number(entry.value),
      },
    );
  }
}
