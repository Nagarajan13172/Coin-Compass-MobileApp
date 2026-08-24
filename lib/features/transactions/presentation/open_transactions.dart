import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/enums.dart';
import '../../../core/utils/date_x.dart';
import '../data/transactions_repository.dart';
import 'transactions_providers.dart';

/// Opens the ledger filtered — the drill-through every analysis screen needs.
///
/// The Transactions screen takes no route query parameters: it reads the
/// shared [transactionQueryProvider], so the filter is written there first and
/// the navigation is a plain `go`. [transactionsMonthProvider] is set too,
/// because that screen re-stamps its month over the query on mount.
///
/// KNOWN LIMIT, and the reason this is one function rather than three: that
/// re-stamp means the window actually opened is the **calendar month
/// containing [from]**. For a Month window — the default, and the only one the
/// owner's data spans — that is exactly the window that was tapped. For Week
/// or Year it widens or narrows, and the ledger's own month header says which.
/// The type / category / account filters always survive intact. Fixing the
/// window properly means teaching TransactionsScreen to accept a pre-set
/// range, which would change how the calendar's "open ledger" behaves too.
///
/// Does nothing when there is no router above [context] — which is how the
/// widget tests mount these screens.
///
/// Reports and Insights each grew a private copy of this during Phase 5; they
/// disagreed on the router guard (one crashed without a router, one no-opped)
/// and on which month the ledger landed on. This is the surviving one.
void openTransactionsFiltered(
  BuildContext context,
  WidgetRef ref, {
  DateTime? from,
  DateTime? to,
  TransactionType? type,
  String? categoryId,
  String? accountId,
}) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;

  ref.read(transactionsMonthProvider.notifier).state =
      (from ?? DateTime.now()).startOfMonth;
  ref.read(transactionQueryProvider.notifier).state = TransactionQuery(
    from: from,
    to: to,
    type: type,
    categoryId: categoryId,
    accountId: accountId,
  );
  router.go('/transactions');
}
