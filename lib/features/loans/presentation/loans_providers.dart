import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/enums.dart';
import '../../../core/utils/date_x.dart';
import '../data/loans_repository.dart';
import '../domain/loan.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Loan maths
//
// Everything below is pure — no Flutter, no Riverpod, no I/O — so it is unit
// tested directly in test/loan_math_test.dart.
//
// The model is a **standard reducing-balance (annuity) loan**:
//
//   * interest accrues monthly on the outstanding balance at `roi / 12 / 100`;
//   * a fixed EMI is paid at the end of every month; whatever is left after the
//     month's interest reduces the principal;
//   * the loan closes on the first month the balance reaches zero, so the term
//     is rounded **up** to a whole month (the last EMI is normally smaller in
//     real life — this treats it as a full one, which is the conservative
//     reading and is what the CoinCompass web app does).
//
// Closed form for the remaining term:
//
//   n = ceil( −ln(1 − P·r / E) / ln(1 + r) )
//
// where P = outstanding, r = monthly rate, E = EMI. It has no solution when
// E ≤ P·r — the EMI cannot even cover one month's interest, so the balance
// never falls. That case is reported as `feasible: false` rather than as a
// huge number, and the UI says "EMI too low".
//
// Total interest is `E·n − P`: every rupee paid beyond the balance is interest.
//
// Assumptions, stated plainly because they are what make the figures estimates:
//   * the rate never changes (no floating-rate resets);
//   * payments are monthly, on time, and never skipped;
//   * no fees, insurance or GST are folded into the EMI;
//   * a prepayment reduces the tenure, not the EMI — the standard Indian bank
//     default, and the only assumption under which "months saved" is meaningful.
//
// Cross-check: for the live loan (₹2,00,00,000 @ 7.25%, EMI ₹1,37,000) this
// returns 355 months and ₹2,86,35,000 of interest, which is exactly what the
// deployed web app renders ("29 yr 7 mo left · ETA Mar 2056", "Interest
// remaining ~₹2,86,35,000"). See the report note in test/loan_math_test.dart.
// ═══════════════════════════════════════════════════════════════════════════

/// The outcome of amortising a balance at a fixed EMI.
@immutable
class LoanSchedule {
  const LoanSchedule({
    required this.feasible,
    required this.months,
    required this.totalPaid,
    required this.totalInterest,
  });

  /// A balance that can never be cleared at this EMI and rate.
  const LoanSchedule.infeasible()
    : feasible = false,
      months = 0,
      totalPaid = 0,
      totalInterest = 0;

  /// False when the EMI does not cover the monthly interest (or is zero).
  /// [months], [totalPaid] and [totalInterest] are meaningless when false.
  final bool feasible;

  /// Whole months until the balance reaches zero. 0 means already paid off.
  final int months;

  /// EMI × [months] — what leaves the borrower's pocket from here on.
  final num totalPaid;

  /// [totalPaid] less the balance being cleared.
  final num totalInterest;

  bool get isPaidOff => feasible && months == 0;
}

/// Amortises [outstanding] at [annualRatePct] p.a. paying [emi] every month.
///
/// See the header comment for the model and its assumptions. A zero or negative
/// rate degrades to simple division (no interest ever accrues).
LoanSchedule amortiseReducingBalance({
  required num outstanding,
  required num annualRatePct,
  required num emi,
}) {
  final balance = outstanding <= 0 ? 0 : outstanding;
  if (balance == 0) {
    return const LoanSchedule(
      feasible: true,
      months: 0,
      totalPaid: 0,
      totalInterest: 0,
    );
  }
  if (emi <= 0) return const LoanSchedule.infeasible();

  final r = annualRatePct / 12 / 100;
  if (r <= 0) {
    // Interest-free: every rupee of the EMI reduces the principal.
    final months = (balance / emi).ceil();
    return LoanSchedule(
      feasible: true,
      months: months,
      totalPaid: balance,
      totalInterest: 0,
    );
  }

  // The EMI must beat one month's interest, or the balance grows forever.
  if (emi <= balance * r) return const LoanSchedule.infeasible();

  final exact = -math.log(1 - balance * r / emi) / math.log(1 + r);
  // Rounding noise on a knife-edge EMI can produce a term of a few million
  // months. Anything past a century is not a loan any more, and `.ceil()` on a
  // non-finite double throws, so both are reported as "EMI too low".
  if (!exact.isFinite || exact <= 0 || exact > 1200) {
    return const LoanSchedule.infeasible();
  }
  final months = exact.ceil();
  // `totalPaid` charges a FULL EMI for the final, partial instalment. That
  // overstates interest by up to one EMI versus a textbook schedule — and it
  // is deliberate: it is what the CoinCompass web app does, and parity with
  // the web figure beats textbook precision here. For the real ₹2,00,00,000
  // loan the web shows ₹2,86,35,000 (= 355 × ₹1,37,000 − ₹2,00,00,000); the
  // exact fractional term gives ₹2,85,55,231, which the web never displays.
  // `test/loan_ground_truth_test.dart` pins both numbers. Do not "fix" this
  // without changing the web app first.
  final totalPaid = emi * months;
  return LoanSchedule(
    feasible: true,
    months: months,
    totalPaid: totalPaid,
    totalInterest: math.max(0, totalPaid - balance),
  );
}

