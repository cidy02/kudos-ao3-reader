# AI Handoff

## Handoff - T-70 - Codex (Android UI refinement / Material-HIG docs) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Scope source:

- `/Users/cidy02/Downloads/Codex_UI_Refinement_Prompt.md`
- `/Users/cidy02/Downloads/Kudos_Interface_Guidelines_Design_Philosophy.md`
- `/Users/cidy02/Downloads/ANDROID_MATERIAL_HIG_TRANSLATION_WEB_CONTEXT.md`

Dependencies added: none.

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`
- `docs/contracts/KUDOS_ANDROID_INTERFACE_GUIDELINES.md`
- `docs/contracts/ANDROID_MATERIAL_HIG_TRANSLATION.md`
- `docs/contracts/CROSS_PLATFORM_UI_BRIDGE.md`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosUi.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/components/AO3WorkCard.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/home/HomeScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/browse/BrowseScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/browse/BrowseUi.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomListScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomWorksScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- deleted unused `PlaceholderScreen.kt` and `WorkCardPlaceholder.kt`

What changed:

- Added canonical Android UI guidance docs:
  `KUDOS_ANDROID_INTERFACE_GUIDELINES.md`,
  `ANDROID_MATERIAL_HIG_TRANSLATION.md`, and
  `CROSS_PLATFORM_UI_BRIDGE.md`.
- Added shared Material UI vocabulary in `KudosUi.kt`: screen/section headers,
  metadata chips, status badges, loading cards, empty cards, and error cards.
- Reworked shared AO3 work cards to expose fandom, rating/warning/category,
  discovery tags, and stats as compact Material chips instead of long text blobs.
- Refined Home shelves into horizontal `LazyRow` sections and kept the existing
  offline/privacy-aware Library-derived data and Work Detail/Reader routing.
- Refined Library saved-work cards, previews, no-results states, and compact rows
  with shared headers/state cards/chips while preserving offline-first behavior,
  filters, privacy masking, and existing query semantics.
- Refined Search idle/loading/error/no-result/results states. The idle state now
  explicitly says Search only runs when the user presses Search.
- Refined Browse category, fandom-list, and fandom-work surfaces with shared
  headers/state cards/chips and kept the WebView fallback behavior unchanged.
- Refined Account/account-list, Settings, Backup, and Work Detail presentation
  with shared headers/state/message/chip vocabulary. No auth, backup, AO3 write,
  reader, Room, parsing, or DataStore behavior was changed.
- Removed unused scaffold-era placeholder components so future UI work does not
  accidentally reuse debug/sample presentation.
- Updated `UI_PARITY_CHECKLIST.md` for the T-70 design/docs/component pass.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest`
  - Result: failed in `:app:dexBuilderDebug` due stale duplicate generated
    classes with `" 2.class"` suffixes in `android/app/build/...`.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest`
  - Result: BUILD SUCCESSFUL, 235 JVM tests, 0 failures.
  - Non-fatal warnings: existing native strip fallback for bundled libraries and
    existing `ReaderProgressSaverTest` coroutine opt-in warnings.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`
  - Result: BUILD SUCCESSFUL.

Known gaps / needs human review:

- No emulator/device screenshots were captured.
- No TalkBack, dynamic font-scale, keyboard/focus, tablet/landscape, or WebView
  manual verification was performed.
- Reader chrome/settings were intentionally not redesigned in this pass; the
  reader should stay quiet and needs a separate device-based audit.
- Home still lacks AO3 Subscriptions/Recently Updated shelves.
- Advanced Search filter UI, Backup SAF import/export UI, direct raw AO3
  work-id/URL hydration, encrypted-at-rest session storage, and live AO3
  login/write verification remain deferred from prior phase handoffs.

Next step:

- Human/Claude should run a visual device audit on phone and tablet/foldable
  sizes, especially large font scale, TalkBack order, horizontal Home shelf
  ergonomics, Work Detail density, and Browse/Search card scanability.

## Handoff - T-69 - Codex (Phase 12 UI polish/accessibility/release readiness) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Base commit observed: `2aed965` (`Record Phase 11 Browse in TASKS and HANDOFF`).

Previous phase state observed:

- Phase 10 authenticated writes/comments were present (`c167ef0`): Work Detail
  exposes kudos, subscribe/unsubscribe, Mark for Later, AO3 bookmark create, and
  comments through user-initiated authenticated POST repositories.
- Phase 11 Browse/WebView fallback was present (`21ffa1f`, doc commit
  `2aed965`): native `/media` Browse, category fandom lists, fandom work lists via
  Phase 5 search, read-only local indicators, and AO3-only WebView fallback.
- `docs/contracts/CROSS_PLATFORM_UI_BRIDGE.md` and
  `docs/contracts/ANDROID_MATERIAL_HIG_TRANSLATION.md` were still absent. I used
  the downloaded Phase 12 prompt, `docs/android/ANDROID_PORT_PLAN.md`, Apple
  Home/Library/Account source, and `UI_PARITY_CHECKLIST.md` as the effective UI
  bridge, and recorded the missing docs as a known documentation gap.

Dependencies added: none.

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`
- `android/app/src/main/java/io/github/cidy02/kudos/app/MainScaffold.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/home/HomeDashboard.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/home/HomeViewModel.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/home/HomeScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryQuery.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/browse/AO3BrowseParser.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/main/res/drawable/ic_kudos_mark.xml`
- `android/app/src/test/java/io/github/cidy02/kudos/home/HomeDashboardTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/app/NavigationRoutesTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryQueryTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/browse/AO3BrowseParserTest.kt`
- `android/app/src/test/resources/ao3/browse/categories_with_featureless.html`

Screens/components polished:

- Home: replaced the Phase 1 placeholder with a real offline dashboard derived
  from the existing Library snapshot. Shelves: Continue Reading, Favorites,
  Recently Opened, Recently Added. It is privacy-aware, does not call AO3, and
  routes to canonical Work Detail/Reader.
- App shell: kept Home/Library/Browse/Account as the only peer destinations,
  Search as a global action, and Reader out of app chrome. Added Material
  navigation rail for wider screens while retaining bottom navigation on phones.
- Settings: replaced sample/scaffold copy with current DataStore-backed reader,
  privacy, and app setting summaries plus a real reset-to-defaults action.
- Backup: replaced placeholder copy with compatibility/privacy status, v1/v2
  backup notes, merge-only behavior, and disabled import/export buttons with an
  honest document-picker/device-verification explanation.
- Search: removed the disabled Filters button; advanced filters remain a
  documented gap instead of a fake control.
- Account: removed stale text claiming Phase 10 writes/comments were deferred.
- Work Detail: replaced raw AO3 hydration "deferred" errors with calmer
  product-facing copy.
- Library: fixed Claude-flagged Phase 8 issues by excluding obscured mature works
  from free-text search and preferring chapter-ratio progress over in-chapter
  scroll fraction for multi-chapter works.
- Browse parser: incorporated Claude's parity fix so featureless media categories
  are skipped like Apple `mediaCategories()`.
- Launcher mark: changed the vector red from old `#8B1E1E` to AO3 red `#990000`.

Accessibility/adaptive/theme changes:

- Home work cards include concise title/author semantics and visible text actions.
- Navigation uses Material bottom navigation on compact widths and navigation rail
  at wider widths (`>= 840dp`).
- Home state labels are textual (Downloaded, Favorite, Finished, percentage read),
  not color-only.
- Settings/Backup use readable grouped cards instead of placeholder prose.
- No new color palette or dependency was introduced; icon/theme red now matches
  the existing `Ao3Red`/settings-contract value.

Security/privacy/release checks:

- Did not change backup schema, auth/session storage, AO3 request cadence/write
  semantics, Readium progress semantics, Apple source, or Xcode project.
- Confirmed Android manifest already disables Auto Backup and excludes root data
  from cloud/device transfer.
- Backup UI explicitly states AO3 passwords, cookies, CSRF tokens, and sessions
  are excluded.
- Release minification remains disabled; R8 keep-rule smoke testing is still a
  pre-release follow-up if minification is enabled later.

Tests added:

- `HomeDashboardTest`: verifies Home uses Library-derived shelves and respects
  mature-content hide privacy.
- `NavigationRoutesTest`: verifies top-level destinations remain Home/Library/
  Browse/Account and Search stays out of the peer tab set; also pins titles for
  Phase 10/11 routes.
- `LibraryQueryTest`: verifies free-text search does not reveal obscured work
  metadata and progress prefers chapter ratio before scroll offset.
- `AO3BrowseParserTest`: verifies featureless media categories are skipped and
  an all-featureless media page surfaces a parser structure error.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.home.*' --tests 'io.github.cidy02.kudos.app.*'`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.library.*'`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleRelease`
  - Result: BUILD SUCCESSFUL, 235 JVM tests, 0 failures.
  - Non-fatal warnings: release native strip fallback for bundled libraries
    (`libandroidx.graphics.path.so`, `libdatastore_shared_counter.so`) and existing
    Readium experimental API opt-in warnings in release Kotlin compilation.

Known gaps / needs human review:

- No emulator/device screenshots were captured in this session.
- No TalkBack, dynamic font-scale, keyboard/focus, tablet/landscape, or WebView
  manual verification was performed.
- Missing Material/HIG translation docs named in the Phase 12 prompt remain a doc
  gap.
