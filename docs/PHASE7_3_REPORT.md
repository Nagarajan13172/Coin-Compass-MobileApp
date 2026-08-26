# Phase 7.3 — CSV import

The web app has an `/import` page. This app now has one too, built entirely
client-side.

| | | state |
|---|---|---|
| **7.3a** | CSV lexer + row parser | ✅ done — 71 tests |
| **7.3b** | matching names to ids, and the decisions that need asking | ✅ done — 26 tests |
| **7.3c** | the writing path, the preview screen, the report | ✅ done — 29 tests |

**1,015 tests pass; `flutter analyze` is clean** for everything under
`lib/features/import/`.

## There is no server-side import endpoint

`docs/SPEC.md`'s endpoint map was verified live against the deployment, and
under export/import it lists exactly one entry: `GET /export/csv`. The web's
`/import` is a **page** path; whether it posts to a server endpoint was never
established, and finding out would mean authenticated probing of a live
financial account.

So the importer is client-side: it parses the file on the phone, resolves every
account and category name against the user's own data, and creates rows through
the existing `POST /transactions`. That honours the spec's "no backend changes"
rule and needs no unverified endpoint. It also buys something a server-side bulk
POST could not — a per-row preview and a per-row failure report.

The cost is one request per row, which is why the runner is paced the way it is.

## 7.3a — reading the file

### The lexer is hand-written, and that is the point

The guaranteed case is a round-trip of this app's own export:

    Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags

Two of those ten columns routinely carry the delimiter inside the value. A note
reading `Lunch, then fuel` survives a spreadsheet round-trip only because the
writer quoted it, and `split(',')` tears exactly that row apart, shifting every
later column left so the amount lands under `Currency`. The row does not fail —
it imports as garbage.

So `csv_table.dart` walks the source tracking quote state, and handles the three
deviations real files have: a **UTF-8 BOM** (Excel writes one on every "CSV
UTF-8" save; left in, the first header reads `﻿Date` and the file parses as
headerless), **mixed line endings**, and a **non-comma delimiter**, sniffed by
counting candidates *outside* quotes in the header line.

Line numbers are the **physical** line, not the record index — a quoted note
containing a newline makes the two diverge for the rest of the file, and only
the physical line matches the gutter in the user's spreadsheet.

### Never guess in a direction that changes money

This is the rule the parser exists to serve. An unreadable amount, an unknown
type word and an undecidable direction are all **refusals**, not defaults. A
wrong guess does not surface as a broken row the user notices; it surfaces as a
plausible transaction with the sign inverted.

Concretely, `ImportParser.parseType` is deliberately **not**
`TransactionType.fromApi`, which maps anything unrecognised to `expense`. That
tolerance is correct for a server response — a new server-side type must not
crash the app — and wrong for a user's file.

Three decisions worth recording:

**Which separator is the decimal point.** `1.234` is one-point-two-three-four to
an Indian writer and one thousand two hundred and thirty-four to a German one; a
1000× error on a real amount. It is resolved from evidence, never a guess:

| input | reading | why |
|---|---|---|
| `1.234,56` | 1234.56 | both separators present — the last one is the decimal point |
| `1,234.56` | 1234.56 | same rule, other way round |
| `1 234,56` | 1234.56 | spaces already grouped the thousands, so the comma can only be decimal |
| `1,234` | 1234 | one separator, nothing else to go on — the app's own `en_IN` convention |
| `1.234` | 1.234 | same |

Also read: `₹1,23,456.78`, `(500)` and `500-` as negatives, and `−500` with the
real minus sign this app itself renders.

**Day-first or month-first.** A single `13/04/2026` settles the whole file —
there is no thirteenth month. Only when *no* row contains such a tell is the
file genuinely ambiguous, and then the preview **asks** rather than defaulting
silently. Getting this wrong shifts up to eleven months of history into the
wrong months. A file needing both orders is reported as conflicting.

`31/02/2026` is unreadable, not rolled over: `DateTime(2026, 2, 31)` silently
becomes 3 March in Dart, which turns an unreadable date into a confidently wrong
one.

**Direction, from whatever the file offers**, in priority order: an explicit
`Type` column (the amount's sign is then discarded, so `-500` and `500` import
identically); otherwise which of `Debit`/`Credit` is filled; otherwise the sign
of `Amount`. Magnitude is resolved separately from direction — reading both from
one branch made a `Type,Debit,Credit` file import as "no amount on any row".

### Headers

Matching is shallow on purpose: normalise and look up, no fuzzy matching and no
positional guessing. A header the table does not know is reported as **unmapped**
and named in the preview, rather than assigned to whichever column sat at that
index. A file with no recognisable header is refused outright — two of the ten
columns are free text, so a positional read of the wrong file writes notes into
`Amount`.

Bank-statement aliases are included, so `Txn Date,Narration,Withdrawal,Deposit`
works. `description`/`narration` map to **Payee**, not Note, because
`Transaction.title` renders payee first and the alternative leaves every
imported row titled by its category.

## 7.3b — names to ids

