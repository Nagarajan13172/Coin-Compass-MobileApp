import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/api/json.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/recurring_rule.dart';

/// What a run / post-one call did. The endpoints answer with either the updated
/// rule, the posted transactions, or a count — [posted] is null when the shape
/// carried no count, so callers can say "Rule run" instead of "Posted 0".
class RecurringRunResult {
  const RecurringRunResult({this.posted, this.rule});

  final int? posted;
  final RecurringRule? rule;

  static RecurringRunResult fromJson(Object? json) {
    if (json is List) {
      return RecurringRunResult(posted: json.length);
    }
    final map = J.map(json);
    final count = map['posted'] ?? map['count'] ?? map['created'];
    final transactions = map['transactions'];

    final rule = map['rule'];
    final ruleMap = rule is Map
        ? J.map(rule)
        : (map.containsKey('frequency') ? map : null);

    return RecurringRunResult(
      posted: count is num
          ? count.toInt()
          : (transactions is List ? transactions.length : null),
      rule: ruleMap == null ? null : RecurringRule.fromJson(ruleMap),
    );
  }
}

class RecurringRepository {
  const RecurringRepository(this._api);

  final ApiClient _api;

  Future<List<RecurringRule>> list() async {
    final json = await _api.getJson(Endpoints.recurring);
    return Envelope.rows(json, const [
      'rules',
      'recurring',
    ]).map(RecurringRule.fromJson).toList();
  }

  /// [body] uses wire field names — see `RecurringRule.toWriteJson()`.
  Future<RecurringRule> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.recurring, body: body);
    return RecurringRule.fromJson(Envelope.document(json, const ['rule']));
  }

  Future<RecurringRule> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.recurringRule(id), body: body);
    return RecurringRule.fromJson(Envelope.document(json, const ['rule']));
  }

  Future<void> delete(String id) =>
      _api.deleteJson(Endpoints.recurringRule(id));

  /// Posts every occurrence the rule is due for and advances `nextRun`.
  Future<RecurringRunResult> run(String id) async {
    final json = await _api.postJson(Endpoints.recurringRun(id));
    return RecurringRunResult.fromJson(json);
  }

  /// Advances `nextRun` past the due occurrence without posting anything.
  Future<RecurringRunResult> skip(String id) async {
    final json = await _api.postJson(Endpoints.recurringSkip(id));
    return RecurringRunResult.fromJson(json);
  }

  /// Posts a single occurrence, even when the rule is not due yet.
  Future<RecurringRunResult> postOne(String id) async {
    final json = await _api.postJson(Endpoints.recurringPostOne(id));
    return RecurringRunResult.fromJson(json);
  }

  /// Everything this rule has posted so far, newest first.
  Future<List<Transaction>> history(String id) async {
    final json = await _api.getJson(Endpoints.recurringTransactions(id));
    return Envelope.rows(json, const [
      'transactions',
    ]).map(Transaction.fromJson).toList();
  }
}

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(ref.watch(apiClientProvider)),
);

final recurringRulesProvider = FutureProvider<List<RecurringRule>>(
  (ref) => ref.watch(recurringRepositoryProvider).list(),
);

/// One rule's posted transactions, loaded when its history sheet opens.
final recurringHistoryProvider = FutureProvider.autoDispose
    .family<List<Transaction>, String>(
      (ref, id) => ref.watch(recurringRepositoryProvider).history(id),
    );
