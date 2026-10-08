# Brief 3bq result

## Counted iOS reads first

Traced `LibrarySectionListView.affinityList` → `prefetchAuthorNewestWorks` →
`AuthorNewestWorkStore.prefetch/fetchAndStore` → `AO3AuthorProfileFetcher.page`.

- Address: `https://archiveofourown.org/users/<encoded username>/works?work_search%5Bsort_column%5D=created_at` (first page, account rather than pseud).
- For N distinct registered account usernames among **all** Authors affinity rows,
  a cold successful opening reads N pages, sequentially, including rows below the
  viewport. No author-count cap. Anonymous/coauthored/unregistered rows cost zero.
  Cached answers cost zero. Systemic failure stops the batch; 404 caches an empty
  answer and continues. Transient retry policy can add up to two retries per read.
- Trigger: entering Authors; changed author set or authentication/session scope;
  leaving and re-entering after expiry/failure. Sorting does not restart the batch.
  Scrolling/redrawing makes zero extra reads (`FavoriteAuthorRow` only reads cache).
  The affinity list has **no pull-to-refresh**; the Works list does. Expiry alone
  does not start a new request; the chip asks the reader to leave and return.
- Parsed newest summary (including an empty answer/404) is in memory for 30 minutes,
  keyed by lowercased username + account/session generation. Transient failures are
  not cached as answers or attempts when no stale fallback exists. A same-scope
  stale HTML fallback can supply a parsed answer with a new 30-minute TTL. Underlying HTML: 5-minute fresh TTL, up to
  24-hour same-scope stale fallback, 128 entries, URL + authentication scope.
  All requests use the coordinator and AO3Client pacing/coalescing/retry rules.
- Policy: `Favorites Authors newest work` expressly allows foreground cancellable
  per-row prefetch; its 3-slot coordinator limits concurrency, its 128-entry cache
  limits storage. Neither limits the number of authors read. Code now skips 404
  bylines and stops on systemic failure (the policy's “first unresolved” sentence
  is less precise than this current code).
- Fandoms and Tags: zero AO3 reads; `prefetchAuthorNewestWorks` returns immediately
  outside Authors and their shared rows contain no network task.

Android therefore omits Newest work/UNREAD and the dependent With new work rail,
as this brief requires for the uncapped prefetch. Opening any Android scope must
make zero AO3 requests; no HTTP implementation is added.

## iOS reference inventory

- Favorites only: Works · Authors · Fandoms · Tags. Default Works, stored device
  locally as `library.favorites.scope`. Aggregate scopes add Recent · Most read ·
  Most time (default Recent, `library.favorites.order`). Tags adds All · Unread works
  (default All, `library.favorites.tagsUnreadOnly`). Works alone shows All · Rereads
  · Offline · WIP; that stored choice does not narrow aggregate rows.
- Source: every active, non-queue-only, privacy-visible work, independent of work
  stars and ordinary section filters, plus summaries of all recorded sessions.
  Authors use trimmed whole bylines; only one registered identity supplies an
  account destination. Fandoms use workFandoms. Tags use workFreeforms, falling back
  to workTags; never character/relationship tags. Each key receives the whole work's
  counts/time, rather than a partition of time.
- Read = positive visit count or hasStartedReading. Unread = not started and no
  summary. Minimum: one read work; no other threshold. Summaries provide session
  count, total seconds and last session end; the last-read date falls back to the
  work date. Unread download counts use isDownloaded; Saved for Later counts use
  queue membership OR legacy isSaved && !isQueuedForLater. Favorited counts include
  starred read and unread works. Ranking descends by last read/count/time, with
  case-insensitive name ties. “Favorite” here means a reading affinity, not an
  explicit ReadingFavorite; the filled star is decorative, never a toggle.
