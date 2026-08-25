import '../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/widgets/form_sheet_scaffold.dart';
import '../../settings/data/settings_repository.dart';
import '../data/export_repository.dart';
import 'period.dart';

/// Hands a CSV that [ExportRepository] has already written to disk to the
/// platform share sheet.
///
/// Behind a provider for one reason: `SharePlus` talks to a method channel
/// that does not exist under `flutter test`, so a widget test that taps
/// "Export range" would blow up inside the plugin instead of exercising the
/// sheet. Tests override this with a recorder; production gets the real thing.
typedef CsvSharer = Future<void> Function(ExportedCsv csv);

final csvSharerProvider = Provider<CsvSharer>((ref) => shareCsvViaPlatform);

Future<void> shareCsvViaPlatform(ExportedCsv csv) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(csv.path, mimeType: 'text/csv', name: csv.fileName)],
      // `cross_file` ignores XFile.name off the web, so the receiving app only
      // sees the real filename when it is overridden here as well.
      fileNameOverrides: [csv.fileName],
      subject: csv.fileName,
    ),
  );
}

/// The mobile form of the web's Export-CSV popover (`KZ`, bundle offset
/// 1020908): the same three actions and the same two date fields, as a bottom
/// sheet rather than a `w-72` popover anchored to a header button.
///
/// The web renders each action as an `<a href="/api/export/csv?…">` and lets
/// the browser download it. That cannot work here — the session is an httpOnly
/// cookie living in Dio's jar, so an external browser tab would get a 401. The
/// bytes come back through the same client, land in the app's temp directory
/// and are handed to the share sheet.
///
/// Three windows, matching the web exactly:
///
///   * **This period** — the visible `[start, end)` window, verbatim.
///   * **All transactions** — no `from`/`to` at all.
///   * **Custom range** — two calendar days; the last one is turned into the
///     midnight that follows it, which is the `addDays(to, 1)` the web applies
///     so that "to 24 Aug" includes 24 Aug rather than stopping before it.
class ExportCsvSheet extends ConsumerStatefulWidget {
  const ExportCsvSheet({super.key, required this.range});

  final PeriodRange range;

  static Future<bool?> show(BuildContext context, {required PeriodRange range}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExportCsvSheet(range: range),
    );
  }

  @override
  ConsumerState<ExportCsvSheet> createState() => _ExportCsvSheetState();
}

/// Which of the three actions is in flight — the sheet disables all of them
/// while any one runs, and only the busy one shows a spinner.
enum _Job { none, period, all, custom }

class _ExportCsvSheetState extends ConsumerState<ExportCsvSheet> {
  late DateTime _from = _day(widget.range.start);

  /// The last day *inside* the window. [PeriodRange.end] is exclusive, so the
  /// picker would otherwise open on 1 September for August.
  late DateTime _to = _day(widget.range.end.subtract(const Duration(days: 1)));

  _Job _job = _Job.none;
  String? _error;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _busy => _job != _Job.none;

  /// The web's rule verbatim: both set, and `from <= to`.
  bool get _rangeValid => !_from.isAfter(_to);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return FormSheetScaffold(
      title: 'Export CSV',
      submitLabel: 'Export range',
      submitting: _job == _Job.custom,
      onSubmit: _rangeValid && !_busy ? _exportCustom : null,
      formError: _error,
      footnote: 'Saved as a .csv file and passed to the share sheet — send it '
          'to yourself, or open it in a spreadsheet.',
      children: [
        _Caption('Download transactions'),
        const SizedBox(height: 8),
        _ActionRow(
          icon: LucideIcons.download,
          title: 'This period',
          subtitle: widget.range.periodLabel,
          busy: _job == _Job.period,
          enabled: !_busy,
          onTap: _exportPeriod,
        ),
        const SizedBox(height: 8),
        _ActionRow(
          icon: LucideIcons.calendarRange,
          title: 'All transactions',
          subtitle: 'Everything on record, with no date filter',
          busy: _job == _Job.all,
          enabled: !_busy,
          onTap: _exportAll,
        ),
        const SizedBox(height: 18),
        Divider(height: 1, color: c.border),
        const SizedBox(height: 16),
        _Caption('Custom range'),
        const SizedBox(height: 8),
        // Two fields on one line at 360dp: each is an Expanded flex child and
        // the label inside ellipsizes, so a long localised date cannot push
        // the row wider than the sheet.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DateField(
                label: 'From',
                value: _from,
                enabled: !_busy,
                // The web sets `max` on the From input; the picker gets the
                // same ceiling so an invalid pair cannot be chosen at all.
                lastDate: _to,
                onChanged: (picked) => setState(() {
                  _from = picked;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateField(
                label: 'To',
                value: _to,
                enabled: !_busy,
                firstDate: _from,
                onChanged: (picked) => setState(() {
                  _to = picked;
                  _error = null;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Both days are included.',
          style: TextStyle(fontSize: 12, color: c.mutedForeground),
        ),
      ],
    );
  }

  Future<void> _exportPeriod() => _run(
    _Job.period,
    (repo, currency) => repo.downloadCsv(
      from: widget.range.start,
      to: widget.range.end,
      baseCurrency: currency,
    ),
  );

  Future<void> _exportAll() => _run(
    _Job.all,
    (repo, currency) => repo.downloadCsv(baseCurrency: currency),
  );

  Future<void> _exportCustom() => _run(
    _Job.custom,
    (repo, currency) => repo.downloadCsvForDays(
      firstDay: _from,
      lastDay: _to,
      baseCurrency: currency,
    ),
  );

  Future<void> _run(
    _Job job,
    Future<ExportedCsv> Function(ExportRepository repo, String currency) fetch,
  ) async {
    if (_busy) return;
    setState(() {
      _job = job;
      _error = null;
    });

    final repository = ref.read(exportRepositoryProvider);
    final currency =
        ref.read(settingsProvider).valueOrNull?.baseCurrency ?? 'INR';
    final share = ref.read(csvSharerProvider);

    try {
      final csv = await fetch(repository, currency);
      await share(csv);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _job = _Job.none;
        _error = error.message;
      });
    } catch (error) {
      // The share sheet itself can fail (no handler, plugin missing). The
      // file is already written, so say so rather than implying the export
      // did not happen.
      if (!mounted) return;
      setState(() {
        _job = _Job.none;
        _error = 'The file was saved but could not be shared: $error';
      });
    }
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: context.colors.mutedForeground,
    ),
  );
}

/// One of the two one-tap downloads: glyph, title, muted second line.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.primary,
                        ),
                      )
                    : Icon(icon, size: 19, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mobile stand-in for `<input type="date">` — the label, the chosen day,
/// and a picker clamped by the other field.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
        ),
        const SizedBox(height: 5),
        Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? () => _pick(context) : null,
            borderRadius: radius,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: c.border),
                color: c.card,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 16,
                    color: c.mutedForeground,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      DateX.shortDay(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    // The clamps have to bracket `value` or showDatePicker asserts, so the
    // bounds are widened to include whatever is already selected.
    final low = firstDate == null || firstDate!.isAfter(value)
        ? DateTime(value.year - 10)
        : firstDate!;
    final high = lastDate == null || lastDate!.isBefore(value)
        ? DateTime(value.year + 10, 12, 31)
        : lastDate!;

    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: low,
      lastDate: high,
    );
    if (picked != null) onChanged(DateTime(picked.year, picked.month, picked.day));
  }
}
