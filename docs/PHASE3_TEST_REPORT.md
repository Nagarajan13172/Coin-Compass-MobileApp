# Phase 3 — test report (24 Aug 2026)

Tested on the OnePlus CPH2569 (Android 15) over wireless ADB, against the live backend.

## Static

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 104 passing |
| `flutter build apk --debug` | Built |

## On-device walkthrough

All five Phase 3 routes were visited; `logcat` showed **no Flutter exceptions and no RenderFlex
overflows**.

| Screen | Result |
|---|---|
| Calendar | Month grid, today marker, per-day transaction markers, day detail (In/Out/Net). One bug — fixed below. |
| Budgets | Empty state correct ("No budgets yet"). |
| Goals | Empty state correct ("No goals yet"). |
| Credits | Net position card, Owed-to-you / You-owe split, People & Splits tiles, empty state. |
| Recurring | Real data: monthly income/expense/net summary, both rules with cadence, next run and amount. |

## Bug found and fixed

**Calendar weekday header rendered day numbers instead of day names** — it showed
`05 06 07 08 09 10 11` where `Mon … Sun` belongs.

Cause: `month_grid.dart` built the label with
`DateX.shortDay(...).split(' ').first`, but `shortDay` formats as `'dd MMM'`, so
`"05 Jan"` → `"05"`. The date arithmetic was correct; only the formatter was wrong.

Fix: added `DateX.weekdayShort` (pattern `EEE`) and `DateX.weekdayNarrow` (`EEEEE`), and used
the former. Added 5 regression tests, including one asserting the label is never parseable as
an integer, so this exact failure cannot come back silently.

## Open issue — silent data loss on five forms

Same class of defect as the Phase 2 accounts blocker: the forms POST fields the backend's Zod
schema does not declare, so they are **stripped without an error**. Verified two ways — probing
each key with a wrong-typed value (validated keys error, unknown keys stay silent), and by
creating real records and reading back what persisted.

Proof, creating a person with every field the form offers:

```
POST /people {"name":"ZZ-PROBE","phone":"…","email":"…","note":"…","color":"#FF0000"}
->  {"name":"ZZ-PROBE","key":"zz-probe","relation":"other","_id":"…"}      # phone/email/note/color gone
```

| Form | Visible inputs that do NOT persist |
|---|---|
| **People** | Phone, Email, Note, Colour, Group — **5 of 6 inputs**; only Name saves |
| **Credits** | Due date, currency, settled, settledAt |
| **Budgets** | Name, rollover |
| **Splits** | Group, currency, settled |
| **Goals** | Note |
| Recurring | *(none — all 14 keys validate correctly)* |

Read-side gaps: the server returns `relation` and `key` on people, and `over` / `periodRange`
on budgets; none are parsed by the Dart models. Not harmful (the client derives `isOver`
itself), but the server's values are authoritative.

### This needs a decision, not just a patch

The fields genuinely do not exist in the backend schema, so there are two valid fixes:

- **A — trim the mobile forms** to what the API accepts. Fast, no backend change, but the app
  then offers less than the inputs imply today (no phone/email on a person, no due date on a
  credit).
- **B — add the fields to the Node backend** (`phone`, `email`, `note`, `color`, `group` on
  people; `dueDate` on credits; `name`, `rollover` on budgets; …) and keep the forms.
  More useful, but it is a backend change and the web app would want them too.

Phase 2 chose A for accounts (dropped institution/last4/note, added icon/colour instead, which
the schema does accept). Worth confirming the same call applies here, since a lending tracker
without a due date is a real capability loss.
