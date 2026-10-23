# Brief 3gz — A88a Android follow-up

Implemented the ten items on `android/agent-codex-3gz`, in this worktree only.
This result file was created before code changes. No Gradle, sign-in, AO3 traffic,
commits, pushes, branch changes, or TASKS.md edits. The four pre-existing untracked
brief/audit files are untouched.

## Per-item findings and changes

Paths in this table are relative to `android/app/src/main/java/io/github/cidy02/kudos/`.

| Item | Location | What changed / code finding |
| --- | --- | --- |
| 1 · Queue tags | `library/QueueTags.kt:515`, `:450`, `:454`, `:461` | Each menu row gets 12dp vertical padding. Both footnotes get the page's 16dp gutter plus the existing 4dp footnote inset. New tag uses the same plain `SubjectTextFieldRow` as Add to Queue, with leading +, placeholder, Add and keyboard submission; the existing trim/duplicate protection and repository action remain in the manager. `QueueTagManagerContent` (`:416`) is the actual page content used by production and tests. Confirmed the spacing/gutter/outlined-field findings in `queuetags.png`. |
| 2 · Fandom filter chip | `browse/FandomWorksScreen.kt:117`, `:119`, `:286` | The presentation filters include the page's fixed fandoms. Chips exclude the **result heading's subject**, as iOS does, instead of excluding the navigation fandom unconditionally. Thus a Doctor Who page whose fixture heading names Star Wars shows Doctor Who and 1 Filters. A heading that already names the fandom still avoids repeating it, matching iOS. Repository inputs, reset comparison, and family-count caching keep their existing behavior. |
| 3 · New collection title | `library/CollectionEditorSheet.kt:162`, `:310` | The shared header lets its weighted title wrap, removing the one-line ellipsis. Cancel and the existing Create/Done buttons retain their intrinsic widths, enablement and callbacks. |
| 4 · Theme swatches | `ui/subject/SubjectForm.kt:430` | **Correction to the brief:** Android already varied preset saturation/brightness by theme. The actual missing rule was opacity. The swatches now reuse `HomeFacts.carouselQueueTint`, with the same HSV/alpha table as iOS: Dark/OLED .38/.78/.30, Light .42/.75/.26, Sepia .34/.70/.22. Custom hex colours still render exactly. This shared row is used by New/Edit Queue (`library/QueueEditorSheet.kt:189`) and New/Details Collection (`library/CollectionEditorSheet.kt:197`). |
| 5 · Formatting Done | `comments/CommentMarkup.kt:266`, `:284` | Added Done beside Formatting, calling the existing dismiss callback without changing the draft. The header stays above the scrolling formatting groups. The modal hosts this exact `CommentFormattingContent`. |
| 6 · Chapter grouping | `comments/CommentsScreen.kt:787`, `:809`, `:874` | All Comments and the chapters share one subject panel, with an inset separator before each chapter. Row surfaces are transparent rectangles instead of individual rounded cards. Selection speech/checks, totals, click callbacks, loading/failure text and scrolling remain. The modal hosts `ChapterPickerContent`. |
| 7 · Nearby tile colours | `ui/components/KudosPaginationBar.kt:203`, `:251`, `:254`, `:266` | Selected fill/stroke/label use the scope palette's chipFill/chipStroke/accentOnFill. Ordinary tiles use Kudos glassFill(.08), glassStroke(.13) and primaryInk, including a visible OLED fill. The sheet uses the Kudos background and delegates to `PageJumpContent`. **Correction:** Material primaryContainer was unset, but surfaceVariant was already explicitly set in Theme.kt; the purple selection finding still holds. |
| 8 · Browse wash input | `browse/FandomWorksScreen.kt:117`, `:122` | Both fandom and tag works now hash the completed result heading's subject, falling back to the navigation name. Android previously used the navigation name through fandomListPalette. Both apps already have the matching Unicode djb2 implementation (`HomeFacts.coverHue`); the difference was its input. The page wash now agrees with its existing hero palette. |
| 9 · Pronunciations empty state | `settings/PronunciationSettings.kt:147`, `:175` | Added a subject card and a speech-bubble outline containing A above No corrections yet. The existing explanatory text and Android engine limitation remain. The sheet invokes the same `PronunciationEmptyState` used by the test. |
| 10 · Collection reorder | `library/CollectionReorderSheet.kt:96`, `:109`, `:189`, `:209`, `:249` | DECISIONS.md does not retain the arrow buttons. Replaced them with handles and the series reorder's long-press/drop approach. Move up/down remain available as TalkBack custom actions, with boundary actions omitted and moves disabled while saving. Whole rows move above their siblings while held. The existing draft-order mutation and save-on-Done repository write remain in the modal wrapper. |

