# Phase 7.6 — Pay from inside the app

Type an expense, tap **Pay ₹250 with UPI**, choose a payment app from a sheet
that lists the ones actually installed, and pay. Android only.

## What was checked before any code was written

Against the owner's phone, not documentation:

    $ adb shell pm query-activities -a android.intent.action.VIEW -d "upi://pay"
    com.google.android.apps.nbu.paisa.user   (Google Pay)
    com.hdfcbank.android.now                 (HDFC)
    com.phonepe.app                          (PhonePe)
    com.whatsapp                             (WhatsApp)
    net.one97.paytm                          (Paytm)

and a real intent, with an intentionally invalid VPA so nothing could complete,
resolved to `ResolverActivity` with all five. So the mechanism was proven before
the feature was designed around it.

## Constraints, stated up front

- **Android only.** UPI's deep-link contract is an Android intent; iOS has no
  equivalent and no result callback. `UpiService.isSupported` is false
  everywhere else and the button does not render.
- **The response is not proof of payment.** NPCI's own spec makes server-side
  verification authoritative; the returned string arrives through an `Intent`
  extra from an app this one did not write. So nothing is recorded on the
  strength of it — see below.
- **A payee VPA had to come from somewhere.** `Person` has `name`, `key` and
  `relation`, and the `/people` write schema accepts no VPA, so there was no
  server-side home for one that did not need a backend change.

## The design

**Amount → sheet → app → back → you decide.**

There are two paths, and the UPI ID decides which:

**Without a UPI ID — the common one.** Tap an app, it opens at its own home
screen, and you pick who to pay *there*: a QR scan, a saved contact, a phone
number. Nothing comes back — a launcher intent carries no result — so the sheet
asks **"Did you pay in GPay?"** and records only if you say yes.

This is the path the owner actually wanted, and the first build did not have it.
Requiring a UPI ID up front left every app tile greyed out and untappable, which
is not what "open my payment app" means. UPI's own link cannot express
"payee unknown" either: `pa` is required, so a link without one is rejected by
the app after it opens.

**With a UPI ID.** A real `upi://pay` link, so the app opens on a payment screen
with payee and amount already filled in, and answers with a status when it is
done.

The sheet is the app's own, not the system chooser: it lists installed apps with
their real launcher icons, so the choice happens inside CoinCompass, which is
what was asked for.

**VPAs are remembered on this phone only.** A VPA is the string money follows;
sending the owner's payee list to a backend with no field for it would mean
inventing storage for the most sensitive value in the feature, on an API this
app cannot change. Kept local, a lost phone loses a convenience and nothing
about anyone's payment addresses ever reaches the network. The sheet says so.

**Nothing is recorded automatically.** After the payment app returns, the sheet
reports what it said and offers to record the expense; the transaction is still
saved by the form's own button. The word "Paid" is deliberately never used — the
copy says *"the app reported success"* and tells the owner to check their bank,
because this app does not state things about money it cannot back up.

`SUBMITTED` is treated as **pending, not success**. Bank-account debits settle
asynchronously, and calling that success is how an app tells someone they paid
when they may not have.

## Correctness that lives in pure Dart

Thirty-two tests, no phone required.

**A VPA is not free text.** A typo does not fail — it pays someone else, and
nothing in UPI catches it. So `Vpa.tryParse` is strict about shape, tolerates a
pasted trailing space, and preserves case because some PSPs are case-sensitive.
The VPA is shown verbatim beside the amount at every step, because that display
is the only check anyone has.

**The amount is never formatted for humans.** `Money.format` produces
`₹1,234.50`; a payment app handed that either refuses the link or parses
whichever digits it recognises. The link carries `1234.50`.

**The link is built with `Uri`, never string concatenation** — a note containing
`&` would otherwise inject a parameter.

**Amounts over ₹1,00,000 are refused before launching**, because the payment app
accepts the link and *then* rejects it, which reads as this app being broken.

## Three defects the device found

**0. The app tiles could not be tapped at all.** Not strictly a defect — the
first build did exactly what it was designed to do — but the design was wrong.
Every tile required a UPI ID first, so the sheet listed five apps and opened
none of them. Fixed by making the ID optional and adding the open-and-ask path
above, which is what the feature was for.

**1. The button never enabled.** `AmountField.onChanged` only calls `setState`
to clear an error, so a button reading the amount at build time never learned it
had been typed and sat disabled forever. It is now rebuilt from the controller
through a `ValueListenableBuilder`, which also keeps every keystroke from
rebuilding the whole sheet.

**2. The sheet crashed on open** — *Null check operator used on a null value*.
To ask "is this amount payable?" before a VPA existed, the sheet fabricated a
placeholder VPA `x@y` — which failed `Vpa`'s own two-character minimum, so `!`
threw. A check that needed a payee in order to validate an amount was simply the
wrong shape; `amountBlocker` is now static and payee-independent.

**3. `<queries>` needs the host, not just the scheme.** This one cost the most.
The manifest declared

    <data android:scheme="upi"/>

which is what every example shows, and the merged APK manifest contained it
exactly. Yet `queryIntentActivities` returned **0** from inside the app while
`adb shell pm query-activities` listed all five, and
`getPackageInfo("com.phonepe.app")` threw `NameNotFound`. A scheme-only query is
matched as the bare URI `upi:`, which does not match the payment apps'
`upi://pay` filters. Adding `android:host="pay"` took it from 0 to 5.

The failure mode is the dangerous part: package visibility returns an **empty
list, never an error**, so the sheet correctly and confidently reported "No UPI
app found on this phone" on a phone with five of them.

## Verified on hardware

CPH2569, Android 15. The whole flow, end to end: type ₹250 → **Pay ₹250 with
UPI** → the sheet lists GPay, HDFC Bank App, Paytm, PhonePe and WhatsApp with
their real icons → tap **GPay** → *Google Pay opens*
(`com.google.android.apps.nbu.paisa.user/…MainActivity` takes focus) → come back
→ **"Did you pay in GPay?"** with *Yes — record ₹250* and *No, I didn't pay*.

The button appears on **Expense** only — UPI sends money
out, so offering it on an income row would be a control that cannot do what it
says — reads *"Pay ₹250 with UPI"*, and opens a sheet listing GPay, HDFC Bank
App, Paytm, PhonePe and WhatsApp with their real icons, greyed until a UPI ID is
entered.

**No real payment was completed**, so these remain unverified:

- whether each app honours a **pre-filled amount** from a third-party caller —
  this is per-app policy and has tightened over time;
- the shape of each app's response string, and therefore the parser against real
  data rather than the documented format;
- the deep-link return path end to end.

The first real payment will settle all three, and the parser is deliberately
tolerant — unknown keys, case-insensitive matching, and an unrecognised status
that becomes `unknown` rather than a guess in either direction.
