# Brief 3aj: demo fixtures for three things that cannot be seen on the emulator

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only, and demo data only.** Nothing here may change what the app does outside the
demo (`kudosDemoLibrary` launch extra): no production screen, repository or network path gets a
new branch for it. The demo never reaches AO3; `network/ao3/DemoNetwork.kt` maps AO3 address
patterns to fixtures and the demo library is seeded in code (find `DemoLibrary`). Read how the
existing fixtures are built and add to them in the same way. iOS's demo library is the
reference for what the demo holds (`/Users/cidy02/kudos-ios-polish/`, read-only): where iOS's
demo already has the thing, use its names and numbers.

Write `docs/android-port/briefs/3aj-result.md` as you go.

## 1. A work with several chapters, for the reader's Find in Work

Every EPUB in the Android demo has one chapter, so the reader's Find in Work (landed
2026-10-05, `reader/ReaderSearchSheet.kt`) has never been seen grouping results by chapter,
pinning "This Chapter (Ch. N)" above the others, or paging toward the current chapter. Give one
demo work an EPUB with a preface, at least six story chapters and an afterword, where:

- one ordinary word appears in every chapter, and another in exactly two that are not adjacent;
- one chapter holds more than 200 matches of a one-letter query;
- the text is original filler written for the fixture (no copied prose, nothing from AO3).

Build it with whatever the demo already uses to make its EPUBs; do not add a binary file to the
repository if the existing fixtures are generated in code. Keep the other demo works as they
are, and keep the work the screenshot scripts open ("Sodium Lights") a one-chapter work unless
it is the natural one to extend: say which work you changed and why.

## 2. Subscriptions with chapter counts, for Mark All as Seen

The account list's Mark All as Seen (`account/AccountWorksListScreen.kt`, brief 3w) only shows
when a subscription has chapters the reader has not seen, and the demo's subscriptions carry no
chapter counts. Give the demo's Subscriptions page works whose looked-up metadata has chapter
counts, with at least two that have new chapters since they were last seen and one that does
not, so the badges and the action show. The lookups go through the demo network like every
other request: add fixtures for the addresses the page asks for, and say which.

## 3. A paired device, for the Backup page's pairing section

The pairing section (`backup/PairingSheet.kt`, `PairingCard`) shows a row for each paired device
and a dialog to revoke one; the demo has no paired device, so neither has been seen. Seed one
paired device in the demo, through whatever store the real pairing writes to, with a name and a
date. It must be a device that cannot be used for anything: a key generated for the fixture,
never one that exists elsewhere. Say what a revoke does to it in the demo.

## For each of the three

Say how to reach it on the emulator in one line (which route or which taps), and add or extend
one test that fails if the fixture goes missing (the demo network and the demo library have
tests: follow them).
