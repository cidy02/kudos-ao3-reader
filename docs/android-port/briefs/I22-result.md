# I22 / A102 result — iPhone parity, batch 3

> **Claude-Code, on review (2026-10-25):** item 2 landed narrower than written below. The shared
> `AppThemedScroll` change was reverted: `SubjectWash` announces `isOnSubjectWash` to everything inside the
> washed content, sheets presented from inside it included, so the shared version could clear other sheets'
> Dark/Sepia/OLED grounds. Instead, the two ScrollViews that sit under their own wash
> (`AO3CollectionsFilterPanel`, the Formatting tray in `CommentMarkup`) drop `.appThemedScroll()`, and its
> test (`themedScrollPreservesSubjectWashAndUnwashedGrounds`) was removed with it. Screenshots verify both.


Branch: `claude/parity-i21`, based on I21's `8ad7a90e`; task: T-457.
Implementation is ready for Claude-Code's deferred build/test/screenshot gates.
**Commit blocked:** explicit-path `git add -- …` failed with `Operation not
permitted` creating
`/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-ios4/index.lock`.
Git metadata is outside this session's writable roots. Nothing was staged or
committed; no SHA or push. Claude-Code must commit the explicit changed paths,
including this report, with `Co-Authored-By: Codex <noreply@openai.com>`.
No builds, test execution, lint gates, simulator operations, sign-in or AO3
requests were performed. `git diff --check` passes. This is not visual approval.

Source paths below are relative to `kudos-ao3-reader/` unless they begin with
`KudosTests/` or `docs/`.

## 1. AO3 filters choose the app accent inside the presentation

Applied I21's existing `ScopeSurfaceAccent` once, to the `NavigationStack` root
in `Features/Search/AO3FilterPanel.swift:149`. The use is `#if os(iOS)`-guarded,
matching the modifier's definition in `UIComponents/AccentInk.swift:71`.
It installs app ink and exact app fill outside the stack's root page, so pushed
language/tag/fandom pages inherit the same accent instead of the results hue.
No host or individual picker was edited.

Shared reach (existing callers, no caller-file changes):

| Host | Source |
|---|---|
| Search results | `Features/Search/SearchView.swift:689` |
| Browse fandom works | `Features/Browse/NativeBrowseView.swift:259` |
| Browse tag works | `Features/Browse/NativeBrowseView.swift:614` |
| Account works | `Features/Bookmarks/AO3AccountWorksList.swift:338` |
| Account's older works filter presentation | `Features/Account/AccountView.swift:236` |
| Author works sort/filter | `Features/Authors/WorksScopeAndSort.swift:179` |

The author panel now explicitly receives the same app palette it already used;
there is no separate author-colour rule. On iPad's regular/regular inspector,
the accent override also applies, with no presentation/layout change.
`UIComponents/FilterPanelPresentation.swift` is untouched. On macOS this new
modifier is excluded; its inspector and navigation stack keep their prior path.
No claim of a successful macOS build is made.

Test: added `ao3FilterRootKeepsTheScopeAccentOutsideItsNavigationStack`
(`KudosTests/AccentInkTests.swift:65`). It reflects only the actual panel body's
outer `ModifiedContent` chain and requires the `ScopeSurfaceAccent` instance
there, without evaluating native navigation pages or executing their tasks.
By reading: removing the production root attachment leaves no matching modifier
and fails the expectation; moving it inside the stack also fails. This covers
wiring, alongside I21's unchanged rendering test
`sectionFiltersChooseAppAccentOverAnInheritedHeroAccent` (`:86`), which checks
both environment roles, two accents and all four themes. Neither test was run.
The wiring test depends on SwiftUI's reflected modifier storage, as the existing
`SettingsHubTests` routing test does; it still needs execution on this SDK.

Left out: native navigation/tick screenshots, pushed-page interaction, AX5 and
inspector smoke checks. The production modifier already implements the required
ink/fill contract; no duplicate colour arithmetic was added.

## 2. Themed scroll backgrounds preserve their enclosing wash

