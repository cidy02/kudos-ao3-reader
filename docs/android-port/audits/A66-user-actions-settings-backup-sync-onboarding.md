# A66: every action in Settings, Backup, Sync, Privacy, Onboarding, Support and sign-in, iOS against Android

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A66-result.md`. Leave no other file behind. **Write the priority list
first and keep it current.** Do not edit `TASKS.md`.

A52 to A61 compared iOS's **tests** with Android; A62 (Library, Work Detail, Reader), A63 (Home,
Search, Browse, Account, Comments, authors) and A64 (Writing, Challenges) compared **actions**.
No audit has compared the actions of the screens below; on 2026-10-16 only their labels were
compared (102 labels, 16 missing by their words, fixed in `2f00aa6a`). Owner direction
(binding): "Layout, content, order of information and behaviour stay in step with iOS.
Navigation and chrome controls are Android's own." So a missing action, or one that does
something different, is a finding; a different-looking control for the same action is not.
iOS is the source of truth: where iOS and an artboard differ, iOS wins.

**iOS (read-only):** `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:
- `Settings/` (all 15 files: hub, reading pages, storage pages, backup page and import sheet,
  sync folder page, pairing sheet, account pages, About, legal notices),
- `Features/Privacy/`, `Features/Onboarding/`, `Features/Support/`, `Features/Auth/`,
- and the services those screens call when it decides what an action does
  (`Services/KudosBackup*.swift`, `Services/*Sync*.swift`), read only as far as needed.

**Android:** this worktree (lane HEAD `28bcd3c5`), mainly
`android/app/src/main/java/io/github/cidy02/kudos/{settings,backup,onboarding,support,auth}/`
and whatever they call. Read `docs/android-port/DECISIONS.md` entries from 2026-10-10 on
first: some differences are recorded decisions, not findings. Also read
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` before judging backup, restore, replace, sync or
deletion: there, "different" usually means data loss.

For each iOS screen, list every user action it offers: buttons, toggles, pickers, menu and
context-menu items, swipe actions, long presses, toolbar items, sheet and alert actions,
empty-state actions, share and file-picker entries. For each, find Android's (quote both sides,
`path:line`) and mark it **same**, **different** (say what a reader would notice),
**missing**, or **Android only**. Note the confirmation, the undo and the message after it,
where iOS has one, and what the action does to stored data (which records, which files, which
settings) when that is where the two differ.

## Report

The priority list first: the **missing** and **different** actions worth fixing, one line
each, most harmful first (anything that loses a reader's data, library, place or settings;
anything that restores, replaces, syncs or deletes differently from iOS; anything done without
the confirmation iOS asks for; anything sent to AO3 the reader did not ask for; then missing
features; then wording). Then one table per screen. Say plainly where Android is right.

Work screen by screen and write each screen's table as you finish it, so a time limit leaves
what is done. Quote `path:line` on both sides or mark the row **unsure**.
