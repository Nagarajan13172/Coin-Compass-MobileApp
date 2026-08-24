# CoinCompass Mobile — Build Spec (single source of truth)

Flutter Android app that reuses the **existing deployed Node.js backend**. No backend changes.
The web app source is NOT on this machine; this spec was reverse-engineered from the live
deployment (bundle analysis + authenticated API probing + mobile-viewport screenshots).

Reference material in the scratchpad (read-only, for agents):
- `/private/tmp/claude-501/-Users-nagarajan-playground-CoinCompass-Mobile/75b41150-6907-4bdc-b7ce-dfb59559ca14/scratchpad/api/*.json`      — real authenticated responses for ~28 GET endpoints
- `/private/tmp/claude-501/-Users-nagarajan-playground-CoinCompass-Mobile/75b41150-6907-4bdc-b7ce-dfb59559ca14/scratchpad/shots/*.png`     — mobile-viewport screenshots of all 17 screens + login
- `/private/tmp/claude-501/-Users-nagarajan-playground-CoinCompass-Mobile/75b41150-6907-4bdc-b7ce-dfb59559ca14/scratchpad/paths_raw.txt`   — every path literal found in the web bundle
- `/private/tmp/claude-501/-Users-nagarajan-playground-CoinCompass-Mobile/75b41150-6907-4bdc-b7ce-dfb59559ca14/scratchpad/assets/*`        — the deployed JS/CSS bundles

## 1. Backend contract

- **Base URL**: `https://coincompass.sathishkumar.cloud/api`
- **Auth**: `POST /auth/signin {email,password}` returns `{user:{...}}` and sets an
  **HttpOnly cookie** `mt_session` (JWT, `Max-Age=15552000`, `SameSite=Lax`, `Path=/`).
  There is **no bearer token in the body** — the session lives only in the cookie.
  → Dart must use a **persistent cookie jar**; every request sends the cookie automatically.
- **Session bootstrap**: `GET /auth/me` → `{user}` when logged in, 401 otherwise.
- **Error envelope** (uniform, Zod):
  `{"error":"Validation failed","code":"VALIDATION_FAILED","details":{"formErrors":[],"fieldErrors":{"field":["Required"]}}}`
- **Rate limit** on auth: 10 requests / 900s (`ratelimit-*` headers). Surface 429 gracefully.
- Mongo documents use `_id`, `createdAt`, `updatedAt`, `__v`. Money is a **plain number in
  minor-unit-free rupees** (e.g. `13312` means ₹13,312 — NOT paise). Dates are ISO-8601 strings.

### Endpoint map (verified live, all 200 unless noted)

**auth** — `/auth/signin` `/auth/signup` `/auth/logout` `/auth/me` `/auth/providers`
`/auth/forgot-password` `/auth/reset-password` `/auth/verify-email` `/auth/resend-verification`
`/auth/change-password` `/auth/lock-wealth` `/auth/unlock-wealth`
`/auth/2fa/{status,setup,enable,disable,verify,pending,email,email-fallback,backup-codes}`

**transactions** — `GET /transactions?page&limit&type&from&to&search&category&account`
→ `{items[],page,limit,total,pages,hasMore}`; `POST /transactions`;
`PATCH|DELETE /transactions/:id`; `POST /transactions/:id/restore`;
`GET /transactions/{balance,summary,tags,deleted}`
required on create: `type` (`income|expense|transfer`), `amount`, `account`

**accounts** — `GET|POST /accounts`, `PATCH|DELETE /accounts/:id`
required: `name`; `type` ∈ `cash|bank|card|wallet|upi|savings|demat`

**categories** — `GET|POST /categories`, `PATCH|DELETE /categories/:id`
required: `name`, `type` ∈ `income|expense`; 33 defaults seeded;
`group` ∈ bills, debt_transfers, earnings, education, family_giving, food, health, home,
inflows, lifestyle, other, returns, savings, transport
`icon` is a **lucide** name (26 in use): banknote, briefcase, car, clapperboard, coffee,
credit-card, ellipsis, fuel, gamepad, gift, graduation-cap, heart-pulse, home, laptop,
percent, piggy-bank, pizza, plane, receipt, repeat, rotate-ccw, shopping-bag, shopping-cart,
sparkles, trending-up, utensils

