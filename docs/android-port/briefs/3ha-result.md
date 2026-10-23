# Brief 3ha — combined Android implementation and finish review

Reviewed the complete tracked `git diff` and untracked
`android/app/src/test/java/io/github/cidy02/kudos/app/Brief3haContentTest.kt`
against all eight items in `3ha-a88b-android.md` and the finish instructions.
All eight have implementation and regression-test coverage in this worktree.
This is a source-review handoff, **not a build, test, mutation or visual pass**.

Worktree: `/Users/cidy02/kudos-agent-codex`; branch:
`android/agent-codex-3ha`. Nothing committed or pushed. No Gradle, branch changes,
sign-in, AO3 contact or `TASKS.md` edits were performed during this finish pass.

## 1. Direct series detail

- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/series/AO3SeriesRepository.kt:109`:
  parse the series heading's Restricted/lock image from the response already being
  parsed. The selector excludes work headings, so a restricted work does not label
  its whole series Restricted. The display-only detail model carries the flag at
  `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/series/AO3SeriesRepository.kt:152`.
- `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:326`:
  carry that flag into the existing series summary card, preserving incoming
  navigation facts as fallback. Bookmark count and updated-date parsing/card
  rendering already existed; the direct DEBUG fixture was missing those facts.
- `android/app/src/debug/assets/fixtures/ao3_demo_dawn_series.html:3`,
  `android/app/src/debug/assets/fixtures/ao3_demo_dawn_series.html:6` and
  `android/app/src/debug/assets/fixtures/ao3_demo_dawn_series.html:7`:
  supply the heading lock, 08 Jul 2026 and 62 bookmarks, matching the author-list
  demo summary. These are fixture facts, not hardcoded production values.
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/series/AO3SeriesRepository.kt:128`:
  normalize only absent full-blurb comments/kudos/bookmarks/hits to zero on series
  pages. Supplied nonzero counts survive; the shared search parser is unchanged.
  The existing show-zero preference still controls display.
- `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:216`:
  replace the page wash with the Kudos background.
  `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:304`
  applies the existing neutral work-card treatment in both browsing and selection.
  `android/app/src/main/java/io/github/cidy02/kudos/ui/components/RemoteWorkSelection.kt:313`
  and `android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:719`,
  `android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:750`
  forward that treatment through selection, local-match and remote branches.
  Other callers default to their existing treatment.

Reference read: iOS `Features/Authors/AO3SeriesDetailView.swift:56` draws the summary
in a neutral card; `:166` retains the incoming summary; its work rows use
`.cardRow()`. Android's direct opening therefore needs its existing response's
facts, whereas an author-list opening can also reuse its incoming facts.

**Read policy:** no fetch, pagination, authentication, cache or request-count code
was changed. `AO3SeriesRepository.kt:52` (`seriesPage`) and the bulk
`seriesWorks` loop still use the guest client. For precision, the pre-existing
single-page `detailPage` implementation at `:64` already has a conditional
authenticated fetch at `:69`; that branch and its existing test were left
untouched. This patch does not make guest listing/bulk reads authenticated and
adds no request. There is no blanket claim that every existing detail read is
anonymous.

## 2. Challenge settings edit

- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditScreen.kt:134`:
  subtitle is the slug, followed by the known total with singular/plural sign-up
  wording. Unknown remains slug-only, per owner decision 16. A total read by the
  editor wins over a carried total.
- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsScreen.kt:65`:
  the DEBUG edit opening waits for the Challenge page's existing load, then passes
  its already-read total through the same callback as the ordinary Edit row.
  `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:796`,
  `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:807` and
  `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:814`
  carry it into the editor and clear the carried value on session-generation
  changes. The old eager DEBUG dispatch was removed from AppNavHost, so there is
  one dispatcher.
- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditScreen.kt:306`:
  replace the plain action row in the existing pinned bottom area with a
  full-width filled button, using scope accent and label-on-accent colours.
  Existing save admission/validation remains in force.
- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditScreen.kt:174`:
  keep Assignments sent and its Manual fallback. iOS
  `Features/Challenges/ChallengeSettingsEditView.swift:330` explicitly includes
  that read-only row; removal would diverge.

