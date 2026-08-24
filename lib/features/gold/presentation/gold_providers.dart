import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_x.dart';
import '../domain/metal_price.dart';

/// Screen state and the client-side rate maths behind Gold & Silver.
///
/// The API publishes exactly one counter rate — GRT's Chennai board — plus the
/// international spot per gram. Every other city on the web app's picker is
/// *derived* from spot with a local premium (import duty, GST, jeweller
/// margin); there is no city parameter on `/metals/latest`. The premium table
/// and the derivation below are lifted verbatim from the deployed web bundle so
/// the two clients quote the same number.

@immutable
class MetalCity {
  const MetalCity(this.key, this.label, this.premiumPct);

  final String key;
  final String label;

  /// Percent added to the international spot per-gram price.
  final num premiumPct;
}

/// The web app's city list, premiums included.
const List<MetalCity> kMetalCities = [
  MetalCity('chennai', 'Chennai', 15.2),
  MetalCity('coimbatore', 'Coimbatore', 15.2),
  MetalCity('madurai', 'Madurai', 15.2),
  MetalCity('bengaluru', 'Bengaluru', 15),
  MetalCity('hyderabad', 'Hyderabad', 15),
  MetalCity('mumbai', 'Mumbai', 14.5),
  MetalCity('delhi', 'Delhi', 14.5),
  MetalCity('kolkata', 'Kolkata', 14.5),
];

const String kDefaultMetalCityKey = 'chennai';

MetalCity metalCityFor(String key) => kMetalCities.firstWhere(
  (city) => city.key == key,
  orElse: () => kMetalCities.first,
);

/// `spot × (1 + premium%)`.
num withPremium(num value, num premiumPct) => value * (1 + premiumPct / 100);

enum MetalPurity {
  k24('24K'),
  k22('22K'),
  k18('18K');

  const MetalPurity(this.label);

  final String label;

  /// `24K / gram` — the label above the headline figure.
  String get gramLabel => '$label / gram';
}

/// The three per-gram figures for one metal in one city, plus where they came
/// from.
@immutable
class MetalRates {
  const MetalRates({
    required this.gram24k,
    required this.gram22k,
    required this.gram18k,
    required this.source,
    required this.approx,
  });

  final num gram24k;
  final num gram22k;
  final num gram18k;

  /// `GRT · grtjewels.com` for a published counter rate, `≈ spot +15.2%` for a
  /// derived one.
  final String source;

  /// True when the figure is estimated from spot rather than quoted.
  final bool approx;

  num forPurity(MetalPurity purity) => switch (purity) {
    MetalPurity.k24 => gram24k,
    MetalPurity.k22 => gram22k,
    MetalPurity.k18 => gram18k,
  };

  /// Chennai gold is GRT's published retail board — used as-is, with spot+
  /// premium filling any purity the scrape did not carry. Every other city is
  /// derived from spot. Silver has no retail board at all (its `retail*` fields
  /// come back as 0), so it always quotes the raw per-gram spot, which is what
  /// the web app charts and shows.
  factory MetalRates.of(MetalPrice price, MetalCity city) {
    if (!price.isGold) {
      return MetalRates(
        gram24k: price.pricePerGram24k,
        gram22k: price.pricePerGram22k,
        gram18k: price.pricePerGram18k,
        source: price.source ?? '',
        approx: false,
      );
    }

    final retail = price.retail22k > 0;
    if (city.key == kDefaultMetalCityKey && retail) {
      return MetalRates(
        gram24k: price.retail24k > 0
            ? price.retail24k
            : withPremium(price.pricePerGram24k, city.premiumPct),
        gram22k: price.retail22k,
        gram18k: price.retail18k > 0
            ? price.retail18k
            : withPremium(price.pricePerGram18k, city.premiumPct),
        source: price.retailSource?.isNotEmpty == true
            ? price.retailSource!
            : 'GRT · Chennai',
        approx: false,
      );
    }

    return MetalRates(
      gram24k: withPremium(price.pricePerGram24k, city.premiumPct),
      gram22k: withPremium(price.pricePerGram22k, city.premiumPct),
      gram18k: withPremium(price.pricePerGram18k, city.premiumPct),
      source: '≈ spot +${_trim(city.premiumPct)}%',
      approx: true,
    );
  }

  static String _trim(num value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : '$value';
}

/// One plotted day: the same rate maths as the cards, applied to a history row.
@immutable
class MetalHistoryPoint {
  const MetalHistoryPoint({
    required this.date,
    required this.value,
    required this.approx,
  });

  final DateTime? date;
  final num value;
  final bool approx;
}

/// `/metals/history` rows -> the series for [purity] in [city].
List<MetalHistoryPoint> metalHistorySeries(
  List<MetalPrice> rows, {
  required MetalCity city,
  required MetalPurity purity,
}) {
  return [
    for (final row in rows)
      () {
        final rates = MetalRates.of(row, city);
        return MetalHistoryPoint(
          date: DateX.parse(row.date),
          value: rates.forPurity(purity),
          approx: rates.approx,
        );
      }(),
  ];
}

/// Today in Asia/Kolkata — the scrape's own day boundary. A `date` behind it
/// means the board has not been refreshed yet, so the card says "Last close"
/// instead of "As of".
String istToday([DateTime? now]) {
  final ist = (now ?? DateTime.now()).toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );
  final month = ist.month.toString().padLeft(2, '0');
  final day = ist.day.toString().padLeft(2, '0');
  return '${ist.year}-$month-$day';
}

/// Which city's premium the whole screen quotes.
final metalCityProvider = StateProvider<MetalCity>(
  (ref) => metalCityFor(kDefaultMetalCityKey),
);

/// Purity is a per-metal preference shared by the card, the chart and the
/// calculator, so the screen never shows two different purities at once.
/// Gold opens on 22K (the jewellery standard the counter rate quotes); silver
/// has no retail purities, so it opens on 24K/999.
final metalPurityProvider = StateProvider.family<MetalPurity, String>(
  (ref, metal) => metal == 'gold' ? MetalPurity.k22 : MetalPurity.k24,
);

/// The metal the history chart is plotting.
final historyMetalProvider = StateProvider<String>((ref) => 'gold');

/// Window for `/metals/history?days=` — 7 / 30 / 90 / 365, as on the web.
final historyDaysProvider = StateProvider<int>((ref) => 30);

/// The metal the "what your gram is worth" calculator prices.
final calculatorMetalProvider = StateProvider<String>((ref) => 'gold');
