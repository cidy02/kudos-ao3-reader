# D8 — record round 2's accepted platform differences in DECISIONS.md

**Agent:** Sonnet 5.5 (agy account 2). **Worktree:** `~/kudos-agent-gemini2`, branch `android/agent-sonnet-d8`
(from the lane's `edf3d2fd`). Documentation only: one file changes, `docs/android-port/DECISIONS.md`.

## Why

Claude-CLI judged round 2's re-shot pairs (tiles in `~/kudos-tools/pairs/tiles-r2/`). These small
differences remain; each loses nothing and is Android's own idiom or the demo data, so they are accepted and
need one dated entry, as D7 did for A97 (read D7's entry, the last one in the file, and follow its form).

## The accepted differences

1. `pagejump`: First page and Last are plain text buttons on Android, filled pills on the iPhone; both use
   primary ink since A98.
2. `chapterpicker`: Android's chapter glyph is Material's open-book outline (`ImportContacts`) and its row
   titles are semibold accent; the iPhone uses SF Symbols' `book` and regular accent titles. The comments
   screen's demo work is "A Test Work" on Android and "Sodium Lights" on the iPhone (demo data).
3. `recovery`: the saved time is the platform's short date style, "10/22/26 10:57 PM" on Android and
   "10/22/2026, 8:50 PM" on the iPhone.
4. `chsettingsedit`: both apps hue the page from the challenge's title, else its slug (A98). The iPhone's
   demo challenge has no title, so it shows the slug and teal; Android's has one, so it shows the title and
   its own hue (demo data).
5. `thread`: Android's page label is the demo work's title ("A TEST WORK"), the iPhone's "SODIUM LIGHTS"
   (demo data); the thread itself matches.

## What to write

Append one entry at the end of `docs/android-port/DECISIONS.md`:
`2026-10-23 · Round 2's accepted platform differences (Claude-CLI's judgement, recorded by Sonnet D8)`. For
each item, one line on what differs and why it is accepted, and the Android code that draws it
(`path:line`, found under `android/app/src/main/java/io/github/cidy02/kudos/`). End with how to reverse and
where the tiles are.

## Rules

Change only `DECISIONS.md`. Do not commit, push, switch branches, build, sign in, contact
archiveofourown.org, or edit `TASKS.md`. Don't add items beyond these five.

## Output

Write `docs/android-port/briefs/D8-result.md` first: the entry, and how you found each `path:line`.
