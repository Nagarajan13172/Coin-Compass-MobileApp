# Phase 4 — Wealth & assets: gate report

**Status: complete.** `flutter analyze` clean · 221 tests passing · debug APK
built and walked on the device (CPH2569, Android 15).

## Shipped

| Screen | Route | Notes |
|---|---|---|
| Net Worth | `/net-worth` | Overview / Assets / Liabilities, 1M·3M·1Y·All series |
| Holdings | `/net-worth/holdings` | ShellRoute sub-route — `destinations.dart` is exactly 17 |
| Loans | `/loans` | Card actions: Planner · Part payment · Preclose |
| Stocks | `/stocks` | Buy / sell / splits; demat-account precondition surfaced |
| Gold & Silver | `/gold` | Latest + history chart per metal, city & purity |

13 of 17 screens are now live. The four remaining placeholders — `/reports`,
`/insights`, `/notifications`, `/settings` — are Phase 5.

## Gate criteria

1. **Analyze / tests / build** — clean, 221 passing, APK builds.
2. **Loan figures match the web app** — verified on device against the real
   ₹2,00,00,000 loan: `29 yr 7 mo`, `ETA March 2056`, `EMI ₹1.37L`, `7.25% p.a.`,
   `interest left ~₹2.86Cr`. Preclose sheet states `₹2,86,35,000` exactly.
3. **Every write body audited** — the schema guard now covers 15 bodies
   (`/accounts`, `/transactions`, `/recurring` were added; they were correct but
   unguarded). Negative-tested: reintroducing `openingBalance` fails the suite.
4. **Empty and negative paths** — net worth renders −₹2Cr with a real
   explanation rather than a blank; stocks detects the missing demat account and
   routes to Accounts; holdings/stocks read "none yet", not "₹0".
5. **Preclose cannot fire from a stray tap** — three gates: an explicit button,
   a sheet showing the full payable breakdown, then a `ConfirmSheet` naming the
   loan and the amount. Never exercised against the live loan.
6. **Deployed and walked** — logcat clean across 10,859 lines: no `RenderFlex`,
   no `E/flutter`, no `FATAL`.

## Review findings fixed

30 claims raised across 5 adversarial lenses, 12 confirmed. Fixed:

| Sev | What | Where |
|---|---|---|
| major | Part payment previewed a clamped amount but **submitted the raw typed one** — ₹3Cr on a ₹2Cr loan posted ₹3Cr | `loan_pay_sheet.dart` |
| major | `weightedRoi` divided by total outstanding, so a loan saved without a rate averaged in as 0% | `loans_providers.dart` |
| major | `class` and `subtype` were independent selects — `{saving, stocks}` writes clean and files under the wrong half | `enums.dart`, `holding_form_sheet.dart` |
| major | Changing the Net Worth range blanked hero, totals and the pills themselves | `net_worth_screen.dart` |
| major | Metals history error card overflowed a fixed 240dp box, hiding Retry | `metal_history_chart.dart` |
| minor | `MoneyText(signed: true)` dropped the `+` in its compact branch | `money.dart`, `money_text.dart` |
| minor | Loan card caption truncated the year (`ETA September 2056`) | `loan_card.dart` |
| minor | Net worth y-axis wrapped `Cr` onto its own line | `net_worth_chart.dart` |

## Not a bug — do not "fix"

The reviewer flagged `amortiseReducingBalance` as a blocker: it charges a full
EMI for the final partial instalment, overstating interest by up to one EMI
against a textbook schedule. **That is deliberate** — it is what the CoinCompass
web app does, and parity beats textbook precision here. The web shows
₹2,86,35,000 (355 × ₹1,37,000 − ₹2,00,00,000); the exact fractional term gives
₹2,85,55,231, which the web never displays. Pinned by
`test/loan_ground_truth_test.dart` and now documented at the call site.

## Still unverified

The **prepayment planner** has only been checked for internal consistency, not
against the web app's own planner. At `+₹10,000/mo` the app projects 23 yr 11 mo
· July 2050 · ~₹2.22Cr interest · ₹64,46,000 saved — arithmetically correct for
the shared formula (287 months), but the web's planner output has not been
diffed. Run the same inputs there before trusting it for a real decision.

`fees` on `/stocks/buy` and `/stocks/sell`: the deployed web client sends it, but
it is in neither column of `WRITE_SCHEMAS.md` and was never probed. Not sent.
Re-probe before adding a brokerage input — both are CREATE endpoints, so it is
safe.
