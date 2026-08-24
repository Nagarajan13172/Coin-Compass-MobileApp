import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ground truth captured from the deployed web app at
/// https://coincompass.sathishkumar.cloud/loans for the owner's real loan.
///
///   Total outstanding    ₹2,00,00,000
///   Monthly EMI          ₹1,37,000
///   Interest remaining   ~₹2,86,35,000   "At current EMIs & rates"
///   Payoff progress      29 yr 7 mo left · ETA Mar 2056
///
/// See docs/LOAN_MATH.md. If these fail, the Flutter figures have diverged from
/// what the user already sees on the web — fix the Dart, not the expectations.
void main() {
  Loan deena({num outstanding = 20000000, num roi = 7.25, num emi = 137000}) =>
      Loan(
        id: 'ground-truth',
        name: 'Deena',
        outstanding: outstanding,
        lender: 'UCO',
        type: LoanType.home,
        principal: 20000000,
        roi: roi,
        emi: emi,
      );

  group('loan payoff — must match the web app exactly', () {
    test('355 months remaining (29 yr 7 mo)', () {
      final n = deena().monthsRemaining;
      expect(n, isNotNull);
      expect(n, 355, reason: 'web app shows 29 yr 7 mo = 355 months');
      expect(n! ~/ 12, 29);
      expect(n % 12, 7);
    });

    test(
      'interest remaining is ₹2,86,35,000 — derived from the CEIL-ed month count',
      () {
        final n = deena().monthsRemaining!;
        final interest = n * 137000 - 20000000;
        expect(interest, 28635000);
        // Using the exact fractional month count instead would give 28,555,231
        // and would NOT match the web app. Guard that specific mistake.
        expect(interest, isNot(28555231));
      },
    );

    test('monthly interest at the current balance', () {
      expect(deena().monthlyInterest, closeTo(120833.33, 0.5));
    });
  });

  group('edge cases that must not crash or lie', () {
    test('EMI below the monthly interest never amortises -> null', () {
      // ₹2Cr at 7.25% accrues ~₹1.21L/month; a ₹50k EMI cannot service it.
      expect(deena(emi: 50000).monthsRemaining, isNull);
    });

    test('EMI exactly equal to the interest -> null (not infinity)', () {
      expect(deena(emi: 120833.3333333).monthsRemaining, isNull);
    });

    test('zero interest falls back to simple division', () {
      expect(deena(roi: 0, emi: 100000).monthsRemaining, 200);
    });

    test('zero EMI -> null rather than a divide-by-zero', () {
      expect(deena(emi: 0).monthsRemaining, isNull);
    });

    test('settled loan -> null or zero, never negative', () {
      final n = deena(outstanding: 0).monthsRemaining;
      expect(n == null || n <= 0, isTrue);
    });

    test(
      'progress is clamped to 0..1 even when outstanding exceeds principal',
      () {
        final l = deena(outstanding: 25000000);
        expect(l.progress, inInclusiveRange(0, 1));
      },
    );
  });
}
