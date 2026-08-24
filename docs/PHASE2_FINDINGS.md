# Phase 2 — confirmed review findings

29 claims raised across 5 lenses; 20 survived independent adversarial refutation.
Findings 1 and 2 were additionally re-verified by hand against the live API.

## [1] BLOCKER · api-correctness

**File:** `lib/features/accounts/domain/account.dart`

lib/features/accounts/domain/account.dart and lib/features/accounts/presentation/account_form_sheet.dart use wire field names the accounts API does not have. The server's Zod schema for POST /accounts and PATCH /accounts/:id accepts `initialBalance` (number) and `includeInTotal` (boolean, defaulting to true) and strips unknown keys; the app sends `openingBalance` and `excludeFromTotal`, which are silently discarded, and reads those same absent keys back.

Evidence (all reproduced independently):
- account.dart:50 `openingBalance: J.number(json['openingBalance'])`, :58 `excludeFromTotal: J.boolean(json['excludeFromTotal'])`, :68 `'openingBalance': openingBalance`, :75 `'excludeFromTotal': excludeFromTotal`.
- account_form_sheet.dart:347 `'openingBalance': _parseAmount(_openingBalance.text) ?? 0`, :349 `'excludeFromTotal': _excludeFromTotal` — accounts_repository.dart passes this map straight to Dio with no key remapping (grep over lib/ finds zero occurrences of `initialBalance`/`includeInTotal`).
- Live probes against https://coincompass.sathishkumar.cloud/api with the session cookie:
  POST {"name":"","openingBalance":"abc"} -> fieldErrors {name} only (key unknown/stripped)
  POST {"name":"","initialBalance":"abc"} -> fieldErrors {name, initialBalance:["Expected number, received string"]}
  POST {"name":"","excludeFromTotal":"abc"} -> fieldErrors {name} only (key unknown/stripped)
  POST {"name":"","includeInTotal":"abc"} -> fieldErrors {name, includeInTotal:["Expected boolean, received string"]}
  PATCH /accounts/000000000000000000000000 with all four keys -> errors only for initialBalance and includeInTotal.
- Deployed web bundle (scratchpad/assets/index-BCZVpAqp.js) submits `{name,type,initialBalance:Number(f)||0,currency,color,icon,includeInTotal:j}` and renders `a.initialBalance` / `.filter(S=>S.includeInTotal)`; the only `openingBalance` hits are i18n label keys, and `excludeFromTotal` appears nowhere.

Runtime impact: an opening balance typed into the create/edit sheet is discarded server-side (the account is stored with initialBalance 0); the "Exclude from total" switch is a no-op that never persists; on read `openingBalance` is always 0 and `excludeFromTotal` always false, so the fallbacks at account_tile.dart:149 (`resolveAccountBalance`) and accounts_preview_card.dart:81 lose the opening balance, and an account excluded from totals (set on the web, where includeInTotal is false) is still counted at accounts_screen.dart:254 and :499. Additionally, the inline server-error binding at account_form_sheet.dart:173 (`_apiError?.fieldError('openingBalance')`) can never match, because validation errors come back keyed `initialBalance`.

**Fix:**

In lib/features/accounts/domain/account.dart, map to the real wire names and invert the boolean, preserving the server's "missing means included" default:
- line 50: `openingBalance: J.number(json['initialBalance']),`
- line 58: `excludeFromTotal: !J.boolean(json['includeInTotal'], true),`  (J.boolean already takes a fallback — json.dart:59 — so the second argument is required here; without it a doc lacking the key would flip to excluded)
- line 68: `'initialBalance': openingBalance,`
- line 75: `'includeInTotal': !excludeFromTotal,`

In lib/features/accounts/presentation/account_form_sheet.dart `_buildBody`:
- line 347: `'initialBalance': _parseAmount(_openingBalance.text) ?? 0,`
- line 349: `'includeInTotal': !_excludeFromTotal,`
- line 173: `errorText: _apiError?.fieldError('initialBalance'),` so server validation errors actually land on the field.

Update the fixtures in test/screen_layout_test.dart:262-271 to the real wire shape (`"initialBalance": …`, `"includeInTotal": true/false`) — note the a3 row's `"excludeFromTotal":true` becomes `"includeInTotal":false`. Dart identifier names (`openingBalance`, `excludeFromTotal`) can stay as-is; only the JSON keys are wrong.

Same root cause, worth fixing in the same pass: the live schema probe shows `institution`, `last4`, `note` and `creditLimit` are also unknown keys stripped by POST/PATCH /accounts — the recognized set is `name, type, initialBalance, currency, color, icon, includeInTotal, archived`. Those four form fields likewise never persist, and `color`/`icon` (which the web always sends) are never sent by _buildBody at all.

---

## [2] MAJOR · api-correctness

**File:** `lib/features/reports/data/reports_repository.dart`

lib/features/reports/data/reports_repository.dart:62 sends the trend bucket size under the query key `bucket`, but `GET /reports/trend` reads that setting from `granularity`. `bucket` is only the name of the response field, so the value is silently discarded and the endpoint falls back to daily buckets. Verified live against https://coincompass.sathishkumar.cloud/api with the saved session cookie: `?granularity=month` -> [{"bucket":"2026-08",...}], `?granularity=week` -> [{"bucket":"2026-W32",...}], while `?bucket=month`, `?bucket=week` and no parameter at all all return [{"bucket":"2026-08-04",...}]; sending both (`?bucket=day&granularity=month`) yields monthly, i.e. only `granularity` is read. The deployed web bundle agrees: index-BCZVpAqp.js calls the trend query as `JY({...u, granularity: h})` with `h = s === "year" ? "month" : "day"`, and `JY` is `q.get("/reports/trend", {params: e})`. Nothing in lib/ compensates — api_client.dart:71 forwards the map verbatim to Dio and no other file mentions `granularity`. Consequence: dashboard_screen.dart:49-52 passes `bucket: 'month'` for the Year period precisely to avoid a 365-point line (its own comment says so), the parameter is dropped, and income_expense_chart.dart renders the whole year as daily points — `showDots` turns off (count <= 12) and the axis prints five day labels like "04 Aug" instead of twelve month labels. Week and Month are unaffected only because `day` matches the server default.

**Fix:**

In lib/features/reports/data/reports_repository.dart, change the query key on line 62 from `bucket` to `granularity`:

    query: {..._range(from, to), 'granularity': ?bucket},

(The Dart parameter name `bucket` and the `TrendPoint.bucket` response field can stay as they are; only the wire key is wrong. Optionally rename the named parameter to `granularity` and update the single call site at lib/features/dashboard/presentation/dashboard_screen.dart:52 for clarity.) No other change is needed — accepted values are `day`, `week`, `month`.

---

## [3] MAJOR · api-correctness

**File:** `lib/features/auth/data/auth_repository.dart`

