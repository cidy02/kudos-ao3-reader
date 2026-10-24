# I19 — iPhone text editor at AX5

Status: implemented, awaiting Claude's build/test/simulator verification on
`claude/agent-ios-i19`. This brief was written before code changes and updated
after the fix. No builds, test runs, simulator work, commits, pushes, branch
changes, AO3 requests or `TASKS.md` edits were performed.

## Changes and visibility

- `kudos-ao3-reader/Features/Writing/WritingTextEditor.swift:103`: iOS recovery
  status has a one-line limit only at accessibility sizes. It truncates rather
  than taking space from the text area; its explicit accessibility label retains
  the complete sentence.
- `kudos-ao3-reader/Features/Writing/WritingTextEditor.swift:274`: the tray keeps
  its existing single horizontal scroll row, ordering, spacing, padding and
  themed background. At accessibility sizes, chip labels use their full ideal
  width and each tag/name stays on one line (`:365`); wider chips scroll into view
  instead of wrapping. All tags and their VoiceOver names remain available.
- `kudos-ao3-reader/Features/Writing/WritingTextEditor.swift:284`: at accessibility
  sizes the long formatting footnote becomes a single-line **Editor help** button
  with `info.circle` and the app's existing `minimumHitTarget()` (44 pt minimum).
  Its native alert (`:291`) contains both the complete recovery status and the
  complete original formatting explanation, with an OK action. Sighted users can
  therefore also reach everything that was shortened. Help remains usable during
  Preview; the scroll row's formatting actions remain disabled there (`:283`).
- At normal sizes the original full recovery text, two-label chips, and full
  formatting footnote (`:297`) retain their fonts, layout, padding and materials;
  there is no help button. New layout behavior is iOS-only; macOS keeps its full
  notices and Format menu.

Expected AX5 presentation: the text area gets the space above a one-line recovery
status, one scrolling chip row and the short help action. The goal is at least
five complete body lines on a 402×874 pt iPhone 17 with the keyboard down. This has
**not** been visually verified or measured by a test run here.

Existing patterns checked: `OnboardingScaffold`
(`Features/Onboarding/OnboardingComponents.swift:15`) moves oversized AX footers
into scrolling content, while `CommentWriteBarPlacement`
(`Features/Comments/CommentsView.swift:24`) places an AX footer beneath the content.
The editor already uses that sibling placement, and needs its text view to own
scrolling, so this fix compacts the footer instead of adding a vertical scroller.
`AO3PreferencesView.helpButton` (`Features/Account/AO3PreferencesView.swift:251`)
uses a labeled help control with a 44 pt target. This change uses the existing hit
target helper and a native alert for its short, local explanation; no new shared
component is introduced.

## Regression coverage and handoff

`KudosTests/WritingTextEditorTests.swift:45`,
`fiveLinesStayVisibleAtTheLargestTextSize`, mounts the **real** editor in a
402×874 pt window and an inline-title NavigationStack, injects `.accessibility5`,
and supplies six short lines. It waits for the native buffer/layout, checks that
the editor has not become first responder and that its font really scaled above
30 pt, then obtains the fifth line's actual caret rectangle. Its bottom plus the
text container's bottom inset must fit inside the text view's bounds (`:80`).
This checks the available writing space using the editor's real fonts, paragraph
spacing, recovery status and tray, without copying footer layout into a harness.
The suite is serialized (`:6`) because its native editor tests share the key
window and keyboard.

Expected reversion failure: keep the test and restore the old wrapping recovery
status and full multiline footnote. At AX5 these consume the viewport shown in
A97, placing the fifth line's bottom outside the text view's bounds, failing the
last expectation. This red/green comparison was **not run**, per the task rules.

Checks performed: targeted `swiftlint lint --quiet --no-cache` on both changed
Swift files exits 0 with only the two pre-existing line-length warnings
(`WritingTextEditor.swift:186`, previously `:180`, and
`WritingTextEditorTests.swift:26`, previously `:25`). No lint rules or thresholds changed.
`git diff --check` passes.

Claude must run build/tests and the reversion comparison, inspect AX5 plus
normal-size screenshots (including the five-line target), tap Editor help, and
check VoiceOver's full recovery status. Keyboard-up editing, horizontal access
to the last formatting chips and Preview help/disabled formatting remain manual.
The pre-existing untracked `Packages`, `Vendor` and `docs/android-port/` content
is outside this fix and will be left intact.