/// Convenience wrapper: [loan]'s own outstanding, rate and EMI.
LoanSchedule scheduleFor(Loan loan) => amortiseReducingBalance(
  outstanding: loan.outstanding,
  annualRatePct: loan.roi,
  emi: loan.emi,
);

/// The lender's prepayment / foreclosure fee: a percentage of the amount being
/// prepaid, rounded to the rupee. Lenders may add GST on top of this — the
/// planner says so rather than guessing at it.
num prepaymentCharge(num amount, num chargePct) {
  if (amount <= 0 || chargePct <= 0) return 0;
  return (amount * (chargePct / 100)).round();
}

/// What an early-payoff plan actually buys.
@immutable
class PrepaymentPlan {
  const PrepaymentPlan({
    required this.base,
    required this.withPlan,
    required this.extraPerMonth,
    required this.lumpSum,
    required this.chargePct,
    required this.charge,
    required this.monthsSaved,
    required this.interestSaved,
  });

  /// The loan left alone.
  final LoanSchedule base;

  /// The loan after the lump sum, paying EMI + [extraPerMonth].
  final LoanSchedule withPlan;

  final num extraPerMonth;
  final num lumpSum;
  final num chargePct;

  /// The fee on the lump sum only — extra EMI is never charged for.
  final num charge;

  /// Months knocked off the term. 0 when either schedule is infeasible.
  final int monthsSaved;

  /// Interest avoided, never negative.
  final num interestSaved;

  /// Interest saved less the fee paid to save it. **Can be negative** — a 4%
  /// fee on a large lump sum can cost more than the interest it avoids, and
  /// the planner says so in words rather than showing a bare minus sign.
  num get netBenefit => interestSaved - charge;

  bool get isWorthIt => netBenefit > 0;

  /// True when a fee was paid and it did not pay for itself.
  bool get chargeOutweighsSaving => charge > 0 && netBenefit <= 0;

  bool get hasPlan => extraPerMonth > 0 || lumpSum > 0;
}

/// Models paying [lumpSum] today (attracting [chargePct] of it as a fee) and
/// [extraPerMonth] on top of every future EMI.
///
/// Both legs are amortised with the same function, so "interest saved" is the
/// difference between two schedules computed identically — not a shortcut
/// formula that could drift from the payoff dates shown beside it.
PrepaymentPlan planPrepayment({
  required num outstanding,
  required num annualRatePct,
  required num emi,
  num extraPerMonth = 0,
  num lumpSum = 0,
  num chargePct = 0,
}) {
  final extra = extraPerMonth <= 0 ? 0 : extraPerMonth;
  // A lump sum bigger than the balance just closes the loan; charging a fee on
  // more than is owed would overstate the cost.
  final lump = lumpSum <= 0 ? 0 : math.min(lumpSum, math.max(0, outstanding));
  final pct = chargePct <= 0 ? 0 : chargePct;

  final base = amortiseReducingBalance(
    outstanding: outstanding,
    annualRatePct: annualRatePct,
    emi: emi,
  );
  final boosted = amortiseReducingBalance(
    outstanding: math.max(0, outstanding - lump),
    annualRatePct: annualRatePct,
    emi: emi + extra,
  );

  final comparable = base.feasible && boosted.feasible;
  return PrepaymentPlan(
    base: base,
    withPlan: boosted,
    extraPerMonth: extra,
    lumpSum: lump,
    chargePct: pct,
    charge: prepaymentCharge(lump, pct),
    monthsSaved: comparable ? math.max(0, base.months - boosted.months) : 0,
    interestSaved: comparable
        ? math.max(0, base.totalInterest - boosted.totalInterest)
        : 0,
  );
}

/// `355` -> `29 yr 7 mo`, `7` -> `7 mo`, `0` -> `Paid off`.
String formatMonths(int months) {
  if (months <= 0) return 'Paid off';
  final years = months ~/ 12;
  final rest = months % 12;
  final parts = [if (years > 0) '$years yr', if (rest > 0) '$rest mo'];
  return parts.isEmpty ? '0 mo' : parts.join(' ');
}

/// The month the balance clears, counting from today. Null when it never does.
DateTime? payoffDate(LoanSchedule schedule) {
  if (!schedule.feasible || schedule.months <= 0) return null;
  return DateTime.now().addMonths(schedule.months);
}

/// `March 2056` — the ETA shown beside a remaining term.
String? payoffEtaLabel(LoanSchedule schedule) {
  final date = payoffDate(schedule);
  return date == null ? null : DateX.monthLabel(date);
}