lib/features/auth/data/auth_repository.dart:58-79 — signIn() detects the 2FA challenge with five invented flag names and never checks the real one. The live backend answers POST /auth/signin with HTTP 200 and `{"requires2fa":true,"methods":["totp",...]}` (proven by the deployed client bundle's signin mutation, which reads `n.requires2fa` off a resolved axios response and forwards `methods` to /login/2fa). Because `requires2fa` is not among the checked keys, `_looksLikeTwoFactorChallenge` returns false and line 63 constructs `SignInSuccess(AppUser.fromJson(map))` from a body that has no user, producing AppUser(id:'', email:''). AuthController marks status=signedIn (auth_providers.dart:92-96), AuthState.isSignedIn is true because user != null, and the GoRouter redirect sends the user to the dashboard — while the server issued no mt_session cookie and the 2FA verification was never performed. With no 401 interceptor in api_client.dart, every subsequent request 401s and the user is stranded on a dead shell with no way back to /login except killing the app. Secondary, same root cause: `emailFallback: J.boolean(map['emailFallback'])` (line 60) reads a key the server never sends — email fallback is signalled by `methods` containing "email" (the web reads `methods` from the signin response and from GET /auth/2fa/pending).

**Fix:**

In lib/features/auth/data/auth_repository.dart, key the challenge off the real field and stop fabricating a user from a response that has none:

1. In signIn(), before the success path:
   `final methods = J.stringList(map['methods']);`
   `if (J.boolean(map['requires2fa']) || map['user'] is! Map) { return SignInNeedsTwoFactor(emailFallback: methods.contains('email')); }`
   i.e. treat `requires2fa == true` as authoritative, and make SignInSuccess require an actual `user` object so an unrecognised body can never become an empty AppUser. (If a bodyless-user response that is *not* a 2FA challenge should be an error, throw ApiException instead of returning SignInNeedsTwoFactor for that branch.)

2. Replace `_looksLikeTwoFactorChallenge` with the `requires2fa` check (keeping the other names only as an extra `||` fallback is harmless, but `requires2fa` must be checked and must be first).

3. Carry `methods` into SignInNeedsTwoFactor (add `final List<String> methods;`) so TwoFactorScreen can enable/disable the "email me a code" and backup-code options from the server's list rather than the never-present `emailFallback` flag; AuthState.twoFactorEmailFallback should be set from `methods.contains('email')`.

Adjacent (same flow, worth fixing in the same pass): verifyTwoFactor posts `{'code': code, 'backupCode': true}`, but the web posts `{method: 'totp'|'backup'|'email', code}` to /auth/2fa/verify, and reads the pending challenge (methods + email) from GET /auth/2fa/pending.

---

## [4] MAJOR · api-correctness

**File:** `lib/features/auth/data/auth_repository.dart`

POST /auth/2fa/verify in /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/data/auth_repository.dart:131-138 sends the wrong body. The backend contract, as exercised by the deployed web client, is `{method, code}` with `method` in `totp|backup|email`; the app sends `{code}` and, on the backup path, `{code, backupCode: true}` — a field the server does not read — while never sending the `method` field the server uses to select the factor. Every 2FA verification (TOTP, backup code, and emailed code) is therefore sent without the factor selector.

**Fix:**

Thread a `method` string through instead of the `backupCode` bool.

1. /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/data/auth_repository.dart:130-139 — replace with:

```dart
/// Completes a 2FA challenge. [method] is one of `totp`, `backup`, `email`.
Future<AppUser> verifyTwoFactor({
  required String code,
  String method = 'totp',
}) async {
  final json = await _api.postJson(
    Endpoints.twoFactorVerify,
    body: {'method': method, 'code': code},
  );
  return AppUser.fromJson(J.map(json));
}
```

2. /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/presentation/auth_providers.dart:136-142 — change the signature to `Future<bool> verifyTwoFactor(String code, {String method = 'totp'})` and pass `method: method` to the repository.

3. /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/presentation/two_factor_screen.dart — replace `bool _useBackupCode` with `String _method = 'totp'`; the toggle button sets `_method = _method == 'backup' ? 'totp' : 'backup'`; `_emailCode()` must also set `_method = 'email'` after the /auth/2fa/email call so the emailed OTP is verified against the email factor and not the TOTP secret; `_submit()` passes `method: _method`. Derive the label/keyboard/formatter branches from `_method == 'backup'` rather than the removed bool.

To make that path actually reachable, also add `requires2fa` to the key list in `_looksLikeTwoFactorChallenge` (auth_repository.dart:66-73) and carry the response's `methods` array into `SignInNeedsTwoFactor` so the screen only offers the factors the server allows — mirroring the web client's `g.includes("email")` gate on the "Email me a code" button.

---

## [5] MAJOR · api-correctness

**File:** `lib/features/accounts/presentation/account_form_sheet.dart`

lib/features/accounts/presentation/account_form_sheet.dart writes four keys that POST/PATCH /accounts does not accept. _buildBody lines 352-354 add 'institution', 'last4', 'note' via _putText, and line 358 adds 'creditLimit'; all four have live inputs (Institution 176-183, Last 4 digits 185-196, Credit limit 197-209 for card type, Note 211-218). The server's Zod schema for /accounts is {name, type, initialBalance, currency, color, icon, includeInTotal}; unknown keys are stripped. Verified live: a POST carrying all four came back as a document containing none of them. Account.fromJson (lib/features/accounts/domain/account.dart:53,54,57,60) reads the same four keys back, so they are permanently null and account_tile.dart:120-123 / :99-102 and account_picker.dart:338-341 never render them. User-visible effect: the user types a bank name, card last-4, credit limit or note, the sheet pops with success (line 295 Navigator.pop(true)), and reopening the sheet shows the fields blank. The same function has the identical bug for two more fields: line 347 sends 'openingBalance' (server key is 'initialBalance') and line 349 sends 'excludeFromTotal' (server key is 'includeInTotal', inverted), both silently dropped — verified in the same probe, which returned initialBalance:0 after 777 was sent and includeInTotal:true after excludeFromTotal:true was sent.

**Fix:**

In lib/features/accounts/presentation/account_form_sheet.dart: (1) delete the four unsupported inputs and their state — controllers _institution/_last4/_creditLimit/_note (lines 49-62), their dispose calls (79-82), and the AppTextField blocks at 176-183, 185-196, 197-209 and 211-218 with the adjacent SizedBox spacers; (2) delete lines 352-359 of _buildBody. (3) Replace them with the two schema fields the sheet currently never lets the user set: a color picker writing body['color'] (hex string, server default '#2563EB') and an icon picker writing body['icon'] (string, server default 'wallet'), matching the web form. (4) Fix the two mis-named keys in the same map: line 347 becomes 'initialBalance': _parseAmount(_openingBalance.text) ?? 0, and line 349 becomes 'includeInTotal': !_excludeFromTotal. In lib/features/accounts/domain/account.dart: drop the institution/last4/note/creditLimit fields (declarations 12-13, 15, 19; getters 33-34, 37, 40; fromJson 53-54, 57, 60; toWriteJson 70-71, 74, 76), rename openingBalance -> initialBalance reading json['initialBalance'] (line 50) and replace excludeFromTotal with includeInTotal reading json['includeInTotal'] defaulting true (line 58). Then update the read sites that can no longer be populated: lib/features/accounts/presentation/widgets/account_tile.dart:99-102 (credit-limit chip) and :120-123 (institution / last4 subtitle), lib/features/transactions/presentation/widgets/account_picker.dart:338-341 (institution / last4 subtitle), plus the excludeFromTotal uses at accounts_screen.dart:254, 482, 499 and account_tile.dart:124, 149 and dashboard/presentation/widgets/accounts_preview_card.dart:81. Finally correct the fixture JSON in test/screen_layout_test.dart:262-271 so it mirrors a real /accounts document ({_id,name,type,initialBalance,currency,color,icon,includeInTotal,archived,order,system,createdAt,updatedAt}) — the current fixture invents institution/last4/creditLimit and is what let the bug ship.

---

## [6] MAJOR · runtime-crash

**File:** `lib/core/utils/date_x.dart`

`DateTimeX.addMonths` in /Users/nagarajan/playground/CoinCompass-Mobile/lib/core/utils/date_x.dart:91-97 uses truncating division for the year carry:

```dart
final total = month - 1 + months;
final y = year + (total ~/ 12);
final m = total % 12 + 1;
```

Dart's `~/` truncates toward zero while `%` is always non-negative for a positive divisor, so whenever `total < 0` the month wraps to December but the year is never decremented. For January with `months == -1`: `total == -1`, `-1 ~/ 12 == 0`, `-1 % 12 == 11` → `y == year`, `m == 12`. Verified with `dart run`: `DateTime(2026,1,15).addMonths(-1)` returns `2026-12-15`, and repeated back-stepping from 2026-08-15 cycles `2026-7 … 2026-1, 2026-12, 2026-11, …` forever inside 2026, never reaching 2025. Forward stepping is correct (`2026-12 +1 → 2027-1`), and the short-month clamp is correct.

The only caller is MonthPager's left chevron (lib/core/widgets/month_pager.dart:43, `onChanged(month.addMonths(-1))`), mounted on the Transactions ledger at lib/features/transactions/presentation/transactions_screen.dart:290-294. `_onMonthChanged` (:103-106) stores the bad month in `transactionsMonthProvider` and `_applyMonth` (:100-102) rewrites the query to `from: month.startOfMonth, to: month.endOfMonth`. Nothing downstream clamps: `TransactionQuery.toQuery()` (lib/features/transactions/data/transactions_repository.dart:56+) emits `from`/`to` verbatim as ISO-8601, and the month-grid picker (:203-209) builds `DateTime(year, month)` directly so it never masks the chevron path. Result: tapping the left chevron in January relabels the header "December 2026" (DateX.monthLabel at :236) and silently fetches a FUTURE month's transactions while the user believes they stepped back a month; the previous year is unreachable via the chevrons.

Note: the reviewer's category label `runtime-crash` is inaccurate — nothing throws. It is a silent correctness/wrong-data bug. Severity major is right.

The only existing coverage, test/money_test.dart:68-70, asserts `DateTime(2026,1,31).addMonths(1) == DateTime(2026,2,28)` — forward only, so nothing catches this.

**Fix:**

In /Users/nagarajan/playground/CoinCompass-Mobile/lib/core/utils/date_x.dart:93, replace the truncating year carry with floor division. `total % 12` is already correct for negatives in Dart (always 0..11), so only the `y` line changes:

```dart
DateTime addMonths(int months) {
  final total = month - 1 + months;
  final y = year + (total - (total % 12)) ~/ 12; // floor division: -1 -> -1, not 0
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, day > lastDay ? lastDay : day, hour, minute);
}
```

(`(total / 12).floor()` is equivalent and equally acceptable.)

Verified with `dart run`: back-stepping from 2026-08-15 now yields `2026-7 … 2026-1, 2025-12, 2025-11, …`; `DateTime(2026,1,15).addMonths(-13)` → `2024-12-15`; `DateTime(2026,3,31).addMonths(-1)` → `2026-02-28`; forward stepping and the `Jan 31 +1 → Feb 28` clamp are unchanged.

Also add a regression test next to test/money_test.dart:68-70:

```dart
expect(DateTime(2026, 1, 15).addMonths(-1), DateTime(2025, 12, 15));
expect(DateTime(2026, 1, 15).addMonths(-13), DateTime(2024, 12, 15));
```

---

## [7] MAJOR · runtime-crash

**File:** `lib/features/transactions/presentation/transactions_screen.dart`

lib/features/transactions/presentation/transactions_screen.dart:240-244 seeds the end-of-day running balance from the unparameterised, all-time `GET /transactions/balance`, and `_buildEntries` (:422-441) rolls it backwards over only the rows the current query returned. Two real consequences: (1) any month other than the current one shows today's balance on its newest day and every older day's figure is shifted by the same error, because the reference implementation fetches `GET /transactions/balance?asOf=<range end>` and this port never sends `asOf`; (2) with a type / category / tag / one-off / search filter active, `_accountDelta` sums only the matching rows, so each footer below the first is off by the filtered-out movements — the web app suppresses the footers entirely in exactly that case.

**Fix:**

Two changes, both mirroring the web implementation.

1) Seed from an as-of snapshot.
- In lib/features/transactions/data/transactions_repository.dart, change `Future<BalanceSnapshot> balance()` to `Future<BalanceSnapshot> balance({DateTime? asOf})` and pass `query: {if (asOf != null) 'asOf': DateX.toApi(asOf)}` to `_api.getJson(Endpoints.transactionsBalance, ...)`.
- In lib/features/transactions/presentation/transactions_providers.dart, keep the existing param-less `transactionBalanceProvider` (accounts_screen.dart, accounts_preview_card.dart, account_picker.dart legitimately want the live balance) and add `final transactionBalanceAsOfProvider = FutureProvider.family<BalanceSnapshot, DateTime?>((ref, asOf) => ref.watch(transactionsRepositoryProvider).balance(asOf: asOf));`.
- In transactions_screen.dart:230, watch `transactionBalanceAsOfProvider(query.to)` instead, and add `ref.invalidate(transactionBalanceAsOfProvider)` alongside the existing invalidation in `_refresh()` (:126) and wherever a write invalidates `transactionBalanceProvider` (transaction_form_sheet.dart:439, quick_add_row.dart:101/125/139, transaction_row.dart:196/210).