**budgets** — `GET|POST /budgets`, `PATCH|DELETE /budgets/:id`
required: `amount`; `period` ∈ `weekly|monthly|yearly`

**goals** — `GET|POST /goals`, `PATCH|DELETE /goals/:id`, `POST /goals/:id/contribute`
required: `name`, `targetAmount`. Server adds `remaining, percent, complete, monthsLeft`,
defaults `color:"#6366F1"`, `icon:"goal"`.

**loans** — `GET|POST /loans`, `PATCH|DELETE /loans/:id`, `POST /loans/:id/pay`,
`POST /loans/:id/preclose`
required: `name`, `outstanding`; `type` ∈ `home|personal|car|education|gold|business|other`;
`status` ∈ `active|closed`; fields: principal, roi, emi, foreclosureChargePct, interestPaid,
chargesPaid, startDate, endDate

**credits** — `GET|POST /credits`, `PATCH|DELETE /credits/:id`, `GET /credits/summary`
required: `person`, `direction` ∈ `given|received|borrowed|repaid`, `amount`

**people** — `GET|POST /people`, `PATCH|DELETE /people/:id`, `POST /people/:id/merge`,
`GET|POST /people/groups`, `PATCH|DELETE /people/groups/:id` — required: `name`

**splits** — `GET|POST /splits`, `PATCH|DELETE /splits/:id`
required: `description`, `totalAmount`, `yourShare`

**recurring** — `GET|POST /recurring`, `PATCH|DELETE /recurring/:id`,
`POST /recurring/:id/{run,skip,post-one}`, `GET /recurring/:id/transactions`
required: `type`, `amount`, `account`; `frequency` ∈ `daily|weekly|monthly|yearly`;
server returns `upcoming: [iso...]`, `nextRun`, `lastRun`, `active`, `interval`

**templates** — `GET|POST /templates`, `PATCH|DELETE /templates/:id` — required: `name`
(these are the "Quick add" chips on the Transactions screen)

**holdings** — `GET|POST /holdings`, `PATCH|DELETE /holdings/:id`
required: `name`, `class` ∈ `saving|investment`, `subtype` ∈ `fixed_deposit|recurring_deposit|
emergency_fund|retirement_fund|stocks|mutual_funds|real_estate|bonds|gold`, `value`

**stocks** — `GET /stocks/portfolio` → `{configured,positions[],totals{marketValue,investedCost,
unrealized,unrealizedPct,dayChange,realizedPL,realizedShortTerm,realizedLongTerm},pricedAt,anyStale}`;
`GET /stocks/search?q`; `POST /stocks/buy` (required `symbol,demat,qty,buyPrice`);
`POST /stocks/sell`; `GET /stocks/sales`, `DELETE /stocks/sales/:id`;
`DELETE /stocks/lots/:id`; `POST /stocks/refresh`; `GET|POST /stocks/splits`,
`POST /stocks/splits/apply`.  NOTE `GET /stocks` is **404** — use `/stocks/portfolio`.

**metals** — `GET /metals/latest` → `{configured,gold{...},silver{...}}` with
`retail18k/22k/24k, pricePerGram18k/22k/24k, pricePerOunce, change, changePct, prevClose,
source, retailSource, date, fetchedAt`; `GET /metals/history?metal=gold&days=30`;
`POST /metals/refresh`

**networth** — `GET /networth/history` → `[{date,netWorth,assets,liabilities,accountsTotal,
holdingsTotal,stocksTotal,investment,saving,currency}]`