No item was skipped wholesale. Items 4 and 7 had partly inaccurate explanations;
the actual differences were fixed as described above.

## iOS references checked

Under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:

- `UIComponents/SubjectHueSwatches.swift:133` fills presets with carouselQueueTint;
  `UIComponents/CarouselCardStyle.swift:255` defines its HSV/opacity table.
- `Features/Browse/NativeBrowseView.swift:173`, `:210`, `:334`, `:567`, `:712`
  supply fixed fandom filters, exclude the hero's subject from chips, and hash the
  completed hero subject for both kinds of works page.
- `Features/Search/SearchPaginationBar.swift:452` uses chipFill/chipStroke for a
  selected tile and glassFill(.08)/glassStroke(.13) otherwise.
- `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:79` uses the
  character.bubble empty-state icon inside a form section.

Both supplied A88a reviews were read. Only the existing queue-tags tile was viewed;
no new app rendering or visual parity is claimed.

## Regression tests and expected mutation failures

**Not executed.** Builds, JVM/Robolectric execution, and behavioral mutations are
reserved for Claude. These are source-reviewed expected outcomes, not green test
claims. Retain content extractions/test access when reverting a behavioral hunk;
removing an entire extracted function would only cause a compilation failure.

Tests use the real content composables without opening dialog windows. The two
colour tests draw the Compose Android view into a bitmap in native graphics mode;
they do not use PixelCopy/captureToImage or compare source-code strings.

Test locations below are relative to `android/app/src/test/java/io/github/cidy02/kudos/`.

