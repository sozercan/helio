# ADR-0002: Reddit API, Authentication, Credential Lifecycle, and Privacy

Status: Accepted

## Context

Helio is a privacy-focused Reddit client with no app-level backend. It supports keyless sign-in via Reddit's web session alongside opt-in user-supplied OAuth API keys, multi-account switching, concurrent background requests, and strict Reddit rate-limit budgets. Authentication, token refresh, request routing, caching, and listing decoding must maintain strict per-account isolation, prevent cookie or secret leakage, and handle Reddit's undocumented protocol quirks safely.

## Decisions

### 1. Keyless Web-Session Authentication & Cookie Isolation

- **Web-session token exchange** (`Sources/HelioKit/models/Credentials/RedditWebSession.swift`, `Sources/HelioKit/views/Settings/views/Credentials/WebLogin/RedditWebLoginView.swift`): By default, users sign in on `reddit.com` inside `RedditWebLoginView`. Helio stores the session's `reddit.com` cookies in the keychain and exchanges them at Reddit's web token service (`accounts.reddit.com/api/access_token`) for ~24 h OAuth bearer tokens usable on the standard `oauth.reddit.com` REST API.
- **Public desktop web client ID** (`Sources/HelioKit/models/Credentials/RedditWebSession.swift`): Token exchange uses the public client ID of Reddit's desktop web site (`token_v2`), which has no secret and is sent on every signed-out `reddit.com` page load. It is the only real Reddit client ID allowed in code.
- **Strict cookie isolation** (`Sources/HelioKit/views/Settings/views/Credentials/WebLogin/RedditWebLoginView.swift`, `Sources/HelioKit/models/Credentials/RedditWebSession.swift`):
  - `RedditWebLoginWebView` uses a fresh, non-persistent cookie store so every sign-in starts signed out and never shares cookies with other views or sessions.
  - Token-mint requests set `httpShouldHandleCookies = false` and pass session cookies explicitly via the `Cookie` header so they never enter the shared cookie store.
- **Token service authority & Reddit JWT quirks** (`Sources/HelioKit/models/Credentials/RedditWebSession.swift`):
  - Reddit sets `reddit_session` even for signed-out visitors, and the token service still returns a valid anonymous bearer token rather than an error. Cookie presence therefore does not prove sign-in; the token service response and JWT `sub` claim are authoritative (a `loid` prefix identifies a logged-out anonymous visitor).
  - An unreadable JWT returns `.failed` rather than `.signedOut`, preserving the user's stored web session on parse failures.
  - Cached web-session tokens are verified against the active `clientID` via the JWT `cid` claim. A mismatch forces a fresh mint because `oauth.reddit.com` answers blocked older client IDs with a `403` block page instead of `401`.
  - `failedMintCooldown` throttles retries after a token-mint failure so API requests do not hammer the token service during an outage or refusal.
- **Web login browser mechanics** (`Sources/HelioKit/views/Settings/views/Credentials/WebLogin/RedditWebLoginView.swift`, `Sources/HelioKit/models/Credentials/RedditWebSession.swift`):
  - Cookies are read from `WKHTTPCookieStore` rather than via page JavaScript (which `reddit.com` restricts).
  - Cookie polling is required because Reddit's sign-in form submits via XHR without navigating, which `WKNavigationDelegate` callbacks alone miss. `reportedSession` caches the last reported cookie so a signed-out visitor cookie is not re-sent to the token service every poll tick, and `finish()` returns `false` for visitor cookies so the browser keeps watching.
  - Provisional-navigation errors are filtered: only failure of the initial sign-in page leaves the user with no UI; popup and post-load errors are ignored.
  - OAuth sign-in popups (Apple/Google) keep their window opener as an overlay until closed; other new-window links (such as the privacy policy) load in place so swiping back returns to sign-in.
  - Navigation back and interactive dismiss are disabled during `.finishing` because saving closes the sheet automatically and leaving mid-save is unsafe.
  - Signing in to an account already saved in Helio updates that existing credential ID rather than creating a duplicate. `apiAppID` is cleared before setting identity because mutating `apiAppID` resets identity. `signIn` calls `/api/v1/me` directly rather than `fetchMe` to avoid switching the active account before the credential is saved. After `save()`, `updateMe()` is triggered explicitly because a signed-out account lost its profile and re-selecting the same credential ID does not reload it.