**reports** — `GET /reports/summary` → `{income,expense,net,incomeCount,expenseCount,
oneoffIncome,oneoffExpense,consumption,nonConsumption,netWorth,byCurrency,range{start,end}}`;
`GET /reports/by-category` → `[{categoryId,name,color,icon,group,total,count,percent}]`;
`GET /reports/by-account`; `GET /reports/trend` → `[{bucket,income,expense,net}]`;
`GET /reports/insights` → `{period,current,previous,expense{current,previous,delta,pct},
income{...},net{...},savingsRate,pace{isCurrent,daysElapsed,daysInPeriod,avgPerDay,projected,
previousToDate},movers[],topExpenses...}` — takes `period` + `ref` (an ISO instant), **not**
from/to; `GET /reports/trend` takes `granularity` (`bucket` is only the response key);
`POST /reports/email-now?kind=` — a **POST** with the kind in the query string (SPEC said GET),
and on the never-call list: it emails the account holder.

**notifications** — `GET /notifications` → `{items[],unread}`; `POST /notifications/:id/read`
(**POST**, not PATCH — corrected against the deployed bundle in Phase 5);
`POST /notifications/read-all`; `DELETE /notifications/:id`; `DELETE /notifications`
("Clear all", omitted here until Phase 5).
Item: `{_id,type,link,params{},read,readAt,dedupeKey,createdAt}`; type e.g. `recurring.posted`.

**settings** — `GET|PUT /settings` → `{name,description,baseCurrency,theme,locale,language,
firstDayOfWeek,monthStartDay,pinEnabled,emailReports,wealthLockEnabled,currencies[
{code,symbol,name,rateToBase}]}` — the verb is **PUT**: `patch("/settings` appears zero times
in the deployed bundle, and PATCH has never been tried against this deployment (do not probe
it on a live account). One concern per body, never the whole document — see
`docs/WRITE_SCHEMAS.md`; `POST /settings/pin`, `POST /settings/pin/verify`,
`DELETE /settings/pin`, `POST /settings/wealth-passcode`, `DELETE /settings/wealth-passcode`

**export** — `GET /export/csv`

## 2. Design system (extracted verbatim from the deployed CSS)

shadcn/ui HSL token model. `--radius: .75rem` → **12px** default corner radius.
Font **Inter** (bundled at `assets/fonts/`, weights 400/500/600/700). Mono = platform mono.

| token | light | dark |
|---|---|---|
| background | `hsl(210 40% 98%)` #F8FAFC | `hsl(222 47% 11%)` #0F172A |
| foreground | `hsl(222 47% 11%)` #0F172A | `hsl(210 40% 98%)` #F8FAFC |
| card | `hsl(0 0% 100%)` #FFFFFF | `hsl(222 33% 15%)` #19212F |
| popover | #FFFFFF | #19212F |
| primary | `hsl(221 83% 53%)` #2563EB | `hsl(217 91% 60%)` #3B82F6 |
| primary-foreground | #FFFFFF | #0F172A |
| secondary | `hsl(210 40% 96%)` #F1F5F9 | `hsl(217 33% 18%)` #1E293B |
| muted | #F1F5F9 | #1E293B |
| muted-foreground | `hsl(215 16% 47%)` #64748B | `hsl(215 20% 65%)` #94A3B8 |
| accent | `hsl(210 40% 94%)` #E7EDF4 | `hsl(217 33% 22%)` #26313F |
| destructive | `hsl(0 72% 51%)` #DC2626 | `hsl(0 84% 60%)` #EF4444 |
| **income** | `hsl(160 84% 31%)` #089268 | `hsl(160 84% 42%)` #11C58A |
| **expense** | `hsl(0 72% 51%)` #DC2626 | `hsl(0 84% 65%)` #F26A6A |
| border / input | `hsl(214 32% 91%)` #E2E8F0 | `hsl(215 28% 24%)` #2F3B4E |
| ring | #2563EB | #3B82F6 |

Theme mode follows `settings.theme` ∈ `light|dark|system`.

### Shell (confirmed by screenshots)
- **Top app bar**: blue #2563EB rounded-square logo (compass glyph) + "CoinCompass" 600 weight,
  then trailing: search icon, bell with blue count badge, language pill (`EN`/`த`), avatar
  circle with initials. Height ~64dp, `background` colored, 1px bottom border.