2) Drop the footers under a restrictive filter.
In transactions_screen.dart:238-244, gate the seed the way the web's `J = !!accounts && !B` does:

    final restrictive = query.type != null ||
        query.categoryId != null ||
        query.tag != null ||
        query.oneoff != null ||
        (query.search?.trim().isNotEmpty ?? false);
    final startBalance = (balance == null || restrictive)
        ? null
        : (accountId == null ? balance.balance : (balance.byAccount[accountId] ?? 0));

`_buildEntries` already emits no `_DayFooterEntry` when `startBalance` is null, so no other change is needed. Leave the account-only filter path enabled — that is the web's `restrictTo` case and its per-account rollback is well defined. Leave `_accountDelta`'s null-account skip exactly as it is.

---

## [8] MINOR · runtime-crash

**File:** `lib/features/auth/presentation/auth_providers.dart`

Stale shared auth error leaks across auth screens (not a crash). `AuthState.error` lives on the app-scoped `authControllerProvider` and is reset only when the next auth request starts; `AuthController.clearError()` is dead code. All four auth screens render that same error in `build` with no reset on mount, so an error produced on one screen is displayed by the next one the user opens. Concretely: a failed sign-in on /login sets `error`; tapping "Sign up" (login_screen.dart:152, `context.push('/signup')`) or "Forgot password?" (login_screen.dart:81) mounts SignupScreen/ForgotPasswordScreen already showing that sign-in failure — as an `AuthErrorBanner` when the error is non-validation (401 "invalid credentials", 429 "Too many attempts. Please wait a moment and try again.", 5xx, "No connection…"), or as stale `errorText` on the email/password fields of the blank form when the error was a Zod VALIDATION_FAILED with fieldErrors. It leaks in both directions and on pop: a failed sign-up leaks onto /login via signup_screen.dart:126 (`context.go('/login')`) or the back arrow at signup_screen.dart:61 (`context.pop()`), and a failed forgot-password leaks back onto /login via forgot_password_screen.dart:50/64/76. Both halves of the banner/field split are exclusive, so only one of the two shows for a given error — but one of them always does.

