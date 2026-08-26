# Phase 7.7 — Scan a QR, fill the form, pay with the amount prefilled

Scan a shop's UPI QR inside CoinCompass, have it fill the expense, then choose a
payment app that opens with the payee **and the amount** already in it.

## Why this was mostly already built

A UPI QR encodes exactly the link 7.6 already constructs:

    upi://pay?pa=chaikada@okhdfcbank&pn=Chai%20Kada&am=250.00&cu=INR&tn=…

So scanning is the **inverse of `UpiRequest.toUri`**, and the prefilled-amount
path is 7.6's "with a UPI ID" branch, reached with a VPA that came from a camera
instead of a keyboard. What 7.7 adds is the reading, the confirmation, and the
wiring between them.

## A QR is untrusted input

It was printed by someone else, nothing in the format is signed, and a sticker
over a shop's real code is the standard UPI fraud. Three consequences:

**The scan stops and asks.** The camera locks on the first readable code and
shows who it would pay — name *and* VPA, the VPA in monospace so a lookalike
character stands out — for the user to accept. Auto-filling straight from the
camera would let the payee change under the user's thumb between glance and tap.
Further frames are ignored while that confirmation is up.

**The printed name is a label, never a payee.** `pn` is whatever the printer
typed. It is shown verbatim beside the VPA and never used in its place; the VPA
is the only field money follows.

**Only `pa` is strict.** Everything else is lenient, because a real counter QR
is often sloppy and refusing the whole code over a junk `am` would be unhelpful:

| field | handling |
|---|---|
| `pa` | must parse as a `Vpa`, or the code is refused |
| `am` | zero, negative, unreadable or over the UPI ceiling all read as **open** — the user types the amount |
| `pn` | control characters stripped, truncated at 60, falls back to the VPA's account |
| `cu` | anything but INR is **refused** — reading a USD amount as rupees would misstate what was paid |
| `mc` | kept: the one hint that this is a business rather than a person |

## Rejections say what the code actually is

A scanner that silently ignores what it dislikes leaves someone pointing a
camera at a wall wondering whether it is broken. So a Wi-Fi code says *"That is
a Wi-Fi code, not a UPI payment code"*, a link says *"a web link"*, and
`upi://mandate` says *"asks for mandate, which this app cannot do"* rather than
being guessed at — an unknown UPI verb is a guess about money.

## The flow

1. **Scan a UPI QR** on the transaction form — always enabled, because scanning
   is *how* the amount arrives for a merchant code; requiring an amount first
   would put the steps in the wrong order.
2. Confirm what was read.
3. The form fills: payee name, VPA, amount **if the code fixed one**, note if
   the note field is still empty. An open-amount code leaves whatever the user
   already typed alone — overwriting it would be worse than not filling it.
4. **Pay ₹250 with UPI** → the app sheet.
5. The chosen app opens **on a payment screen with payee and amount in it**,
   because a scanned VPA takes 7.6's prefilled branch.

A scanned VPA **wins over a remembered one**: the code in front of the user now
is more current than a VPA saved weeks ago, and a shop can change its handle.

## Verified on hardware

CPH2569, Android 15. **Scan a UPI QR** renders above Pay with UPI and is enabled
at ₹0; tapping it opens the sheet, the camera starts (Android's green camera
indicator lights, and `CAMERA` shows `granted=true`), and closing the sheet
releases the camera — `dumpsys media.camera` reports no open device afterwards.

**Not verified: an actual scan.** Nothing here can point a phone's camera at a
printed code, so the camera→parse link is the one step untested end to end. The
parse itself has 20 tests covering real merchant-QR shapes, open-amount counter
codes, uppercase keys, percent-encoding, control characters, and every rejection
above. The first real scan will confirm the wiring between them.

Also still unverified from 7.6, and now reachable for the first time: whether
each payment app honours a **pre-filled amount** from a third-party caller. That
is per-app policy, it has tightened over the years, and only a real payment
settles it.

