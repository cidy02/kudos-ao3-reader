# iOS ↔ Android parity review — 2026-08-07

**Trees reviewed:** `hig-review` @ `e9ed0c6a` (worktree `.claude/worktrees/hig-review-reference`, iOS source root `kudos-ao3-reader/`) · `android/exclusion-parity` @ `a5a46116` (worktree `.claude/worktrees/android-exclusion-parity`, Android source root `android/app/src/main/java/io/github/cidy02/kudos/`)

> Note on the Android branch name: the review prompt names the branch
> `kudos-ao3-reader-android`. The worktree at `.claude/worktrees/android-exclusion-parity`
> is checked out on `android/exclusion-parity` @ `a5a46116` — which is the exact SHA the
> prompt cites, so this is the intended tree under a different branch label.

**Method:** see *Method log* at the foot of this file. Updated as work proceeds.
**Status:** in progress

**Confirmed sizes** (`find | wc -l`, run 2026-08-07): iOS 214 Swift sources + 85 test
files; Android 281 Kotlin sources + 93 test files. Both match the prompt's figures.

---

## Progress ledger

**Resume here:** every area has been opened; seventeen are partial. The highest-value
remaining item is the **comment model field set** (area 7) — compare
`Models/AO3CommentModels.swift` against `network/ao3/comments/AO3CommentModels.kt` field by
field for creator/moderator badges, edited state, deleted/hidden state and thread depth, since
finding 13 showed this area's model layer is thinner on Android than it looks. After that, the
**Library shelf predicates** (area 10) and the **error/empty-state copy sweep** (area 19),
which is the only area where nothing beyond adjacent evidence has been gathered.

**Standing caution for whoever resumes:** two of two clusters spot-checked from the Android
branch's `docs/audits/` turned out to be **already fixed** while still listed as confirmed-open
(finding 3). Verify any item from that corpus against the tree before scheduling it.

**Then:** areas 1, 5, 7, 8, 19 are untouched; 6, 9, 12, 13, 16, 18, 20, 21 are partial.
See *Not covered* for the full breakdown and for the standing warning about the Android
branch's audit corpus. Read *Not covered* before planning —
it says which of them already have partial coverage from the Android branch's own
`docs/audits/` and should therefore be re-verified rather than re-derived.

**Do not redo:** area 17 (closed, see the re-check table); the date-encoding question
(closed as R-1); the suite-shape comparison in *Asymmetric test coverage*.

**Method warning for whoever resumes:** two 7-agent parallel sub-agent reviews were
dispatched for areas 2–15 and **both died on a session usage limit with zero results
returned** (1.29 M tokens, nothing recovered — the run journals contain no `result` lines).
Everything in this report was produced by direct inline reading afterwards. Do not re-try
that fan-out shape; work areas serially and commit each one.

| # | Area | iOS roots | Android roots | Status | Findings | Notes |
|---|---|---|---|---|---|---|
| 1 | Onboarding & first run | `Features/Onboarding/`, `App/MyApp.swift`, `App/ContentView.swift` | `onboarding/`, `app/` | 🔄 in progress | 0 | Gating + state model match: both gate on `hasCompletedOnboarding`, both run Welcome → sync-folder, both keep a separate permanent-dismissal flag for the second step (iOS `ContentView.swift:35-41`, Android `KudosApp.kt:101-175`). **Not done:** the screens' copy, illustrations and step content |
| 2 | Auth / session / cookies | `Services/AO3AuthService.swift`, `AO3SessionVault.swift`, `AO3WebLoginCoordinator.swift`, `AO3RedirectCookieRelay.swift`, `Features/Auth/` | `auth/` | ✅ done | 0 (V-3) | Storage, cookie jar and logout all at parity; Android's plaintext store ruled out as test-only. **Not read:** `AO3SessionValidator.kt` / expiry cadence, native-vs-web login flow choice |
| 3 | Networking core (pacing, retry, coalescing, errors, URL resolution) | `Services/AO3Client.swift`, `AO3RequestCoordinator.swift`, `RequestCoalescer.swift`, `AO3URLResolver.swift` | `network/ao3/` (root files) | ✅ done | 1 (finding 6) | Every politeness constant compared and matching (V-4); UA version stale on Android. **Not read:** `AO3OverloadDetector.kt`, coalescer key/TTL detail, `AO3URLResolver` |
| 4 | Search + filters + tag autocomplete + saved searches | `Features/Search/`, `Models/SavedSearch.swift` | `search/`, `network/ao3/search/` | 🔄 in progress | 1 (finding 7) | Filter field set + emitted `work_search[...]` params (7); `required-tags` parser trap (V-5); SavedSearch round trip verified lossless (V-13). **Not done:** tag autocomplete endpoint/debounce, result pagination |
| 5 | Browse (category → fandom → works) + fandom catalog | `Features/Browse/`, `Features/Search/FandomCatalog*.swift` | `browse/`, `network/ao3/browse/` | 🔄 in progress | 1 (finding 14) | `BrowseLocalIndicators` mapping question resolved — it genuinely has no iOS counterpart → finding 14. **Not done:** category list/ordering, fandom counts parsing, catalog cache TTL, WebView-fallback policy, `CategoryStats` mapping |
| 6 | Work detail + write actions (kudos/bookmark/subscribe) | `Features/WorkDetail/`, `Services/AO3WriteActions.swift` | `works/WorkDetailScreen.kt`, `network/ao3/writes/` | ✅ done | 0 (V-8, V-12) | Write endpoints + duplicate handling identical (V-8); stat row labels/order and the full AO3 actions menu verified (V-12). **Deliberately not read:** the local-action subset (Delete/Redownload EPUB, Rebuild from Original), which is Library-lifecycle work covered by area 10 |
| 7 | Comments (threads, drafts, posting) | `Features/Comments/`, `Services/AO3Client+Comments.swift`, `AO3CommentActions.swift`, `CommentSubmission.swift` | `comments/`, `network/ao3/comments/` | 🔄 in progress | 2 (findings 13, 15) | Timestamp handling traced selector-to-pixel (13); `AO3Comment` field set diffed — 24 iOS vs 21 Android, all substantive fields present on both incl. deleted/hidden and cutoff state (V-10); commenter-profile navigation missing on Android (15). **Not done:** posting form fields, pagination, error copy |
| 8 | Author profile + series | `Features/Authors/`, `Services/AO3AuthorProfileService.swift`, `AO3Client+Authors.swift` | `author/`, `network/ao3/author/`, `network/ao3/series/` | 🔄 in progress | 1 (finding 12) | Series navigation resolved → finding 12 (dead tap target), plus a whole-tree sweep of no-op-defaulted callbacks (4/50 unwired, 1 material). **Not done:** author-profile field-by-field comparison, multi-pseud handling (`/users/X` vs `/users/X/pseuds/Y`), orphaned/anonymous authors |
| 9 | Reader(s) | `Features/ReaderReadium/`, `Features/Reader/`, `Reading/` | `reader/` (+ `readium/`, `settings/`, `speech/`) | 🔄 in progress | 4 (8, 9, 20, 21) | Progress locator + fallback (V-6, 8); settings field set/defaults/clamps (V-7, 9); colour themes → findings 20 and 21. **Not done:** TOC building, in-reader search, annotations/highlights, TTS |
| 10 | Library / collections / queues / stats / recently deleted | `Features/Library/`, `Services/ReadingQueueService.swift` | `library/` | 🔄 in progress | 0 (V-9) | **Statistics done** — all 9 statistics + completion rate verified identical (V-9), and the audit's 3 stats defects are all fixed (folded into finding 3). **Not done:** Recently-Deleted retention window, collections, queue ordering/reorder, shelf predicates |
| 11 | Home | `Features/Home/` | `home/` | ✅ done | 0 (V-8, V-12) | Five shelves, same order; all four local-section predicates, sort keys, the `recency` helper, the 12-item cap and persisted collapse state verified identical; 3/4 empty strings identical and the 4th a documented deliberate divergence (V-12) |
| 12 | Account / inbox / dashboard / AO3 preferences | `Features/Account/`, `Services/AO3Client+Inbox.swift`, `AO3InboxActions.swift`, `AO3Client+Preferences.swift` | `account/`, `network/ao3/inbox/`, `network/ao3/preferences/` | 🔄 in progress | 0 | The four AO3 account-list types match (V-8). **Not done:** inbox parser + malformed-row handling, AO3 preferences read/write field set, dashboard, whether Android reaches Collections/Works/Series |
| 13 | Import / conversion / EPUB pipeline | `Services/WorkImporter.swift`, `*WorkConverter.swift`, `Reading/` | `works/converters/`, `works/WorkImporter.kt`, `files/` | 🔄 in progress | 1 (finding 10) | HTML sanitisation compared (both allowlist-based, V-8); author-note handling absent on Android. **Not done:** PDF/TXT converters, EPUB builder output, text-encoding detection, download queue |
| 14 | Backup / restore / folder sync | `Services/KudosBackup*.swift`, `PersistenceSync.swift`, `FolderSyncService.swift` | `backup/` | ✅ done | 4 (1,2,4,5) + 1 minor | Manifest versions, manifest field set, date encoding (R-1), folder-sync write path (1 & 2), `SyncMerge` rules (V-1), `mergeWork` field rules (4), export round-trip (5). **Deliberately not read:** collection/queue/annotation merge bodies and ZIP container internals — the works path is the one carrying user content and it is where all four findings landed |
| 15 | Persistence + migrations (SwiftData vs Room) | `Models/Models.swift` | `data/local/` (`entity/`, `dao/`, `KudosDatabaseMigrations.kt`) | ✅ done | 2 (findings 5, 19) | All 8 entity pairs diffed mechanically: `SavedWork`↔`WorkEntity` → finding 5; the other 7 verified equivalent (V-11); dead schema on both sides → finding 19. Migration safety verified (V-2). **Deliberately not read:** DAO query semantics, which belong to the feature areas that call them |
| 16 | Settings / theming | `Settings/`, `App/ThemeManager.swift` | `settings/`, `data/preferences/`, `ui/theme/` | 🔄 in progress | 3 (9, 20, 21) | Backup settings payload verified 21/21 (V-7); theme enums and restore validation compared → findings 20, 21. **Not done:** the Settings *screens* themselves, per-setting UI wording, light/sepia token tones (see note under finding 20) |
| 17 | Update system | (none expected) | `update/`, `network/github/` | ✅ done | 0 | Confirmed Android-only; iOS has no app-update path. See the re-check table. Nothing further to compare — a feature one platform deliberately lacks is not drift |
| 18 | Support / bug report / shake | `Features/Support/` | `support/` | 🔄 in progress | 0 (+1 lead) | Inventory compared. `WhatsNew` is iOS-only **by design** — `TASKS.md` row 26 says it exists precisely because iOS has no update system, and Android surfaces GitHub release notes instead (`GitHubReleaseModels.kt:21`). Not a gap. Screenshot attachment is lead L-6 |
| 19 | Error handling & empty states | cross-cutting | cross-cutting | 🔄 in progress | 2 (findings 16, 17) | Error *copy* swept: 6 sites render `AO3Error.toString()` raw (16), offline is not a distinct state (17), and Android's four duplicated `displayMessage()` mappers are otherwise well-written and consistent. **Not done:** empty-state copy per screen, loading/skeleton states, signed-out states outside comments |
| 20 | Accessibility | cross-cutting | cross-cutting | 🔄 in progress | 1 (finding 11) | Touch-target enforcement compared → finding 11; annotation density measured (274/51 files vs 202/34). **Not done:** per-control label audit, Dynamic Type vs `sp` scaling, focus order, TalkBack traversal |
| 21 | Test coverage asymmetry | `KudosTests/` (85) | `android/app/src/test` (93); no `androidTest` | 🔄 in progress | 1 minor | Suite shape done + the folder-sync asymmetry established. The per-rule sweep across all other areas is not done |

Legend: ⬜ not started · 🔄 in progress · ✅ done · ⏭️ skipped (reason in Notes)

---

## Summary

Eighteen confirmed findings, ten verified "no divergence" results, seven leads (three since
resolved), one ruled out. Of twenty-one areas: **four closed, seventeen partial, none
untouched.** Every area has had at least one question answered; none has been exhausted.

The honest headline has not changed since the first pass: **the two apps agree far more than
they differ, and where they differ it is almost never in the business rules.** Every constant
in the binding networking policy matches to the digit (V-4). The backup merge core is
semantically identical function for function, including the deliberate asymmetry where a tie
applies an incoming edit but does *not* revive a deleted record (V-1). All nine reading
statistics compute identically, formula for formula (V-9) — the area I expected to be worst.
Write endpoints match down to the verbatim sentence shown when you kudos twice (V-8). The
settings payload matches 21 fields for 21 (V-7); the Recently Deleted window is 90 days on
both. Where someone sat down and ported a rule, they ported it correctly.

**The divergences cluster in four places instead.** *Around the edges of a correct rule*: the
sync write is atomic on iOS and truncating on Android (1), the merge is faithful but one flag
is OR'd rather than assigned (4) and another is never lowered (18), the archive is
well-specified but nine fields do not survive a round trip (5). *Breadth* — Android implements
a strict subset of iOS's surface: ten missing search parameters including sort direction (7),
no author's-note handling (10), no touch-target floor on custom controls (11), no way to reach
a commenter's profile (15). *The last mile of a feature that is otherwise built*: a series row
that draws a ripple and does nothing (12), comment timestamps rendered as raw AO3 text (13),
raw Kotlin error objects shown as user copy while a correct mapper sits unused in the same
package (16), and offline never named as a state (17). And *staleness in the record rather
than the code*: a hardcoded UA version that has already drifted (6), a contract doc asserting
atomicity the code does not provide (1), and an audit corpus still listing closed work as open
(3).

That third cluster is the most actionable, because in every case Android already has the
hard part. The series repository, the commenter's `profileUrl`, four well-written error
mappers, an author-profile destination — all present, none reached. Several of these are
one-line wiring fixes in `AppNavHost` and one shared `displayMessage()`.

Three things are worth carrying forward.

**The most reliable predictor of a defect was absent test coverage, not absent care.**
`SyncRepository.kt` holds two of the four backup findings and has no test of any kind; the iOS
file it was ported from has a 796-line suite. Conversely the statistics code, which *is*
tested on both sides, came through a formula-by-formula comparison clean.

**The "iOS is the source of truth" convention was right in sixteen cases and wrong in two.**
Finding 8 (iOS discards a reading position it was handed) and finding 14 (Android marks
already-saved works in browse; iOS cannot) are both places where Android *added* something
rather than porting it, so a rule about not cutting iOS down simply does not apply. It is a
good default, not a law.

**The Android branch's audit corpus should not be trusted as a work list.** Three clusters
were spot-checked and all three were stale (finding 3) — one wrong in all three of its claims,
including a fix whose code comment quotes the audit's own worked example, and another whose
fix comment names the very iOS function the audit said had no counterpart. The fixes were
evidently made *from* those reports and the reports were never marked resolved. Re-verify
against the tree before scheduling anything from them.

What is *not* established: no test suite was run on either platform, and nothing here is
runtime-verified. Seventeen areas are partial — the ledger's Notes column names what was left
in each, and *Not covered* ranks where a follow-up should start. The empty-state half of area
19 in particular is still open: findings 16 and 17 cover error *copy*, not what each screen
shows when a list is legitimately empty.

## Findings

### 1. Android's folder sync truncates the destination before writing it — `blocker` · Backup / folder sync

- **iOS:** `kudos-ao3-reader/Services/FolderSyncService.swift:689` writes `manifest.json`
  with `options: .atomic`, and `:707-709` (`writeIfChanged`) writes every EPUB and font
  asset the same way. `Data.write(options: .atomic)` writes to an auxiliary file and
  swaps it into place, so the destination is either the old bytes or the new bytes,
  never a prefix of the new bytes. The code says so itself, at `:675-679`: *"Assets
  first, manifest last: the manifest is the commit point … An interruption leaves the
  previous manifest — and therefore the previous consistent view — in place."*
- **Android:** `backup/SyncRepository.kt:205` writes `manifest.json` with
  `context.contentResolver.openOutputStream(manifestDoc.uri, "wt")`, and `:226`
  (`writeIfChanged`) writes every EPUB and font asset the same way. The `"wt"` mode is
  *write + truncate*: the SAF provider truncates the existing document to zero length
  when the stream is opened, before a single new byte is written.
- **Divergence:** iOS never has a moment where the destination is invalid. Android has a
  window — the whole duration of the write — during which the destination is truncated or
  partially written. The *ordering* of the iOS design was ported faithfully (assets first,
  manifest last, then orphan pruning); the *atomicity* that makes that ordering mean
  anything was not.
- **Scenario:** a user with a 400 MB library syncs to a Google Drive / Dropbox / SD-card
  folder. Mid-sync the process is killed — Android's background-work killer, storage
  full, the cloud provider dropping the SAF connection, or the user force-quitting.
  On iOS the folder still holds the complete previous manifest and every previous asset,
  and the next sync retries cleanly. On Android the folder holds a zero-length or
  half-written `manifest.json`. That file is the sync folder's index of the entire
  library. On the next sync-down — and on every *other* device pointed at that folder —
  `BackupValidator` fails to parse it and the folder is unusable; the orphan-pruning passes
  at `SyncRepository.kt:176` and `:193` then have no manifest to compute "expected" from.
  The user's off-device backup is destroyed by an interrupted write.
- **Evidence:** read both write paths end to end. Grepped the Android backup package for
  any staging or rename primitive — `grep -rniE "renameTo|atomic|\.part|createNewFile"
  backup/` over `BackupExporter.kt`, `BackupPaths.kt`, `BackupRepository.kt` returns no
  staging of any kind; the only `openOutputStream` calls are the two `"wt"` ones plus
  `BackupScreen.kt:61` (a user-chosen export target, where truncation is correct because
  the user picked the file). Ruled out: (a) that SAF might make `"wt"` atomic — it does
  not, `"wt"` maps to `ParcelFileDescriptor.MODE_TRUNCATE` and the truncation is applied
  on open; (b) that a `.tmp`-and-rename existed elsewhere — no `DocumentsContract.
  renameDocument` call exists anywhere in the tree; (c) that this is deliberate — see
  History.
- **History:** not recorded as a decision anywhere — and the surrounding record makes this
  a miss rather than a trade-off, in three independent ways:
  1. **It is a named, binding invariant on the iOS side.**
     `docs/DATA_AND_PERSISTENCE_INVARIANTS.md:39` — "Writes: stage to
     `itemReplacementDirectory` (same volume) → `replaceItemAt` — the remote package must
     survive any failed write. **Never remove-then-write.**" `docs/AGENT_ONBOARDING.md:46`
     repeats it in the pitfalls table, annotated "(sync package destruction window)" — the
     pitfalls table is described in that file's own header as scar tissue from real
     debugging sessions. `AGENTS.md:153` makes the invariants doc binding for any change
     touching sync.
  2. **The Android port plan specified it and the contract doc already claims it is done.**
     `docs/android/ANDROID_PORT_PLAN.md:1005` — "Write EPUB files atomically."
     `docs/contracts/BACKUP_FORMAT.md:83` states, as settled behaviour, "EPUB files are
     written atomically when present." That sentence is true of the *restore* path (which
     lands files in app-private storage) and **false** of the sync-folder write path. A
     contract document asserting an atomicity guarantee the sync path does not provide is
     itself worth fixing, because it is what a future agent will trust instead of reading
     `SyncRepository.kt`.
  3. **Android already implements exactly this discipline elsewhere.**
     `files/WorkFileStore.kt:24-39` writes an EPUB by creating
     `Files.createTempFile(worksDirectory, ".$workId-", ".tmp")`, writing to it, then
     `Files.move(temp, destination, REPLACE_EXISTING, ATOMIC_MOVE)` with a non-atomic
     `Files.move` fallback and a `deleteIfExists(temp)` cleanup; `:80-90` does the same for
     originals. So this is not a team that does not know the pattern, and not a platform
     that cannot express it. The one path where the destination is a *user-visible,
     shared, and irreplaceable* folder is the one path that does not use it.
