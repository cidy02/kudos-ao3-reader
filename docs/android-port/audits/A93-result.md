# A93 result: adversarial review of Codex's 3hb (read only)

*Done, 2026-10-23.*
- **Read:** `briefs/3hb.patch` (against `f8d65081`), Codex's `3hb-result.md`, and the brief.
- **Paths:** Android paths are under `android/app/src/main/java/io/github/cidy02/kudos/`, as applied in the lane. iOS paths are under `~/kudos-ios-polish/kudos-ao3-reader/`. Pixel values are sampled from the A88c shots.
- **Not done:** builds, Gradle, git writes, AO3.

**Verdict:** fit to land. There's no P1 or P2, and no ✅ row's screens change. Two of the fixes move a different way from the iPhone; the first two P3s below say how, and both are small to correct. One sheet still has darker cards than the iPhone's (missed by A88c and the brief), and four more pagers miss the page's palette. Item 9's undo is clean.

## Findings

### P3: a pinned field draws a flat stripe across the wash (item 1)

- **What's drawn:** once pinned, `writingPinnedFieldGround` paints `palette.theme.cardBackdrop` (`writing/WritingPinnedFieldGround.kt:9-12`; callers `WritingTagsEditorScreen.kt:128`, `WritingAssociationPickers.kt:132`).
- **Why it shows:** the band pins at the list's top, the status bar plus 76 dp, about 110–190 dp down the screen. The screen's wash runs 380 dp (`SubjectMetrics.defaultWashHeight`), so the band sits where the wash is still strong.
  - **Pinned:** the bar area above is washed, the band is flat (#F2F2F7 in Light), and the chips scrolling below are washed again. That's a stripe with an edge on each side.
  - **At the moment it pins:** nothing else jumps; the switch comes exactly when the header item scrolls off (`firstVisibleItemIndex >= index`). But the band turns from wash to flat in one frame.
- **iOS doesn't pin this field.** The tags editor's `GlassFieldBar` is an ordinary row in the `List` (`Features/Writing/WritingTagsEditor.swift:110`, `:162`). Collections' search is a `TextField` row (`Features/Writing/WorkAssociationPickers.swift:132`). Both scroll away under the one wash. Android's pin is its own (it keeps the input over the keyboard).
- **Fix:** keep the pin, but once pinned paint the screen's wash as it is at the band's offset, not a flat ground. For example, take the band's `positionInRoot().y` from `onGloballyPositioned`. Inside a `clipRect`, `drawRect(backdrop)`, then `translate(top = -bandTop)` and draw `palette.wash(washHeightPx)` over `Size(width, washHeightPx)`. The band then hides the chips and reads as the page behind it.
- **The test locks the stripe in:** `checkPinnedField` asserts the pinned pixel is `tokens.background` (`Brief3hbContentTest.kt:141`). With the fix it should assert `washAt(pinned.top + 2)`, as its initial check already does.

### P3: in Light the Display and Note sheets' cards turn white, but the iPhone's are a shade darker than the sheet (item 3)

- **The change:** `LocalSettingsFormGround provides true` wraps the whole Display sheet (`reader/ReaderScreen.kt:1080`) and the Note editor (`reader/ReaderNoteEditor.kt:82`), in every theme. Their panels become `cardSurface`: white in Light, cream in Sepia.
- **Sepia is right:** the iPhone's sheets are opaque Sepia with cream #FBF0D9 cards.
- **Light goes the wrong way:** the iPhone's reader sheets are system glass there, and their cards are a shade darker than the sheet.
  - Sampled: Display 195–205 on 226, Note 206 on 226, Read Aloud 206/203 on 226.
  - Android's #E6E6EA on #F2F2F7 had that relationship. White on #F2F2F7 reverses it.
- **Pronunciations and the backup import are right in both:** on the iPhone those are opaque, with white cards on #F2F2F7.
- **The brief's premise was half right:** Android's `readerspeech` "already right" is right in Sepia only. Its Light cards are white against the iPhone's grey, the same mismatch, which A88c didn't call out.
- **Side effect:** the flag also makes the selected segment a white pill in Light and Sepia (`ui/subject/SubjectSegmentedControl.kt:52`). That matches the iPhone's segmented control in both themes, so a fix shouldn't simply drop the flag in Light.
- **Fix:** on the three reader sheets (Display, Note, Read Aloud), keep the panel's glass in Light and use `cardSurface` in Sepia. Dark and OLED already match: `cardSurface` #222228 and #1C1C1E against the iPhone's 34,34,40 and 28,28,30. For example, give `settingsPanelGround()` a reader-sheet variant, or provide the flag as `theme != Light` and keep the segmented control's white fill on its own condition.
- **The tests lock Light in:** `displayCardsUseSpeechSheetsElevatedGroundInLightAndSepia` (`:174`) and `noteCardsUse…` (`:183`) assert `cardFill` in Light.

### P3: Customize Theme's cards are still darker than the iPhone's (missed by A88c, so not briefed)

- **Android:** the sheet's `SettingsSection`s (`reader/CustomizeThemeSheet.kt:136`, `:217`, `:229`, `:259`) have no form-ground provider, so they're glass. Sampled #E6E6EA on #F2F2F7 in Light, and #E0D3B7 on #ECDEC1 in Sepia.
- **iPhone:** white #FFFFFF on #F2F2F7, and cream #FBF0D9 on #ECDEC1. Customize Theme is an opaque sheet on the iPhone, as Pronunciations is.
- **Fix:** wrap `CustomizeThemeContent`'s column in `LocalSettingsFormGround provides true`, in every theme. The test pattern from `displayCards…` carries over.
- My A88c note gave this screen other minors and missed this one.

### P3: other pagers that iOS gives the page's palette, where Android still passes the default (your item 7 question)

3hb fixed the two works pages. In the iOS callers of `SearchPaginationBar`, a page palette is also passed in these places, where Android passes none:

| iOS | Android | Android's page palette (exists) | Row |
|---|---|---|---|
| `Features/Search/SearchView.swift:604` `palette: resultsPalette` | `search/SearchScreen.kt:1073`, `:1142` | `resultsPalette` at `:296` | Search 🟦 |
| `Features/Account/AO3CollectionDetailView.swift:535` (title-hued, `:218-221`) | `account/AO3CollectionDetailScreen.kt:310` | `palette` at `:127` | AO3 collections **✅** |
| `Features/Challenges/CollectionModerationView.swift:210` (title-hued, `:68-70`) | `account/AO3CollectionModerationScreen.kt:181` | `palette` at `:67` | AO3 collections **✅** |
| `Features/Challenges/PromptMemeView.swift:454` (title-hued, `:75-77`) | `account/AO3PromptMemeScreen.kt:177` | `:73` is `tokens.scopePalette`, the app's, not the title's | Challenges 🟦 |

- **Already equal:** the remaining iOS callers either pass `theme.scopePalette` (collection items, collections list, drafts) or nothing (Later, Bookmarks, History, Subscriptions, Inbox, your works). Android's default matches them.
- **Pre-existing, not 3hb's:** the shots never caught these because the demo pages have one page or the pager is below the fold. Passing the palette changes two ✅ screens (the collection page and moderation), so they'd need a re-shoot.
- **Worth a look:** whether Android's prompt meme page's own wash differs from iOS's title-hued one.

### P3 (small): item 8's tint keeps a different red from iOS outside Sepia

- **Sepia is exactly iOS:** `tokens.theme.appTint` is #9A6732 (`ui/theme/Color.kt:9`). iOS's reader sheets take `accentTint(theme.effectiveTint, …)` (`Features/ReaderReadium/ReadiumReaderView.swift:23`, `:1686`), and `effectiveTint` is `appTint` in Sepia (`App/ThemeManager.swift:59-61`; `controlColor` is the identity, `UIComponents/SubjectSurface.swift:84-86`). Same value, `Features/Reader/ReaderStyle.swift:146-148`.
- **Light, Dark and OLED keep `tokens.scopePalette.accent`:** that's a palette-derived shade (Light: hue at 0.72 saturation, 0.52 brightness). iOS's glyphs there are `accentInk(effectiveTint)`, the picked accent, lifted on Dark and OLED.
- **Simpler and exact:** `tokens.accentInk` in all four themes, for `ReaderContentsSheet.kt:104` and `ReaderScreen.kt:1074`. It equals `appTint` in Sepia, and the new test already asserts `tokens.accentInk` (`:312`).

## Tests that would pass with their change reverted

- **Passes on the old code by design:** `otherCustomTitlesKeepTheirExistingEllipsisBehaviour` (`:254`). It's a guard, as Codex says.
- **Fail on revert, but assert the behaviour the first two P3s would change:** `checkPinnedField`'s pinned assertion (`:141`), and the Light half of the Display and Note card tests (`:174`, `:183`).
- **The rest fail on revert** (each read for its revert path):
  - the pre-pin wash pixel;
  - the filled minus (an ✕ has no pixel above its centre);
  - the pronunciations and backup cards;
  - both disabled-Add colours (`layoutInput.style.color` is the explicit accent before and the inherited disabled colour now);
  - the title fit (at 80 dp the old Text would exist);
  - the title-case headers and the chevron's 35 dp;
  - the WebView's zoom reset (it stays 200 and the wait times out);
  - the explicit palette, plus the two works-page integration tests (the global red is a different hue from the Star Wars brown);
  - the Sepia ✓;
  - the separators;
  - the Find and Note focus;
  - the editor's whole-title registration and pane title.
- **Runtime unknowns:** whether Robolectric's WebView keeps `textZoom`, and whether it draws the `drawBehind` ground. I couldn't run either.

## Checked and fine

- **No ✅ row's screens change:**
  - `KudosPaginationBar`'s new `palette` defaults to the old `tokens.scopePalette`, and the 22 other callers pass none.
  - `SettingsActionRow`'s new `tint` defaults to null.
  - The form-ground providers are local to the four sheets: Reader and Settings rows, both 🟦.
  - The bar title is unchanged for its other users.
- **Item 5:** the only `wholeTitleOnly = true` caller is the editor (`writing/WritingTextEditorScreen.kt:127`).
  - The other `customTitle` users don't measure (`!wholeOnly ||` short-circuits) and draw the same Text: the selection counts in `home/HomeSectionListScreen.kt:260`, `author/AuthorProfileScreen.kt:461`, `library/CollectionDetailScreen.kt:353` and `library/RecentlyDeletedScreen.kt:382`, and the three `chrome.customTitle = null` sets.
  - `PushedShellChrome.reset()` clears the flag, and each registration sets it.
  - `BoxWithConstraints` is a subcompose layout, which throws on intrinsic queries. The bar row asks none (no `IntrinsicSize` in `MainScaffold.kt`).
  - TalkBack gets the title as the editor's `paneTitle`, so it still names the field when the bar has no title.
- **Item 9's undo is clean:**
  - Find and Note open full height (`skipPartiallyExpanded = true`) and request focus on appear, as iOS's `ReaderSearchView.swift:280` and `ReaderNoteEditor.swift:98` do. `ReaderEditingSheetState.kt` is gone from the net diff.
  - The extracted `ReaderSearchContent` keeps behaviour. Clear now calls `onQueryChange("")`, which is `model.search("")`, and that resets first and returns on a blank query (`reader/ReaderSearch.kt:81-85`). So it's the same as the old `model.reset()`.
- **Item 2:** `Icons.Default.RemoveCircle` at the same red, label and callback, as iOS's `minus.circle.fill` (`WorkAssociationPickers.swift:257`).
- **Item 4:**
  - Moving the accent to `textButtonColors(contentColor = …)` lets the disabled state use Material's 38% ink.
  - Both places are fixed, the queue manager and the shared bulk-tag form.
  - `SharedTagContent` is a straight extraction from the dialog.
- **Item 6:**
  - `SettingsGroupLabel` (title case, gutter padding) replaces `SectionRuleHeader`.
  - The Font row gets `showsDisclosure`.
  - The preview WebView is held at `textZoom = 100` with `text-size-adjust: 100%`, so it stays at the reader's size at 2×. Android's WebView takes its default text zoom from the system font scale.
- **Item 8's Contents dividers:**
  - They sit between the rows in `itemsIndexed` (a lazy item stacks its children), inset 20 dp, on `tokens.separator`.
  - Navigation is unchanged.

**P1 0 / P2 0 / P3 5**
