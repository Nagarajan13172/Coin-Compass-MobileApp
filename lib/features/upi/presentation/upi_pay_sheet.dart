import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/upi_payee_book.dart';
import '../data/upi_service.dart';
import '../domain/upi_request.dart';
import '../domain/upi_result.dart';

/// Phase 7.6 — pay the amount you just typed, from inside the app.
///
/// The whole sheet exists to make one thing hard to get wrong: **paying the
/// wrong person**. The payee's VPA is shown verbatim next to the amount at
/// every step, because the deep link protects nothing — a typo does not fail,
/// it pays someone else, and no part of UPI will catch it.
///
/// Returns the [UpiResult] when a payment was attempted, or null when the sheet
/// was dismissed without one. The caller decides what to record; this sheet
/// never writes a transaction, because the response it gets back is **not proof
/// of payment** — see [UpiResult].
class UpiPaySheet extends ConsumerStatefulWidget {
  const UpiPaySheet({
    super.key,
    required this.amount,
    required this.payeeName,
    this.note,
  });

  final num amount;
  final String payeeName;
  final String? note;

  /// Null when nothing was attempted.
  static Future<UpiResult?> show(
    BuildContext context, {
    required num amount,
    required String payeeName,
    String? note,
  }) {
    return showModalBottomSheet<UpiResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpiPaySheet(
        amount: amount,
        payeeName: payeeName,
        note: note,
      ),
    );
  }

  @override
  ConsumerState<UpiPaySheet> createState() => _UpiPaySheetState();
}

class _UpiPaySheetState extends ConsumerState<UpiPaySheet> {
  final _vpaController = TextEditingController();

  Vpa? _vpa;
  bool _remember = true;
  bool _loadedRemembered = false;
  String? _vpaError;

  UpiApp? _paying;
  UpiResult? _result;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  @override
  void dispose() {
    _vpaController.dispose();
    super.dispose();
  }

  Future<void> _loadRemembered() async {
    final book = await ref.read(upiPayeeBookProvider.future);
    if (!mounted) return;
    final remembered = book.lookup(widget.payeeName);
    setState(() {
      _loadedRemembered = true;
      if (remembered != null) {
        _vpa = remembered;
        _vpaController.text = remembered.value;
      }
    });
  }

  void _onVpaChanged(String raw) {
    final parsed = Vpa.tryParse(raw);
    setState(() {
      _vpa = parsed;
      // Only complain once there is enough typed to be wrong — an error on the
      // first keystroke is noise, not help.
      _vpaError = raw.trim().length < 3 || parsed != null
          ? null
          : 'That is not a UPI ID. It looks like name@bank.';
    });
  }

  UpiRequest? get _request {
    final vpa = _vpa;
    if (vpa == null) return null;
    return UpiRequest(
      payeeVpa: vpa,
      payeeName: widget.payeeName,
      amount: widget.amount,
      note: widget.note,
    );
  }

