import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../data/stocks_repository.dart';
import '../domain/stock.dart';

/// Symbol lookup over `GET /stocks/search?q=`.
///
/// The endpoint answers with `{symbol, ticker, exchange, shortName, longName,
/// sector, industry}` and **no price** — it identifies the instrument, and the
/// buy sheet asks for the price. Two rules mirror the web client exactly: the
/// query is debounced by 250ms, and nothing is sent until it is at least two
/// characters, which is where the backend starts answering usefully.
class StockSearchSheet extends ConsumerStatefulWidget {
  const StockSearchSheet({super.key});

  /// Resolves to the chosen instrument, or null when the sheet is dismissed.
  static Future<StockQuote?> show(BuildContext context) {
    return showModalBottomSheet<StockQuote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const StockSearchSheet(),
    );
  }

  @override
  ConsumerState<StockSearchSheet> createState() => _StockSearchSheetState();
}

class _StockSearchSheetState extends ConsumerState<StockSearchSheet> {
  static const Duration _debounce = Duration(milliseconds: 250);
  static const int _minQuery = 2;

  final TextEditingController _controller = TextEditingController();
  Timer? _timer;

  /// What the last keystroke settled on — the only value that reaches the API.
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _timer?.cancel();
    final next = raw.trim();
    // A cleared field should empty the list immediately rather than 250ms late.
    // The rebuild is unconditional so the "type at least two characters" hint
    // appears on the first keystroke.
    if (next.length < _minQuery) {
      setState(() => _query = '');
      return;
    }
    _timer = Timer(_debounce, () {
      if (!mounted || next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final typed = _controller.text.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Find a stock',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: AppTextField(
                  controller: _controller,
                  hint: 'Search a stock by name or ticker',
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  prefix: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: c.mutedForeground,
                  ),
                ),
              ),
              Flexible(child: _results(context, typed)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context, String typed) {
    if (_query.length < _minQuery) {
      return _Hint(
        icon: LucideIcons.search,
        title: typed.isEmpty
            ? 'Search NSE and BSE'
            : 'Type at least two characters.',
        message: typed.isEmpty
            ? 'Find the company by name or by ticker — RELIANCE, INFY, TCS.'
            : null,
      );
    }

    final results = ref.watch(stockSearchProvider(_query));

    return switch (results) {
      AsyncData(:final value) when value.isEmpty => const _Hint(
        icon: LucideIcons.searchX,
        title: 'No NSE or BSE stock matched that.',
        message: 'Check the spelling, or try the ticker instead of the name.',
      ),
      AsyncData(:final value) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: value.length,
        itemBuilder: (context, index) => _ResultRow(quote: value[index]),
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ErrorRetry(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(stockSearchProvider(_query)),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            LoadingShimmer(height: 54),
            SizedBox(height: 10),
            LoadingShimmer(height: 54),
            SizedBox(height: 10),
            LoadingShimmer(height: 54),
          ],
        ),
      ),
    };
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.quote});

  final StockQuote quote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);
    final exchange = quote.exchange;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(quote),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // `RELIANCE · Energy`, skipping whichever half is
                        // missing — the exchange rides in the badge instead.
                        [
                          quote.ticker ?? quote.symbol,
                          ?quote.sector,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (exchange != null && exchange.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _ExchangeBadge(label: exchange),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExchangeBadge extends StatelessWidget {
  const _ExchangeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: EmptyState(
        icon: icon,
        title: title,
        message: message,
        compact: true,
      ),
    );
  }
}
