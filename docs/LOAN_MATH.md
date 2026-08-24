# Loan maths — validated against the deployed web app

Do NOT invent an amortisation formula. The one below reproduces the web app's figures exactly
for the owner's real loan; the Flutter implementation must match it, and the unit tests must
assert these numbers.

## Ground truth (captured from https://coincompass.sathishkumar.cloud/loans)

Loan "Deena" / UCO — home, outstanding ₹2,00,00,000, ROI 7.25% p.a., EMI ₹1,37,000.

The web app renders:

```
Total outstanding    ₹2,00,00,000      0% repaid of ₹2Cr borrowed
Monthly EMI          ₹1,37,000         Total across 1 active loan
Interest remaining   ~₹2,86,35,000     At current EMIs & rates
Payoff progress      29 yr 7 mo left · ETA Mar 2056
```

## The formula (reproduces every figure above)

Reducing balance, monthly compounding.

```
r  = annualRatePercent / 100 / 12          // 7.25 -> 0.00604166…
n  = ceil( -ln(1 - outstanding·r / emi) / ln(1 + r) )
interestRemaining = n · emi − outstanding
eta = today + n months
```

Verified:

| Quantity | Computed | Web app |
|---|---|---|
| months (exact) | 354.7827 | — |
| months (ceil) | **355** = 29 yr 7 mo | 29 yr 7 mo ✓ |
| interest remaining | **₹2,86,35,000** | ~₹2,86,35,000 ✓ |
| ETA (from Aug 2026) | **Mar 2056** | Mar 2056 ✓ |

Note `n` is **ceil**-ed, and `interestRemaining` is derived from the ceil-ed `n` — not from the
exact fractional value. Using the exact value gives ₹2,85,55,231, which does NOT match the web
app. This detail matters.

## Edge cases the implementation must handle

| Case | Required behaviour |
|---|---|
| `emi <= outstanding · r` | The EMI cannot even service the interest — the loan never amortises. Return null and render "EMI too low". Do not return infinity or loop. |
| `r == 0` (interest-free) | `n = ceil(outstanding / emi)`; `interestRemaining = 0`. The log formula divides by zero here. |
| `emi <= 0` or `outstanding <= 0` | Return null; render nothing rather than a bogus figure. |
| `outstanding` already 0 | Loan is settled — 0 months, 0 interest. |

`Loan.monthsRemaining` in `lib/features/loans/domain/loan.dart` already implements the log
formula and the EMI-too-low guard. Reuse it; do not write a second copy.

## Prepayment planner — still unverified

The planner's own numbers (extra-per-month, lump sum, prepayment charge, net benefit) could NOT
be recovered from the web bundle. Build them on the same reducing-balance basis:

```
withPlan.n         recompute n with (outstanding − lumpSum) and (emi + extraPerMonth)
interestSaved      interestRemaining(current) − interestRemaining(withPlan)
charge             lumpSum · prepaymentChargePct / 100
netBenefit         interestSaved − charge          // CAN BE NEGATIVE — say so plainly
monthsSaved        n(current) − n(withPlan)
```

Flag these as unverified in the UI copy or the report until compared against the web app's
planner side by side. The base figures above ARE verified; the planner deltas are not.