- Home does not yet include AO3 Subscriptions or Recently Updated shelves.
- Advanced Search filter UI is still deferred on Android.
- Backup document picker import/export UI is still disabled.
- Direct raw AO3 work-id/URL native hydration is still deferred until full work
  detail parsing.
- Live AO3 login/account-list/write/comment verification with a safe test account
  is still required.
- Encrypted-at-rest AO3 session storage remains a known Phase 9 gap.
- Account collections/dashboard, native bookmark edit/update, custom font import,
  and full reader settings UI remain incomplete.
- Distribution policy, AO3/OTW policy, GPL/source-offer, and third-party NOTICE
  review still require human release review.

Final parity audit recommendation:

- Android is ready for a final human parity audit pass, not for public release yet.
  The code builds, tests, lints, and assembles release, but manual device and live
  AO3 verification are still required before declaring feature parity complete.

## Handoff - T-68 - Claude (Phase 11 Browse + WebView fallback) - 2026-06-27

Branch: `kudos-ao3-reader-android` (merge commit `21ffa1f`).

Phase 11 was built in an isolated worktree branch
(`kudos-ao3-reader-android-phase-11-browse`, base `1d9a7c9`) in parallel with
Codex's Phase 10, then merged into `kudos-ao3-reader-android`. The merge had only
additive `AppNavHost.kt` conflicts (kept both sides); `Routes.kt` /
`KudosAppContainer.kt` auto-merged; the new `network/ao3/browse`, `browse`, `web`
packages did not overlap Phase 10. Combined tree verified clean:
`:app:clean :app:assembleDebug :app:testDebugUnitTest` → 226 tests, 0 failures.

Full detail (design decisions, files, URL/WebView policy, known gaps) lives in
[`docs/ai/PHASE_11_BROWSE_HANDOFF.md`](PHASE_11_BROWSE_HANDOFF.md). The phase-11
worktree/branch were removed after merge.

## Handoff - T-67 - Codex (Phase 10 Authenticated Writes and Comments) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Base commit observed: `1d9a7c9` (`Verify Android Phases 0-5 and fix confirmed findings`).

Previous phase state observed:

- Phase 9 auth/session/account work was present and reused: visible AO3 WebView
  login, app-private no-backup session file, AO3-only cookie header generation,
  authenticated GET support, session expiry handling, and read-only account lists.
- Phase 4 networking was present and reused: `OkHttpAO3Client`, 3-slot
  coordinator, retry policy, overload detector, login redirect mapping, and GET
  coalescing.
- Phase 6/7 surfaces existed: canonical Work Detail, local save/download actions,
  `EndOfWorkActions`, and Reader route. Reader did not yet have a true Readium
  end-of-work trigger.

Dependencies added: none.

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosAppContainer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/`
- `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/reader/EndOfWorkActions.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3AuthenticatedPostTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writes/`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/`
- `android/app/src/test/resources/ao3/writes/`
- `android/app/src/test/resources/ao3/comments/`

Authenticated POST behavior:

- Added explicit form POST support to `OkHttpAO3Client` through
  `AO3FormPostClient.postForm`.
- POSTs use the existing AO3 request coordinator and centralized User-Agent.
- POSTs are not GET-coalesced and the retry policy never auto-retries non-GET
  methods; 429/overload/auth-required are surfaced for manual retry/re-login.
- Form bodies use ordered RFC3986-style percent encoding matching Apple's
  `AO3AuthService.formEncoded`.
- `DefaultAO3AuthenticatedClient` attaches cookies only through Phase 9
  `AO3AuthRepository.authenticatedHeaders`, so non-AO3 targets do not receive
  AO3 cookies.

Token/form parsing behavior:

- Parses fresh `authenticity_token` values from hidden inputs and
  `<meta name="csrf-token">`.
- Parses default comment/bookmark pseud IDs.
- Parses AO3 validation errors from `.errorlist`, `.error`, and `.flash.error`.
- Parses subscribe vs unsubscribe state from AO3 subscription forms.

Writes implemented:

- Kudos: fetches the work page, parses a token, posts once to `/kudos.js` with
  AO3 AJAX headers, and treats AO3's "already left kudos" 422 as a confirmed
  already-done state.
- Subscribe/unsubscribe: fetches the work page, detects current form state, posts
  either subscribe fields to `/users/<username>/subscriptions` or `_method=delete`
  to the unsubscribe form action.
- Mark for Later: fetches the work page, parses a token, posts once to
  `/works/<id>/mark_for_later`; does not save to local Library.
- AO3 bookmark: implements basic native create with notes, tags, private, rec,
  and default pseud where parseable. Native edit/update of an existing AO3
  bookmark is deferred; use Open on AO3 as the honest fallback for edit/update.

Comments behavior:

- Added work/chapter `AO3CommentTarget` models.
- Public comment thread loading uses normal GETs when comments are public.
- Comment parser reads author, date, body, Unicode, simple nesting/depth, empty
  state, deleted/hidden-ish comments, form action/token/pseud, auth-required, and
  overload states.
- Comment submission fetches the authenticated page/form first, rejects empty
  comments locally, then posts exactly one form body. Confirmed success can reload
  the thread; validation errors are surfaced.
- Work Detail has a Comments action. Reader exposes Comments in reader chrome
  when the saved work has a canonical AO3 work URL. True end-of-work detection and
  chapter-context routing remain deferred because the Readium navigator end hook
  is not wired yet.

UI behavior:

- Work Detail AO3 actions now call real repositories for Kudos,
  Subscribe/Unsubscribe, Mark for Later, AO3 Bookmark, and Comments.
- Login remains explicit through the existing AO3 login screen; write failures
  surface auth-required rather than silently logging in or retrying.
- Local Library state and AO3 account state remain separate.
- This phase intentionally did not do final Material/HIG polish.

Tests added:

- POST transport: no auto-retry, auth-required redirect mapping, centralized
  User-Agent, form-body encoding, overload mapping.
- Parsers: token hidden/meta parsing, pseud parsing, subscription state, write
  error parsing, comment Unicode/nesting/empty state.
- Repositories: kudos body/AJAX headers/already-kudosed, subscribe/unsubscribe,
  Mark for Later, bookmark create fields, missing-token validation, comment load,
  empty comment rejection, comment submission body, comment validation errors.
- Fixtures are small artificial/sanitized snippets under `android/app/src/test/resources/ao3/writes/`
  and `android/app/src/test/resources/ao3/comments/`.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.network.ao3.*' --tests 'io.github.cidy02.kudos.network.ao3.writes.*' --tests 'io.github.cidy02.kudos.network.ao3.comments.*'`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
  - Result: BUILD SUCCESSFUL, 201 JVM tests, 0 failures.

Manual verification:

- Not performed. No live AO3 login/write/comment flow was run. Native write
  selectors/endpoints are fixture-tested and Apple-reference-matched, but must be
  manually verified with a safe test AO3 account before trust/release.

Known gaps / deferred:

- No encrypted-at-rest session storage yet; Phase 9's app-private/no-backup
  session storage gap remains.
- Native AO3 bookmark edit/update remains deferred.
- Reader has a Comments entry, but not a true end-of-work panel and not
  chapter-specific routing because current Android Readium integration does not
  expose that context.
- Work Detail subscribe button uses a generic "Subscribe/Unsubscribe" label until
  the fetched form state is known.
- No live AO3 write verification and no screenshots/device verification.
- No final UI polish pass.

Recommended next phase:

Manual device verification of Phase 9 login plus Phase 10 writes/comments with a
safe AO3 test account. Then Phase 11 Browse/WebView fallback or a focused Claude
review of Phase 10's live-selector assumptions before broader UI work.

## Handoff - T-66 - Claude (Phase 0-5 verification + Phase 7 follow-ups) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Scope: (a) finalized the Phase 7 reader review fix, (b) verified Codex's Phases
0-5 the same way Phase 6 was verified (build + tests + multi-agent code review
against the plan/contracts/Apple), and (c) fixed the confirmed findings. No
divergence: my Phase 7 work is the committed Phase 7 (`3d08ca1`); Codex's Phases
8-9 sit cleanly on top; the branch is linear.

Verification method: a 6-reviewer + adversarial-verify workflow (one reviewer per
phase, each grounded in committed code + contracts + Apple source). The first run
was rate-limited (session limit) and produced no usable output; the re-run
confirmed 9 real findings. Build green throughout: `:app:assembleDebug` +
`:app:testDebugUnitTest` = **177 JVM tests, 0 failures**.

Findings fixed (7):

- [HIGH][bug] `WorkDao` used `@Insert(OnConflictStrategy.REPLACE)`; every scalar
  update (favorite/finished/progress) did DELETE+INSERT, firing ON DELETE CASCADE
  on `work_tag_cross_refs` / `collection_work_cross_refs` and silently wiping a
  work's user tags + collection memberships. Changed both `upsert`/`upsertAll` to
  `@Upsert` (in-place update). Added `RoomDaoTest.updatingAWorkPreservesItsTagsAndCollections`.
- [MED][parity] AO3 red accent was `#8B1E1E`; changed `Ao3Red` to `#990000`
  (matches Apple `ThemeManager.ao3Red` + `accentColorHex` default); re-derived
  `Ao3RedDark` to `#660000`.
- [LOW][parity] Sepia theme used the red/green accent; added `SepiaTint`
  (`#9A6732`) and set the Sepia scheme primary+secondary to it (Apple suppresses
  red in Sepia).