**Fix:**

Call the existing-but-unused `AuthController.clearError()` on every navigation edge between auth screens, so the error is dropped before the next screen builds (no one-frame flash of the stale banner). In lib/features/auth/presentation: login_screen.dart:81 and :152 — change the `onTap` bodies to `() { ref.read(authControllerProvider.notifier).clearError(); context.push('/forgot-password'); }` and `... context.push('/signup'); }` respectively, and do the same before `context.go('/login/2fa')` at login_screen.dart:42; signup_screen.dart:61 (`onBack`) and :126 (the "Sign in" `onTap`); forgot_password_screen.dart:50 and :76 (`onBack`) and :64 ("Back to sign in"); two_factor_screen.dart:65 (`onBack`). More robust alternative that cannot be defeated by a future navigation path being added without the call: give each of the four screens an `initState` that schedules `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) ref.read(authControllerProvider.notifier).clearError(); });` — the post-frame hop is required because mutating a watched StateNotifier during the first build throws "Tried to modify a provider while the widget tree was building". Either way, keep the existing `clearError: true` calls in signIn/signUp/verifyTwoFactor/forgotPassword — they handle the same-screen retry case.

---

## [9] MAJOR · riverpod

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/transactions/presentation/widgets/transaction_row.dart`

Swipe-to-delete (lib/features/transactions/presentation/widgets/transaction_row.dart:196-197, and its Undo branch at :210-211) and the one-tap quick-add template post (lib/features/transactions/presentation/widgets/quick_add_row.dart:125-126, and its Undo delete at :137-138) invalidate only transactionBalanceProvider and transactionsPageProvider. They never invalidate accountsProvider, which is a session-lifetime non-autoDispose cache (lib/features/accounts/data/accounts_repository.dart:69) holding the server-computed per-account `balance` field. Because resolveAccountBalance (lib/features/accounts/presentation/widgets/account_tile.dart:148) and the dashboard card (lib/features/dashboard/presentation/widgets/accounts_preview_card.dart:78-81) both read `account.balance` FIRST and only fall back to the /transactions/balance byAccount map, every account balance on the Accounts screen and the dashboard Accounts card — plus the Total balance / Assets / Liabilities figures derived from them in AccountTotals.of (lib/features/accounts/presentation/accounts_screen.dart:492-511) — keeps showing the pre-write number until the user manually pull-to-refreshes /accounts or the dashboard, or happens to save a transaction through the full form sheet (which does invalidate accountsProvider at transaction_form_sheet.dart:441). The full-sheet fallback inside quick_add_row.dart `_run` (:96-103) is NOT affected, since the sheet's own `_invalidateDerived()` covers it.

**Fix:**

Invalidate accountsProvider everywhere a transaction is written, not just in the form sheet. Concretely: (1) In lib/features/transactions/presentation/widgets/transaction_row.dart, add `import '../../../accounts/data/accounts_repository.dart';` and add `container.invalidate(accountsProvider);` alongside the existing two invalidations at both :196-197 (post-delete) and :210-211 (post-restore/undo). (2) In lib/features/transactions/presentation/widgets/quick_add_row.dart (accounts_repository.dart is already imported), add `container.invalidate(accountsProvider);` alongside the existing two invalidations at both :125-126 (after repository.create) and :137-138 (after the undo repository.delete). Preferred non-duplicating form: promote transaction_form_sheet.dart's `_invalidateDerived()` into a shared top-level helper in lib/features/transactions/presentation/transactions_providers.dart, e.g. `void invalidateTransactionDerived(ProviderContainer container, {bool tags = false}) { container..invalidate(transactionBalanceProvider)..invalidate(transactionsSummaryProvider)..invalidate(accountsProvider)..invalidate(transactionsPageProvider); if (tags) container.invalidate(transactionTagsProvider); }` and call it from all four sites above plus transaction_form_sheet.dart:438-446, so no future write path can drift out of sync again.

---

## [10] MAJOR · riverpod

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/categories/presentation/category_form_sheet.dart`

