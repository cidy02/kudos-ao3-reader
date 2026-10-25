# 3hh: destructive and error marks use iOS's system red (A102)

Same setup as 3he–3hg; their briefs are in this worktree's `docs/android-port/briefs/`.
- **Where:** `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3he`, now at 3hg `fd791da1`.
- **Rules:** no Gradle, no sign-in or AO3 traffic, no schema or backup changes, never revert anyone's work.
- **Committing:** if the git index can't be written, leave the edits uncommitted and say so.
- **Report:** write `docs/android-port/audits/3hh-result.md`.

## What the verification found
The iPhone draws every destructive or error mark in the system red, whatever the app accent and whatever the theme.
That covers `role: .destructive` buttons and menu items, `.foregroundStyle(.red)` and `Color.red` (about 180 sites in
`kudos-ao3-reader/`). Measured on the iPhone (iOS 26):
- Light and Sepia: (255,56,60), `#FF383C`;
- Dark and OLED: (255,66,69), `#FF4245`.

Measured on series remove's ⊖ and on recovery's "Delete this local copy", in every column.

Android uses two other reds, and neither matches:
- `SubjectPalette.fromHue(0.0, theme).accent` at 33 sites: (219,114,114) in Dark and OLED, (133,37,37) in Light, and
  (122,49,49) in Sepia.
- Material's default `colorScheme.error` at 51 sites (never set in `ui/theme/Theme.kt`).

Some destructive actions just use the app's accent, recovery's Delete for one. With a non-red accent they would draw
teal or purple. No decision covers any of this.

## The change
1. **One destructive colour.** Add a single source, e.g. `val destructive: Color` on `KudosTokens` (or a
   `ReaderTheme` property, whichever fits the existing code better). It is `#FF383C` for Light and Sepia and `#FF4245`
   for Dark and OLED. Also set Material's `colorScheme.error` to it in all four schemes in `ui/theme/Theme.kt`, so
   every `colorScheme.error` use follows. Pick `onError` for contrast with `SubjectPalette.label(...)`. Check that
   nothing that uses `colorScheme.error` means something other than error or destructive.
2. **Replace the 33 `fromHue(0.0, …)` sites** that mean destructive or error with the new colour: delete, remove,
   revoke, refusal, error messages, warning icons, "Save and reveal" (a destructive-confirm on iOS? check). Where a
   whole red palette is passed (`AO3TagSetScreen.kt:197`, `:223`, `:233`), give it the destructive colour as its
   exact tint, e.g. `SubjectPalette.fromColor(destructive, theme)`, so its fills and text agree. Leave
   non-destructive hue uses, such as `"DEFAULTED" -> fromHue(0.08, …)` in `AO3ChallengeAssignmentsScreen.kt:164`, as
   they are.
3. **Audit Android's destructive actions against iOS's `role: .destructive`.** Grep iOS for `role: .destructive`
   and `.red`; for each, find the Android counterpart (a row, menu item, dialog confirm button or swipe action) and
   make sure it draws in the destructive colour, not the app accent or `primaryInk`. Known examples:
   - recovery's "Delete this local copy" (`writing/WritingTextEditorScreen.kt`, the recovery sheet);
   - the queue tag manager's "Remove from this queue";
   - Log Out and Delete confirmations.

   List every pair you checked in the report, changed or not. Swipe actions that already use `colorScheme.error`
   follow step 1 automatically.

## Tests
- A test that the destructive colour is `#FF383C` in Light and Sepia and `#FF4245` in Dark and OLED, and that
  `MaterialTheme.colorScheme.error` equals it under `KudosTheme` in each mode.
- One rendered check on a real screen: series remove's ⊖ or recovery's Delete text colour, in all four themes. It
  must fail with the old colour.
- Update any existing test that asserted the old hue-0 colour, and say which.
