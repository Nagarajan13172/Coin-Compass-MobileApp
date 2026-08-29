import 'dart:async';

import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../data/upi_payee_book.dart';
import '../data/upi_service.dart';
import '../domain/upi_request.dart';
import '../domain/upi_qr.dart';
import '../domain/upi_result.dart';

/// Phase 7.6/7.8 — pay the amount you just typed, from inside the app.
///
/// The whole sheet exists to make one thing hard to get wrong: **paying the
/// wrong person**. The payee's VPA is shown verbatim next to the amount at
/// every step, because the deep link protects nothing — a typo does not fail,
/// it pays someone else, and no part of UPI will catch it.
///
/// ## The ladder
///
/// The sheet always starts at [UpiHandover.prefilled]: the payment app opens on
/// a payment that already has the payee, the amount and a reference in it, and
/// the only thing left to do there is approve it. That is the feature.
///
/// It cannot be the *only* rung, because whether a PSP honours a pre-filled
/// intent from an app that is not registered with it is that PSP's policy and
/// not something this app can satisfy. So when an attempt comes back refused —
/// **refused, not assumed** — the sheet offers the next rung down rather than
/// sending anyone away: payee only, amount typed there. See [UpiHandover].
///
/// Returns the [UpiResult] when a payment was attempted and the owner said to
/// record it, or null when the sheet was dismissed without one. The caller
/// decides what to record; this sheet never writes a transaction, because the
/// response it gets back is **not proof of payment** — see [UpiResult].
class UpiPaySheet extends ConsumerStatefulWidget {
  const UpiPaySheet({
    super.key,
    required this.amount,
    required this.payeeName,
    this.note,
    this.scanned,
  });

  final num amount;
  final String payeeName;
  final String? note;

  /// Supplied when the payee came from a scanned QR.
  ///
  /// Carries the whole payload, not just its VPA: paying a merchant means
  /// keeping `mc` and the merchant's own `tr`, because a link stripped back to
  /// a bare payee is treated as a person-to-person transfer and refused. See
  /// `UpiRequest.fromScan`.
  ///
  /// It also wins over anything remembered for the same payee name: the code in
  /// front of the user now is more current than a VPA saved weeks ago.
  final UpiQrPayload? scanned;

  /// Null when nothing was attempted.
  static Future<UpiResult?> show(
    BuildContext context, {
    required num amount,
    required String payeeName,
    String? note,
    UpiQrPayload? scanned,
  }) {
    return showModalBottomSheet<UpiResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpiPaySheet(
        amount: amount,
        payeeName: payeeName,
        note: note,
        scanned: scanned,
      ),
    );
  }

  @override
  ConsumerState<UpiPaySheet> createState() => _UpiPaySheetState();
}

class _UpiPaySheetState extends ConsumerState<UpiPaySheet> {
  /// The app currently being launched, so its tile can spin and the rest stay
  /// untappable.
  UpiApp? _paying;

  /// The app the last attempt went to, and how much went with it. Both are
  /// needed to offer the next rung down against the same app.
  UpiApp? _lastApp;
  UpiHandover _lastHandover = UpiHandover.prefilled;

  /// A result the payment app actually reported. Null while nothing has been
  /// attempted, and null again for a result that says nothing usable — those
  /// go to [_AskIfPaid] instead, because "the app told us nothing" and "the app
  /// told us it failed" are different facts and must not share a screen.
  UpiResult? _result;

  /// Set when the attempt came back with nothing this app can read, so the
  /// only honest thing left is to ask.
  bool _asking = false;

  /// The VPA this payment is going to, once resolved — from the scan, or from
  /// the payee book for a payee paid before. Null means there is nothing to
  /// build a payment link out of, and the app can only be opened.
  Vpa? _resolvedVpa;