## The defect real payments found

Scanning worked. **Paying did not** — every scanned QR came back "payment
failed" or "exceeded for this account", on every phone tried.

The cause was in this app, not in the payment apps. `toUri()` **rebuilt** the
link from the handful of fields the parser understands:

    pa, pn, am, cu, tn

A real merchant QR carries much more: `mc` (merchant category code), `sign` (the
merchant signature on a Bharat/dynamic QR), `orgid`, `mode`, and merchant ids
like `mid`/`msid`. Rebuilding threw all of them away, so what reached the
payment app was a bare **person-to-person transfer to a merchant VPA**. Two
consequences, and they are exactly the two errors reported:

- merchant VPAs commonly **refuse P2P** outright → *"payment failed"*;
- without `mc`, the transaction is metered against **P2P limits** rather than
  merchant ones → *"exceeded for this account"*.

### The fix: replay, never rebuild

`UpiQrPayload` now keeps the scanned string byte for byte, and
`UpiRequest.fromScan` replays it:

| case | what is sent |
|---|---|
| QR fixed the amount, user accepted it | the string **untouched** — not re-encoded, not reordered |
| QR fixed no amount | the string plus `&am=…` (and `&cu=INR` only if absent) |
| user typed a different amount | `am` replaced in place; every other field kept |

The first case matters most: a signed QR's `sign` covers the exact bytes, so
even a faithful round-trip through `Uri` can invalidate it. The string is
returned as scanned.

`fromScan` also takes **no note**. Adding `tn` to a scanned link changes the
bytes the signature covers, and the merchant's own note is already in the
string — so the form's note reaches the *ledger* and never the payment.

Seven tests pin this, including that `mc`, `sign`, `orgid`, `mode` and `tr` all
survive, and that an accepted amount round-trips to the original string
character for character.

## The second defect: a stale signature

The replay fix above cured merchant QRs and broke personal ones.

A ₹100 payment to a personal PhonePe QR (`9786452324@axl`) showed the **right
payee, the right verified banking name and the right ₹100.00** in Google Pay,
and was then declined by ICICI with *"Your money has not been debited — you've
exceeded the bank limit for this payment."* ₹100 exceeds no real limit; banks
map many unrelated decline codes onto that message.

The decisive fact was that **the same QR scanned inside Google Pay worked.** So
the link was at fault, not the account.

The cause: replaying the string carried across `sign` and `mode=02`. Both
describe a **QR session**, and neither is true once CoinCompass has read the code
and handed a payment app an *intent*:

- `sign` is a signature over the QR's own bytes. A personal QR carries no
  amount, so filling one in changes the very content the signature covers — the
  signature is invalid **by construction**. A signature that no longer matches
  is a validation failure; no signature is merely an unsigned intent.
- `mode=02` asserts "scanned by the app performing this payment", which stopped
  being true the moment it arrived as an intent.

### What is sent now

A scanned QR is converted into an intent rather than replayed whole:

| kept — describes the payee | dropped — describes the scan |
|---|---|
| `pa`, `pn`, `mc`, `tr`, `tn`, `purpose`, `orgid` | `sign`, `signType`, `mode` |

`mc` staying is what keeps a merchant payment from being metered as
person-to-person, which was the first defect. `sign` and `mode` going is what
stops a stale signature being validated, which was the second. Both failures
came from treating the two groups as one thing.

## The defect that actually broke every payment

Three fixes above were reasoned from what a QR *probably* contains. All three
were real improvements. **None of them was the bug.**

The bug was found in one round by logging what the app actually sent:

    UPI-OUT -> upi://pay?pa=prithivi2804raj%40okicici&pn=…&am=1.00&cu=INR

**`pa=prithivi2804raj%40okicici`.** `Uri(queryParameters: …)` percent-encodes
`@` as `%40`, and a payee address without a literal `@` is not a payee address.

