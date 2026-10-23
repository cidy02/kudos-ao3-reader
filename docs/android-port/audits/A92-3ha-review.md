# Review A92 (read-only): Codex's Android batch 3ha against the iPhone

Read only: change no file except your note; no builds, no Gradle, no git commands that change anything, no
sign-in, no AO3. Write `/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A92-result.md`.

**What:** Codex's 3ha, uncommitted in `/Users/cidy02/kudos-agent-codex` (branch `android/agent-codex-3ha`,
base the lane's `46a50158`; `git -C /Users/cidy02/kudos-agent-codex diff` plus the untracked
`Brief3haContentTest.kt`). The same diff is applied, uncommitted, in `/Users/cidy02/kudos-android-lane`.
Its brief: `docs/android-port/briefs/3ha-a88b-android.md` (and `3ha-finish.md`); its account:
`3ha-result.md` there. Two of Codex's turns overlapped on this worktree; the third reconciled them, so look
for leftovers (duplicated logic, half-applied changes, dead code).

As in A89, with `file:line` on both sides, P1/P2/P3 and a concrete failing case:
1. Lost behaviour or information against DECISIONS.md and iOS (series detail's card and work figures, the
   challenge settings' subtitle and pinned Save, bulk names, author bookmarks, sheet grounds, availability,
   privacy's wash, the chapter-form DEBUG route).
2. Wrong parity (read the iOS file each item cites).
3. AO3 traffic: `AO3SeriesRepository` now parses a Restricted flag and zero figures from pages it already
   reads; confirm no new or repeated request, and that the sign-up count adds no read (owner decision 16:
   show it only when already known).
4. Tests: does each fail with its change reverted? Name any that wouldn't.

End with one line of counts. Message me when done.
