# Brief 3ha (Android): what the re-review of the second 36 screens still found (A88b)

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3ha`, from
the lane's landing of 3gy and 3gz). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Write
`docs/android-port/briefs/3ha-result.md` first; per item `path:line`, what changed, and per test what it
does with its change reverted. iOS is the reference (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`).
Reviews: `/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A88b-result.md` (Gemini) and
`/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A88b-cli-result.md` (Claude-CLI); tiles in
`/Users/cidy02/kudos-tools/pairs/tiles-a88/<name>.png`. Avoid dialog windows in Robolectric tests (test the
content composable, as 3gy did).

1. `seriesdetail` opened directly (the series page, `app/SeriesWorksScreen.kt` and the card in
   `author/AuthorProfileComponents.kt`): the iPhone's card shows the bookmark count, Restricted and the
   updated date, its work cards keep their zero figures, and its page is not tinted; Android's card lacks
   those three, its work cards drop zero figures, and the page and cards take a green tint. Read how iOS
   gets each (`Features/Authors/AO3SeriesDetailView.swift`) and match, without new AO3 reads.
2. `chsettingsedit` (`account/AO3ChallengeSettingsEditScreen.kt`): iOS's subtitle is "<slug> · N sign-ups"
   (Android shows the title only); iOS's Save changes is a pinned filled button (Android a left-aligned
   row); and check Android's "Assignments sent" row against iOS (keep it only if iOS has it, or if
   DECISIONS.md keeps it).
3. `bulknames` (`writing/WritingBulkEditScreen.kt`): "Collection name" shows twice and Add sits on its own
   row; iOS has one "Collection name … Add" row.
4. `authorbookmarks` (the author page's Bookmarks tab): iOS's bookmark cards are neutral (Android tints them
   by fandom), iOS has a "Bookmarks" section header, and its Load More is a card row (Android plain text).
5. Sheets that fall back to Material's default surface (lavender in Light, grey in OLED): `prefhelp`
   (`account/AO3PreferencesScreen.kt`) and `recovery` in OLED (`writing/WritingTextEditorScreen.kt`).
   Use the Kudos background, as the app's other sheets do (`containerColor = tokens.background`).
6. `availability` (`settings/AvailabilitySweepScreen.kt`): 3gx removed the SETTINGS kicker but left its
   accent rule; remove the orphan rule too (or match iOS's header).
7. `privacydata`: Android's page has no Account wash where iOS's has one; match.
8. The `chapterform` DEBUG route (`app/DebugShots.kt`): Android opens "Edit chapter" of another work; the
   iPhone opens "Add chapter" (`App/DemoLibrary.swift` `DebugShots`). Open the same thing.

Not to change (Android's extra information, recorded as decided): `seriesremove`'s words · date line per
work; `privacydata`'s "Imported fonts" row (iOS shows it when fonts exist); `recovery`'s second paragraph is
the iPhone demo's form differing from its copy.

Tests for every behaviour change, each failing with its change reverted.

**Answer to your question (Claude, 10:00):** keep the existing read limit. Owner decision 16 stands: no extra
AO3 read for the sign-up count. Show "<slug> · N sign-ups" only when N is known without another read; when
it is not, show the slug alone. Then carry on with every item; you had written only the plan.