- **Recommendation:** Android moves. Note honestly that SAF has **no** atomic-replace
  primitive, so `.atomic` cannot be mirrored exactly — do not write a task that implies it
  can. The achievable fix is to narrow the window and keep a fallback: write to
  `manifest.json.tmp`, `flush()` + `fd.sync()`, then `DocumentsContract.renameDocument`
  over the live name, and retain the previous manifest as `manifest.json.bak` that
  sync-down falls back to when the primary fails to parse. That reduces an
  entire-write-duration hole to a rename, and makes the remaining hole recoverable.
  This is also the single highest-value place to add Android test coverage — see
  *Asymmetric test coverage*, where this exact rule turns out to be pinned on iOS and
  unpinned on Android.

### 16. Android renders raw Kotlin error objects as user-facing error text — `real-bug` · Error handling

The sharpest detail: the comments feature *has* a correct error-copy mapper, 850 lines from
the code that needs it, `private` to the wrong file, and never called.

- **iOS:** `Features/Comments/CommentsErrorMessages.swift:40-54` maps each error case to
  human copy — `AO3Error.rateLimited` → "AO3 is asking for a pause. Please try again in a
  moment.", `authenticationRequired` → "Log in to AO3 to do that.", `notFound` → "AO3
  couldn't find these comments — the work may be hidden or deleted.", `forbidden` → "AO3
  declined the request. The work may be restricted to logged-in users." — with a final
  fallback at `:53-54` to `(error as? LocalizedError)?.errorDescription ?? "Something went
  wrong talking to AO3."` So no code path can reach the UI with a debug string.
- **Android:** `comments/CommentsViewModel.kt:107`, `:179` and `:232` all publish
  `result.error.toString()` straight into the UI state
  (`CommentsUiState.Error(result.error.toString())` and `_message.value = …`).
  `AO3Error` (`network/ao3/AO3Error.kt:3-16`) is a **sealed interface of `data object`s and
  `data class`es**, so `.toString()` is Kotlin's auto-generated debug representation. The
  user sees literally `RateLimited(retryAfterMillis=30000)`, `Server(statusCode=503)`, or
  `Http(statusCode=418)`.
- **Divergence:** the same rate-limit produces "AO3 is asking for a pause. Please try again
  in a moment." on iPhone and `RateLimited(retryAfterMillis=30000)` on Android.
- **Scenario:** a user opens a busy work's comments while AO3 is under load. iOS explains
  what happened and what to do. Android displays a Kotlin constructor call. There is no
  recovery hint, and the string is not localisable.
- **Evidence:** read `AO3Error.kt` in full to confirm every case is a `data object`/`data
  class` with compiler-generated `toString()`. Traced all three comments call sites. Then
  swept the tree: **six** sites publish `error.toString()` to UI state —
  `comments/CommentsViewModel.kt:107,179,232`, `browse/TagWorksScreen.kt:104`,
  `account/AO3PreferencesScreen.kt:70`, and `settings/SettingsScreen.kt:283` (as the `else`
  branch of an otherwise-mapped `when`).
  **Ruled out that Android simply lacks a mapper — it has four.**
  `AO3Error.displayMessage()` is defined at `comments/CommentsScreen.kt:856`,
  `search/SearchScreen.kt:707`, `works/WorkDetailScreen.kt:2569` and
  `account/AccountViewModel.kt:223`. Their copy is well-written and near-identical, varying
  only the context noun ("that search" / "this work" / "this account page"), which is good
  practice rather than drift. `search/` and `works/` call theirs. **`comments/` does not** —
  `grep -n displayMessage comments/CommentsScreen.kt` returns exactly one line, the
  definition at `:856`, with no call site. Because it is `private` to the Screen file, the
  ViewModel that needs it cannot see it.
- **History:** not recorded anywhere. Greps of `TASKS.md` and the Android branch's `docs/`
  for error-copy handling return nothing.
- **Recommendation:** Android moves. Promote one `displayMessage()` to a shared location
  (`network/ao3/`, beside `AO3Error` itself), delete the four copies, and replace all six
  `error.toString()` sites with it. That is a mechanical change with an obvious test: assert
  that no user-visible string matches `^[A-Z][A-Za-z]*\(`. Worth adding to
  `android/Scripts/check-invariants.sh`, which already guards single-sourcing for the
  User-Agent and would catch the next recurrence.

### 21. Restoring a backup silently drops the OLED theme and lands the user in light mode — `real-bug` · Backup / settings

Found while checking a loose end in finding 20's recommendation, and it turned out to be
worse than the thing I was checking. **This one does not need iOS at all — an
Android→Android backup round trip loses the setting.**

- **Android writes `"oled"`.** `core/model/SettingsModels.kt:26-31` declares
  `AppThemeSetting` with `Oled("oled")`, and `core/model/BackupSettings.kt:72` exports
  `appTheme = settings.app.appTheme.storageValue` — so a user on the OLED app theme produces
  an archive containing `"appTheme": "oled"`.
- **Android's own validator rejects it.** `backup/BackupValidator.kt:12` defines
  `private val appThemes = setOf("light", "sepia", "dark", "system")` — **`"oled"` is not in
  the allowlist**, despite being a value the same codebase emits. `:181` then does
  `settings.appTheme.takeIf { it in appThemes } ?: defaults.appTheme`, and the default is
  `BackupSettingsPayload.appTheme = "light"`.
- **The reader half fails the same way, and fails to `Light` rather than `Dark`.**
  `BackupValidator.kt:11` has `readerThemes = setOf("light", "sepia", "dark")`, so `:182`
  substitutes the default for `"oled"`. Independently,
  `core/model/SettingsModels.kt:19-22`'s `ReaderThemeSetting.fromStorage` is
  `entries.firstOrNull { it.storageValue == value } ?: Light` — an unknown value falls back
  to **Light**, not to the nearest dark theme.
- **iOS emits the same string.** `Features/Reader/ReaderStyle.swift:27-28` is
  `enum ReaderTheme: String { case light, sepia, dark, oled }`, so its raw value is `"oled"`,
  and `KudosBackup.swift:758-759` carries `appTheme`/`readerTheme` as plain `String`s.
- **Scenario, in the order a user hits it:**
  1. *Android only.* A user picks the OLED app theme, backs up, reinstalls, restores. Their
     app comes back in **light mode**. Nothing reports a problem; the theme setting simply
     reads "Light". They chose true-black and got white.
  2. *Cross-platform.* An iPhone user on the OLED reader theme restores on Android and gets
     a **white reader** — not the dark one, because `fromStorage` falls back to `Light`.
  This is the worst kind of settings bug: silent, total (both app and reader), and it inverts
  the user's choice rather than approximating it.
- **Evidence:** traced the value end to end in both directions — emit
  (`BackupSettings.kt:72`), validate (`BackupValidator.kt:11-12, 181-182`), and parse
  (`SettingsModels.kt:19-22`). Ruled out: (a) that `AppThemeSetting.fromStorage` rescues it —
  it cannot, the validator has already replaced `"oled"` with `"light"` before
  `BackupSettings.kt:43` calls `fromStorage`; (b) that the allowlist is deliberately
  conservative because Android lacks an OLED app theme — it has one, fully implemented
  (`ui/theme/Theme.kt:15` exposes it, `:60-64` builds `oledScheme` from `SurfaceOled`);
  (c) that `"system"` in the app allowlist means the sets were copied from iOS and iOS lacks
  OLED — iOS has `.oled` and Android's list contains `"system"`, which *iOS's* `ReaderTheme`
  does not, so neither list is a copy of the other. Both are hand-maintained and one is
  simply missing a case.
- **History:** not recorded. This is the same species as finding 6 (a hand-maintained
  constant that fell out of step with the enum beside it) and finding 9 (a clamp range that
  was never updated), which is now three instances of the same underlying habit.
- **Recommendation:** Android moves, and the immediate fix is two strings: add `"oled"` to
  both sets at `BackupValidator.kt:11-12`. But the durable fix is to stop hand-maintaining
  them — derive both from the enums that already exist
  (`AppThemeSetting.entries.map { it.storageValue }`,
  `ReaderThemeSetting.entries.map { it.storageValue }`), which makes this class of bug
  structurally impossible and would have prevented it. Separately, `fromStorage`'s
  fallback to `Light` is the wrong default for an unrecognised *dark* theme; falling back to
  `Dark` would at least preserve intent. Note finding 20 must land too, or `"oled"` will
  validate and then still be collapsed to `Dark` by `ReaderSettingsMapper.kt:50`.

### 20. The OLED theme applies to Android's app shell but not to its reader — `real-bug` · Reader / theming

The reader is the screen a user looks at longest and the one where a true-black theme
actually matters. It is the single place on Android where the OLED theme is dropped.

- **iOS:** `ReaderTheme` has four cases — `Features/Reader/ReaderStyle.swift:28`,
  `case light, sepia, dark, oled` — and `.oled`'s reader background is literally
  `.black` (`:87`). `.dark` is a distinct, lighter `Color(red: 0.086, green: 0.086,
  blue: 0.105)` (`:86`). The two are deliberately different, and the comment at `:79-81`
  notes the app shell reuses the same token "so the app and the reader can never drift apart
  into two different 'dark backgrounds'."
- **Android:** `reader/settings/ReaderColorTheme.kt:9` declares
  `enum class ReaderColorTheme { Light, Sepia, Dark }` — **three** cases, no OLED — and
  `backgroundColor()` (`:12-16`) maps `Dark` to `SurfaceDark`, which is
  `0xFF191817` (`ui/theme/Color.kt:14`), a dark grey. `core/model/SettingsModels.kt:14-17`
  confirms the reader-theme setting itself only offers `Light`, `Sepia`, `Dark`.
- **Divergence:** Android *has* OLED everywhere else.
  `ui/theme/Color.kt:16-17` defines `SurfaceOled = 0xFF000000` and `SurfaceOledElevated`;
  `ui/theme/Theme.kt:60-64` builds a real `oledScheme` using them as `background` and
  `surface`; `Theme.kt:15` exposes `Oled("OLED")` as a user-selectable app theme. Only the
  reader collapses it — `reader/settings/ReaderSettingsMapper.kt:50` reads
  `AppThemeSetting.Dark, AppThemeSetting.Oled -> ReaderColorTheme.Dark`, folding OLED into
  Dark before the reader ever sees it.
- **Scenario:** a user on an OLED phone picks the OLED app theme, precisely to get true black
  at night and to save battery. Every screen obliges — Library, Home, Account are `#000000`.
  They open a work to read, which is the whole reason the setting exists, and the page
  background is `#191817` grey. Because "match app reader theme" defaults to true
  (`BackupSettingsPayload.matchAppReaderTheme = true`), this is what happens without the user
  touching any reader setting. The contrast against the surrounding true-black chrome makes
  the reader look like a lighter panel floating on the app.
- **Evidence:** read all four iOS cases and both Android enums, then traced the collapse to
  the single line that causes it. Ruled out: (a) that Android's `Dark` token *is* black —
  it is `0xFF191817`, and `SurfaceOled = 0xFF000000` exists separately in the same file;
  (b) that the reader picks up the app scheme elsewhere and the mapper is vestigial —
  `ReaderColorTheme` has no OLED case to map *to*, so the enum itself is the ceiling;
  (c) that this is a Readium constraint — Readium's EPUB themes are configured from the
  adapter, and Android already passes three distinct backgrounds through it, so a fourth is
  the same mechanism.
- **History:** not recorded. No `TASKS.md` row and nothing in the Android branch's `docs/`
  mentions an OLED reader theme or its omission.
- **Recommendation:** Android moves. Add `Oled` to `ReaderColorTheme`, map it to
  `SurfaceOled` in `backgroundColor()`, stop collapsing it at `ReaderSettingsMapper.kt:50`,
  and add the case to `ReaderThemeSetting` so it is selectable independently as well as via
  "match app theme". Note for whoever does it: `BackupSettingsPayload.readerTheme` is a
  `String` (`backup/BackupManifest.kt`) and iOS already writes `"oled"`, so an iOS archive
  restored on Android **today** carries a reader theme Android cannot represent — worth
  checking what `ReaderThemeSetting.fromStorage` does with it (`SettingsModels.kt:19-20`)
  while making this change.

### 18. A work whose EPUB file has vanished still restores as "downloaded" on Android — `minor` · Backup / restore

Promoted from lead L-5 after tracing both sides. Small impact, but it is the same shape as
finding 4 — a flag Android can raise and never lower.

- **iOS:** `Services/KudosBackup.swift:1228-1231` — when the archive carries no EPUB for a
  work *and* no local file exists, iOS clears the flag and demotes the preservation state:
  `work.hasEPUB = false`, and `if work.epubPreservationStatus == .preserved {
  work.epubPreservationStatus = .missingFile }`.
- **Android:** `backup/BackupMergeService.kt:64` —
  `val existingHasEpub = id in currentEpubIds || existing?.hasEpub == true`. The first clause
  is sound: `currentEpubIds` comes from `backup/BackupRepository.kt:112-118`, which filters
  the DB's `hasEpub` works down to those where
  `Files.isRegularFile(workFileStore.workEpubPath(id))` actually holds — a real filesystem
  check. But the trailing `|| existing?.hasEpub == true` re-admits the stale database flag,
  so a work with no file on disk and none in the archive still comes out `hasEpub = true`.
- **Divergence:** iOS treats absence-of-file as authoritative and downgrades; Android treats
  the DB flag as sufficient and never downgrades.
- **Scenario:** a user's EPUB is removed out from under the app — an aggressive storage
  cleaner, a restore from a thinner backup, a failed file write. On iPhone the work is
  correctly shown as not downloaded (and, if it had been preserved, as `missingFile`, which
  is what drives re-preservation). On Android it still displays as downloaded; the user taps
  Read and gets an error instead of a book. The state is self-correcting only if something
  else rewrites the flag.
- **Evidence:** read the merge derivation and traced `currentEpubIds` to its filesystem
  filter. Ruled out: (a) that Android downgrades elsewhere on restore — `grep -rn "hasEpub"`
  across `backup/` shows the only writes are `BackupMergeService.kt:64,67,192,206` (all
  raising) and `BackupRepository.kt:151-152` (also raising, after a successful file write);
  nothing clears it; (b) that the reader repairs it on failure — `reader/ReaderError.kt`
  has a `FileMissing` case surfaced at `reader/ReaderScreen.kt:149` with a "Remove offline
  copy" action, but that requires the user to act, where iOS corrects the record silently at
  restore time.
- **History:** not recorded. Note this is the mirror image of finding 4: there Android forces
  `isSaved` up and never down; here it leaves `hasEpub` up and never brings it down. Both sit
  in the same 30 lines of `mergeWork`.
- **Recommendation:** Android moves, and it is a one-clause change: drop
  `|| existing?.hasEpub == true` so `existingHasEpub` reflects only the filesystem check
  Android already performs, then mirror iOS's preservation demotion. Worth doing in the same
  pass as finding 4 — same function, same class of bug.

### 17. Offline is not a distinct state on Android — `gap` · Error handling / empty states

- **iOS:** `Features/Comments/CommentsErrorMessages.swift:50-51` matches
  `URLError where error.code == .notConnectedToInternet` and returns "You're offline.
  Comments will load when you're back online." — a message that names the cause and tells
  the user it will resolve itself. `:19-21` additionally treats `.timedOut` and
  `.networkConnectionLost` as a distinct retryable class.
- **Android:** there is no offline concept.
  `grep -rniE "offline|isConnected|NetworkCapabilities|ConnectivityManager|UnknownHostException"`
  across the whole Android source root returns only two unrelated things: the reader's
  `onRemoveOfflineCopy` action for a missing local file (`reader/ReaderScreen.kt:149`,
  `:249`, `:1319`, `:1341`) and comments in `auth/AO3SessionValidator.kt:15,33,55` noting
  that network failures must not log the user out. Nothing inspects connectivity, and all
  four `displayMessage()` mappers pass the transport failure straight through —
  `is AO3Error.Network -> message` — where `message` is whatever OkHttp produced.
- **Divergence:** offline on iOS is a named, reassuring state; on Android it is an
  underlying library's exception text.