| Test / location | What it checks | Expected result with its behavior reverted |
| --- | --- | --- |
| `app/Brief3gzContentTest.kt:52` · `queueTagsAreFullRowsAndBothFootnotesUseThePageGutter` | Used and unused rows are at least 44dp; both actual footnotes start inside the field-label gutter. | Removing vertical padding fails row height; reverting either footnote's gutter fails its left-bound assertion. |
| `app/Brief3gzContentTest.kt:67` · `queueNewTagIsAPlainFieldWithAnAddActionAndKeyboardSubmission` | The plain named input has text height, Add is off while empty, and Add plus IME submit forward each draft. | Restoring OutlinedTextField removes the shared plain input semantics and restores its 56dp minimum; input lookup/height fails. |
| `browse/FandomResultsParityTest.kt:138` · `fandomChipAndCountDescribeTheFixedFandomWhenTheResultHeadingNamesAnotherSubject` | Fake Doctor Who route plus a Star Wars result heading displays Doctor Who and 1 Filters. | Restoring the original summaryLabels call produces no fandom chip and 0 Filters. |
| `app/Brief3gzContentTest.kt:83` · `newCollectionTitleWrapsAtScaleTwoAndBothActionsStayReachable` | Actual 2.0× text layout wraps with no visual overflow/ellipsized line; Cancel and Create are displayed and invoke their callbacks. | Restoring maxLines=1/ellipsis fails wrapping and ellipsis assertions. |
| `app/Brief3gzContentTest.kt:190` · `presetSwatchesUseIosThemeOpacityAndCustomColoursStayExact` | Samples all five preset fills against independent HSV/alpha literals in all four themes, checks the exact custom colour, and checks selecting Mint clears the custom hex. | Restoring opaque carouselTint produces mid-tone pixels instead of the expected translucent wash in every theme. |
| `app/Brief3gzContentTest.kt:98` · `formattingDoneDismissesWithoutEditingAndTilesStayOpen` | At 2.0×, Bold changes the draft without dismissal; after scrolling to Spoiler, Done stays displayed and dismisses without editing again. | Removing Done fails its lookup; putting the header back inside the scroll makes its displayed assertion fail when scrolled far enough. |
| `app/Brief3gzContentTest.kt:110` · `chapterChoicesShareOnePanelWithSeparatorsAndKeepSelectionAndCounts` | One common panel, three separators, adjacent rows separated by at most a hairline, selected Chapter 1, formatted total, and both row callbacks. | Restoring separate cards removes the shared panel/separators and restores gaps between rows; grouping/geometry assertions fail. |
| `app/Brief3gzContentTest.kt:225` · `nearbyTilesUseTheScopePaletteAndOledHasAnUnselectedFill` | Samples selected and ordinary tile fills in all four themes using an amber scope palette, checks the selected label colour, and verifies a tile stages until Go. | Restoring Material container/label roles fails pixel/label-colour assertions, including OLED's ordinary tile fill. |
| `browse/FandomResultsParityTest.kt:147` · `fandomWashUsesTheResultSubjectAndNotTheNavigationFandom` | Reads the actual shell wash submitted by the loaded fandom page and compares its hue with the result subject's hash. | Restoring fandomListPalette(navigationName) yields the Doctor Who hue instead of Star Wars. |
| `browse/FandomResultsParityTest.kt:154` · `tagWashAlsoUsesTheResultSubjectAndDoesNotInventAFandomFilter` | The same real wash check on the tag route, plus 0 Filters and no invented Doctor Who chip. | Restoring the old palette input fails the hue assertion. |
| `app/Brief3gzContentTest.kt:133` · `pronunciationEmptyCardShowsASpeechBubbleAAboveTheTitle` | The title is in the new card; the actual outline icon and A are present, with the bubble above the title. | Restoring the plain empty-state column removes the card/icon; those lookups fail. |
| `app/Brief3gzContentTest.kt:143` · `collectionHandlesDragAndAccessibilityMovesChangeTheDraftBeforeDone` | Three handles, no arrow buttons, a real long-press drag, then a TalkBack move, followed by Done observing the changed order. Neither move invokes Done. | Restoring the arrow-button rows fails handle/arrow assertions; reverting the drag handler or custom action fails the corresponding order/action assertion. |

The browse tests use the suite's fake AO3Client and local HTML; they make no real
network requests. Existing tests in both edited classes are retained.

## Verification and handoff

- `git diff --check` passed. Branch remains `android/agent-codex-3gz`.
- A lexical delimiter check passed for the eleven changed/new Kotlin files;
  this is not a compiler check.
- Twelve new tests: nine in Brief3gzContentTest and three in FandomResultsParityTest.
- TASKS.md has no diff. Existing untracked A90/3gz input files remain untouched.
- No build, runtime test, or mutation run was attempted, per the brief.

Claude: run both edited test classes first, then the lane's usual gate and the
existing Brief3gxParityTest, TagSheetParityTest, LibraryForms3gxTest,
PageJumpSheetParityTest and WritingSeriesScreenTest for adjacent behavior.
Execute the mutations above; no mutation outcome is certified here. Capture all
affected screens in Dark, Light, Sepia, OLED and 2.0× text, including the modal
wrappers, keyboard/IME paths, long-press drop, and TalkBack move actions.

Collection dragging intentionally follows the existing series approach: drops
target visible rows; repeated accessibility moves can reach the rest of the list.
Edge auto-scroll is not implemented. Native bitmap rendering in the new colour
tests and physical drag gestures still need Claude's first runtime pass.
