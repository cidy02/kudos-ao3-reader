# A92 result: Codex's Android batch 3ha against the iPhone (read only)

*Done, 2026-10-23.*
- The diff is `46a50158..1ea4377c` in `/Users/cidy02/kudos-agent-codex`: the WIP record commit holds the whole delivery, so the working tree is clean, plus `Brief3haContentTest.kt`.
- The lane's uncommitted diff is the same, line for line, and its copy of the new test file is identical.
- Read only: no builds, no Gradle, no git command that changes anything, no AO3. Android paths are under `android/app/src/main/java/io/github/cidy02/kudos/` (tests under `…/src/test/…`); iOS paths are under `kudos-ao3-reader/`.

**Verdict:** fit to land after the first two fixes below, each a line or two. It adds no AO3 read. I found no leftovers from the overlapping turns except one dead parameter (finding 1).

## Findings

### P3 — The edit-settings subtitle now always shows the slug, where iOS shows the collection's title

- **Android:** the subtitle is `slug + " · N sign-ups"` (`account/AO3ChallengeSettingsEditScreen.kt:134`). It was `title.ifEmpty { slug }`.
- **iOS:** the subtitle is `effectiveTitle`, which is `collectionTitle.isEmpty ? collectionSlug : collectionTitle` (`Features/Challenges/ChallengeSettingsEditView.swift:82-84`, `:177-178`). That is the rule Android had.
- **Why A88b looked different:** the iPhone shot read "winter_exchange · 4 sign-ups" only because its DEBUG push passes no title. That's demo data, not the design.
- **Failing case:** open Edit settings from a collection whose title is known. iOS reads "Winter Exchange 2026 · 4 sign-ups"; Android now reads "winter_exchange · 4 sign-ups".
- **Leftovers:**
  - The function's `title` parameter is now unused (`:36`), though callers still pass it.
  - The new test `AO3ChallengeSettingsEditScreenTest.slugSubtitleAndFilledSaveStayVisibleWhileScheduleScrolls` asserts `onNodeWithText("Winter Exchange 2026").assertDoesNotExist()`, which locks the regression in.
- **Fix:** restore `title.ifEmpty { slug }` and drop that assertion. The count logic beside it is right (see Checked).

### P3 — The recovery sheet is now grey in Light, where it matched the iPhone's white

- **Android:** the sheet's ground went from `tokens.cardFill` to `tokens.background` in every theme (`writing/WritingTextEditorScreen.kt`, `WritingRecoverySheet`, `presentSheet(tokens.background)`).
  - In Light, `background` is the grouped grey #F2F2F7 and `cardFill` is white (`ui/subject/KudosTokens.kt:145-147` and the Light values beside them).
- **iOS:** the recovery sheet takes the theme's base in Sepia, Dark and OLED. Light keeps the system sheet, which is white (I10, `Features/Writing/WritingTextEditor.swift`, recovery sheet). The A88b tile showed both apps white in Light.
- **Failing case:** open the recovery sheet in Light. The iPhone's is white, Android's is now light grey. The brief asked only for OLED.
- **Fix:** use `cardFill` in Light and `background` otherwise, as iOS does.
- `prefhelp` takes the same `tokens.background`; see the unconfirmed note below.

### P3 — Neutral cards reuse `mutedHistory`, the Library's abandoned-work style, which also greys their meta lines

- **What changed:**
  - Series works (`app/SeriesWorksScreen.kt:304-310`) and author bookmark cards (`author/AuthorProfileComponents.kt:236`) now pass `mutedHistory = true` to drop the fandom tint.
  - But `mutedHistory` was made for abandoned works in History (`library/LibraryScreen.kt:1066`). Besides removing the wash (`ui/components/SensitiveWorkRow.kt:225`), it recolours the fandom and date meta lines from `onSurfaceVariant` to `secondaryInk` (`:350`, `:365`, `:453`).
- **Effect:** the visible change is small (two greys), but these cards now carry the muted-history styling under a name that says so. The next change to how abandoned works look would silently restyle series and bookmark cards.
- **Fix:** a separate `neutralGround` flag that only skips the wash, or rename the flag and keep the recolour for abandoned works only.

### P3 — Tests that would still pass with their change reverted

