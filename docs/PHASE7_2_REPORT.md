# Phase 7.2 — Google sign-in

Two things came out of this: a small change that shipped, and a **production bug
on the live web app** that has nothing to do with mobile.

## ⚠️ Google sign-in is broken on the deployed website

`GET https://coincompass.sathishkumar.cloud/api/auth/oauth/google` returns a 302
whose `location` is:

    https://accounts.google.com/o/oauth2/v2/auth
      ?response_type=code
      &client_id=792601730978-…apps.googleusercontent.com
      &redirect_uri=http%3A%2F%2Flocalhost%3A4000%2Fapi%2Fauth%2Foauth%2Fgoogle%2Fcallback
      &state=…&code_challenge_method=S256&code_challenge=…
      &scope=openid+profile+email

and the response also carries

    x-oauth-redirect-uri: http://localhost:4000/api/auth/oauth/google/callback
    access-control-allow-origin: http://localhost:4000

**The production server is telling Google to send users back to
`http://localhost:4000`.** Anyone who clicks "Continue with Google" on the live
site is redirected, after consenting, to a machine that is not there. This is
not a mobile problem — it is broken for every web user right now, and it looks
like a `redirect_uri` / origin environment variable left at its development
value. Fixing it is a one-line config change, and nothing in this repo can do
it.

Everything else about the flow is sound: PKCE (`S256`), a `state` nonce, both
held in short-lived httpOnly cookies (`mt_oauth_state`, `mt_oauth_verifier`,
`Max-Age=600`), and a minimal `openid profile email` scope.

## What the deployment supports

    GET /api/auth/providers  →  200
    {"google":true,"github":false,"microsoft":false,"apple":false}

Google is the only configured provider.

## Why the app cannot complete the flow

The session is an **httpOnly `mt_session` cookie**. Only the server can mint
one, and it lands in whichever cookie jar made the request. That single fact
closes all three routes:

| Approach | Why it fails |
|---|---|
| **External browser** (Custom Tab / `ASWebAuthenticationSession`) | The flow completes and the cookie lands in the *browser's* jar. Dio's `PersistCookieJar` never sees it. |
| **Embedded WebView** | Cookies could be copied into Dio's jar — but Google has refused OAuth in embedded WebViews since 2021 (`disallowed_useragent`). |
| **Native `google_sign_in`** | Yields an ID token with no WebView, but no endpoint accepts one. |

Unlike 7.4 — where polling the existing feed gave a genuinely useful
client-only feature — there is no partial version here, because *obtaining the
session* **is** the feature.

## The backend change 7.2 needs

Small, and it needs no Google Console work, because Google never sees the app's
custom scheme — only the server's existing https callback.

**1. Mark the flow as mobile.**

    GET /api/auth/oauth/google?client=mobile

Identical behaviour, except the server remembers this one is for the app.

**2. On success, hand back a one-time code instead of a redirect to the web app.**

    302 Location: coincompass://auth/callback?code=<one-time, single-use, ~60s>

**3. Add an exchange endpoint.**

    POST /api/auth/oauth/exchange   {"code": "<one-time>"}
    → 200 {user:{…}} + Set-Cookie: mt_session=…

**Why this shape works.** The app opens step 1's Google URL in a system browser,
so Google sees a real browser and is satisfied. The server's own callback runs
normally, with the `mt_oauth_state` / `mt_oauth_verifier` cookies it set in step
1, so PKCE is unchanged. The final exchange in step 3 is made by **Dio**, so
`mt_session` is set in the app's jar — which is the whole problem, solved by
moving one request.

On the app side that is then: register the `coincompass://` scheme (an
`intent-filter` on Android, `CFBundleURLTypes` on iOS — neither exists yet),
`flutter_web_auth_2` or equivalent to run step 1 and catch the callback, and one
repository method for step 3.

An alternative — `POST /auth/oauth/google/token {idToken}` fed by the native
`google_sign_in` SDK — is simpler in the app but needs Android and iOS OAuth
clients created in the Google project, so it moves work rather than removing it.

## What shipped

`GET /auth/providers` had been declared in `Endpoints` since phase 1 and
**never called**. The login screen hardcoded a Google button, which was correct
only by luck: it would have gone on offering Google if the server turned it off,
and would never have offered Apple if it were turned on.

The social block is now drawn from the server's answer:

- nothing configured → the divider and the whole block are hidden;
- while the call is in flight, or if it fails → nothing is drawn, because a
  provider button that cannot work is worse than no button, and email sign-in is
  unaffected either way;
- `google: true` → the Google button appears.

Tapping it now **explains** instead of saying "coming soon on mobile": that the
server needs a change first, that email and password work here, and that Google
works on the website. That is more use than a promise, and it stops the button
being a control that claims something the app cannot do — the shape of the 7.1a
bug.

Seven tests cover the parse, including junk and a non-boolean truthy value
(`"google": "yes"` must not light the button up), because this runs on the first
screen a cold start paints and a throw there is a crash before anyone can type.

## Still open

- **The `localhost:4000` redirect_uri**, which is a live bug for web users and
  the first thing to fix.
- The three backend pieces above. Until they exist, 7.2 cannot be finished in
  this repo, and no amount of client work changes that.