- **Scenario:** a user on the Underground opens a work's comments. iPhone: "You're offline.
  Comments will load when you're back online." Android: `Unable to resolve host
  "archiveofourown.org": No address associated with hostname` — or, via finding 16's path,
  the whole `Network(message=…, cause=…)` wrapper. The user cannot tell a connectivity
  problem from an app failure, and may conclude the app is broken.
- **Evidence:** the grep above, plus reading all four `displayMessage()` bodies to confirm
  every one delegates the `Network` case to the raw message. Ruled out: (a) that Compose or
  Material surfaces an offline banner automatically — nothing does; (b) that this is
  platform idiom — Android has first-class connectivity APIs (`ConnectivityManager`,
  `NetworkCapabilities`) and Material guidance calls for an explicit offline state, so this
  is again Android diverging from its own platform rather than expressing it; (c) that it is
  covered by finding 16 — it is not: fixing `toString()` still leaves
  `is AO3Error.Network -> message` leaking transport text.
- **History:** not recorded. The `AO3SessionValidator` comments show the team has reasoned
  carefully about offline in the *auth* path ("offline must not log out"), which makes the
  absence of user-facing offline handling look like an oversight rather than a decision.
- **Recommendation:** Android moves. Classify the transport failure once — in `AO3Client`,
  where `network/ao3/AO3Client.kt:185,228` already wraps `error.message` into
  `AO3Error.Network` — by distinguishing `UnknownHostException`/`ConnectException` from other
  `IOException`s, then give that case its own copy in the shared `displayMessage()` from
  finding 16. The two findings share one fix site, so they should be done together.

### 15. You cannot open a commenter's profile from an Android comment — `gap` · Comments

Android parses and stores everything required and then never offers the tap. Unlike finding
12 this is not a dead control — the byline is plain text, so nothing lies to the user — which
makes it a clean feature gap rather than a bug.

- **iOS:** `Models/AO3CommentModels.swift:224-231` exposes
  `var profileRoute: AO3AuthorRoute?`, documented at `:221-223` as the "Single source of
  truth for avatar + byline entry points", and correctly returning `nil` for a guest, a
  deleted tombstone, or an unresolvable path. It is consumed in three places:
  `Features/Comments/CommentThreadRow.swift:1627` (`if let route = comment.profileRoute,
  let open = onOpenAuthor`) behind a "Tappable author avatar for comments" component
  declared at `:1595`, `Features/Comments/CommentsView.swift:1203` for the parent comment,
  and `Services/AO3CommentActions.swift:278` to resolve a commenter's username for actions.
- **Android:** the data is all there. `network/ao3/comments/AO3CommentModels.kt:246-251`
  defines `AO3CommentAuthor(name, profileUrl, username)`, with `username` documented as the
  "Canonical AO3 account username from the profile path, when resolvable"; the parser fills
  both — `AO3CommentParser.kt:76`, `:175`, `:326`, `:334-336`. But the byline is rendered as
  a plain, non-interactive `Text` at `comments/CommentsScreen.kt:590-596`, and `username` is
  consumed only at `:546` to resolve the participant *badge* (Me / Author / User / Guest).
  `profileUrl` has **no UI consumer at all**.
- **Divergence:** on iOS, tapping a commenter's name or avatar opens their author profile. On
  Android there is no way to get from a comment to the person who wrote it.
- **Scenario:** a reader finds a thoughtful comment on a fic and wants to see what else that
  person has written or recommended — a completely ordinary move on AO3, where commenters are
  frequently authors themselves. On iPhone: tap the avatar, land on their profile. On
  Android: no affordance exists, so the only route is to memorise the username, back out to
  Search, and look them up by hand.
- **Evidence:** traced both directions. On Android, `grep -rn "profileUrl"` across the source
  root returns only parser writes and model declarations — no screen reads it. Read the byline
  composable in full to confirm it is a bare `Text` with no `Modifier.clickable` and no
  `onClick` parameter threaded in. On iOS, read all three `profileRoute` call sites. Ruled
  out: (a) that Android offers the navigation elsewhere in the comment row — the row's other
  interactive elements are reply/edit/delete, and no author-navigation callback is declared on
  the screen (unlike finding 12, there is not even an unwired parameter); (b) that Android
  deliberately omits it because it lacks an author-profile destination — it has one,
  `author/AuthorProfileScreen.kt`, reached from work bylines; (c) that iOS's route is
  vestigial — it is used in three places including a component whose doc comment describes it
  as tappable.
- **History:** not recorded. `docs/audits/PARITY_SWEEP2_D:7` lists several comment gaps as
  already covered ("no work header / no reply / no pagination / incomplete idempotency
  guard"); commenter-profile navigation is not among them, and greps of the Android branch's
  `docs/` return nothing.
- **Recommendation:** Android moves, and it is one of the cheapest items in this report. The
  screen already knows the username and profile URL, and `AuthorProfileScreen` already takes a
  username. Thread an `onOpenAuthor: (String) -> Unit` from `AppNavHost` to the byline and
  avatar, gated exactly as iOS gates it — not a guest, not a deleted tombstone, resolvable
  username — so the affordance appears only where it will work. Pair it with finding 12: both
  are author-navigation wiring in `AppNavHost`, and fixing them together is one change.

### 14. Android marks already-in-your-library works in browse and search results; iOS does not — `gap` · Browse / search · **iOS is the platform behind here**

The second of two cases where the standing convention points the wrong way — Android has the
feature, and it is a good one.

- **Android:** `browse/BrowseLocalIndicators.kt` defines
  `BrowseLocalIndicator(isSaved, hasEpub, isFavorite, isFinished)` — four flags, documented
  at `:6` as "Local Library state for a browsed work, derived without any DB write". It is
  built once per screen from the saved-works list (`BrowseLocalIndicators.index(savedWorks)`)
  and applied per row: `browse/FandomWorksScreen.kt:96` for fandom browse results, and
  `author/AuthorWorksScreen.kt:70` + `:151` (`LocalIndicatorRow(...)`, rendered at `:204`)
  for an author's works.
- **iOS:** `Features/Search/AO3WorkRow.swift:6-14` — the remote result row takes
  `work: AO3WorkSummary`, `expandAll`, `isSelecting`, `isSelected` and nothing else. It has
  no local-state input, performs no `@Query`, and touches no `modelContext` (grep over the
  row and `Features/Browse/NativeBrowseView.swift` returns zero hits for either). Broader
  greps for `isInLibrary`, `alreadySaved`, `localIndicator`, `savedBadge`, `inLibrary`
  across `Features/Browse/`, `Features/Search/` and `UIComponents/` return **nothing**.
- **Divergence:** browsing the same fandom on both devices, Android tells you which works you
  already have; iOS does not.
- **Scenario:** a user with 300 saved works browses "Naruto (Anime & Manga)", 142,362 works
  deep. On Android, rows they have already saved, downloaded, favourited or finished carry an
  indicator, so they scroll past them. On iPhone every row looks identical, so they open works
  they finished last month to find out — one navigation, one metadata fetch, and a moment of
  "haven't I read this?" each time. The information is entirely local: iOS already has the
  `SavedWork` records and even a `WorkIdentityIndex` service for exactly this matching.
- **Evidence:** read Android's indicator type and both of its call sites; read iOS's row
  declaration in full and grepped its file and the browse view for any persistence access.
  Ruled out: (a) that iOS surfaces this somewhere else in the row's body — the row has no
  local data to surface, since nothing is passed in and nothing is queried; (b) that iOS
  deliberately avoids the DB read for performance — Android's own comment stresses the
  derivation is "without any DB write" and it is an in-memory index over an already-loaded
  list, which is the same cheap approach iOS could take; (c) that this is the known
  `BrowseLocalIndicators`-has-no-iOS-counterpart mapping question I flagged earlier in this
  review's own ledger — that is now resolved, and the answer is that it genuinely has none.
- **History:** not recorded on either side. No `TASKS.md` row and no Android-branch doc
  mentions local indicators on remote results.
- **Recommendation:** **iOS moves, against the standing convention.** This is the second case
  in this review (with finding 8) where Android is ahead, and it is worth naming the pattern:
  both are places where Android *added* something rather than porting it, so the
  "iOS is the source of truth" rule — which is about not cutting iOS down to Android's level —
  simply does not apply. The port is cheap: `Services/WorkIdentityIndex.swift` already exists
  for matching remote summaries to local records, so `AO3WorkRow` needs an optional indicator
  parameter and the two list screens need to build the index once per load, exactly as
  `BrowseLocalIndicators.index` does.

### 13. Comment timestamps are relative and localised on iOS, raw AO3 text on Android — `drift` · Comments

- **iOS:** `Models/AO3CommentTimestamp.swift` is a dedicated 116-line type. It parses through
  **nine** accepted formats (`:8-16` — `"EEE dd MMM yyyy hh:mma zzz"`,
  `"EEE dd MMM yyyy HH:mm XXXXX"`, `"dd MMM yyyy hh:mma zzz"` and six more), each with a
  formatter pinned to `en_US_POSIX` and GMT (`:26-32`), and normalises non-breaking spaces
  first (`:39`). `displayText` (`:52-80+`) then renders **relatively**:
  `RelativeDateTimeFormatter` with `.unitsStyle = .full` for anything under 24 hours old,
  a "Yesterday" branch for the previous calendar day, and an absolute format beyond that —
  all computed in the device's calendar, time zone and locale.
- **Android:** `network/ao3/comments/AO3CommentParser.kt:178` scrapes
  `.datetime, p.datetime, .posted`, takes its text, and stores it as
  `val date: String` (`AO3CommentModels.kt:194`). `comments/CommentsScreen.kt:611-613`
  renders that string **verbatim**. There is no parsing step and no formatting step.
- **Divergence:** the same comment reads "3 hours ago" on iPhone and, on Android, whatever
  literal string AO3's HTML contained — e.g. "Sat 02 Aug 2026 08:15PM UTC".
- **Scenario:** a user reads a fic's comments on both devices. On iPhone the thread is
  scannable — "12 minutes ago", "Yesterday", "2 Aug 2026" — so recency is obvious at a
  glance, which is the entire point of a comment timestamp. On Android every line carries a
  full absolute datetime in AO3's rendering, including its time-zone suffix. Two consequences:
  the thread is much harder to skim, and **the time shown is not converted to the user's own
  zone**, so a reader in UTC−7 seeing "08:15PM UTC" has to do the arithmetic themselves. That
  second part is what makes this more than cosmetic; I have still filed it as `drift` rather
  than `real-bug` because the displayed value is not *wrong*, merely unconverted and
  unfriendly.
- **Evidence:** read the iOS type end to end and traced Android from selector to pixel —
  parser `:178` → model field `:194` → `Text(comment.date, …)` at `CommentsScreen.kt:611-613`,
  with no transform anywhere between. Ruled out: (a) that Android formats it elsewhere —
  `grep -rn "getRelativeTimeSpanString\|DateUtils"` across the whole Android source root
  returns **zero hits**, so no relative-time formatting exists in the app at all;
  (b) that this is platform idiom — it is the opposite: `DateUtils.getRelativeTimeSpanString`
  is the standard Android API for exactly this and Material's guidance favours relative
  recency in feeds, so Android is diverging from *its own* platform convention, not
  expressing it; (c) that the raw string might already be device-local — it is whatever AO3
  served, and AO3 renders timestamps in the account's configured zone, which is not the
  device's.
- **History:** not recorded. `docs/audits/PARITY_SWEEP2_D:7` lists several comment gaps as
  already covered — "no work header / no reply / no pagination / incomplete idempotency
  guard" — but timestamp presentation is not among them, and greps of the Android branch's
  `docs/` for timestamp/datetime handling return nothing.
- **Recommendation:** Android moves. The parsing half is the real work and should be ported
  from `AO3CommentTimestamp.parseFormats` rather than re-derived — that nine-format list is
  accumulated knowledge about AO3's actual output, including the non-breaking-space quirk,
  and a fresh `DateTimeFormatter.ofPattern` guess will parse fewer of them. Once parsed,
  rendering is idiomatic and cheap: `DateUtils.getRelativeTimeSpanString` for the recent
  case, a `DateTimeFormatter` in the device zone beyond it. Note the failure mode to preserve:
  iOS's `displayText` returns `rawText` unchanged when parsing fails (`:60`), so an
  unrecognised format degrades to today's Android behaviour rather than to a blank.

### 12. Tapping a series in an Android author profile does nothing at all — `real-bug` · Author profile / series

A control that renders as interactive, gives tap feedback, and has no effect. This is worse
than the feature simply being absent, because the affordance tells the user it works.

- **iOS:** `UIComponents/AO3AuthorNavigation.swift:244` pushes
  `AO3SeriesDetailView(series: series)` — a real destination,
  `Features/Authors/AO3SeriesDetailView.swift:4`.
- **Android:** `author/AuthorProfileScreen.kt` has a full Series tab: the enum case at
  `:63` (`Series("Series")`), a loader at `:126-127`
  (`authorRepository.loadSeries(route, pageNum)`), an empty state at `:298`, and each row
  wrapped in `.clickable { onOpenSeries(item.url) }` at `:308`. But `onOpenSeries` is
  declared with a **no-op default** — `onOpenSeries: (String) -> Unit = {}` at `:79` — and
  nothing overrides it. `AppNavHost.kt:674-683`, the sole construction site, passes
  `username`, `authorRepository`, `onOpenWork` and `onOpenWeb`, and **omits `onOpenSeries`**.
- **Divergence:** the data layer, the tab, the list, the pagination and the tap target all
  exist on Android; only the navigation callback is unwired, so the tap resolves to `{}`.
- **Scenario:** a user opens an author they like, taps the Series tab — which populates
  correctly, so nothing looks broken — and taps "The Long Way Round, 12 works". Compose
  draws the ripple because the row is `clickable`. Nothing else happens. Tapping again does
  nothing again. On iPhone the same tap opens the series detail. The user's reasonable
  conclusion is that the app is frozen or the series is broken.
- **Evidence:** `grep -rn "onOpenSeries"` across the entire Android source root returns
  exactly **two** hits — the parameter declaration at `AuthorProfileScreen.kt:79` and the
  `clickable` at `:308`. There is no third hit, so no caller supplies an implementation.
  Confirmed by reading the only invocation (`AppNavHost.kt:674-683`) argument by argument.
  Ruled out: (a) that a series route exists and is reached another way — `Routes.kt` defines
  `home`, `library`, `browse`, `account`, `search`, `settings`, `backup`, `queue_storage`,
  `collections`, `about`, `url`, and nothing series-shaped; (b) that Android deliberately has
  no series concept — it does, `network/ao3/series/AO3SeriesRepository.kt` is real and *is*
  wired into `KudosAppContainer`, `ReadingQueueRepository`, `DownloadQueue` and
  `WorkDetailScreen`, so series data drives preservation and queue downloads; only the
  browsable destination is missing; (c) that the row is non-interactive so the user gets no
  false signal — it is `Modifier.clickable`, which applies the standard Material ripple.
- **History:** not recorded anywhere. Greps of the Android branch's `docs/` and of
  `TASKS.md` for a series-screen gap return nothing. Note that `AppNavHost` is named in
  `docs/audits/PARITY_SWEEP2_D:7` for a *different* defect ("AppNavHost shared selection
  state"), so the file has been reviewed before without this being caught — which is what an
  unwired optional parameter does: it compiles, it renders, and it reads as complete.
- **Recommendation:** Android moves, and there is a one-line stopgap worth taking
  immediately even if the native screen is deferred. `onOpenWeb` is already wired at
  `AppNavHost.kt:680-682` to `navController.navigate(Routes.webFallback(url))`; passing
  `onOpenSeries = { url -> navController.navigate(Routes.webFallback(url)) }` makes the tap
  open the series on AO3 in the app's existing WebView fallback — the same demotion pattern
  the app already uses elsewhere, and strictly better than silence. The full fix is a native
  series screen mirroring `AO3SeriesDetailView`, for which the repository and models
  (`AO3AuthorSeriesSummary`, `AO3AuthorSeriesPage`) already exist. Either way, a
  `clickable` whose handler defaults to `{}` is a pattern worth sweeping for — which I did,
  below.

**Swept for the general pattern, and it is not systemic.** A no-op-defaulted callback that
no caller supplies is invisible to the compiler, so I checked all of them rather than
assuming this was the only one. Android declares **50** parameters matching
`on[A-Z]…: (…) -> Unit = {}`; for each, I searched the whole tree for any caller supplying
it as a named argument. **Four are never supplied, and only this one loses user-facing
behaviour:**

| Never supplied | Verdict |
|---|---|
| `author/AuthorProfileScreen.kt:79` `onOpenSeries` | **finding 12** — a visible, rippling tap target that does nothing |
| `library/LibraryViewModel.kt:304` `onCreated` (`createCollection`) | benign — an optional "here is the new id" convenience; `workRepository.createCollection(name)` still runs at `:306` |
| `library/LibraryViewModel.kt:311` `onCreated` (`createQueue`) | benign — same shape; `queues.createQueue(name)` still runs at `:314` and the refresh tick still fires at `:315` |
| `update/AppUpdateInstaller.kt:54` `onProgress` | benign-ish — the download completes regardless; the only cost is that no progress UI is driven during an APK download. Worth wiring, not a defect |

That 46 of 50 are correctly wired is the reason finding 12 reads as an oversight in one
screen rather than a habit worth a broader remediation.

### 11. Android's custom clickable surfaces have no minimum touch-target floor — `gap` · Accessibility

Material 3 specifies a 48 dp minimum touch target just as firmly as HIG specifies 44 pt, so
this is not an iOS convention being imposed on Android — it is Android missing its own
platform's requirement on the controls it hand-builds.

- **iOS:** `UIComponents/MinimumHitTarget.swift:31` provides
  `func minimumHitTarget(_ size: CGFloat = 44) -> some View`, documented at `:27-30` as
  "44pt, Apple's HIG" minimum, expanding the hit region "leaving its rendered appearance
  untouched". It is applied deliberately, including at a lowered floor where dense layouts
  demand it — `Features/Library/LibraryView.swift:456` uses `.minimumHitTarget(28)` on a
  chip, an owner-chosen floor recorded in `TASKS.md` row 87 as covering six controls that
  "render back-to-back in dense `FlowLayout`/horizontal-scroll groups".
- **Android:** no equivalent exists.
  `grep -rniE "minimumInteractiveComponentSize|sizeIn\(min"` across the whole Android source
  root returns **zero** relevant hits (the three `48.dp` matches are
  `WorkCoverCardMetrics.height - 48.dp` arithmetic in `library/LibraryScreen.kt:1487,1532`,
  unrelated to touch targets). The equivalent chip is made tappable by a bare
  `Modifier.clickable` — `ui/components/KudosUi.kt:153`,
  `modifier.then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)` —
  with no size floor.
- **Divergence:** iOS guarantees a floor on custom controls; Android guarantees one only
  where it happens to use a Material component.
- **Scenario:** a user with limited motor control, or anyone on a bus, tries to tap a tag
  chip in the Library. On iPhone the chip's touch region is padded to at least 28 pt (44 pt
  elsewhere) regardless of how small the text renders. On Android a short chip — "F/F", or a
  one-character rating — is tappable only across its literal rendered bounds, which at
  default text size is well under 48 dp tall, and misses land on the chip behind it or on
  nothing.
- **Evidence:** counted the 27 `Modifier.clickable` uses across the Android tree and read the
  shared chip component. Ruled out the strongest counter-argument explicitly: **Compose
  Material 3 does apply `minimumInteractiveComponentSize()` automatically**, which would make
  this a non-issue — but it does so only for Material components (`IconButton`, `Checkbox`,
  `Switch`, and friends), **not** for a `Row`/`Box` carrying `Modifier.clickable`, which is
  what `KudosUi.kt:153` is. So the automatic floor does not reach the hand-built controls,
  which are exactly the ones iOS bothered to pad. I did **not** measure rendered heights on a
  device, so the specific claim "under 48 dp" is inferred from the absence of any minimum
  rather than observed — the *absence of enforcement* is what is verified.
- **History:** not recorded anywhere. iOS's side is recorded (`TASKS.md` row 87, part of the
  HIG pass); the Android branch's `docs/audits/` contains no touch-target entry.
- **Recommendation:** Android moves. The fix is one modifier at the shared component —
  `Modifier.minimumInteractiveComponentSize()` on the clickable branch in `KudosUi.kt:153`,
  or `.sizeIn(minWidth = 48.dp, minHeight = 48.dp)` where the visual must stay small and only
  the touch region should grow. Applying it at the shared component covers every chip at
  once, which is the same leverage iOS got from one modifier.

**Supporting measurement, for context rather than as a finding.** Accessibility annotation
density differs roughly two-to-one per file: iOS carries **274** `accessibilityLabel` /
`Hint` / `Value` / `AddTraits` / `Element` calls across **51** of 214 source files (24%);
Android carries **202** `contentDescription` / `semantics` / `stateDescription` calls across
**34** of 281 files (12%). I am deliberately not filing that ratio as a finding — the two
APIs are not one-to-one (a single Compose `semantics { }` block can carry what several
SwiftUI modifiers express, and Compose derives labels from `Text` content automatically where
SwiftUI often needs them stated), so the numbers cannot bear a per-control conclusion. They
are recorded because the direction is consistent with finding 11 and because a follow-up that
wants to audit accessibility properly now knows the shape of the gap it is looking for.

### 10. Author's notes are detected and set apart on iOS and rendered as ordinary prose on Android — `gap` · Import / reader

- **iOS:** two mechanisms converging on one output. Structurally,
  `Services/HTMLWorkSanitizer.swift:33-35` rewrites AO3's own note containers —
  `div.notes`, `div.end.notes`, `.preface .notes`, `.chapter .notes`, `#notes` — directly.
  Heuristically, `Services/AuthorNoteDetector.swift` runs a scoped phrase table over
  extracted blocks for PDF and plain-text sources, consumed at
  `HTMLWorkSanitizer.swift:72`. Both emit `<aside epub:type="note" class="author-note">`
  instead of `<p>` (`:67-70`), with adjacent notes merged into one `<aside>` "since a
  three-paragraph preamble is one note". There is a dedicated `AuthorNoteDetectorTests`
  suite and a `diagnostics(for:)` entry point for vetting new phrases.
- **Android:** nothing. `grep -rniE "authorNote|author-note|div\.notes|aside"` across the
  entire Android source root returns **zero hits**.
  `works/converters/HTMLWorkConverter.kt:34` is the whole sanitisation step —
  `Jsoup.clean(region.html(), Safelist.relaxed().removeTags("img"))` — and Jsoup's
  `relaxed()` safelist permits neither the `aside` element nor the `class` attribute.
