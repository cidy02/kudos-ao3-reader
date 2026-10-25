# I22: iPhone fixes from the parity verification, batch 3 (A102)

Same setup as I21 (`docs/android-port/briefs/I21-a102-iphone.md`):
- **Worktree and branch:** `/Users/cidy02/kudos-agent-ios4`, branch `claude/parity-i21`, which now holds I21 as commit
  `8ad7a90e` (T-456, committed by Claude-Code).
- **Rules:**
  - Don't build, test or touch a simulator.
  - No sign-in or AO3 traffic.
  - No `project.pbxproj` edits; don't commit the `Packages` or `Vendor` symlinks.
  - Match the hand-wrapped style.
- **Committing:** if your sandbox can't write the git index, leave the edits uncommitted and say so.
- **Report:** write `docs/android-port/briefs/I22-result.md` in the same shape as I21's.

## 1. The AO3 filter panel takes the app accent
Over the search results page, the filter sheet's language page draws its tick in the page's amber: (216,168,112) in
Dark, (128,80,32) in Light. Android draws it in the app accent. `AO3FilterPanel`'s hosts all sit under
`.screenTint(resultsPalette)`:
- `Features/Search/SearchView.swift:689` (`filterPanel`);
- `Features/Browse/NativeBrowseView.swift:259` and `:614`.

So the sheet inherits the results' hue, which T-446's rule ("scope surfaces use the app accent", Sepia's brown in
Sepia) doesn't allow. Apply I21's `ScopeSurfaceAccent` (`UIComponents/AccentInk.swift`) once, inside
`AO3FilterPanel`'s presentation root, so every host and every page pushed inside the sheet (language, tags, fandoms
and so on) gets it. I21 did the same inside `WorkBulkTagSheet`.

The author works filter sheet already shows the exact app red, so it should be unchanged. Check that the inspector
column on iPad and macOS isn't affected in a way that breaks the macOS build (keep the `#if os(iOS)` guard the
modifier uses).

**Test:** extend `KudosTests/AccentInkTests.swift` the way I21 did, so it fails if the panel's root loses the modifier.

## 2. The AO3 Collections filter sheet shows its wash in every theme
`Features/Account/AO3CollectionsFilterPanel.swift:48` asks for `.subjectScreenWash(palette: theme.scopePalette)`, but the
wash shows only in Light. In Light the sheet's top is pink (228,205,210), fading to (242,242,247). In Dark, Sepia and
OLED it is flat: (22,22,27), (236,222,193) and (0,0,0) right from the top. Something paints an opaque ground over the
wash in those three themes, most likely the form's themed scroll background.

`Features/Account/AccountInboxFilterSheet.swift:66` uses the same wash, and its wash shows in all four themes, (61,7,8)
at the top in Dark. Compare the two and make the collections sheet behave like the inbox sheet. Fix the cause, which
may be shared by other sheets with a Form under a wash; if it is, say which.

## Report
Per item:
- what you changed (`path:line`);
- the test, or why there isn't one;
- anything you think the brief got wrong.
