# Phase 7.8 — Scan and pay from the nav bar, with the amount in the payment app

Three things, and the middle one is the reason the other two are worth having:

1. **The pre-filled amount is back.** Scanning a shop's code opens Google Pay,
   PhonePe or Paytm on a payment that already has the payee, the amount and a
   reference in it. The only thing left to do there is approve it.
2. **Scan is a nav-bar slot**, reachable from every screen in the shell.
3. **The payment leaves a ledger row**, prefilled from the code and the
   response, with the owner pressing Save.

## Why the pre-filled amount came back

7.7 gave it up. The reasoning is written out in `PHASE7_7_REPORT.md` and the
observation behind it was real: after the `%40` fix the link was correct, Google
Pay accepted it and reached its PIN screen, and the bank declined ₹1 with *"you
have exceeded the bank limit for this payment"* — while the same QR scanned
inside Google Pay went through.

What that observation supports is **"this PSP, on this account, refused this
link"**. What 7.7 concluded from it was "no intent from this app can carry an
amount", and it removed the feature on the strength of one app's behaviour.
Those are different claims:

- whether a PSP honours a pre-filled intent from an app that is not registered
  with it is **that PSP's policy**, and it differs between Google Pay, PhonePe
  and Paytm, between bank accounts, and over time;
- *"exceeded the bank limit"* is a **generic decline string**. ICICI maps many
  unrelated codes onto it — including the 20-payments-per-day count, which a
  session of repeated ₹1 test payments will reach;
- and the fallback 7.7 shipped instead — open the payee's screen with the amount
  blank — is a strictly *smaller* version of the same intent. If the intent flow
  itself were refused, that would not work either. It does work, which says the
  intent is being accepted and something narrower was refusing the amount.

So the amount goes back into the link, and the app stops guessing on the owner's
behalf about what their bank will accept.

### What is different this time

Not a fourth theory about what a QR contains. Two concrete changes:

**Every link now carries a `tr`.** NPCI's transaction reference is *mandatory
for a merchant payment* and is the field a PSP de-duplicates on; 7.7's links
sent one only when a scanned QR happened to contain one. `UpiRef.generate()`
mints an upper-case alphanumeric reference well inside the 35-character cap, and
`UpiRequest` mints one whenever the caller supplies none — which is also why the
class is no longer `const`. A **merchant's own** `tr` is kept when the QR has
one: a dynamic code carries the invoice number the shop expects to reconcile
against, and inventing a different one settles the payment against nothing. Two
requests never share a reference, because a shared one is worse than none — a
PSP de-duplicating on `tr` reads the second payment to the same shop as a replay
of the first.

**A refusal is met, not surrendered to.** `UpiHandover` makes the three ways of
handing a payment over explicit, and the sheet walks down them **only after an
attempt has actually come back without a payment**:

| rung | what goes to the payment app |
|---|---|
| `prefilled` | payee, amount, currency, reference — the default, and the feature |
| `payeeOnly` | the payee; the amount is typed there |
| `appOnly` | the app's own home screen |

The retry is never offered up front — that would make "the amount could not be
sent" the app's opening statement about something that usually works — and never
after a `SUCCESS` or a `PENDING`, because retrying a payment that may have gone
through is a second payment.

### What is still not knowable from here

Whether any given phone, app and bank will honour rung one. That needs a real
payment on a real account, and no amount of test coverage substitutes for it.
What the tests *do* pin is that the app asks: `am` is in the first link, the
`@` is literal, the reference is unique, and a refusal produces the next rung
rather than a dead end.

## The nav-bar slot

The bottom bar's four slots are what keeps the centre FAB centred — the FAB sits
in the gap between two slots on the left and two on the right, so a fifth would
push it off-centre. Scan therefore had to **replace** something rather than join
it.

It replaced **Reports**, which moved into the More sheet as its **first row**. A
payment is made at a counter, one-handed, with someone waiting; a report is read
sitting down. Reports lost one tap and Scan lost two.

The slot is an action, not a destination: it is never lit, because nothing it
opens is a route.

## The flow, and where it refuses to guess

    scan → confirm the amount → pay in the payment app → record the expense

**The amount step is always shown**, even when the code fixes one. A counter code
usually sets no amount at all, and one that does can still be wrong for what is
actually being bought — so the figure is prefilled, editable, and the sheet says
which of the two it is looking at. It is also the screen that puts the payee
name and the **VPA** together one last time before money moves, which is where
the standard sticker-over-a-shop's-QR fraud is caught.

**The ledger row is prefilled, not saved.** The transaction sheet opens with the
amount, the payee and a note carrying the shop's own note and the UPI reference —
and the owner presses Save. That is not friction for its own sake: an account is
required by the API and a category is worth choosing, and pressing Save is also
the only confirmation this app is entitled to that the payment happened. A UPI
deep-link response is advisory (`UpiResult`), so nothing here writes a row on the
strength of it.

The note deliberately never says **paid**.

**Backing out after the payment still offers the row.** By then the money has
moved, and a payment that leaves no trace because a sheet was dismissed is the
one outcome this must not produce.

On a platform with no UPI intent contract — iOS, web — the flow skips the payment
step and goes straight to the ledger. The scan still read the payee and the
amount off the code, which is most of the typing gone.

## The payee book, finally connected

`UpiPayeeBook` has existed since 7.6 and nothing read it. The pay sheet now
does: a scanned payee's VPA is remembered against their name, so the *second*
payment to the same shop is pre-filled without rescanning. It stays on the phone
— a VPA is the string money follows, and the backend has no field for it.

## Tests

30 new, 1,170 passing, 0 analyzer errors.

- `upi_domain_test.dart` — the reference is always sent, never reused, never
  overwritten when a merchant supplied one.
- `upi_pay_sheet_test.dart` — the first attempt carries `am`; a reported failure
  offers the payee-only rung and the retry really does drop the amount; a
  success or a pending is never offered a retry; silence becomes a question and
  never an assumption; the bottom rung offers nothing below it.
- `upi_scan_pay_test.dart` — the amount step, the note composition, and the
  transaction form arriving filled in.
- `app_navigation_test.dart` — the Scan slot exists, Reports is the first More
  row.

## Not verified

**A real payment.** Nothing here can put a phone in front of a printed code and
a PIN pad. The camera→parse link and the parse→intent link are both covered by
tests; the intent→bank link is the one that needs a shop and a rupee.

The diagnostic from 7.7 is still in place and now logs both directions:

    adb logcat -s flutter | grep UPI

`UPI-QR-IN` is the code as scanned, `UPI-OUT (prefilled)` is the exact link
sent, `UPI-IN` is what came back. Four rounds of 7.7 were spent reasoning about
what was probably being sent; one round with the real string ended it.
