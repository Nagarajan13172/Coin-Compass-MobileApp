import 'package:coincompass/core/utils/date_x.dart';
import 'package:coincompass/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.format — Indian grouping', () {
    test('whole thousands', () => expect(Money.format(13312), '₹13,312'));
    test('lakh grouping', () => expect(Money.format(123456), '₹1,23,456'));
    test(
      'crore grouping',
      () => expect(Money.format(20000000), '₹2,00,00,000'),
    );
    test(
      'negative uses real minus',
      () => expect(Money.format(-13312), '−₹13,312'),
    );
    test(
      'signed positive',
      () => expect(Money.format(5000, signed: true), '+₹5,000'),
    );
    test('decimals kept', () => expect(Money.format(1234.5), '₹1,234.50'));
    test('zero', () => expect(Money.format(0), '₹0'));
  });

  group('Money.compact — Indian short scale', () {
    test('14K', () => expect(Money.compact(14000), '₹14K'));
    test('1.5L', () => expect(Money.compact(150000), '₹1.5L'));
    test('1.25Cr', () => expect(Money.compact(12500000), '₹1.25Cr'));
    test('below 1000', () => expect(Money.compact(555), '₹555'));
    test('plain for axes', () => expect(Money.compactPlain(14000), '14K'));
  });

  group('Money.percent', () {
    test(
      'already scaled',
      () => expect(Money.percent(100, alreadyScaled: true), '100%'),
    );
    test('null is dash', () => expect(Money.percent(null), '—'));
  });

  _weekdayHeaderTests();

  group('DateX', () {
    final d = DateTime(2026, 8, 4, 5, 30);
    test('monthLabel', () => expect(DateX.monthLabel(d), 'August 2026'));
    test('dayLabel', () => expect(DateX.dayLabel(d), 'Tuesday, 04 Aug 2026'));
    test('timeLabel', () => expect(DateX.timeLabel(d), '5:30 AM'));
    test('rangeLabel same year', () {
      expect(
        DateX.rangeLabel(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
        '1 Aug – 1 Sep 2026',
      );
    });
    test('parse ISO from API', () {
      expect(DateX.parse('2026-08-04T00:00:00.000Z')?.year, 2026);
    });
    test('parse yyyy-MM-dd', () => expect(DateX.parse('2026-08-01')?.month, 8));
    test('parse null/empty', () {
      expect(DateX.parse(null), isNull);
      expect(DateX.parse(''), isNull);
    });
    test('startOfMonth/endOfMonth', () {
      expect(d.startOfMonth, DateTime(2026, 8, 1));
      expect(d.endOfMonth.day, 31);
    });
    test('startOfWeek Monday', () {
      // 4 Aug 2026 is a Tuesday -> week starts Mon 3 Aug
      expect(d.startOfWeek(1), DateTime(2026, 8, 3));
    });
    test('addMonths clamps short months', () {
      expect(DateTime(2026, 1, 31).addMonths(1), DateTime(2026, 2, 28));
      expect(DateTime(2026, 3, 31).addMonths(-1), DateTime(2026, 2, 28));
    });
    test('addMonths steps back across the year boundary', () {
      // Truncating `~/` used to leave this in 2026 — the MonthPager's back
      // chevron in January then jumped forward to December of the same year.
      expect(DateTime(2026, 1, 15).addMonths(-1), DateTime(2025, 12, 15));
      expect(DateTime(2026, 3, 15).addMonths(-13), DateTime(2025, 2, 15));
      expect(DateTime(2026, 1, 15).addMonths(-13), DateTime(2024, 12, 15));
    });
    test('addMonths steps forward across the year boundary', () {
      expect(DateTime(2026, 12, 15).addMonths(1), DateTime(2027, 1, 15));
      expect(DateTime(2026, 12, 15).addMonths(13), DateTime(2028, 1, 15));
    });
    test('addMonths back-steps reach the previous year one at a time', () {
      var m = DateTime(2026, 8, 15);
      for (var i = 0; i < 12; i++) {
        m = m.addMonths(-1);
      }
      expect(m, DateTime(2025, 8, 15));
    });
  });
}

void _weekdayHeaderTests() {
  group('DateX.weekdayShort — calendar header', () {
    // 4 Jan 1970 was a Sunday, so DateTime(1970, 1, 4 + weekday) maps a
    // DateTime.weekday value (1=Mon … 7=Sun) onto the right day name.
    String label(int weekday) =>
        DateX.weekdayShort(DateTime(1970, 1, 4 + weekday));

    test('Monday is first when weekday == 1', () => expect(label(1), 'Mon'));
    test('Tuesday', () => expect(label(2), 'Tue'));
    test('Saturday', () => expect(label(6), 'Sat'));
    test('Sunday wraps to weekday 7', () => expect(label(7), 'Sun'));
    test('never returns a bare number (the shortDay regression)', () {
      for (var w = 1; w <= 7; w++) {
        expect(
          int.tryParse(label(w)),
          isNull,
          reason:
              'weekday $w rendered "${label(w)}" — a day number, not a name',
        );
      }
    });
  });

  group('compact carries a sign', () {
    test('signed adds a leading + to a positive compact value', () {
      expect(Money.compact(150000, signed: true), '+\u20b91.5L');
      expect(Money.compact(12500000, signed: true), '+\u20b91.25Cr');
    });

    test('a negative compact value keeps its minus either way', () {
      expect(Money.compact(-150000, signed: true), Money.compact(-150000));
      expect(Money.compact(-150000).startsWith('\u2212'), isTrue);
    });

    test('zero never takes a plus', () {
      expect(Money.compact(0, signed: true), Money.compact(0));
    });

    test('unsigned is unchanged', () {
      expect(Money.compact(150000), '\u20b91.5L');
    });
  });

  group('compact picks its bucket after rounding', () {
    test('a hair under a crore reads as a crore, like the web', () {
      expect(Money.compact(9999999), '\u20b91Cr');
    });

    test('a hair under a lakh reads as a lakh', () {
      expect(Money.compact(99999), '\u20b91L');
    });

    test('the buckets themselves are unchanged', () {
      expect(Money.compact(10000000), '\u20b91Cr');
      expect(Money.compact(12500000), '\u20b91.25Cr');
      expect(Money.compact(150000), '\u20b91.5L');
      expect(Money.compact(14000), '\u20b914K');
      expect(Money.compact(999), '\u20b9999');
    });

    test('a value that does not round up stays in its own bucket', () {
      expect(Money.compact(9900000), '\u20b999L');
      expect(Money.compact(99000), '\u20b999K');
    });

    test('the rounding boundary follows the requested precision', () {
      // At 0 decimals "99.6L" prints as "100L", so it belongs in Cr.
      expect(Money.compact(9960000, decimals: 0), '\u20b91Cr');
      // At 2 decimals it does not round up, so it stays in lakhs.
      expect(Money.compact(9960000), '\u20b999.6L');
    });

    test('negatives follow the same rule', () {
      // U+2212 minus, then the symbol: '\u2212\u20b91Cr'.
      expect(Money.compact(-9999999), '\u2212\u20b91Cr');
    });
  });
}
