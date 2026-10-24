# Duo6 — choose layout by size class, not by device idiom

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-duo6` (from the iOS lane's
T-447, `e8036a77`). iOS only. Duo5 runs at the same time in `~/kudos-agent-ios2` (the reader's page box,
safe areas and remeasure in `ReadiumBook.swift`, `ReaderDismissDrag.swift`, `ReadiumReaderView.swift`'s
chrome padding): if you must touch `ReadiumReaderView.swift`, keep to the lines named below.

## Why

Apple's iPhone Duo guidance (checked, `~/kudos-android-lane/docs/android-port/briefs/Duo2-result.md`):
"don't choose a layout by idiom"; on the inner display (regular width and regular height in both
orientations) the app should look like a natural extension of its iPad layout. Your Duo3 audit
(`~/kudos-agent-gemini2/docs/android-port/briefs/Duo3-result.md`, findings 3 and 4) found the three idiom
gates that keep the Duo on phone layouts:
- `Settings/SettingsView.swift:103–111,128–130`: the Two-page spread toggle is offered only off-phone;
- `Features/ReaderReadium/ReadiumReaderView.swift:1435–1436,1469–1477`: `columnCount` is `.one` on phones;
- `UIComponents/FilterPanelPresentation.swift:37–47`: phones always get a sheet, never the inspector.

## What to do

1. Replace each gate with the **size classes** of the view it decides for: the wide behaviour (spread
   offered and honoured; filters as an inspector) when the horizontal **and** vertical size classes are both
   `.regular`, the phone behaviour otherwise. That keeps every current iPhone unchanged (a Pro Max in
   landscape is regular width but compact height) and the iPad unchanged full screen; in a narrow iPad
   multitasking window the phone behaviour applies (the sheet the file's comments at `:6–28` say is safe
   in compact). The Duo's inner display gets the iPad behaviour.
2. Read the size classes where SwiftUI provides them (`@Environment`), and pass the decision into
   non-View code such as the style mapper; don't read `UIScreen`, the window or the device.
3. One small pure function for the decision, unit-tested for the four size-class combinations; the two
   reader settings keep their stored values.
4. Out of scope: the fold, Book pose, reserved regions, a gutter on the division (Duo3's 3 second half, 8,
   10, 11): those wait for the inner display. The queue browser's split (finding 5) too.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds and checks on the iPhone 17
  (unchanged), an iPad simulator (unchanged full screen) and later the Duo.
- No new UI elements; no setting is removed.

## Output

`docs/android-port/briefs/Duo6-result.md`, written first and kept current: each change (file:line), the
tests and how they fail when reverted, and what Claude must check on each device.
