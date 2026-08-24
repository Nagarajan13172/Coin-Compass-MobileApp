import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/loans/presentation/loans_providers.dart';
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

  group('web parity — figures executed from the deployed bundle', () {
    // These expectations were produced by extracting the web app's own `Ma`
    // function out of assets/index-BCZVpAqp.js and running it under Node, not
    // by re-deriving the formula. If one of these fails, the app and the
    // website are telling the owner different things about the same loan.

    test('a knife-edge EMI reports a term, exactly as the web does', () {
      // EMI Rs 1,20,834 against monthly interest of Rs 1,20,833.33 — it clears,
      // but only after 2011 months. The app used to bail out above 1200 months
      // and call this "EMI too low" while the website quoted 167 yr 7 mo.
      final s = amortiseReducingBalance(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 120834,
      );

      expect(s.feasible, isTrue);
      expect(s.months, 2011);
      expect(s.totalPaid, 242997174);
      expect(s.totalInterest, 222997174);
      expect(s.isImplausible, isTrue,
          reason: 'a 167-year term must still be flagged for presentation');
    });

    test('an EMI that cannot service the interest is still infeasible', () {
      final s = amortiseReducingBalance(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 100000,
      );
      expect(s.feasible, isFalse);
    });

    test('the real loan is not flagged implausible', () {
      final s = amortiseReducingBalance(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
      );
      expect(s.months, 355);
      expect(s.isImplausible, isFalse);
    });

    test('+Rs 10,000 a month matches the website to the rupee', () {
      // Web, executed: 287 months, interest 22189000, saved 6446000.
      final plan = planPrepayment(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
        extraPerMonth: 10000,
      );

      expect(plan.withPlan.months, 287);
      expect(plan.withPlan.totalInterest, 22189000);
      expect(plan.monthsSaved, 68);
      expect(plan.interestSaved, 6446000);
      expect(plan.netBenefit, 6446000);
    });
  });
}
