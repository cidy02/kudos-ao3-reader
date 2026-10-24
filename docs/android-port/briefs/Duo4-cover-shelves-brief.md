# Duo4 — the iPhone Duo's cover: shelves that run under the side rail, and the card clamp

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-duo4` (from the iOS lane's
tip, which includes T-446). iOS only.

## Why

Android parity is done; the owner's focus is now optimizing Kudos for iPhone Duo. On the Duo's cover
(closed, 466×678 pt), the iOS 27.1 SDK puts the tab bar and the toolbar on a **vertical rail at the right
edge**. Claude-CLI shot 22 screens there (`~/kudos-tools/out/duo/cover-sheet-1.png`, `cover-sheet-2.png`,
notes `~/kudos-tools/out/duo/cover-notes.md`): lists and forms respect the rail, but horizontal rows run
under it at rest, and their last item sits beneath the rail's buttons:
- `library`: the Reading Now carousel (its third card under the +, filter and … buttons) and the fandom
  chip row;
- `home`: Continue Reading's second card and the Reading Queues deck row;
- `queues`: the queue chip row.

Your Duo3 audit (`~/kudos-agent-gemini2/docs/android-port/briefs/Duo3-result.md`) traced the cause:
finding 1 (`UIComponents/WorkCarouselSection.swift:93–101`, `.scrollClipDisabled()`; Continue Reading
repeats it at `Features/Home/HomeView.swift:442`) and finding 2 (`UIComponents/CarouselCardStyle.swift:80–98`
clamps cards to `UIScreen.main.bounds.width - 32`).

## What to do

1. Every horizontal shelf and chip row named above (and any other that shares the same pattern: find them
   all) stays inside its container's usable width: at rest nothing paints under the side rail, and the last
   item can scroll fully clear of it. Keep the card shadows (vertical room) and the iPhone's current look on
   a normal phone, where the rows reach the screen edge: use the safe area / bar geometry SwiftUI gives
   (`safeAreaInsets`, `contentMargins`, `scrollClipDisabled` only where it can't reach the rail), not a
   guessed rail width, and not a device or idiom check.
2. The card clamp measures the space it is in (the container's width), not the screen.
3. Out of scope for now: the reader, the fold, the inner display and its Book pose (Duo3's findings 3, 5,
   7–11, 16), the download banner and toolbar items (12–14): Claude confirms those on the simulator first.
4. Tests where the code allows: the clamp's arithmetic from a given width; anything else as a note of what
   Claude must check on the simulator.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. No `Packages` or `Vendor` here: nothing builds; Claude builds,
  gates and shoots in `~/kudos-ios-polish`, on the iPhone 17 and on the Duo's cover.
- Don't lose density or information (AGENTS.md); no new UI elements.

## Output

`docs/android-port/briefs/Duo4-result.md`, written first and kept current: each change (file:line), why it
can't reach the rail, what an iPhone 17 shows before and after (should be unchanged), the tests and how they
fail when reverted, and the screens Claude must shoot on both devices.