- **Divergence:** two layers, and the second is the one that surprises.
  1. Android's own imports never *detect* notes, so a converted PDF/TXT/HTML work has its
     author's notes inline with the fiction.
  2. Even a work converted **on iOS** and carried to Android by backup or folder sync loses
     the distinction, because Android injects no CSS for `.author-note` (same zero-hit
     grep). The markup survives in the EPUB; nothing styles it.
- **Scenario:** a reader imports a community PDF of a long fic. On iPhone the chapter opens
  with the author's "A/N: sorry for the wait, this chapter has a major character death, skip
  to the break if you'd rather not" visually set apart as apparatus — which is the point,
  because that block is a content warning. On Android the same sentence is typeset as the
  first paragraph of the chapter, indistinguishable from narration. The user reads a
  spoiler, or reads an apology as prose.
- **Evidence:** read the iOS sanitiser and detector; grepped the whole Android tree for four
  independent spellings of the concept with zero hits. Ruled out: (a) that Android detects
  notes elsewhere in the import pipeline — the grep covers `works/converters/`, `files/` and
  everything else under the source root; (b) that Android's reader styles the class without
  naming it — no CSS asset or injected stylesheet mentions `author-note`, and the same grep
  would have caught it; (c) that Jsoup's `relaxed()` might pass `aside` through — it does
  not, the safelist is a fixed tag list that excludes it, so Android could not preserve
  iOS-style markup on re-import even if a note arrived pre-marked.
- **History:** **iOS-side, extensively recorded; Android-side, not at all.** `TASKS.md`
  T-157b is the implementation ("Author's-note detection, built to be extended as new PDF
  sources arrive", ✅ DONE, 10 new tests), and it states the product rationale plainly:
  "notes are apparatus, not prose, and a reader that renders them as prose makes every
  converted work read worse than the file it came from." T-158 (`✋ SPEC READY`) adds
  user-editable overrides, T-173 and T-175 extend detection. Four task rows, one dedicated
  doc (`docs/AUTHOR_NOTES.md`), and no Android counterpart anywhere — greps of the Android
  branch's `docs/` for "author note" return nothing.
- **Recommendation:** Android moves, but in two separable steps of very different cost, and
  only the first is worth scheduling now. **Step one is nearly free and should not wait for
  step two:** add `.author-note` styling to Android's reader CSS and stop stripping `aside`
  and `class` in the sanitiser (`Safelist.relaxed().removeTags("img").addTags("aside")
  .addAttributes("aside", "class", "epub:type")`). That alone makes every iOS-converted work
  render correctly on Android, which is the cross-device case a shared library actually hits.
  **Step two**, porting `AuthorNoteDetector`'s phrase table, is a larger job and carries the
  asymmetry iOS's own docs stress — "a missed note is cosmetic, a false positive demotes real
  prose" — so it should be ported wholesale with its test fixtures rather than
  re-derived, or it will be less safe than the original.

### 8. Restoring a cross-platform reading position on iPhone loses the position *within* the chapter — `real-bug` · Reader

**This is the one case where iOS is the weaker platform**, so the standing "iOS is the
source of truth" convention should not be applied here — see the recommendation.

- **iOS:** `Features/ReaderReadium/ReadiumReaderView.swift:1372-1375` — when the stored
  Readium locator fails to decode, the fallback is chapter-granularity only:
  `let fallbackSpineIndex = initialLocator == nil && work.lastSpineIndex > 0 ?
  work.lastSpineIndex : nil`, passed to `book.open(…, fallbackSpineIndex:)` at `:1384-1385`.
  `work.lastScrollFraction` is never read. Grepping every `.swift` file for
  `lastScrollFraction` shows the only *reader* that consumes it is
  `Features/Reader/ReaderView.swift:484` — the legacy WKWebView reader, which is
  `#if os(macOS)`-guarded and therefore does not run on iPhone or iPad. Every other hit
  (`KudosBackup.swift:374,430,490,550,1989`, `PersistenceSync.swift:389,439,450`) stores,
  encodes or merges the value. It is faithfully carried across devices and then ignored on
  arrival.
- **Android:** `reader/ReaderRestoreTarget.kt:14` models the cross-platform case as
  `data class Fallback(val spineIndex: Int, val scrollFraction: Double)` — both components —
  and `reader/readium/ReadiumProgressAdapter.kt:51` consumes it, with
  `reader/ReaderProgressMapper.kt:19` building it.
- **Divergence:** both platforms correctly refuse a foreign locator (see V-6) and fall back
  to the portable fields. Android's fallback restores chapter **and** offset; iOS's restores
  chapter only, discarding an offset it received, stored, and merged.
- **Scenario:** a reader is 70% through chapter 12 of a 40,000-word chapter on their Android
  phone. They back up and restore on an iPhone. Android→Android would reopen at 70% of that
  chapter. iOS reopens at the **top** of chapter 12, so they must re-find their place in
  roughly 28,000 words of text. The data needed to do better is present in the archive and
  in the SwiftData record; nothing reads it. The same applies to a macOS→iPhone move within
  one user's own devices, because the macOS reader writes the value and the iOS reader
  ignores it.
- **Evidence:** grepped `lastScrollFraction` across the whole iOS tree and classified every
  hit by whether it reads or writes; confirmed `Features/ReaderReadium/` contains **zero**
  reads. Confirmed the one reader that does read it is macOS-only by checking
  `AGENTS.md:40-44`, which states `BookReaderView` routes iOS → Readium and macOS → the
  legacy reader, and that the legacy files are `#if os(macOS)`-guarded. Ruled out:
  (a) that Readium's own restore makes the offset redundant — it would, but only when the
  *locator* decodes; this path is precisely the one where it did not; (b) that
  `lastSpineIndex > 0` guard means the position is usually recoverable anyway — the guard is
  about the chapter, not the offset, and it additionally means a work whose fallback is
  chapter 0 gets no restore at all even when `lastScrollFraction` is 0.9; (c) that Android's
  scroll fraction is not comparable — both platforms write the same
  `lastScrollFraction: Double` in the manifest (`KudosBackup.swift:374` /
  `BackupManifest.kt`), and `BackupValidator.kt:69-71` even range-checks it to `0.0..1.0`.
- **History:** not recorded. `docs/contracts/READER_STATE_CONTRACT.md` on the Android branch
  defines the resolution order Android implements ("a same-platform-compatible locator
  first, then the cross-platform fallback fields, otherwise the beginning"), quoted in
  `ReaderRestoreTarget.kt:4-6`. iOS has no counterpart document and implements a
  degraded form of the same order.
- **Recommendation:** **iOS moves, and the source-of-truth convention should be set aside
  here.** Android's `ReaderRestoreTarget` is the better model — it is explicit about all
  three cases and it does not throw away data it was given. The iOS change is small: pass
  `work.lastScrollFraction` alongside `fallbackSpineIndex` into `book.open` and seek to it
  after the chapter loads, which is what the macOS reader already does at
  `ReaderView.swift:484`. iOS should also drop the `> 0` guard on `lastSpineIndex` so a
  chapter-0 position with a non-zero fraction still restores.

### 7. Android's work search cannot express ten of AO3's search parameters, including sort direction — `gap` · Search + filters

- **iOS:** `Models/AO3Models.swift` `AO3SearchFilters` carries **37** stored fields, and the
  query builder emits **25** distinct `work_search[...]` parameters.
- **Android:** `network/ao3/search/AO3SearchFilters.kt` carries **23** fields, and
  `network/ao3/search/AO3SearchUrlBuilder.kt` emits **15** parameters.
- **Divergence:** ten parameters iOS sends have no Android equivalent at all —
  `work_search[title]`, `[creators]`, `[single_chapter]`, `[hits]`, `[kudos_count]`,
  `[comments_count]`, `[bookmarks_count]`, `[date_from]`, `[date_to]`, and
  `[sort_direction]`. The other fifteen match exactly, name for name. Android has no
  Android-only parameter, so this is a strict subset, not a different design.
- **Scenario:** two concrete ones, the second worse than the first.
  1. A user wants "Naruto works with over 1,000 kudos, posted this year". On iPhone that is
     two filter fields. On Android neither field exists, so the search cannot be expressed —
     the user scrolls 142,000 results instead.
  2. **Sort direction is the sharp one.** Android exposes `sort` (the column) but not
     `sort_direction`, so every sort is stuck on AO3's default, descending. "Fewest kudos
     first", "oldest first", "shortest first" are all unreachable on Android and one tap on
     iOS. This is not a filter the user might not miss; it is half of a control that is
     visibly present.
- **Evidence:** extracted both parameter sets mechanically rather than by reading the UI —
  `grep -rhoE 'work_search\[[a-z_]+\]' … | sort -u` over each tree, giving 25 vs 15, then
  set-differenced. Field counts came from brace-matched extraction of the two filter types
  (37 iOS stored `var`s excluding computed properties, 23 Android `val`s). Ruled out:
  (a) that Android emits these under different parameter names — the grep is over the raw
  `work_search[...]` literals, so a rename would still show up, and nothing unmatched
  appears on the Android side; (b) that these are AO3 parameters that do not actually work,
  making the gap theoretical — the opposite is proven,
  `docs/reports/filter-parity-2026-08-07.md:42-58` measured each one **live against AO3 on
  2026-08-07** and records real result-count movement for `hits` (142,362 → 78,570),
  `kudos_count` (→ 55,392), `title` (→ 23,291), `creators` (→ 83), and confirms both
  `sort_column` and `sort_direction` reorder results; (c) that iOS hides them anyway — it
  hides them only in `AO3FilterPanel.Mode.refine`, on two screens
  (`filter-parity-2026-08-07.md:76-77`), which means they are available in the primary
  search panel.
- **History:** not recorded as a decision. `docs/android/ANDROID_PORT_PLAN.md:1297` contains
  the line "Validate numeric ranges", which suggests the numeric-range filters were planned
  and not built, but no task ID owns it and no `TASKS.md` row or `docs/audits/` entry names
  any of these ten parameters. Greps for `kudosFrom`, `hitsFrom`, `commentsFrom`,
  `bookmarksFrom`, `sort_direction` across the Android branch's `docs/` return nothing.
- **Recommendation:** Android moves, per the standing convention, and the cost is low
  because the plumbing already exists — `AO3SearchUrlBuilder` already emits `word_count` as
  a range and `revised_at` as a date-ish parameter, so the four count ranges and the date
  pair are the same shape as code already written. Sort direction should go first regardless
  of the rest: it is one boolean, it completes a control the UI already shows, and it is the
  only item on this list a user can *see* is missing.

### 6. Android's User-Agent reports version 0.1.0; the app is 0.2.0 — `real-bug` · Networking

`docs/AO3_NETWORKING_POLICY.md` makes "One identifiable User-Agent, with contact" the first
of its hard rules, and frames the whole policy as "Respectful access is a hard product
requirement — community trust is the whole ballgame." Android currently misidentifies its
version to AO3 on every single request.

- **iOS:** `Services/AO3AuthService.swift:202-207` builds the UA at runtime —
  `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"`
  interpolated into `KudosReader/\(version) (+https://github.com/cidy02/kudos-ao3-reader)`.
  It cannot drift: the string is derived from the shipped bundle.
- **Android:** `network/ao3/AO3UserAgent.kt:14` — `const val APP_VERSION: String = "0.1.0"`,
  a compile-time literal, interpolated at `:19`. The actual app version is
  `android/app/build.gradle.kts:27-28` — `versionCode = 8`, `versionName = "0.2.0"`.
- **Divergence:** the two UA strings are otherwise byte-identical (I compared them
  character by character — same Safari-shaped base, same token order, same contact URL). The
  only difference is that iOS's version tracks the build and Android's is a hand-maintained
  constant that **has already fallen out of date by a minor version**.
- **Scenario:** an AO3 sysadmin sees traffic from `KudosReader/0.1.0`, correlates it with a
  behaviour they want to discuss or block, and reaches for the version. Every Android
  install — including the eight `versionCode`s shipped since — reports `0.1.0`. The
  identifiable-UA rule exists precisely so operators can distinguish releases; a frozen
  version silently removes that. It also means a future "0.1.0 has a bug, please upgrade"
  conversation cannot be acted on, because 0.1.0 is indistinguishable from current.
- **Evidence:** read both UA definitions. Confirmed `APP_VERSION` has exactly two references
  in the whole Android tree (`grep -rn "APP_VERSION" app/src/main/java/` → its own
  declaration and its own interpolation), so nothing else keeps it honest. Confirmed the
  invariant script does not catch it: `android/Scripts/check-invariants.sh:14-21` checks only
  that `Mozilla/5.0` appears nowhere outside `AO3UserAgent.kt` and that a `KudosReader/`
  token is present — never that the version matches `versionName`. Ruled out: (a) that
  `APP_VERSION` is generated or substituted at build time — it is a plain `const val` with a
  literal, and `build.gradle.kts` has no `buildConfigField` or token-replacement writing it;
  (b) that Android has no runtime alternative — `BuildConfig.VERSION_NAME` is available to
  any Android module and is exactly the `CFBundleShortVersionString` analogue.
- **History:** not recorded anywhere. Notable in context: the memory of this project records
  that Android has a GitHub self-update system where "every future fix/feature now needs a
  build+publish", so `versionName` moves regularly while this constant does not — the drift
  will keep widening on its own.
- **Recommendation:** Android moves, one line: `const val APP_VERSION = BuildConfig.VERSION_NAME`
  (adding `buildConfig = true` to the `buildFeatures` block if it is not already on). Worth
  pairing with one more line in `android/Scripts/check-invariants.sh` asserting that the UA's
  version token equals `versionName`, since the existing invariant already guards this file
  and clearly intends to keep it single-sourced — it just guards the wrong property.

### 5. A backup that round-trips through Android comes back to iOS with EPUB preservation state erased — `real-bug` · Persistence + backup

Android decodes nine optional iOS work fields, has no Room column for any of them, and does
not re-emit them on export. The archive is therefore lossy in one direction, and the loss is
silent because `explicitNulls = false` removes the keys rather than writing nulls.

- **iOS:** `Models/Models.swift` `SavedWork` stores all of them. On import,
  `Services/KudosBackup.swift:561-564` decodes a **missing** `epubPreservationStatusRaw` as
  `EPUBPreservationStatus.notPreserved.rawValue`, and `:565-568` decodes a missing
  `metadataSyncStatusRaw` as `MetadataSyncStatus.unknown.rawValue`. The merge at `:1973-1975`
  then applies it: `if incomingWins || work.epubPreservationStatus == .notPreserved {
  work.epubPreservationStatusRaw = archived.epubPreservationStatusRaw }`. On a fresh restore
  `incomingWins` is forced true (`:1895`, `isNewRecord ||…`), so the substituted default wins.
- **Android:** `data/local/entity/WorkEntity.kt` has 46 columns and none of these. The export
  mapper `backup/BackupMappers.kt:72-121` (`toBackupWork`) never mentions them, so each falls
  back to its `BackupWork` default — `null` — and `backup/BackupJson.kt`'s
  `explicitNulls = false` drops the key from the JSON entirely.
- **Divergence:** iOS→Android→iOS is not identity. Fields lost outright:
  `epubPreservationStatusRaw`, `metadataSyncStatusRaw`, `preservedAt`,
  `lastPreservationAttemptAt`, `assetIdentifier`, `datePublished`, `dateUpdated`,
  `ao3SeriesID`. (`bookmarks` is also absent but is the known T-193 divergence, not counted
  here.) **Two degrade rather than vanish, and it is only fair to say so:** `createdAt`
  falls back to `dateAdded` at `:1900`, and `ao3WorkID` self-heals because
  `:1966` re-derives it — `work.ao3WorkID ?? archived.ao3WorkID ?? WorkTags.ao3WorkID(from:
  archived.sourceURL)`.
- **Scenario:** an iPhone user has preserved 200 works — `epubPreservationStatus == .preserved`,
  which is the whole point of the preservation feature. They back up, restore on a new
  Android phone, use it for a month, then move back to iOS and restore Android's backup onto
  a clean install. Every work returns with `epubPreservationStatus == .notPreserved` and
  `metadataSyncStatus == .unknown`, despite the EPUBs themselves being present in the archive
  and restored correctly. AO3 publication and update dates are blank, series IDs are gone.
  Nothing warns the user, and there is no way to tell the restored state from a library that
  was never preserved. The clean-install case is the one that matters: with an existing local
  record, `newest(work.preservedAt, archived.preservedAt)` at `:1978-1982` keeps the local
  value, so the loss only bites in exactly the disaster-recovery scenario backups exist for.
- **Evidence:** derived the column/field diff mechanically rather than by eye — extracted
  stored (not computed) `var`s from `SavedWork` and `val`s from `WorkEntity` and set-differenced
  them: 64 stored iOS properties against 46 Room columns. Then read `toBackupWork`
  (`BackupMappers.kt:72-121`) in full to confirm the export omission, and the iOS decode
  defaults at `KudosBackup.swift:555-575` to confirm what a missing key becomes.
  Ruled out: (a) that `BackupValidator` carries unknown work fields through — its
  carry-through comment and `manifest.copy(...)` cover *queues, annotations and tombstones*
  only, and in any case that path runs during **import**, so it cannot survive a trip through
  a Room database that has no column; (b) that the fields are recovered by a later AO3 refresh
  — `epubPreservationStatusRaw` and `preservedAt` describe local file state, which no network
  refresh restores; (c) that iOS ignores a missing key instead of substituting — it does not,
  the `?? …notPreserved.rawValue` is explicit.
- **History:** partially acknowledged, in a way that makes the gap sharper.
  `backup/BackupManifest.kt:97` labels this exact block "Apple v5–v8 optional work fields
  (ignored for local model until ported)" — so the *decode* side is a conscious deferral. But
  `backup/BackupValidator.kt:130-131` shows the team already understands the round-trip
  hazard and solved it elsewhere: "Queues/annotations/tombstones are applied by
  BackupMergeService; carry them through here unchanged **so re-export doesn't drop
  anything**." Work fields never got that treatment. No `TASKS.md` ID covers it.
- **Recommendation:** Android moves, and it does not need 9 new columns to do it. **The
  codebase already contains a working precedent for the cheap fix** — see V-13: saved-search
  filters are stored as an opaque `filtersJson` string and re-emitted verbatim
  (`backup/BackupMappers.kt:271, 280`), so iOS-only filter keys survive an Android round trip
  untouched. Apply the same shape here: add one `unmappedFieldsJson` TEXT column to
  `WorkEntity`, stash the undecoded remainder on import, and splice it back in
  `toBackupWork` — preserving every present and future iOS field for the cost of one column
  and one migration. Porting the fields properly is the better long-term answer for the two
  that drive UI (`datePublished`, `dateUpdated`) and the preservation trio, but the
  pass-through is what stops the bleeding now. Either way this wants the round-trip test that
  does not exist on either platform: export → import → export → assert the two manifests are
  equal.

### 4. Restoring an iOS backup on Android converts every queue-only work into a saved library item — `real-bug` · Backup / restore

This was lead L-3; it is now confirmed, and it turns out to defeat the exact feature
finding 3 shows Android has just implemented.

- **iOS:** `Services/KudosBackup.swift:1931` merges the flag by last-writer-wins and
  nothing else — `work.isSaved = incomingWins ? archived.isSaved : work.isSaved`. iOS
  *deliberately produces* works with `isSaved == false` and an EPUB present:
  `Services/ReadingQueueService.swift:300` and `:550` both run
  `if createdNewWork { saved.isSaved = false }` and then immediately
  `try await preserve(saved, in: context, downloadEPUB:)`, which downloads and stores the
  EPUB. That is the queue-only-with-preserved-EPUB state, and
  `Models/Models.swift:378-380` defines `isQueueOnlyWork` as
  `isQueuedForLater && !isSaved && !isFavorite`.
- **Android:** `backup/BackupMergeService.kt:193`, inside the `incomingWins` branch —
  `isSaved = restored.isSaved || existing.isSaved || (existing.hasEpub || restored.hasEpub)`.
  The presence of an EPUB on *either* side forces `isSaved` true regardless of what the
  archive says. `core/model/SavedWork.kt:81-82` defines `isQueueOnlyWork` identically to
  iOS, so forcing `isSaved` true also forces `isQueueOnlyWork` false.
- **Divergence:** iOS treats "saved to Library" and "has a local EPUB" as independent;
  Android's restore treats an EPUB as proof of saved-ness. `isSaved` can therefore only ever
  travel false→true across a restore on Android, never true→false.
- **Scenario:** on iPhone, add a work to a reading queue without saving it. iOS creates it
  with `isSaved = false` and preserves the EPUB, so it stays out of the Library shelves and
  out of Reading Now / Recently Updated / Recently Opened — that is the whole point of the
  queue-only concept. Back up, restore on Android. `restored.isSaved` is false and
  `existing` is absent, but `restoredHasEpub` is true because the archive carried the EPUB,
  so `:193` evaluates to true. The work lands as a full Library item, is counted in the
  saved totals, and appears in the Home sections `home/HomeSectionKind.kt:50,59,64`
  explicitly filters queue-only works out of. A second, subtler case: un-save a work on
  iOS that has a downloaded EPUB, sync, and the un-save never reaches Android.
- **Evidence:** read `mergeWork` in full, both branches (`BackupMergeService.kt:176-284`).
  Ruled out: (a) that the `else` branch compensates — it does not touch `isSaved` at all
  (`:205-229`), which correctly mirrors iOS's `: work.isSaved`, so the divergence is
  confined to the `incomingWins` branch; (b) that the neighbouring rules diverge too, which
  would suggest a generally sloppy port — they do not: `isQueuedForLater` is OR'd on both
  (iOS `:1971`, Android `:194`), `dateAdded` is `min` on both (iOS `:1901`, Android `:195`),
  `lastModifiedAt` is `max` on both (iOS `:1996`, Android `:196`). `isSaved` is the one
  field that departs, which is why it reads as an oversight rather than a design;
  (c) that Android's `hasEpub` derivation is itself wrong — it is not,
  `BackupMergeService.kt:63-67` grounds it in real file presence
  (`incomingEpub != null || id in currentEpubIds || existing?.hasEpub == true`).
- **History:** not recorded. The `isSaved` semantics *cluster* is documented on the Android
  branch (`docs/audits/ANDROID_PARITY_REPORT.md:231,247,292`), but every instance there is
  in the import/library-query paths — `WorkImporter.saveMetadataOnly`,
  `WorkMetadataMerger.merge`, `WorkRepository.observeSavedWorks`. No document mentions
  `BackupMergeService`, and greps for `isSaved` across `docs/` return no hit in a backup
  context. This is a new instance of a known root divergence, in a file nobody has looked at.
- **Recommendation:** Android moves, and the fix is to delete the clause:
  `isSaved = restored.isSaved` in the `incomingWins` branch, matching iOS exactly. The
  `hasEpub` guard is protecting the wrong invariant — Android already preserves the EPUB
  itself via `hasEpub = existing.hasEpub || restored.hasEpub` on the next line, and
  `SavedWork.kt:69-75` already folds `isQueuedForLater` into deletion protection, so
  nothing needs `isSaved` forced true to keep the file safe. Worth pairing with the
  round-trip test neither platform has: save → un-save → export → restore → assert
  `isSaved` is still false.

### 3. The Android branch's own audit corpus is stale: the `isQueuedForLater` / queue-only gap it reports as open is implemented — `real-bug` (in the documentation) · Cross-cutting

This is a finding about the *record*, not the code, and it is reported because acting on
that record would waste a work cycle re-building something that exists.

- **Claimed, in three places on the Android branch:**
  `docs/audits/ANDROID_PARITY_REPORT.md:231` — "On Android there is no
  `isQueuedForLater`/queue-only concept at all in `SavedWork` (`core/model/SavedWork.kt`)
  or `LibraryQuery`." `docs/audits/ANDROID_PARITY_FINDINGS_VERIFIED.md:59` lists it as
  **CONFIRMED**, and `:23` names it among the "Highest-priority CONFIRMED majors (still
  open)". `docs/audits/PARITY_SWEEP2_A_home-library-queues-stats.md:6,24` then excludes
  the whole cluster from re-review on the grounds that it is already covered as a known
  open gap.
- **Actually, at `a5a46116`:** it is implemented, and implemented as a deliberate mirror of
  iOS.
  - `core/model/SavedWork.kt:21` — `val isQueuedForLater: Boolean = false`, with the
    comment at `:17-20` explicitly citing iOS's `SavedWork.isQueuedForLater` and noting it
    is "Kept distinct from `isSaved`".
  - `core/model/SavedWork.kt:80-82` — `val isQueueOnlyWork get() = isQueuedForLater &&
    !isSaved && !isFavorite`, documented as "iOS `SavedWork.isQueueOnlyWork`". That is
    character-for-character the iOS predicate the audit quotes from `Models.swift:376-378`.
  - `data/local/entity/WorkEntity.kt:59` — the backing Room column exists.
  - `home/HomeSectionKind.kt:50`, `:59`, `:64` — queue-only works are filtered out of
    exactly three sections, which are the same three (Reading Now / Recently Updated /
    Recently Opened) the audit says iOS excludes them from at `HomeSections.swift:57,66,71`.
  - `library/LibraryQuery.kt:14` carries a comment stating a queue-only work is
    "intentionally not on the main saved" shelf, and
    `core/model/SavedWork.kt:69-75` folds `isQueuedForLater` into the deletion-protection
    predicate with the note "queue-add now preserves the EPUB".
- **Divergence:** between the Android branch's documentation and the Android branch's code.
- **Scenario:** a planner reads `ANDROID_PARITY_FINDINGS_VERIFIED.md`, sees a
  highest-priority confirmed-open major, and schedules "add `isQueuedForLater` to Android".
  The work is already done. Worse, `PARITY_SWEEP2_A:6` uses the same belief to *exclude*
  the area from a later sweep, so the cluster is simultaneously "known open" and "not
  re-checked" — the state in which a stale claim survives indefinitely.
- **A second cluster, checked independently, is stale in every one of its three claims.**
  `ANDROID_PARITY_FINDINGS_VERIFIED.md:79-81` records three CONFIRMED Reading-statistics
  defects. All three are fixed at `a5a46116`:
  1. *"`ReadingStatistics.hasStarted` omits `readiumLocator`"* (`:79`, elaborated at
     `ANDROID_PARITY_REPORT.md:306` quoting the field list). **Fixed** —
     `library/ReadingStatistics.kt:84-90` reads
     `work.isFinished || work.lastReadDate != null || !work.readiumLocator.isNullOrBlank()
     || work.lastSpineIndex > 0 || work.lastScrollFraction > 0.0`. The locator check is
     `:87`, at the exact lines the audit cites as lacking it.
  2. *"`formatCompactNumber` can emit '1000.0K' near 999950 due to round-then-suffix"*
     (`:80`). **Fixed** — `library/ReadingStatisticsScreen.kt:490-500` now rounds first and
     then picks the unit, and its comment names the audit's own example: "rounding a tier's
     scaled value to 1 decimal can itself reach 1000 (e.g. 999,950 / 1000 = 999.95, which
     rounds to '1000.0'), which belongs in the next unit up".
  3. *"Missing `readiumOnlyWorkCountsAsStarted` regression test"* (`:81`). **Fixed** —
     `ReadingStatisticsTest.kt:128` is `readiumLocatorOnlyStillCountsAsStarted()`, seeded
     with a locator-only work and commented "A backup restore can land a work with only a
     Readium locator and no…", i.e. it tests the precise state the audit said was untested.
- **Evidence:** greps run against `a5a46116` — `grep -n "isQueuedForLater|isQueueOnly"
  core/model/SavedWork.kt data/local/entity/WorkEntity.kt` and
  `grep -rn "isQueueOnly" --include="*.kt" .`, which returns hits in `SavedWork.kt`,
  `settings/QueueStorageScreen.kt` (`:119`, `:244`, `:281`, `:316`),
  `home/HomeSectionKind.kt` and `library/LibraryQuery.kt`; then direct reads of
  `ReadingStatistics.kt`, `ReadingStatisticsScreen.kt` and `ReadingStatisticsTest.kt` for the
  second cluster. I did **not** verify the *whole* first cluster: whether
  `WorkImporter.saveMetadataOnly` still hard-codes `markSaved = true` (the audit's other
  half) is **unchecked** — see lead L-4. So the correct statement is "the model/query half
  of the queue cluster is closed, and the Reading-statistics cluster is closed entirely",
  not "the corpus is wrong everywhere".
- **Why this changes the conclusion:** one stale entry is bookkeeping. **Three clusters
  spot-checked, three stale — one of them in all three of its claims, including a fix whose
  code comment quotes the audit's own worked example, and another whose fix comment names the
  iOS function the audit said was missing. The corpus is not drifting; it is systematically
  behind the code.** The fixes were evidently made *from*
  these reports and the reports were never marked resolved. Anyone planning from
  `ANDROID_PARITY_FINDINGS_VERIFIED.md` today will schedule work that is already done.
- **History:** the audit documents carry no revision date tying them to a SHA, which is why
  the staleness is invisible from inside them. Note the same pattern as finding 1's
  `BACKUP_FORMAT.md:83`: an Android-branch document asserting something the code
  contradicts. In finding 1 the doc over-claims completion; here it under-claims it. Both
  directions cost real work.
- **Recommendation:** neither platform's code moves. The Android audit documents should
  gain a "verified at `<sha>`" line and have this cluster's status corrected. More
  generally: the review prompt's first rule — "review the trees, not the reports" — is
  earning its place. Two of the three documents this review cross-checked turned out to
  misdescribe the code.

---

## Bugs present on both platforms

### 2. Sync skips any changed file whose byte length is unchanged — `real-bug` · `DEFERRED` · Backup / folder sync · **both platforms**

> **This is not a new discovery, and this review adds nothing to it.** It is already
> written up — correctly, in more detail than I would have given it, and on both halves —
> on the Android branch at `docs/iOS_Issues_Found_While_Porting.md:69-96`, under the
> heading "Sync skips unchanged files by size alone, so a same-size edit never syncs".
> That entry cites the same iOS lines (`:707-710`, and `:687` for the unconditional
> manifest write), makes the same "the index stays correct while the asset is stale —
> arguably worse than both being stale" argument, proposes the same fix ("A content hash,
> or size plus modification time, would close it"), **and already records that Android
> ported it deliberately**: *"ported faithfully (`backup/SyncRepository.kt`
> `writeIfChanged`), because iOS is the specification for this sweep and diverging
> unilaterally would make the two platforms disagree about what 'unchanged' means. Fix
> both together."*
>
> It is retained here, tagged `DEFERRED`, for exactly one reason: it is the clearest
> instance in the codebase of the category this report is asked to surface, it remains
> unfixed at both review SHAs, and it has no `TASKS.md` ID, so nothing schedules it. The
> only thing I verified independently is that it is still true at `e9ed0c6a` / `a5a46116`.