In four write paths the Riverpod cache invalidation is placed after the network `await` but before the `if (!mounted) return;` guard, so if the modal sheet is dismissed while the request is in flight the call executes on a disposed `WidgetRef` and throws `StateError: Cannot use "ref" after the widget was disposed.` — before `_container.invalidate` runs, so the cache is never invalidated. Sites: /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/categories/presentation/category_form_sheet.dart:161 (`_save`) and :193 (`_delete`), and /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/accounts/presentation/account_form_sheet.dart:293 (`_submit`) and :327 (`_delete`). Both sheets are dismissible during the save — `showModalBottomSheet` is called with only `isScrollControlled: true` (category_form_sheet.dart:81, account_form_sheet.dart:29), so the scrim tap and drag-down stay live and the Android back button pops the route; there is no PopScope anywhere in lib/. The close IconButton is disabled while `_busy` (category_form_sheet.dart:233), which only makes the gap in the other dismissal paths clearer. Consequences differ per file. In account_form_sheet the bare `catch (error)` (:294, :328) funnels the StateError through `ApiException.from`, which wraps any unknown error as `ApiException(message: error.toString())` (api_exception.dart:69), and the following `if (!mounted) return;` drops it: the account is created/updated/deleted server-side, `accountsProvider` is never invalidated, and nothing is surfaced. In category_form_sheet the catch is narrowed to `on ApiException` (:164, :196), so the StateError propagates out of `_save`/`_delete`; `AppButton.onPressed` is a `VoidCallback?` (app_button.dart:17) so the Future is discarded and it becomes an uncaught async error in the root zone (logged, not a crash — main.dart installs no zone guard). Because `categoriesProvider` and `accountsProvider` are intentionally non-autoDispose, session-lifetime FutureProviders (categories_repository.dart:66-70, accounts_repository.dart:65-70) and neither screen re-invalidates on sheet close (categories_screen.dart:39-52 shows only a snackbar; accounts_screen.dart:74-82 invalidates `transactionBalanceProvider` and only when the sheet returned `true`, whereas a scrim dismiss returns null), the newly written record stays invisible on the Accounts/Categories screens, the dashboard and every account/category picker until the user manually pull-to-refreshes.

**Fix:**

Capture a ref that outlives the widget before the `await`, and invalidate through that. In each of the four methods, take the container while the element is still mounted and use it after the network call, e.g. in `category_form_sheet.dart _save()`:

    final container = ProviderScope.containerOf(context, listen: false); // before any await
    try {
      final repo = ref.read(categoriesRepositoryProvider);
      ...
      await repo.create(body);           // or repo.update(...)
      container.invalidate(categoriesProvider);   // no mounted assertion; safe post-dispose
      if (!mounted) return;
      Navigator.of(context).pop(CategorySheetResult.saved);
    } on ApiException catch (error) { ... }

`ProviderContainer.invalidate` has no disposal assertion and the root container lives for the app's lifetime, so this both stops the throw and preserves the evident intent of refreshing even when the sheet was dismissed. Apply the same shape at category_form_sheet.dart:193 (`_delete`, capturing the container before the `ConfirmSheet.show` await) and at account_form_sheet.dart:293 and :327 for `accountsProvider`.

Minimal alternative if you accept losing the refresh on dismissal: move each `ref.invalidate(...)` to after `if (!mounted) return;`, matching the existing correct ordering at transaction_form_sheet.dart:393-394. This removes the StateError but leaves the list stale when the user dismisses mid-save.

Independently worth doing (not a substitute): make the sheets non-dismissible while a write is in flight — pass `isDismissible: false, enableDrag: false` and wrap the body in `PopScope(canPop: !_busy)` — and have `categories_screen._openSheet` / `accounts_screen._openForm` invalidate their provider on return regardless of the popped value, as defence in depth.

---

## [11] MINOR · riverpod

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/transactions/presentation/transaction_form_sheet.dart`

The dashboard's Net worth hero renders `netWorthHistoryProvider.valueOrNull!.last.netWorth` (net_worth_card.dart:24-32), but `netWorthHistoryProvider` (networth_repository.dart:31) is a plain, non-autoDispose `FutureProvider` — a process-lifetime session cache — and no write path invalidates it: not `_invalidateDerived()` (transaction_form_sheet.dart:438-446), not transaction_row.dart:196/210, not quick_add_row.dart:101/125/139, not account_form_sheet.dart:293/327, not accounts_screen.dart:65. Its three dashboard siblings (`dashboardSummaryProvider`/`dashboardTrendProvider`/`dashboardCategoryProvider`, dashboard_screen.dart:34/45/56) are `.autoDispose`, and the shell is a plain `ShellRoute` with `GoRoute(builder:)` (app_router.dart:155-162), so leaving `/` unmounts DashboardScreen and those three refetch on return while the net-worth read does not. Result: after any transaction or account write the Income/Expense/Net cards show fresh numbers and the Net worth card directly below them keeps showing the pre-write figure, until pull-to-refresh (`refreshDashboard`, dashboard_screen.dart:148) or the card's own error retry (net_worth_card.dart:44).

**Fix:**

Treat the net-worth read like every other session cache in this codebase — invalidate it on the writes that move it, mirroring the web app's `Yt()`:

1. transaction_form_sheet.dart `_invalidateDerived()` (line 438-446): add `ref.invalidate(netWorthHistoryProvider);` (import `../../networth/data/networth_repository.dart`).
2. Add `container.invalidate(netWorthHistoryProvider);` next to each existing `invalidate(transactionBalanceProvider)`: transaction_row.dart:196 (delete) and :210 (undo/restore); quick_add_row.dart:101 (sheet save), :125 (quick create), :139 (undo delete).
3. Add `ref.invalidate(netWorthHistoryProvider);` next to `ref.invalidate(accountsProvider)` in account_form_sheet.dart:293 and :327, and in accounts_screen.dart:65 (account delete) — opening balances and account deletes move net worth too.

Minimal alternative (one line, if the fuller change is out of scope for this pass): change networth_repository.dart:31 to `final netWorthHistoryProvider = FutureProvider.autoDispose<List<NetWorthPoint>>(...)`, which makes the hero refetch on each dashboard mount exactly like its three siblings. That covers today's flows because `AddSheet` always leaves `/` before opening the form, but it still leaves a same-screen write stale, so option 1-3 is the durable fix; doing both matches the reference web behaviour.

Optional, and worth flagging separately: net_worth_card.dart:28-32 prefers `history.last.netWorth` over `summary.netWorth`, while the web dashboard's hero renders `summary.netWorth` (bundle: `t.jsx(yt,{value:c.summary.netWorth,id:"dash-networth"…})`). In the captured live data those two disagree outright (reports_summary `netWorth: 0` vs history `-20000000`), so preferring the summary and falling back to the snapshot would both match the reference and drop this cache off the hero's critical path.

---

## [12] MAJOR · design

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/core/widgets/app_button.dart`

`AppButton(expand: false)` does not produce a compact button: the shared theme's `minimumSize: Size.fromHeight(48)` (an infinite minimum width) makes `ButtonStyleButton`'s internal ConstrainedBox clamp minWidth up to the parent's maxWidth, so the button fills all available width. Measured: 768.0px wide inside a 768px-wide parent. Visible on Transactions (`transactions_screen.dart:279-286`, the "Add" CTA) and Categories (`categories_screen.dart:106-113`, the "New category" CTA), which render a full-width blue bar instead of the label-hugging pill in shots/transactions.png (~20% of viewport) and shots/categories.png (~36%). accounts_screen.dart:104-123 already bypasses AppButton with a raw FilledButton for exactly this reason, and its comment at lines 109-113 names the same root cause.