  /// True until the payee book has been consulted. The chooser says what
  /// tapping an app will do, and it cannot say it before this is known.
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolvePayee();
  }

  /// Where the money is going, decided once when the sheet opens.
  ///
  /// A scan wins outright. Failing that, a payee paid this way before has their
  /// VPA remembered on this phone, which is what makes the second payment to
  /// the same shop as short as the first — see [UpiPayeeBook], and note that
  /// the book never leaves the device.
  Future<void> _resolvePayee() async {
    final scanned = widget.scanned;
    if (scanned != null) {
      if (mounted) {
        setState(() {
          _resolvedVpa = scanned.payeeVpa;
          _resolving = false;
        });
      }
      return;
    }

    Vpa? remembered;
    try {
      final book = await ref.read(upiPayeeBookProvider.future);
      remembered = book.lookup(widget.payeeName);
    } catch (_) {
      // No preferences on this platform, or a corrupt entry. A forgotten payee
      // costs one rung of convenience; failing the sheet over it would cost
      // the payment.
      remembered = null;
    }
    if (!mounted) return;
    setState(() {
      _resolvedVpa = remembered;
      _resolving = false;
    });
  }

  /// Everything this payment needs, or null when there is no payee to pay.
  UpiRequest? _request() {
    final scanned = widget.scanned;
    if (scanned != null) {
      return UpiRequest.fromScan(scanned, amount: widget.amount);
    }
    final vpa = _resolvedVpa;
    if (vpa == null) return null;

    final note = widget.note?.trim();
    return UpiRequest(
      payeeVpa: vpa,
      payeeName: widget.payeeName,
      amount: widget.amount,
      note: note == null || note.isEmpty ? null : note,
    );
  }

  /// Hands the payment to [app] at [handover], and reads what comes back.
  ///
  /// Nothing here decides that a payment happened. A reported status is shown
  /// as *reported*; anything unreadable becomes a question. The one thing this
  /// must never do is turn silence into a recorded expense.
  Future<void> _pay(UpiApp app, UpiHandover handover) async {
    setState(() {
      _paying = app;
      _lastApp = app;
      _lastHandover = handover;
      _result = null;
      _asking = false;
    });

    final service = ref.read(upiServiceProvider);
    final request = _request();

    UpiResult result;
    if (request == null || handover == UpiHandover.appOnly) {
      // No payee to build a link from — or the last rung, which is a launcher
      // intent and carries no result by construction.
      //
      // Recorded as `appOnly` whichever of the two it was, so the sheet does
      // not then offer "just open the app instead" as a remedy for having just
      // opened the app: there is no rung below this one.
      _lastHandover = UpiHandover.appOnly;
      await service.openApp(app);
      result = const UpiResult(status: UpiStatus.cancelled);
    } else {
      result = await service.pay(
        app: app,
        request: request,
        handover: handover,
      );
      // A payee worth paying twice is worth remembering. Written after the
      // launch rather than before, so a sheet dismissed without ever choosing
      // an app leaves nothing behind.
      unawaited(_remember(request.payeeVpa));
    }

    if (!mounted) return;
    setState(() {
      _paying = null;
      // SUCCESS / PENDING / FAILURE are things the app actually said, and are
      // shown as said. CANCELLED and UNKNOWN are not answers — a back press
      // and an unreadable response both mean nobody but the owner knows.
      final speaks =
          result.status == UpiStatus.success ||
          result.status == UpiStatus.pending ||
          result.status == UpiStatus.failure;
      _result = speaks ? result : null;
      _asking = !speaks;
    });
  }

  Future<void> _remember(Vpa vpa) async {
    if (widget.payeeName.trim().isEmpty) return;
    try {
      final book = await ref.read(upiPayeeBookProvider.future);
      await book.remember(widget.payeeName, vpa);
    } catch (_) {
      // Remembering is a convenience; a payment already made does not care.
    }
  }

  /// The rung below whatever was last tried, or null at the bottom.
  ///
  /// Only offered after an attempt has actually come back without a payment.
  /// Offering it up front would make "the amount could not be sent" the app's
  /// opening statement about a feature that usually works.
  UpiHandover? get _nextRung => switch (_lastHandover) {
    UpiHandover.prefilled =>
      _resolvedVpa == null ? UpiHandover.appOnly : UpiHandover.payeeOnly,
    UpiHandover.payeeOnly => UpiHandover.appOnly,
    UpiHandover.appOnly => null,
  };

  void _retry() {
    final app = _lastApp;
    final rung = _nextRung;
    if (app == null || rung == null) return;
    _pay(app, rung);
  }

  @override
  Widget build(BuildContext context) =>
      _SheetBody(title: 'Pay with UPI', child: _body());

  Widget _body() {
    final result = _result;
    if (result != null) {
      return _Outcome(
        result: result,
        amount: widget.amount,
        payeeName: widget.payeeName,
        retryLabel: _rungLabel(_nextRung),
        onRetry: _retry,
        onClose: (record) => Navigator.of(context).pop(record ? result : null),
      );
    }

    if (_asking) {
      return _AskIfPaid(
        amount: widget.amount,
        appLabel: _lastApp?.label ?? 'the payment app',
        handover: _lastHandover,
        retryLabel: _rungLabel(_nextRung),
        onRetry: _retry,
        onAnswer: (paid) => Navigator.of(context).pop(
          paid ? const UpiResult(status: UpiStatus.unknown) : null,
        ),
      );
    }

    return _Chooser(
      amount: widget.amount,
      payeeName: widget.payeeName,
      vpa: _resolvedVpa,
      resolving: _resolving,
      // Asked of the amount alone: the sheet must be able to say "too large"
      // before a VPA has been resolved.
      blocker: UpiRequest.amountBlocker(widget.amount),
      paying: _paying,
      onPay: (app) => _pay(app, UpiHandover.prefilled),
    );
  }

  static String? _rungLabel(UpiHandover? rung) => switch (rung) {
    UpiHandover.payeeOnly => 'Try again — I will type the amount there',
    UpiHandover.appOnly => 'Just open the app instead',
    UpiHandover.prefilled || null => null,
  };
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
    required this.vpa,
    required this.resolving,
    required this.blocker,
    required this.paying,
    required this.onPay,
  });

  final num amount;
  final String payeeName;

  /// Where the money is going. Null means there is nothing to pay *to*, and
  /// tapping an app can only open it.
  final Vpa? vpa;
  final bool resolving;
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
        _AmountHeader(amount: amount, payeeName: payeeName, vpa: vpa),
        const SizedBox(height: 16),

        if (blocker != null) ...[
          Text(blocker!, style: TextStyle(fontSize: 12.5, color: c.destructive)),
          const SizedBox(height: 12),
        ],

        Text(
          'Choose an app',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(height: 2),
        // What tapping a tile will actually do — and it differs, so it cannot
        // be one fixed sentence. With a VPA the app opens on a payment that is
        // already filled in; without one there is nothing to fill it with.
        Text(
          resolving
              ? 'Checking who this pays…'
              : vpa == null
              ? 'Opens the app so you can pay there. You will be asked '
                    'afterwards whether it went through.'
              : 'Opens the app on this payment with '
                    '${Money.format(amount)} already in it — you only approve '
                    'it with your UPI PIN.',
          style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
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
                  enabled: blocker == null && paying == null && !resolving,
                  onTap: () => onPay(app),
                ),
            ],
          ),
          _ => const SizedBox.shrink(),
        },

        const SizedBox(height: 14),
        Text(
          'CoinCompass opens the app and never sees your UPI PIN. It only '
          'records the expense after you confirm you paid.',
          style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
        ),
      ],
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({
    required this.amount,
    required this.payeeName,
    this.vpa,
  });

  final num amount;
  final String payeeName;

  /// Shown whenever it is known. The VPA is the only field money follows and
  /// the only one anyone can check, so it is on screen next to the figure at
  /// every step rather than hidden behind the payee's printed name.
  final Vpa? vpa;

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
          if (vpa != null) ...[
            const SizedBox(height: 3),
            // Monospace so a lookalike character in a swapped VPA stands out.
            _Verbatim(
              vpa!.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: c.mutedForeground,
              ),
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

/// "Did it go through?" — the only honest question after an app that reported
/// nothing this build can read.
///
/// Nothing is assumed. A back press and an unreadable response look identical
/// from here: the user may have paid, abandoned it, or gone to check something.
/// Guessing "yes" would put money in the ledger that never left the account,
/// which is the one thing this feature must not do.
///
/// [onRetry] is the way out that is not a guess. It appears only after an
/// attempt has actually come back — never before one — and drops the payment
/// one rung, so "the amount would not go through" is offered as a remedy rather
/// than announced as this app's opening position.
class _AskIfPaid extends StatelessWidget {
  const _AskIfPaid({
    required this.amount,
    required this.appLabel,
    required this.handover,
    required this.retryLabel,
    required this.onRetry,
    required this.onAnswer,
  });

  final num amount;
  final String appLabel;
  final UpiHandover handover;
  final String? retryLabel;
  final VoidCallback onRetry;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.circleHelp, size: 20, color: c.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Did you pay in '),
                    // The app's own name, as Android reports it.
                    TextSpan(text: appLabel),
                    const TextSpan(text: '?'),
                  ],
                ),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The payment app did not tell CoinCompass what happened, so only you '
          'know. Recording it adds the expense; it does not move any money.',
          style: TextStyle(fontSize: 13, color: c.mutedForeground),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Yes — record ${Money.format(amount)}',
          icon: LucideIcons.check,
          onPressed: () => onAnswer(true),
        ),
        if (retryLabel != null) ...[
          const SizedBox(height: 8),
          AppButton(
            label: retryLabel!,
            icon: LucideIcons.rotateCcw,
            variant: AppButtonVariant.outlined,
            onPressed: onRetry,
          ),
          const SizedBox(height: 6),
          Text(
            handover == UpiHandover.prefilled
                ? 'Some banks refuse a payment that arrives already filled in '
                      'from another app. Opening on the payee with the amount '
                      'blank is the same payment with one number to type.'
                : 'Opens the app on its own screen, so you can pay however you '
                      'normally would.',
            style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
          ),
        ],
        const SizedBox(height: 8),
        AppButton(
          label: "No, I didn't pay",
          variant: AppButtonVariant.outlined,
          onPressed: () => onAnswer(false),
        ),
      ],
    );
  }
}

/// What the payment app said, and the one decision left.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.result,
    required this.amount,
    required this.payeeName,
    required this.retryLabel,
    required this.onRetry,
    required this.onClose,
  });

  final UpiResult result;
  final num amount;
  final String payeeName;

  /// Null at the bottom of the ladder, or when the payment already went
  /// through — there is nothing to retry then.
  final String? retryLabel;
  final VoidCallback onRetry;

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

    // Retrying a payment the app says went through would be a second payment.
    final canRetry = retryLabel != null && !result.mayHavePaid;

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
        if (canRetry) ...[
          const SizedBox(height: 8),
          AppButton(
            label: retryLabel!,
            icon: LucideIcons.rotateCcw,
            variant: AppButtonVariant.outlined,
            onPressed: onRetry,
          ),
        ],
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