- [LOW][parity] `AO3Constants.isLoginUrl` used exact path equality; changed to
  `.contains("/users/login")` to match Apple and catch login-redirect variants.
- [LOW][parity] `AO3SearchUrlBuilder.wordCountExpression` coerced sides to
  positive Int (dropping `10,000`); now passes trimmed raw values through like
  Apple; updated `AO3SearchUrlBuilderTest`.
- [LOW][doc] `SETTINGS_CONTRACT.md` appTheme default row said "existing reader
  theme or light"; corrected to the literal backup-capture default `light` with a
  note about ThemeManager seeding (Android serializer should use `appTheme ?? "light"`).
- [LOW][reader, from Phase 7 review] `ReaderProgressSaver` only flushed on Compose
  dispose; added a `Lifecycle.ON_STOP` flush in `ReaderScreen` (+
  `lifecycle-runtime-compose` dep) so backgrounding reliably saves progress.
- [MED→tightened][bug] `AO3OverloadDetector` matched bare substrings ("capacity",
  "try again later") gated only by ever-present "Archive of Our Own", risking
  false positives on normal pages; tightened to specific phrases and added a
  regression test (`doesNotFlagNormalAo3PageContainingCapacitySubstring`).

Findings intentionally NOT changed (match Apple / low value), reported for the owner:

- [LOW] `AO3RequestCoalescer`: a cancelled caller does not cancel the in-flight
  request (detached SupervisorJob). This MATCHES Apple's detached-Task behavior;
  changing it risks concurrency bugs. Optional robustness improvement only.
- [LOW] `BackupMergeService` collection/saved-search update by UUID overwrites a
  local rename (last-write-wins). This MATCHES Apple's bookmark/font merge
  convention; recommended follow-up is a documenting test, not a behavior change.
- [LOW, low-confidence] `BackupMergeService.mergeFonts` may re-suffix an existing
  font when the snapshot omits its bytes — only reachable once the deferred
  BackupScreen restore UI builds real snapshots; pin with a test when that lands.

Files changed:

- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/WorkDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/theme/Color.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/theme/Theme.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Constants.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3OverloadDetector.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/data/local/RoomDaoTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilderTest.kt`
- `android/app/build.gradle.kts`, `android/gradle/libs.versions.toml` (lifecycle dep)
- `docs/contracts/SETTINGS_CONTRACT.md`

Commands run: `:app:assembleDebug :app:testDebugUnitTest` → BUILD SUCCESSFUL, 177
tests, 0 failures (one earlier run failed spuriously due to two concurrent gradle
daemons — the stale-Kotlin-daemon flakiness noted in prior handoffs; clean re-run
green).

Net: Phases 0-5 are faithful to the plan/contracts/Apple. Cross-checked parity
confirmed for coordinator concurrency (3), reader numeric defaults (18/1.65/28),
SavedSearch.dateAdded, WorkCollection fields, AO3 rating/warning/category IDs,
sort_column mapping, and ZIP-slip protection.

## Handoff - T-65 - Codex (Phase 9 Authentication and Account) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Previous phase state observed:

- Branch was on `kudos-ao3-reader-android` with Phase 7 (`3d08ca1`) and Phase 8
  (`ce62115`) already committed locally. GitHub CLI auth was available; running
  `gh auth setup-git` allowed `git push origin kudos-ao3-reader-android` to
  succeed before Phase 9 started.
- Existing Phase 4-8 seams were present and reused: `OkHttpAO3Client` with
  coordinator/retry/coalescing/login-redirect handling, `AO3SearchParser` and
  `AO3WorkSummary`, canonical `WorkDetailSource.RemoteSummary`, Room-backed
  saved works, Library UX, and Reader route.
- The only unrelated untracked path observed was `.idea/`; it was left untouched.

Dependencies added: none.

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosAppContainer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountListRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountListType.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountUiState.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountViewModel.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/auth/`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParser.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/auth/AO3AuthTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/account/AccountRepositoryTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt`
- `android/app/src/test/resources/ao3/account/`

Login / WebView behavior:

- Android now uses a visible WebView login flow at
  `https://archiveofourown.org/users/login`.
- The user enters credentials only into AO3's real page. Android does not provide
  a native password form, does not store passwords, and does not implement hidden
  repeated login attempts.
- Login completion is detected by AO3 logged-in page signals (`body.logged-in` or
  logout link/form) plus a username from `#greeting a[href^="/users/"]`.
- On success, the app captures AO3 cookies from Android `CookieManager`, saves an
  `AO3Session`, installs cookies back into `CookieManager`, and returns to the
  Account screen.
- Cancel and Reload controls are available. Manual/device verification was not
  performed in this environment.

Session / cookie storage behavior:

- `AO3Session`, `AO3StoredCookie`, `AO3CookieJar`, `AO3CookieStore`,
  `FileAO3SessionStore`, and `AO3AuthRepository` were added under `auth/`.
- Cookie headers are generated only for HTTPS AO3 hosts and matching cookie paths.
  Cookies are not attached to third-party hosts.
- Logout clears the app session store and expires AO3 cookies known to
  `CookieManager`; it does not touch Library data, backups, reading history, or
  saved works.
- Auth-required account responses call `sessionDidExpire()`, clear local session
  state, and surface a re-login state.

Secure storage decision / gap:

- Phase 9 stores session JSON in `context.noBackupFilesDir/ao3/session.json`,
  which is app-private and outside Android Auto Backup/device transfer. The
  manifest backup rules already exclude all app data, and no `.kudosbackup`
  code reads this session path.
- Encryption at rest with Tink/Android Keystore was **deferred** to avoid a large
  new crypto/storage dependency inside this phase. This is the main security gap:
  session cookies are app-private and no-backup, but not encrypted by this commit.

Authenticated request behavior:

- Account list requests reuse the Phase 4 `AO3Client.get(url, headers)` path.
- `AO3AuthRepository.authenticatedHeaders(url)` attaches only the AO3 `Cookie`
  header; the existing client continues to add the centralized User-Agent and
  apply coordinator/retry/coalescing behavior.
- Login redirects and logged-out pages map to `AO3Error.AuthenticationRequired`.
- No authenticated POST/write support was added.

Account list URLs implemented:

- Marked for Later: `/users/<username>/readings?show=to-read`
- History: `/users/<username>/readings`
- AO3 Bookmarks: `/users/<username>/bookmarks`
- Subscriptions: `/users/<username>/subscriptions?type=works`
- My Works: `/users/<username>/works`
- Usernames are path-encoded through OkHttp `HttpUrl.Builder`.

Account parsers implemented:

- `AO3UsernameParser`: logged-in detection, username extraction, login-required
  page detection.
- `AO3AccountParser`: typed account-list parsing with overload and
  login-required errors.
- Marked for Later, History, and My Works reuse search-style `li.work.blurb`.
- Bookmarks use the existing AO3 work-summary parser with `li.bookmark.blurb`,
  skipping non-work bookmarks.
- Subscriptions parse sparse `dl.subscription dt` work rows and skip series/user
  subscriptions.
- `AO3SearchParser` gained `parseWorksListPage(html, page, blurbSelector)` so
  bookmarks can reuse the same `AO3WorkSummary` path.

Account UI behavior:

- Account screen now has signed-out, restoring, signing-in, signed-in, expired,
  and error states.
- Signed-out state explains AO3 login is optional, uses AO3's real login page,
  never stores the AO3 password, and is unofficial/not AO3/OTW-affiliated.
- Signed-in state shows the username, session note, Logout, and read-only list
  entry points.
- Account list screens show loading, empty, failed/retry, auth-required/re-login,
  simple pagination, and AO3 work cards.
- Tapping an account-list work opens canonical Work Detail through
  `WorkDetailSource.RemoteSummary`; account-derived works are not auto-saved.

Tests added:

- Auth/session/cookie: `AO3SessionStoreTest`, `AO3CookieStoreTest`,
  `AO3CookieJarTest`, `AO3AuthenticatedRequestTest`,
  `AO3WebLoginInspectionTest`, `AccountLogoutTest`.
- Account URLs/parsers: `AO3UsernameParserTest`, `AO3AccountUrlsTest`,
  `AO3MarkedForLaterParserTest`, `AO3HistoryParserTest`,
  `AO3BookmarksParserTest`, `AO3SubscriptionsParserTest`,
  `AO3AccountListEmptyStateParserTest`,
  `AO3AccountListLoginRequiredParserTest`,
  `AO3AccountListOverloadParserTest`.
- Repository: `AccountRepositoryAuthRequiredTest`,
  `AO3AuthRedirectDetectionTest`, `AccountRepositoryPaginationTest`,
  `AccountListItemsDoNotAutoSaveTest`.
- Fixtures are hand-built/sanitized under `android/app/src/test/resources/ao3/account/`.

Commands run:

- `gh auth setup-git`
  - Result: succeeded.
- `git push origin kudos-ao3-reader-android`
  - Result: succeeded before Phase 9 edits; pushed through Phase 8 (`ce62115`).
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.auth.*' --tests 'io.github.cidy02.kudos.account.*' --tests 'io.github.cidy02.kudos.network.ao3.account.*'`
  - Result: initially found the WebView inspection-result parser bug, then passed
    after switching to a JVM-safe regex decoder.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.account.*'`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
  - Result: BUILD SUCCESSFUL, 175 JVM tests, 0 failures, 0 errors, 0 skipped.

Manual verification:

- Not performed. No emulator/device AO3 login was run from this environment.
- Must be manually verified with a non-private test AO3 account before trusting
  selectors/cookie behavior against live AO3.

