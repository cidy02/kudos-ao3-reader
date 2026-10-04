# Brief 6c: pairing, one presentation

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas, the backup format, or what any callback calls; don't edit
`TASKS.md`. Your sandbox can't run Gradle; Claude builds and tests afterwards, so make it compile
by reading the real symbols you use.

`android/app/src/main/java/io/github/cidy02/kudos/backup/PairingSheet.kt` draws two presentations,
switched by `backupChrome`. Since brief 6b both callers pass `true` (`backup/BackupScreen.kt` and
`SettingsFolderSyncPage` in `settings/SettingsPages2.kt`), so every `false` branch is dead.

1. **Delete the old presentation and the parameter**, at every site, leaving exactly what
   `backupChrome = true` draws today: same strings, same callbacks, same order. Remove the
   imports that become unused. Update both callers.
2. **One alignment fault.** In the "Deletion signing" section the "Pair a Device" row, and the
   "N deletions skipped from an unpaired device" row, start 13 dp further in than the rows around
   them: the section's content column pads horizontally and `SettingsActionRow` pads again. Make
   every row's text start on the same line as "This device". Rows manage their own padding;
   plain text blocks get the 13 dp.
3. **The paired-device rows** (Rename with its field and Save, Undo Trust, Revoke, and the
   revocation dialog with its two reasons) are still Material buttons, a Material text field and
   a Material dialog. Redraw them with the settings chrome (`settings/SettingsChrome.kt`,
   `ui/subject/`), as the rest of the section is drawn. Every callback keeps its exact call and
   condition; list them before and after in the result, as brief 6b's result did. If something
   the chrome lacks is needed, don't invent it: say what is missing.
4. In the pairing sheet, the three actions ("Show My QR Code", "Copy My Key", "Advanced: paste a
   key manually") and the paste field, the confirmation toggle and Trust: the same treatment,
   the same rule.

## Result

`docs/android-port/briefs/6c-result.md`: the callbacks before and after; every user-visible
string, unchanged or not; what was left Material and why; what has to be seen on the emulator
(both pages, the sheet, a paired device's row, the revoke dialog, Dark and the largest text).
