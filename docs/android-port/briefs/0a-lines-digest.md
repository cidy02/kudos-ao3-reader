You are helping reconcile four diverged lines of the Kudos Android app (Kotlin, Jetpack Compose, Room) into one base. Work only inside the workspace `~/kudos-android-redesign`. Do not run git commands that write, do not build, do not touch the network. The only file you may create or edit is `docs/android-port/LINES-DIGEST.md`.

## Inputs
The base is the lane's own `android/` tree (branch `android/redesign-parity`, identical to `integrate/cloud-redesign`). For each other line there are two files in `docs/android-port/digest-input/`:
- `<line>.diff` is `git diff <base> <line> -- android`. A `+` line exists on the other line but not in the base. A `-` line exists in the base but not on the other line; most of these are base-only work you can ignore.
- `<line>.log` lists that line's commits, as `hash date subject`.

The lines:
- `kudos-ao3-reader-android`: the 0.2.1 parity, sync and backup fixes, and Home Phase A.
- `android_ios-parity-port-2`: shipped as 0.2.2. MuPDF, hasGivenKudos, restricted works, Work Detail hero overlay, polish.
- `android_fix-savedforlater-race`: a transaction around ensureSavedForLaterQueue.
- `android_tasklist-15-reports`: hard-delete cleanup, scoped bulk removal, availability sweep, scroll and page-turn prefs.

Known issue: three branches define different Room `MIGRATION_7_8`s. Released 0.2.1 and 0.2.2 are schema 7, and the base is at schema 9 (signed tombstones).

## What to produce (`docs/android-port/LINES-DIGEST.md`)
For each line, a table of the hunks that add something (`+` lines), grouped into features or fixes:

| # | Feature / fix (plain words) | Files (paths under android/) | Classification | Evidence | Port notes |

Classification is exactly one of:
- **MISSING**: the base lacks it, so it should be ported. Say what the base has instead, if anything.
- **SUPERSEDED**: the base has a newer or equivalent version. Cite the base file and line where the equivalent lives.
- **CONFLICT**: both sides changed the same thing differently. Say how.
- **UNSURE**: say what would settle it.

Then add three cross-line sections:
1. **Room schema and migrations.** Every `Migration(` and entity or column change on each line, compared with the base's `KudosDatabaseMigrations.kt` and `app/schemas/*.json`. Propose one straight migration chain from released v7 that keeps every column any line adds.
2. **Backup manifest.** Fields each line reads or writes that the base doesn't (`BackupManifest.kt`, `BackupMappers.kt`).
3. **Overlaps.** The same fix appearing on more than one line, so it gets ported once.

Cite real paths and line numbers from the diffs. Don't guess: if a hunk is unclear, mark it UNSURE. Keep the digest under 4,000 words. End with a recommended port order and an estimate of size in lines per item.
