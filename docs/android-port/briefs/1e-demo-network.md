# Brief 1e: the Android demo must never reach AO3, plus Browse follow-ups

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. Write code that
compiles by careful reading: declare every value before use, and check every symbol you call
exists with that exact signature. Claude builds and checks on the emulator.

## 1. A demo network block (top priority)
When an agent ran the Android demo on the emulator, Browse fetched **live AO3 pages**, because
Android's demo mode has no counterpart to iOS's `DemoNetworkBlock`. Overnight agents must not load
AO3. Port it:
- iOS: `kudos-ao3-reader/App/DemoLibrary.swift`, `final class DemoNetworkBlock: URLProtocol` (~line 410):
  `isActive` when the demo is on, `routes` mapping URL path patterns to fixture files, `fixture(for:)`,
  `startLoading` serving `KudosTests/Fixtures/<file>.html` from `-KudosFixtureDir`, and refusing
  everything else.
- Android: an OkHttp `Interceptor` (find how `network/` builds its `OkHttpClient`; the AO3 client
  and any other clients such as auth, WebView excepted). It's added only when the debug demo extra
  is on (`--ez kudosDemoLibrary true`), serves the same fixtures by the same route patterns, and
  answers every other `archiveofourown.org` request with a local error response. **No AO3 request
  may leave the device in demo mode.**
- Fixtures: copy `KudosTests/Fixtures/*.html` into `android/app/src/debug/assets/fixtures/` (debug only,
  so they never ship) and read them through `AssetManager`.
- Add a unit test for the route matching, and one showing a non-fixture AO3 URL is refused.

## 2. Browse follow-ups (from commit b8d965bb)
- **Jump Back In didn't appear** in the agent's screenshots, though iOS shows it for the same demo
  library (3 cards: Doctor Who (2005), Doctor Who, Sherlock). Find out why. Likely suspects: the
  category mapping needs fandom lists the demo doesn't load, or reads aren't counted. Fix it to match
  iOS `MediaBrowserView.rankJumpBackIn` / `jumpBackInFandoms`, including the case where categories come
  from fixtures.
- **Remove the "Search AO3 or enter a URL" field** from the Browse root. iOS has none; Search is its
  own tab. Make sure URL entry still exists on the Search tab before removing it here.

Write `docs/android-port/briefs/1e-result.md` (under 300 words).
