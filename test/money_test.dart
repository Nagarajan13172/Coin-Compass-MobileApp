import 'package:coincompass/core/utils/date_x.dart';
import 'package:coincompass/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.format — Indian grouping', () {
    test('whole thousands', () => expect(Money.format(13312), '₹13,312'));
    test('lakh grouping', () => expect(Money.format(123456), '₹1,23,456'));
    test('crore grouping', () => expect(Money.format(20000000), '₹2,00,00,000'));
    test('negative uses real minus', () => expect(Money.format(-13312), '−₹13,312'));
    test('signed positive', () => expect(Money.format(5000, signed: true), '+₹5,000'));
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
    test('already scaled', () => expect(Money.percent(100, alreadyScaled: true), '100%'));
    test('null is dash', () => expect(Money.percent(null), '—'));
  });

  group('DateX', () {
    final d = DateTime(2026, 8, 4, 5, 30);
    test('monthLabel', () => expect(DateX.monthLabel(d), 'August 2026'));
    test('dayLabel', () => expect(DateX.dayLabel(d), 'Tuesday, 04 Aug 2026'));
    test('timeLabel', () => expect(DateX.timeLabel(d), '5:30 AM'));
    test('rangeLabel same year', () {
      expect(DateX.rangeLabel(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
          '1 Aug – 1 Sep 2026');
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
    });
  });
}
