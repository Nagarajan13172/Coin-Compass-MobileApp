import 'package:coincompass/core/api/enums.dart';
import 'package:coincompass/features/loans/domain/loan.dart';
import 'package:coincompass/features/loans/presentation/loans_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reducing-balance amortisation, the prepayment planner, and the portfolio
/// summary — the arithmetic behind every figure the Loans screen shows.
///
/// ## Where the numbers come from
///
/// The web app's source is not on this machine, but its *rendered output* is:
/// `scratchpad/shots/loans.png` shows the live loan (₹2,00,00,000 @ 7.25% p.a.,
/// EMI ₹1,37,000) as **"29 yr 7 mo left · ETA Mar 2056"** with **"Interest
/// remaining ~₹2,86,35,000"**. The closed form used here reproduces both
/// exactly — 355 months (= 29 yr 7 mo) and ₹2,86,35,000 — which is the
/// strongest evidence available that the model matches production.
///
/// Every other expectation below was worked out by hand from
///
///     n = ceil( −ln(1 − P·r / E) / ln(1 + r) ),  r = roi / 12 / 100
///     total interest = E·n − P
///
/// and, for the small cases, checked against a month-by-month simulation (see
/// the `simulation agrees` test, which amortises the balance one month at a
/// time and must land on the same term).
///
/// **Still to verify:** these figures have not been compared field-for-field
/// against the web app's own planner for a prepayment scenario — only the
/// no-prepayment case is confirmed by the screenshot. Before the planner's
/// "interest saved" and "net benefit" are trusted for a real decision, run the
/// same inputs through the web app and diff.
void main() {
  group('amortiseReducingBalance', () {
    test('reproduces the live loan exactly as the web app renders it', () {
      // ₹2,00,00,000 @ 7.25% p.a., EMI ₹1,37,000.
      //   r  = 0.0725 / 12          = 0.00604166…
      //   P·r                        = 1,20,833.33
      //   n  = ceil(2.137029 / 0.00602348) = ceil(354.77) = 355
      //   paid = 1,37,000 × 355      = 4,86,35,000
      //   interest = 4,86,35,000 − 2,00,00,000 = 2,86,35,000
      final schedule = amortiseReducingBalance(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
      );

      expect(schedule.feasible, isTrue);
      expect(schedule.months, 355);
      expect(formatMonths(schedule.months), '29 yr 7 mo');
      expect(schedule.totalPaid, 48635000);
      expect(schedule.totalInterest, 28635000);
    });

    test('₹1,00,000 @ 12% with a ₹10,000 EMI clears in 11 months', () {
      // r = 0.01, P·r = 1,000, n = ceil(−ln(0.9)/ln(1.01)) = ceil(10.59) = 11.
      final schedule = amortiseReducingBalance(
        outstanding: 100000,
        annualRatePct: 12,
        emi: 10000,
      );

      expect(schedule.months, 11);
      expect(schedule.totalPaid, 110000);
      expect(schedule.totalInterest, 10000);
    });

    test('a zero rate is plain division, with no interest', () {
      final schedule = amortiseReducingBalance(
        outstanding: 50000,
        annualRatePct: 0,
        emi: 10000,
      );

      expect(schedule.feasible, isTrue);
      expect(schedule.months, 5);
      expect(schedule.totalInterest, 0);
      // The last month is partial, and it still counts as a whole month.
      expect(
        amortiseReducingBalance(
          outstanding: 50001,
          annualRatePct: 0,
          emi: 10000,
        ).months,
        6,
      );
    });

    test('an EMI that cannot cover the monthly interest is infeasible', () {
      // ₹2,00,00,000 @ 7.25% accrues ₹1,20,833/month; a ₹1,00,000 EMI leaves
      // the balance growing forever.
      final schedule = amortiseReducingBalance(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 100000,
      );

      expect(schedule.feasible, isFalse);
    });

    test('an EMI exactly equal to the monthly interest is infeasible', () {
      // ₹1,20,000 @ 12% accrues exactly ₹1,200 — every rupee is interest.
      final schedule = amortiseReducingBalance(
        outstanding: 120000,
        annualRatePct: 12,
        emi: 1200,
      );

      expect(schedule.feasible, isFalse);
    });

    test('no EMI is infeasible; nothing outstanding is already paid off', () {
      expect(
        amortiseReducingBalance(
          outstanding: 10000,
          annualRatePct: 10,
          emi: 0,
        ).feasible,
        isFalse,
      );

      final cleared = amortiseReducingBalance(
        outstanding: 0,
        annualRatePct: 10,
        emi: 5000,
      );
      expect(cleared.feasible, isTrue);
      expect(cleared.isPaidOff, isTrue);
      expect(cleared.totalInterest, 0);
    });

    test('simulation agrees — month by month lands on the same term', () {
      // The independent check on the closed form: run the actual schedule.
      int simulate(num balance, num annualPct, num emi) {
        final r = annualPct / 12 / 100;
        var remaining = balance;
        var months = 0;
        while (remaining > 0 && months < 10000) {
          remaining = remaining + remaining * r - emi;
          months++;
        }
        return months;
      }

      for (final scenario in const [
        [100000, 12, 10000],
        [500000, 9.5, 7500],
        [20000000, 7.25, 137000],
        [250000, 14, 25000],
      ]) {
        final schedule = amortiseReducingBalance(
          outstanding: scenario[0],
          annualRatePct: scenario[1],
          emi: scenario[2],
        );
        expect(
          schedule.months,
          simulate(scenario[0], scenario[1], scenario[2]),
          reason: 'closed form disagrees with the simulation for $scenario',
        );
      }
    });
  });

  group('prepaymentCharge', () {
    test('is a percentage of the amount prepaid, to the rupee', () {
      expect(prepaymentCharge(500000, 2), 10000);
      expect(prepaymentCharge(123456, 2.5), 3086); // 3086.4 -> 3086
      expect(prepaymentCharge(500000, 0), 0);
      expect(prepaymentCharge(0, 4), 0);
      // Nonsense inputs cost nothing rather than paying the borrower.
      expect(prepaymentCharge(-500000, 2), 0);
      expect(prepaymentCharge(500000, -2), 0);
    });
  });

  group('planPrepayment', () {
    test('an extra ₹10,000 a month takes 68 months off the live loan', () {
      // With plan: ₹2,00,00,000 @ 7.25%, EMI ₹1,47,000 -> 287 months,
      // interest ₹2,21,89,000. Saved: 355 − 287 = 68 months and
      // ₹2,86,35,000 − ₹2,21,89,000 = ₹64,46,000. No lump sum, so no charge.
      final plan = planPrepayment(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
        extraPerMonth: 10000,
      );

      expect(plan.base.months, 355);
      expect(plan.withPlan.months, 287);
      expect(plan.monthsSaved, 68);
      expect(plan.interestSaved, 6446000);
      expect(plan.charge, 0);
      expect(plan.netBenefit, 6446000);
      expect(plan.isWorthIt, isTrue);
      expect(plan.chargeOutweighsSaving, isFalse);
    });

    test('a ₹5,00,000 lump sum at 0% charge saves 28 months', () {
      // With plan: ₹1,95,00,000 @ 7.25%, EMI ₹1,37,000 -> 327 months,
      // interest ₹2,52,99,000. Saved: 28 months, ₹33,36,000.
      final plan = planPrepayment(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
        lumpSum: 500000,
      );

      expect(plan.withPlan.months, 327);
      expect(plan.monthsSaved, 28);
      expect(plan.interestSaved, 3336000);
      expect(plan.netBenefit, 3336000);
    });

    test('both levers together compound', () {
      // ₹1,95,00,000 @ 7.25% at ₹1,47,000 -> 269 months, interest
      // ₹2,00,43,000. Saved 86 months and ₹85,92,000; the 2% charge on the
      // ₹5,00,000 lump sum costs ₹10,000.
      final plan = planPrepayment(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 137000,
        extraPerMonth: 10000,
        lumpSum: 500000,
        chargePct: 2,
      );

      expect(plan.withPlan.months, 269);
      expect(plan.monthsSaved, 86);
      expect(plan.interestSaved, 8592000);
      expect(plan.charge, 10000);
      expect(plan.netBenefit, 8582000);
    });

    test('a charge that outweighs the saving gives a negative net benefit', () {
      // The case the planner exists to catch: a cheap loan near its end, and a
      // lender that charges to close it early. ₹5,00,000 @ 4% p.a. with a
      // ₹25,000 EMI runs 21 months and costs ₹25,000 of interest…
      final base = amortiseReducingBalance(
        outstanding: 500000,
        annualRatePct: 4,
        emi: 25000,
      );
      expect(base.months, 21);
      expect(base.totalInterest, 25000);

      // …so a 6% foreclosure fee (5% + GST, typical on a car loan) costs
      // ₹30,000 to avoid ₹25,000 of interest. Prepaying loses ₹5,000.
      final plan = planPrepayment(
        outstanding: 500000,
        annualRatePct: 4,
        emi: 25000,
        lumpSum: 500000,
        chargePct: 6,
      );

      expect(plan.withPlan.isPaidOff, isTrue);
      expect(plan.charge, 30000);
      expect(plan.interestSaved, 25000);
      expect(plan.netBenefit, -5000);
      expect(plan.isWorthIt, isFalse);
      expect(plan.chargeOutweighsSaving, isTrue);
    });

    test('a lump sum bigger than the balance is capped, and so is its fee', () {
      final plan = planPrepayment(
        outstanding: 100000,
        annualRatePct: 8,
        emi: 10000,
        lumpSum: 500000,
        chargePct: 2,
      );

      expect(plan.lumpSum, 100000);
      // 2% of the balance, not 2% of what was typed.
      expect(plan.charge, 2000);
      expect(plan.withPlan.isPaidOff, isTrue);
    });

    test('nothing is saved when the base loan never amortises', () {
      // The EMI cannot cover the interest, so there is no "before" to improve
      // on — the planner reports zero rather than an invented saving.
      final plan = planPrepayment(
        outstanding: 20000000,
        annualRatePct: 7.25,
        emi: 100000,
        extraPerMonth: 1000,
      );

      expect(plan.base.feasible, isFalse);
      expect(plan.monthsSaved, 0);
      expect(plan.interestSaved, 0);
      expect(plan.netBenefit, 0);
    });

    test('an empty plan is a no-op', () {
      final plan = planPrepayment(
        outstanding: 100000,
        annualRatePct: 12,
        emi: 10000,
      );

      expect(plan.hasPlan, isFalse);
      expect(plan.monthsSaved, 0);
      expect(plan.interestSaved, 0);
      expect(plan.netBenefit, 0);
    });
  });

  group('formatMonths', () {
    test('reads as years and months', () {
      expect(formatMonths(355), '29 yr 7 mo');
      expect(formatMonths(12), '1 yr');
      expect(formatMonths(7), '7 mo');
      expect(formatMonths(0), 'Paid off');
      expect(formatMonths(-3), 'Paid off');
    });
  });

  group('payoffDate', () {
    test('counts whole months forward from today', () {
      final schedule = amortiseReducingBalance(
        outstanding: 100000,
        annualRatePct: 12,
        emi: 10000,
      );
      final date = payoffDate(schedule)!;
      final expected = DateTime.now();

      // 11 months out: the month index must line up, whatever today is.
      expect(
        date.year * 12 + date.month,
        expected.year * 12 + expected.month + 11,
      );
    });

    test('an infeasible schedule has no payoff date', () {
      expect(payoffDate(const LoanSchedule.infeasible()), isNull);
      expect(payoffEtaLabel(const LoanSchedule.infeasible()), isNull);
    });
  });

  group('LoansSummary', () {
    Loan loan({
      required String id,
      required num outstanding,
      num principal = 0,
      num roi = 0,
      num emi = 0,
      LoanStatus status = LoanStatus.active,
    }) => Loan(
      id: id,
      name: id,
      outstanding: outstanding,
      principal: principal,
      roi: roi,
      emi: emi,
      status: status,
    );

    test('totals the live loan the way the web overview does', () {
      final summary = LoansSummary.of([
        loan(
          id: 'Deena',
          outstanding: 20000000,
          principal: 20000000,
          roi: 7.25,
          emi: 137000,
        ),
      ]);

      expect(summary.totalOutstanding, 20000000);
      expect(summary.totalEmi, 137000);
      expect(summary.interestRemaining, 28635000);
      expect(summary.repaidPct, 0);
      expect(summary.weightedRoi, 7.25);
      expect(summary.anyInfeasible, isFalse);
    });

    test('a loan saved without a rate is left out of the average', () {
      // roi defaults to 0 when the field is left blank. Averaging that in as
      // "0%" drags the portfolio rate towards zero in proportion to the
      // unrated balance — here it would read 3.63%, not 7.25%.
      final summary = LoansSummary.of([
        loan(id: 'rated', outstanding: 20000000, roi: 7.25, emi: 137000),
        loan(id: 'unrated', outstanding: 20000000, emi: 50000),
      ]);

      expect(summary.weightedRoi, 7.25);
      expect(summary.totalOutstanding, 40000000);
    });

    test('no rate anywhere leaves the average unknown, not zero', () {
      final summary = LoansSummary.of([
        loan(id: 'a', outstanding: 500000, emi: 10000),
      ]);

      expect(summary.weightedRoi, isNull);
    });

    test('the average rate is weighted by balance, not by loan count', () {
      // ₹2,00,00,000 @ 7.25% and ₹1,00,000 @ 14% is a 7.28% portfolio — a
      // plain mean would call it 10.625%.
      final summary = LoansSummary.of([
        loan(id: 'big', outstanding: 20000000, roi: 7.25, emi: 137000),
        loan(id: 'small', outstanding: 100000, roi: 14, emi: 10000),
      ]);

      expect(summary.weightedRoi, closeTo(7.2836, 0.0005));
    });

    test('% repaid ignores loans with no original amount recorded', () {
      // Without the guard, the ₹50,000 loan with no principal would count as
      // fully repaid and flatter the figure.
      final summary = LoansSummary.of([
        loan(id: 'tracked', outstanding: 400000, principal: 1000000),
        loan(id: 'untracked', outstanding: 50000),
      ]);

      expect(summary.totalPrincipal, 1000000);
      expect(summary.repaid, 600000);
      expect(summary.repaidPct, 60);
      // The untracked balance still counts as money owed.
      expect(summary.totalOutstanding, 450000);
    });

    test('an unservicable EMI is flagged and left out of the interest', () {
      final summary = LoansSummary.of([
        loan(id: 'stuck', outstanding: 20000000, roi: 7.25, emi: 100000),
      ]);

      expect(summary.anyInfeasible, isTrue);
      expect(summary.interestRemaining, 0);
    });

    test('no loans means no figures to report', () {
      final summary = LoansSummary.of(const []);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalOutstanding, 0);
      expect(summary.repaidPct, isNull);
      expect(summary.weightedRoi, isNull);
    });
  });

  group('Loan.monthsRemaining agrees with the amortisation', () {
    test('the model and the planner cannot drift apart', () {
      const deena = Loan(
        id: 'l1',
        name: 'Deena',
        outstanding: 20000000,
        roi: 7.25,
        emi: 137000,
      );

      expect(deena.monthsRemaining, 355);
      expect(scheduleFor(deena).months, deena.monthsRemaining);

      const stuck = Loan(
        id: 'l2',
        name: 'Stuck',
        outstanding: 20000000,
        roi: 7.25,
        emi: 100000,
      );

      expect(stuck.monthsRemaining, isNull);
      expect(scheduleFor(stuck).feasible, isFalse);
    });
  });
}
