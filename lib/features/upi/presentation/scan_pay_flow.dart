/// Phase 7.8 — the whole thing, from one button: scan, pay, record.
///
/// 7.7 put a scanner on the transaction form, which meant the owner had to
/// decide they were logging an expense *before* they knew what it would be.
/// At a counter it is the other way round: the code is in front of you, the
/// amount is on the till, and the ledger entry is the consequence. So this runs
/// in that order —
///
///     scan → confirm the amount → pay in the payment app → record what happened
///
/// — and it lives on the nav bar rather than inside a form, because the first
/// step now needs nothing typed at all.
///
/// The last step is the one that has to stay honest. A UPI deep-link response
/// is advisory (see [UpiResult]), so nothing here writes a transaction on its
/// own: it opens the transaction sheet with what it knows already filled in,
/// and the owner presses Save. What is saved is the owner's statement, not the
/// payment app's.
library;

import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../transactions/presentation/transaction_form_sheet.dart';
import '../../transactions/presentation/transactions_providers.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../data/upi_service.dart';
import '../domain/upi_qr.dart';
import '../domain/upi_request.dart';
import '../domain/upi_result.dart';
import 'upi_pay_sheet.dart';
import 'upi_scan_sheet.dart';

/// Where the flow lands the ledger row it creates.
const String _ledgerRoute = '/transactions';

/// Scan a UPI QR, pay it, and record the expense.
///
/// [location] is the route the shell is already on, so a scan started from the
/// ledger does not re-navigate. Resolves when the flow is over — completed,
/// abandoned at any step, or never started because nothing was scanned.
///
/// Every step can be backed out of, and backing out of a step **after** the
/// payment still offers the ledger row: the money has already moved by then,
/// and the one outcome this must never produce is a payment that leaves no
/// trace because a sheet was dismissed.
Future<void> startScanAndPay(
  BuildContext context,
  WidgetRef ref, {
  required String location,
}) async {
  final payload = await UpiScanSheet.show(context);
  if (payload == null || !context.mounted) return;

  // The QR's own amount is a starting point, never a verdict: a counter code
  // usually fixes none, and one that does can still be wrong for what is
  // actually being bought. So it is always shown, always editable, and the
  // sheet says which of the two it is looking at.
  final amount = await UpiAmountSheet.show(context, payload: payload);
  if (amount == null || !context.mounted) return;

  // UPI's intent contract is Android-only. Everywhere else the scan is still
  // worth having — it read the payee and the amount off the code — so the flow
  // skips straight to the ledger rather than offering a payment that cannot
  // happen.
  UpiResult? result;
  if (ref.read(upiServiceProvider).isSupported) {
    result = await UpiPaySheet.show(
      context,
      amount: amount,
      payeeName: payload.payeeName,
      note: payload.note,
      scanned: payload,
    );
    // Null means the sheet was dismissed, or the owner said they did not pay.
    // Either way there is nothing to record.
    if (result == null || !context.mounted) return;
  }

  await _record(
    context,
    ref,
    location: location,
    payload: payload,
    amount: amount,
    result: result,
  );
}

/// Opens the transaction sheet on a row that is already filled in.
///
/// Prefilled, not saved. An account is required by the API and a category is
/// worth choosing, so there is a decision to make either way — and making it
/// is also the owner's confirmation that the payment happened, which is the
/// only confirmation this app is entitled to.
Future<void> _record(
  BuildContext context,
  WidgetRef ref, {
  required String location,
  required UpiQrPayload payload,
  required num amount,
  required UpiResult? result,
}) async {
  // Land on the ledger first, so the row appears under the form it was logged
  // in — the same order `AddSheet` uses.
  if (location != _ledgerRoute) {
    context.go(_ledgerRoute);
    // Let the new route build before a sheet is pushed over it.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
  }

  final container = ProviderScope.containerOf(context, listen: false);
  final saved = await showTransactionSheet(
    context,
    ref,
    initialType: TransactionType.expense,
    initialAmount: amount,
    initialPayee: payload.payeeName,
    initialNote: upiNote(payload: payload, result: result),
    initialScanned: payload,
  );
  if (saved == null) return;

  // The ledger may be filtered to a month this row falls outside of, so reload
  // rather than splicing it in blind. The form sheet has already dropped the
  // balance, summary and account caches.
  if (container.exists(transactionsListProvider)) {
    await container.read(transactionsListProvider.notifier).refresh();
  }
}

/// What the note says on a row that came from a scan.
///
/// The QR's own note first — it is what the shop wrote on the bill — then the
/// PSP's reference, which is the only string that ties this row to the payment
/// if anyone ever has to reconcile the two. Either can be absent; both being
/// absent leaves the note empty rather than inventing something.
///
/// Deliberately not the word "paid": [UpiResult] is advisory, and a note is not
/// the place to assert what the rest of the app is careful not to.
String? upiNote({required UpiQrPayload payload, required UpiResult? result}) {
  final parts = <String>[];

  final printed = payload.note?.trim();
  if (printed != null && printed.isNotEmpty) parts.add(printed);

  final reference = result?.transactionId?.trim();
  if (reference != null && reference.isNotEmpty) parts.add('UPI $reference');

  return parts.isEmpty ? null : parts.join(' · ');
}

/// "How much?" — the one step between reading a code and paying it.
///
/// Its whole job is to put the payee and the figure on the same screen before
/// any money moves. The VPA is shown in monospace directly under the name
/// because the name is whatever the printer typed and the VPA is what money
/// follows; a sticker over a shop's real code is the standard UPI fraud, and
/// this is the last screen on which it can be spotted.
class UpiAmountSheet extends StatefulWidget {
  const UpiAmountSheet({super.key, required this.payload});

  final UpiQrPayload payload;

  /// The amount to pay, or null when the sheet was dismissed.
  static Future<num?> show(
    BuildContext context, {
    required UpiQrPayload payload,
  }) {
    return showModalBottomSheet<num>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpiAmountSheet(payload: payload),
    );
  }

  @override
  State<UpiAmountSheet> createState() => _UpiAmountSheetState();
}

class _UpiAmountSheetState extends State<UpiAmountSheet> {
  late final TextEditingController _amount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fixed = widget.payload.amount;
    _amount = TextEditingController(
      text: fixed == null
          ? ''
          : fixed % 1 == 0
          ? fixed.toInt().toString()
          : fixed.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = parseAmount(_amount.text);
    if (value == null) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    // The same check the pay sheet uses, asked here so a figure that UPI
    // cannot carry is caught before a payment app is opened on it.
    final blocker = UpiRequest.amountBlocker(value);
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final payload = widget.payload;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'How much?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _PayeeCard(payload: payload),
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                symbol: '₹',
                tint: c.expense,
                errorText: _error,
                autofocus: true,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 8),
              Text(
                payload.hasAmount
                    ? 'The code asks for ${Money.format(payload.amount!)}. '
                          'Change it if the till says something else.'
                    : 'This code sets no amount — type what you owe.',
                style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
              ),
              const SizedBox(height: 18),
              AppButton(
                label: 'Continue',
                icon: LucideIcons.arrowRight,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who the code pays, exactly as it was printed.
///
/// Never machine-translated: 7.3 caught the app's translating `Text` rewriting
/// user data, and a rewritten payee name on this screen would hide the one
/// check anyone has.
class _PayeeCard extends StatelessWidget {
  const _PayeeCard({required this.payload});

  final UpiQrPayload payload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paying',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(text: payload.payeeName),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(text: payload.payeeVpa.value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              color: c.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
