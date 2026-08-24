# Loan planner — web parity verification

**Method.** Not a screenshot comparison. The web app's own `Ma` (amortisation),
`wm` (prepayment charge) and `us` (tenure formatter) were extracted verbatim from
`assets/index-BCZVpAqp.js` — the bundle the live site serves today — by
brace-matching rather than retyping, then executed under Node v24. The Dart
planner was run over the identical 20-scenario matrix. The two outputs were
diffed field by field, then every claimed difference was put to independent
refutation agents.

**Result: 19 of 20 scenarios match to the rupee**, including the owner's real
loan. 47 agents, 0 errors.

## The real loan — verified identical

| Figure | Web (executed) | Mobile |
|---|---|---|
| Base term | 355 mo = 29 yr 7 mo | ✅ |
| Base interest | ₹2,86,35,000 | ✅ |
| With +₹10,000/mo | 287 mo = 23 yr 11 mo | ✅ |
| Interest with plan | ₹2,21,89,000 | ✅ |
| Months saved | 68 = 5 yr 8 mo | ✅ |
| Interest saved / net benefit | ₹64,46,000 | ✅ |

Pinned by `test/loan_ground_truth_test.dart`.

## The one divergence — fixed

`knife-edge`: EMI ₹1,20,834 against monthly interest of ₹1,20,833.33. The loan
does clear, but only after 2011 months. The web quoted **167 yr 7 mo** and
**₹22,29,97,174** of interest; the app said **"EMI too low"** and showed nothing.

Cause: `amortiseReducingBalance` carried an `exact > 1200` bail-out the web has
no equivalent for. Two screens told the owner contradictory things about whether
a loan was payable at all.

Fixed by removing the cap from the **maths** — the app now reproduces the web's
2011 months and both rupee figures exactly — and moving the concern to
**presentation**: `LoanSchedule.isImplausible` flags a term past 100 years, and
the card renders `100 yr+` with the caption *"EMI barely covers the interest"*
instead of quoting a 167-year mortgage deadpan. Neither app lies; the arithmetic
agrees. Only `!exact.isFinite` remains as a guard, because `.ceil()` on a
non-finite double throws in Dart (JS has no such hazard).

## Other confirmed findings — fixed

- **Planner verdict panel gated too loosely.** The web shows it only when the
  plan achieves something: `(lump>0||extra>0) && (monthsSaved>0||interestSaved>0)`.
  Mobile gated on `hasPlan` alone, so typing an extra ₹5 against a ₹2Cr balance
  printed a "does not shorten the term" verdict with four zeroes under it. Gate
  now matches the web exactly.
- **Loan card compacted figures the web states in full.** `₹1.37L` where the web
  shows `₹1,37,000`, and `₹2Cr left of ₹2Cr` where the web shows the full
  balances. These are balances, not axis labels — restored to `Money.format`.

## Confirmed but deferred

Held back only to avoid editing `lib/core/` while the Phase 5 agents are running.
All three are real:

1. **`AmountInputFormatter` rejects a pasted separator.** Copying `50,00,000` out
   of the web app and pasting it into the mobile amount box drops the whole
   paste; the web sanitises it. Affects the real loan.
2. **Percent fields reuse the money formatter** and cap at 2 decimals, so typing
   `2.125` silently becomes `2.12` with the keystroke swallowed.
3. **`Money.compact` picks its magnitude bucket before rounding**, so ₹99,99,999
   renders `₹100L` where the web renders `₹1Cr`.

## Settled for good

The reviewer's "blocker" from Phase 4 — that `amortiseReducingBalance` charges a
full EMI for the final partial instalment — is **confirmed correct behaviour**.
The web's `Ma` contains `Math.ceil` in exactly the same place. Same algorithm,
not a bug tolerated on a hunch.

`weightedRoi` has **no web counterpart at all**: the web's loans summary computes
only totalOutstanding, totalEmi, totalPrincipal, interestRemaining, repaid and
repaidPct. The "Avg rate · weighted by balance" tile is a mobile-only addition,
so excluding unrated loans from it is our design decision, not a parity break.
