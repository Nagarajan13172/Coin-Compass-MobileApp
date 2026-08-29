Two things for you to decide
Notifications are English while the app is Tamil. NotificationCopy is domain code — there's no widget tree in a notification, so nothing passes through the translating Text.
Amounts are now on your lock screen. Cash is overdrawn (−₹7,50,633) is visible without unlocking, in an app that has both an app lock and a wealth lock. Worth considering VISIBILITY_PRIVATE, or copy that names the event without the figure.






What's genuinely fine ✅
1,069 tests pass, 0 analyzer errors, all my commits are pushed. 7.3, 7.4 and 7.5 are built and device-verified. The two remaining warnings are pre-existing and cosmetic.

Major — and the biggest one isn't in this repo
1. Google sign-in is broken for every web user, right now. Your production server sends Google a redirect_uri of http://localhost:4000. Anyone clicking "Continue with Google" on the website consents and lands on a machine that isn't there. One-line config fix, highest impact of anything on this list, and nothing in this repo can do it.

2. User data is machine-translated app-wide — I only fixed the importer. _Verbatim exists in exactly one file. Every screen showing a payee, account, category or note has the same bug — Accounts, Categories, Budgets, Dashboard, Recurring, Transactions. On the device I watched ZZTest Alpha render as Zztest ஆல்பா and an account named Import Test display as இறக்குமதி சோதனை. The app currently shows names that differ from what's stored. That's a correctness problem, not cosmetics.

3. Two i18n systems coexist. 92 files on the runtime ML Kit path, but 8 files still call L.of, plus 478 live ARB keys, the generated lib/l10n/*, and dead 7.1b tooling (tool/i18n_scan.py, i18n_extract.py, i18n_coverage_test.dart — the source of one warning). Someone has to pick a winner.

4. 50 glossary entries have never been checked by a Tamil speaker, and translation_policy.dart points at docs/PHASE7_TRANSLATION.md — which does not exist. These are finance terms shown to the account holder, and the file that was supposed to hold them for review was never written.

Moderate
Duplicate detection (7.3) — re-importing a file silently doubles every transaction
Your two TODO.md items — notification language, and amounts on the lock screen
iOS on-device test — never run; ML Kit rules out the simulator entirely
PHASE7_1_REPORT.md is entirely stale — zero mentions of ML Kit; it still describes the abandoned ARB approach
If I picked one thing
The localhost:4000 fix, today, by whoever owns the backend — it's broken in production and costs a minute.

In this repo, #2 — it's the only one that makes the app display something untrue.

Want me to take #2? It's mechanical now that the pattern exists, and I'd promote _Verbatim into core/ so it's not import-only.