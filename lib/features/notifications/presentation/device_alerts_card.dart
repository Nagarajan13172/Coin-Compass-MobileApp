import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../data/notification_alerts.dart';
import '../data/notification_poller.dart';

/// Phase 7.4 — the Settings control for device alerts.
///
/// Off by default and asked for explicitly, because turning it on triggers the
/// Android 13 permission prompt and starts a periodic background task. Neither
/// should happen because someone installed the app.
///
/// The switch reflects what is **actually** true, not what was tapped: the user
/// can refuse the OS prompt, and a toggle that stayed on after that would be
/// claiming something the app cannot do — the same failure 7.1a had with the
/// language pill.
class DeviceAlertsCard extends ConsumerStatefulWidget {
  const DeviceAlertsCard({super.key});

  @override
  ConsumerState<DeviceAlertsCard> createState() => _DeviceAlertsCardState();
}

class _DeviceAlertsCardState extends ConsumerState<DeviceAlertsCard> {
  bool _enabled = false;
  bool _busy = true;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await ref.read(deviceAlertsProvider).isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _busy = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _note = null;
    });

    final now = await ref.read(deviceAlertsProvider).setEnabled(value);
    if (!mounted) return;

    setState(() {
      _enabled = now;
      _busy = false;
      // Only when the request and the result disagree: asking for `on` and
      // getting `off` back means Android refused.
      _note = value && !now
          ? 'Android did not grant permission to post notifications. '
                'Turn it on for CoinCompass in system settings, then try again.'
          : null;
    });
  }

  Future<void> _checkNow() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final result = await ref.read(deviceAlertsProvider).checkNow();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = switch (result) {
        null => 'Could not check just now.',
        PollResult(didRun: false, :final skippedReason) => skippedReason,
        PollResult(adopted: true) =>
          'Caught up. Notifications already in your feed were not repeated — '
              'you will be told about the next one.',
        PollResult(announced: 0) => 'Nothing new.',
        PollResult(:final announced) =>
          'Sent $announced ${announced == 1 ? 'notification' : 'notifications'}.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Notifications'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alerts on this phone',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Recurring transactions, budget limits and low balances '
                      '— the same alerts the bell shows, on your phone.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 34,
                child: Center(
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.primary,
                          ),
                        )
                      : Switch(value: _enabled, onChanged: _toggle),
                ),
              ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 4),
            Text(
              'Checked when you open the app, and about every 15 minutes in the '
              'background. Android decides the exact timing, so an alert can '
              'arrive late.',
              style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _checkNow,
                child: const Text('Check now'),
              ),
            ),
          ],
          if (_note != null) ...[
            const SizedBox(height: 6),
            Text(
              _note!,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
