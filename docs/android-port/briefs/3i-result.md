# Brief 3i Result: Settings & AO3 Preferences

## Restored Features Mapping

| Feature Group | Item | Target Page | Target File |
| :--- | :--- | :--- | :--- |
| **Appearance and reader** | App theme | Appearance | `SettingsPages.kt` |
| | Reader theme | Appearance | `SettingsPages.kt` |
| | Accent color | Appearance | `SettingsPages2.kt` (AccentColorEditor) |
| | Apply accent | Appearance | `SettingsPages2.kt` (AccentColorEditor) |
| | Reset to AO3 Red | Appearance | `SettingsPages2.kt` (AccentColorEditor) |
| | Selected (check icon) | Font | `SettingsPages2.kt` |
| | Text size / Text Size | Reader | `SettingsPages.kt` |
| | Line height | Reader | `SettingsPages.kt` |
| | Letter spacing | Reader | `SettingsPages.kt` |
| | Word spacing | Reader | `SettingsPages.kt` |
| | Margin | Reader | `SettingsPages.kt` |
| | Import font (.ttf / .otf) | Font | `SettingsPages2.kt` |
| | Built-in families plus... | Font | `SettingsPages2.kt` |
| | Could not import font. | Font | `SettingsPages2.kt` |
| | Could not read the selected font file. | Font | `SettingsPages2.kt` |
| | Could not delete font. | Font | `SettingsPages2.kt` |
| **Library and files** | Add your own .epub files to the Library… | Library | `SettingsPages2.kt` |
| | Files (count format) | Privacy | `PrivacyDataScreen.kt` |
| | Could not import EPUB. | Library | `SettingsPages2.kt` |
| | Could not import. | Library | `SettingsPages2.kt` |
| | Could not read the selected file. | Library | `SettingsPages2.kt` |
| | Nothing imported. | Library | `SettingsPages2.kt` |
| | Ask before removing a work from your Library. Imported EPUBs… | Library | `SettingsPages2.kt` |
| | Check Now | About | `SettingsPages2.kt` |
| | Check library for deleted/hidden works on AO3. | Library | `SettingsPages2.kt` |
| | Free Up Space? | Privacy | `PrivacyDataScreen.kt` |
| **Folder Sync** | Enable folder sync | Folder Sync | `SettingsPages2.kt` |
| | Select sync folder | Folder Sync | `SettingsPages2.kt` |
| | Change sync folder | Folder Sync | `SettingsPages2.kt` |
| | Sync Now | Folder Sync | `SettingsPages2.kt` |
| | Merged 1 conflicting copy from another device. | Folder Sync | `SettingsPages2.kt` |
| | Working… | Folder Sync | `SettingsPages2.kt` |
| **Privacy** | Require biometric to reveal | Privacy (Settings) | `SettingsPages2.kt` |
| | When hidden | Privacy (Settings) | `SettingsPages2.kt` |
| | Clear Reading History | Privacy (Data) | `PrivacyDataScreen.kt` |
| | Clear Browse Cache | Privacy (Data) | `PrivacyDataScreen.kt` |
| | Safe to clear — it rebuilds... | Privacy (Data) | `PrivacyDataScreen.kt` |
| | Your saved and downloaded works aren't affected. | Privacy (Data) | `PrivacyDataScreen.kt` |
| **Reset** | Reset settings to defaults | Backup | `SettingsPages2.kt` |
| **Help & Project** | Software Update | About | `SettingsPages2.kt` |
| | Checking GitHub for updates… | About | `SettingsPages2.kt` |
| | Up to date | About | `SettingsPages2.kt` |
| | Install Update | About | `SettingsPages2.kt` |
| | Try Again | About | `SettingsPages2.kt` |
| | Source on GitHub | About | `SettingsPages2.kt` |
| | Kudos Android is Alpha... | About | `SettingsPages2.kt` |

## Verification
- Built successfully using `assembleDebug`.
- Unit tests pass.
- Verified in emulator-5554 that Folder Sync, Import font, Software Update, Clear Browse Cache, and Reset settings each open and act.