Fixed the shared cause in `UIComponents/AppThemeSurface.swift:14`: when
`isOnSubjectWash` is true, `AppThemedScroll` hides the native scroll background
and adds no flat background. Without a wash, it keeps the existing theme-base
background in Dark/Sepia/OLED and native behavior in Light. This reuses the
existing marker and precedent in `CardList` (`:235`), rather than adding a
collections-only workaround or removing scroll theming at one call site.

`AO3CollectionsFilterPanel` is unchanged. Its `.appThemedScroll()`
(`Features/Account/AO3CollectionsFilterPanel.swift:43`) previously added an opaque theme
base *in front of* `.subjectScreenWash(...)` (`:48`). Light's base token is nil,
which explains why only Light showed the wash. The inbox sheet has no
`.appThemedScroll()` and therefore no competing flat ground
(`Features/Account/AccountInboxFilterSheet.swift:66`).

Additional confirmed shared reach: `CommentFormattingTray`'s scroll area at
`Features/Comments/CommentMarkup.swift:400`, enclosed by its own `.subjectWash`
at `:405`, had the same compositing pattern and now preserves that wash too.
Read every production `.appThemedScroll()` call site. Other same-file matches
(Settings, library collections, queues, comments, Work Detail and writing) apply
the wash and themed-scroll modifiers to different view branches, not a second
confirmed instance of this local pattern. Descendants that receive an enclosing
wash marker use the same shared rule, on both iOS and macOS.

Updated the shared modifier's documentation (`UIComponents/AppThemeSurface.swift:9`,
`:42`) and the environment marker documentation
(`UIComponents/SubjectSurface.swift:1244`). No additional production call sites
were edited. The collections Reset bar's private opaque ground remains intact.

Test: added `themedScrollPreservesSubjectWashAndUnwashedGrounds`
(`KudosTests/AccentInkTests.swift:180`). It renders transparent content through
the real shared modifiers in every theme, compares three wash pixels with the
same wash without the scroll modifier, requires a visible gradient, and checks
the unwashed background against the original theme base/native sentinel.
By reading: reverting the shared fix covers the wash with a flat ground in
Dark, Sepia and OLED, failing the pixel comparison. Clearing every background
unconditionally would fail the unwashed assertions. No test or mutation was run.

Left out: the native Form/List scroll-background suppression is not demonstrated
by a transparent-content render test. Full collections and Formatting sheets,
the Reset bar, native Form/List descendants, Light/Dark/Sepia/OLED, AX5, iPad and
macOS still need Claude-Code's execution and screenshot gates.

## Brief discrepancies and remaining gates

- Item 2 calls the collections content a Form; it is a hand-built ScrollView of
  SubjectFormRow groups. The opaque ground comes from the shared scroll modifier,
  not a native Form or the bottom Reset bar. The inbox also uses ScrollView.
- Item 1 preserves I21's existing app-accent contract: text/glyphs use readable ink
  in Dark/OLED; filled controls use the exact app tint; Sepia uses its app brown.
  Thus “app accent” does not promise exact default-red RGB for every text tick.
- I21's brief/report were absent from this checkout. Read the copies in the
  adjacent `kudos-android-lane/docs/android-port/briefs/` to match the setup and
  report shape; no adjacent-worktree files were changed.
- Source self-review covered all shared callers, both platform branches, root
  attachment versus modifier behavior, wash ordering and ordinary backgrounds.
  No runtime verification or independent adversarial review was performed.
- `docs/ARCHITECTURE_MAP.md` and `docs/REGRESSION_TEST_MATRIX.md` now describe the
  shared rules, test coverage and manual residue. `project.pbxproj`, `Packages`
  and `Vendor` were not changed or staged.
- Next: Claude-Code commits the explicit changed paths, builds both platforms,
  runs AccentInkTests and the required verification gates, gets the merge-bound
  adversarial review, and checks all themes/AX5 plus iPad/macOS before the human
  screenshot approval. Android already has the intended behavior; no Android
  port is needed.
