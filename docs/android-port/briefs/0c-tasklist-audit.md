READ-ONLY audit. Do not edit, create or delete files. Do not run git commands that write (no checkout, cherry-pick, stash, reset or commit). Do not build or touch the network. Read-only git commands (`git show`, `git log`, `git diff`, `git grep`) are fine.

Repo: `/Users/cidy02/kudos-android-redesign`. The base is the working tree on branch `android/redesign-parity` (Android app under `android/`). Branch `android/tasklist-15-reports` has three commits the base lacks:
- `3c0c1cc7` "close 10 items from the 15-issue cross-platform report"
- `fe799218` "restore the real WebView scrollbar; refine detailed card stats"
- `a2fc89d5` "bring the work card's stat row to parity with iOS"

They were written on top of release 0.2.0 (`873f38b7`). The base is newer: it has the 0.2.1 work (for example `bb165940` "Networking: stop the unattended full-library AO3 sweeps", `4a19bc13` "Updates: tell the user what changed", `6d3adbad` "add the page scrubber") plus later security work. Cherry-picking produces 13 conflicting files, so each item has to be judged on its own.

For each item below, read its hunks (`git show <sha> -- <paths>`) and the base's current code. Decide:
- **HAVE**: the base already does it, perhaps differently. Cite the base file and line.
- **MISSING**: the base lacks it, and nothing on the base contradicts it. List exactly which hunks to port and where they land in the base's current code.
- **CONTRADICTED**: a later base change deliberately does the opposite. Cite that commit or code and say why.
- **PARTIAL**: say what is missing.

Items in `3c0c1cc7` (from its message):
- **G**: hard-delete cleans up annotations and queue memberships, and tombstones deleted annotations.
- **D1**: the update checker's default candidate set is the full library. Check this against `bb165940`.
- **A1**: `disablePageTurnsWhileScrolling` on the Readium navigator.
- **B2**: `collectLocalTagSuggestions` wired into SearchScreen.
- **C1**: update and publish dates on remote work cards, plus the `datePublished` and `dateUpdated` fields and migration on the local SavedWork. The base's Room schema is now version 10 (7→8 preservation, 8→9 tombstone signatures, 9→10 hasGivenKudos), so any new column needs MIGRATION_10_11. Say which columns and types.
- **E1**: shake-to-report requires a direction reversal.
- **F**: GitHub release notes surfaced.
- **D2**: availability sweep hardening (recheck interval, pacing, limit, cancellation) and its screen with a list of affected works.
- **A5**: a scrub-origin tick on the reader progress slider.
- **H1**: batch select and scoped removal on the Reading Queue and Collection detail screens.

Then do the same for `fe799218` and `a2fc89d5`, item by item, from their commit messages.

Also check the iOS app (`kudos-ao3-reader/`) for each MISSING item: does iOS have the behaviour? Name the iOS file. The port's goal is parity with iOS, so a MISSING item iOS lacks is lower priority.

Output a markdown table:

| Item | Verdict | Evidence (base file:line / commit) | iOS has it? (file) | Port notes (hunks, target files) |

Then a short recommended port list in order. Under 1,500 words. Cite only what you read.
