# A37: three screens you wrote, reviewed as they landed

**Read-only.** Change no source file anywhere. Do not build, commit, push, switch branches, sign
in or contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A37-result.md`. No helper scripts left behind.

You wrote briefs 3cc, 3cd and 3ce on 2026-10-09. Claude landed each the same evening on a Mac
that was out of memory: each was gated, none was read whole, and none was seen on the emulator
before landing. Each landing note (`docs/android-port/briefs/3cc-result.md`, `3cd-result.md`,
`3ce-result.md`, the section "Landing note") says what Claude changed and what was not read.
Review what is in the lane now, not what you handed over. For every finding: the code quoted
(`path:line`), a severity (P1 data loss or a wrong write to AO3; P2 wrong behaviour a reader
meets; P3 the rest), the exact inputs or taps that fail, and the smallest fix. Where the lane is
right, say "no fault" in one line and move on. iOS's code at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` is the reference; say where Android differs
from it and whether the landing note already records that difference.

## 3cc, assignments: `git show c161a0bb -- android/app/src`

1. Claude's four landing changes. (a) A moderator is no longer turned away and the lists are
   asked for: can a participant now reach a read iOS would not make, or a control that sends a
   write AO3 will refuse? (b) "AO3's first refusal stops the other lists": which errors count
   as a refusal, and can a refusal on one list hide another list that had loaded? (c) The
   owner's failed settings read can be tried again: can the retry run twice at once, or run
   while a write is out? (d) The "Load more" labels.
2. Claim a pinch hit and Report a default: each request against iOS's
   (`Services/AO3ChallengeActions.swift`) field for field, the token's source, the verdict.
   After a POST whose answer never arrives, what does the screen say and what does a second
   tap send? After a session change between the tap and the POST?
3. The lists are read again after a write. Can a late read from before the write overwrite the
   lists read after it? Can "Load more" on one list race the re-read and duplicate or drop
   rows (two rows with one key crashes a lazy list)?
4. The demo's answers for these lists and writes in `network/ao3/DemoNetwork.kt`: does any
   address this patch claims belong to another screen's fixture (Challenge Settings reads the
   sign-ups page; the Moderation screen reads the items page)?

## 3cd, own works and Edit multiple works: `git show 9e1fa2a8 -- android/app/src`

5. `network/ao3/writing/AO3BulkEdit.kt`, not read by Claude: the parser of AO3's Edit Multiple
   Works page and the diff it produces. For each served group (rating, warnings, categories,
   language, the tag kinds, collections, creators, visibility, comment settings): what an
   untouched group sends (it must send nothing), what a cleared one sends, what a group AO3
   did not serve does. Any value that is trimmed, lower-cased, deduplicated or re-ordered on
   the way out. Against iOS's `EditMultipleWorksView.swift` and its encoder.
6. The per-work tag run followed by the one uniform POST: if the run stops at work 3 of 7, is
   the uniform POST still sent? Should it be (what does iOS do)? What is on screen, and what
   does Save send if tapped again: the four not yet done, or all seven?
7. Bulk delete: the confirmation names the count and the titles. Are the ids sent exactly the
   ones named (a selection changed while the dialog is open; a work that left the list after
   a refresh)? One POST or one per work, and what if AO3 deletes some and refuses the rest?
8. Selection mode on the writer's own Works (`author/OwnWorksControls.kt`,
   `author/AuthorProfileScreen.kt` after the hand merge with 3ce): is it ever offered on
   another author's works, on a pseud that is not the reader's, or to a signed-out reader? Does
   a selection survive a page turn, a refresh or a session change, and should it?
9. The two screens' layout code, not read: anything that drops a control at large text or in
   a narrow window, any text with no line height, any stock Material colour.

## 3ce, the page cache: `git show f0bda512 -- android/app/src`

10. The four screens' banner wiring, not read: for each (author profile, Inbox, series, and
    the fourth: name it), when does "Showing cached AO3 data" appear and when does it leave?
    Can it stay over a page that has since been read fresh? Can a fresh read that fails after
    a cached one was shown replace the page with an error?
11. The Inbox's removals, not read: after each Inbox write (mark read, mark unread, delete,
    the bulk actions) which cached pages are removed? Any page of the Inbox that survives and
    would show a deleted comment, or a read state the reader just changed?
12. Claude's merge: 3cd's reloads pass `bypassCache = true`. List every other write in the app
    whose screen then re-reads a page that this cache can answer (a comment posted then the
    thread; a collection item approved then the list; Unsubscribe; a sign-up withdrawn; a
    work edited then its page) and say for each whether the re-read can be answered with the
    page from before the write. This is the fault most likely to be here.
13. `AO3PageCache.kt` keys by address, viewer name and session. Two readers of one address at
    once (Home and a pushed screen): one read or two, and can one's failure give the other a
    stale page marked fresh? Is anything kept when the session moved on while the read was out?
14. Tests: `AO3SeriesRepositoryTest` was sharing the default cache. Name every other test
    that builds a repository with the default cache and could pass or fail by the order it
    runs in.

If you run short of time: 12 first, then 5 and 6, then 2 and 3, then the rest; write the file
with what you have verified. A partial file with true verdicts is worth more than none.
