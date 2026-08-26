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

## Platform

`mobile_scanner` 7.4.0, QR format only — a UPI code is never a barcode, and
narrowing the formats stops the scanner locking on to a product barcode that
happens to be in frame. `CAMERA` is requested when the scanner opens, never at
launch: a finance app asking for the camera on first run has no visible reason
to, and a refused prompt is hard to recover from. The camera's error builder
names what went wrong — permission, unsupported device, or a failed start —
rather than showing a black square.
