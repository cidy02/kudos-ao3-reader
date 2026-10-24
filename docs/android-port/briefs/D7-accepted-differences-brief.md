# D7 — record A97's accepted platform differences in DECISIONS.md

**Agent:** Sonnet 5.5 (agy account 2). **Worktree:** `~/kudos-agent-gemini2`, branch `android/agent-sonnet-d7`
(from the lane's `e347c8d2`). Documentation only: one file changes, `docs/android-port/DECISIONS.md`.

## Why

The owner wants Android at parity with iOS so the team can move on. A parity row closes when its screen
pairs show no real difference and every small one is either fixed or written down as an accepted platform
difference. Claude-CLI judged A97's 38 pairs (`~/kudos-tools/out/a97/A97-claude-notes.md`) and decided the
items below are accepted: each loses no information and is Android's own idiom (Material controls,
Android chrome) or the demo data differing. They need one dated entry so later passes don't report them
again.

## The accepted differences

1. `chapterform`, `chsettingsedit`: a date is a value with a chevron opening Material's date picker on
   Android, a pair of date and time pills on the iPhone.
2. `bulknames`: Android shows a large page title with its section label ("AO3 ACCOUNT"), the iPhone a small
   inline bar title.
3. `revokedevice`: Android asks in a dialog over Sync Folder, the iPhone in a sheet.
4. `addworks`: Android's sheet is part-height with checkboxes, the iPhone's full-height with circles.
5. `readerdisplay`: Android's sheet is full height over the reader and its text-size slider is Material's
   stepped slider.
6. `collectiondetails`, `newcollection`, `newqueue`: Android's text fields are Material outlined fields with
   their labels above; `collectiondetails` is a pushed page on Android, a sheet on the iPhone.
7. `tagworks`, `fandomworks`: at 2.0× Android's pager keeps "Page 1 / 3", the iPhone's AX5 pill shortens to
   "1 / 3"; both are whole.
8. `pronunciations`: Android opens it as a sheet over the speech settings, the iPhone as a pushed page; its
   footnote about the voice pack is Android's own (Android's engines differ).
9. Demo data that differ between the apps (different works, counts, chosen fandoms, highlight text): not a
   difference between the apps.

## What to write

Append one entry at the end of `docs/android-port/DECISIONS.md`, in the file's format (read the last few
entries first: `- **2026-10-23 · …**` then indented bullets). Title it
`2026-10-23 · A97's accepted platform differences (Claude-CLI's judgement, recorded by Sonnet D7)`. For each
item: one line saying what differs and why it is accepted, and the Android file that draws it
(`path:line`, found by searching `android/app/src/main/java/io/github/cidy02/kudos/`). End with how to
reverse ("port the iPhone's form if the owner prefers it") and that the tiles are in
`~/kudos-tools/pairs/tiles-a97/`.

## Rules

- Change only `DECISIONS.md`. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Don't add items beyond the nine above.

## Output

Write `docs/android-port/briefs/D7-result.md` first: the entry you added, and for each item the
`path:line` you cited and how you found it.