No extra sign-up-total read was added. The debug flow now visits the same
preceding Challenge load as normal navigation rather than opening the editor
before that existing data is available.

## 3. Bulk collection names

`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingBulkEditScreen.kt:241`
puts the field and Add in one panel row.
`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingBulkEditScreen.kt:245`
uses the existing field-only mode: one visible Collection name placeholder,
with the spoken field label retained. Add still trims, rejects blank input,
suppresses duplicates and clears the entry. Its previous separate row is removed.
Reference: iOS `Features/Writing/BulkTagStatePicker.swift:179`.

## 4. Author bookmarks

`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:236`
makes bookmark work cards neutral via the same shared forwarding as item 1,
including local matches.
`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:1039`
adds the Bookmarks section heading.
`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:1067`
uses the existing card-style Load More/retry presentation; page callbacks are
unchanged. Reference: iOS
`Features/Authors/AuthorProfileContentSections.swift:666` (Bookmarks section)
and `:683` (neutral bookmark card).

## 5. Preference-help and recovery sheet ground

- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:479`:
  preference help passes Kudos background to its sheet host;
  `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:476`
  uses it as Material's containerColor.
- `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt:250`:
  the recovery branch uses the extracted recovery sheet.
  `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt:268`
  passes background instead of cardFill;
  `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt:262`
  forwards it to containerColor. Recovery selection, conditional paragraph,
  copy/restore/keep/delete actions, scrolling, dismissal lock and scrim are
  preserved.

Both wrappers accept a composable sheet host so tests can exercise their chosen
colour and real content in the activity, with no modal/dialog window, as required
by the brief. The actual default Material host wiring remains a source-reviewed
and emulator-verification boundary; injected hosts do not test Material itself.

## 6. Availability orphan rule

`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectComponents.kt:341`
omits the whole kicker when blank, including its rule and the space it occupied.
`android/app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt:103`
is the only production caller with a blank kicker. No second header/rule fix was
added in Availability itself.

## 7. Privacy Account wash

`android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:88`
passes the Account scope palette into the existing SettingsPage wash.
Reference: iOS `Features/Account/PrivacyDataView.swift:117`.
Imported fonts and all storage/clear/session behavior are retained.

## 8. Chapter-form DEBUG route

`android/app/src/main/java/io/github/cidy02/kudos/app/DebugShots.kt:75`
opens the posted work with the work-form dispatch page.
`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:114`
opens its new-chapter model with a null chapter ID, just like the existing manual
Add chapter action at `:330`. This reaches Add chapter 3 of posted demo work
995006 rather than Edit chapter 1 of the draft.
Reference: iOS `App/DemoLibrary.swift:319`, posted work → chapterform.
The Android demo's title remains its own fixture title.

## Combined-turn cleanup and finish edits

- No duplicate production blocks remained after reviewing the combined diff.
  The one challenge DEBUG dispatcher is now on the loaded content screen.
- Removed the new, redundant `DebugShotsTest.chapterFormOpensAddForThePostedWork`.
  `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingWorkFormScreenTest.kt:147`
  now asserts the complete DebugShot (route **and** dispatch pages) before testing
  the actual Add chapter screen. `DebugShotsTest.kt` has no remaining diff.
- `android/app/src/test/java/io/github/cidy02/kudos/app/Brief3haContentTest.kt:156`
  checks EditableText for the cleared input, avoiding an empty-string assertion
  that could also see the restored placeholder.
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/series/AO3SeriesRepositoryTest.kt:122`
  supplies a real 17-kudos value alongside missing figures, guarding against
  overwriting real counters while filling absent ones.
- `android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditScreenTest.kt:91`
  now covers carried singular 1 sign-up; `:97` covers loaded zero/plural and its
  precedence over a carried 4.

## Tests and reversion expectations