1. **`Brief3haContentTest.preferenceHelpPassesTheKudosGroundToItsSheetInEveryTheme` (`:160`) and `recoveryPassesTheKudosGroundToItsSheetAndRestoreKeepsWorking` (`:178`).**
   - Both replace `presentSheet` with their own `Surface` and check the ground it receives.
   - The production presenters (`account/AO3PreferencesScreen.kt:475-477`, and the default in `WritingRecoverySheet`) aren't exercised. Removing `containerColor = ground` from either keeps both green, and that's exactly the bug the item fixed (Material's default surface).
   - Acceptable as a seam, given Robolectric and dialog windows, but count it as weak.
2. **`AO3ChallengeSettingsEditScreenTest.knownSignUpTotalUsesTheSlugAndPlural`.**
   - It passes `knownTotal = 4` but asserts "… · 0 sign-ups". That figure is the edit page's own single-page count, which wins over the known total (`data?.signUpTotal ?: knownSignUpTotal`).
   - The known total isn't tested here, so ignoring `knownSignUpTotal` entirely keeps it green.
   - `paginatedEditorKeepsTheTotalAlreadyReadByTheChallengePageWithoutAnotherRead` does test the known total, and it also checks that the read count is unchanged. That one is good.
3. **`slugSubtitleAndFilledSaveStayVisibleWhileScheduleScrolls`:** as in finding 1, it asserts the wrong rule. Its pinned-Save and filled-accent checks are good.

The rest read as sensitive to their change:
- the series repository test (Restricted only from the heading image; only missing counters become zero);
- `directSeriesReads…`, `seriesSelection…`, `blankKicker…`, `collectionName…`, `bookmarksHaveASectionHeading…`, `privacyRegistersTheAccountWash…`;
- the work-form `chapterform` shot test;
- `editReceivesTheAlreadyReadTotalAndTheShotWaitsForIt`.

None was run here.

### Unconfirmed

- **Restricted from the series page's heading.** `AO3SeriesRepository` now reads Restricted from an image inside the page's `h2.heading` (`network/ao3/series/AO3SeriesRepository.kt:109-112`). The demo fixture was edited to carry one (`src/debug/assets/fixtures/ao3_demo_dawn_series.html:3`).
  - iOS reads the lock from the series *listing's* `h4.heading img`, with the same three tests: `lockblue`, title "Restricted", alt contains "restricted" (`Services/AO3Client+Authors.swift:222-232`). iOS's series page takes the card from the listing it was opened from.
  - Whether AO3's own series *show* page draws the lock in its `h2` I can't check here (no AO3).
  - If it doesn't, a directly opened restricted series shows no Restricted on Android. That's no false claim, and the same as before.
  - The listing-carried flag is still honoured (`app/SeriesWorksScreen.kt:326`, `detail.isRestricted || seed restricted`).
- **`prefhelp` in Light:** now `tokens.background` (#F2F2F7) rather than Material's lavender. That's closer, but the iPhone's help sheet in Light looked white in the A88b tile. Check on the re-shoot; if it's white, the same rule as the recovery fix applies.

## Checked and fine

- **No new or repeated AO3 read:**
  - **Series:** the change only parses the page Android already fetches, with no new request. Reads stay as a guest, as A90 settled. The parse adds:
    - the Restricted heading image (`AO3SeriesRepository.kt:109-112`);
    - zero for absent comment, kudos, bookmark and hit counters (`:126-131`), which is how AO3 omits a zero;
    - `bookmarkCount` and `dateUpdated`, which were already parsed (`:107-108`). The direct-open card lacked them only because the demo fixture had neither.
  - **The sign-up count (owner decision 16):**
    - The count comes from Challenge Settings' existing read, which has fetched the first and, when there's more than one, the last sign-ups page since 3ba (`account/AO3CollectionDetailRepository.kt:178-193`).
    - It is handed to the edit screen (`app/AppNavHost.kt:806-814`, `account/AO3ChallengeSettingsScreen.kt:66`, `:121`).
    - The edit page's own read is unchanged (one sign-ups page, a count only when that's the only page, `:144-147`).
    - The handed count is reset with the session (`remember(settingsGeneration)`), and the DEBUG shot now waits for it (`AO3ChallengeSettingsScreen.kt:65-67`).
- **Overlapping turns:**
  - `DebugShotEffect("challenge-settings")` moved from `AppNavHost` into the settings screen, not duplicated.
  - `WritingRecoverySheet` is a straight extraction: the same content, only the ground parameterised.
  - No doubled `SectionRuleHeader`, wash or Add path.
  - The one leftover is the dead `title` parameter (finding 1).
- **Lost behaviour:**
  - The pinned Save keeps "Saving…" as its label, so the separate progress row it replaces loses nothing (`AO3ChallengeSettingsEditScreen.kt:306-313`). It sits below the `LazyColumn`, so it stays pinned, as iOS's does.
  - Assignments sent is still there.
  - `seriesremove`'s words-and-date line, privacy's Imported fonts row and recovery's second paragraph are untouched, as the brief said.
- **Parity:**
  - The series page is unwashed, as iOS's plain list. The selection rows now also get `expandAll`.
  - Bulk names: one field with Add beside it (`writing/WritingBulkEditScreen.kt:241-252`); the same trim and de-duplication.
  - Author bookmarks: a "Bookmarks" section header and a card Load More (`author/AuthorProfileScreen.kt:1039`, `:1067`). `showsCard` already existed.
  - Availability: an empty kicker now draws neither label nor rule (`ui/subject/SubjectComponents.kt:341`). That's the only `kicker = ""` caller.
  - Privacy gets the Account wash (`settings/PrivacyDataScreen.kt:88`).
- **The `chapterform` shot** now opens Add chapter from the posted work's form (`app/DebugShots.kt:75`, `writing/WritingWorkFormScreen.kt:114`), the same call as the form's own Add chapter row (`:330`). DEBUG only.

**P1 0 / P2 0 / P3 4 / unconfirmed 2**

---

## Triage (Claude, 2026-10-23)

All four P3s acted on before 3ha landed: the challenge settings' subtitle is `title.ifEmpty { slug }` again
(iOS `effectiveTitle`), with its tests fixed (the title shows; a new test that a known total fills in when the
edit page has none); recovery and preference help take a new `sheetGround` token (card fill in Light, as
iOS's white sheet; the page's ground elsewhere); series works and author bookmarks use a new `neutralCard`
flag (no wash, meta unchanged), so `mutedHistory` is again only for abandoned works. Left as leads: the
two sheet-ground tests replace the presenter (they check the colour chosen, not that production passes it),
and whether AO3's real series page draws the lock in its h2 (if not, a directly opened series shows no
Restricted, as before).
