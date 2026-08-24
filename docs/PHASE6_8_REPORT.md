# Phase 6.8 — auth flow tests

`test/auth_flow_test.dart`, 23 tests. Suite total 710 → **733**, analyzer clean.

## What was missing

6.8 was `[~]` because Money, DateX and the model round-trips were covered but the
auth flow was only ever exercised *incidentally* — a fixture happened to return a
user, so the shell mounted. Nothing asserted what happens when it doesn't.

That is the one feature in the app that decides **whose data is on screen**, so it
now has its own suite, driven through the real stack:

```
AuthController → AuthRepository → ApiClient → Dio → _Adapter (fake transport)
```

Only the socket is replaced. The cookie jar, the interceptors, the exception
mapping and the JSON parsing are all the shipping code — because the interesting
failures in this feature are not in the controller's arithmetic, they are in the
seams between those layers.

## The four that earn their place

Each was verified by **reintroducing the bug and watching the test fail**. A test
that has never failed is a guess.

| # | Guard | Mutation applied | Result |
|---|---|---|---|
| 1 | `_userGeneration` in `refreshUser()` | deleted the generation check | ❌ fails — *"the older /auth/me answer must lose to the newer unlock"* |
| 2 | `/auth/` excluded from `forFailedWrite` | `isAuth = false` | ❌ fails — login shows *"Not saved — you're offline."* |
| 3 | `_hasUser` → `UNEXPECTED_RESPONSE` | deleted the throw | ❌ fails — a user-less 200 becomes a signed-in session |
| 4 | `_isUnreachable` | forced to `false` | ❌ fails — offline cold start lands on `/login` |

**#1** is the one worth stating in the owner's terms: enter the right passcode, see
Net Worth for a second, watch it vanish — because a `GET /auth/me` that *started*
before the unlock *landed* after it and put the old flag back. It had no
regression test until now.

**#3** is the nastiest failure shape in the file. Fabricating an empty `AppUser`
still satisfies `AuthState.isSignedIn`, so the app lands on a dashboard where every
request 401s and there is no route back to the login screen.

## Also covered

- **Sign-in**: wrapped and bare user bodies; `requires2fa` with and without
  `methods`; the legacy `twoFactorRequired` fallback; 401 credentials; offline.
- **The session cookie**, through the real `PersistCookieJar`: issued on sign-in,
  replayed on the next request, gone after sign-out — and never sent as an
  `Authorization` header, since the whole scheme is httpOnly cookies and a stray
  bearer would be a second unmanaged credential path.
- **Cold start**: 401 and 403 are real answers (signed out); offline and 5xx are
  not (`unverifiedSession`, user still null — fail-safe, never fail-open);
  `restore()` hits the network once however often it is called.
- **401 mid-session** tears the session all the way down; an unreachable refresh
  keeps the last known `wealthLockEnabled` rather than guessing either way.
- **Sign-out** resets to a clean state even when `POST /auth/logout` itself fails.

## Two harness bugs found while writing it

Worth recording, because both would have made tests pass for the wrong reason:

1. **The cookie jar was shared across every test in the file.** `ApiClient.create`
   builds its `PersistCookieJar` at `<documents>/.cookies/`, and the
   `path_provider` mock returned one directory for the whole file — so a previous
   test's `mt_session` was replayed into the next. The documents directory now
   moves per client.
2. **Dio reports an absent header as a null value**, and stringifying it turned
   "no cookie" into the literal string `'null'` — which is not `null`, so the
   sign-out assertion passed while proving nothing. Null values are now dropped
   at capture.

## Safety

`_Adapter` replaces Dio's `HttpClientAdapter` outright — no socket is opened — and
calls `fail()` on any path in the never-call list (`/auth/lock-wealth`,
`/auth/unlock-wealth`, `/settings/wealth-passcode`, `/settings/pin`).
`/auth/logout` is served locally because sign-out is under test, and can only ever
reach the fake.