There are **14 new tests and one strengthened existing test**. The following
outcomes are expectations from source review, **not executed mutation results**.
Paths below are relative to
`android/app/src/test/java/io/github/cidy02/kudos/`.

| Test (path:line) | What it exercises | With the relevant change reverted |
| --- | --- | --- |
| `app/Brief3haContentTest.kt:85` — `directSeriesReadsItsOwnFactsAndKeepsZeroFiguresOnNeutralGround` | Direct unseeded screen: bookmarks, lock, date, four zero figures; plain page/neutral card pixels in Light, Sepia, Dark, OLED; one fake read. | Missing fixture fact/flag propagation fails the corresponding label assertion; reverting absent-counter normalization fails zero descriptions; restoring page/card tint fails wash/pixel checks. |
| `app/Brief3haContentTest.kt:112` — `seriesSelectionAlsoUsesNeutralCardsAndStillToggles` | Production selection row's neutral paint and tap callback. | Reverting neutral forwarding in the selection row fails its card pixel. A broken toggle fails selected-state assertion. |
| `network/ao3/series/AO3SeriesRepositoryTest.kt:85` — `theSeriesOwnFactsComeFromItsPageWithOrWithoutClassesOnItsFigures` (strengthened existing test) | Fixture bookmark/date/heading lock and zero figures; existing classless labelled-metadata case. | Reverting fixture facts, restriction parsing or zero defaults fails the corresponding expected value. This is the positive lock-parsing test. |
| `network/ao3/series/AO3SeriesRepositoryTest.kt:117` — `seriesRestrictionComesOnlyFromItsHeadingAndOnlyMissingCountersBecomeZero` | Unlocked series with a locked work; missing comments/bookmarks/hits become zero, real 17 kudos survives; one fake read. | Reverting zero defaults fails null-versus-zero assertions. An overbroad lock selector fails the false-series-lock assertion. Reverting only lock parsing to always false would pass this negative case; the preceding positive test catches that. |
| `account/AO3ChallengeSettingsEditScreenTest.kt:66` — `slugSubtitleAndFilledSaveStayVisibleWhileScheduleScrolls` | At 2× text: slug-only unknown count, painted filled Save, fixed Save position while scrolling, Assignments sent/Manual and edited-instructions save through a fake. | Restoring title subtitle fails slug lookup; restoring plain Save fails fill assertion; moving Save into scroll content fails fixed/displayed checks. Removing Assignments sent fails its lookup. |
| `account/AO3ChallengeSettingsEditScreenTest.kt:91` — `paginatedEditorKeepsTheTotalAlreadyReadByTheChallengePageWithoutAnotherRead` | Paginated editor carries 1 sign-up; exact unchanged opening-read list. | Dropping carried-total fallback or using plural for 1 fails exact subtitle; adding a count read fails request-list equality. |
| `account/AO3ChallengeSettingsEditScreenTest.kt:97` — `knownSignUpTotalUsesTheSlugAndPlural` | Loaded 0 sign-ups wins over carried 4; slug and plural wording. | Restoring title-based subtitle, omitting known zero or preferring carried 4 fails exact text. |
| `account/AO3ChallengeSettingsScreenTest.kt:80` — `editReceivesTheAlreadyReadTotalAndTheShotWaitsForIt` | Held Challenge read: no eager DEBUG edit, then loaded total 4; normal Edit also receives 4; four existing reads only. | Removing content dispatch times out; eager dispatch fails early-edit assertion; dropping loaded total fails count assertion. |
| `app/Brief3haContentTest.kt:135` — `collectionNameHasOneLabelBesideAddAndAddsOnlyOneTrimmedName` | At 1× and 2×: one visible placeholder, field/Add same row, blank disabled, trims Winter, suppresses repeat addition, clears EditableText. | Restoring labelled field fails label count; restoring separate Add row fails row geometry. Losing trimming/dedup/clear behavior fails state assertions. |
| `author/AuthorProfileSortScreenTest.kt:109` — `bookmarksHaveASectionHeadingAndCardLoadMoreThatStillLoadsTheNextPage` | Actual Bookmarks tab: section heading before work, neutral work/card Load More pixels in four themes; next page fetched once. | Removing heading fails lookup; restoring fandom tint/bare Load More fails respective pixel checks; broken pagination fails page/read assertions. |
| `app/Brief3haContentTest.kt:160` — `preferenceHelpPassesTheKudosGroundToItsSheetInEveryTheme` | Actual preference-help wrapper with activity host: chosen background, painted ground and actual instructions/footer in four themes. | Changing the passed ground back to Material surface/cardFill fails colour assertions in differing themes. Reverting only default Material-host containerColor wiring is not caught by this host-substituted test; that line is source-reviewed and remains an emulator check. |
| `app/Brief3haContentTest.kt:178` — `recoveryPassesTheKudosGroundToItsSheetAndRestoreKeepsWorking` | Actual recovery wrapper with activity host: background/paint in four themes, recovery text and restore into editor. | Restoring passed cardFill fails OLED colour; losing content/Restore fails text/state checks. Default Material-host wiring has the same explicit test boundary as preference help. |
| `app/Brief3haContentTest.kt:128` — `blankKickerHasNeitherAnEmptyLabelNorAnOrphanRule` | Blank-kicker header starts at its title, with no reserved kicker/rule space. | Restoring unconditional kicker moves title below header top and fails geometry. |
| `settings/PrivacyDataScreenTest.kt:132` — `privacyRegistersTheAccountWashInEveryTheme` | Actual Privacy screen registers exact Account palette in all four themes. | Removing washPalette leaves no registered page wash and fails equality. It tests wash registration, not a screenshot of the shell gradient. |
| `writing/WritingWorkFormScreenTest.kt:142` — `chapterFormShotDispatchesToAddChapterOfThePostedWork` | Complete DEBUG route/pages, production work-form dispatch, Add chapter 3, exact edit/new-chapter fake reads, zero posts. | Restoring draft route or dropping dispatch pages fails DebugShot equality; removing chapterform handling times out; opening edit/draft chapter fails title/subtitle/read assertions. |