Known gaps / deferred:

- Session file is app-private/no-backup but not encrypted at rest. Add Tink or an
  Android Keystore-backed encryption layer before public release.
- No hidden/automatic login flow; visible WebView login only.
- No authenticated writes: kudos, comments, subscribe/unsubscribe, AO3 bookmark
  create/update, Mark for Later mutation, and destructive account actions remain
  Phase 10+.
- No account collections list in Android Phase 9.
- No live AO3 verification; account selectors and URLs are fixture-tested only.
- WebView UI has not been screenshot/device verified.

Recommended next phase:

Manual device verification of Phase 9 login/session/account lists first. Then
Phase 10 authenticated writes/comments only after confirming live auth works and
after approving the write/CSRF safety scope.

## Handoff - T-64 - Codex (Phase 8 Library UX) - 2026-06-27

Branch: `kudos-ao3-reader-android`

Base observed:

- Started from local commit `3d08ca1` (`Add Android Readium reader integration`),
  with the branch clean and ahead of `origin/kudos-ao3-reader-android` by one
  unpushed Phase 7 commit. GitHub push auth was not configured in this
  environment, so Phase 7 remained local at pickup.
- Phase 6/7 pieces were present: Room `SavedWork`, user tag and collection
  relations, `WorkRepository`, file-backed `hasEpub`, canonical local Work Detail,
  and Reader route/opening for downloaded works.

Dependencies added: none.

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosAppContainer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryFilter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryModels.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryPrivacy.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryQuery.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibrarySort.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryViewModel.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryQueryTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryRepositoryTest.kt`

Library sections implemented:

- Continue Reading: works where `SavedWork.isInProgress` is true, sorted by
  `lastReadDate ?: dateAdded` descending; direct `Read` is offered when a visible
  row has `hasEpub`.
- Reading History: works with `lastReadDate`, sorted descending; opens Work Detail.
- Recently Added: sorted by `dateAdded` descending.
- Favorites: favorite works, sorted by last-read recency.
- All Saved Works: searchable/filterable/sortable saved-work list.

Filters implemented:

- Favorite only.
- Finished / Unfinished.
- Downloaded / Not downloaded (`hasEpub`).
- User tag membership.
- Collection membership.
- Query-layer support also exists for completion, rating, warnings, categories,
  fandoms, relationships, characters, and freeforms, though the Phase 8 UI only
  exposes the minimum core filters plus tag/collection facets.

Sorts implemented:

- Recently added.
- Last read.
- Title.
- Author.
- Word count.
- Kudos.

Local search behavior:

- Pure offline search only; no AO3/network calls.
- Case-insensitive matching across title, author, summary, rating, language,
  chapters, series title, AO3 tag fields, user tags, and collection names.

User tags behavior:

- Library snapshots attach each work's existing user tags via `WorkRepository`.
- The screen lists all user tags as filter chips and shows tags on saved-work cards.
- Create/remove remains in Work Detail from Phase 6; rename/delete management is
  deferred.

Collections behavior:

- Library snapshots attach collection membership via existing collection DAOs.
- The screen lists collections as filter chips and shows collection membership on
  saved-work cards.
- Create/remove membership remains in Work Detail from Phase 6; collection
  rename/delete/detail screens are deferred.

Privacy behavior:

- Added `LibraryPrivacy` classifier. With privacy off, all works are visible.
- In `Hide` mode, Mature/Explicit works are removed from Library results.
- In `Obscure` mode, Mature/Explicit works remain in the list but card details are
  masked. Biometric/session reveal UI is intentionally deferred.

Navigation behavior:

- Tapping Details opens canonical Work Detail with `WorkDetailSource.LocalWork`.
- Downloaded, visible works expose a direct Read action that uses the existing
  Phase 7 Reader route; Work Detail still remains the management surface.
- Search/Browse remote Work Detail behavior was not changed.

Tests added:

- `LibraryRepositoryAllWorksTest` verifies Room-backed Library snapshots include
  saved works, user tags, and collections, and ignore non-saved/history records.
- `LibraryQueryTest` covers favorite, finished/unfinished, downloaded/not
  downloaded, user tag, collection, combined filters, deterministic sorts, local
  search, Continue Reading, Reading History, Recently Added, UI-state no-results,
  non-mutating filtering, missing-EPUB state, and privacy hide/obscure behavior.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.library.*'`
  - Result: BUILD SUCCESSFUL.
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
  - Result: BUILD SUCCESSFUL, 155 JVM tests, 0 failures, 0 errors.

Known gaps / deferred:

- No AO3 update checking or Recently Updated section; do not add background
  crawling without a later approved phase.
- No biometric reveal UI for obscured Mature/Explicit works.
- No full tag/collection management screens (rename/delete/detail).
- No bulk actions.
- Advanced AO3 metadata facet panel exists only in query support, not UI.
- Home remains mostly placeholder; light Home data wiring can be a later focused
  pass.
- No device/emulator visual verification was performed.

Recommended next phase:

Device verification for Phase 7/8 reader + Library flows, then Phase 9
Account/Auth only if the human approves that phase.

---

## Handoff - T-63 - Claude (Phase 7 Readium Reader) - 2026-06-26

Branch: `kudos-ao3-reader-android`

### Codex takeover finalization

The human asked Codex to take over after Claude hit a usage limit with this work
still uncommitted. Codex reviewed the Phase 7 prompt, plan/contract docs, existing
handoffs, and the uncommitted reader implementation; kept Claude's architecture;
and made four focused contract fixes before landing:

- `ReaderLocatorCodec` now requires the Android locator envelope version to match
  the current adapter version before same-platform restore is allowed.
- `ReadiumProgressAdapter` now stores `lastScrollFraction` from Readium's
  per-spine `locations.progression` first, falling back to whole-book
  `totalProgression` only when needed.
- `ReaderLinkHandler` now validates the parsed URL host instead of substring
  matching `archiveofourown.org` anywhere in the URL.
- Reader AO3 work links now route into the native Work Detail destination with
  `WorkDetailSource.Ao3WorkId`; full raw-id hydration is still deferred to the
  Work Detail parsing phase.

### Previous phase state observed

- Phases 0–6 implemented and committed (Codex Phases 0–6 + Claude's T-62 Phase 6
  review fix). Working tree had only the uncommitted T-62 Phase 6 changes
  (`WorkImporter`/`WorkLifecycleTest`/`TASKS`/`HANDOFF`) plus, now, this Phase 7
  work. No unexpected third-party changes.
- Phase 6 gave us: `SavedWork` with `readiumLocator: String?`, `lastSpineIndex`,
  `lastScrollFraction`, `lastReadDate`; app-private EPUB storage at
  `files/works/<UUID>.epub` via `WorkFileStore`; `WorkRepository`; Work Detail
  with a disabled "Read" button and a `Routes.Reader` placeholder.

### Integration approach (Compose ↔ Fragment)

Readium's navigator is Fragment/View-based (reflowable EPUB uses an internal
WebView), so Compose hosts it through a single seam, `ReadiumNavigatorHost`:
`AndroidView { FragmentContainerView }` + a `FragmentTransaction` on the
activity's `supportFragmentManager`, with `EpubNavigatorFactory.createFragmentFactory(...)`
set as the `fragmentFactory`. `MainActivity` was changed from `ComponentActivity`
to `androidx.fragment.app.FragmentActivity` to provide `supportFragmentManager`
(it still uses `setContent`/Compose). All Readium types stay inside
`reader/readium/`; the rest of the reader layer is engine-agnostic.

### Dependencies added

- `org.readium.kotlin-toolkit:readium-shared:3.3.0`
- `org.readium.kotlin-toolkit:readium-streamer:3.3.0`
- `org.readium.kotlin-toolkit:readium-navigator:3.3.0`
- `com.android.tools:desugar_jdk_libs:2.1.5` (core library desugaring)
- `androidx.fragment:fragment-ktx:1.8.9` (Readium exposes fragment only at
  runtime; we need it on the compile classpath; 1.8.9 matches the resolved graph)

### minSdk / desugaring decision

minSdk is **26**, but Readium 3.3.0 publishes AAR metadata that *requires* core
library desugaring regardless of minSdk (the build fails `checkDebugAarMetadata`
without it). So `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring`
were added. No minSdk change.

### R8 / proguard

None added for debug. Release minification is not configured in this module yet;
when it is, Readium keep rules will be needed (documented as a follow-up, not a
Phase 7 deliverable since there is no release build config here).

### Files changed

New (engine-agnostic, `reader/`): `ReaderError`, `ReaderProgress`,
`ReaderRestoreTarget`, `ReaderLocatorCodec`, `ReaderProgressMapper`,
`ReaderOpenResult`, `ReaderRepository`, `ReaderProgressSaver`,
`ReaderLinkHandler`, `EndOfWorkActions`, `ReaderUiState`, `ReaderViewModel`,
`ReaderScreen`; `reader/settings/`: `ReaderColorTheme`, `ReaderPreferences`,
`ReaderSettingsMapper`. New (Readium adapter, `reader/readium/`):
`ReadiumPublicationOpener`, `ReadiumProgressAdapter`, `ReadiumSettingsAdapter`,
`ReadiumNavigatorHost`.
Deleted: `reader/ReaderPlaceholderScreen.kt`.
Modified: `MainActivity.kt`, `app/AppNavHost.kt`, `app/KudosAppContainer.kt`,
`works/WorkDetailScreen.kt`, `app/build.gradle.kts`, `gradle/libs.versions.toml`.
New tests (`reader/` + `reader/settings/` + `reader/readium/`): `ReaderProgressMappingTest`
(locator codec + mapper + fallback + legacy-field preservation),
`ReaderLinkHandlerTest`, `ReaderProgressSaverTest`, `ReaderRepositoryTest`
(Robolectric + in-memory Room + temp file store), `ReaderSettingsMapperTest`,
`ReaderThemeMappingTest`, `ReadiumProgressAdapterTest`.