- **iOS:** `kudos-ao3-reader/Services/FolderSyncService.swift:707-709` —
  `writeIfChanged` returns early when `existingSize == data.count`, comparing **only**
  the file's byte length against the new payload's byte length. No hash, no mtime.
- **Android:** `backup/SyncRepository.kt:217-221` — `writeIfChanged` returns early when
  `file.length() == data.size.toLong()`. The same rule, ported faithfully, including the
  name of the function.
- **Divergence:** none between the platforms — that is the point. This is one wrong
  assumption implemented identically twice, so no amount of iOS↔Android comparison
  surfaces it; only asking what the rule *is* does.
- **Scenario:** a user has work X synced. AO3's copy is edited by its author — a typo
  fixed, a word swapped for another of the same length, a punctuation change — and Kudos
  re-downloads the EPUB. EPUB is a ZIP: a same-length content change very often yields a
  same-length archive (the compressed streams differ, the central directory and entry
  sizes do not move). `writeIfChanged` compares 41,932 bytes to 41,932 bytes, returns
  early, and the sync folder keeps the **old** EPUB forever. Every other device syncing
  from that folder receives the stale text. The manifest is rewritten (it goes through
  the unconditional path, not `writeIfChanged`), so the sync *reports success* and the
  user has no signal at all that one work's content never propagated. The same applies to
  a custom font replaced by a different font of identical file size.
- **Evidence:** read both implementations in full. Confirmed that the manifest write does
  **not** go through `writeIfChanged` on either platform (iOS `FolderSyncService.swift:687-690`;
  Android `SyncRepository.kt:201-206`), so nothing downstream compensates — the manifest
  changing does not cause the asset to be re-copied. Ruled out: (a) that EPUBs are
  content-addressed by name, so a changed file would land under a new name — they are not,
  the name is `<work-uuid>.epub` on both sides (iOS `:680`, Android `:169`) and is stable
  across re-downloads; (b) a checksum anywhere in either path —
  `grep -niE "sha|md5|checksum|digest"` over both files returns zero hits.
  **Not** ruled out by grep alone, and worth stating precisely: iOS *does* read
  modification dates in this file — `coordinatedContentModificationDate` at
  `FolderSyncService.swift:741-748`, called from `:273`, `:338` and `:380`. Reading those
  three call sites shows they all operate on `manifestURL` (and a legacy URL), to decide
  sync *direction* and staleness of the folder as a whole. None of them is on the
  per-asset path, and `writeIfChanged` at `:707-709` consults nothing but size. Android
  has no modification-date read at all in `SyncRepository.kt` (same grep, zero hits).
- **Why it is written this way:** deliberately, and for a good reason — the iOS comment at
  `:677-679` explains that leaving unchanged files untouched (same inode) is what lets
  iCloud Drive upload only the delta. Hashing every EPUB on every sync would be the
  obvious fix and would cost a full read of the library each time. So this is a real
  trade-off that was made consciously on iOS; what is missing is that the *cheap* half of
  the trade-off was taken without the correctness half.
- **History:** `docs/iOS_Issues_Found_While_Porting.md:68-90` (Android branch) records the
  iOS side; nothing records the Android side, and nothing in `TASKS.md` assigns it an ID or
  a decision. It has therefore been known and unowned for as long as that document has
  existed.
- **Recommendation:** both platforms move, and the fix should stay cheap: compare
  `(size, mtime)` rather than size alone. That keeps the same-inode / delta-upload property
  the iOS comment is protecting, costs one stat per file instead of a full read, and closes
  the case above because a re-download updates mtime even when it does not change length.
  A content hash is the belt-and-braces option and is not worth a full library read on
  every sync. iOS already has the helper it needs —
  `FolderSyncService.swift:741-748`'s `coordinatedContentModificationDate` — currently used
  only against the manifest; Android would use `DocumentFile.lastModified()`, which it does
  not currently call anywhere in `SyncRepository.kt`.

---

### 19. Both platforms carry dead persistence schema, in opposite directions — `minor` · Persistence · **both platforms**

Not a divergence between the apps so much as the same habit expressed twice. Grouped because
each half individually is too small to file and together they explain several of the
"field one platform has and the other doesn't" rows in V-11.

- **iOS carries an unused per-record sync-status scaffold.** `SavedWork`, `WorkCollection`,
  `ReadingQueue` and `ReadingQueueMembership` each declare `syncStatusRaw`,
  `lastSyncAttemptAt` and `lastSyncError`, with a computed `syncStatus` accessor
  (`Models/Models.swift:147-148,367-369`; `:593-594,607-609`; `:632-633,661-663`; and the
  membership block). Grepping the whole iOS tree for these names returns hits in
  **`Models/Models.swift` only** — no feature writes them, no view reads them, and
  `lastSyncError = ` has zero assignment sites anywhere. Four models carry three columns each
  that nothing populates or consumes.
- **Android carries two unreachable collection columns.** `CollectionEntity` declares
  `description` and `sortOrder`, `BackupCollection` serialises both
  (`backup/BackupManifest.kt`), and `library/CollectionsScreen.kt:243-245` renders the
  description when non-blank. But `grep -rn "description = \|sortOrder = "` filtered to
  collections returns **zero** write sites, and `WorkRepository.createCollection(name)`
  (`works/WorkRepository.kt:417`) takes only a name. iOS's `WorkCollection` has neither field
  at all, so no archive from either platform can ever populate them. The render branch is
  unreachable.
- **Why this is `minor` and not a data-loss finding:** I checked the obvious worry first —
  that an Android-authored collection description would be dropped by an iOS round trip,
  which would be the mirror of finding 5. It cannot happen, because nothing ever sets the
  field. Both halves are inert.
- **Evidence:** the greps above, plus reading `createCollection` and the four iOS model
  blocks. Ruled out: (a) that iOS's sync fields are written by the folder-sync service under
  a different spelling — `FolderSyncService.swift` and `PersistenceSync.swift` contain no
  assignment to any of the three; (b) that Android's `sortOrder` drives collection ordering —
  `CollectionsScreen` sorts by name, and nothing reads the column.
- **History:** not recorded on either side. The iOS trio looks like scaffolding for a
  per-record sync-status UI that was never built; Android's pair looks like a collection
  description feature that was designed as far as the render and then stopped.
- **Recommendation:** low priority, and the *decision* matters more than the deletion. Either
  finish or delete. If per-record sync status is still wanted on iOS, it needs writers before
  it needs columns; if not, dropping twelve unused properties makes the next
  `SavedWork`-vs-`WorkEntity` diff (the one that produced finding 5) considerably easier to
  read. Android's `description`/`sortOrder` should either get a create/edit path or come out
  with a Room migration. Deleting on either side is safe *only* after confirming no archive
  in the wild carries a value — which, per the evidence above, none can.

---

## Asymmetric test coverage

Partially assessed. The shape of the two suites, established by direct enumeration:

| | iOS | Android |
|---|---|---|
| Test files | 85 under `KudosTests/` | 93 under `android/app/src/test/` |
| Test targets / source sets | one target, `KudosTests` (only `name = KudosTests;` appears in `AO3_App_OpenSource.xcodeproj/project.pbxproj`) | one source set, `src/test` (JVM) |
| UI / instrumented tests | **none** — no UI-test target, and `grep -rl XCUIApplication KudosTests` → zero hits | **none** — `android/app/src/androidTest/` does not exist |
| UI-test dependency declared | n/a | yes — `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` at `android/app/build.gradle.kts:110`, plus the Compose BOM at `:77` |
| Android-framework simulation in unit tests | n/a | Robolectric (`android/app/build.gradle.kts:117`), used by ≥10 unit tests incl. `ReaderViewModelPreferencesTest.kt`, `CommentsViewModelDraftTest.kt`, `RoutesNavigationTest.kt`, `ThemeTest.kt` |

Two observations follow, and they point in opposite directions:

1. **Neither app has a single UI-level test.** This is a *shared* gap, not an asymmetry —
   every screen on both platforms is verified only by the human screenshot gate that
   `AGENTS.md` mandates. It is recorded here rather than in Findings because it is a
   property of the project's testing strategy, not a divergence between the two apps.
2. **Android declares an instrumented-test dependency it never uses.**
   `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` is resolved on every
   build for a source set that does not exist. That is dead build configuration —
   `minor`, and worth deleting or filling.

