# Brief 3i-fix: put back everything the Settings redesign dropped

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only**.

## What's wrong
Your 3i result says "No functionality was dropped". That is not true. Comparing the old
`SettingsScreen.kt` (saved verbatim at `docs/android-port/briefs/3i-old-SettingsScreen.kt.txt`) with the
new `settings/*.kt`, these user-visible strings, and the controls and actions behind them, are gone:

- Appearance and reader: App theme, Reader theme, Accent color, Apply accent, Reset to AO3 Red,
  Selected, Text size / Text Size, Line height, Letter spacing, Word spacing, Margin, Import font
  (.ttf / .otf), "Built-in families plus fonts you import (.ttf / .otf).", Could not import font.,
  Could not read the selected font file., Could not delete font.
- Library and files: "Add your own .epub files to the Library…", Files, Could not import EPUB.,
  Could not import., Could not read the selected file., Nothing imported., "Ask before removing a work
  from your Library. Imported EPUBs…", Check Now, "Check library for deleted/hidden works on AO3.",
  Free Up Space?
- Folder Sync: Enable folder sync, Select sync folder, Change sync folder, Sync Now, "Merged 1
  conflicting copy from another device.", Working…
- Privacy: Require biometric to reveal, When hidden, Clear Reading History (+ its confirm dialog),
  Clear Browse Cache (+ "Clear Browse Cache?", "Browse Cache Cleared", "Safe to clear — it rebuilds the
  next time you open Browse.", "Your saved and downloaded works aren't affected.")
- Reset settings to defaults (+ its confirm dialog)
- Help & Project: Software Update, Checking GitHub for updates…, Up to date, Install Update, Try Again,
  Source on GitHub, and the "Kudos Android is Alpha until it reaches iOS feature parity —" note.

## Do
1. Bring every one of these back, wired to the same ViewModel / repository calls the old screen used
   (same callbacks: onCheckNow, onInstall, onImport, onDelete, onSelect, onValueChange,
   onValueChangeFinished, onSuccess, onFailure), inside the new redesigned pages. Place each one where
   iOS places its equivalent: `kudos-ao3-reader/Settings/SettingsRoute.swift` (`hubGroups`) and the
   `Settings*Page*.swift` files in the iOS lane
   (`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`).
   Android-only features (Software Update from GitHub, the Alpha note) go on the About / Help page.
2. Style them with the same subject components you used (SubjectFormRow, SubjectToggle,
   subjectPanel, SubjectFieldLabel).
3. Write a check that proves nothing is missing: a unit test or script that lists each string above
   and asserts it occurs in `settings/*.kt`. Then confirm on the emulator that Folder Sync, Import
   font, Software Update, Clear Browse Cache and Reset settings each open and act.
4. Rewrite `docs/android-port/briefs/3i-result.md` with a table: each item above → the page and file
   where it now lives.

Don't touch `backup/`, `data/local`, migrations, `app/MainScaffold.kt` or `app/Routes.kt` (Claude
changed the tab-bar rules there). Don't use `if (false)` or other dead code to silence errors.
