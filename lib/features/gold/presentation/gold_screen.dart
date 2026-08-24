import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../data/metals_repository.dart';
import '../domain/metal_price.dart';
import 'gold_providers.dart';
import 'widgets/metal_history_chart.dart';
import 'widgets/metal_price_card.dart';

/// `/metals/latest` + `/metals/history` — today's gold and silver board, the
/// trend behind it, and a calculator for what a given weight is worth.
///
/// Body only; [AppScaffold] supplies the chrome.
class GoldScreen extends ConsumerStatefulWidget {
  const GoldScreen({super.key});

  @override
  ConsumerState<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends ConsumerState<GoldScreen> {
  /// True while `POST /metals/refresh` is in flight — the server rate-limits it
  /// to once every 15 minutes, so the button must not be double-fired.
  bool _refreshing = false;

  /// Pull-to-refresh re-reads what the server already has; it never triggers a
  /// scrape. Re-scraping is the explicit button beside the city picker.
  Future<void> _reload() async {
    ref.invalidate(metalsLatestProvider);
    ref.invalidate(metalsHistoryProvider);
    try {
      await ref.read(metalsLatestProvider.future);
    } catch (_) {
      // The error surface is rendered from the provider; just stop the spinner.
    }
  }

  Future<void> _refreshRates() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(metalsRepositoryProvider).refresh();
      ref.invalidate(metalsLatestProvider);
      ref.invalidate(metalsHistoryProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Rates refreshed')));
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : "Couldn't refresh rates";
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metals = ref.watch(metalsLatestProvider);
    // With no metals provider wired up there is nothing to re-scrape and no
    // rate to localise, so the controls stay out of the way of the explanation.
    final configured = metals.valueOrNull?.configured ?? true;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          const ScreenHeader(
            title: 'Gold & Silver',
            subtitle:
                'Live precious-metal rates in ₹ · auto-refreshed daily, or refresh now',
          ),
          if (configured)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: _CityRow(
                refreshing: _refreshing,
                onRefresh: _refreshRates,
              ),
            ),
          switch (metals) {
            AsyncData(:final value) => _Board(metals: value),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(metalsLatestProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 5),
                  SizedBox(height: 12),
                  LoadingCard(lines: 4),
                  SizedBox(height: 12),
                  LoadingCard(lines: 6),
                ],
              ),
            ),
          },
        ],
      ),
    );
  }
}

