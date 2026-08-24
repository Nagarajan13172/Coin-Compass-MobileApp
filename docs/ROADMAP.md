# CoinCompass Mobile — Build Roadmap

Target: Flutter Android app with **feature parity** to the CoinCompass web app, against the
existing Node.js backend (no backend changes). Contract + design tokens: see `SPEC.md`.

Legend: [x] done · [~] in progress · [ ] not started

---

## Phase 0 — Environment & recon  [x]

| # | Task | Status |
|---|---|---|
| 0.1 | Flutter project scaffold (`cloud.sathishkumar.coincompass`) | [x] |
| 0.2 | Fix missing Java — point Flutter at Android Studio JDK 21 | [x] |
| 0.3 | Lock dependency set, verify `pub get` + native APK build | [x] |
| 0.4 | Bundle Inter font (400/500/600/700) | [x] |
| 0.5 | Pair OnePlus CPH2569 over wireless ADB | [x] |
| 0.6 | Baseline app built → installed → launched → screenshotted on phone | [x] |
| 0.7 | Reverse-engineer API contract (~90 endpoints, live-verified) | [x] |
| 0.8 | Extract design tokens (light+dark) from deployed CSS | [x] |
| 0.9 | Screenshot all 17 screens at mobile viewport | [x] |
| 0.10 | Write `SPEC.md` (contract + tokens + architecture) | [x] |

**Key finding:** auth is an HttpOnly `mt_session` cookie, not a bearer token → the app needs a
persistent cookie jar. Money values are whole rupees. Locale is `en-IN` (Indian digit grouping).

---

## Phase 1 — Foundation  [x]

Nothing user-facing ships without this. Single-writer per file to avoid collisions.

| # | Task | Status |
|---|---|---|
| 1.1 | `AppColors` light+dark from the token table; `AppTheme` (M3, Inter, 12px radius) | [x] |
| 1.2 | Theme controller (light/dark/system, persisted) | [x] |
| 1.3 | Shared widget kit — AppCard, StatCard, SectionHeader, SegmentedPeriodSelector, MoneyText, CategoryAvatar, EmptyState, AppButton, AppTextField, AppSelect, LoadingShimmer, ErrorRetry, ConfirmSheet, MonthPager | [x] |
| 1.4 | `ApiClient` — Dio + **PersistCookieJar** + timeouts + error interceptor | [x] |
| 1.5 | `ApiException` — parses the Zod `details.fieldErrors` envelope; 401/429 handling | [x] |
| 1.6 | `Endpoints` — every path in the contract | [x] |
| 1.7 | `Money` (Indian grouping, K/L/Cr compact), `DateX`, `lucideIcon()` map (26 icons) | [x] |
| 1.8 | 20 domain models + shared enums + `Paginated<T>`, derived from real payloads | [x] |
| 1.9 | Auth: session restore, sign in/up/out, forgot password, 2FA state | [x] |
| 1.10 | Auth screens: Login (pixel-matched), Signup, Forgot password, 2FA | [x] |
| 1.11 | App shell: top bar (logo, search, bell+badge, EN/த pill, avatar) | [x] |
| 1.12 | Bottom nav 5-slot + raised center FAB + Add sheet + More sheet | [x] |
| 1.13 | GoRouter — 17 in-app routes + 4 auth routes + auth redirect | [x] |
| 1.14 | i18n scaffold (`t()` + EN dictionary + locale persistence) | [x] |
| 1.15 | `main.dart` wiring, integrate, `flutter analyze` clean, APK builds | [x] |

**Gate: PASSED (24 Aug 2026).** Verified on the OnePlus CPH2569 over wireless ADB:
real sign-in against the live API succeeded; a force-stop + cold relaunch restored the session
straight to the dashboard (persistent cookie jar works); all 17 routes navigable; 38 tests green;
`flutter analyze` clean.

---

## Phase 2 — Core money loop  [x]

The daily-use path. Highest value; do it first.

