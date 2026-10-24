# Duo3 — where the iPhone app's layout will break on iPhone Duo (read-only audit)

**Agent:** Codex. **Worktree:** `~/kudos-agent-gemini2` (write only the result file there).
**Source to read (read-only):** `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` at `d3e66077`.

## Why

Android parity is done (2026-10-24). The owner's next focus is optimizing Kudos for iPhone Duo (owner,
2026-10-23: "After android parity is complete we will be focusing all our efforts in optimizing the app
for iPhone Duo"). Before any Duo code is written, we need a map of what will break.

## What Apple says (checked; `~/kudos-android-lane/docs/android-port/briefs/Duo2-result.md`)

- An app built with the iOS 27.1 SDK (Kudos is) gets the whole display. Cover (closed): 466×678 pt.
  Inner (open): 951×669 pt landscape, 669×951 portrait, **regular in both size classes**.
- Tab bars and toolbars move to the **side** (vertical, below the status bar) except on the inner display
  in portrait. On the simulator, Kudos's tab bar is a vertical bar on the right edge of the cover, and the
  Home queue row's last card runs under it (`~/kudos-tools/out/duo/duo-home-light-s1.png`).
- "Don't choose a layout by idiom"; "the device's orientation doesn't tell you what shape your app is"; use
  size classes and the space you're given. On the inner display the app should look like a natural
  extension of its iPad layout.
- The fold is a reserved region (`ReservedRegion`, kind `division`, about 40 pt wide down the middle of the
  inner display, active in the Book pose). Framework views (split views, sheets) avoid it; custom views
  that place their own content must arrange around it. `onHingeChange`, `DeviceHingeContext`, UIKit's
  `UIHinge` exist in the 27.1 SDK.

## What to find (file:line for every item, with the code quoted)

1. Layout chosen by **idiom** or device model (`userInterfaceIdiom`, `UIDevice`, `.pad`/`.phone`, model
   strings) where size classes or the given size should decide.
2. **Fixed sizes and screen reads** that assume a phone's shape: `UIScreen.main.bounds`, hard-coded widths
   or heights, aspect-ratio assumptions, `GeometryReader` math that assumes portrait.
3. **Bottom-bar assumptions:** content insets, padding or overlays computed for a bottom tab bar or a
   bottom toolbar (e.g. a fixed bottom inset, a custom mini-player or floating button placed above the
   tab bar) that will be wrong when the bars are vertical on the side. Start from the Home queue row.
4. **Compact-only paths:** places that check `horizontalSizeClass == .compact` and fall back to something
   that would look wrong regular-width on a phone (the inner display is regular/regular).
5. **The reader** (`Features/ReaderReadium/`, `Features/Reader/`): how its pagination, columns and
   controls would meet the fold and a 951 pt-wide landscape page. Is there any two-page/spread setting in
   Readium's preferences already wired?
6. **Custom full-width views** that would put content across the fold: hero headers, carousels, the
   stacked queue deck, custom sheets/overlays.

## Output

`docs/android-port/briefs/Duo3-result.md` in this worktree. Write it first and keep it current. For each
finding: file:line, quoted code, which Duo state breaks (cover, inner portrait, inner landscape, Book pose),
what would go wrong, a severity (P1 broken or unreadable, P2 clearly wrong, P3 polish), and the smallest
fix you'd suggest. End with the three or four changes that would fix the most, in order.

## Rules

Read-only. Do not edit any source, commit, push, switch branches, build, sign in, contact
archiveofourown.org, or edit `TASKS.md`. Claude builds and checks on the Duo simulator.
