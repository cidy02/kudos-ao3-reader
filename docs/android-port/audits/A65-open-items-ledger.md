# A65: the ledger of what is still open on Android (an index; Claude verifies)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A65-result.md`. Leave no other file behind. Do not edit `TASKS.md`.

The Android lane is at `28bcd3c5` (this worktree). Over 2026-10-08 to 2026-10-16 the loop left
"deferred", "not addressed", "excluded", "owed", "not seen", "left", "lead" and "P3, not
changed" notes in many files. Some were closed later; many were not. Build one ledger of the
ones that are **still open**, so the next sprint works from a list instead of archaeology.

## Read, in this order

1. `docs/android-port/LIVING-PROMPT.md` §7 (parity matrix), §10 (task queue), §11 (owner
   questions), §12 (status log, newest first: a later line often closes an earlier note).
2. Every `docs/android-port/briefs/3e*-result.md`, `3f*-result.md` and every
   `docs/android-port/audits/A49-result.md` … `A64-result.md` (their "deferred", "stop point",
   "remaining", "not addressed", "excluded" and priority-list sections first).
3. `docs/android-port/DECISIONS.md` entries from 2026-10-10 on (a recorded decision closes a
   difference: mark it CLOSED-BY-DECISION and quote the entry's first line).
4. `git log --oneline 1da8f5fa..28bcd3c5` (read the log only, never check anything out) to
   match a note to the commit that closed it.

## For each open-looking note, one row

| # | Note (quote, ≤25 words) | Where (`file:line`) | Kind | Closed by (quote + `file:line` or commit) | Verdict |

- **Kind:** `code` (an Android change iOS already has), `verify` (a look on the emulator or
  beside the iPhone, no code), `owner` (waits on an owner question: name its §11 number),
  `device` (needs a real phone, a real AO3 account, or sound), `ios` (an iOS-only item),
  `design` (no iOS behaviour to copy).
- **Verdict:** `OPEN`, `CLOSED` (quote what closed it), `CLOSED-BY-DECISION`, or `UNSURE`.
  Never mark CLOSED without a quote.
- For `code` rows, also name the Android file most likely touched and the iOS file it should
  match, each as `path:line` if you can find it in this worktree / in
  `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). If you cannot, write `?`.

## Report

First a short list: every `OPEN` `code` row, most harmful to a reader first (lost text, place or
work; wrong work acted on; a write AO3 should not get; then missing features; then looks and
wording). Then the `OPEN` `verify` rows grouped by §7 area. Then the full table. Keep the file
under 60 KB. Write as you go, so a time limit leaves what is done.