A CSV says `HDFC Bank`; `POST /transactions` wants `account: "66f1…"`.

**Nothing is auto-created.** Auto-creating an unmatched name is one line of code
and the wrong trade: a typo'd `HDFC Bnak` in row 400 of a file the user did not
write silently adds a permanent account to their real finances, discovered weeks
later when a balance will not reconcile.

**Matching stops at case and spacing.** `HDFC` and `HDFC Bank` are different
accounts to the user and similar strings to an algorithm. Fuzzy matching files
transactions against the wrong account without ever asking — the same failure as
auto-creating, in the opposite direction. Punctuation is *not* folded, so
`Amex (Gold)` and `Amex Gold` stay distinct. The ladder is short and total:
exact, then case-and-spacing, then **ask**.

Categories are typed on this backend, so `Food` as an expense and `Food` as an
income category are two separate decisions.

Three asymmetries that follow from what the API requires:

- **An unresolved account blocks its rows** — there is no such thing as a
  transaction without one.
- **An unresolved category does not.** The row imports uncategorised, which the
  app renders correctly. Blocking would turn one unfamiliar category name into a
  hundred rows the user cannot import.
- **A blank Account column is answered once**, by a fallback the user picks,
  rather than row by row.

"Decided" and "buildable" are deliberately different states. A name the user has
asked to create is settled as far as the preview is concerned even though its id
will not exist until the run starts — folding the two together made the preview
say "Nothing to import" the instant the user tapped "Create it".

## 7.3c — the part that writes

Everything above is offline and reversible. The runner is not, so its rules are
about damage control:

- **Sequential, never parallel.** The deployment is one small Node process with
  a rate limit; 800 concurrent POSTs is how an import becomes an outage, and the
  failures it produced would be indistinguishable from real rejections.
- **No retries.** A failed POST may still have created the row — a timeout says
  nothing about what the server did. Retrying is how one flaky row becomes two
  identical transactions.
- **A failed creation aborts before any transaction is written.** At that point
  only the records the user asked for exist, so they can fix the problem and
  re-run: what was created now matches by name, and the second run creates only
  what is left.
- **Five consecutive failures stop the run.** An expired session makes *every*
  remaining row fail; without this the app spends minutes hammering an unhappy
  backend and hands back 800 identical errors instead of one explanation. The
  counter resets on success, so a patch of bad rows does not trip it.
- **Cancelling stops at a row boundary** and says exactly what was kept. It
  cannot un-write what is already written, and the report does not pretend
  otherwise.

Refresh goes through `invalidateTransactionDerived`, the same helper every other
write path uses, so an import cannot drift out of sync with what a single manual
add refreshes.

### The screen

Mounted at `/reports/import` — under Reports so the bottom nav stays lit, the
same arrangement `/credits/people` uses. Reached from Reports' own header, next
to Export CSV, because they are the same job in two directions. The web's
top-level `/import` has no nav slot to spare here.

The screen is one long confirmation. Every state before the run writes nothing,
and the only way into the writing state is a button that **names the row count** —
the number is the confirmation. It is disabled while any name is undecided, and
a separate line says how many records will be created.

The preview also shows the first five rows exactly as they will be saved, which
is the last chance to notice that an amount or a date came out wrong.

### One layout bug, caught by the widget test

`AppButton` centres a `Row` of icon + unconstrained `Text`, so a label wider than
its share of a 360dp card overflows rather than ellipsising — the unmatched-name
card's two side-by-side buttons overflowed by 5.4px on "Will be created". They
are stacked now. Tamil runs to **173%** of English on labels this shape (see
`PHASE7_1_REPORT.md`), so a side-by-side pair could not have survived the
language toggle either.

> Stacking turned out to be necessary and **not sufficient** — the device found
> the same buttons overflowing again in Tamil at full card width, and the real
> fix was in `AppButton` itself. See *Three defects only the device could show*
> below.

## Localisation

The import feature's user-facing strings are rendered through the app's `Text`,
so they travel the same route as the rest of the UI.

`RowIssue` is a domain object with no `BuildContext`, so it cannot reach a
localisations instance, and threading one through a pure parser would make every
parser test need a widget binding. Each issue therefore carries
**`code` + `field` + `detail`** — everything needed to rebuild the sentence in
any language — with the English rendering as a fallback. Callers match on `code`,
never on `message`, and a test pins that contract.

## Verified on hardware

Walked on the owner's phone (CPH2569, Android 15, 360x804dp) on 25 Aug 2026 —
first in English against a five-row test file, then **for real** against the live
account with the app in Tamil.

### The dry run

- **The file picker opens and filters.** This is the piece `flutter test` could
  not reach — `file_picker` is a method channel with no implementation under the
  test binding. The Android SAF picker appears and lists only the CSV.
- **`/reports/import` is reachable** from the Reports header, and the bottom nav
  keeps **Reports** lit, which is why it is mounted there.
- **The date-ambiguity card fires.** Every row used `DD/MM` values under 13, and
  the preview asked *"03/04 could be 3 April or 4 March"* rather than choosing.
