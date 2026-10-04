# Brief 6a: four Settings screens still in the old design

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

Brief 3i redesigned the Settings hub and its pages. Four screens opened from Settings are still
the old Material ones (a title bar, Material cards), seen on the emulator on 2026-10-03. Under
`android/app/src/main/java/io/github/cidy02/kudos/`:

| Android | iOS (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`) |
|---|---|
| `account/AboutScreen.kt` | `Settings/AboutView.swift`, `Settings/LegalNoticesView.swift` |
| `account/BugReportScreen.kt` | `Features/Support/BugReportView.swift` |
| `settings/QueueStorageScreen.kt` (it has two back buttons: the shell's and its own) | `Settings/SettingsStoragePages.swift` (`SettingsReadingQueuesPage`) and what it opens |
| `settings/AvailabilitySweepScreen.kt` | `Features/Account/AvailabilitySweepView.swift` |

iOS wins: same sections, same controls, iOS's strings verbatim.

## Do this, and only this

1. Redraw each of the four as its iOS screen, the way the redesigned Settings pages are drawn.
   Read `settings/SettingsChrome.kt`, `settings/SettingsPages.kt` and `settings/SettingsPages2.kt`
   first and reuse what they use (`SettingsPage`, `SettingsSection`, `SubjectFormRow`,
   `SettingsActionRow`, the floating chrome). No Material `Scaffold`, `TopAppBar` or `Card`.
2. **Behaviour stays.** Every button must do what it does today: the same repository call with
   the same arguments. Where iOS's screen does something Android's doesn't, add it only if the
   repository call already exists; otherwise list it.
3. Bug Report builds a report from device and app details. Don't change what it collects or
   where it sends it; restyle only.
4. Don't touch `backup/BackupScreen.kt` (brief 6b) or any other screen.

## Result

Write `docs/android-port/briefs/6a-result.md`: for each screen, every user-visible string before
and after and every callback before and after; anything iOS has that you left out, and why;
anything Android has that iOS lacks.
