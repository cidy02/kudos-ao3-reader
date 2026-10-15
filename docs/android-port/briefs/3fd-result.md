# 3fd — A54's six parsing faults

Implemented all six on `android/agent-codex-3fd`, based on `3caa16d6fa8cbf52251e7098675ee2ebb368b4e7`. No commits, pushes, branch switches, TASKS edits, sign-in, AO3 contact, Room changes or backup-format changes.

Paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`:

| File | Change |
|---|---|
| `account/AO3ChallengeSignUpsState.kt` | Sequentially joins every Complete, Open and Defaults page through the existing paged repository/client. Checks cancellation/session before further reads. Publishes assignments only after the whole join succeeds; a failed HTTP response or parse stops assignment reads and shows the existing match error with unknown match state. |
| `account/AO3CollectionDetailRepository.kt` | Removes the now-unused page-one-only assignment method; reuses `getChallengeAssignments`. |
| `network/ao3/account/AO3CollectionParser.kt` | Missing exact totals stay null; explicit zero stays zero. |
| `account/AO3CollectionDetailScreen.kt` | Omits each unknown stat cell and omits an entirely unknown strip, matching iOS `statCells(for:)`. Known zero remains visible. |
| `network/ao3/account/AO3AccountParser.kt` | Passes subscription byline links into the app's existing account/pseud identity codec alongside author names. |
| `network/ao3/writing/AO3ChapterFormParser.kt` | Keeps bare workskin/pane HTML when structured blocks are absent; blank/image-only panes report the existing unavailable-preview error. Shared by work and chapter previews. |
| `network/ao3/account/AO3ReadingEntry.kt` | Recognizes case-insensitive, optionally colon-free “last visited” and stops at either parenthesis. |
| `network/ao3/preferences/AO3PreferencesModels.kt` | Adds served web links to the transient preferences snapshot. |
| `network/ao3/preferences/AO3PreferencesParser.kt` | Captures navigation titles/absolute destinations, deduplicates URLs, excludes Preferences/help links as iOS does. |
| `account/AO3PreferencesScreen.kt` | Android does show account-management rows. They now use served titles/destinations instead of hard-coded relative paths, retaining row styling/icons. |

All Android consumers of collection totals were checked: detail stat cells changed; detail Recent headings already accept null; collection-index metadata already omits unknown counts; `AO3CollectionsFilter` already sorts unknown last and excludes unknown from “with works only.” Index parsing already preserves null. No other count consumers needed changes.

The join costs **C + O + D paced assignment GETs**, one per reported page (including an empty list's first page), plus one settings GET and one sign-ups GET, or two sign-ups GETs when its last page is needed for the total. Example: 100 pages in each assignment list costs **302–303 reads** on opening/refresh, before transport retries. iOS `allChallengeAssignments` has **no cap**; Android matches it. No fourth pinch-hit list, background task or extra preview/preferences fetch was added. `docs/AO3_NETWORKING_POLICY.md` records this foreground join.

Tests added/adjusted (not executed). Paths are relative to `android/app/src/test/java/io/github/cidy02/kudos/`:

| File | Assertions |
|---|---|
| `account/AO3ChallengeSignUpsTest.kt` | Ports `assignmentJoinFetchesEveryPageIncludingOpenAssignments`: exact 2/3/2 page order, seven assignments, Open page-three URL parameters, and a visible recipient matched only there. Further tests check HTTP/parse failure on each list's second page leaves no partial/unmatched evidence, and screen closure/session replacement during page two stops subsequent reads. Existing setup now supplies the real page-two fixtures. |
| `account/AO3ChallengeSignUpsScreenTest.kt` | Updates the pagination wait for the expanded opening-read count. |
| `network/ao3/account/AO3CollectionParserTest.kt` | Ports `collectionShowReadsTotalsFromItsOwnNavLinks`: own versus child nav totals, absent totals null; also explicit zeros. |
| `account/AO3CollectionTotalsTest.kt` | Checks the actual stat-cell builder omits either/both unknown totals and retains known zero. |
| `network/ao3/account/AO3AccountParserTest.kt` | Ports `readsTitleAndAllBylineAuthors` with the iOS inline bylines, including two separate co-author identities and account/pseud routing. Ports `readsADeletedWorkRow`: fourth row deleted, no work ID, date `12 Jan 2023`; also preserves all three live-row dates. |
| `network/ao3/writing/AO3ChapterFormTest.kt` | Ports `previewExtractsThePreviewPane`: “Hello.” survives the exact bare-workskin input and the rendering parser for both work/chapter modes. Empty/blank/image-only panes fail. |
| `writing/WritingChapterSaveTest.kt` | Separates unreadable empty-pane failure from a readable preview missing draft identity; both retain the form. |
| `network/ao3/preferences/AO3PreferencesParserTest.kt` | Ports `parsesTogglesSelectsTextAndWebLinks`: controls/values remain intact, Change Password and all seven served routes survive. Also checks help/preferences exclusion, empty href rejection and URL deduplication. |
| `account/Brief3caScreenTest.kt` | Checks tapping Change Password opens its served absolute address without another read or write. |

`src/test/resources/ao3/account/ios_readings.html` and `src/test/resources/ao3/preferences/ios_preferences.html` are byte-identical copies of the respective iOS `KudosTests/Fixtures/ao3_readings.html` and `ao3_preferences.html` (confirmed with `cmp`). Existing Android fixtures remain unchanged.

Checked: surrounding callers/types, fixture contents, `sh android/Scripts/check-invariants.sh` (passed), `git diff --check` (passed). Gradle/builds/JUnit/Compose tests and rendered UI were **not checked**, per the brief; Claude must run them. Live AO3 behavior remains unverified. No helper scripts, stubs or `.orig` files were created.
