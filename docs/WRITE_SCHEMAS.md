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
| `POST /holdings` | name*, class*, subtype*, value* (+ others — not yet probed) | — |
| `POST /loans` | name*, outstanding* (+ others — not yet probed) | — |

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