- **Bottom nav** (5 slots): `Dashboard | Transactions | [FAB] | Reports | More`.
  Centre is a raised circular **FAB** (#2563EB, white `+`, ~64dp, elevated). Active item is
  `primary` colored icon+label; inactive `muted-foreground`. Labels ~11sp.
- **"More"** opens a sheet with the remaining 12 destinations.
- Full nav set (17): Dashboard `/`, Transactions, Reports, Calendar, Budgets, Goals, Accounts,
  Credits, Recurring, Categories, Net Worth, Stocks, Loans, Gold, Insights, Notifications, Settings.

### Money & locale
`baseCurrency: INR`, `locale: en-IN` → **Indian digit grouping** (₹13,312 / ₹1,23,456).
Expense amounts render `−₹12,312` in `expense` color; income `+₹…` in `income` color.
Use `intl` `NumberFormat.currency(locale:'en_IN', symbol:'₹', decimalDigits:0)`.

### Dashboard composition (from `/private/tmp/claude-501/-Users-nagarajan-playground-CoinCompass-Mobile/75b41150-6907-4bdc-b7ce-dfb59559ca14/scratchpad/shots/home.png`)
Greeting "Good morning, {name}" + range subtitle "This month · 1 Aug – 1 Sep 2026";
Week/Month/Year segmented control; three stat cards (Income ↙ green-tint, Expense ↗ red-tint,
Net piggy-bank) each with a tinted rounded-square icon; gradient **Net worth** card with
"Breakdown" action; quick-stats card (Avg spend/day, Biggest category, Transactions);
income-vs-expense chart card with legend + "Net this period"; Accounts card ("View all");
Gold & Silver card with sparkline; Spending-by-category card with Groups/All toggle + donut +
per-category rows; Recent transactions list ("View all"). Empty states are explicit
("No accounts yet", "No income this period").

## 3. Flutter architecture (fixed — do not deviate)

Flutter 3.44 / Dart 3.12. **No code generation** (no freezed/build_runner) — hand-write
`fromJson`/`toJson`. State = **Riverpod 2.6.1** (`flutter_riverpod`), routing = **go_router 17**,
charts = **fl_chart 1.2**, icons = **lucide_icons_flutter 3.1**.

```
lib/
  main.dart                      app bootstrap, ProviderScope, session restore
  core/
    api/  api_client.dart        Dio + PersistCookieJar + interceptors
          api_exception.dart     parses the Zod error envelope
          endpoints.dart         path constants
    theme/ app_colors.dart       both palettes as const
           app_theme.dart        ThemeData light/dark from tokens
           theme_controller.dart
    router/ app_router.dart      GoRouter + auth redirect
    i18n/  strings + locale controller
    utils/ money.dart date_x.dart lucide_map.dart
    widgets/ shared UI kit (see below)
  features/<feature>/
    data/<f>_repository.dart     API calls, returns models
    domain/<f>.dart              model(s)
    presentation/<f>_screen.dart + widgets/ + <f>_providers.dart
```

Shared UI kit (`core/widgets/`) — every feature MUST reuse these, not re-invent:
`AppCard`, `AppScaffold` (app bar + bottom nav), `StatCard`, `SectionHeader` (title + trailing
action), `SegmentedPeriodSelector`, `MoneyText`, `CategoryAvatar` (tinted circle + lucide icon),
`EmptyState`, `AppButton`, `AppTextField`, `AppSelect`, `LoadingShimmer`, `ErrorRetry`,
`ConfirmSheet`, `MonthPager`.

Repository pattern: screens never touch Dio. Every list screen handles the four states
loading / empty / error+retry / data, and supports pull-to-refresh.

## 4. Out of scope for this pass (flag, don't attempt)
- Porting the web app's ~5,200 Tamil i18n strings (the toggle + EN dictionary are built;
  Tamil is a follow-up, and needs a Tamil-capable font — bundled Inter has no Tamil glyphs).
- Google OAuth sign-in (web uses a browser redirect flow at `/api/auth/oauth/:provider`).
- CSV import UI (`/import`) — export only.