Local-match neutral forwarding is source-reviewed; the new paint tests render
remote rows, not a populated local-library match. Session-generation clearing of
the carried count is source-reviewed at AppNavHost; the new screen tests exercise
the count handoff callbacks, not a complete NavHost session replacement.

## Verification, retained scope and handoff

- `git diff --check` passed after the finish edits.
- Reviewed each changed production caller, fixture and test; checked referenced
  iOS series/challenge/bookmarks/bulk/help/recovery/privacy/debug code.
- Kept guest series listing/bulk reads and existing detail request/cache selection
  unchanged. No extra request for series facts or sign-up count.
- Intentionally retained Assignments sent (present on iOS), series-remove
  words/date subtitles, Imported fonts, and recovery's conditional second
  paragraph (explicit brief decisions).
- No other A88b findings were folded in: text-editor toolbar, other collection
  screens and capture/ANR issues are outside these eight items.
- No Gradle/build/runtime test or mutation runs, emulator screenshots, sign-in,
  live AO3 verification, commits, pushes, branch changes or TASKS.md edits:
  expressly excluded by this brief. No visual-correctness claim.
- Sheet tests use activity content hosts rather than dialog windows, as requested.
  Real modal surfaces, gestures, keyboard paths, local-match card paint, count
  reset across session replacement and human visual approval remain unverified.

Claude's next step: build and run `Brief3haContentTest`,
`AO3SeriesRepositoryParseTest`, `AO3ChallengeSettingsEditScreenTest`,
`AO3ChallengeSettingsScreenTest`, `AuthorProfileSortScreenTest`,
`PrivacyDataScreenTest` and `WritingWorkFormScreenTest`, then adjacent
3gx/3gy/3gz, series-editing, bulk-edit and text-editor suites. Execute the relevant
reversions above and capture the eight affected flows in Light, Dark, Sepia, OLED
and 2× text, including real modal hosts. Pixel coordinates, large-text geometry
and DEBUG lifecycle waits still need their first runtime pass. All work remains
uncommitted in this worktree for that handoff.