- **Web-session rotation vs. sign-out** (`Sources/HelioKit/models/Credentials/RedditCredential.swift`):
  - When Reddit signs a web session out, `webSessionCookies` becomes `nil`, keeping the credential record waiting for re-authentication rather than deleting it.
  - Direct replacement of `webSessionCookies` rotates `webSessionID` (treating it as a new sign-in), whereas `updateWebAccessToken` restores `webSessionID` after atomically merging rotated cookies (cookie rotation belongs to the same web grant).

### 2. Opt-In API-Key OAuth Credentials

- **Client ID validation** (`Sources/HelioKit/models/Credentials/RedditCredential.swift`): API-key credential validity keys off the 22-character app ID alone without requiring a client secret, supporting both installed-app credentials (no secret) and legacy web-app credentials (22-character ID plus secret).
- **HTTPS OAuth redirect** (`Sources/HelioKit/models/RedditAPI/RedditAPI.swift`): Reddit requires an `https` redirect URI for web-app keys. Helio uses a static HTTPS redirect page (`https://sozercan.github.io/helio/auth-success`) that forwards the query to `helioapp://auth-success` for `authorize` to handle.

### 3. Credential Concurrency, Single-Flight Refresh & Account State

- **Secret-free authorization identity** (`Sources/HelioKit/models/Credentials/RedditCredential.swift`): `AuthorizationID` is stable across access-token renewals, changes when the OAuth grant or client is replaced, and never retains raw client secrets or refresh tokens.
- **Single-flight token refresh & waiter ownership** (`Sources/HelioKit/models/Credentials/AccessTokenRefresher.swift`, `Sources/HelioKit/models/Credentials/RedditCredential.swift`):
  - Token refreshes coalesce single-flight per OAuth client/grant, including across duplicate saved credential records. Cancelling one waiter does not cancel the shared refresh.
  - A known rejected token is never reused, while a forced renewal can coalesce onto a newer in-flight token.
  - Each waiter owns its persistence policy (`saveToken`) and merges results (including web-session cookie rotation or sign-out) only into its captured installed grant—looked up by grant ID, never by current selection—and scoped to the requesting `AuthorizationID` so stale refreshes never clobber newer edits.
  - Updates merge only the token field into the live record (never overwriting with a captured credential snapshot). A monotonic `lastRefresh` guard prevents a delayed shared-refresh waiter from restoring an older rejected token, and a compare-and-clear guard prevents a delayed rejected waiter from clearing a newer successful renewal.
  - `isFresh` applies a 100-second early-expiry safety margin to cover requests already in flight.
- **Synchronous mutations & lease-guarded background persistence** (`Sources/HelioKit/models/Credentials/RedditCredentialsManager.swift`):
  - Credential mutations and their persistence/profile side effects complete synchronously within the same main-actor turn.
  - A lock-based authorization lease allows background persistence to commit only while a grant remains installed, without blocking main-actor selection reads. Grant invalidation acquires this lease before publishing replacement credentials so an in-flight commit can never overwrite a replacement account's write.
  - Saving an edited credential draft preserves untouched background-rotated web-session cookies/token/grant and preserves any `userName` backfilled by `/me` while the editor was open. Legacy `backfillUserName` checks grant identity and emptiness so it never overwrites user edits or another grant.
  - `selectionIsSaved` is checked separately from `selectedCredential`'s fallback to the first account because views keyed by the raw stored UUID (such as the subs list) would render empty if the stored ID points to a deleted or missing-keychain credential.
  - Launch and account-switch subscription/multi syncs are throttled to at most once per hour (local subscribes update immediately and pull-to-refresh syncs immediately). The `subsSyncedAt` key includes `userName` so re-authenticating a credential as a different account triggers a fresh sync, and the background task captures the credential explicitly because selection can change before it runs.
- **Profile state ownership & credential-gate escape hatch** (`Sources/HelioKit/models/Credentials/SelectedAccountProfile.swift`, `Sources/HelioKit/models/RedditAPI/user/fetchMe.swift`, `Sources/HelioKit/components/WithCredentialOnly.swift`):
  - `SelectedAccountProfile` owns the selected account's profile state; `fetchMe` and other API calls remain stateless and only return data.
  - `authorizationID` is separately observable so UI detects account switches even while both profiles are `.loading`, and account switches clear the previous account synchronously before starting the new fetch.
  - `WithCredentialOnly` shows `AccountSwitcherMenu` on the credential-gate screen because the Me tab's switcher sits occluded behind it, preventing users from being trapped on a signed-out account.

### 4. Reddit API Protocol, Rate Limiting, Batching & Data Integrity

