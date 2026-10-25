# I21: iPhone fixes from the parity verification, batches 1 and 2 (A102)

The owner asked for parity to be verified before any iPhone Duo work. Two judges compared fresh pairs from both
phones in five columns: Dark, Light, Sepia, OLED, and Sepia at the largest text (AX5). These items are where the
**iPhone** breaks its own rules (Android is right). Each was measured on the shots and traced in code. Fix the
cause, not the screen.

**Where:** `/Users/cidy02/kudos-agent-ios4`, branch `claude/parity-i21`, from `claude/polish-loop` at `1e5d3d44`.
`Packages` and `Vendor` are local symlinks; never commit them.

**Rules:**
- Don't build, test or touch a simulator. Claude-Code builds and gates after tonight's screenshot run, since one
  device runs at a time.
- Don't sign in or contact archiveofourown.org.
- Don't change `project.pbxproj`; new Swift files are picked up automatically.
- Don't revert anyone's work.
- Commit on your branch with explicit paths (never `git add -A` or `.`). End each commit message with
  `Co-Authored-By: Codex <noreply@openai.com>`.
- The codebase is hand-wrapped; match the surrounding style and don't reformat.

The colour contract these items enforce:
- **Scope surfaces** (pickers and forms opened over a page) use the app accent, which is brown in Sepia
  (`ThemeManager`; T-446).
- **A coloured sheet** (one with its own subject colour, like New Queue or New Collection) gives its controls that
  colour.
- **Fills** (switches, filled buttons, selected pills) use the exact colour. They never use the lightened text
  accent (owner question Q19; T-348).

## 1. Sheets over Work Details and the queue page inherit the hero's colour
The root tint follows the newest wash, so a sheet presented over a washed page inherits that page's hue. Over Sodium
Lights that's purple, in every theme, Sepia included. T-446 fixed only the Library and Home section filter sheets,
with `LibrarySectionFilterAccent` (`Features/Library/LibraryFilterPanel.swift:5`), which applies
`accentTint(themeManager.effectiveTint, on: appTheme)` from inside the presentation.

Apply the same to these scope surfaces:
- Add to Queue (`WorkDetailView.swift:214`, `AddToQueueView`);
- Add to Collection (`:211`, `AddToCollectionView`);
- the AO3 bookmark form ("Bookmark on AO3"; find where it is presented);
- the series preservation prompt (`:218`, `SeriesPreservationPromptSheet`);
- the queue page's Add Works sheet and bulk Tag sheet ("Your changes apply to all N selected works"). The bulk Tag
  sheet's Done is amber today, (216,168,112) in Dark, and should be the app accent.

Keep the work's colour on the My Copy sheet and the download-date editor, which are about the work itself. Android
colours those two with the work's palette too.

If one well-named shared modifier is cleaner than reusing `LibrarySectionFilterAccent` at more call sites, rename it
and update its three uses. Keep the `#if os(iOS)` guards.

**Expected:** each sheet's tick, Done, Cancel, Save and toggles are (153,0,0) in Dark, Light and OLED, and
(154,103,50) in Sepia.

## 2. Selected pills fill with the lightened accent
`UIComponents/SubjectSurface.swift` `SubjectChip` (~1060): `.pill(isSelected: true)` fills with
`palette?.accent ?? fill`. In Dark and OLED that's the lightened text accent, (219,114,114), with dark text. Two
places show it:
- the AO3 works filter's Completion pill (`Features/Search/AO3FilterPanel.swift:707`, `worksCompletionChips`);
- the author page's "All" fandom pill.

Android fills with the palette's exact tint (`palette?.tint ?: tokens.accent`) and labels it for that fill. Make iOS
fill with the exact tint (`SubjectPalette.tint`, which is the picked colour exactly). Keep the label colour computed
from the actual fill (`ThemeManager.label(on:)`).

**Expected:** a selected pill is (153,0,0) with white text in Dark and OLED, unchanged in Light, and Sepia's brown in
Sepia.

## 3. The AO3 works filter sheet's header band is white in Sepia
In Sepia, and in Sepia at AX5, the sheet's header band (title, Reset, "3 of the 3 works on this page match") is
(255,255,255) above a Sepia body of (236,222,193). Android's Sepia sheet is one ground. Find what paints the band
(likely a system background colour on a pinned header) and give it the theme's sheet ground. Light and Dark should
look as they do now.

## 4. Report a Bug: a disabled button looks enabled
`Features/Support/BugReportView.swift:61–66`: "Continue on GitHub" is `.disabled(trimmedSummary.isEmpty)`, but with
an empty description it draws primary-ink text and a red ladybug, so it looks tappable. Android greys it. When
disabled, draw it the way iOS draws a disabled form button (secondary or tertiary ink for both text and icon); when
enabled, leave it as it is. Find why the label ignores the disabled state (row styling or a foreground style) and fix
it there. If the cause is shared, check other rows.

## 5. Pinned bottom buttons at AX5 have no ground
On the challenge pages at AX5, the pinned bottom buttons float over the list's text, and the text runs between and
through them:
- Assignments ("Report a default" / "Claim a pinch hit");
- Your Sign-up ("Add request" / "Submit sign-up");
- Sign-ups ("Your sign-up" / "Create sign-up");
- Prompts ("New prompt");
- Challenge settings ("Save changes").

Give the bar the system's edge treatment so content fades under it, as an iOS 26 app would. Prefer
`safeAreaBar(edge: .bottom)` (system scroll-edge effect) over a hand-made gradient where the deployment target allows
it. Look for a shared helper behind these bars before editing five screens. Brief I10 put a gradient behind the
collections filter's Reset; check whether that helper should be shared.

## Tests
Add a focused test per item where the existing style allows it:
- `KudosTests/AccentInkTests.swift` (T-446's `sectionFiltersChooseAppAccentOverAnInheritedHeroAccent`) is the model for
  items 1 and 2;
- render with `ImageRenderer` and warm it up once first, since its first pass can be blank.

Each test should fail with the fix reverted, so say how you checked that by reading. Where a test is impractical,
say so.

## Report
Write `docs/android-port/briefs/I21-result.md` in your worktree with:
- per item: what changed (`path:line`), the test, and what you left out and why;
- every extra call site you changed;
- anything you think the brief got wrong.