### One per-rule asymmetry, established

The full per-rule comparison is **not done** — it is the substance of this section and
belongs to area 21, which was never dispatched. But the backup/sync area produced one
instance directly, and it is the one that matters most, because it sits under finding 1:

| | iOS | Android |
|---|---|---|
| Folder-sync tests | `KudosTests/FolderSyncTests.swift`, **796 lines**, plus `FolderSyncBackgroundTaskTests.swift` | **none** — `android/app/src/test/…/backup/` contains only `BackupCompatibilityTest.kt` and `DatabaseChangeTrackerTest.kt` |

`SyncRepository.kt` — the file holding both findings above — has no test of any kind.
That is precisely the prediction the review prompt makes about asymmetric coverage: *where
one platform pins a rule and the other does not is where the divergence appears next*.
Here it already has. The write-atomicity rule is pinned on iOS by a 796-line suite and is
unpinned on Android, and Android is the platform that lost it.

---

## Already-known divergences, re-checked

The calibration list from the review prompt. Status filled in as each area is reached.

| Known divergence | Recorded in | Re-checked? | Status |
|---|---|---|---|
| "Show zero counts" (Settings → Library) is iOS-only; Android always shows zeros | `TASKS.md` T-193 | ⬜ | |
| Android's `SavedWork` has no `bookmarks` column | `TASKS.md` T-193 | ⬜ | |
| Compose `FlowRow` applies `SpaceBetween` to a wrapped last row; iOS leaves it ragged | `TASKS.md` T-193 | ⬜ | |
| iOS ships two readers (Readium iOS / legacy macOS); Android has one | prompt | ⬜ | |
| Android has a GitHub-backed self-update system; iOS has none | prompt | ✅ | **Still true.** `grep -rniE "appUpdate\|checkForUpdate\|releases/latest\|api\.github\.com\|installUpdate\|AppUpdateRepository" kudos-ao3-reader --include="*.swift"` returns exactly two hits, both `WorkUpdateChecker` — which checks *AO3 works* for new chapters (`Services/WorkUpdateChecker.swift:17`, called from `Features/Home/HomeView.swift:134`), not the app. iOS has no app-update path of any kind. Android's lives in `update/` + `network/github/`. |

---

## Open leads

*Nothing is ever deleted from this section — leads are promoted to Findings or moved
to Ruled out with a reason.*

**L-1 — the Android branch's in-tree copy of the iOS app is 122 files behind.**
Suspicion: Android work is being ported against a stale iOS reference, so "parity"
decisions recorded on the Android branch may be parity with an iOS that no longer
exists. Where seen: `find .claude/worktrees/android-exclusion-parity/kudos-ao3-reader
-name '*.swift' | wc -l` → **92**, versus **214** in `hig-review-reference`. The check
that settles it: diff the file lists, then confirm whether any Android-side doc or
task cites iOS behaviour that `hig-review` has since changed. This is a process
finding, not a user-visible one — it is recorded here because it predicts *where*
user-visible drift will be found.

**L-3 — RESOLVED → promoted to finding 4.** The `isSaved` merge-rule divergence is
confirmed: iOS assigns the flag outright (`KudosBackup.swift:1931`), Android ORs it with
EPUB presence (`BackupMergeService.kt:193`), so an iOS queue-only work becomes a saved
Library item on restore. See finding 4 for the full write-up and the ruled-out alternatives.

**L-6 — the bug report may not carry a screenshot on Android.** Suspicion: iOS ships
`Features/Support/ScreenshotCapture.swift` alongside `BugReportView.swift` and
`ShakeDetector.swift`; Android's `support/` contains only `BugReport.kt` and
`ShakeDetector.kt`, and `account/BugReportScreen.kt:73` tells the user "Only these app and
system details are attached" with no image. A shake-to-report that captures the screen on
one platform and not the other is a real difference in what a maintainer receives. Why it is
a lead and not a finding: I did not open `BugReportView.swift` to confirm iOS actually
attaches the capture to the outgoing report rather than using it for something else, and
attaching screenshots is a place where the platforms' share sheets genuinely differ. The
check that settles it: read `Features/Support/BugReportView.swift` for its use of
`ScreenshotCapture`, then `support/BugReport.kt` for the Android payload.

**L-7 — Android's inbox parser mirrors iOS's fail-open-on-partial-failure policy, so the
known iOS weakness is present on both.** iOS `Services/AO3Client+Inbox.swift:50-51` throws
`AO3Error.parse` only when `parsedItems.allSatisfy({ $0 == nil })`; Android
`network/ao3/inbox/AO3InboxParser.kt:47-50` does the same — `runCatching { parseInboxItem }
.getOrNull()` per row, then throw only if all are null. `TASKS.md` row 64 already records
this on iOS as F7 ("low severity, requires unusual AO3 markup to trigger"). Recorded as a
lead rather than a both-platforms finding because F7's severity assessment was made for iOS
and I have not re-derived whether it holds identically on Android — Android's parser has two
guards iOS's lacks (`AO3OverloadDetector.isOverloadPage` at `:29` and a `LoginRequired`
check at `:31`), which may change the reachable failure modes. The check that settles it:
feed both parsers a fixture where half the rows are malformed and compare what each returns.

**L-5 — RESOLVED → finding 18.** Confirmed: Android's own EPUB inventory *is*
filesystem-verified (`backup/BackupRepository.kt:112-118` filters on
`Files.isRegularFile(workFileStore.workEpubPath(id))`), but the trailing
`|| existing?.hasEpub == true` at `backup/BackupMergeService.kt:64` still lets a stale
database flag win. See finding 18. Original text follows.

**L-5 (original) — Android may not downgrade a stale `hasEpub` when the file is gone.** Suspicion:
iOS actively clears the flag — `KudosBackup.swift:1229`, `work.hasEPUB = false` in the
`else if !FileManager.default.fileExists(...)` branch, which also demotes
`epubPreservationStatus` to `.missingFile`. Android's equivalent
(`BackupMergeService.kt:64-67`) computes
`existingHasEpub = id in currentEpubIds || existing?.hasEpub == true` — the trailing OR
means a DB flag that is already true survives even when the work has no file on disk and
none in the archive. A user whose EPUB was removed out from under the app (storage
cleaner, restored-from-a-thinner-backup) would keep seeing the work as downloaded on
Android and would see it correctly marked missing on iOS. The check that settles it: read
what populates `currentEpubIds` in `BackupMergeService`, then test a restore where the DB
says `hasEpub = true`, no file exists locally, and the archive carries no EPUB for that id.
Low severity — cosmetic until the user taps Read — but it is the same class as finding 4:
a flag Android can raise and never lower.

**L-4 — RESOLVED: the other half of the `isQueuedForLater` cluster is also fixed.** Both
claims in `docs/audits/ANDROID_PARITY_REPORT.md:292` are stale at `a5a46116`:
(1) `WorkImporter.saveMetadataOnly` no longer hard-codes `markSaved = true` — its KDoc
(`works/WorkImporter.kt:30-37`) now states that "Queue-add (see
`WorkDetailScreen.ensureLocalThen`) passes `markSaved = false, isQueuedForLater = true` so a
not-yet-saved work stays queue-only (`SavedWork.isQueueOnlyWork`) instead of becoming a full
Library item", with the parameter merely *defaulting* true for ordinary save/download callers,
which is iOS's behaviour too. (2) `ReadingQueueRepository.removeWork` does perform the
queue-only cleanup — `library/ReadingQueueRepository.kt:130-150` is commented "iOS parity:
removeFromQueueAndDeleteIfQueueOnly" and soft-deletes a work that has lost its last membership
and was never explicitly saved or favourited. It is in one respect *more* careful than iOS:
it re-reads the row after the intervening writes (`:145`, `val freshEntity = workDao.getById`)
rather than deciding from a snapshot taken before the suspension points, with a comment
explaining the race. **This closes finding 3's caveat: the queue cluster is fully closed, not
half.** It also makes three of three spot-checked audit clusters stale.

**L-2 — `exportedAt` is the one manifest date that bypasses Room, and its precision is
unverified.** Suspicion: R-1 below proves the date round trip is safe *because* every
`Instant` is milli-precision after a Room round trip. `exportedAt` is the exception — it
comes straight from an injected clock, `backup/BackupRepository.kt:31`
(`private val clock: () -> Instant = { Instant.now() }`), and `backup/SyncRepository.kt:31`
does the same. iOS decodes it as a real `Date` (`KudosBackup.swift:228`) through the strict
two-formatter strategy. If `Instant.now()` on the target Android runtime returns
microsecond-precision nanos — as `Clock.systemUTC()` does on OpenJDK 9+, though Android's
libcore has historically been millisecond-backed — then `formatInstant` emits six fractional
digits, iOS's fractional formatter rejects it, the whole-second fallback rejects it, and
`KudosBackup.swift:200-205` throws. That aborts the **entire** import of an Android-written
archive on iOS. Where seen: `BackupValidator.kt:161` (`instant.toString()`) reached from a
non-Room source. The check that settles it: on a device/emulator at the project's `minSdk`,
evaluate `Instant.now().nano % 1_000_000` — non-zero means the hazard is live. The fix is
one call either way and is worth making unconditionally: `.truncatedTo(ChronoUnit.MILLIS)`
in `formatInstant`, which also makes Android's output identical in shape to iOS's for every
field. **I could not settle this from source alone and am not claiming it as a defect.**

---

## Verified agreement

A verified "these genuinely agree" is a result, not an absence of one. This section records
only comparisons where the rule was non-trivial and I read both implementations in full.

### V-1 — the sync merge/conflict rules are semantically identical, including the parts most likely to rot

`SyncMerge` is the decision core of backup restore on both platforms: it decides which
record survives a conflict, whether a deleted record may be revived, and how a reading
queue's effective modification time is computed. iOS `Services/PersistenceSync.swift:379-431`
against Android `backup/BackupMergeService.kt:718-753`, function by function:

| Rule | iOS | Android | |
|---|---|---|---|
| `shouldApplyIncoming` — incoming missing | `guard let incomingModifiedAt else { return false }` (`:396`) | `if (incomingModifiedAt == null) return false` (`:720`) | ✅ |
| — local missing | `guard let localModifiedAt else { return true }` (`:397`) | `if (localModifiedAt == null) return true` (`:721`) | ✅ |
| — both present | `incomingModifiedAt >= localModifiedAt` (`:398`) | `!incomingModifiedAt.isBefore(localModifiedAt)` (`:722`) | ✅ same relation, **ties go to incoming** on both |
| `effectiveQueueModifiedAt` | max of the non-nil of (`dateUpdated`, `lastMembershipChangedAt`) plus every membership's `lastModifiedAt` (`:405-412`) | `(listOfNotNull(queueUpdatedAt, lastMembershipChangedAt) + membershipModifiedAts).maxOrNull()` (`:726-733`) | ✅ |
| `tombstoneResolution` — no tombstone | `.noTombstone` (`:428`) | `NO_TOMBSTONE` (`:739`) | ✅ |
| — tombstone but no incoming timestamp | `.preserveAmbiguous` (`:429`) | `PRESERVE_AMBIGUOUS` (`:740`) | ✅ |
| — both present | `incomingModifiedAt > tombstoneDeletedAt` → revive, else suppress (`:430`) | `incomingModifiedAt.isAfter(tombstoneDeletedAt)` → `REVIVE_NEWER`, else `SUPPRESS_STALE` (`:741-745`) | ✅ **strict** `>` on both, so **ties suppress** |

The detail worth dwelling on is the last two rows against the third. `shouldApplyIncoming`
uses a **non-strict** comparison (a tie applies the incoming record) while
`tombstoneResolution` uses a **strict** one (a tie suppresses, i.e. a deletion wins a tie
against a same-instant edit). That asymmetry is deliberate and easy to lose in a port —
it is the difference between "a tie is harmless" and "a tie must not resurrect something
the user deleted". Android preserves it exactly. Both enum shapes match too, four cases
each with the same names.

**One thing was not ported: the reason.** iOS carries a comment at `PersistenceSync.swift:401-405`
explaining that `effectiveQueueModifiedAt` *deliberately* takes no
restore/import wall-clock parameter, because doing so "previously let a content-stale backup
revive an explicitly-deleted queue just because the file itself happened to be newer than
the tombstone" — i.e. it records a fixed bug. Android's equivalent (`:726-733`) has the
correct signature but no such note; its KDoc is only "Apple `SyncMerge` helpers used by
backup restore." Nothing is wrong today. The risk is that a future change to the Android
side that adds an export-time parameter looks like a reasonable improvement and silently
reintroduces a bug iOS already paid for. Recorded as `minor`, with the fix being one
comment, not one line of code.

---

### V-13 — saved searches round-trip losslessly through Android, including filters Android cannot itself use

This is the counter-example to finding 5, in the same codebase, and it is why that finding's
recommendation is cheap rather than speculative.

`SavedSearch` matches on both sides — iOS `Models/SavedSearch.swift` (`id`, `name`,
`dateAdded`, `filters`) against Android `data/local/entity/SavedSearchEntity.kt` (`id`,
`name`, `dateAdded`, `filtersJson`). The interesting part is how Android treats the filter
payload, which is where finding 7's 37-vs-23 field gap should have caused data loss:

- **Storage is opaque.** Android keeps the filters as an unparsed JSON string. Import does
  `filtersJson = filters.toString()` (`backup/BackupMappers.kt:280`); export does
  `filters = filtersJson.toJsonObjectOrEmpty()` (`:271`). Neither goes through a typed model,
  so **keys Android has no field for are carried through untouched**.
- **Parsing happens only at point of use.** `search/SearchFiltersCodec.kt:39-46` decodes into
  a DTO with `ignoreUnknownKeys = true` when Android actually needs to *run* the search.
- **The codec was written for cross-platform compatibility on purpose.** Its KDoc (`:21-26`)
  states that "Enum cases use Apple's camelCase raw values (`appleCaseName`) so the JSON is
  semantically compatible with Swift `AO3SearchFilters` Codable payloads", and iOS's
  `CodingKeys` (`Models/AO3Models.swift:253-260`) confirm the shared names line up.

So a search saved on iPhone with `kudosFrom: 1000` and `sortDirection: asc`, restored on
Android and re-exported, arrives back on iOS **with both values intact**.

The honest caveat, which is finding 7's consequence rather than a new defect: while that
search sits on the Android device, *running* it silently ignores those two filters, because
`AO3SearchUrlBuilder` has no parameter to emit for them. The stored data is faithful; the
executed query is narrower than the user saved. A user who saved "1000+ kudos, oldest first"
on their phone gets an unfiltered, newest-first result set on their tablet, with the saved
search still displaying its original name.

### V-12 — Home and Work Detail agree on the things most likely to drift: predicates, caps, order, and labels

Both areas were opened expecting drift — Home because section queries are easy to get subtly
wrong, Work Detail because the review prompt uses its stat row as *the* example of drift
("a field that says 'Word count' on one and 'Words' on the other"). Neither delivered.

**Home (area 11).** Five shelves on both, in the same order — Reading Now, Recently Updated,
Subscriptions, Favorites, Recently Opened (iOS `Features/Home/HomeView.swift:9` documents the
order; Android renders it at `home/HomeScreen.kt:172, 196, 218, 230, 253`). The four *local*
sections live in a shared enum on each side; Subscriptions is a network section handled
separately on both, which resolves the "4 sections each" note from my earlier pass.

Predicates and ordering are identical clause for clause
(iOS `Features/Home/HomeSections.swift:52-73`, Android `home/HomeSectionKind.kt:45-64`):

| Section | filter | sort |
|---|---|---|
| Reading Now | `isInProgress && !isQueueOnlyWork && visible` | `recency` desc |
| Favorites | `isFavorite && visible` | `recency` desc |
| Recently Updated | `hasUpdate && !isQueueOnlyWork && visible` | `lastUpdateCheck` desc |
| Recently Opened | `lastReadDate != nil && !isQueueOnlyWork && visible` | `lastReadDate` desc |

…including the `recency` helper itself (`lastReadDate ?? dateAdded` on both), the shelf cap
(iOS `.prefix(12)` at `HomeView.swift:196`; Android `HomeShelfLimit = 12` at
`HomeScreen.kt:595`), and persisted per-section collapse state (iOS `collapseKey:
"home.\(kind.rawValue)"` at `HomeView.swift:192`; Android `CollapsedSections` /
`collapsedShelves` at `HomeScreen.kt:221-222`). Three of four empty-state strings are
character-identical; the fourth is the **deliberate, documented** divergence from
`docs/iOS_Issues_Found_While_Porting.md:12-41`, which Android annotates in place at
`HomeSectionKind.kt:24-27` — iOS's copy names subscriptions for a section that filters on
`hasUpdate`, and Android kept the accurate wording rather than porting a known-wrong string.

**Work Detail (area 6).** The stat row matches in label *and* order:
`Words`, `Chapters`, `Hits`, `Kudos`, `Comments` (iOS
`Features/WorkDetail/WorkDetailOverviewSections.swift:251, 254, 270, 273, 298`; Android
`works/WorkDetailScreen.kt:1735-1745`). The prompt's example drift does not occur — neither
platform says "Word count". Both format with grouping separators from the active locale
(iOS `.formatted()`, Android `"%,d".format(...)`).

Every AO3 action is present on both: Give Kudos, Comments, Bookmark on AO3,
Subscribe/Unsubscribe, Mark for Later, Open on AO3. **I nearly filed Subscribe as an
Android gap and was wrong** — a literal-string grep missed it because the label is built
dynamically at `works/WorkDetailScreen.kt:1327`
(`if (state.isSubscribed == true) "Unsubscribe" else "Subscribe"`), and `:272-283` prefetches
the live subscription state so the menu matches AO3 before the user taps. Recorded because it
is exactly the false positive rule 4 of the review method exists to prevent.

One label differs and it is defensible: iOS says "Mark for Later"
(`AO3WorkActionsMenu.swift:41`), Android "Mark for Later (AO3)"
(`WorkDetailScreen.kt`). Android carries a *local* "Saved for Later" queue alongside the AO3
server action, so the suffix disambiguates two things that would otherwise read identically
in one menu. Not filed as drift — it is a local disambiguation iOS does not need.

### V-11 — the remaining seven entities carry the same information; every apparent gap resolves to naming, idiom, or dead schema

Finding 5 covered `SavedWork` ↔ `WorkEntity`. This is the other seven pairs, diffed
mechanically (brace-matched Swift property extraction against Room `data class` `val`s) and
then read where the diff was non-empty.

| iOS model | Android entity | Result |
|---|---|---|
| `SyncTombstone` (9) | `SyncTombstoneEntity` (9) | **exact match**, field for field |
| `Bookmark` (3) | `BookmarkEntity` (4) | match + Room's synthetic `id` primary key |
| `CustomFont` (3) | `CustomFontEntity` (4) | match + Room's synthetic `id` |
| `Tag` (2) | `TagEntity` (3) | match + `id`; Android adds `dateCreated`, which iOS does not track. Cosmetic — nothing reads it |
| `WorkCollection` (12) | `CollectionEntity` (9) | see below |
| `ReadingQueue` (14) | `ReadingQueueEntity` (10) | see below |
| `ReadingQueueMembership` (12) | `ReadingQueueMembershipEntity` (7) | see below |

Three classes of apparent difference, none of them a data gap:

1. **Relationships vs foreign keys.** iOS's `works`, `memberships`, `queue`, `work` are
   SwiftData relationship properties; Android expresses the same edges as
   `queueID`/`workID` columns plus junction tables with `ForeignKey(onDelete = CASCADE)`
   (`CollectionEntity.kt:29-39`, `ReadingQueueEntity.kt:34-38`, `TagEntity.kt:22-32`). Pure
   platform idiom.