### Reader open behaviour

`WorkDetail` "Read" is enabled only when `hasEpub`. `ReaderRepository.open`
returns typed failures: `WorkNotFound`, `NotDownloaded` (no EPUB), `FileMissing`
(`hasEpub` true but file gone), else `Success(work, path, restoreTarget, prefs)`.
`ReaderScreen` shows Loading → opens the publication off-thread via
`ReadiumPublicationOpener` → Reading (navigator) or a friendly error with
Retry / Back / (for FileMissing) "Remove offline copy" → `markEpubMissing`
(only explicit, never automatic). Corrupt/missing EPUBs surface errors, never
crash.

### Progress restore / persistence

Restore order (READER_STATE_CONTRACT): a platform-compatible locator first, then
`lastSpineIndex`+`lastScrollFraction`, else the beginning. Android-written
locators are stored as a self-describing envelope
`{"platform":"android","engine":"readium-kotlin","version":1,"locator":{…}}`
(`ReaderLocatorCodec`); foreign/Apple, version-incompatible, or unwrapped
locators decode to null and fall back. On every save,
`ReaderProgressMapper.applyProgress` refreshes `lastSpineIndex`,
`lastScrollFraction` (per-spine progression, clamped 0..1), `readiumLocator`
(envelope), and `lastReadDate`, and never touches favorite/finished/tags/etc.
Saves are debounced (`ReaderProgressSaver`, 1.5s) and flushed on reader dispose.

### Settings mapping + fallbacks

`ReaderSettingsMapper` → neutral `ReaderPreferences` → `ReadiumSettingsAdapter`
→ `EpubPreferences`. Mapped: theme **Light/Dark/Sepia** (honors
`matchAppReaderTheme`; `appTheme=System` falls back to Light), scroll vs paged,
two-page columns, font size (% of 18pt base), line height, page margins (×28pt
base, clamped 0.5–2.0), justify, letter/word spacing. Deferred fallbacks: bold
(`readerBoldText`) and custom fonts (`readerFontID`) are NOT applied to Readium
yet — Readium's `fontWeight`/`fontFamily` are value-class prefs and custom-font
import/registration is out of scope; the neutral prefs still carry them.

### Link handling

`ReaderLinkHandler.classify` (pure, tested, host-gated) maps AO3 work URLs →
WorkDetail, AO3 tag URLs → TagSearch (decoded), other absolute URLs → External (opened via
`ACTION_VIEW`), relative/in-publication → Unhandled (navigator handles). In-reader
wiring forwards external links and routes AO3 work links into the native Work
Detail destination; deep raw-id hydration and tag→Search routing are scaffolded
but deferred (Search route takes no args yet).

### Tests added / results

- New reader tests cover: locator envelope round-trip + foreign/raw rejection,
  version-incompatible locator rejection, restore preference order, fallback on
  invalid/foreign locator, legacy fields populated alongside a locator, per-spine
  fallback progression, host-gated reader link routing, progress save preserving
  user state + updating `lastReadDate`, debounce + flush, settings/theme mapping,
  and repository open states (not-found / not-downloaded / file-missing / success
  / reopen-restores).
- `./gradlew :app:compileDebugKotlin` → SUCCESS.
- `./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.reader.*' --tests 'io.github.cidy02.kudos.reader.readium.*'` → BUILD SUCCESSFUL.
- `./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
  → BUILD SUCCESSFUL, **135 JVM tests, 0 failures, 0 errors** (was 100 after T-62).

### Manual verification

NOT performed — no emulator/device in this environment. The app-owned layer is
fully unit-tested; the actual Readium rendering, Fragment lifecycle, WebView
behaviour, on-device progress restore, and theme application can only be
confirmed on a device. `ReadiumNavigatorHost` compiles against the Readium 3.3.0
API (verified via the resolved AAR signatures) but is intentionally not exercised
by JVM tests. Suggested manual checklist is in the Phase 7 prompt.

### Known gaps / deferred

- Live reader rendering + Fragment-in-Compose lifecycle unverified on device.
- Guaranteed save on process death (only debounced + dispose-flush today).
- Bold / custom-font application to Readium; full reader chrome & settings sheet.
- Deep link hydration (raw AO3 work id → full metadata, tag→Search),
  end-of-work series/next.
- Release R8 keep rules (no release build config in module yet).

### Recommended next phase

Phase 8 (Library UX) or a device-verification pass for the reader. If verifying
the reader: build to a device, open a downloaded work, confirm render + resume +
theme; then iterate on `ReadiumNavigatorHost` lifecycle if needed.

---

## Handoff - T-62 - Claude (Phase 6 takeover review) - 2026-06-26

Branch: `kudos-ao3-reader-android`

Context: Took over for Phase 6 (Work Detail + Save/Download) per the Phase 6
takeover prompt. On inspection, Codex had **already implemented and committed
the full Phase 6 lifecycle** in commit `d14e97e` ("Add Android work detail save
download lifecycle"), with a clean working tree. Per the takeover rules I did
not rewrite Codex's work; I reviewed it, verified the build/tests, and fixed one
clear bug.

Verification performed (committed Codex state):

- `./gradlew :app:assembleDebug :app:testDebugUnitTest` — BUILD SUCCESSFUL,
  99 JVM tests, 0 failures.
- Reviewed `WorkImporter`, `WorkMetadataMerger`, `WorkFileStore`,
  `AO3EpubDownloader`, `AO3WorkMetadataParser`, `WorkRepository`, `AppNavHost`,
  and the lifecycle tests against the contract. All sound: file-store rejects
  non-UUID/unsafe paths, downloads validate ZIP signature + reject HTML,
  `hasEpub` is set only after the file write, merge preserves local user state,
  `workTagsFetched` is gated on a non-empty canonical fetch, and Library/Work
  Detail share one canonical screen across remote-summary and local-id sources.

Bug fixed:

- `WorkImporter.persistDownloadedEpub` applied `work.copy(..., isFinished =
  false)` on every successful download, which would silently clear the user's
  Finished marker whenever a previously-finished work was re-downloaded. This
  contradicts the contract ("preserve local user state: `isFinished`") and the
  merger, which already preserves it. Removed the `isFinished = false` override
  so only the file-backed flags (`hasEpub`, `isSaved`) change on download.

Test added:

- `WorkImporterLifecycleTest.downloadPreservesExistingFinishedState` — saves a
  finished+favorite work, downloads it, and asserts `hasEpub` becomes true while
  `isFinished` and `isFavorite` are preserved.

Files changed (this handoff):

- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/works/WorkLifecycleTest.kt`
- `TASKS.md`
- `docs/ai/HANDOFF.md`

Commands run + results:

- `./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.works.*'` —
  passed.
- `./gradlew :app:assembleDebug :app:testDebugUnitTest` — BUILD SUCCESSFUL,
  100 JVM tests, 0 failures.

Known gaps / deferred: unchanged from Codex's T-61 handoff below (Readium, auth,
authenticated AO3 writes/lists, EPUB metadata parsing, full Library UX, advanced
download queue). Recommended next phase remains Phase 7 (Readium Reader).

---

## Handoff - T-61 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `7b09348`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/app/src/main/java/io/github/cidy02/kudos/KudosApplication.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/MainActivity.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosApp.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosAppContainer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/MainScaffold.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/CollectionDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/TagDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/WorkDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/files/FileWriteResult.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/files/WorkFileStore.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3HttpResponse.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3DownloadUrlBuilder.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3EpubDownloader.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadata.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadataParser.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadataRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailSource.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkMetadataMerger.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkTags.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/files/WorkFileStoreTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkNetworkTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/works/WorkLifecycleTest.kt`

Dependencies added:

- None.

Work Detail behavior implemented:

- `WorkDetailSource` now supports `LocalWork`, `RemoteSummary`, `RemoteUrl`,
  and `Ao3WorkId`.
- `AppNavHost` carries the selected source so Search opens remote summaries and
  Library opens local saved-work ids into the same `WorkDetailScreen`.
- `WorkDetailScreen` hydrates from either a remote `AO3WorkSummary` or a local
  `SavedWork` Room record.
- The screen displays title, author, fandoms, rating, warnings, categories,
  relationships, characters, freeforms, summary, language, words, chapters,
  kudos, comments, hits, series metadata, completion state, source URL, saved
  state, downloaded state, favorite state, and finished state where available.
- Read and authenticated AO3 actions are visible but disabled/deferred; no
  reader opening or AO3 write behavior was implemented.

Save/download lifecycle implemented:

- `KudosAppContainer` creates the Room database, app-private file store, AO3
  client, work repository, metadata repository, EPUB downloader, importer, and
  Library repository.
- `WorkImporter.saveMetadataOnly(summary)` creates or updates a saved Room record
  with `isSaved = true` and `hasEpub = false`.