/// City picker + the manual re-scrape button.
///
/// There is no city parameter on the API: Chennai is GRT's published counter
/// rate and every other city is derived from international spot with that
/// city's premium. Picking one only changes the maths this screen does.
class _CityRow extends ConsumerWidget {
  const _CityRow({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final city = ref.watch(metalCityProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppSelect<String>(
            value: city.key,
            items: [
              for (final option in kMetalCities)
                SelectItem(option.key, option.label, icon: LucideIcons.mapPin),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref.read(metalCityProvider.notifier).state = metalCityFor(value);
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          height: 52,
          child: OutlinedButton(
            onPressed: refreshing ? null : () => onRefresh(),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
            ),
            child: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(
                    LucideIcons.refreshCw,
                    size: 18,
                    color: c.secondaryForeground,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The configured / no-rates / rates states of `/metals/latest`.
class _Board extends StatelessWidget {
  const _Board({required this.metals});

  final MetalsLatest metals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = metals.gold;
    final silver = metals.silver;

    if (!metals.configured) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: DashedBox(
          child: EmptyState(
            icon: LucideIcons.coins,
            title: "Gold tracking isn't set up yet",
            message:
                'Gold & silver tracking is turned off for this account. Once the '
                'server has a metals provider wired up, the daily rate board '
                'appears here.',
          ),
        ),
      );
    }

    if (gold == null && silver == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: DashedBox(
          child: EmptyState(
            icon: LucideIcons.chartLine,
            title: 'No rates yet',
            message:
                'The first snapshot will appear after the next daily fetch. '
                'Check back shortly.',
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gold != null) ...[
            MetalPriceCard(price: gold),
            const SizedBox(height: 12),
          ],
          if (silver != null) ...[
            MetalPriceCard(price: silver),
            const SizedBox(height: 12),
          ],
          const MetalHistoryChart(),
          const SizedBox(height: 12),
          _CalculatorCard(metals: metals),
          const SizedBox(height: 16),
          Text(
            'Rates are scraped daily from GRT Jewellers (grtjewels.com). Chennai '
            'shows their published counter rate; other cities are estimated from '
            'it with a local premium (duty, GST & margin) and exclude making '
            'charges. Refreshed automatically once a day, or on demand with the '
            'refresh button above (max once every 15 minutes).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: c.mutedForeground,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// "What your gram is worth" — weight × today's per-gram rate, entirely
/// client-side. Nothing here is sent anywhere; it is a valuation aid, not a
/// holding.
class _CalculatorCard extends ConsumerStatefulWidget {
  const _CalculatorCard({required this.metals});

  final MetalsLatest metals;

  @override
  ConsumerState<_CalculatorCard> createState() => _CalculatorCardState();
}

class _CalculatorCardState extends ConsumerState<_CalculatorCard> {
  /// A sovereign is 8 g — the unit Indian jewellers actually quote.
  static const List<double> _presets = [1, 8, 10, 100];

  final TextEditingController _grams = TextEditingController(text: '8');

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double get _weight => double.tryParse(_grams.text.trim()) ?? 0;

  /// Something was typed, but `12.5.3` is not a weight.
  bool get _malformed =>
      _grams.text.trim().isNotEmpty &&
      double.tryParse(_grams.text.trim()) == null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final city = ref.watch(metalCityProvider);
    final gold = widget.metals.gold;
    final silver = widget.metals.silver;

    // Fall back to whichever metal the server actually returned.
    var metal = ref.watch(calculatorMetalProvider);
    if (metal == 'gold' && gold == null) metal = 'silver';
    if (metal == 'silver' && silver == null) metal = 'gold';
    final price = metal == 'gold' ? gold : silver;
    if (price == null) return const SizedBox.shrink();

    final purity = ref.watch(metalPurityProvider(metal));
    final rates = MetalRates.of(price, city);
    final perGram = rates.forPurity(purity);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calculator, size: 18, color: c.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'What your gram is worth',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Value jewellery or coins you already own at today’s rate. Nothing '
            'is saved.',
            style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
          ),
          if (gold != null && silver != null) ...[
            const SizedBox(height: 14),
            SegmentedPeriodSelector<String>(
              options: const [
                SegmentOption('gold', 'Gold'),
                SegmentOption('silver', 'Silver'),
              ],
              value: metal,
              onChanged: (value) =>
                  ref.read(calculatorMetalProvider.notifier).state = value,
            ),
          ],
          const SizedBox(height: 14),
          AppTextField(
            label: 'Weight in grams',
            controller: _grams,
            hint: 'e.g. 8',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            errorText: _malformed ? 'Enter a weight like 8 or 12.5' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                _GramChip(
                  label: preset == 8
                      ? '8 g · 1 sovereign'
                      : '${_trim(preset)} g',
                  selected: _weight == preset,
                  onTap: () {
                    _grams.text = _trim(preset);
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedPeriodSelector<MetalPurity>(
            options: [
              for (final option in MetalPurity.values)
                SegmentOption(option, option.label),
            ],
            value: purity,
            onChanged: (value) =>
                ref.read(metalPurityProvider(metal).notifier).state = value,
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: c.border),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Value',
                      style: TextStyle(fontSize: 13, color: c.mutedForeground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_trim(_weight)} g × ${purity.label} · ${_rateLabel(perGram)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // A valuation to the paise would be false precision, and the
              // long form still has to survive 100 g of gold on a 360dp row.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: MoneyText(
                    (_weight * perGram).round(),
                    compactAbove: 1000000,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (rates.approx) ...[
            const SizedBox(height: 8),
            Text(
              'Estimated for ${city.label} from international spot; excludes '
              'making charges and wastage.',
              style: TextStyle(fontSize: 11.5, color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }

  /// `8 g × 22K · ₹15,030/g` — the working behind the figure.
  String _rateLabel(num perGram) => '${Money.format(perGram)}/g';

  /// `8` rather than `8.0`, `12.5` kept as typed.
  static String _trim(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : '$value';
}

/// Weight preset pill.
class _GramChip extends StatelessWidget {
  const _GramChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primary.withValues(alpha: 0.12) : c.secondary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? c.primary : c.secondaryForeground,
            ),
          ),
        ),
      ),
    );
  }
}
