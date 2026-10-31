---
name: helio-perf
description: "Measure and improve Helio's performance: Reddit API request counts, main-thread time, scroll hitches, comment loading. Use for perf work, changes to networking or feed/comment rendering, or to check a change didn't regress either."
---

# Helio performance

Measure before and after every change with `Tools/perf` (read its `README.md` first), and report numbers, not impressions. Everything runs in the simulator on fixture data: no Reddit account, no network.

## Loop

1. Baseline: `perf build base --repo <worktree at the base commit>`, then `perf bench base`. Builds from before `Tools/perf` existed work too; the tool adds its setup test for the build.
2. Find the cost:
   - Requests: read the `R` lines in `run<n>.log`; look for repeats of the same URL, calls with empty ids, retries, and requests that could share a batch.
   - Main thread: `perf bench <label> --runs 1 --profile`, then `perf stalls <label>` for the feed and `--from post_open --to cscroll_end` for a post. `perf callers <label> <symbol>` shows who calls a hot frame. The app is the `Helio` binary; everything else is the system.
3. Change one thing, `perf build head`, `perf bench head`, `perf compare base head`. Keep a change if it moves the medians beyond the noise (see the README), and check behavior in the simulator: a faster screen that shows less isn't a win.
4. Update `Tools/perf/budget.json` when request counts drop, and put the before/after table in the pull request.

Don't build while a benchmark runs; the build takes the CPU the measurement needs.

## What the measurements taught

- XCUITest isn't a timing tool: its accessibility snapshots took about a fifth of the main thread and added hitches. Drive measured scenarios from inside the app (the shim's `open`/`scroll` commands). `simctl openurl` stops at an "Open in Helio?" prompt; the shim's `open` doesn't.
- On a busy device, iOS can hold `.background` tasks for many seconds: comments took 0.5 to 30 s to load until their fetch stopped running at background priority.
- `GenericRedditEntity` is a generic `@Observable` class, so every read of an observed property builds a key path at runtime. Reading identity in `==`, `ForEach` and per-row lookups cost about a tenth of main-thread time while scrolling.
- `Defaults[key]` and `@Default` decode JSON on every read, and each `@Default` sets up an observer per view instance.
- An animated insert of a long `List` builds and measures every new row in one frame (a ~230 ms stall for a comment thread).
- What's left while scrolling is mostly SwiftUI creating and sizing `List` cells. Expect the next wins from simpler row view trees, not from app logic.

## Rules for Helio code

- Reddit requests go through the shared loaders, which batch, dedupe and cache: `AvatarLoader` (author avatars), `RedditInfoLoader` (posts, comments and subreddits by id or name), `AccessTokenRefresher` (one token refresh at a time). Don't add a per-row or per-post request.
- Retries are for transient failures only (`RedditAPI.isTransient`).
- Work the user waits on runs at `.userInitiated`, supporting work at `.utility`. Keep `.background` for work nobody waits on (Core Data bookkeeping).
- Settings read in layout or rows go through `CachedDefaults`, or are read once per `body` and passed down. Don't add `@Default` to row views.
- Don't read observed properties of every post or comment in a loop on the main thread, and don't search `entities` linearly per row.
- Link previews use `PreviewModel.shared(_:compact:)`, not a new model per view update.
- Insert long lists without animation.
- Fixtures and logs use placeholders only; never real Reddit credentials or usernames.