- `WorkImporter.download(summary)` creates/updates the saved Room record, then
  downloads the EPUB and sets `hasEpub = true` only after the file write succeeds.
- Failed downloads leave the metadata record intact but do not mark `hasEpub`
  true.
- Existing saved works are matched by source URL before creating a new UUID,
  avoiding duplicate local records for the same AO3 work in this phase.
- Local actions implemented: favorite toggle, finished toggle, add/remove user
  tags, add/remove collections, delete local EPUB, and remove from Library.

File storage paths:

- EPUB files are written under app-private storage:

```text
files/works/<UUID>.epub
```

- `WorkFileStore` uses the local `SavedWork.id` UUID as the filename.
- Non-UUID/unsafe ids are rejected for EPUB paths.
- Writes go through a temp file in the works directory, then move to the final
  UUID path. Atomic move is attempted first with a normal replace fallback.
- Deleting the local EPUB keeps the Room work record and sets `hasEpub = false`.
- Removing from Library deletes the EPUB file and the Room work record.

Metadata merge policy:

- `WorkMetadataMerger` merges remote search summary, canonical AO3 metadata, and
  any existing local `SavedWork`.
- It preserves local user state: `isFavorite`, `isFinished`, reading progress,
  `lastReadDate`, `lastSpineIndex`, `lastScrollFraction`, `readiumLocator`,
  `knownChapterCount`, and `lastUpdateCheck`.
- Remote metadata fills or updates AO3-derived fields: title, author, summary,
  source URL, rating, language, word count, chapters, kudos, comments, hits,
  warnings, categories, fandoms, characters, relationships, freeforms, series,
  and completion state.
- Blank remote values do not erase existing non-empty local values.

Canonical tag fetch behavior:

- `AO3WorkMetadataRepository` fetches:

```text
/works/<workID>?view_adult=true
```

- `AO3WorkMetadataParser` extracts fandoms, relationships, characters,
  freeforms, warnings, categories, language, words, chapters, kudos, comments,
  and hits using Jsoup selectors matching Apple `parseWorkTags`.
- `workTagsFetched` is set true only when canonical metadata fetch succeeds and
  returns non-empty metadata.
- If canonical fetch fails, save/download proceeds from the search summary and
  `workTagsFetched` remains false.

EPUB download behavior:

- `AO3DownloadUrlBuilder` builds the Apple-matching route:

```text
/downloads/<workID>/work.epub
```

- `AO3Client.getBytes` was added for binary GETs while keeping existing text GETs
  intact.
- OkHttp binary GETs use the Phase 4 coordinator/retry policy and map HTTP,
  login redirect, overload, and network errors to `AO3Error`.
- `AO3EpubDownloader` rejects empty bodies, HTML content types/pages, and
  non-ZIP signatures before allowing the file write.

Library behavior implemented:

- `LibraryScreen` observes Room-backed saved works through `LibraryRepository`.
- It shows an empty state, saved work cards, downloaded/offline status, favorite
  status, finished status, rating, words, chapters, summary, and Details action.
- Tapping Details opens canonical Work Detail from the local saved-work id.
- Full filters, sorting controls, bulk actions, privacy filtering, and richer
  Library UX remain Phase 8 work.

Tests added:

- `WorkMetadataMergerTest`
- `WorkLifecycleRepositoryTest`
- `WorkImporterLifecycleTest`
- `WorkFileStoreTest`
- `WorkFileStoreRejectsUnsafePathTest`
- `AO3DownloadUrlBuilderTest`
- `AO3EpubDownloaderTest`
- `AO3WorkMetadataParserTest`
- `AO3WorkMetadataFetchPartialFailureTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.files.*' --tests 'io.github.cidy02.kudos.network.ao3.work.*' --tests 'io.github.cidy02.kudos.works.WorkMetadataMergerTest'`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.works.WorkLifecycleRepositoryTest' --tests 'io.github.cidy02.kudos.works.WorkImporterLifecycleTest'`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- Focused file/network/parser/merger tests passed.
- Focused Room/lifecycle tests passed.
- Full `:app:testDebugUnitTest` passed.
- Non-clean combined assemble/test/lint exposed stale generated Compose output
  (`AO3WorkCardKt 2.class`), matching the stale-output issue seen in prior phases.
- Clean combined verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 99 JVM tests, 0 failures, 0 errors
  - `:app:lintDebug`

Known gaps / intentionally deferred:

- No Readium integration or real reader opening.
- No EPUB metadata parsing/import; Phase 6 persists AO3 metadata and stores EPUB
  bytes, but does not inspect OPF metadata yet.
- No auth/WebView, cookies, authenticated AO3 lists, comments, kudos,
  subscriptions, Mark for Later, AO3 bookmarks, or AO3 writes.
- Direct `RemoteUrl`/`Ao3WorkId` Work Detail hydration is scaffolded but deferred
  until fuller Work Detail page parsing.
- No advanced download queue, cancellation, progress percentages, or series
  download queue.
- Library has a basic saved-work list only; full filters/sorts/bulk/privacy UX is
  still Phase 8.

Apple/contract ambiguity:

- Apple's remote Work Detail `Read` action imports/downloads lazily. Android
  Phase 6 keeps `Read` disabled because the prompt explicitly says not to
  implement reader opening; users can Save or Download instead.
- Apple imports EPUB metadata before creating `SavedWork`. Android Phase 6 does
  not parse EPUB metadata yet; it uses AO3 search/canonical metadata and records
  this as a Phase 7/import follow-up.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 7 Readium Reader. Build on the file-backed `hasEpub` state and
`files/works/<UUID>.epub` storage, open downloaded EPUBs with Readium Kotlin,
and continuously maintain `lastSpineIndex` plus `lastScrollFraction` alongside
any Android Readium locator.

## Handoff - T-60 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `f1ab0fe`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Error.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryPolicy.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchFilters.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchModels.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParser.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/components/AO3WorkCard.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParserTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepositoryTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilderTest.kt`
- `android/app/src/test/resources/ao3/search_basic.html`
- `android/app/src/test/resources/ao3/search_locked.html`
- `android/app/src/test/resources/ao3/search_no_results.html`
- `android/app/src/test/resources/ao3/search_overload.html`
- `android/app/src/test/resources/ao3/search_series.html`
- `android/app/src/test/resources/ao3/search_unicode.html`

Dependencies added:

- Jsoup `1.22.2` (`org.jsoup:jsoup`) for AO3 HTML parsing.

AO3 filter coverage:

- Ported Android search DTOs for the current Apple filter set:
  query, fandom, characters, relationships, additional tags, excluded fandoms,
  excluded characters, excluded relationships, excluded additional tags, rating,
  rating match, include Not Rated, included/excluded warnings, included/excluded
  categories, crossover, completion, words-from/to, updated window, language,
  and sort.
- Rating ids match Apple/AO3:
  Not Rated `9`, General `10`, Teen `11`, Mature `12`, Explicit `13`.
- Warning ids match Apple/AO3:
  `16`, `14`, `17`, `18`, `19`, `20`.
- Category ids match Apple/AO3:
  `116`, `22`, `21`, `23`, `2246`, `24`.
- Excluded tag names are folded into `work_search[query]` as `-"tag"` and
  deduped in first-seen order.
- Excluded warnings/categories are folded into search text as
  `-archive_warning_ids:<id>` and `-category_ids:<id>`.
- Multiple-rating, rating-plus, rating-minus, and Not Rated combinations are
  folded into AO3 text-search clauses when the single structured rating field
  cannot express them.

Sort mapping:

- `relevance` -> omitted
- `dateUpdated` -> `revised_at`
- `datePosted` -> `created_at`
- `words` -> `word_count`
- `kudos` -> `kudos_count`
- `hits` -> `hits`
- `comments` -> `comments_count`
- `bookmarks` -> `bookmarks_count`
- No `title` or `author` sort option was added.

URL generation behavior:

- Search path is `https://archiveofourown.org/works/search`.
- Empty/blank fields are omitted.
- `page` is 1-based and always emitted, including `page=1`, matching current
  Apple behavior.
- Included warnings/categories use repeated
  `work_search[archive_warning_ids][]` and `work_search[category_ids][]`.
- Word count expressions are:
  `from-to`, `> from`, `< to`, or omitted.
- Android additionally ignores invalid/non-positive word-count sides safely
  instead of sending malformed expressions.

Parser fixtures added:

- `search_basic.html`
- `search_no_results.html`
- `search_series.html`
- `search_locked.html`
- `search_unicode.html`
- `search_overload.html`

Parser behavior:

- Uses Jsoup and AO3-like CSS selectors to parse `li.work.blurb` search results
  into `AO3WorkSummary`.
- Extracts id, title, authors, work URL, fandoms, rating, warnings, categories,
  relationships, characters, freeforms, summary, language, words, chapters,
  comments, kudos, hits, bookmarks, series title/position/url, completion state,
  restricted marker, and updated date when present.
- Preserves first-seen tag order, dedupes normalized tag text, decodes HTML
  entities, normalizes whitespace, and preserves Unicode.
- Empty/no-result pages return an empty work list and current page fallback.
- AO3 overload/capacity fixture throws a typed parser error and repository maps
  it to `AO3Error.Overloaded`.
- Single malformed work blurbs are skipped at page level, matching Apple; direct
  `parseWorkSummary` calls throw a clear missing-structure error.

Repository behavior:

- `AO3SearchRepository` builds the URL, calls the Phase 4 `AO3Client`, parses
  successful bodies off the main dispatcher, and returns `AO3Result<AO3SearchPage>`.
