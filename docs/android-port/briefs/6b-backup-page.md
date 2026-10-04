# Brief 6b: the Backup screen, redrawn without changing what it does

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't change Room schemas, migrations, the backup format, or any file under `backup/`
other than `BackupScreen.kt` and `PairingSheet.kt`**; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt` is still the old
Material screen (a title bar, Material cards, purple chips). iOS's is
`kudos-ao3-reader/Settings/SettingsBackupPage.swift`, with `Settings/BackupImportSheet.swift`,
`Settings/PairingSheet.swift`, and the replace-library confirmations in
`Settings/SettingsView.swift` (the lane is `/Users/cidy02/kudos-ios-polish`). This screen exports,
imports, merges and **replaces a reader's whole library**, so the rule is stricter than usual.

## Do this, and only this

1. Redraw the screen as iOS's page, the way the redesigned Settings pages are drawn
   (`settings/SettingsChrome.kt`, `settings/SettingsPages.kt`, `settings/SettingsPages2.kt`):
   iOS's sections in iOS's order, iOS's strings verbatim, the floating chrome, no Material
   `Scaffold`, `TopAppBar` or `Card`.
2. **Every action keeps its exact behaviour.** Before you change anything, list every callback
   in the file with the repository function it calls and its arguments. After, the same list must
   hold: same calls, same arguments, same order, same conditions. A restyle that changes what a
   button does will be rejected.
3. **Every confirmation and warning stays.** Replace asks before it removes anything, and iOS has
   more guards than a plain confirmation (the undo copy, the second-attempt warning, "I understand
   the risks", the count of works that will be removed, pausing Library Sync). Compare them one
   by one. Where Android lacks a guard iOS has, add it only if it needs no new repository code;
   otherwise list it first in the result. Never remove a guard Android has.
4. Don't touch any other screen.

## Result

Write `docs/android-port/briefs/6b-result.md`: the callback list before and after, side by side;
every user-visible string before and after; each of iOS's guards and whether Android has it; what
you left out and why.