**Fix:**

Fix it once in /Users/nagarajan/playground/CoinCompass-Mobile/lib/core/widgets/app_button.dart so every caller benefits: when `expand` is false, pass a style that overrides only the sizing (all colours/shape/textStyle still resolve from the theme, because widget.style merges per-property over themeStyleOf).

In `build`, before constructing `button`:

    final compact = expand
        ? null
        : ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );

then pass `style: compact` to the FilledButton and OutlinedButton cases (the TextButton case needs no change — textButtonTheme sets no minimumSize — but passing it is harmless). Line 56 stays as-is:

    return expand ? SizedBox(width: double.infinity, child: button) : button;

Height 46 and horizontal padding 18 reproduce the existing accounts workaround exactly; use Size(0, 48) if you prefer to keep the theme's 48dp height. After this, delete the raw `FilledButton.icon` workaround at accounts_screen.dart:104-123 (and its 109-113 comment) and replace it with `AppButton(label: 'New account', icon: LucideIcons.plus, expand: false, onPressed: onAdd)` so all three CTAs share one implementation.

---

## [13] MAJOR · design

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/categories/domain/category.dart`

In /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/categories/domain/category.dart:61-76, `categoryGroupLabels` diverges from the deployed app's group dictionary in two ways. Five of the fourteen labels are wrong — `bills` ("Bills" vs "Bills & Subscriptions"), `savings` ("Savings" vs "Savings & Deposits"), `debt_transfers` ("Debt & Transfers" vs "Loans & Transfers"), `returns` ("Returns" vs "Returns & Interest"), and `inflows` ("Inflows" vs "Other Inflows") — and the two income keys are declared in the wrong sequence (`inflows` before `returns`, while the web seeds returns=order 1... wait, earnings=1, returns=2, inflows=3). Because this map is the sole label source and its key order drives section ordering, the wrong text appears on the Categories screen group headers (categories_screen.dart:185), the dashboard spending donut's Groups mode rows and legend (spending_donut_card.dart:356), the transaction category picker's section labels and its search matching (category_picker.dart:211, :241), and the category form's Group dropdown (category_form_sheet.dart:306); the key-order swap additionally mis-sorts the Income tab sections (categories_screen.dart:172) and the income picker sections (category_picker.dart:236).

**Fix:**

Replace the map body at lib/features/categories/domain/category.dart:61-76 so the labels and the income key order match the deployed dictionary:

const Map<String, String> categoryGroupLabels = {
  'food': 'Food',
  'transport': 'Transport',
  'home': 'Home',
  'bills': 'Bills & Subscriptions',
  'health': 'Health',
  'education': 'Education',
  'lifestyle': 'Lifestyle',
  'family_giving': 'Family & Giving',
  'savings': 'Savings & Deposits',
  'debt_transfers': 'Loans & Transfers',
  'earnings': 'Earnings',
  'returns': 'Returns & Interest',
  'inflows': 'Other Inflows',
  'other': 'Other',
};

Three edits in substance: (1) fix the five label strings — bills -> 'Bills & Subscriptions', savings -> 'Savings & Deposits', debt_transfers -> 'Loans & Transfers', returns -> 'Returns & Interest', inflows -> 'Other Inflows'; (2) move the 'returns' entry above 'inflows' so the declared key order is earnings, returns, inflows, matching the web seed orders (earnings=1, returns=2, inflows=3) that categories_screen.dart:172 and category_picker.dart:236 rely on; (3) leave 'other' last and leave the ten expense keys in their existing order, which already matches the seed's expense orders 1-10. No consumer needs changing — all four read through this map. The doc comment above it ("Human labels for the 14 `group` values the API seeds") stays accurate.

---

## [14] MAJOR · design

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/transactions/presentation/transactions_screen.dart`

On the Transactions screen, any change to the query window — MonthPager chevron/month picker, any of the four TransactionFilters dropdowns, or the debounced search box — repaints the header for the NEW window while the body keeps rendering the OLD window's day headers, rows and end-of-day balances, with no loading affordance anywhere, until the fetch returns. Mechanism: transactionsListProvider is a non-family, non-autoDispose StateNotifierProvider that captures the query via ref.read and reacts through ref.listen -> applyQuery, so the controller (and its items) survives a query change; applyQuery (transactions_providers.dart:206-213) preserves items/total and refresh() (149-156) sets loading:true while preserving them too, making isInitialLoad (`loading && items.isEmpty`, line 86) false, so the skeleton gate at transactions_screen.dart:327 is skipped and the else branch at 352 renders stale rows. Simultaneously the subtitle at 234-236 combines the already-updated month (from transactionsMonthProvider, set synchronously at 104-107) with the stale state.total, producing e.g. "2 transactions · September 2026" directly above a "Tuesday, 04 Aug 2026" day header. Secondary effect: those stale rows remain tappable and _openSheet (135-156) evaluates visibility against the NEW query, so editing one during the window takes the controller.deleteLocal branch. Net effect: of the four required states, the loading state is reachable only on the very first load of the session.

**Fix:**

Two changes, both small.

(1) lib/features/transactions/presentation/transactions_providers.dart — in `applyQuery` (206-213), drop the previous window's accumulated rows when the query actually changes, so the state matches the query it is stamped with:

    void applyQuery(TransactionQuery query) {
      final next = query.firstPage();
      if (next == _query) return;
      _query = next;
      state = state.copyWith(
        items: const [],
        total: 0,
        query: next,
        loading: true,
        loadingMore: false,
        hasMore: false,
        page: 1,
        clearError: true,
      );
      onQueryChanged?.call(next);
      refresh();
    }

`copyWith` already accepts non-null `items`/`total`, so this needs no signature change. With items empty, `isInitialLoad` becomes true and transactions_screen.dart:327 renders `_LoadingList` for the whole re-query; the else branch at 352 can no longer paint the previous window. Pull-to-refresh is unaffected — `_refresh()` (transactions_screen.dart:125-130) calls `refresh()` directly, which still keeps items, preserving the documented no-blank behaviour at 147-148. `showEmptyState` (`!loading && !hasError && items.isEmpty`) stays correct because `loading` is true throughout.

(2) lib/features/transactions/presentation/transactions_screen.dart — stop pairing the new month with a count that is stale (before the fix) or 0 (after it). Replace lines 234-236 with:

    final loadingWindow = state == null || state.loading;
    final count = state?.total ?? 0;
    final subtitle = loadingWindow
        ? DateX.monthLabel(month)
        : '$count transaction${count == 1 ? '' : 's'} · ${DateX.monthLabel(month)}';

If the team deliberately wants stale-while-revalidate instead of a skeleton, the acceptable alternative is to keep (1) as-is but add an explicit in-flight affordance — e.g. a sliver `LinearProgressIndicator` (or dimmed list) rendered when `state.loading && !state.isInitialLoad` — plus (2); what is not acceptable is the current combination of stale rows, a new-month header, and zero loading feedback.