Why it took four attempts to see: the payment app **decodes `%40` for display**.
Google Pay showed the right person, the verified banking name and the right
amount every single time — so the link looked correct at the only point anyone
could observe it. Only the network saw the malformed address, and the decline
came back as *"You've exceeded the bank limit for this payment. Retry with a
smaller amount."* on a payment of **₹1**.

Every symptom follows from it:

| symptom | explanation |
|---|---|
| right payee and amount on screen | the app decodes `%40` to display it |
| ₹1 declined as a "limit" | generic decline for a malformed VPA |
| failed on every phone | the encoding is in this app, not the phones |
| failed on every linked bank account | ditto |
| the same QR worked scanned inside Google Pay | Google Pay builds its own link, with a literal `@` |

RFC 3986 permits `@` unescaped in a query; Dart is simply stricter than the
grammar. Both the scan path and the hand-typed path now build the query by hand
through one encoder that leaves `@` alone and escapes everything else, so a note
containing `&` still cannot inject a parameter and a space is still `%20` rather
than `+`.

Verified on the device, same method that found it:

    UPI-OUT -> upi://pay?pa=prithivi2804raj@okicici&pn=…&am=1.00&cu=INR

and Google Pay proceeded to its PIN screen rather than declining.

### The diagnostic stays

`UPI-QR-IN` and `UPI-OUT` log the exact code read and the exact link sent.
Four rounds were spent reasoning about what was probably being sent; one round
with the real string ended it. The values are the owner's own, on the owner's
own device, readable only by someone who already has developer access — which is
a small price for never having to guess at this again.

## What the pre-filled amount cost, and why it was given up

After the `%40` fix the link was correct — verified on the device, `pa` with a
literal `@`, right amount — and **Google Pay accepted it and went to its PIN
screen**. The bank still declined, every time, with *"you've exceeded the bank
limit for this payment"* on a payment of **₹1**, on every phone and every linked
account, while the same QR scanned inside Google Pay went through.

At that point the link is not the variable. What is left is *who is allowed to
initiate the payment*: NPCI's intent flow is built for **merchant** apps, and a
bank may refuse an unsigned intent from an app that is not registered with a
PSP. That is a business arrangement, not a defect, and no code change reaches
it.

So the pre-filled amount was given up and the flow the owner originally asked
for became the only one:

    scan → fills the EXPENSE → open the payment app → pay there → confirm

The scan still earns its place: it reads the payee and the amount off the code
so neither has to be typed, and the payment happens in the app the owner already
trusts with it. What is lost is the pre-fill. What is gained is that it works.

`UpiRequest` and `UpiRequest.fromScan` are **kept and still tested**. They are
one line from being reconnected if the app is ever registered with a PSP, or if
a merchant QR turns out to behave differently from a personal one — which was
never tested, because the QR in hand was a friend's personal Google Pay code.

### What it cost to learn

Four fixes were made before the real defect was found, each reasoned from what a
QR *probably* contains rather than from what the app *actually sent*:

1. rebuilt the link, dropping `mc` — broke merchant QRs;
2. replayed the whole string — carried a stale `sign`;
3. blocklist instead of allowlist — leaked `mc=0000`, `orgid`, `purpose`;
4. **`pa=…%40…`** — the actual bug, found in one round by logging the string.

Every one of those was a genuine improvement, and none of them was the problem.
The lesson is the ordering: **instrument first.** The diagnostic that found it
took ten minutes and should have been the first thing built, not the fifth.

## Platform

`mobile_scanner` 7.4.0, QR format only — a UPI code is never a barcode, and
narrowing the formats stops the scanner locking on to a product barcode that
happens to be in frame. `CAMERA` is requested when the scanner opens, never at
launch: a finance app asking for the camera on first run has no visible reason
to, and a refused prompt is hard to recover from. The camera's error builder
names what went wrong — permission, unsupported device, or a failed start —
rather than showing a black square.