// ═══════════════════════════════════════════════════════════════════════════
// Screen state
// ═══════════════════════════════════════════════════════════════════════════

/// Portfolio-level figures for the loans a borrower still owes on.
@immutable
class LoansSummary {
  const LoansSummary({
    required this.count,
    required this.totalOutstanding,
    required this.totalEmi,
    required this.totalPrincipal,
    required this.repaid,
    required this.interestRemaining,
    required this.weightedRoi,
    required this.anyInfeasible,
  });

  /// Built from **active** loans only — a closed loan owes nothing and its EMI
  /// is no longer leaving the account.
  factory LoansSummary.of(List<Loan> active) {
    num outstanding = 0;
    num emi = 0;
    num principal = 0;
    num outstandingWithPrincipal = 0;
    num interest = 0;
    num roiWeight = 0;
    num outstandingWithRoi = 0;
    var infeasible = false;

    for (final loan in active) {
      outstanding += loan.outstanding;
      emi += loan.emi;
      // A loan with no original amount recorded cannot contribute to "% repaid"
      // — counting its outstanding against a zero principal would read as 100%
      // repaid. Both sides of that ratio skip it.
      if (loan.principal > 0) {
        principal += loan.principal;
        outstandingWithPrincipal += loan.outstanding;
      }
      final schedule = scheduleFor(loan);
      if (schedule.feasible) {
        interest += schedule.totalInterest;
      } else if (loan.outstanding > 0) {
        infeasible = true;
      }
      // Same rule as principal above: a loan saved without a rate must not be
      // averaged in as 0%, or one unrated balance drags the whole portfolio
      // rate towards zero. It leaves both sides of the ratio.
      if (loan.roi > 0) {
        roiWeight += loan.outstanding * loan.roi;
        outstandingWithRoi += loan.outstanding;
      }
    }

    return LoansSummary(
      count: active.length,
      totalOutstanding: outstanding,
      totalEmi: emi,
      totalPrincipal: principal,
      repaid: math.max(0, principal - outstandingWithPrincipal),
      interestRemaining: interest,
      // Weighted by balance: a ₹2Cr loan at 7.25% and a ₹1L loan at 14% is a
      // 7.28% portfolio, not a 10.6% one.
      weightedRoi: outstandingWithRoi > 0
          ? roiWeight / outstandingWithRoi
          : null,
      anyInfeasible: infeasible,
    );
  }

  final int count;
  final num totalOutstanding;
  final num totalEmi;

  /// Original amounts, counting only loans that recorded one.
  final num totalPrincipal;

  /// Principal cleared so far, across the same loans as [totalPrincipal].
  final num repaid;

  /// Whole-percent share of the original borrowing already repaid. Null when
  /// no active loan recorded an original amount to measure against.
  int? get repaidPct =>
      totalPrincipal > 0 ? (repaid / totalPrincipal * 100).round() : null;

  /// Interest still to be paid across every feasible active loan.
  final num interestRemaining;

  /// Balance-weighted average rate, null when nothing is outstanding.
  final double? weightedRoi;

  /// At least one active loan's EMI cannot service its interest, so
  /// [interestRemaining] understates the truth.
  final bool anyInfeasible;

  bool get isEmpty => count == 0;
}

/// Which tab the loans screen is showing. Survives sheet round-trips, which is
/// why it is a provider rather than local widget state.
final loansTabProvider = StateProvider<LoanStatus>((ref) => LoanStatus.active);

/// Active loans, biggest balance first — the order the summary bars use too.
final activeLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansProvider).valueOrNull ?? const <Loan>[];
  final active = loans.where((loan) => loan.isActive).toList()
    ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
  return active;
});

/// Closed loans, most recently updated first.
final closedLoansProvider = Provider<List<Loan>>((ref) {
  final loans = ref.watch(loansProvider).valueOrNull ?? const <Loan>[];
  final closed = loans.where((loan) => !loan.isActive).toList()
    ..sort(
      (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.updatedAt ?? a.createdAt ?? DateTime(0),
      ),
    );
  return closed;
});

final loansSummaryProvider = Provider<LoansSummary>(
  (ref) => LoansSummary.of(ref.watch(activeLoansProvider)),
);

/// The prepayment / foreclosure fee lenders typically charge for each kind of
/// loan, used to prefill the form and the two action sheets.
///
/// Recovered from the deployed web bundle. Floating-rate home, personal and
/// education loans are 0% by RBI rule; the rest are the lender's own schedule,
/// so they are a starting point the user is expected to correct.
const Map<LoanType, num> typicalChargePct = {
  LoanType.home: 0,
  LoanType.personal: 0,
  LoanType.car: 5,
  LoanType.education: 0,
  LoanType.gold: 1,
  LoanType.business: 4,
  LoanType.other: 2,
};