| # | Task | Endpoints |
|---|---|---|
| 2.1 | Dashboard: greeting, Week/Month/Year, Income/Expense/Net stat cards | `/reports/summary` |
| 2.2 | Dashboard: net-worth card, quick stats (avg/day, biggest category, count) | `/networth/history` |
| 2.3 | Dashboard: income-vs-expense chart, spending donut + category rows | `/reports/trend`, `/reports/by-category` |
| 2.4 | Dashboard: Accounts, Gold & Silver sparkline, Recent transactions cards | `/accounts`, `/metals/latest`, `/transactions` |
| 2.5 | Transactions list: day grouping + day-net headers, running balance | `/transactions`, `/transactions/balance` |
| 2.6 | Transactions: MonthPager, search, filters (type/account/category/tags) | `/transactions?…` |
| 2.7 | Transactions: pagination, pull-to-refresh, swipe to delete + undo/restore | `/transactions/:id`, `/:id/restore` |
| 2.8 | Add/Edit transaction sheet: income / expense / **transfer**, amount keypad, category & account pickers, date, payee, note, tags, one-off | `POST/PATCH /transactions` |
| 2.9 | Quick-add templates (the chips row) | `/templates` CRUD |
| 2.10 | Accounts screen: list by type, balances, totals, CRUD | `/accounts` |
| 2.11 | Categories screen: grouped list, icon+color picker, subcategories, CRUD | `/categories` |

