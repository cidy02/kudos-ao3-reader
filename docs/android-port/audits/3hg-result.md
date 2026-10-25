# A102 / 3hg: Android parity fixes, batches 4–5

Branch: `android/agent-codex-3he`, based on **`2ce2498a`** (3hf), with 3he **`ef99bb6b`** retained. Owner: Codex.
Reference: `/Users/cidy02/kudos-ios-polish`, committed iOS `HEAD` **`1e5d3d44`**, read using `git show HEAD:<path>`; no uncommitted iOS work used. Read both local briefs and root `READIUM_MIGRATION_NOTES.md`.

Android production paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`; test paths are relative to `android/app/src/test/java/io/github/cidy02/kudos/`. iOS paths are relative to `kudos-ao3-reader/` in that reference checkout.

## Verification and handoff

- **Passed:** `android/Scripts/check-invariants.sh`; `git diff --check`; Kotlin **2.3.21** compiler PSI syntax parsing of all **10** changed/new Kotlin files using cached compiler jars directly, without Gradle. Syntax parsing does **not** check Kotlin types, Compose behavior or test results.
- **Not run:** Gradle, builds, JVM/Compose tests, screenshots or emulator checks. No sign-in or AO3 traffic. No schema, migration, backup, dependency, signing or Apple project changes.
- **Three focused tests added**, one for each of items 1–3, in `app/Parity3hgControlsTest.kt`. Extended 3he's formatting-letter test and updated the existing preference-help ground test and content fixture. Reversion sensitivity below was checked **by reading the pre-change implementation and assertions**, without executing mutations. No claim that these tests pass yet.
- **No commit or push:** explicit-path `git add` failed before staging anything: `Unable to create '/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-codex/index.lock': Operation not permitted`. The linked worktree's shared Git index is outside the sandbox's writable roots; approval is unavailable. The **12** changed/new task files remain for Claude-Code to gate and commit with explicit paths and `Co-Authored-By: Codex <noreply@openai.com>`. The three pre-existing untracked briefs are untouched. No other-branch port required; Android-lane integration remains pending.
- **Next:** Claude-Code runs focused suites (`Parity3hgControlsTest`, `CommentFormattingTrayScreenTest`, `Brief3haContentTest`, `A88dSmallFixesTest`) and the full Android gate, performs adversarial review, checks fresh theme screenshots and the manual items below, then commits/pushes/integrates. No open product question; human screenshot approval remains outstanding.

## 1. Compact queue cards share each row

`library/QueuePageScreen.kt:399`: the In Line row fills its container, each work gets a `Box(Modifier.weight(1f))`, and the cover fills that slot. `:421` reserves the second weighted slot with a spacer for an odd last row. Both cards therefore receive half of the available row width after its existing **8dp** gap. This constrains the swipe wrapper's `fillMaxWidth()` without changing `SwipeActionRow` globally.

`QueueWorkItem` retains its existing menus, click handlers, leading/trailing swipe actions and privacy gate: editing, obscured works and callers without actions still take the no-swipe branch. Both branches now sit inside the same width slot. No metadata or selection controls were removed.

**iOS:** `Features/Library/ReadingQueueBrowser.swift:603` (`compactGrid`), with Up Next separate from the In Line covers. The owner-supplied paired-phone observation establishes the missing second column and two-column target.

**Test:** `app/Parity3hgControlsTest.kt:95`, `compactQueueCardsShareEachRowAndAnOddLastCardKeepsItsHalfSlot`, composes the actual queue page with a local in-memory repository, four works, Compact default, and real work actions. One work is Up Next; three In Line works exercise both a full row and an odd final row. It asserts displayed, positive/equal cover widths, equal first-row tops, an 8dp gap, and the odd card's unchanged left edge/width. It also swipes the first cover to reveal Remove while its partner remains displayed. Reading the original unweighted row shows its first swipe wrapper consumes the width and its partner cannot satisfy these assertions; removing just the spacer makes the last card wider. Neither mutation was executed.

### Other two-column layouts checked

Searched every production `chunked(...)` site and every `SwipeActionRow` call, then followed the card wrappers in the relevant list/grid callers. **No other hand-built two-column grid puts `SwipeActionRow` inside its row.** All sites below remain unchanged:

| Site | What was checked |
| --- | --- |
| `library/LibraryScreen.kt:1588` → `LibrarySubjectWorkCard:970` | Variable-column compact cover rows use clickable covers and menus, with no swipe wrapper. Ledger rows at `:1089` have swipes but are separate list items. |
| `library/LibrarySubjectComponents.kt:112,167` | Collection mosaic and miniature-cover pairs use weighted cells; neither has swipes. |
| `library/ReadingStatisticsScreen.kt:632` | Weighted metric cells, no swipes. |
| `author/AuthorProfileComponents.kt:288` → `ui/subject/SubjectComponents.kt:619` | Stat-strip pairs use weighted cells, no swipes. |
| `account/WritingDraftsScreen.kt:313` | Fixed-size status tiles, no swipes. |
| `ui/subject/SubjectWorkCoverCard.kt:385` | Fixed-size status-tile pairs, no swipes. |
| `account/AccountScreen.kt:901` | Accessibility shortcut pairs use weighted boxes, no swipes. |
| `ui/subject/SubjectSegmentedControl.kt:66` | Accessibility option pairs use weighted cells, no swipes. |
| `comments/CommentMarkup.kt:353` | Formatting tiles can become two columns; weighted surfaces, no swipes. |
| `account/AO3ChallengeAssignmentsScreen.kt:170` | Pairs are grouped into explanatory text inside a panel, not two swipeable cards. |

The other swipe calls are single list rows in `library/CollectionDetailScreen.kt:912`, `library/RecentlyDeletedScreen.kt:934`, `home/HomeSectionListScreen.kt:780`, `reader/ReaderContentsSheet.kt:147`, and `ui/components/WorkRowActions.kt:115,197`. Home's cover grid uses `GridCells.Adaptive` (`HomeSectionListScreen.kt:577`), rather than a hand-built two-card row. Pagination chunks groups of five page buttons, not work covers.

**Manual:** verify the owner's actual four-In-Line queue in all five comparison columns, including its blurred partner; swipe both visible columns, confirm that a blurred card does not swipe, and check an odd final row and Select mode. Those privacy/visual claims were traced in source, not observed on an emulator.

## 2. Queue tag-manager dialogs inherit the queue palette

`library/QueueTags.kt:376`: `SubjectPaletteTheme(palette)` encloses the manager's entire dialog group: Edit tag (`:378`), Copy (`:391`) and Remove (`:419`). The Edit dialog's nested Merge confirmation (`QueueTagEditContent`, `:679`) is also created under that provider. The existing form layout and dialog callbacks are unchanged. The house theme supplies Material primary/secondary/tertiary and the subject/token palette, so Material action text, text-field cursor and any selection controls use the queue's readable ink. Intentional destructive error text remains destructive.

**iOS:** `Features/Library/QueueTagManagerView.swift:314,411,451`: Edit tag, its own wash and `.screenTint(palette)`. This task changes Android's dialog tint only, as requested; it does not replace the decided dialog form with a sheet or add a wash.

**Test:** `app/Parity3hgControlsTest.kt:129`, `tagManagerDialogsUseTheirQueuePaletteInEveryTheme`, opens Rename, Copy and Remove through the actual manager for a purple queue under the app theme. It checks Cancel ink in Light/Sepia/Dark/OLED and enabled Save after a local draft rename, cancelling every dialog without changing stored tags. It does not wrap the fixture in a purple theme, so reverting the production provider exposes app red/brown/cream and fails. The nested Merge inheritance and field cursor were checked by reading the shared provider and Material defaults; no separate cursor pixel assertion or nested-window test was added. There are no radio controls in the current edit form itself.

**Manual:** check field focus/cursor, nested Merge, Copy and Remove in each theme, including the owner's purple Neon reread queue. No real writes are needed to inspect these dialogs.

## 3. Note Done uses accent ink

`reader/ReaderNoteEditor.kt:101`: the Done check explicitly uses `tokens.accentInk`, matching `reader/ReaderContentsSheet.kt:104`. Save/cancel/keep-on-dismiss behavior is untouched.

**iOS:** `Features/ReaderReadium/ReaderNoteEditor.swift:86` has the native confirmation-toolbar checkmark; the owner supplied the accent-colour reference. Android Display also explicitly tints its Done check (`CustomizeThemeSheet.kt:135`).

**Test:** `app/Parity3hgControlsTest.kt:158`, `noteDoneCheckUsesAccentInkInEveryTheme`, draws the actual editor, then counts accent-coloured pixels inside Done's bounds across all four themes. Reverting the explicit tint makes `ToolbarCircleButton` supply primary ink (`ui/subject/SubjectComponents.kt:894`), leaving no accent check pixels in that region. Checked by reading, not by executing a reverted run.

**Manual:** Add Note and Edit Note over a reader page, including sheet status-bar behavior already changed by 3hf.

## 4. Preference help keeps cards visible in Light

`account/AO3PreferencesScreen.kt:482`: pass `tokens.background` to `presentSheet`, rather than `sheetGround`. These differ only in Light: grouped page grey behind white topic cards. Other themes retain their existing grounds. `writing/WritingTextEditorScreen.kt:270` and recovery presentation remain unchanged on `sheetGround`.

**iOS:** `Features/Account/AO3PreferencesView.swift:267,306,314` uses the card backdrop for help presentation and card rows for topics; the owner's measurements specify Light **242,242,247** ground / white cards.

**Tests updated:** `app/Brief3haContentTest.kt:160`, renamed `preferenceHelpPassesThePageGroundToItsSheetInEveryTheme`, now asserts the supplied ground and an actual surface pixel against `tokens.background`, after waiting for idle. Reverting the production line fails in Light. Its recovery test at `:179` still asserts `sheetGround`. `app/A88dSmallFixesTest.kt:91` uses the correct background when composing help content directly; it retains its white-card and Done checks. This corrects the historical preference-help `sheetGround` contract; no shared token policy changed.

**Manual:** Light help ground/card separation and the recovery sheet's still-white Light background.

## 5. Series current-membership mark

`writing/WritingAssociationPickers.kt:257`: current series now uses filled `CheckCircle` and the scope accent even when `isSelected` is false. A newly selected series keeps its existing accent filled-circle mark, and unselected series keep `RadioButtonUnchecked`. The "This work is in it" line and disabled current-series click behavior remain unchanged. Removed the unused bare-Check import. Collections use this row with `current = false`, so their behavior is unchanged.

**Reference discrepancy:** the owner's measured iPhone target is a filled accent check circle. The available committed iOS snapshot, `Features/Writing/WorkAssociationPickers.swift:450`, still uses bare `checkmark` for `isCurrent` (and also has the "This work is in it" line at `:457`). Followed the explicit requested target rather than that older snapshot. No product clarification is needed.

**Test/omission:** no new test for this two-branch icon/tint substitution; traced all `AssociationPickRow` callers (Series and Collections). Visual verification of the current, newly selected and unselected series marks remains manual.

## 6. Formatting tray letters match the reference

`comments/CommentMarkup.kt:228`: the existing shared glyph renderer now draws scripted A + 2 in serif with fixed **15dp / 9dp** text sizes, aligning their baselines and offsetting the 2 **6dp up / 4dp down**. Heading is bold **H**, fixed **15dp**, default font. Existing B/I/U/S remain serif 16dp and Aa serif 11dp. Quote, Bullets, Numbers, Code, Divider, Link and Spoiler still use icons, as explicitly requested. No markup insertion logic changed.

**iOS:** `Features/Comments/CommentMarkup.swift:534–563`, especially `scriptedTwo`: 15pt serif A, 9pt serif 2, baseline offsets +6/−4; Heading uses default-font 15pt bold H. Thus "serif letters where iOS draws letters" does not make H serif. iOS's Code is text `</>` in this snapshot, but the owner expressly requested leaving Android Code as an icon.

**Test extended:** `comments/CommentFormattingTrayScreenTest.kt:47`, `formattingLettersUseIosSerifSizes`, retains the five original letter checks and adds H's family/size/weight plus A/2's serif families, separate sizes, side-by-side bounds and raised/lowered positions for both tags. Restoring the icon branches removes H/A/2 text nodes, so these assertions fail by inspection. The tests were not executed. Glyphs still use fixed dp-to-sp sizing like 3he's letters; the existing tray column-count tests remain intact.

**Manual:** compare A², A₂ and H at normal and largest text, checking that the small 2 is unclipped and the tray's labels/tiles still align.