  Future<void> _pay(UpiApp app) async {
    final request = _request;
    if (request == null || !request.isSendable) return;

    setState(() => _paying = app);

    if (_remember) {
      final book = await ref.read(upiPayeeBookProvider.future);
      await book.remember(widget.payeeName, request.payeeVpa);
    }

    final result = await ref.read(upiServiceProvider).pay(
      app: app,
      request: request,
    );

    if (!mounted) return;
    setState(() {
      _paying = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Asked of the amount alone: the sheet must be able to say "too large"
    // before a VPA has been typed.
    final blocker = UpiRequest.amountBlocker(widget.amount);

    return _SheetBody(
      title: 'Pay with UPI',
      child: _result != null
          ? _Outcome(
              result: _result!,
              amount: widget.amount,
              payeeName: widget.payeeName,
              onClose: (record) =>
                  Navigator.of(context).pop(record ? _result : null),
            )
          : _Chooser(
              amount: widget.amount,
              payeeName: widget.payeeName,
              vpaController: _vpaController,
              vpa: _vpa,
              vpaError: _vpaError,
              onVpaChanged: _onVpaChanged,
              remember: _remember,
              onRememberChanged: (v) => setState(() => _remember = v),
              loadedRemembered: _loadedRemembered,
              blocker: blocker,
              paying: _paying,
              onPay: _pay,
            ),
    );
  }
}

/// A plain bottom-sheet shell.
///
/// `FormSheetScaffold` is the app's usual sheet, but it is built around a
/// submit button and this sheet has none: the action *is* choosing an app, and
/// a "Save" that did nothing would be a control claiming something it cannot
/// do. So this borrows the chrome and leaves out the footer.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      // Keeps the sheet above the keyboard while a UPI ID is being typed.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
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
              const SizedBox(height: 6),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// User data, never machine-translated.
///
/// A payee name and a VPA are the user's own strings, and 7.3 found the app's
/// translating `Text` rewriting exactly this kind of value — an account called
/// `Import Test` displayed as `இறக்குமதி சோதனை`. Here it would be worse than
/// confusing: the VPA on screen is the only check anyone has that the money is
/// going to the right place, so it must read exactly as typed.
class _Verbatim extends StatelessWidget {
  const _Verbatim(this.text, {this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(text: text),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class _Chooser extends ConsumerWidget {
  const _Chooser({
    required this.amount,
    required this.payeeName,
    required this.vpaController,
    required this.vpa,
    required this.vpaError,
    required this.onVpaChanged,
    required this.remember,
    required this.onRememberChanged,
    required this.loadedRemembered,
    required this.blocker,
    required this.paying,
    required this.onPay,
  });

  final num amount;
  final String payeeName;
  final TextEditingController vpaController;
  final Vpa? vpa;
  final String? vpaError;
  final ValueChanged<String> onVpaChanged;
  final bool remember;
  final ValueChanged<bool> onRememberChanged;
  final bool loadedRemembered;
  final String? blocker;
  final UpiApp? paying;
  final ValueChanged<UpiApp> onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final apps = ref.watch(upiAppsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AmountHeader(amount: amount, payeeName: payeeName),
        const SizedBox(height: 16),

        if (!loadedRemembered)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          AppTextField(
            controller: vpaController,
            label: 'Their UPI ID',
            hint: 'name@bank',
            errorText: vpaError,
            keyboardType: TextInputType.emailAddress,
            onChanged: onVpaChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                value: remember,
                onChanged: (v) => onRememberChanged(v ?? false),
              ),
              // The payee is often still blank at this point — the amount is
              // typed first — and interpolating it produced "Remember this for
              // , on this phone only".
              Expanded(
                child: payeeName.trim().isEmpty
                    ? Text(
                        'Remember this UPI ID on this phone only',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Remember this for '),
                            // The payee's own name — never translated.
                            TextSpan(text: payeeName.trim()),
                            const TextSpan(text: ', on this phone only'),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
              ),
            ],
          ),

          if (blocker != null) ...[
            const SizedBox(height: 8),
            Text(
              blocker!,
              style: TextStyle(fontSize: 12.5, color: c.destructive),
            ),
          ],

          const SizedBox(height: 16),
          Text(
            'Choose an app',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.mutedForeground),
          ),
          const SizedBox(height: 10),

          switch (apps) {
            AsyncLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            AsyncError() => Text(
              'Could not read the payment apps on this phone.',
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
            AsyncData(value: final list) when list.isEmpty => Text(
              'No UPI app found on this phone. Install one — Google Pay, '
              'PhonePe, Paytm — and it will appear here.',
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
            AsyncData(value: final list) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final app in list)
                  _AppTile(
                    app: app,
                    busy: paying?.packageName == app.packageName,
                    enabled: vpa != null && blocker == null && paying == null,
                    onTap: () => onPay(app),
                  ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },

          const SizedBox(height: 14),
          Text(
            'CoinCompass hands the amount to the app you choose. It never sees '
            'your UPI PIN, and it only records the expense after you confirm.',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
      ],
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.amount, required this.payeeName});

  final num amount;
  final String payeeName;

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
          Text('Paying', style: TextStyle(fontSize: 12.5, color: c.mutedForeground)),
          const SizedBox(height: 2),
          Text(
            Money.format(amount),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          if (payeeName.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            _Verbatim(
              'to $payeeName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final UpiApp app;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : app.icon != null
                        ? Image.memory(app.icon!, filterQuality: FilterQuality.medium)
                        : Icon(LucideIcons.wallet, color: c.mutedForeground),
              ),
              const SizedBox(height: 8),
              // The app's own name, as Android reports it — never translated.
              _Verbatim(
                app.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the payment app said, and the one decision left.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.result,
    required this.amount,
    required this.payeeName,
    required this.onClose,
  });

  final UpiResult result;
  final num amount;
  final String payeeName;

  /// true = record the expense.
  final ValueChanged<bool> onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (icon, tint, headline) = switch (result.status) {
      UpiStatus.success => (LucideIcons.circleCheck, c.income, 'The app reported success'),
      UpiStatus.pending => (LucideIcons.clock, c.warning, 'The payment is still going through'),
      UpiStatus.failure => (LucideIcons.circleX, c.destructive, 'The payment did not go through'),
      UpiStatus.cancelled => (LucideIcons.undo2, c.mutedForeground, 'No payment was made'),
      UpiStatus.unknown => (LucideIcons.circleHelp, c.warning, 'The app did not say what happened'),
    };

    // Deliberately not the word "Paid". The deep-link response is advisory —
    // only the bank is authoritative — and this app has spent its life not
    // stating things about money it cannot back up.
    final explanation = switch (result.status) {
      UpiStatus.success =>
        'Check your bank or the payment app before relying on it. '
            'UPI cannot confirm a payment back to this app.',
      UpiStatus.pending =>
        'Bank transfers can take a few minutes to settle. Check the payment '
            'app before recording it as spent.',
      UpiStatus.failure => 'Nothing was taken from your account.',
      UpiStatus.cancelled => 'You backed out before paying.',
      UpiStatus.unknown =>
        'The payment app returned something this app does not understand. '
            'Check the app before recording anything.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                headline,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(explanation, style: TextStyle(fontSize: 13, color: c.mutedForeground)),

        if (result.transactionId != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(AppTheme.radius - 4),
            ),
            child: _Verbatim(
              'UPI reference: ${result.transactionId}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],

        const SizedBox(height: 20),
        if (result.mayHavePaid)
          AppButton(
            label: 'Record ${Money.format(amount)} as spent',
            icon: LucideIcons.check,
            onPressed: () => onClose(true),
          ),
        const SizedBox(height: 8),
        AppButton(
          label: result.mayHavePaid ? "Don't record it" : 'Close',
          variant: AppButtonVariant.outlined,
          onPressed: () => onClose(false),
        ),
      ],
    );
  }
}
