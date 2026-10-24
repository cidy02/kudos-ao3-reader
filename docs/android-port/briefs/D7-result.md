# D7 result — A97's accepted platform differences recorded

Sonnet 5.5 (agy account 2), branch `android/agent-sonnet-d7`. Changed: `docs/android-port/DECISIONS.md`
(one entry appended at the end) and this file. Nothing built, committed, pushed or contacted.

## Entry added

- **2026-10-23 · A97's accepted platform differences (Claude-CLI's judgement, recorded by Sonnet D7).**
  A97's 38 pairs left the differences below. Each loses no information and is Android's own idiom
  (Material controls, Android chrome) or the demo data differing, so none is reported again.
  Paths are under `android/app/src/main/java/io/github/cidy02/kudos/`.
  - `chapterform`, `chsettingsedit`: a date is one value with a chevron that opens Android's
    Year/Month/Day picker, where the iPhone shows a pair of date and time pills; the same date is
    shown either way. Drawn at `writing/WritingChapterFormScreen.kt:148` (row) and `:185` (sheet);
    `account/AO3ChallengeSettingsEditScreen.kt:189` (row) and `:88` (picker); chevron
    `ui/subject/SubjectForm.kt:220`.
  - `bulknames`: Android shows a large page title with its section label ("AO3 ACCOUNT"), the iPhone
    a small inline bar title; the same title and fields. `writing/WritingBulkEditScreen.kt:179`.
  - `revokedevice`: Android asks in a dialog over Sync Folder, the iPhone in a sheet; the same
    question and reasons. `backup/PairingSheet.kt:488`.
  - `addworks`: Android's sheet is part-height with checkboxes, the iPhone's full-height with
    circles; the same works to pick. `library/AddLibraryWorksSheet.kt:84` (sheet) and `:182`
    (checkbox).
  - `readerdisplay`: Android's sheet is full height over the reader and its text-size slider is
    Material's stepped slider; the same settings. `reader/ReaderScreen.kt:1016-1018` (sheet),
    `settings/SettingsPages.kt:263` (slider), `reader/ReaderScreen.kt:1131` (its use).
  - `collectiondetails`, `newcollection`, `newqueue`: Android's text fields are Material outlined
    fields with their labels above, and `collectiondetails` is a full-screen page on Android, a
    sheet on the iPhone; the same fields. `library/CollectionEditorSheet.kt:154` (page) and `:239`
    (field), `library/QueueEditorSheet.kt:140` (page) and `:181` (field).
  - `tagworks`, `fandomworks`: at 2.0× Android's pager keeps "Page 1 / 3", the iPhone's AX5 pill
    shortens to "1 / 3"; both are whole. `ui/components/KudosPaginationBar.kt:174`, used by
    `browse/FandomWorksScreen.kt:305`.
  - `pronunciations`: Android opens it as a sheet over the speech settings, the iPhone as a pushed
    page; its footnote about the voice pack is Android's own, since Android's engines differ.
    `settings/PronunciationSettings.kt:81` (sheet) and `:208` (footnote).
  - Demo data that differ between the apps (different works, counts, chosen fandoms, highlight text)
    are not a difference between the apps.
  Reversal: port the iPhone's form for any one of these if the owner prefers it. The paired tiles
  are in `~/kudos-tools/pairs/tiles-a97/`. Evidence: `briefs/D7-result.md`.

## Citations and how each was found

All paths under `android/app/src/main/java/io/github/cidy02/kudos/`. Screen names map to Android
screens via `app/DebugShots.kt:30-83` (shot name → route + `DebugShotEffect` key), then a search of
the named screen's file.

| Item | Cited | How found |
|---|---|---|
| chapterform | `writing/WritingChapterFormScreen.kt:148`, `:185`; `ui/subject/SubjectForm.kt:220` | `DebugShots.kt:77` + `WritingWorkFormScreen.kt:110-112` open `chapterModel`; grep `Publication date` / `WorkFormDateSheet`; chevron = `ExpandMore` under `if (choice)` |
| chsettingsedit | `account/AO3ChallengeSettingsEditScreen.kt:189`, `:88` | `DebugShots.kt:68`; grep `showsChoice`, `dateEditing` |
| bulknames | `writing/WritingBulkEditScreen.kt:179` | `DebugShots.kt:65`; `:51-53` opens the names picker; `BulkHeader` (`:177-179`) passes `kicker = "AO3 Account"` to `SubjectHeaderBlock` |
| revokedevice | `backup/PairingSheet.kt:488` | `DebugShots.kt:83` → `PairingSheet.kt:106`; `RevokeDeviceDialog` calls `AlertDialog` |
| addworks | `library/AddLibraryWorksSheet.kt:84`, `:182` | `DebugShots.kt:31` → `QueuePageScreen.kt:478-491` → `AddLibraryWorksSheet`; `ModalBottomSheet` (no `skipPartiallyExpanded`) and `Checkbox` |
| readerdisplay | `reader/ReaderScreen.kt:1016-1018`, `:1131`; `settings/SettingsPages.kt:263` | `ReaderScreen.kt:383`; `ModalBottomSheet` with `skipPartiallyExpanded = true`; `TextSizeSlider` (`steps = 19`) wraps Material `Slider` |
| collectiondetails / newcollection | `library/CollectionEditorSheet.kt:154`, `:239` | `DebugShots.kt:39-40` → `CollectionDetailScreen.kt:591`, `CollectionsScreen.kt:109`; `Dialog(usePlatformDefaultWidth = false)`; `SubjectFieldLabel` above `OutlinedTextField` |
| newqueue | `library/QueueEditorSheet.kt:140`, `:181` | `DebugShots.kt:30` → `QueueOrganizerScreen.kt:303`; same `Dialog` + `OutlinedTextField` |
| tagworks / fandomworks | `ui/components/KudosPaginationBar.kt:174`; `browse/FandomWorksScreen.kt:305` | grep `"Page `; label list is `Page n / m`, `n / m`, `n`, first that fits |
| pronunciations | `settings/PronunciationSettings.kt:81`, `:208` | `DebugShots.kt:50` → `PronunciationSettings.kt:63-73`; `ModalBottomSheet`; `PRONUNCIATION_ENGINE_LIMIT` is the voice-pack footnote |
| demo data | none | not a code difference |

## Where the code differs a little from the brief's wording (entry follows the code)

- **Dates (item 1):** neither screen opens Material's `DatePicker`. Both open Android's own
  Year/Month/Day picker (`WorkFormDateSheet`, a bottom sheet) and, for challenge dates, also
  Hour/Minute (a dialog). The entry says "Android's Year/Month/Day picker".
- **`collectiondetails` (item 6):** the code is a full-screen `Dialog`
  (`CollectionEditorSheet.kt:154`), not a navigation route. The entry says "full-screen page".
- Line numbers are at `e347c8d2` plus this entry; the working tree has no other changes to those
  files.