---

## [15] MINOR · design

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/core/utils/lucide_map.dart`

lucideIcon() cannot resolve 'smartphone', the icon name AccountType.upi returns (lib/core/api/enums.dart:60), because _lucideByName in lib/core/utils/lucide_map.dart:8-54 has no such key and the camel/snake normalisation at lines 65-69 cannot synthesise one. Every UPI account therefore renders the default LucideIcons.circle -- a bare outline circle -- instead of a phone glyph, at: lib/features/accounts/presentation/account_form_sheet.dart:155 (the UPI row of the Type dropdown, unconditional), lib/features/transactions/presentation/widgets/account_picker.dart:178 and :359 (CategoryAvatar with account.type.icon, unconditional, ignores account.icon), lib/features/accounts/presentation/widgets/account_tile.dart:52, lib/features/dashboard/presentation/widgets/accounts_preview_card.dart:103, and lib/features/transactions/presentation/widgets/transaction_filters.dart:83 (these three fall back to type.icon whenever the server did not store a per-account icon). All six other AccountType icon names resolve, so the UPI entry is the lone blank glyph in an otherwise fully iconified type list.

**Fix:**

Add the missing key to _lucideByName in /Users/nagarajan/playground/CoinCompass-Mobile/lib/core/utils/lucide_map.dart. In the "app chrome + defaults" block (after line 44, 'landmark': LucideIcons.landmark,) insert:

  'smartphone': LucideIcons.smartphone,

LucideIcons.smartphone is defined in the pinned lucide_icons_flutter 3.1.17 (lib/lucide_icons.dart:102288), so no dependency change is needed. Optionally also add the other AccountType-adjacent aliases for symmetry, but the single 'smartphone' entry fixes all six call sites, since they all route through lucideIcon().

---

## [16] MINOR · design

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/transactions/presentation/widgets/transaction_row.dart`

Income rows in the Transactions ledger omit the leading `+`. lib/features/transactions/presentation/widgets/transaction_row.dart:128-136 calls MoneyText without `signed:`, which defaults to false (money_text.dart:15), and Money.format only prefixes `+` when `signed && amount > 0` (money.dart:36). Because Transaction.signedAmount is positive for income, an income row renders `₹5,000` instead of the spec's `+₹5,000` (SPEC.md:158). Expenses are unaffected — their `−` comes from the negative value. The result is two different formats for the same money in two places the user sees together: the dashboard's Recent card renders `+₹5,000` (recent_transactions_card.dart:128, `signed: !transfer`), and the Transactions screen's own day header renders `Net +₹5,000` (transactions_screen.dart:538, `signed: true`) directly above rows that render `₹5,000`.

**Fix:**

In /Users/nagarajan/playground/CoinCompass-Mobile/lib/features/transactions/presentation/widgets/transaction_row.dart, add the `signed` flag to the amount MoneyText (lines 128-136), guarding transfers exactly as the dashboard card does:

                      MoneyText(
                        t.signedAmount,
                        tone: tone,
                        signed: !t.isTransfer,
                        compactAbove: Money.crore,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

`!t.isTransfer` is required rather than a plain `signed: true`: Transaction.signedAmount is positive for transfers as well as income (transaction.dart:71), so an unguarded flag would stamp a misleading `+` on transfer rows. With the guard, income becomes `+₹5,000`, expense stays `−₹5,000` (unconditional minus), and transfers stay `₹5,000` in neutral tone. No other file needs to change; the `compactAbove: Money.crore` path still drops the sign for amounts ≥ ₹1Cr because Money.compact never emits `+`, but the dashboard card has the identical behaviour, so the two views stay consistent there.

---

## [17] MAJOR · layout

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/core/widgets/app_scaffold.dart`

`_NavItem` (lib/core/widgets/app_scaffold.dart:319-333) is a `mainAxisSize.max` Column of a fixed 21dp icon + 3dp gap + an 11sp `Text` with no `maxLines`, `overflow`, or `FittedBox`, laid out in a 72dp-wide slot inside `SizedBox(height: 62)` (line 229). The label also inherits `height: 1.45` from `bodyMedium` (lib/core/theme/app_theme.dart:238). At Android's standard "Largest" font setting (textScale 1.3) "Dashboard" (75.4dp) and "Transactions" (89.6dp) exceed the 72dp slot, wrap to two 21dp lines, and the Column needs 66dp in a 62dp box — 2 x "A RenderFlex overflowed by 4.0 pixels on the bottom" on every one of the 17 shell screens (10px at 1.5, up to 58px at 2.0). In release the Flex clips hard-edge and centering collapses, so the nav item jams against the top of the bar with the bottom of its second label line cut off.

**Fix:**

In `_NavItem.build` (lib/core/widgets/app_scaffold.dart:324-331), replace the bare `Text` with a single-line, scale-down label wrapped in `Flexible`:

```dart
Flexible(
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      destination.label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,               // don't inherit bodyMedium's 1.45
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        color: color,
      ),
    ),
  ),
),
```

`maxLines: 1` + `softWrap: false` stops the wrap, `FittedBox(scaleDown)` shrinks an over-wide scaled label to the 72dp slot, `Flexible` guarantees the Column can never exceed 62dp, and the explicit `height: 1.2` drops the inherited 1.45 leading. I verified this exact tree at 360x800 with Inter loaded: 0 overflows at scales 1.0, 1.3, 1.5 and 2.0, versus 2/2/3 overflows for the current code at 1.3/1.5/2.0.

(A one-line `maxLines: 1, overflow: TextOverflow.ellipsis` also kills the RenderFlex error, but it renders "Transacti…" at 1.3 — the FittedBox keeps the word whole.)

---

## [18] MAJOR · layout

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/core/widgets/more_sheet.dart`

/Users/nagarajan/playground/CoinCompass-Mobile/lib/core/widgets/more_sheet.dart:186-223 — AddSheet.build returns SafeArea > Column(mainAxisSize: min) holding a header, seven ListTiles and a 12dp tail, with no height cap and nothing scrollable. Opened with isScrollControlled: true (line 129-133) under a theme that adds a 48dp drag-handle inset, the Column is handed the whole remaining viewport height and needs 446dp. On any phone in landscape it overflows (134px at 800x360, 82px at 915x412) and the last menu rows — Loan and Credit, plus Goal on shorter devices — are laid out below the screen edge, cannot be scrolled to, and cannot be tapped. Those two destinations are unreachable from the FAB menu whenever the device is rotated.

**Fix:**

Give AddSheet the same treatment MoreSheet already has (same file, lines 25-51): cap the height and make the rows a scroll view. Replace the body of AddSheet.build with

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(   // unchanged 'Add' header
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final item in _items)
                    ListTile(... unchanged tile body ...),
                ],
              ),
            ),
          ],
        ),
      ),
    );

