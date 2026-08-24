# Verified write schemas (probed against the live backend, 24 Aug 2026)

Method: POST each key with a wrong-typed value (`{"key":{"z":1}}`). A key the Zod schema
declares returns a `fieldErrors` entry; an undeclared key is **silently stripped**. Confirmed
by round-tripping real records and reading back what persisted.

**Anything not in the ACCEPTED column is discarded by the server with no error.**

| Resource | ACCEPTED keys | Silently stripped (do NOT send) |
|---|---|---|
| `POST /accounts` | name, type, initialBalance, includeInTotal, color, icon, currency | openingBalance, excludeFromTotal, institution, last4, note, creditLimit |
| `POST /transactions` | type*, amount*, account*, toAccount, category, date, note, payee, tags, oneoff, currency | — |
| `POST /recurring` | type*, amount*, account*, toAccount, category, note, payee, tags, currency, frequency, interval, startDate, endDate, active | — |
| `POST /budgets` | amount*, category, period, currency, startDate | **name, rollover**, note, alertAt, threshold, account |
| `POST /goals` | name*, targetAmount*, savedAmount, targetDate, monthlyContribution, color, icon, currency | **note**, priority, status |
| `POST /credits` | person*, direction*, amount*, note, date, account, category | **dueDate, currency, settled, settledAt**, status |
| `POST /people` | name*, relation | **phone, email, note, color, group**, key, nickname, avatar, tags |
| `POST /people/groups` | name*, members | **color, note**, description, icon |
| `POST /splits` | description*, totalAmount*, yourShare*, participants, date, note, category, account | **group, currency, settled** |
| `POST /holdings` | name*, class*, subtype*, value*, maturityDate, startDate, note, currency | **invested, institution, roi**, account |
| `POST /loans` | name*, outstanding*, lender, type, principal, roi, emi, foreclosureChargePct, startDate, endDate, status, note, currency | **interestPaid, chargesPaid** (server-computed), tenure, account |
| `POST /stocks/buy` | symbol*, demat*, qty*, buyPrice*, buyDate, note | date, exchange, name, charges, brokerage |
| `POST /stocks/sell` | symbol*, demat*, qty*, sellPrice*, sellDate, note | date, lot, charges, brokerage |

`*` = required (server returns `["Required"]` when the whole body is empty).

## Enum vocabularies

| Field | Values |
|---|---|
| `people.relation` | `family` \| `friend` \| `colleague` \| `other` (server default: `other`) |
| `credits.direction` | `given` \| `received` \| `borrowed` \| `repaid` |
| `budgets.period` | `weekly` \| `monthly` \| `yearly` |
| `transactions.type` / `recurring.type` | `income` \| `expense` \| `transfer` |
| `accounts.type` | `cash` \| `bank` \| `card` \| `wallet` \| `upi` \| `savings` \| `demat` |
| `categories.type` | `income` \| `expense` |
| `loans.type` | `home` \| `personal` \| `car` \| `education` \| `gold` \| `business` \| `other` |
| `loans.status` | `active` \| `closed` |
| `holdings.class` | `saving` \| `investment` |
| `holdings.subtype` | fixed_deposit \| recurring_deposit \| emergency_fund \| retirement_fund \| stocks \| mutual_funds \| real_estate \| bonds \| gold |

## Server-computed fields the client should read, not send

| Resource | Fields |
|---|---|
| budgets | `spent`, `remaining`, `percent`, `over`, `periodRange{start,end}` |
| goals | `remaining`, `percent`, `complete`, `monthsLeft` |
| people | `key` (slug), `relation` (defaults to `other`) |
| recurring | `upcoming[]`, `nextRun`, `lastRun` |

## Rule for this codebase

Never put an input on screen whose value the server will discard. Either the key is in the
ACCEPTED column, or the control does not exist. Re-probe this table before adding any new form
field — the check takes seconds and has already caught two rounds of silent data loss.


---

# Phase 4 action endpoints (from the deployed web bundle, not probed)

The web client's exact call sites, recovered from `index-BCZVpAqp.js`:

| Call | Body |
|---|---|
| `POST /loans/:id/pay` | `{amount, chargePct}` |
| `POST /loans/:id/preclose` | `{chargePct}` |
| `POST /stocks/splits/apply` | the split object |
| `POST /stocks/refresh` | *(no body)* |
| `DELETE /stocks/lots/:id` | — |
| `DELETE /stocks/sales/:id` | — |

`GET /stocks/splits` lists splits. **There is no `POST /stocks/splits`** — it 404s. Splits are
applied via `/stocks/splits/apply`. Fix `Endpoints.stocksSplits` usage accordingly.

`demat` on buy/sell is an **account id of type `demat`** — buying requires such an account to
exist first.

---

# ⚠️ NEVER PROBE MUTATING ACTION ENDPOINTS

Schema probing works by POSTing a wrong-typed value and reading the validation error. That is
safe for **create** endpoints (validation rejects before anything is written). It is NOT safe
for **action** endpoints, where an empty or partial body can be *valid* and the action simply
executes.

This was learned the hard way: `POST /loans/:id/preclose {}` with an empty body returned no
error because `chargePct` is optional — it **closed a live ₹2,00,00,000 home loan**
(`outstanding` → 0, `status` → `closed`). It was restored from the Phase 0 recon capture in
`scratchpad/api/loans.json`, field for field.

Treat these as off-limits for probing — read the web bundle instead:

    /loans/:id/pay        /loans/:id/preclose      /goals/:id/contribute
    /recurring/:id/run    /recurring/:id/skip      /recurring/:id/post-one
    /people/:id/merge     /transactions/:id/restore
    /stocks/splits/apply  /stocks/refresh          /metals/refresh
    /notifications/read-all  /auth/lock-wealth     /auth/unlock-wealth

**Rule:** only probe endpoints that CREATE a new row. For anything that mutates existing state,
recover the contract from `scratchpad/assets/index-BCZVpAqp.js`, or test against a throwaway
record you created yourself — never against the user's real data.

## Constraints a key-level probe cannot see

`POST /holdings` — **`class` and `subtype` are not independent.** The server
validates each against its own enum separately, so `{class:'saving',
subtype:'stocks'}` is accepted and written without complaint; the holding then
files under the wrong half of the saving/investment split. The pairing is:

| class | subtypes |
|---|---|
| `saving` | fixed_deposit, recurring_deposit, emergency_fund, retirement_fund |
| `investment` | stocks, mutual_funds, real_estate, bonds, gold |

Encoded once in `HoldingSubtype.holdingClass` (`lib/core/api/enums.dart`) and
pinned by `test/write_schema_test.dart` — the form derives its Type options from
the selected class rather than offering all nine.

The wrong-typed-value probe only answers "is this key declared?". It cannot
detect a relationship *between* two accepted keys, so constraints like this one
have to be read off the web bundle or inferred from the rendered UI.