- One shared card: 38pt tile (two initials; Authors circular, Fandoms rounded
  square; Tags circular #), name + filled star, log line. Authors: “N works read”;
  Fandoms adds “N favorited” if positive; Tags: “N works read carry this tag”
  (singular “1 work read carries this tag”). Positive time and known “last read
  <abbreviated date>” follow with middle dots. Missing facts are omitted.
- Authors/Fandoms: “N unread works · N downloaded · N in Saved for Later”, omitting
  zero extras; otherwise “No unread works in your library”. Tags: hairline then
  IN YOUR LIBRARY, “N unread works” or “No unread works”, extras or “Everything
  tagged this way has been opened”.
- Author chevron/action opens the registered author page; no guessed byline route.
  Fandom/Tag whole-card tap opens Library filtered by fandom/additional tag.
  Combined accessibility label: name, log sentence, library sentence; author action
  “Open author page”; fandom/tag hint “Shows these works in your Library”.
- Empty aggregate: “Nothing read yet”; “These <authors/fandoms/tags> come from works
  you have read and are ranked by your reading. You don't need to favorite them
  first.” Filtered Tags: “No unread works”; “Every work in your library under these
  tags has been opened. Tap All to see them again.” Works retains its existing empty
  state. iOS Authors' network-filter empty state is “No new work”. The real iOS
  `content` branch shows no strip/quick rail on a genuinely empty Works shelf;
  Android follows that code even though it means a default Works choice cannot
  lead to Authors until a work is starred. An already-stored aggregate choice
  still opens its own empty/content page.
- **Code wins over brief/comment:** iOS's outer toolbar is not gated by
  showsAffinityList. It still offers Filter and work-selection options when starred
  works exist, plus Privacy; those filters do not alter affinities. Android will
  preserve its existing Filter/Select/Privacy controls while ensuring invisible
  work selection is cleared. Filter/Select are present only with Works content;
  Privacy is gated by the hide-mature setting on Favorites, as in iOS. iOS also
  offers Display/Expand in that outer work menu; those presentations were not
  available on Android section lists before this brief and are not introduced
  here. iOS's name has two lines normally; Android lifts that at AX scale.

## Decided without asking

- Reuse the Library section route, shared tokens/segmented control, existing log
  DAO, and the Library's existing fandom/freeform predicates. No schema/backup key.
- Keep scope/order/Tags unread choice in SettingsRepository, outside KudosSettings.
  Use `ReadingAffinities.kt` and `FavoriteAffinityRow.kt` alongside the Library's
  existing pure rules/components; test names follow the iOS suite.
- An incoming Fandom/Tag navigation request resets dashboard predicates, search and
  sort (iOS applies a fresh LibraryFilters), not the chip bar's additive filter
  change. The root screen consumes it, never the outgoing section screen.
- Preserve demo work counts by adding only missing freeforms to existing samples:
  Slow Burn on Sodium Lights/Paper Cranes; Fix-It on Unanswered Is Not Unread/Burn
  my heart, heed my eyes; Found Family on Winter Garden (the zero-unread tag).
  Already-installed demos get the same additive upgrade. No extra works/sessions,
  identity guesses or HTTP fixtures; existing nonempty tags and progress survive.
- Use named iOS aggregation cases in an Android ReadingAffinitiesTests suite and
  seeded Room/Compose screen tests with native graphics and a tall window.

## Open questions

- Newest work: iOS's cold request count is N (e.g. 3 authors = 3 first-page reads;
  100 = 100, before retries), with no author-count cap named by policy. Android
  omits the block and With new work. Owner must decide a cap/attempt cooldown before
  a later port; no request is made here to resolve that question. Successful
  reads that each require the two permitted retries could cost up to 3N starts.
- Android stores `authorIdentitiesJSON` but the existing metadata enrichment does
  not populate it. The new decoder uses valid stored registered identities and
  otherwise leaves the author destination absent, matching iOS's unverified-byline
  behavior. A later enrichment task must supply actual parsed identities, never
  guessed usernames; this brief adds no network read to fill that gap.
- iOS's empty Works branch makes the scope strip inaccessible with no stars, and
  its outer menu still offers work controls over aggregates. Preserved the actual
  code as required; whether iOS should change these remains an owner decision.
  Android's preexisting lack of section Display/Expand controls remains outside
  this scopes port; no extra work presentation was invented.