- **Per-request account pinning & retry policy** (`Sources/HelioKit/models/RedditAPI/RedditAPI.swift`):
  - Account selection is resolved exactly once per request (including when both endpoint construction and dispatch depend on the account) so retries and token renewals remain pinned to that account and an absent account never becomes a deferred "use whoever is selected later".
  - Transient retries keep forwarding `rejectedToken` because a captured credential snapshot (`altCredential`) still holds the stale rejected token.
  - Only dropped connections and intermittent `5xx` errors are retried. `4xx` (other than `401`), `429`, and decode failures are never retried because they fail identically and still count against Reddit's rate limit.
- **Windowed rate-limit tracking & optional-lookup shedding** (`Sources/HelioKit/models/RedditAPI/RedditRateLimit.swift`, `Sources/HelioKit/models/RedditAPI/user/AvatarLoader.swift`):
  - Helio tracks each account's request budget from `x-ratelimit-*` headers to avoid sending requests into a `429` window.
  - Within a window, remaining counts merge monotonically (`min`) so slow, out-of-order HTTP responses cannot lift a limit or clear a `429`. A 5-second `sameWindowSlack` tolerance accommodates whole-second header granularity and response latency before a later reset starts a new window.
  - Below `lowRemaining` (10 requests left), optional lookups (avatars) are shed until the next window so core feed and comment requests keep the remaining budget. Skipped or failed avatar batches are not cached in `withoutAvatar`, allowing later screens to retry.
- **Batching, caching & per-account isolation** (`Sources/HelioKit/models/RedditAPI/shared/RedditInfoLoader.swift`, `Sources/HelioKit/models/RedditAPI/user/AvatarLoader.swift`, `Sources/HelioKit/models/RedditAPI/user/fetchUsers.swift`):
  - `RedditInfoLoader` batches up to 100 items per `/api/info` request (Reddit's fullname-list cap), coalesces concurrent lookups, and caches results for a few minutes. Everything is strictly per account because responses include account-specific votes, saves, subscriptions, and private-subreddit visibility. `fetchInfoThings` takes a non-optional captured `RedditCredential` so `nil` never falls back to a later selection, and `self.accounts` is cleared on flush so credential snapshots are retained only for pending/in-flight work, never in the cache.
  - `AvatarLoader` batches up to 100 IDs per `/api/user_data_by_account_ids` request, coalesces concurrent lookups, and caches once per session across feeds, comments, and crossposts. Comment-tree avatar population (`fetchUsers.swift`) performs one batched lookup and a single main-queue hop for the entire tree rather than per-comment hops.
- **Lossy listing decoding & destructive-sync safeguards** (`Sources/HelioKit/models/RedditAPI/RedditAPI.swift`, `Sources/HelioKit/models/RedditAPI/shared/RedditInfoLoader.swift`, `Sources/HelioKit/models/RedditAPI/subs/fetchSubs.swift`):
  - `ListingData` and `RedditInfoLoader` decode children one by one so a single unexpected Reddit item is skipped rather than failing the whole page or batch.
  - When zero children decode, `ListingData` throws so union decoders (such as comments responses using `Either<Listing<PostData>, Listing<CommentData>>`) can fall back to the alternate listing type.
  - `ListingData.skippedChildren` records skipped items; callers treating a listing as complete must check it. `fetchSubs.swift` fails the entire fetch (returning `nil`) if `skippedChildren > 0` or any page fails, preventing Core Data sync from deleting subscriptions that were skipped or on failed pages.
- **Endpoint quirks** (`Sources/HelioKit/models/RedditAPI/multis/fetchMultiPosts.swift`): Multireddits do not support a `/best` sort endpoint (Best exists only for the front page and subreddits), so `.best` requests the multireddit's bare `.json` default listing.

## Consequences

- **Strong privacy and account isolation**: Session cookies never enter the shared cookie store, caches and requests are strictly scoped to captured accounts, and `AuthorizationID` avoids retaining raw secrets.
- **Resilience to concurrency and Reddit quirks**: Single-flight refresh, monotonic token/rate-limit updates, lease-guarded commits, lossy per-item decoding, and strict complete-listing checks prevent race conditions, silent account cross-talk, rate-limit exhaustion, and destructive subscription loss.
- **Maintenance burden on web-session protocol**: Because keyless web-session auth relies on Reddit's web login flow, XHR submission, `reddit_session` cookies, and JWT `sub`/`cid` claims, changes to `reddit.com` login or token endpoints require updating `RedditWebSession` and `RedditWebLoginView` while keeping opt-in API keys working independently.