2. **`isPendingDeletion` vs `isDeleted`.** The rename is the documented convention —
   `docs/AGENT_ONBOARDING.md:39` records that iOS *must* avoid `isDeleted` on an `@Model`
   because it collides with `NSManagedObject.isDeleted` and silently resets on save, while
   the backup JSON key stays `isDeleted`. Both platforms honour exactly that.
3. **Membership soft-delete: different mechanism, same outcome.** iOS keeps a soft-deleted
   membership row (`deletedAt`, `isPendingDeletion`); Android hard-deletes the row and
   records a tombstone instead (`library/ReadingQueueRepository.kt:114-128`, with the comment
   "Without a tombstone, restoring a backup that still lists this membership silently
   resurrects it"). Since merge suppression on both platforms is driven by the tombstone
   index, not by the row, the two converge — and neither platform's manifest carries
   membership deletion flags, so nothing is lost across the wire either.

### V-10 — the comment model carries the same information on both platforms

Ordered by the review prompt's own checklist for this area — "author, pseud, avatar,
role/badge, timestamp, chapter, edited-state, deleted/hidden state, thread depth". iOS
`AO3Comment` (`Models/AO3CommentModels.swift`) declares **24** stored properties, Android
`AO3Comment` (`network/ao3/comments/AO3CommentModels.kt:191-245`) **21**. The difference is
naming and convenience, not information:

| Concept | iOS | Android | |
|---|---|---|---|
| identity, byline, guest flag | `id`, `author`, `isGuest` | same names | ✅ |
| anonymous creator | `isAnonymousCreator` | `isAnonymousCreator` | ✅ |
| avatar | `avatarURL` | `avatarUrl` | ✅ |
| body | `bodyText` | `body` | ✅ |
| chapter | `chapterID`, `chapterLabel` | `chapterId`, `chapterLabel` | ✅ |
| **deleted / hidden** | `isDeleted` (`:199`, with a comment explaining AO3's "(Previous comment deleted.)" placeholder `li`) | `isDeletedOrHidden` (`:197`) | ✅ both, both rendered (iOS `:225`, Android `CommentsScreen.kt:623`) |
| thread cutoff | `isThreadCutoff`, `cutoffCount`, `cutoffThreadPath` | same three | ✅ |
| reply affordance + actions | `canReply`, `editPath`, `deletePath` | same three | ✅ |
| threading | `threadPath`, `parentThreadPath`, nested `replies` | same, plus `depth` and `parentCommentId` | ✅ Android carries the depth explicitly where iOS derives it from nesting |
| **role / badge** | `AO3CommentParticipantRole` — `me`, `author`, `user`, `guest` (`:6-10`) with a `resolve(...)` taking commenter/current username and work authors | `AO3CommentParticipantRole` (`:99`) resolved at `CommentsScreen.kt:541-550` with the same inputs | ✅ same four roles |
| timestamp | `postedText` **and** `postedAt` (raw + parsed) | `date` (raw only) | ⚠️ **finding 13** |
| commenter profile link | `userPath` → `profileRoute` (`:224-231`) | `AO3CommentAuthor.profileUrl` + `username` — parsed and stored, never used for navigation | ⚠️ **finding 15** |

iOS's three remaining extras — `threadActionURL`, `parentThreadURL`, `cutoffThreadURL` — are
resolved-`URL` conveniences over the `*Path` strings both platforms already store (`:232`
onward), not additional data.

So the model layer is sound on both, and the two comment findings are about what the *UI*
does with fields Android has already parsed, not about missing information. Worth stating
plainly because the opposite would have been a much larger problem.

### V-9 — every reading statistic is computed identically, formula for formula

This was the highest-value untouched item on the ledger, on the theory that a statistic
computed from a different denominator on each platform is invisible until someone compares
two phones. I compared all nine statistics plus the derived rate. They agree.

| Statistic | iOS (`Features/Library/ReadingStatistics.swift`) | Android (`library/ReadingStatistics.kt`) | |
|---|---|---|---|
| `totalWorks` | `works.count` (`:41`) | `works.size` (`:67`) | ✅ |
| `startedWorks` | count where `isFinished \|\| hasStartedReading` (`:37-39`, `:68`) | count where `hasStarted` (`:54`, `:84-90`) | ✅ same predicate — see below |
| `finishedWorks` | `works.filter(\.isFinished)` (`:40`) | `works.filter { it.isFinished }` (`:55`) | ✅ |
| `inProgressWorks` | `started.filter { !$0.isFinished }` (`:41`) | same (`:56`) | ✅ |
| `wordsRead` | `finished.reduce(0) { $0 + max(0, $1.wordCount) }` (`:47-49`) | `finished.sumOf { maxOf(0, it.wordCount) }` (`:58`) | ✅ **over finished only**, on both |
| `latestReadDate` | `works.compactMap(\.lastReadDate).max()` (`:50`) | `works.mapNotNull { it.lastReadDate }.maxOrNull()` (`:59`) | ✅ over *all* works on both |
| `openedLast7Days` | window `startOfDay(now) - 6 days` (`:53-54`) | `startOfToday.minusDays(6)` (`:64`) | ✅ |
| `openedLast30Days` | `- 29 days` (`:55-56`) | `.minusDays(29)` (`:65`) | ✅ |
| window bounds | `date >= start, date <= end` (`:75`) | `!date.isBefore(since) && !date.isAfter(through)` (`:97`) | ✅ inclusive both ends, both |
| `topFandoms` | dedupe per work, count over **started** (`:58`, `:82-90`) | same, over **started** (`:75`, `:106-115`) | ✅ |
| `completionRate` | `finished / started`, 0 when `started == 0` (`:26-29`) | same (`:34-38`) | ✅ |

The `hasStarted` predicate is the one worth spelling out, because it is where iOS was bitten
before. iOS defers to the model — `Models.swift:421-424`,
`lastReadDate != nil || !readiumLocator.isEmpty || lastSpineIndex > 0 || lastScrollFraction > 0`
— with a comment at `ReadingStatistics.swift:63-67` recording *why*: "a private re-listing of
its fields here once drifted (it missed the Readium reader's locator, undercounting works
read only on iOS)". Android re-lists the fields inline at `ReadingStatistics.kt:84-90`
rather than deferring to its own `SavedWork.hasStartedReading`. **The re-listing is currently
correct** — all five terms match, in the same order — and both platforms now carry a
regression test for the locator-only case (iOS `KudosTests/ReadingStatisticsTests.swift:67`
`readiumOnlyWorkCountsAsStarted`, Android `ReadingStatisticsTest.kt:128`
`readiumLocatorOnlyStillCountsAsStarted`). So this is a **structural risk, not a defect**:
the duplication that caused iOS's past bug still exists on Android, but the values agree and
a test now pins the case that would catch drift. It is not filed as a finding because there
is no wrong behaviour to report; it is noted here so that a future change to
`SavedWork.hasStartedReading` on Android is known to need a second edit.

One genuinely trivial difference, recorded for completeness rather than action: the
fandom tie-break sorts by count descending then name ascending on both, but iOS uses
`localizedCaseInsensitiveCompare` (`:96`) and Android `String.CASE_INSENSITIVE_ORDER`
(`:118`). These agree for ASCII and can differ for names with diacritics or non-Latin
scripts, and only when two fandoms have exactly equal counts. Not worth a code change.

### V-8 — write actions, Home sections, account lists and HTML sanitisation all agree

Four smaller comparisons, grouped because each came out clean and none needs its own section.

**Write actions (area 6) are at parity down to the user-facing strings.** Every endpoint
matches: `kudos.js` (iOS `Services/AO3WriteActions.swift:282`, Android
`network/ao3/writes/AO3WriteUrls.kt:17-21`), `/works/<id>/comments` (iOS `:283-285`,
Android `:24-32`), `/works/<id>/chapters/<cid>/comments` (Android `:34-46`, iOS via
`AO3Client+Comments`), `/users/<u>/subscriptions` (iOS `:293-295`, Android `:48-57`),
`/works/<id>/mark_for_later` (iOS `:297-299`, Android `:59-67`), `/works/<id>/bookmarks`
(iOS `:301-303`, Android `:69-77`). The duplicate-action paths agree too, including the
literal text shown to the user: iOS `:32-33` returns "You've already left kudos here." on a
422 whose body contains "already left kudos"; Android `AO3WriteRepository.kt:41-42` returns
the same sentence on the same condition (`statusCode == 422 && parser.alreadyKudosed(body)`,
with the matcher at `AO3WriteFormParser.kt:125`). "You're already subscribed." likewise
(iOS `:114-115`, Android `:96-97`). Both fetch the work page with `view_adult=true` for the
CSRF token (iOS `:290`, Android `AO3WriteUrls.kt:12`) and both deliberately omit that
parameter on listing endpoints — iOS explains why at `AO3Client.swift:453-458` (it defeats
AO3's public caching). *Caveat, from the project's own docs rather than my testing:*
`docs/AO3_NETWORKING_POLICY.md` records that iOS write actions "have never been exercised
against a live AO3 session". Neither platform's write path is runtime-verified; this is
static agreement only.

**Home sections (area 11).** Four cases each, same names, same order: iOS
`Features/Home/HomeSections.swift:9-12` (`readingNow`, `recentlyUpdated`, `favorites`,
`recentlyOpened`) against Android `home/HomeSectionKind.kt:17,23,31,36` (`ReadingNow`,
`RecentlyUpdated`, `Favorites`, `RecentlyOpened`). Note the known iOS copy bug in
`recentlyUpdated`'s empty message is already recorded on the Android branch
(`docs/iOS_Issues_Found_While_Porting.md:12-41`) with Android deliberately keeping the
accurate wording — not re-reported here.

**Account list types (area 12, partially).** Both expose the same four AO3 account lists:
iOS `Features/Bookmarks/AO3AccountWorksList.swift:14-17` (`markedForLater`, `bookmarks`,
`history`, `subscriptions`) and Android `account/AccountListType.kt:81-84`
(`MarkedForLater`, `Bookmarks`, `History`, `Subscriptions`). iOS additionally routes
Collections, Works and Series through separate `AccountView` destinations
(`Features/Account/AccountView.swift:66-100`); whether Android reaches those by another
route was **not** checked, so area 12 stays open.

**HTML sanitisation is allowlist-based on both (area 13).** iOS `HTMLWorkSanitizer.swift`
is a hand-rolled allowlist whose header states the reasoning — imported markup "is treated
as hostile input — allowlist, not denylist, because a denylist is a list of the attacks you
happened to think of" — dropping images and all styling. Android reaches the same posture
with `Jsoup.clean(region.html(), Safelist.relaxed().removeTags("img"))`
(`works/converters/HTMLWorkConverter.kt:34`): Jsoup's `relaxed()` permits no `script`, no
`style` attribute, and restricts `a[href]` to safe protocols, so the XSS vector is closed on
both. The two *deliberate omissions* iOS documents — images dropped, no styling — hold on
Android as well. The cost of Android's stricter safelist is finding 10.

### V-7 — reader settings and the backup settings payload match field for field, default for default

The settings payload is the second artefact that crosses platforms, so it carries the same
data-loss risk as the work records. It is clean.

**Backup payload: 21 fields, 21 matches, same order.** iOS `KudosBackupSettings`
(`Services/KudosBackup.swift:743-763`) and Android `BackupSettingsPayload`
(`backup/BackupManifest.kt:200-221`) declare an identical field list —
`readerFontID, readerMode, readerTwoPage, readerCustomize, readerBoldText, readerFontPt,
readerLineHeight, readerLetterSpacing, readerWordSpacing, readerMargin, readerJustify,
confirmBeforeDelete, hideMatureContent, matureContentMode, requireBiometricToReveal,
appTheme, readerTheme, matchAppReaderTheme, accentColorHex,
autoPreserveSmallSeriesOnSaveForLater, autoPreserveSeriesWorkThreshold` — with no field
unique to either side. The seeded defaults agree too: `18` pt, `1.65` line height, `28` pt
margin, `#990000` accent (iOS `:738-741`, Android `:202-221`).

**Runtime defaults agree.** Android's user-facing `ReaderSettings`
(`core/model/SettingsModels.kt:53-62`) defaults to `readerFontPt = 18.0`,
`readerLineHeight = 1.65`, `readerMargin = 28.0`, letter/word spacing `0.0`,
`readerJustify = false` — matching iOS's `ReaderStyle` constants
(`Features/Reader/ReaderStyle.swift:236-252`) exactly.

**A trap I nearly reported and should not have.** Android's engine-level
`ReaderPreferences` (`reader/settings/ReaderPreferences.kt:28`) declares
`lineHeight: Double = 1.2`, which looks like a visible typography divergence from iOS's
1.65. It is not: that object is engine-facing, its data-class default is always overwritten
by `ReaderSettingsMapper.map` (`reader/settings/ReaderSettingsMapper.kt:36`), and the value
that reaches it comes from `ReaderSettings.readerLineHeight`, which defaults to 1.65. The
unit differences alongside it — `fontSizePercent` against iOS's absolute points,
`pageMarginsFactor` against iOS's absolute margin — are likewise a documented adapter to
Readium-Kotlin's native units (`:12-20`), with `fontSizePercent(pt) = (pt / 18) * 100` and
`marginsFactor(pt) = pt / 28`, both anchored on the shared defaults. Correct, not drift.

### 9. Android still accepts a negative letter-spacing range that iOS deliberately removed — `minor` · Settings / reader

Recorded because it is a clean instance of the pattern this review was asked to hunt — a fix
made on one platform and never ported — even though its user-visible impact is nil.

- **iOS:** `Features/Reader/ReaderStyle.swift:246-250` — `letterSpacingRange = 0.0 ... 0.12`,
  carrying an explicit comment that the range *used to* include negatives and no longer
  does: "Readium's `letterSpacing` preference rejects negative values
  (`ReadiumReaderStyleMapper.preferences`), so the negative half this range used to
  advertise could never render on iOS and is now clamped away".
- **Android:** `backup/BackupValidator.kt:174-175` — `settings.readerLetterSpacing
  .takeIfFiniteIn(-0.03, 0.12)`, i.e. still the pre-fix range including the negative tail.
- **Divergence:** on restore, Android accepts and stores a letter-spacing of, say, −0.02;
  iOS's range does not include it.
- **Scenario, honestly bounded:** the user sees nothing. Android's own render path clamps it
  again at `reader/settings/ReaderSettingsMapper.kt:37` —
  `letterSpacingEm = reader.readerLetterSpacing.coerceAtLeast(0.0)` — so a stored negative
  renders as 0, which is what iOS would show too. The only observable consequence is that
  the stored settings value differs between two devices restored from the same archive, and
  would differ again if either re-exported. Nothing in the UI surfaces it.
- **Evidence:** compared all five clamped ranges. Four match exactly — font 12–34
  (iOS `:243`, Android `:171`), line height 1.2–2.4 (iOS `:245`, Android `:172-173`), word
  spacing 0.0–0.6 (iOS `:251`, Android `:176-177`), margin 8–64 (iOS `:252`, Android `:178`).
  Letter spacing is the single mismatch. Ruled out that Android renders the negative — the
  `coerceAtLeast(0.0)` above is unconditional on the mapping path.
- **History:** not recorded. The iOS comment describes the change as already made, so the
  ordering is clear: iOS tightened the range, Android's validator kept the old bounds.
- **Recommendation:** Android moves; change `-0.03` to `0.0` in `BackupValidator.kt:174`.
  One character of real content. Worth doing not for the impact but because the two files
  are meant to encode the same contract, and a reader comparing them will otherwise wonder
  which is right.

### V-6 — neither platform will apply the other's Readium locator, so a cross-platform restore cannot land in the wrong place

The review prompt flags this as a blocker-severity risk: "a locator saved on one platform
must survive backup→restore onto the other … a format mismatch here is a BLOCKER because it
silently loses a user's place." The dangerous outcome would be one platform *accepting* the
other's locator and resolving it to a wrong position. Neither does.

Android is explicit about it. `reader/ReaderLocatorCodec.kt:28-31` wraps every locator it
writes in a self-describing envelope — `{"platform":"android","engine":"readium-kotlin",
"version":1,"locator":{…}}` — and `decodeCompatibleLocator` (`:52-63`) returns the inner
locator **only** when all three of `platform`, `engine` and `version` match its own
constants, returning null otherwise. Its KDoc states the intent directly: treat foreign
locators "as incompatible, falling back to `lastSpineIndex`/`lastScrollFraction`."

iOS reaches the same outcome by different means, and I checked rather than assumed. It
writes a bare Readium Swift locator with no envelope — grepping the iOS tree for
`readiumLocatorPlatform`, `readiumLocatorEngine` and `readiumLocatorVersion` returns **zero
hits**, so the three fields Android reserves in `backup/BackupManifest.kt:70-72` are never
populated by iOS. On read, `Locator(persistenceString:)`
(`Features/ReaderReadium/ReadiumNavigatorContainer.swift:503-510`) is a *failable*
initialiser guarding on UTF-8 decode, `JSONSerialization`, `JSONValue`, and finally
`try? Locator(json:)`. Android's envelope has no `href`/`type`/`locations` at its top level,
so the toolkit's own decode fails and the initialiser returns nil — which routes to the
fallback path rather than to a wrong position.

So the blocker does not exist in either direction: iOS rejects Android's envelope
structurally, and Android rejects iOS's bare locator by the missing `platform` key. **What
the two do next differs**, and that is finding 8 — but no user is silently dropped at an
incorrect location, which was the risk worth chasing.

### V-5 — the `required-tags` markup trap is handled identically on both platforms

The review prompt singles this out as the AO3 trap most likely to produce a silent
behaviour difference: a `ul.required-tags` row is a *summary icon* whose label holds every
value comma-joined (`"F/F, M/M"`), not a list of elements. Splitting it wrong yields either
one mashed-together tag or a dropped one.

Both platforms get it right, and by the same method. iOS
`Services/AO3Client.swift:1600-1607` and Android
`network/ao3/search/AO3SearchParser.kt:236-239` implement `splitRequiredTag` as
split-on-comma → trim → drop empties, and the six-line doc comment above each is the same
text on both sides, down to the worked examples and the closing "Verified against live
`/tags/<t>/works` markup."

The selectors that feed it also match one for one:
`ul.required-tags .rating .text` (iOS `:1632`, Android `:73`),
`.category .text` (iOS `:1636`, Android `:78`),
`.iswip .text` (iOS `:1637`, Android `:80`; and in the author parsers, iOS
`AO3Client+Authors.swift:193`, Android `AO3AuthorParser.kt:147`),
`.warnings .text` (iOS `:1658`, Android `:100`). Both apply the split to categories and
warnings and take rating as a scalar, which is correct — rating is single-valued.

The only textual difference is the empty check: iOS guards `!label.isEmpty`, Android
`label.isNullOrBlank()`. Android therefore also rejects a whitespace-only label up front,
but since both then trim and filter empties, the returned list is identical for every
input. Not a divergence.

### V-4 — every AO3 politeness constant matches, and Android enforces the no-retry-on-writes rule more strongly than iOS

`docs/AO3_NETWORKING_POLICY.md` is binding on both platforms and specifies exact numbers.
They agree, and one of them says so in a comment.

| Rule (policy doc) | iOS | Android | |
|---|---|---|---|
| Pacing ≥ 0.6 s between request **starts** | `AO3Client.swift:180` — `minRequestInterval: TimeInterval = 0.6` | `AO3NetworkConfig.kt:6` — `minDelayBetweenRequestsMillis = 600`, with the comment "Apple paces at 0.6s between starts (AO3RequestDefaults). Keep parity." | ✅ |
| Concurrency cap of 3 | `AO3RequestCoordinator.swift:28` — `init(limit: Int = 3)`, with `:16` noting it "matches the polite '2–3 concurrent metadata requests'" | `AO3NetworkConfig.kt:4` — `maxConcurrentRequests: Int = 3` | ✅ |
| Max 2 retries | `AO3Client.swift:298` — `withRetry<T>(maxRetries: Int = 2, …)` | `AO3NetworkConfig.kt:7` — `maxRetries: Int = 2` | ✅ |
| Backoff 0.5 s → 1 s → 2 s | `AO3Client.swift:330` — `0.5 * pow(2, Double(attempt - 1))` | `AO3RetryPolicy.kt:36` — `500L * (1L shl (retryNumber - 1).coerceAtLeast(0))` | ✅ identical curve |
| `Retry-After` honoured, floored by backoff | `:332-333` — `max(retryAfter ?? 0, backoff)` | `:38-39` — `maxOf(error.retryAfterMillis ?: 0L, backoff)` | ✅ |
| Retry only transient (5xx / 429 / transport) | `:331-340` — `rateLimited`, `server`, transient `URLError`; everything else returns `nil` | `:22-33` — `Network`, `Overloaded`, `RateLimited`, `Server` true; `BadRequest`, `AuthenticationRequired`, `Forbidden`, `NotFound`, `Http`, `Parse`, `Validation` false | ✅ |
| Identifiable UA, single-sourced | `AO3AuthService.swift:202-207` | `AO3UserAgent.kt:16-20` | ⚠️ same string, stale version — **finding 6** |

Two asymmetries that are *not* defects and are worth recording so nobody "fixes" them:

1. **Android enforces the write rule structurally; iOS enforces it by construction.** The
   policy says writes are "single-shot: never retried, never coalesced". Android's
   `AO3RetryPolicy.shouldRetry` opens with `if (method != AO3HttpMethod.GET) return false`
   (`:19`) — no non-GET can be retried, whatever the error. iOS achieves the same by having
   `submitWrite` simply not call `withRetry`. Android's is the more robust expression of the
   rule, because a future caller cannot accidentally opt a POST into retries. If anything,
   iOS could adopt it.
2. **Android has an `Overloaded` error class iOS does not** (`AO3OverloadDetector.kt`,
   handled at `AO3RetryPolicy.kt:24` and `:39`). It is treated exactly like `RateLimited` —
   retried, `Retry-After` honoured. That is an addition in the politeness direction, so it
   does not violate the policy's "no removal/weakening" clause. I did **not** read
   `AO3OverloadDetector.kt` to see what it detects; noted rather than assessed.

### V-3 — session storage, cookie handling and logout are at parity; no privacy divergence

The review prompt calls out weaker credential storage on one platform as a blocker-severity
privacy finding. I went looking for it and it is not there.

| | iOS | Android |
|---|---|---|
| Session store | Keychain, one item — `Services/AO3SessionVault.swift:96` `KeychainAO3SessionVault`, written with `SecItemAdd`/`SecItemUpdate` (`:127`, `:130`) | `auth/AO3SessionStore.kt:26` `EncryptedFileAO3SessionStore`, AES-256-GCM via `MasterKey.Builder(...).setKeyScheme(AES256_GCM)` (`:35-37`), i.e. hardware-backed Android Keystore |
| Device-only / no cloud escape | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`:125`) — never syncs to iCloud Keychain, never restored to another device | file lives under `context.noBackupFilesDir` (`:116`), so it is excluded from Android auto-backup and device transfer |
| What is in plaintext | a bare "removal pending" flag and a username *hint* in `UserDefaults` (`:49`, `:68`), documented at `:40` and `:67` as "Non-secret — a bare flag, never session data" | nothing; the legacy plaintext store is discussed below |
| WebView cookie jar | `WKWebsiteDataStore.default().httpCookieStore` (`AO3SessionVault.swift:312`, `:317`, `:342`) | `android.webkit.CookieManager` (`auth/AO3CookieStore.kt:15`) |
| Logout clears the web cookie jar | yes | yes — `clear()` (`:41-51`) re-sets every AO3 cookie expired, for both `BASE_URL` and `WORKS_HOST`, then `flush()` |

Both scope the cookie wipe to AO3's hosts rather than nuking the whole jar, which is the
correct choice on both platforms.

**Ruled out — Android's plaintext session store is not reachable in production.**
`auth/AO3SessionStore.kt:111` defines `FileAO3SessionStore`, which writes the session as
unencrypted JSON. Its own KDoc at `:107-110` says it is "retained only for unit tests that
don't need Android Keystore". I did not take that on trust: `grep -rn` for its constructor
across the whole Android source root returns exactly one production wiring site,
`app/KudosAppContainer.kt:103`, and it passes `EncryptedFileAO3SessionStore`. Further, the
encrypted store actively migrates and deletes any legacy plain file (`:100`). Not a finding.

**One real asymmetry, reported as a note rather than a finding.** iOS's `logout()`
(`Services/AO3AuthService.swift:504-533`) does five things Android's
(`auth/AO3AuthRepository.kt:170-174` → `clearSession()` at `:184-188`) does not: it advances
a session generation to invalidate in-flight requests (`:505`), cancels the in-progress
login (`:506`), deletes the username hint (`:515`), clears the logged-out identity's
unresolved comment-submission guards (`:522-524`, annotated T91-RF2 — "must not survive the
account they were made under"), and refuses to report success if the durable delete threw
(`:526-533`, annotated A5-F4). Android's is four lines and reports no error.

I am not filing this as a finding for two reasons, and both are worth stating so a later
session does not re-open it. First, the leak iOS's comment-store clearing prevents does not
exist on Android: `network/ao3/comments/CommentDraftStore.kt:20-22` keys every draft by
`"draft:$workId:$chapterId:$parentId:${username ?: "guest"}"`, so account A's text can never
surface for account B — the same partitioning iOS achieves with `entriesByIdentity`
(`Services/CommentSubmission.swift:119-151`). The residual behaviour difference is only that
a draft survives on Android if the *same* user logs back in, which is arguably the better
product behaviour. Second, the *idempotency* half — Android lacking iOS's unresolved-submission
guard — is already documented on the Android branch
(`docs/audits/PARITY_SWEEP2_D_workdetail-reader-comments-infra.md:7`, "incomplete idempotency
guard", listed as already covered). What is genuinely unrecorded is the missing
delete-failure reporting, which is a one-line honesty gap rather than a user-visible defect.

### V-2 — Android's Room migration story is safe, and no destructive fallback exists

The review prompt flags `fallbackToDestructiveMigration` as a data-loss blocker if reachable
in a release build. It is not present:
`grep -rn "fallbackToDestructiveMigration|allowMainThreadQueries"` across the whole Android
source root returns **zero hits**. `data/local/KudosDatabase.kt:44-45` declares
`version = 7, exportSchema = true`, and `data/local/KudosDatabaseMigrations.kt` provides an
explicit, hand-written `Migration` object for every step — `MIGRATION_1_2` (`:20`),
`2_3` (`:159`), `3_4` (`:173`), `4_5` (`:181`), `5_6` (`:192`), `6_7` (`:199`). Six
migrations covering versions 1→7 with no gaps, so an existing user's database is carried
forward rather than recreated.

The comparison to iOS is not symmetric and should not be forced: SwiftData performs
lightweight migration implicitly from the model definitions, so there is no iOS artefact to
diff against these. The correct parity statement is that both platforms preserve an
upgrading user's data, by different mechanisms — which is a platform-idiom difference, not
drift. Note also `data/local/converters/KudosTypeConverters.kt:31-38`, which degrades a
corrupt JSON list column to `emptyList()` rather than throwing, with a comment explaining
that one bad row must not take down every query touching the column. That is defensive
behaviour iOS has no equivalent of, and it is a point in Android's favour rather than a gap.

---

## Ruled out

**R-1 — backup date encoding is *not* incompatible between the two apps.** This was the
most promising lead in the whole backup area and it does not survive contact with the code,
so it is worth recording in full to stop the next session chasing it.

The suspicion: `docs/AGENT_ONBOARDING.md:43` warns that plain `.iso8601` truncates to whole
seconds and makes merge decisions unorderable, and that iOS therefore uses "a fractional-seconds
encoder with whole-second decode fallback. Don't change either direction." iOS does exactly
that — `KudosBackup.swift:169-179` builds two `ISO8601DateFormatter`s (one with
`.withFractionalSeconds`, one without); `:181-189` always *writes* the fractional one;
`:191-206` *reads* fractional first and falls back to whole-second, throwing
`DecodingError` if neither matches. Android, meanwhile, writes dates via
`BackupValidator.formatInstant`, which is a bare `instant.toString()`
(`backup/BackupValidator.kt:161`). `Instant.toString()` emits `DateTimeFormatter.ISO_INSTANT`,
whose fractional part is *variable width* — 0, 3, 6 or 9 digits depending on the value's
nanos. `ISO8601DateFormatter` accepts **exactly** 3 fractional digits or none. So a 6- or
9-digit fraction from Android would fail both iOS formatters and abort the entire import.

Why it does not happen: every `Instant` that reaches the manifest comes back out of Room,
and Room stores them through `data/local/converters/KudosTypeConverters.kt:13-21`, which is
`instantToEpochMillis` / `epochMillisToInstant` — `toEpochMilli()` / `Instant.ofEpochMilli()`.
Millisecond precision in, millisecond precision out. A milli-precision `Instant` renders as
either 0 fractional digits (nanos == 0) or exactly 3. iOS's whole-second fallback covers the
first, its fractional formatter covers the second. The round trip is sound in both
directions, and Android's parser (`BackupValidator.kt:145-155`) accepts iOS's always-fractional
form via `Instant.parse`, with an `OffsetDateTime.parse` second chance for offset-bearing
timestamps. **Verified compatible.** One residual is carved out as lead L-2 below.

---

## Not covered

**Of twenty-one areas: four closed, seventeen partial, none untouched.** "Closed" means the
area's central question was answered, not that every file was read — each ledger row names
what was deliberately left.

**Read closely** (findings rest on these): folder sync and backup on both sides
(`FolderSyncService.swift`, `KudosBackup.swift` manifest/encoder/merge regions;
`SyncRepository.kt`, `BackupManifest.kt`, `BackupVersion.kt`, `BackupJson.kt`,
`BackupValidator.kt`, `BackupMergeService.kt` merge core + `mergeWork`, `BackupMappers.kt`
export path, `BackupRepository.kt` apply path); the session/cookie stores and logout paths
(`AO3SessionVault.swift`, `AO3AuthService.logout`; `AO3SessionStore.kt`, `AO3CookieStore.kt`,
`AO3AuthRepository.kt`); the networking constants (`AO3Client.swift` pacing/retry,
`AO3RequestCoordinator.swift`; `AO3NetworkConfig.kt`, `AO3RetryPolicy.kt`, `AO3UserAgent.kt`);
the search parameter builders on both sides; the reader locator and settings paths
(`ReadiumReaderView.swift` open path, `ReadiumNavigatorContainer.swift` codec,
`ReaderStyle.swift`; `ReaderLocatorCodec.kt`, `ReaderRestoreTarget.kt`,
`ReaderSettingsMapper.kt`, `ReaderPreferences.kt`); the write endpoints and duplicate paths;
`HTMLWorkSanitizer.swift` against `HTMLWorkConverter.kt`; the schema diff
(`Models.swift` `SavedWork` against `WorkEntity.kt`, mechanically); `KudosDatabase.kt` +
`KudosDatabaseMigrations.kt`.

**Partial** — area 6 (write actions done, the Work Detail *screen* not), area 9 (position and
settings done; themes, TOC, in-reader search, annotations and TTS not), area 12 (list types
only), area 16 (backup payload only, not the Settings screens), area 20 (touch targets and
density only), area 21 (suite shape and one per-rule instance only).

**Thinnest coverage** (opened, but only one question each answered): area 1 (onboarding) has its gating verified but none of its copy; area 5 (browse) resolved only
the local-indicator question. Within better-covered areas, notable omissions: the
collection/queue/annotation merge bodies, ZIP container internals, PDF and plain-text
converters, the EPUB builder's output, text-encoding detection, the download queue, tag
autocomplete, the `SavedSearch` round trip, the comment model field set, Library shelf
predicates, and reader colour themes / TOC / annotations / TTS.

**Where a follow-up should start, highest value first:**
1. **The comment model field set** (area 7). Finding 13 showed this area's model layer is
   thinner on Android than its parser suggests; creator/moderator badges, edited state,
   deleted/hidden state and thread depth are all unchecked.
2. **Error handling and empty states** (area 19). The only area with no dedicated pass, and
   the one the review prompt singles out as diverging quietly and rarely being tested.
3. **Library shelf predicates** (area 10) — which work appears on which shelf. The statistics
   came through clean, but the shelf partition is a separate rule set and L-4 is open inside it.
4. **The two statistics/queue items still open as leads**: L-4 (`WorkImporter.saveMetadataOnly`
   still hard-coding `markSaved = true`) and L-5 (`hasEpub` never downgraded when the file is
   gone).

**A standing warning about the Android branch's own audit corpus.** `docs/audits/`
(`PARITY_SWEEP2_A`–`D`, `ANDROID_PARITY_REPORT.md`, `ANDROID_PARITY_FINDINGS_VERIFIED.md`,
`REMAINING_PARITY_AND_UI_GAPS.md`) and `docs/Android_Parity_Review_2026-08-04.md` cover much
of areas 1–13 and were **not** verified here beyond one spot-check. That spot-check found the
cluster substantially implemented while still listed as a confirmed-open major (finding 3),
and a sibling contract doc asserting behaviour the code does not perform (finding 1). Treat
that corpus as a lead list to re-verify against the trees, never as coverage already banked.

**Not run:** neither `Scripts/verify.sh` nor `android/Scripts/verify.sh`. No build, no test
suite, no simulator or emulator. Every claim here is static reading of source at
`e9ed0c6a` / `a5a46116`. Two items explicitly cannot be closed without running code: lead
L-2 (`Instant.now()` precision) and the rendered-height half of finding 11.

## Method log

Chronological record of what was actually done, so a cold reader can judge the
evidence rather than trust the conclusions.

### 2026-08-07 — scoping pass (no source files read yet)

- Confirmed both worktrees exist at the SHAs the prompt names (`git worktree list`):
  `hig-review-reference` @ `e9ed0c6a`, `android-exclusion-parity` @ `a5a46116`.
- Read `AGENTS.md`, `docs/AGENT_ONBOARDING.md`, `docs/ADVERSARIAL_REVIEW_TEMPLATE.md`
  in the `hig-review` tree.
- `TASKS.md` in `hig-review` is 530 lines / 450 KB (very long rows). Indexed rather
  than read linearly: `grep -oniE '(android|parity|deferred|not ported|port to)…'`
  shows Android/parity material concentrated in rows 24, 26, 30, 61, 64, 75, 78, 82,
  87, 93, 116, 241, 262, 382. Full-text search against `TASKS.md` is the required
  check before any finding is reported.
- Enumerated both source trees to build the area map above (`ls` per package).
- **Noted for the record:** the Android worktree carries its own, divergent `docs/`
  tree (`docs/audits/`, `docs/contracts/`, `docs/Android_Parity_Review_2026-08-04.md`,
  `docs/iOS_Issues_Found_While_Porting.md`) that the `hig-review` tree does not have,
  and `hig-review`'s `docs/reports/` does not exist on the Android branch. It also
  contains a **stale copy of the iOS app**: 92 Swift files under `kudos-ao3-reader/`
  versus 214 in `hig-review`. Anyone comparing "iOS" from inside the Android worktree
  is comparing against a much older iOS. Recorded as Open lead L-1.
- No source file has been read yet; no suite has been run. Nothing below is claimed
  as verified until it carries file:line evidence on both platforms.

### 2026-08-07/08 — attempted parallel review of areas 2–15, abandoned

Two `Workflow` runs were dispatched, seven area reviewers each (areas 2–8, then 9–15),
every finding pipelined into an adversarial refutation stage. **Both runs failed
completely.** All 14 reviewers terminated on a session usage limit; the run journals
(`…/workflows/wf_63152fd2-03e/journal.jsonl` and `wf_26c5bb5e-db9/journal.jsonl`) contain
zero `{"type":"result"}` lines, so nothing was recoverable — 1.29 M sub-agent tokens spent
for no output. Recorded because it is a real cost already paid and the next session should
not repeat the shape. Everything in this report was produced afterwards by direct inline
reading.

### 2026-08-07/08 — cross-check of the Android branch's audit corpus

Spot-checked one cluster (`isQueuedForLater` / queue-only) that
`docs/audits/ANDROID_PARITY_FINDINGS_VERIFIED.md:23,59` lists as a highest-priority
CONFIRMED-and-open major, and that `PARITY_SWEEP2_A:6,24` therefore excludes from
re-review. Found it substantially implemented at `a5a46116` → **finding 3**. Opened
L-3 (an `isSaved` merge-rule divergence noticed while reading the work-merge bodies) and
L-4 (the unchecked half of the same cluster). No other audit document was verified.

### 2026-08-07/08 — area 14 (backup / folder sync), partial

- Compared manifest versioning: iOS `KudosBackup.swift:224-225` (`currentVersion = 8`,
  `supportedVersions = [1…8]`) against Android `backup/BackupVersion.kt:22-25`
  (`CURRENT = 8`, `supported = 1..8`). They agree, and Android's file documents the Apple
  version history deliberately. No finding.
- Compared the manifest field set: iOS `KudosBackupManifest` (`KudosBackup.swift:220-250`)
  against Android `KudosBackupManifest` (`backup/BackupManifest.kt:9-27`). Same ten
  collections. Android's `BackupJson` (`backup/BackupJson.kt`) sets `ignoreUnknownKeys`
  and `explicitNulls = false`, and `BackupValidator` carries queues/annotations/tombstones
  through unchanged "so re-export doesn't drop anything" — i.e. the unknown-field
  preservation question the review prompt raises is handled deliberately. No finding.
- Chased the date-encoding hazard to a conclusion → **ruled out**, recorded as R-1, with
  the one residual carved out as lead L-2.
- Read both folder-sync write paths end to end → **findings 1 and 2**.
- Cross-referenced against the Android branch's own docs, which changed two conclusions:
  `docs/iOS_Issues_Found_While_Porting.md:69-96` already documents finding 2 on both
  platforms (so this review claims no credit for it — see the note under that finding),
  and `docs/contracts/BACKUP_FORMAT.md:83` + `docs/android/ANDROID_PORT_PLAN.md:1005`
  turned finding 1 from "an oversight" into "a specified requirement, asserted as complete
  in a contract doc, while the same codebase implements the pattern correctly elsewhere at
  `files/WorkFileStore.kt:24-39`".
- Compared the `SyncMerge` decision core in full, both null branches and both comparison
  strictnesses → **V-1**, verified identical. This is the result I expected least: the
  subsystem with the worst failure mode has the most faithful port.
- Corrections applied to this file after re-checking my own citations: three line numbers
  (iOS EPUB naming `:680` not `:681`; Android `:169` not `:170`; Android orphan pruning
  `:176`/`:193` not `:181-186`/`:193-197`), and one over-claimed grep — iOS *does* read
  modification dates in `FolderSyncService.swift` (`:741-748`, called from `:273`, `:338`,
  `:380`), just never on the per-asset skip path. The corrected form is what appears under
  finding 2's evidence.