- Network errors pass through unchanged.
- Parser errors surface as non-retryable `AO3Error.Parse`.
- `AO3RetryPolicy` now explicitly does not retry parse errors.

UI behavior implemented:

- `SearchScreen` is no longer static. It has query input, search action, sort
  menu, disabled advanced-filter entry point, loading/error/empty states, results
  list, retry, and previous/next pagination.
- Results render in `AO3WorkCard` with title, author, fandoms, required tags,
  relationships/characters/freeforms, summary, and stats.
- Tapping Details stores the selected remote summary in `AppNavHost` and opens
  `WorkDetailScreen`.
- `WorkDetailScreen` displays the selected AO3 result metadata and placeholder
  actions for Read, Download, Favorite, User Tags, Collections, Open on AO3,
  Kudos, and Comment. No action performs real save/download/auth/write work.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- First `:app:testDebugUnitTest` exposed a test fixture helper visibility issue;
  fixed with local helper names.
- Final `:app:testDebugUnitTest` passed.
- Final combined verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 81 JVM tests, 0 failures, 0 errors
  - `:app:lintDebug`

Known gaps / intentionally deferred:

- No advanced filter sheet UI yet; only query and sort are exposed visually.
- No saved-search persistence or local Library search integration.
- No auth/WebView, cookies, authenticated account lists, comments, kudos,
  subscriptions, bookmarks, Mark for Later, or writes.
- No EPUB download/import, save lifecycle, Readium reader, Room work persistence,
  or production Library wiring.
- No full AO3 Work Detail page hydration; Work Detail displays only search-result
  metadata carried from the selected card.
- No real AO3 traffic was used in tests. Parser behavior is fixture-driven.

Apple/contract ambiguity:

- Apple currently forwards raw word-count strings. The Phase 5 prompt required
  safe invalid normalization, so Android ignores invalid/non-positive sides while
  preserving Apple-compatible output for valid values. No human approval appears
  needed unless exact malformed-input parity is desired.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 6 Work Detail and Save/Download. Build on `AO3WorkSummary`, fetch canonical
work tags/detail where needed, implement EPUB download/import and local save
lifecycle, and keep auth/writes/reader expansion gated to their approved phases.

## Handoff - T-59 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `c3fe55f`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Constants.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Error.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3HttpResponse.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3NetworkConfig.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3OverloadDetector.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RequestCoalescer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RequestCoordinator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Result.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryAfter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryPolicy.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3UserAgent.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`

Dependencies added:

- OkHttp `5.4.0`
- MockWebServer 3 `5.4.0`
- kotlinx-coroutines-core `1.11.0`
- kotlinx-coroutines-test `1.11.0`

Chosen User-Agent:

```text
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15
```

This matches the Apple browser-like User-Agent and contains no private
user/device-identifying data.

Concurrency configuration:

- `AO3NetworkConfig.maxConcurrentRequests = 3`, matching the current Apple
  `AO3RequestCoordinator` parity note.
- `AO3NetworkConfig.minDelayBetweenRequestsMillis = 500`.
- `AO3RequestCoordinator` uses a coroutine semaphore plus a spacing mutex, is
  cancellation-aware through suspending primitives, and does not block the main
  thread.

Retry/backoff behavior:

- Default `maxRetries = 2`.
- GET retries only for `AO3Error.Network`, `AO3Error.RateLimited`,
  `AO3Error.Server`, and `AO3Error.Overloaded`.
- POST/PUT/PATCH/DELETE are never retryable by policy.
- Bad request, auth required, forbidden, not found, generic non-429/non-5xx HTTP,
  and validation errors are not retryable.
- Backoff is 500 ms for the first retry and 1000 ms for the second retry.

Retry-After behavior:

- `AO3RetryAfter` parses integer seconds and RFC 1123 HTTP-date values.
- For 429 and overload errors, retry delay is at least the parsed
  `Retry-After` value when present.
- Invalid `Retry-After` values fall back to the normal backoff.

Request coalescing behavior:

- Concurrent identical GETs share one in-flight operation.
- Coalescing keys include method, canonical URL, and normalized headers.
- Non-GET retry/coalescing policy is documented through `AO3RetryPolicy`; no
  write client method was added in Phase 4.
- In-flight entries are removed on success or failure, so errors do not poison
  future calls.
- Cancelling one waiter does not automatically cancel the shared operation.

Client behavior:

- `AO3Client.get(url, headers)` returns `AO3Result<AO3HttpResponse>`.
- `AO3HttpResponse` exposes final URL, status code, headers, and raw body.
- OkHttp types are kept inside the network layer.
- Status mapping covers success, 400, 401, 403, 404, 429, 5xx, other HTTP,
  network failures, login redirects, validation errors, and overload/capacity
  pages.
- The conservative overload detector checks obvious AO3/AO3-capacity text so
  later parsers do not treat those pages as empty results.

Tests added:

- `AO3RetryAfterTest`
- `AO3RetryPolicyTest`
- `AO3RequestCoordinatorTest`
- `AO3RequestCoalescerTest`
- `AO3ClientStatusMappingTest`
- `AO3ClientRetryTest`
- `AO3ClientDoesNotRetryPostOrNonRetryableErrorsTest`
- `AO3ClientUserAgentTest`
- `AO3ClientCoalescingTest`
- `AO3OverloadDetectorTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- Focused `:app:testDebugUnitTest` initially exposed a MockWebServer 5 API update
  (`close()` instead of `shutdown()`), then a test ordering assumption for
  concurrent different-URL requests. Both were fixed.
- One combined assemble/test/lint run failed because stale generated build output
  contained duplicate `ComposableSingletons$SearchScreenKt` classes after editing
  the Compose placeholder. A clean Gradle run removed the stale output.
- Final clean verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 59 JVM tests
  - `:app:lintDebug`

Known gaps:

- No AO3 search query builder or search UI integration.
- No AO3 HTML parsing/Jsoup.
- No auth/WebView, cookies, authenticated requests, or write actions.
- No EPUB download/import, Readium, comments, account lists, or production Library
  networking.
- No persistent HTTP cache beyond OkHttp defaults.
- No real AO3 traffic was used in tests.

Deliberate deviations from Apple behavior:

- None requiring human approval. Android matches the documented 3-slot default,
  browser-like User-Agent, transient GET retry policy, and Retry-After behavior.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 5 AO3 search/query building and parsing from an approved prompt. Reuse this
network layer; keep auth, writes, reader, EPUB import/download, and production
Library wiring out unless the Phase 5 prompt explicitly expands scope.

## Handoff - T-58 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `02ad56a`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupErrors.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupExporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupJson.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupPaths.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupValidator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupVersion.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`

Dependencies added:

- Kotlin serialization compiler Gradle plugin
  `org.jetbrains.kotlin.plugin.serialization` using the existing Kotlin/Compose
  compiler version `2.3.21`.
- No new runtime JSON dependency; Phase 3 uses the existing
  `kotlinx-serialization-json` runtime added in Phase 2.

Backup format implemented:

- Current Apple v1 directory-backed `.kudosbackup` manifest decoding and
  best-effort directory import where Android can access the package path.
- Android v2 ZIP `.kudosbackup` export/import with internal paths:
  `manifest.json`, `Works/<UUID>.epub`, and `Fonts/<fileName>`.
- v2 manifest includes `exportedBy`, optional collections, saved searches,
  v2 work stats/update fields, and Readium locator metadata. v2-only fields stay
  optional and are not treated as Apple v1 parity.

Import/export behavior:

- JSON is UTF-8 and decoded with unknown-field tolerance.
- UUIDs normalize to canonical lowercase for work, collection, and saved-search
  identity.
- Dates validate as ISO-8601 instants.
- ZIP import rejects missing manifests, unsupported versions, invalid JSON,
  invalid dates, invalid UUIDs, unsafe paths, absolute paths, traversal, malformed
  `Works/` or `Fonts/` entries, duplicate entries, truncated archives, and entries
  over the configured size limits.
- v2 ZIP output is deterministic where practical: manifest first, then sorted
  work/font entries with stable ZIP timestamps.

Merge behavior:

- Works merge by UUID without deleting local-only works.
- Local EPUB state is preserved when the backup lacks the EPUB file; a new work
  whose manifest claims `hasEPUB = true` is restored with `hasEpub = false` when
  the file is missing.
- Backup EPUB bytes are returned as files-to-write by work UUID for later
  app-private atomic persistence.
- User tags are trimmed, deduplicated, and unioned with local assignments.
- Bookmarks merge by URL and update title/date to match Apple restore behavior.
- Collections merge by UUID; name collisions with different UUIDs create a
  separate suffixed restored collection.
- Fonts merge by safe filename. Colliding different/unknown bytes are suffixed,
  and a restored `readerFontID` is retargeted to the suffixed file when needed.
- Settings are applied after data merge with enum/range validation. Missing or
  unsafe custom font references fall back to `system`.
- `readiumLocator` is preserved for same-platform precision; portable resume
  fields `lastSpineIndex` and `lastScrollFraction` are preserved as the
  cross-platform fallback.

Tests added:

