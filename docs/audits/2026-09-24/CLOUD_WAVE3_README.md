# Wave 3 (cloud): how these files were made

Written by a Claude session in a Linux cloud container on 2026-09-25,
working the handoff "Redesign handoff: finishing the remaining items" on
branch `cloud/redesign-finish`.

## What was missing, and what that changes

The handoff says to read `docs/audits/2026-09-24/AUDIT_METHOD.md` and to
append to `otwarchive-facts.json` (Q1–Q10 already answered). **Neither file,
nor any of `critic-wave2.json`, `writing.json`, `history-favorites-queues.json`,
`challenges.json`, or the collections/account-settings JSONs, was on origin.**
`origin/review/codex-item12` was still at `c4ce1e2`, and none of the handoff's
T-246…T-255 commits (`f9d00e36` … `e32fba77`) existed in any ref.

So:

- **Base.** Everything here was audited at `c4ce1e2`. Where a board is known to
  be changed by an unpushed Mac commit, the board says so. The big one is **1f
  (comments)**: T-247 rebuilt the thread rendering on the Mac, so 1f's threading
  verdict in `browse-workdetail-comments.json` describes the pre-T-247 code.
- **Method.** Reconstructed from the handoff's own words and
  `docs/REDESIGN_PLAN.md` §4 (Unattended-run policy, the fidelity sweep, and
  "A number on an artboard is a drawing, not a source"):
  1. Read the board: `Scripts/redesign-spec-outline.py --board <id>` and its
     label and "Needs building" note.
  2. Find the screen from a real call site (entry point), not from a folder
     name or a plan row.
  3. Check each element the board draws against the code that renders it, and
     each figure against where the number comes from. A figure must be sourced
     or dropped; a page count is not a total; a failure is not "empty".
  4. Record one item per element or finding, with `file:line` evidence.
     Earlier plan rows (the T-219 table in `REDESIGN_PLAN.md`) were treated as
     claims to check, never as evidence.
- **JSON shape.** My own, because the real one was not available. It is
  described in each file's `status_vocabulary`. If the Mac's shape differs,
  the fields map one to one: `status`, `size`, `evidence`, `spec`,
  `failure_scenario`, `fix`, `test`.
- **otwarchive facts.** Written to `otwarchive-facts-wave3.json`, starting at
  Q11 as instructed, with the entry shape the handoff gives (`q`, `answer`,
  `sources`, `quote`, `implication`). Append its entries to
  `otwarchive-facts.json` when the two branches meet.
- **C2 brief (collections-moderation + account-settings-collections).** Its
  inputs are the missing JSONs plus `critic-wave2.json`. See `brief-C2.md` for
  what could and could not be done without them.

## Sources

- The spec: `docs/design/Final_Redesign_Spec.dc.html` (byte-identical to the
  owner's upload `Final_Redesign_Spec.dc_2.html`, md5 `2fd2924a…`).
- AO3's own code: otwarchive at `00ad85b4` (master, 2026-09-10), read from a
  shallow clone. Citations are `path:line` in that tree.
- No AO3 page was fetched, and nothing was signed in to.

## Nothing here was built, run, or seen

No Xcode, no macOS SDK, no simulator. A `DONE` means "the source draws it", not
"it looks right". The owner's screenshot gate applies to all of it.
