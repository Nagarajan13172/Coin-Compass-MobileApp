import '../../../core/ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../domain/upi_qr.dart';

/// Phase 7.7 — point the camera at a UPI QR and read it.
///
/// Returns the [UpiQrPayload] on a confirmed scan, or null if the sheet was
/// dismissed. It reads and confirms; it never pays, and it never writes
/// anything — the caller fills its form from what comes back.
///
/// ## Why a confirmation step
///
/// A QR is untrusted: it was printed by someone else, and a sticker over a
/// shop's real code is the standard UPI fraud. The camera therefore stops on
/// the first readable code and shows **who it would pay** — VPA and all — for
/// the user to accept. Auto-filling straight from the camera would mean the
/// payee could change under the user's thumb between glance and tap.
class UpiScanSheet extends StatefulWidget {
  const UpiScanSheet({super.key});

  static Future<UpiQrPayload?> show(BuildContext context) {
    return showModalBottomSheet<UpiQrPayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const UpiScanSheet(),
    );
  }

  @override
  State<UpiScanSheet> createState() => _UpiScanSheetState();
}

class _UpiScanSheetState extends State<UpiScanSheet> {
  final MobileScannerController _controller = MobileScannerController(
    // QR only: a UPI code is never a barcode, and narrowing the formats stops
    // the scanner locking on to a product barcode that happens to be in frame.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  UpiQrPayload? _found;
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // Already holding a code and waiting for the user — further frames are
    // ignored, so the payee cannot change between glance and tap.
    if (_found != null) return;

    for (final barcode in capture.barcodes) {
      // Diagnostic: the raw code, exactly as printed. Pairs with UPI-OUT in
      // upi_service.dart so a failure can be read as "this went in, that came
      // out" rather than guessed at.
      debugPrint('UPI-QR-IN <- ${barcode.rawValue}');

      final result = UpiQr.parse(barcode.rawValue);
      if (result.isUsable) {
        setState(() {
          _found = result.payload;
          _problem = null;
        });
        _controller.stop();
        return;
      }
      // Keep scanning, but say what was wrong with what it saw. Silence here
      // leaves someone pointing a camera at a wall wondering if it works.
      if (result.problem != _problem) {
        setState(() => _problem = result.problem);
      }
    }
  }

  void _rescan() {
    setState(() {
      _found = null;
      _problem = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
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
                      'Scan a UPI QR',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_found != null)
                _Found(
                  payload: _found!,
                  onUse: () => Navigator.of(context).pop(_found),
                  onRescan: _rescan,
                )
              else
                _Camera(
                  controller: _controller,
                  onDetect: _onDetect,
                  problem: _problem,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Camera extends StatelessWidget {
  const _Camera({
    required this.controller,
    required this.onDetect,
    required this.problem,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: AspectRatio(
            aspectRatio: 1,
            child: MobileScanner(
              controller: controller,
              onDetect: onDetect,
              // The camera can fail for reasons the user can act on — a denied
              // permission, another app holding it — so it says which.
              errorBuilder: (context, error) => ColoredBox(
                color: c.muted,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.cameraOff, color: c.mutedForeground),
                        const SizedBox(height: 10),
                        Text(
                          switch (error.errorCode) {
                            MobileScannerErrorCode.permissionDenied =>
                              'CoinCompass needs the camera to scan a QR. '
                                  'Allow it in system settings and try again.',
                            MobileScannerErrorCode.unsupported =>
                              'This device cannot scan QR codes.',
                            _ => 'The camera could not be started.',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          problem ?? 'Point the camera at the payment QR.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: problem == null ? c.mutedForeground : c.warning,
          ),
        ),
      ],
    );
  }
}

/// User data — a QR's payee name and VPA are printed by someone else and must
/// read exactly as printed. 7.3 found the app's translating `Text` rewriting
/// this kind of value, which here would hide who is about to be paid.
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

class _Found extends StatelessWidget {
  const _Found({
    required this.payload,
    required this.onUse,
    required this.onRescan,
  });

  final UpiQrPayload payload;
  final VoidCallback onUse;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.circleCheck, size: 18, color: c.income),
                  const SizedBox(width: 8),
                  Text(
                    'Code read',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.income,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Verbatim(
                payload.payeeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              // The VPA is the only part a payer can check. Shown in mono so a
              // lookalike character is easier to spot.
              _Verbatim(
                payload.payeeVpa.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: c.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                payload.hasAmount
                    ? 'Asks for ${Money.format(payload.amount!)}'
                    : 'No amount set — you enter it',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (payload.note != null) ...[
                const SizedBox(height: 2),
                _Verbatim(
                  payload.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Check the name and UPI ID against the shop before paying. Anyone can '
          'print a QR.',
          style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Use these details',
          icon: LucideIcons.check,
          onPressed: onUse,
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'Scan a different code',
          variant: AppButtonVariant.outlined,
          onPressed: onRescan,
        ),
      ],
    );
  }
}
