# Brief 1e result

Demo mode answers AO3 from fixtures. On emulator-5554, airplane mode still on, Browse shows iOS's three Jump Back In cards.

## Demo network block

OkHttp clients are built in `KudosApplication.onCreate`, before `MainActivity` reads `--ez kudosDemoLibrary true`, so the interceptor is installed at build time (AO3, ahead of the redirect relay; GitHub; app update; TTS; Coil) and stays inert until `DemoNetwork.activate`. While active, `archiveofourown.org` and its subdomains use the iOS route table and `android/app/src/debug/assets/fixtures/` (41 HTML files, debug only). Any other URL on that host is a local 404. Other hosts proceed. WebView is not intercepted.

Startup metadata refresh waits up to 3 seconds for that decision, then skips AO3 in demo mode. Demo Browse does not read or write `FandomCatalogCache`.

## Jump Back In and Search

The empty carousel was a live fetch. With `ao3_media_fandoms.html` on every category, the demo library ranks Doctor Who (2005), Doctor Who, and Sherlock (TV), all under Anime & Manga. The limit stays 10.

The Browse root no longer has "Search AO3 or enter a URL". The existing Search field opens the web fallback for `http(s)://`, `www.`, or an `archiveofourown.org` host. Other text, including "dr. who", stays a search. "Open AO3 Website" remains.

## Checks

`cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline` — BUILD SUCCESSFUL. Tests cover route matching, a non-fixture AO3 URL refused without `chain.proceed`, demo cache bypass, the three fixture cards, and URL detection.

emulator-5554, `airplane_mode_on` left at 1. After the demo extra: Jump Back In is those three cards (61.9K, 82.1K, 131K); each category is 4 fandoms / ~635.8K works. Search showed the fixture "Two Voices at Dawn". `archiveofourown.org/works/1` in Search opened the in-app page, which did not load (WebView is outside the block; the radio is off). Logcat had no `archiveofourown.org` lines. Not committed.
