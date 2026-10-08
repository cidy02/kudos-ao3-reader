# Audit A2: the parity index, iOS screens against Android

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A2-result.md`.

This is an **index**, not a verdict: Claude checks every line he acts on. So be exact about
what you saw and where, and never infer. If you did not open a file, do not describe it.

## Sources

- iOS: `kudos-ao3-reader/Features/` in this worktree (every `.swift` file in every folder),
  with `docs/ARCHITECTURE_MAP.md` and `.claude-overnight/polish/INVENTORY.md` (68 screens) as
  maps.
- Android: `android/app/src/main/java/io/github/cidy02/kudos/` (every package), and
  `android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt` and `AppNavHost.kt` for what
  can be reached.
- `docs/android-port/LIVING-PROMPT.md` §7 (the parity matrix) for what is believed today.

## What to produce

1. **One table for all of iOS `Features/`**, a row per Swift file that declares a screen or a
   sheet (a `View` presented by navigation, `.sheet` or `.fullScreenCover`): the iOS file; the
   Android file or files that are its counterpart, found by reading, with the composable's
   name; and one of `present`, `partial` (say in five words what is missing), `absent`,
   `opens AO3 in the browser`. Where you are not sure of the counterpart write `unsure` and the
   two candidates.
2. **For every row that is not `present`**, a short list of what iOS has that you did not find
   on Android, each with the iOS `path:line`: user-visible strings (button titles, row labels,
   section headers, alerts), and actions (a write to AO3, a navigation, a menu item). Search
   Android for each string before listing it; quote the search you made.
3. **Android screens with no iOS counterpart** (old Material screens still reachable from
   `AppNavHost.kt`, or unreachable files): the file, and whether a route reaches it.
4. **Matrix corrections:** rows of §7 that your table contradicts, each with the evidence.

Order the result so the most incomplete areas come first. Give counts at the top (files read
on each side, rows per status). End with what you did not read.
