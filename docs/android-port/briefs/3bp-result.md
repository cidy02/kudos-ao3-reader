# Brief 3bp result: Reading History grouping and undo

## What iOS has (read from the reference code)

`LibraryHistoryGrouping.swift`, `LibrarySectionListView.swift`, `ReadingHistoryFactsStrip.swift`, `ReadingLogService.swift`, `WorkLifecycle.swift`, and `Models.swift` in `/Users/cidy02/kudos-ios-polish/` are the reference, read only.

The scope strip is **Time, State, Fandom, Flat**, in that order. Time is the default. `@AppStorage("library.history.grouping")` stores the choice per device; it is not a backup setting. Only History shows it. Other section kinds share neither the grouping nor the Abandoned presentation/button; Favorites has its separate quick filters.

Time bucket titles and fixed order: **"Today", "Yesterday", "This week", "This month", "Earlier", "Never opened"**. First matching rule wins: same calendar day as supplied now; same day as `calendar.startOfDay(for: now) - 60` (the day immediately before today's midnight); same calendar week as now; same calendar month as now; any other date; nil date. These are calendar boundaries, not rolling 24-hour/7-day/30-day windows. Empty buckets disappear; incoming row order is preserved within each bucket.

State titles and fixed order: **"In progress", "Abandoned", "Read, not finished", "Finished", "Not started"**. Finished wins even without a file. Otherwise no EPUB means Read, not finished; an EPUB never started means Not started; a started, unfinished EPUB is Abandoned if the derived rule holds, otherwise In progress. There are five because the four-way reading-state partition splits In progress into active and abandoned. This is where iOS wins over the artboard's three-state simplification.

Fandom uses the **first nonempty fandom**, reduced by `FandomDisplayName.bareTitle` to its family (e.g. Doctor Who and Doctor Who (2005) share a bucket); missing fandom is **"No fandom"**. Buckets rank by descending work count, then alphabetically. Flat is one **"All"** bucket. Empty input returns no buckets for every grouping.

Tally wording: Time and Flat **"6 works · most recently read first"** (singular **"1 work · most recently read first"**); Fandom **"6 works"**; State **"5 works · 2 in progress · 1 abandoned"**. State appends only nonzero In progress and Abandoned counts. With filters hiding every item, the existing collision tally remains **"N works · none match the current filters"**.

Only in State grouping, an Abandoned row has a muted ledger kicker and no fandom cover hue (nil hue, plain grey card surface). Its existing content/actions remain. It is abandoned exactly when: no `keepInProgressOverride`; EPUB present; reading started (`lastReadDate` present, nonempty locator, positive spine index, or positive scroll fraction); not finished; reading progress strictly greater than 0.05 and strictly less than 0.95 (nil counts as zero); last-read date present; elapsed time strictly greater than **21 × 24 × 3600 seconds**. Exactly 21 days, 5%, and 95% do not qualify.

Outside selection mode its button says **"Move back to In progress"**, with the backward U-turn glyph. It writes only the existing `keepInProgressOverride = true`, marks the work modified, and saves. The row immediately moves to In progress and the threshold cannot abandon it again, even a year later. Under Time/Fandom/Flat the same work has ordinary styling and no undo button. iOS's selection row has no undo button.

## Android implementation

- Kept the inherited untracked `LibraryHistoryGrouping.kt` enum titles/order/default, bucket identifiers, state precedence, first-nonempty fandom family/ranking, dropped-empty buckets, preserved incoming row order, tally wording, and the exact abandonment guards/21-day threshold after comparing every line to Swift. Changed Yesterday from `today.minusDays(1)` to the calendar day at one minute before today's local midnight: this also matches iOS in a zone that skipped a civil day. Tests include DST and Pacific/Apia's skipped day.
- History alone draws the shared `SubjectSegmentedControl`; at accessibility font scales it uses the same vertical panel of radio choices as the prompt meme. No fixed-height text, all new labels have line heights. The shared strip/header/subtitle labels now also specify line heights.
- Visible, already sorted rows become lazy keyed sections with `SectionRuleHeader` counts and the existing `LibrarySubjectLedgerRow`. The header subtitle uses the grouping tally; the existing filter collision wording stays. Other section kinds retain their header and quick filters.
- State's abandoned row opts out of the fandom card wash and uses secondary-ink fandom metadata. The local undo has the iOS words/U-turn glyph and the list's token panel/contrast-safe palette accent. It is hidden while selecting, as in iOS, and remains outside the privacy blur as iOS draws it.
- `WorkRepository.keepInProgress` reads the existing row and writes the override plus `lastModifiedAt = clock()` inside one Room transaction, through the same `upsert` path used by Mark as Finished. EPUB, progress, last-read date, and memberships stay intact. This invokes no importer, download queue, metadata read, or network client.
- `SettingsRepository.historyGrouping` stores `library.history.grouping` outside `KudosSettings`; defaults/unknown values resolve to Time. `LibraryViewModel` includes its flow in collected `LibraryUiState`, so a change redraws. Existing backup restore leaves the device-local key alone.

The 3u/3u-fix/3u-fix2 landing notes were read at `409c4d2f`, `ed4568bf`, and `33b6a23c`. The missing standalone 3u-fix result is covered by its landing note, including the rejected backup setting change. No such backup change is introduced here. No Gradle/Xcode invocation, sign-in, AO3 request, commit, push, branch switch, TASKS edit, backup format change, or Room schema change was made.

## Decided without asking

- Keep the existing Kotlin file/type names and use Java time ZoneId and WeekFields as the explicit calendar inputs.
- Port rule tests with the Swift suite and test method names; use existing lifecycle, settings, and demo test locations; exercise BackupMappers in the lifecycle regression.
- Preserve demo work/queue/collection counts by enriching existing demo rows rather than adding rows. Ashfall is yesterday, Winter Garden is 30 days old (Abandoned), and the existing off-device Static on Channel Nine is 60 days old (Read, not finished). Sodium Lights remains Today. Static is already queue-only, so the main shelves and reading-insights denominator do not gain a work. Installed demos upgrade only untouched original fixture dates/progress with no override or Readium locator, preserving later user reads/finishes/undo; that upgrade bumps both merge clocks. Reseeding does not move the dates again.
- Use the shared scope control at regular text size and the prompt meme's vertical radio panel at accessibility size, avoiding compressed/clipped labels.
- Keep the existing standard work row's palette everywhere except State's Abandoned card. Use the scope palette accent for action text, per the owner's later rule.

## Open questions

- None requiring owner input. Verification remains Claude's build/test and visual handoff.

## Checks and test handoff (not run yet)

`git diff --check` passes; the three new files and this result pass a whitespace/conflict-marker scan. All 12 Swift grouping test names are present in the Android suite. Existing whitespace in untouched lines was left alone. Symbol/signature checks used the real repositories, model reading-progress rules, DAO/flow path, existing UI parts, Compose test patterns, and BackupMappers. No build or test suite has been run: Gradle and Xcode are prohibited by the brief.

Added `LibraryHistoryGroupingTests` with all 12 Swift test method names, plus family/source-order, all-five-state, calendar boundary/DST/skipped-day, and abandonment endpoint/missing-field cases. Ported `ReadingLogTests.abandonedIsDerivedAndOverrideSticks` by name. Added `WorkLifecycleRepositoryTest.moveBackToInProgressStoresTheOverrideAndRebuckets` for the transaction's observed emission, merge clock, unchanged progress, persistent rebucketing and the real BackupMappers JSON export/import. Settings tests assert every persisted grouping, unknown fallback, exact unchanged backup-settings JSON, and survival through restore. Demo tests assert Today/Yesterday/Earlier, Abandoned/Read, not finished, unchanged total count, idempotence, installed-fixture upgrade and protection of later reads/undo.

`LibraryHistoryScreenTest` uses native graphics, a tall window, patient waits, actual LibraryScreen/ViewModel/Room/SettingsRepository and the supplied shell toolbar. It covers the four tallies, live undo and zero-count omission, every other section's absent strip, grouped long press → Select → grouping change → hidden-row selection pruning → Select All/Done, History's Remove swipe, and Light/Dark/Sepia/OLED at 2.4× font scale with non-ellipsized strip/tally/section/action label-height assertions. These claims require Claude's test run. Theme correctness/visual layout still requires seeing the actual emulator screens.

### Interaction check details

- Selection: traced the unchanged `LibrarySelection.visible` effect against the complete visible ID set, not one bucket; all row selection callbacks and the bulk action bar stay in place. Stable work keys survive a move between groups. The UI regression checks selection retained across grouping and removed when another section hides a selected row.
- Swipes: each grouped row still calls `LibrarySubjectLedgerRow` → the unchanged `leadingSwipeActions`/`trailingSwipeActions` → `SwipeActionRow`; History still uses its existing Remove-from-history callback rather than deleting the work. The UI regression reveals that Remove action and checks that a reveal does not delete.
- Long press: the existing row's `onLongClick`, `menuOpen` keyed by work ID, and `LibraryWorkMenu` are retained. The UI regression opens the menu on the Abandoned row and enters Select through it.
- Toolbar: the same `ProvidePushedShellChrome` supplies Filter/More, selection Select All/Deselect All and Done, and the same bulk bar remains. The UI regression draws the supplied shell row and exercises Select All/Done (the toolbar Done is matched by ancestor because the bulk bar also has Done). Action text uses `scopePalette.accent`.

All four were checked by source tracing and callback/string diff against HEAD. UI regressions are written, not executed; no visual correctness is claimed.

### Claude's remaining gate

Run Android debug compilation and the unit suite (`:app:assembleDebug`, `:app:testDebugUnitTest`), including `LibraryHistoryGroupingTests`, `LibraryHistoryScreenTest`, `WorkLifecycleRepositoryTest`, `SettingsRepositoryTest`, `DemoLibraryTest`, and existing LibraryQuery/section/quick-filter/selection and backup regressions. All compilation, repository emission timing, Compose interaction/accessibility assertions, backup round-trip assertions, and unchanged demo shelf counts need that run. Then inspect History Time/State/Fandom/Flat on the emulator in Light/Dark/Sepia/OLED and at accessibility scale; also check grouped swipe/menu/select/bulk actions and the pushed top row. Changes remain uncommitted on `android/agent-gemini-3bp` for that gate.

## Landing note (Claude, 2026-10-08)

Landed on `android/redesign-parity`. The grouping rules file was written by agy's Sonnet
before its quota ended and checked line by line by Codex, who wrote the rest.

Changed on landing:

- **The line heights added to shared components were left out** (`SubjectComponents.kt`,
  `SubjectSegmentedControl.kt`): they change every screen that uses them, and the rule from
  earlier landings stands.
- `SensitiveWorkRow.kt` was merged by hand over the audit A18 fix that landed the same hour.
- Three test faults: `WorkLifecycleTest` lacked the imports for the backup mappers; its
  sample work had no file, so it was never "in progress"; and it waited on Room's
  invalidation under the test's virtual clock, which times out at once. It now reads the
  list after the write.
- `LibraryHistoryScreenTest` failed at random: its last tap's write to the settings file was
  still on its way when the clean-up deleted the folder. The clean-up now queues a write
  behind it first.

Seen on the emulator (demo, reseeded): Time ("TODAY 2", "THIS WEEK 1"), State ("11 works ·
6 in progress · 1 abandoned", the muted Winter Garden row and its button; a tap moves it to
In progress and the tally becomes "7 in progress"), Fandom, Flat ("ALL 11"); the choice
survives a relaunch; at double text size in Light the strip becomes a panel of four rows and
nothing is clipped. Not seen: Sepia and OLED, and selection across a grouping change (the
screen test covers it). An installed demo keeps its old rows: clear the app's data to see
the Abandoned work.