- `BackupV1ManifestDecodeTest`
- `BackupV2ZipDecodeTest`
- `BackupV2ZipExportTest`
- `BackupRoundTripBasicTest`
- `BackupMergeDoesNotDeleteExistingWorkTest`
- `BackupMergeDoesNotDeleteExistingEpubTest`
- `BackupMissingEpubMarksHasEpubFalseTest`
- `BackupUserTagMergeTest`
- `BackupCollectionMergeTest`
- `BackupBookmarkMergeByUrlTest`
- `BackupFontMissingReaderFontFallbackTest`
- `BackupRejectsUnsupportedVersionTest`
- `BackupRejectsMissingManifestTest`
- `BackupRejectsPathTraversalTest`
- `BackupRejectsAbsolutePathTest`
- `BackupRejectsInvalidJsonTest`
- `BackupRejectsTruncatedZipTest`
- `BackupRejectsDuplicateEntryTest`
- `BackupPreservesLegacyProgressFieldsTest`
- `BackupPreservesReadiumLocatorAsPlatformSpecificDataTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- First focused `:app:testDebugUnitTest` run found a test-fixture issue: Java
  `ZipOutputStream` refuses duplicate entries before the importer can inspect
  them. Fixed by hand-writing the duplicate-entry ZIP fixture.
- Final `:app:testDebugUnitTest` passed: 35 tests, 0 failures.
- Final `:app:assembleDebug` passed.
- Final `:app:lintDebug` passed and wrote
  `android/app/build/reports/lint-results-debug.html`.

Known gaps:

- Storage Access Framework picker/share-sheet wiring remains placeholder-only.
- Backup services return file bytes/maps for later app-private staging and atomic
  writes; production Room/DataStore persistence and file commit orchestration are
  not wired yet.
- Apple v2 ZIP import/export support is not implemented in this branch.
- No AO3 networking, parsing, search requests, auth, Readium, EPUB download/import
  from AO3, account lists, comments, or production Library browsing/filtering.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 4 AO3 networking core from an approved prompt. Keep it limited to request
policy/client foundations and tests; do not start search parsing, auth, reader,
or production Library UI unless the phase prompt explicitly allows it.

## Handoff - T-57 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `c1a7475`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/schemas/io.github.cidy02.kudos.data.local.KudosDatabase/1.json`
- `android/app/src/main/java/io/github/cidy02/kudos/core/model/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/**`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/**`

Dependencies added:

- KSP Gradle plugin `2.3.9`
- Room runtime/ktx/compiler/testing `2.8.4`
- DataStore Preferences `1.2.1`
- Kotlinx serialization JSON `1.11.0`
- AndroidX Test core `1.7.0`
- JUnit `4.13.2`
- Robolectric `4.16.1`

Database schema summary:

- Room database: `KudosDatabase`, name `kudos.db`, schema version `1`, schema
  export enabled and committed.
- Tables: `works`, `user_tags`, `work_tag_cross_refs`, `collections`,
  `collection_work_cross_refs`, `bookmarks`, `custom_fonts`, `saved_searches`.
- User tags and collections are normalized with cross-reference tables.
- AO3 tag groups are stored as JSON-encoded string-list columns for Phase 2.
- Date/time values use `java.time.Instant` converted to epoch milliseconds.
- `comments`, `hits`, `knownChapterCount`, and `lastUpdateCheck` are nullable
  Android/local/future-compatible fields, not current Apple v1 backup parity
  fields.
- Production destructive migrations were not enabled.

Settings defaults implemented:

- `readerFontID = "system"`
- `readerMode = "scroll"`
- `readerTwoPage = false`
- `readerCustomize = false`
- `readerBoldText = false`
- `readerFontPt = 18`
- `readerLineHeight = 1.65`
- `readerLetterSpacing = 0`
- `readerWordSpacing = 0`
- `readerMargin = 28`
- `readerJustify = false`
- `confirmBeforeDelete = true`
- `hideMatureContent = true`
- `matureContentMode = "obscure"`
- `requireBiometricToReveal = false`
- `appTheme = "light"`
- `readerTheme = "light"`
- `matchAppReaderTheme = true`
- `accentColorHex = "#990000"`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed: 11 tests, 0 failures, 0 errors.
- `:app:lintDebug` passed with `0 errors, 6 warnings`; the warnings are the same
  version-availability notices carried from Phase 1.

Known gaps:

- No AO3 networking, parsing, search requests, auth, backups, Readium, EPUB
  import/download, account lists, comments, or production Library queries.
- DataStore repository exists and is tested, but app-wide runtime settings wiring
  remains minimal; Settings screen only displays default values.
- Backup import/export is not implemented; `BackupSettings` only preserves the
  contract field names for future Phase 3 work.
- Robolectric is included because Room DAO tests run under local JVM unit tests,
  not instrumentation.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 3 backup v1/v2 compatibility from an approved prompt. Keep it limited to
manifest decoding/encoding, ZIP safety, merge semantics, fixtures, and tests.

## Handoff - T-56 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `00a25b6`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/.gitignore`
- `android/gradle/libs.versions.toml`
- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/drawable/ic_kudos_mark.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/xml/backup_rules.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `android/app/src/main/java/io/github/cidy02/kudos/**`

Summary:

Phase 1 scaffold only. Added a native Android project under `android/` with
Gradle Kotlin DSL, a Gradle 9.4.1 wrapper, AGP 9.2.0, Kotlin/Compose compiler
2.3.21, Compose BOM 2026.06.00, Material 3, and placeholder Compose navigation.
The app shell has Home, Library, Browse, Account, global Search, Work Detail,
Reader placeholder, Settings, and Backup placeholder routes. It intentionally
does not implement AO3 networking, parsing, auth, backup import/export, Readium,
Room, DataStore, EPUB handling, account data, comments, or production Library
behavior.

Verification:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed with no unit tests defined yet.
- `:app:lintDebug` passed and wrote `android/app/build/reports/lint-results-debug.html`.
- Lint report has `0 errors, 6 warnings`, all version-availability notices for
  Gradle, AGP, Activity Compose, Lifecycle, Navigation Compose, and the Compose
  compiler plugin.
- First assemble without `ANDROID_HOME` failed because Gradle could not locate
  the Android SDK. Re-running with `ANDROID_HOME=$HOME/Library/Android/sdk`
  succeeded; Gradle installed the licensed Android SDK Platform 37.0 package
  into the local SDK.

Version decisions:

- `minSdk = 26`
- `compileSdk = 37`
- `targetSdk = 37`
- Gradle wrapper `9.4.1`
- Android Gradle Plugin `9.2.0`
- Compose BOM `2026.06.00`
- Compose compiler plugin `2.3.21`

Known risks:

- UI has not been emulator/screenshot verified; verification was build/lint only.
- Placeholder copy and layout are intentionally temporary and should be replaced
  as each contract-backed implementation phase lands.
- Version catalog choices are pinned to the official AGP/Compose baseline used
  for this scaffold; review whether to bump the six lint-reported newer
  versions before Phase 2.
- `ANDROID_HOME` must be set to `$HOME/Library/Android/sdk` in this local
  environment unless Android Studio or shell configuration exports it.

Next recommended agent: Claude or Codex

Next steps:

1. Review the Phase 1 scaffold against the Phase 0 contracts and prompt scope.
2. If accepted, start Phase 2 only from the approved next-phase prompt.
3. Keep AO3 networking/parsing/auth, backups, Room/DataStore, Readium, EPUB import,
   and account/comment behavior out of the scaffold until their phases are approved.

## Handoff - T-55 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `69e92a6`

Files changed:

- `TASKS.md`
- `AGENTS.md`
- `docs/android/ANDROID_PORT_PLAN.md`
- `docs/contracts/CORE_BEHAVIOR_CONTRACT.md`
- `docs/contracts/BACKUP_FORMAT.md`
- `docs/contracts/AO3_BEHAVIOR_CONTRACT.md`
- `docs/contracts/READER_STATE_CONTRACT.md`
- `docs/contracts/SETTINGS_CONTRACT.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`
- `docs/ai/HANDOFF.md`

Summary:

Phase 0 docs only. Added the approved Android port plan from
`Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md`, contract skeletons,
Android branch policy notes, current Apple v1 backup facts, explicit v2 backup
additions, AO3 sort/concurrency notes, and this handoff. No Android Gradle,
Compose, Room, DataStore, networking, backup, reader, auth, or parser
implementation was added.

Commands run:

- `git branch --show-current`
- `git status --short`
- `git branch -a --list '*kudos-ao3-reader-android*'`
- `git switch -c kudos-ao3-reader-android`
- `mkdir -p docs/android docs/contracts docs/ai`
- `cp /Users/cidy02/Downloads/Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md docs/android/ANDROID_PORT_PLAN.md`
- `git rev-parse --short HEAD`

Tests passing:

- Not run; documentation-only Phase 0 change.

Tests failing/not run:

- Swift tests not run.
- Android tests unavailable because no Android scaffold exists yet.

Known risks:

- `docs/android/ANDROID_PORT_PLAN.md` is copied from the external plan and should
  be reviewed for any remaining wording drift before Phase 1.
- Contract docs are skeletons, not complete executable specs.
- Phase 1 remains blocked until Codex/Claude review accepts these docs.

Needs human decision:

- Confirm Android `minSdk`, `targetSdk`, desugaring policy, and first release
  channel during Phase 0/Phase 1 planning.

Next recommended agent: Codex

Next steps:

1. Review the Phase 0 docs for consistency with the current repo.
2. If accepted, hand to Claude for Phase 1 scaffold on `kudos-ao3-reader-android`.
3. Keep Phase 1 limited to Gradle/app shell/navigation/theme placeholders only.