The Flexible + ListView is the load-bearing part (the ConstrainedBox alone would still overflow); the trailing SizedBox(height: 12) becomes the ListView's bottom padding. Verified equivalent shape: MoreSheet with 14 rows measures 280.8dp and scrolls cleanly at 800x360 with zero overflow errors. Worth adding a landscape case (e.g. 800x360) that opens AddSheet to test/screen_layout_test.dart, since that suite currently only pumps 360x800 portrait.

---

## [19] MAJOR · layout

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/presentation/login_screen.dart`

The auth footer rows put two intrinsically-sized `Text`s in a fixed-width `Row` with no flex or wrapping, so both auth screens throw a RenderFlex overflow at the largest ordinary system font setting.

- `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/presentation/login_screen.dart:144-163` — `Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Don't have an account? "), GestureDetector(child: Text('Sign up'))])`
- `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/auth/presentation/signup_screen.dart:118-137` — the same shape with 'Already have an account? ' / 'Sign in'

The Row is a child of a `CrossAxisAlignment.stretch` Column inside an `AppCard(padding: EdgeInsets.all(20))` inside `AuthScaffold`'s `EdgeInsets.symmetric(horizontal: 20)`, so on a 360dp screen it is tightly constrained to 280dp with no room to give. Measured at 360x800 with the bundled Inter faces: login overflows by 1.9 px at textScale 1.3, 44 px at 1.5, 150 px at 2.0; signup by 16 px at 1.3, 60 px at 1.5, 170 px at 2.0. Clean at 1.0 and 1.15.

**Fix:**

Let the footer wrap instead of forcing one line. In `login_screen.dart`, replace the `Row` at lines 144-163 with a `Wrap`:

    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(fontSize: 14, color: c.mutedForeground),
        ),
        GestureDetector(
          onTap: () => context.push('/signup'),
          child: Text(
            'Sign up',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.primary,
            ),
          ),
        ),
      ],
    )

and make the identical substitution in `signup_screen.dart:118-137` (`'Already have an account? '` / `'Sign in'`, `onTap: () => context.go('/login')`). `Wrap` measures children individually and moves the link to a second centred line once the pair exceeds 280dp, keeping the full sentence readable and the whole link hit-testable at every scale.

Do not "fix" this by wrapping the first Text in `Flexible` with `overflow: TextOverflow.ellipsis` — that truncates the prompt to "Don't have an acc…" while leaving the link on the same line, which is worse than wrapping. If you prefer a single text node, `Text.rich` with a `TapGestureRecognizer` on the link span plus `textAlign: TextAlign.center` also wraps correctly (remember to dispose the recognizer in `State.dispose`).

Since `test/screen_layout_test.dart` covers neither auth screen nor any non-default text scale, add the two screens to it and pump them under `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(1.3)))` — and 1.5 — so the regression is caught next time.

---

## [20] MINOR · layout

**File:** `/Users/nagarajan/playground/CoinCompass-Mobile/lib/features/accounts/presentation/accounts_screen.dart`

On devices whose bottom system inset exceeds 30dp (Android 3-button navigation = 48dp; marginally a 34dp home indicator), the Accounts and Categories lists scroll to a resting position where the last row is drawn underneath the shell's raised centre FAB. Both screens reserve a hard-coded 110dp tail — lib/features/accounts/presentation/accounts_screen.dart:70 `const SliverToBoxAdapter(child: SizedBox(height: 110))` and lib/features/categories/presentation/categories_screen.dart:63 `padding: const EdgeInsets.fromLTRB(16, 16, 16, 110)` — but because AppScaffold sets `extendBody: true`, the required clearance is `62 (nav bar) + MediaQuery.viewPaddingOf(context).bottom + FAB overhang`, i.e. 128dp at a 48dp inset. Measured on the real AppScaffold at 360x800 with a 48dp inset: Accounts overlaps by 18dp (the last tile's subtitle line, y 660-678, is partly under the FAB circle at x 150-210 / y 672-732) and Categories by 10dp, while Dashboard — which computes the same value instead of hard-coding it — clears by 10dp.

**Fix:**

Replace both hard-coded 110s with the inset-aware value Dashboard already computes, and hoist that computation so all three screens share one definition.

1. Add a single helper next to the shell it describes, in lib/core/widgets/app_scaffold.dart:

    /// Height the shell's bottom nav (62dp) plus the system inset plus the
    /// raised FAB's 18dp overhang occupy over the body, which renders with
    /// `extendBody: true`. Every scrollable screen must pad its tail by this.
    const double kShellNavBarHeight = 62;
    const double kShellFabClearance = 28; // 18dp overhang + 10dp breathing room

    double shellBottomInset(BuildContext context) =>
        kShellNavBarHeight +
        MediaQuery.viewPaddingOf(context).bottom +
        kShellFabClearance;

   Use `viewPaddingOf`, not `paddingOf`: inside a Scaffold body with `extendBody: true`, Flutter's `_BodyBuilder` rewrites `MediaQuery.padding.bottom` to `max(systemInset, bottomWidgetsHeight)` = 63 + inset, so `paddingOf` would double-count the nav bar.

2. lib/features/accounts/presentation/accounts_screen.dart:70 — drop the `const` and use the helper:

    SliverToBoxAdapter(child: SizedBox(height: shellBottomInset(context))),

   (`context` is already in scope in `build`; add the import of `../../../core/widgets/app_scaffold.dart`.)

3. lib/features/categories/presentation/categories_screen.dart:63 — drop the `const` and use the helper:

    padding: EdgeInsets.fromLTRB(16, 16, 16, shellBottomInset(context)),

4. lib/features/dashboard/presentation/dashboard_screen.dart:70-97 — delete the local `_navBarHeight` / `_fabClearance` constants and the inline `_navBarHeight + systemInset + _fabClearance` expression and call `shellBottomInset(context)` instead, so there is one definition rather than three. (Its current value is already correct, so this is a de-duplication, not a behaviour change.)

Optionally also normalise lib/features/transactions/presentation/transactions_screen.dart:369, which uses `MediaQuery.paddingOf(context).bottom + 96`. That over-pads rather than under-pads (206dp at a 48dp inset, because `paddingOf` already includes the 63dp nav bar) so it does not overlap, but it double-counts the nav bar and should become `shellBottomInset(context)` too.

Regression guard: test/screen_layout_test.dart mounts screens in a bare `Scaffold(body: screen)` (line 124), so it cannot see this class of bug. Add a case that wraps the screen in the real `AppScaffold`, sets `tester.view.padding`/`viewPadding` to `FakeViewPadding(bottom: 48)`, scrolls to the end, and asserts `tester.getRect(find.byType(AccountTile).last).bottom <= fabTop` (with the FAB rect derived from the nav bar's plus icon).

---