- **Typed category matching holds.** `Food` reported "No **expense** category"
  and `Salary` "No **income** category", and the category's third button read
  **"Leave blank"** where the account's read "Skip these rows".
- **Blocked rows name the spreadsheet line.** L2-L6, with L4 reporting *both*
  accounts of the transfer row and L5 reporting `"oops" is not an amount this
  app can read.`
- **The run button stayed shut** — *"5 names need a decision"*, disabled.

### The real import

Three rows into a purpose-made `Import Test` account, no category, so exactly
one record would be created. Predicted before running, then checked:

| | before | predicted | after |
|---|---|---|---|
| Income | ₹0 | ₹222 | **₹222** |
| Expense | ₹13,312 | ₹13,756 | **₹13,756** |
| Net | −₹13,312 | −₹13,534 | **−₹13,534** |
| Transactions | 2 | 5 | **5** |
| Accounts | 0 | 1 | **1** |

Every figure landed exactly. The report read *"3 transactions added from
verify-73.csv · New accounts: Import Test"*, and opening a row confirmed every
field round-tripped: payee `ZZTest Gamma`, note `7.3 verification`, account
`Import Test`, category blank, 22 Aug 2026.

Then cleaned up — three transactions swiped away, the account deleted — and the
baseline came back to ₹13,312 / 2 transactions / no accounts / −₹2,00,00,000.
(The transactions are soft-deleted: gone from every view and every balance, still
recoverable in the app's deleted list, because the API has no purge endpoint.)

### Three defects only the device could show

All three are Tamil-only, and every widget test in this repo runs in English.

**1. `AppButton` overflowed, three times on one screen** — 1.3px on "Skip these
rows", 12px on "Import 3 transactions", 126px on "Import another file". The
widget centred a `Row` of icon + *unconstrained* `Text`; a `Row` sized to its
children hands unbounded width to that `Text`, so a long label paints past the
button instead of ellipsising. Tamil runs to 173% of English (PHASE7_1_REPORT),
which is what exposed it.

This was a latent bug in a **shared** widget, not in the importer — every button
in the app had it. `AppButton` now wraps its label in `Flexible` with
`TextOverflow.ellipsis`; ellipsis rather than wrap because the shared theme
fixes button height at 46-48px, so a second line would be clipped.
`test/app_button_overflow_test.dart` pins all three real strings at 360dp, and
fails with a `RenderFlex overflowed` without the fix.

Worth noting the earlier 360dp fix in the preview was *stacking* those buttons,
with a comment predicting exactly this risk. Stacking was necessary and not
sufficient: it fixed English, and Tamil still overflowed the full card width.

**2. User data was machine-translated on the way to the screen.** `core/ui.dart`
swaps `Text` for one that sends its content to ML Kit — right for UI copy, wrong
for data. The screen showed the chosen file as `சரிபார்க்கவும் 73.csv` (the
filename `verify-73.csv`, translated, so it no longer matched anything in the
user's file manager), `ZZTest Alpha` as `Zztest ஆல்பா`, and `ZZTest Gamma` as
`Zztest gamma` — the same column rendered three different ways. The account about
to be created displayed as `இறக்குமதி சோதனை` when the record it creates is named
`Import Test`.

The *data* was never wrong: drafts carry `row.payee` and `ref.name` from the
parsed model, and the device confirmed the stored payee is `ZZTest Gamma`. But a
preview whose entire job is "see exactly what will be added" was showing
something other than what would be added. Every user-data site now renders
through `Text.rich`, the documented bypass, and `import_screen_test.dart`
asserts the user-data sites take the span path while app copy does not.

**This is a general problem and only this screen is fixed.** Any screen showing
a payee, account, category or note has it.

**3. Two cosmetic issues left for the 7.1 owner**, both outside this feature:

- `AppSelect`'s `hint` stayed English (`Use an existing one…`) in an otherwise
  Tamil screen. `hintText` builds its own paragraph rather than a `Text`, which
  `translated_text.dart` documents as needing explicit handling — `AppTextField`
  got it, `AppSelect` did not.
- The intro paragraph came back duplicated: *"இது ஒரு CSV இது ஒரு CSV ஏற்றுமதி
  இறக்குமதி இருந்து ஏற்றுமதி."* Same failure mode as the "on this phone on this
  phone" duplication already fixed in 7.1.

The mono CSV-header block deliberately stayed English throughout — it is a
literal the user must reproduce, and it is a `SelectableText`, not the app's
`Text`.

## Not done

- **XLSX.** The web's example file is an xlsx; this reads CSV only. Parsing xlsx
  needs a real dependency, and the app's own export is CSV, which is what makes
  the round-trip the guaranteed case.
- **Duplicate detection.** Importing the same file twice will double every
  transaction. The backend has no idempotency key, so catching this means
  fetching the file's date range and matching on (date, amount, type, account).
  It is the highest-value thing left in this area and is not built.
- **Duplicate detection**, still the highest-value gap: the real import above
  would double every row if the same file were imported twice.