**Gate: PASSED (24 Aug 2026).** Created an account and logged a ₹250 expense on the OnePlus;
both reached the live backend and the expense appeared in the web app ("3 transactions · August
2026 · Net −₹250"). Test data deleted afterwards. A follow-up adversarial review raised 29
claims, 20 confirmed; all fixed — see docs/PHASE2_FINDINGS.md. 75 tests green.

---

## Phase 3 — Planning & tracking  [x] built · tested 24 Aug 2026  [~]

| # | Task | Endpoints | Status |
|---|---|---|---|
| 3.1 | Budgets: per-category progress bars, on-track/near-limit states, CRUD | `/budgets` | [x] |
| 3.2 | Goals: progress rings, remaining/monthsLeft, **contribute** flow, CRUD | `/goals`, `/goals/:id/contribute` | [x] |
| 3.3 | Recurring: rules list, next/last run, `upcoming` preview, active toggle | `/recurring` | [x] |
| 3.4 | Recurring actions: run, skip, post-one, per-rule transaction history | `/recurring/:id/*` | [x] |
| 3.5 | Calendar: month grid with per-day income/expense, day drill-down | `/transactions?from&to` | [x] |
| 3.6 | Credits: given/received/borrowed/repaid, summary, settle, CRUD | `/credits`, `/credits/summary` | [x] |
| 3.7 | People & Groups: CRUD, merge duplicates | `/people`, `/people/groups` | [x] |
| 3.8 | Splits: shared expenses (description, total, your share), CRUD | `/splits` | [x] |

Five routes now render real screens (`/budgets`, `/goals`, `/recurring`, `/calendar`,
`/credits`); People and Splits hang off Credits at `/credits/people` and `/credits/splits`,
so the nav still has exactly 17 destinations.

Notes on what the API could not confirm:
- **Budget spend** is not on `/budgets`, so progress is measured against `/reports/summary`
  and `/reports/by-category` for the window the budget's period describes. A server-sent
  `spent` wins when it is there.
- **`/credits/summary`** answers with an empty array on an account with no credits, so the
  screen totals the list itself whenever the response is not an object.
- **Person merge** — the recorded account has no people, so the field name for the merge
  target is unverified. `POST /people/:id/merge` goes out with both `into` and `target`;
  a mismatch surfaces as a field error on the sheet.

**Gate: not yet run.** 96 tests green and `flutter analyze` clean, but nothing here has been
exercised against the live API on the phone — create a budget and a rule on the device, run
the rule, and confirm both land in the web app.

---

## Phase 4 — Wealth & assets

| # | Task | Endpoints |
|---|---|---|
| 4.1 | Net Worth: assets vs liabilities breakdown, growth trend chart | `/networth/history` |
| 4.2 | Holdings: saving vs investment, 9 subtypes, CRUD | `/holdings` |
| 4.3 | Loans: list, outstanding/EMI/ROI/tenure, active vs closed | `/loans` |
| 4.4 | Loans: part-payment, **preclose** with foreclosure charge, CRUD | `/loans/:id/pay`, `/preclose` |
| 4.5 | Loans: prepayment planner (extra/month + lump sum → interest saved, net benefit) | client-side calc |
| 4.6 | Stocks: portfolio positions, market value, unrealized/realized P&L, day change | `/stocks/portfolio` |
| 4.7 | Stocks: symbol search, buy, sell, sales history, lot management | `/stocks/*` |
| 4.8 | Stocks: corporate splits + apply, price refresh, stale-price indicator | `/stocks/splits` |
| 4.9 | Gold & Silver: 18k/22k/24k retail + per-gram, change %, history chart | `/metals/latest`, `/metals/history` |

---

## Phase 5 — Insight & account

| # | Task | Endpoints |
|---|---|---|
| 5.1 | Reports: period summary, consumption vs non-consumption, by-currency | `/reports/summary` |
| 5.2 | Reports: by-category donut + drill-down, by-account breakdown | `/reports/by-category`, `/by-account` |
| 5.3 | Reports: trend chart (income/expense/net per bucket) | `/reports/trend` |
| 5.4 | Insights: period-over-period deltas, savings rate, pace & projection, movers | `/reports/insights` |
| 5.5 | Notifications: list, unread badge, mark read, read-all, delete, deep links | `/notifications` |
| 5.6 | Settings: profile, wallet name, base currency + rates, theme, locale, week/month start | `/settings` |
| 5.7 | Settings: change password, email verification, email reports toggle | `/auth/*` |
| 5.8 | Settings: 2FA setup (QR/secret), enable/disable, backup codes, email fallback | `/auth/2fa/*` |
| 5.9 | Settings: app PIN (server-verified), wealth lock / passcode | `/settings/pin`, `/auth/lock-wealth` |
| 5.10 | Export CSV + share sheet | `/export/csv` |

---

## Phase 6 — Mobile-native polish & release

| # | Task | Status |
|---|---|---|
| 6.1 | Biometric + PIN app lock on resume (`local_auth`) | [x] walked on the device. See `PHASE6_1_REPORT.md` |
| 6.2 | Wealth-lock blur/mask on sensitive amounts | [x] walked end-to-end on the device against the live backend; account restored to `Off`. See `PHASE6_2_REPORT.md` |
| 6.3 | Offline read cache + request retry; graceful no-connection banner | [x] `response_cache.dart` + `retry_policy.dart` + stale banner; wealth-scope barriers verified on the device in 6.2 |
| 6.4 | Optimistic updates for create/edit/delete | [~] transactions only (delete/undo, insert, edit); every other feature awaits then invalidates |
| 6.5 | Audit every screen for loading / empty / error+retry states | [x] |
| 6.6 | Dark mode audit across all 17 screens | [x] |
| 6.7 | App icon, adaptive icon, splash screen, app label | [x] built · seen on the device during the 6.2 pass |
| 6.8 | Widget tests for Money/DateX, model round-trips, auth flow | [x] `auth_flow_test.dart` — 23 tests through the real stack; 4 guards mutation-proven. See `PHASE6_8_REPORT.md` |
| 6.9 | Release signing keystore, `--release` APK + AAB, size check | [x] signed with a real upload key — see `RELEASE.md` |
| 6.10 | On-device pass over all 17 screens with real data | [x] all 17 + 4 secondary, live backend. One caption bug found and fixed. See `PHASE6_10_REPORT.md` |

### 6.9 — release signing

Full detail in `RELEASE.md`. In short: a PKCS12 upload keystore (RSA 4096,
valid to 2054) lives at `~/.android-keystores/coincompass-upload.jks`, outside
the working tree — a gitignored keystore *inside* the repo is still destroyed by
`git clean -xfd`, and losing it ends the ability to update the listing. Its
password was generated at creation, written only into the gitignored
`android/key.properties`, and printed nowhere.

`build.gradle.kts` signs with that key when `key.properties` is present and falls
back to the debug key when it is not, so a checkout without the signing material
still builds. Both artifacts were verified to carry `CN=CoinCompass`, not
`CN=Android Debug`: the APK via `apksigner` (SHA-1 `4c3a…1dba`, matching the
keystore) and the AAB via `jarsigner` ("jar verified"). v2-only signing is
correct here — `minSdk` is 24, and v1 is only needed below that.

| Artifact | Size |
|---|---|
| `app-release.aab` | 59.2 MiB |
| fat APK (3 ABIs) | 61.6 MiB |
| arm64-v8a APK | 22.7 MiB |
| armeabi-v7a APK | 20.6 MiB |

Nearly all of it is the Flutter engine (~18–21 MiB per ABI). The one avoidable
chunk: **2.62 MiB of unused `LucideVariable-w*.ttf`**, declared as package assets
by `lucide_icons_flutter` and bundled whole — icon tree-shaking only reaches
`lucide.ttf` (858 KiB → 43 KiB), not plain asset fonts. Removing it means
vendoring the package.

Two things to do before any upload: bump `version:` in `pubspec.yaml` (Play
rejects a repeated `versionCode`, still `+1`), and settle `local_auth` — it is
already injecting `USE_BIOMETRIC` and `USE_FINGERPRINT` into the manifest while
6.1 leaves it unused.

### 6.5 + 6.6 — the audit

`test/state_audit_test.dart` drives all 20 in-app screens (the 17 destinations
plus Holdings, People and Splits) through four states at 360 × 800dp — 80 tests.
The whole stack is real; only Dio's adapter is swapped.

| state | transport | what is asserted |
|---|---|---|
| loading | never answers | a loading affordance, and no ErrorRetry |
| error | 500s every call | an ErrorRetry **you can tap**, and **zero skeletons** |
| empty | answers with nothing | an empty state, never a bare ₹0 |
| dark | replays the real account | lays out, and paints no light-theme surface |

Three real defects, all fixed:

| Sev | What | Where |
|---|---|---|
| major | A failed `/credits/summary` was read through `valueOrNull`, so the Net-position card **shimmered for ever** behind the list's own error — it read as "still loading" when the request was dead. Now an em dash. | `credits_screen.dart` |
| minor | The transactions header printed **"0 transactions · August 2026" on a failed load** — `total` is 0 there because nothing arrived. It already dropped the count while loading; a failure now does the same. | `transactions_screen.dart` |
| minor | `budget_tile` pinned `Color(0xFFF59E0B)` for the near-limit amber with a comment saying no token existed. One does (`c.warning`), added later for insights/notifications/reports — and the literal was the **dark** value, so light mode drew amber-500 where the palette says amber-600. | `budget_tile.dart` |

The `error` assertion of **zero skeletons** is the one that earns its keep: an
errored provider read as `valueOrNull` is indistinguishable from a slow one, and
renders as a skeleton that never resolves. That is now pinned on every screen.

Two things that looked like gaps and are not — checked, deliberately left:

- **Calendar has no skeleton.** The grid is structurally known before the data
  lands, so it draws the month and dims the amounts to 0.4 (`MonthGrid.loading`).
  Better than a skeleton, and the audit encodes it as the calendar's own proof.
- **Dashboard, Reports and Settings have no EmptyState.** They are aggregates,
  not lists. With nothing recorded the dashboard says `₹0`, *"No income this
  period"*, *"Biggest category —"* — it states zero honestly rather than
  pretending there is nothing to show.

Dark mode came out clean: no screen paints `AppColors.light`'s card, background
or secondary under `AppTheme.dark()`, and the only literal colours outside the
theme layer are white-on-brand-blue (logo, FAB, selected chip) plus the fixed
category hues, which match the web. `AppCard`'s `Colors.black` shadow is a no-op
on a dark surface — cosmetic, left alone.

### 6.7 — what shipped

The launcher icon is not a redraw: it is the web app's own installed-app icon,
fetched from `manifest.webmanifest` (`pwa-512x512.png` and the `maskable` variant)
and re-cut for Android. Note this is a *different* mark from the header logo —
the header is a white Lucide `Compass` on `#2563EB`, the installed icon is a navy
`#0F172A` ringed compass. Both are correct; they are used in different places on
the web too.

- Legacy icon, round icon (API 21-25), adaptive icon with a `<monochrome>` layer
  for Android 13 themed icons, at all five densities.
- Splash: Android 12+ via `windowSplashScreenAnimatedIcon`, older via a
  `launch_background` layer-list. Both follow the OS theme through a night-aware
  `@color/splash_background` (`#F8FAFC` / `#0F172A`), and the launch theme sets
  `windowLightStatusBar` to match, so the status bar icons stay readable.
- Label `coincompass` → **CoinCompass**, via `@string/app_name` so 7.1 can add
  `values-ta/` without touching the manifest. iOS `CFBundleDisplayName` too.
- `tool/gen_brand_assets.sh` regenerates every size from the two sources in
  `tool/brand/`; no new Flutter dependency, `pubspec.yaml` untouched.

Deliberate deviation: the web manifest's `background_color` is `#0F172A`
unconditionally, so a PWA install always flashes navy. The mobile splash follows
the OS theme instead — a cold start into the light UI has no navy flash.

**Not yet verified on hardware.** `adb devices` is empty and the OnePlus is not
answering mDNS, so the icon has only been checked by rendering the shipped
assets under each launcher mask. Reconnect the phone and confirm the icon in the
launcher, the themed icon with Material You on, and the splash in both themes.

---

## Phase 7 — Deferred (needs your call)

| # | Task | Note |
|---|---|---|
| 7.1 | Tamil localisation | ~5,200 strings extractable from the web bundle; needs Noto Sans Tamil (Inter has no Tamil glyphs) |
| 7.2 | Google OAuth sign-in | Web uses a browser redirect via `/api/auth/oauth/:provider` |
| 7.3 | CSV import | Web has `/import` with an example xlsx |
| 7.4 | Push notifications | Backend currently has in-app notifications only; would need FCM + a backend change |
| 7.5 | iOS build | Project is already configured for iOS; needs signing + on-device test |