## Implementation / verification

- `ReadingAffinities`: pure per-work summaries and Authors/Fandoms/Tags arithmetic,
  current reading-state/download/shelf rules, privacy/deletion/queue-only exclusion.
  Explicit ReadingFavorite rows are intentionally not read, as on iOS. All required
  aggregation facts already exist on Android; no log fact was invented or omitted.
- `LibraryViewModel` puts summaries and device-local preferences into collected
  LibraryUiState. Scope/order/unread changes redraw through that state. One lazy
  affinity list/card, section wash/palette, gold token, explicit text line heights,
  no fixed row height; AX controls use the existing form panel pattern and tiles
  grow with font scale. `ProvidePushedShellChrome` stays owned by the section.
- Navigation: existing authorProfile route; existing Library root and filter
  handoff, extended with an additional-tag request (not a personal-tag request).
  LibrarySelection.visible receives an empty work-ID set for aggregate scopes.
- Written, **not executed**: ReadingAffinitiesTests (13 cases, including all 10
  named iOS cases); FavoriteScopesScreenTest (9 seeded Room/Compose cases, native
  graphics, tall window, patient waits); one new SettingsRepositoryTest case;
  one new DemoLibraryTest case. The recording AO3Client is injected into the
  real work tags/metadata/download dependencies and asserts **0** requests for
  Works, Authors, Fandoms and Tags opening and scrolling. UI cases also cover
  wording/navigation, empty scopes and unread-empty Tags, strip gating, quick
  filters, selection clearing, additional-tag handoff, and four palettes at AX.
- Ran `android/Scripts/check-invariants.sh`: passed. `git diff --check`: passed.
  Read the actual signatures/models/DAO and navigation calls used. Neither result
  proves Kotlin/Compose compilation or runtime behavior.
- Claude must run assembleDebug + testDebugUnitTest (new suites and existing
  Library/Settings/demo regressions), then inspect 1ak/1bc/1bd at ordinary + AX
  scale in Light/Dark/Sepia/OLED and exercise real shell/navigation/selection.
  No build/test execution or visual-correctness claim is made here.
- Reviewed earlier landing notes: 3u `409c4d2f`, corrected card/list `ed4568bf`,
  quick filters `33b6a23c`; 3o `35647609`; author pages `d11c4056` and chrome fix
  `ccb30b57`. There is no 3u-fix-result.md in this worktree; its landing body records
  Claude's compile, wording and backup fixes. Earlier result claims are not treated
  as verification of this new diff.
- No AO3 contact, sign-in, branch change, commit, push, TASKS edit, helper/scratch
  file, `.orig`, Room schema or backup-format change. Changes remain uncommitted.

## Landing note (Claude, 2026-10-08)

Landed on `android/redesign-parity`; the patch applied cleanly over 3bp. Gate: 2,188 tests.

Changed on landing:

- The line height added to the shared segmented control was left out (the standing rule).
- **The demo had two rows where the brief asked for three.** Rows are works that were read,
  and the demo's finished works had no read date, so they counted as never opened; a finished
  work now gets one when the demo is seeded. Two more demo works carry a tag
  ("Lighthouse Hours", "What the River Keeps"). An installed demo keeps its old rows.
- Two test faults: a test whose body returned a value (JUnit wants none), and a wait on a
  title that all three scopes share, which passed before the scope had changed.

Seen on the emulator (demo, reseeded): Works with its quick filters; Authors (three cards,
monogram, star, "1 work read · last read …", "No unread works in your library") with the
Recent / Most read / Most time strip; Tags with All / Unread works; a tap on a tag opens the
Library filtered by it; Fandoms in Sepia at double text size, where both strips become
panels of rows and nothing is clipped.

Not seen: an author row opening the profile, the unread filter's empty state, OLED and
Light, the "Most time" order with real sessions (the demo has none).
