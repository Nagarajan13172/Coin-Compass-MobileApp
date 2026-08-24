import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../domain/loan.dart';

/// `/loans` — borrowings, their EMI schedule, and the two actions that move
/// money against them.
///
/// [pay] and [preclose] are **not** probeable: an empty body is valid for
/// preclose and it simply executes. Their contracts were read off the deployed
/// web bundle instead (`POST /loans/:id/pay {amount, chargePct}`,
/// `POST /loans/:id/preclose {chargePct}`) — see docs/WRITE_SCHEMAS.md.
class LoansRepository {
  const LoansRepository(this._api);

  final ApiClient _api;

  Future<List<Loan>> list() async {
    final json = await _api.getJson(Endpoints.loans);
    return Envelope.rows(json, const ['loans']).map(Loan.fromJson).toList();
  }

  /// [body] uses wire field names — see `Loan.toWriteJson()`.
  Future<Loan> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.loans, body: body);
    return Loan.fromJson(Envelope.document(json, const ['loan']));
  }

  Future<Loan> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.loan(id), body: body);
    return Loan.fromJson(Envelope.document(json, const ['loan']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.loan(id));

  /// A part payment. The server reduces `outstanding` by [amount], adds the
  /// prepayment charge ([chargePct] percent of the amount) to `chargesPaid`,
  /// and closes the loan by itself once nothing is left.
  ///
  /// The body is built here, not by the caller, so no screen can invent a key:
  /// exactly `{amount, chargePct}` goes out.
  Future<Loan> pay({
    required String id,
    required num amount,
    num chargePct = 0,
  }) async {
    final json = await _api.postJson(
      Endpoints.loanPay(id),
      body: {'amount': amount, 'chargePct': chargePct},
    );
    return Loan.fromJson(Envelope.document(json, const ['loan']));
  }

  /// Settles the whole outstanding balance and marks the loan `closed`.
  ///
  /// Destructive and immediate — there is no dry-run and no undo. The body is
  /// exactly `{chargePct}`; the amount is whatever the server computes the
  /// balance to be, which is why the caller cannot pass one. Always confirm
  /// with the user first.
  Future<Loan> preclose({required String id, num chargePct = 0}) async {
    final json = await _api.postJson(
      Endpoints.loanPreclose(id),
      body: {'chargePct': chargePct},
    );
    return Loan.fromJson(Envelope.document(json, const ['loan']));
  }
}

final loansRepositoryProvider = Provider<LoansRepository>(
  (ref) => LoansRepository(ref.watch(apiClientProvider)),
);

/// Cached for the session: the loans list feeds the loans screen, the net-worth
/// liabilities total and the dashboard. Invalidate after any write with
/// `ref.invalidate(loansProvider)`.
final loansProvider = FutureProvider<List<Loan>>(
  (ref) => ref.watch(loansRepositoryProvider).list(),
);
