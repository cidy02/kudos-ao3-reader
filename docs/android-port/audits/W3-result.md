# W3 Audit: Words on Six More Android Screens Checked Against iOS

This audit compares every reader-visible and reader-audible string (titles, kickers, subtitles, section headers, row labels, values, placeholders, footnotes, buttons, menu items, alerts, empty/loading/failure states, and accessibility labels, hints, and action names) across the six screen pairs specified in the W3 brief.

- **iOS path**: `kudos-ao3-reader/`
- **Android path**: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`

Excluded from "differs":
- Words naming platform-specific concepts Android does not have (e.g. iCloud, Face ID, the Files app, swipe gestures where Android draws menus).
- Changes recorded in `/Users/cidy02/kudos-android-lane/docs/android-port/DECISIONS.md`:
  - `## 2026-10-09: what a sent write says, continued (audit A26)` (unconfirmed chapter delete and series removal messages).
  - `## 2026-10-09: the work form posts, previews on AO3 and deletes (brief 3bx)` (work form post, preview, delete mechanics).
  - `## 2026-10-09: the Privacy screen as iOS has it (brief 3bz)` (privacy screen layout, 4-section architecture, and local logout).
  - `## 2026-10-09: fifteen small differences from iOS (brief 3ca, from reading R5)` (six heading levels offered on comment formatting sheet).
  - `## 2026-10-09: a required field is spoken as "…, required"` (TalkBack reads required form labels as "..., required").
  - `## 2026-10-09: Chapter Comments from the Inbox, second version (audit A28)` (chapter comments navigation from inbox items).

---

## Pair 1: Writing Work Form — Post, Preview, Delete

- **Android**: `writing/WritingWorkFormScreen.kt`, `writing/WritingAO3PreviewScreen.kt`, `writing/WritingWorkFormState.kt`
- **iOS**: `Features/Writing/WorkEditView.swift`, `Features/Writing/WritingPreviewView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Post"` (`WorkEditView.swift:133`, Section header) | `"Post"` (`WritingWorkFormScreen.kt:369`, Section header) | **same** |
| `"Post work"` (`WorkEditView.swift:709`, Action row) | `"Post work"` (`WritingWorkFormScreen.kt:371`, Action row) | **same** |
| `"Preview on AO3"` (`WorkEditView.swift:713`, Action row) | `"Preview on AO3"` (`WritingWorkFormScreen.kt:374`, Action row) | **same** |
| `"Delete draft"` (`WorkEditView.swift:716`, Action row) | `"Delete draft"` (`WritingWorkFormScreen.kt:380`, Action row) | **same** |
| `"AO3 deletes an unposted draft 30 days after it is created."` (`WorkEditView.swift:137`, Footnote) | `"AO3 deletes an unposted draft 30 days after it is created."` (`WritingWorkFormScreen.kt:384`, Footnote) | **same** |
| `"Delete"` (`WorkEditView.swift:142`, Section header) | `"Delete"` (`WritingWorkFormScreen.kt:387`, Section header) | **same** |
| `"Delete work on AO3"` (`WorkEditView.swift:526`, Action row) | `"Delete work on AO3"` (`WritingWorkFormScreen.kt:389`, Action row) | **same** |
| `"Post this work?"` (`WorkEditView.swift:213`, Post alert title) | `"Post this work?"` (`WritingWorkFormScreen.kt:192`, Post alert title) | **same** |
| `missing.isEmpty ? "Post work" : "Fill in what is missing"` (`WorkEditView.swift:215, 217`, Post alert confirm button) | `if (missing.isEmpty()) "Post work" else "Fill in what is missing"` (`WritingWorkFormScreen.kt:192`, Post alert confirm button) | **same** |
| `"Cancel"` (`WorkEditView.swift:219`, Post alert cancel button) | `"Cancel"` (`WritingWorkFormScreen.kt:193`, Post alert cancel button) | **same** |
| 0 missing: `"Posting notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WorkEditView.swift:767`, Post alert message) | 0 missing: `"Posting notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WritingWorkFormState.kt:477`, Post alert message) | **same** |
| 1 missing: `"One thing is missing. Add <item>. AO3 requires it. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WorkEditView.swift:771, 775`, Post alert message) | 1 missing: `"One thing is missing. Add <item>. AO3 requires it. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WritingWorkFormState.kt:482, 484`, Post alert message) | **same** |
| 2 missing: `"Two things are missing. Add <item 1> and <item 2>. AO3 requires both. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WorkEditView.swift:772, 775`, Post alert message) | 2 missing: `"Two things are missing. Add <item 1> and <item 2>. AO3 requires both. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WritingWorkFormState.kt:482, 484`, Post alert message) | **same** |
| 3+ missing: `"<n> things are missing. Add <list>. AO3 requires all of them. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WorkEditView.swift:773, 775`, Post alert message) | 3+ missing: `"<n> things are missing. Add <list>. AO3 requires all of them. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft."` (`WritingWorkFormState.kt:482, 484`, Post alert message) | **same** |
| Missing field phrase mapping: `"Title"` → `"a title"`, `"Rating"` → `"a rating"`, `"Archive Warning"` → `"an archive warning"`, `"Fandoms"` → `"a fandom"`, `"Language"` → `"a language"`, `"Work Text"` → `"the work text"` (`WorkEditView.swift:780-787`) | Missing field phrase mapping: `"Title"` → `"a title"`, `"Rating"` → `"a rating"`, `"Archive Warning"` → `"an archive warning"`, `"Fandoms"` → `"a fandom"`, `"Language"` → `"a language"`, `"Work Text"` → `"the work text"` (`WritingWorkFormState.kt:478-479`) | **same** |
| `form.isDraft ? "Delete this draft?" : "Delete this work?"` (`WorkEditView.swift:224`, Delete alert title) | `if (form.isDraft) "Delete this draft?" else "Delete this work?"` (`WritingWorkFormScreen.kt:201`, Delete alert title) | **same** |
| `form.isDraft ? "Delete" : "Delete on AO3"` (`WorkEditView.swift:228`, Delete alert button) | `if (form.isDraft) "Delete" else "Delete on AO3"` (`WritingWorkFormScreen.kt:204`, Delete alert button) | **same** |
| `"Cancel"` (`WorkEditView.swift:231`, Delete alert dismiss button) | `"Cancel"` (`WritingWorkFormScreen.kt:206`, Delete alert dismiss button) | **same** |
| `imp.cautionText` (`WorkEditView.swift:234`, Delete alert message) | `implications.cautionText` (`WritingWorkFormScreen.kt:202`, Delete alert message) | **same** |
| `"AO3 Account"` (`WritingPreviewView.swift:33`, Preview kicker) | `"AO3 Account"` (`WritingAO3PreviewScreen.kt:56`, Preview kicker) | **same** |
| `"Preview"` (`WritingPreviewView.swift:33`, Preview title) | `"Preview"` (`WritingAO3PreviewScreen.kt:56`, Preview title) | **same** |
| `subtitle` (`WritingPreviewView.swift:33`, Preview subtitle) | `subtitle` (`WritingAO3PreviewScreen.kt:56`, Preview subtitle) | **same** |
| `preview.notice` (`WritingPreviewView.swift:37`, Preview notice footnote) | `preview.notice` (`WritingAO3PreviewScreen.kt:57`, Preview notice footnote) | **same** |
| `"Post"` (`WritingPreviewView.swift:46`, Preview section header) | `"Post"` (`WritingAO3PreviewScreen.kt:72`, Preview section header) | **same** |
| `postTitle` (`WritingPreviewView.swift:48`, Preview post row button: `"Post work"` / `"Update"`) | `postTitle` (`WritingAO3PreviewScreen.kt:74`, Preview post row button: `"Post work"` / `"Update"`) | **same** |
| `"Edit"` (`WritingPreviewView.swift:53`, Preview edit row button) | `"Edit"` (`WritingAO3PreviewScreen.kt:79`, Preview edit row button) | **same** |
| `"AO3 could not post this"` (`WritingPreviewView.swift:67`, Preview error alert title) | `"AO3 could not post this"` (`WritingAO3PreviewScreen.kt:48`, Preview error alert title) | **same** |
| `"OK"` (`WritingPreviewView.swift:70`, Preview error alert dismiss button) | `"OK"` (`WritingAO3PreviewScreen.kt:48`, via `WritingErrorAlert`) | **same** |
| `confirmation?.title` / `"Post this work?"` (`WritingPreviewView.swift:72`, Preview confirmation alert title) | `confirmation` / `"Post this work?"` (`WritingAO3PreviewScreen.kt:49`, Preview confirmation alert title) | **same** |
| `postTitle` (`WritingPreviewView.swift:73`, Preview confirmation confirm button) | `postTitle` (`WritingAO3PreviewScreen.kt:49`, Preview confirmation confirm button) | **same** |
| `"Cancel"` (`WritingPreviewView.swift:74`, Preview confirmation cancel button) | `"Cancel"` (`WritingAO3PreviewScreen.kt:49`, via `WorkPostAlert`) | **same** |
| `confirmation?.message` (`WritingPreviewView.swift:75`, Preview confirmation message) | `confirmation` (`WritingAO3PreviewScreen.kt:49`, via `WorkPostAlert`) | **same** |

---

## Pair 2: Settings Privacy & Data

- **Android**: `settings/PrivacyDataScreen.kt`, `settings/LocalDataFootprint.kt`, `auth/AO3AuthRepository.kt`
- **iOS**: `Features/Account/PrivacyDataView.swift`, `Services/LocalDataFootprint.swift`, `Services/LocalDataClearing.swift`, `Services/AO3AuthService.swift`, `UIComponents/DeleteConfirmation.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Account › Settings"` (`PrivacyDataView.swift:187`, Header kicker) | `"AO3 Account › Settings"` (`PrivacyDataScreen.kt:84`, Header kicker) | **same** |
| `"Privacy"` (`PrivacyDataView.swift:188`, Header title) | `"Privacy"` (`PrivacyDataScreen.kt:84`, Header title) | **same** |
| `"Your reading data stays on this device"` (`PrivacyDataView.swift:189`, Header subtitle) | `"Your reading data stays on this device"` (`PrivacyDataScreen.kt:85`, Header subtitle) | **same** |
| `"No ads or tracking, and no separate Kudos account"` (`PrivacyDataView.swift:212`, Promise card title) | `"No ads or tracking, and no separate Kudos account"` (`PrivacyDataScreen.kt:36, 92`, Promise card title) | **same** |
| `"Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device."` (`PrivacyDataView.swift:220-222`, Promise card body) | `"Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device."` (`PrivacyDataScreen.kt:37, 94`, Promise card body) | **same** |
| `"Stored on this device"` (`PrivacyDataView.swift:89`, Section header) | `"Stored on this device"` (`PrivacyDataScreen.kt:98`, Section header) | **same** |
| `"Downloaded works"` (`PrivacyDataView.swift:259`, Row label) | `"Downloaded works"` (`PrivacyDataScreen.kt:102`, `LocalDataFootprint.kt:29`) | **same** |
| `"Works you're reading"` (`PrivacyDataView.swift:266`, Row label) | `"Works you're reading"` (`LocalDataFootprint.kt:30`) | **same** |
| `"Original files kept"` (`PrivacyDataView.swift:274`, Row label) | `"Original files kept"` (`LocalDataFootprint.kt:31`) | **same** |
| `"Imported fonts"` (`PrivacyDataView.swift:282`, Row label) | `"Imported fonts"` (`LocalDataFootprint.kt:32`) | **same** |
| `"Draft recovery"` (`PrivacyDataView.swift:289`, Row label) | `"Draft recovery"` (`PrivacyDataScreen.kt:103`, `LocalDataFootprint.kt:33`) | **same** |
| `"Caches"` (`PrivacyDataView.swift:295`, Row label) | `"Caches"` (`PrivacyDataScreen.kt:103`, `LocalDataFootprint.kt:34`) | **same** |
| Byte formatting pattern: `<n> byte[s]`, `<n> KB`, `<n> MB`, `<n> GB` (`LocalStorageFootprint.swift:51-78`) | Byte formatting pattern: `<n> byte[s]`, `<n> KB`, `<n> MB`, `<n> GB` (`LocalDataFootprint.kt:39-54`) | **same** |
| `"—"` (`PrivacyDataView.swift:458`, Unmeasured size placeholder em dash) | `"—"` (`PrivacyDataScreen.kt:81`, Unmeasured size placeholder em dash) | **same** |
| `"Reading positions"` (`PrivacyDataView.swift:304`, Row label) | `"Reading positions"` (`PrivacyDataScreen.kt:109`, Row label) | **same** |
| Work count pattern: `<n> work[s]` (`PrivacyDataView.swift:482`) | Work count pattern: `<n> work[s]` (`PrivacyDataScreen.kt:237`) | **same** |
| `"Local collections"` (`PrivacyDataView.swift:310`, Row label) | `"Local collections"` (`PrivacyDataScreen.kt:111`, Row label) | **same** |
| `"Saved searches"` (`PrivacyDataView.swift:316`, Row label) | `"Saved searches"` (`PrivacyDataScreen.kt:113`, Row label) | **same** |
| `"Search history"` (`PrivacyDataView.swift:321`, Row label) | `"Search history"` (`PrivacyDataScreen.kt:116`, Row label) | **same** |
| `"Not recorded"` (`PrivacyDataView.swift:321`, Row value) | `"Not recorded"` (`PrivacyDataScreen.kt:116`, Row value) | **same** |
| `"The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space."` (`PrivacyDataView.swift:325-327`, Stored footnote) | `"The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space."` (`PrivacyDataScreen.kt:38, 118`, Stored footnote) | **same** |
| `"Clear"` (`PrivacyDataView.swift:96`, Section header) | `"Clear"` (`PrivacyDataScreen.kt:121`, Section header) | **same** |
| `"Free up space"` (`PrivacyDataView.swift:335`, Row label) | `"Free up space"` (`PrivacyDataScreen.kt:122`, Row label) | **same** |
| File count pattern: `<n> file[s]` (`PrivacyDataView.swift:482`) | File count pattern: `<n> file[s]` (`PrivacyDataScreen.kt:237`) | **same** |
| `"Clear reading positions"` (`PrivacyDataView.swift:345`, Row label) | `"Clear reading positions"` (`PrivacyDataScreen.kt:125`, Row label) | **same** |
| `"Clear reading history"` (`PrivacyDataView.swift:355`, Row label) | `"Clear reading history"` (`PrivacyDataScreen.kt:128`, Row label) | **same** |
| `browseCacheCleared ? "Browse cache cleared" : "Clear browse cache"` (`PrivacyDataView.swift:365`, Row label) | `if (browseCacheCleared) "Browse cache cleared" else "Clear browse cache"` (`PrivacyDataScreen.kt:131`, Row label) | **same** |
| `"Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences."` (`PrivacyDataView.swift:381-383`, Clear footnote) | `"Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences."` (`PrivacyDataScreen.kt:39, 136`, Clear footnote) | **same** |
| `"AO3 session"` (`PrivacyDataView.swift:103`, Section header) | `"AO3 session"` (`PrivacyDataScreen.kt:139`, Section header) | **same** |
| `"Signed in"` (`PrivacyDataView.swift:393`, Row label) | `"Signed in"` (`PrivacyDataScreen.kt:142`, Row label) | **same** |
| `"Remove AO3 session"` (`PrivacyDataView.swift:396`, Destructive action label) | `"Remove AO3 session"` (`PrivacyDataScreen.kt:144`, Destructive action label) | **same** |
| `"AO3 account"` (`PrivacyDataView.swift:403`, Row label) | `"AO3 account"` (`PrivacyDataScreen.kt:146`, Row label) | **same** |
| `"Not signed in"` (`PrivacyDataView.swift:403`, Row value) | `"Not signed in"` (`PrivacyDataScreen.kt:146`, Row value) | **same** |
| `"Your AO3 sign-in is kept only on this device and is never shared."` (`PrivacyDataView.swift:416`, Session footnote) | `"Your AO3 sign-in is kept only on this device and is never shared."` (`PrivacyDataScreen.kt:40, 149`, Session footnote) | **same** |
| `"Logged out of AO3."` (`AO3AuthService.swift:613`, Logout notice) | `"Logged out of AO3."` (`AO3AuthRepository.kt:302`, Logout notice) | **same** |
| `"Signed out here, but this device couldn't fully remove the saved AO3 session. It won't be restored automatically — we'll keep retrying."` (`AO3AuthService.swift:620-621`, Session warning notice) | `"Signed out here, but this device couldn't fully remove the saved AO3 session. It won't be restored automatically — we'll keep retrying."` (`AO3AuthRepository.kt:299-300`, Session warning notice) | **same** |
| `"Your AO3 session expired. Please log in again."` (`AO3AuthService.swift:641, 988`, Expiry notice) | `"Your AO3 session expired. Please log in again."` (`AO3AuthRepository.kt:148, 215, 288`, Expiry notice) | **same** |
| `"Couldn't finish removing a previous AO3 session from this device. We'll keep retrying; you are not signed in."` (`AO3AuthService.swift:1071-1072`, Removal pending notice) | `"Couldn't finish removing a previous AO3 session from this device. We'll keep retrying; you are not signed in."` (`AO3AuthRepository.kt:358-359`, Removal pending notice) | **same** |
| `"Read Aloud downloads"` (`PrivacyDataView.swift:109`, Section header) | `"Read Aloud downloads"` (`PrivacyDataScreen.kt:152`, Section header) | **same** |
| `"Optional Voice Pack downloads stay separate from your reading data."` (`PrivacyDataView.swift:425`, Voice pack card title) | `"Optional Voice Pack downloads stay separate from your reading data."` (`PrivacyDataScreen.kt:41, 155`, Voice pack card title) | **same** |
| `"Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."` (`PrivacyDataView.swift:428-432`, Voice pack card body) | `"Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."` (`PrivacyDataScreen.kt:42, 157`, Voice pack card body) | **same** |
| `"Clear Reading History?"` (`PrivacyDataView.swift:121`, Dialog title) | `"Clear Reading History?"` (`PrivacyDataScreen.kt:166`, Dialog title) | **same** |
| `"Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again."` (`PrivacyDataView.swift:132-134`, Dialog message) | `"Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again."` (`PrivacyDataScreen.kt:166`, Dialog message) | **same** |
| `"Clear \(countLabel(freedHistory.count, "Work"))"` (1: `"Clear 1 Work"`, 2+: `"Clear 2 Works"`, 0: `"Clear 0 Works"`) (`PrivacyDataView.swift:125`, Dialog confirm button) | `"Clear ${count(history?.size, "Work")}"` (1: `"Clear 1 Work"`, 2+: `"Clear 2 Works"`, 0: `"Clear 0 Works"`) (`PrivacyDataScreen.kt:174`, Dialog confirm button) | **same** |
| `"Cancel"` (`PrivacyDataView.swift:130`, Dialog cancel button) | `"Cancel"` (`DestructiveConfirmation.kt:29`) | **same** |
| `"Free Up Space?"` (`PrivacyDataView.swift:137`, Dialog title) | `"Free Up Space?"` (`PrivacyDataScreen.kt:164`, Dialog title) | **same** |
| `"Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them."` (`PrivacyDataView.swift:147-148`, Dialog message) | `"Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them."` (`PrivacyDataScreen.kt:164`, Dialog message) | **same** |
| `"Free \(countLabel(freeableDownloads.count, "File"))"` (1: `"Free 1 File"`, 2+: `"Free 2 Files"`, 0: `"Free 0 Files"`) (`PrivacyDataView.swift:141`, Dialog confirm button) | `"Free ${count(freeable?.size, "File")}"` (1: `"Free 1 File"`, 2+: `"Free 2 Files"`, 0: `"Free 0 Files"`) (`PrivacyDataScreen.kt:172`, Dialog confirm button) | **same** |
| `"Cancel"` (`PrivacyDataView.swift:145`, Dialog cancel button) | `"Cancel"` (`DestructiveConfirmation.kt:29`) | **same** |
| `"Clear Reading Positions?"` (`PrivacyDataView.swift:151`, Dialog title) | `"Clear Reading Positions?"` (`PrivacyDataScreen.kt:165`, Dialog title) | **same** |
| `"Clears your place in every work. Your works and their order in Continue Reading stay the same."` (`PrivacyDataView.swift:160-161`, Dialog message) | `"Clears your place in every work. Your works and their order in Continue Reading stay the same."` (`PrivacyDataScreen.kt:165`, Dialog message) | **same** |
| `"Clear \(countLabel(positionedWorks.count, "Position"))"` (1: `"Clear 1 Position"`, 2+: `"Clear 2 Positions"`, 0: `"Clear 0 Positions"`) (`PrivacyDataView.swift:155`, Dialog confirm button) | `"Clear ${count(positions?.size, "Position")}"` (1: `"Clear 1 Position"`, 2+: `"Clear 2 Positions"`, 0: `"Clear 0 Positions"`) (`PrivacyDataScreen.kt:173`, Dialog confirm button) | **same** |
| `"Cancel"` (`PrivacyDataView.swift:158`, Dialog cancel button) | `"Cancel"` (`DestructiveConfirmation.kt:29`) | **same** |
| `"Clear Browse Cache?"` (`PrivacyDataView.swift:164`, Dialog title) | `"Clear Browse Cache?"` (`PrivacyDataScreen.kt:167`, Dialog title) | **same** |
| `"Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it."` (`PrivacyDataView.swift:175-176`, Dialog message) | `"Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it."` (`PrivacyDataScreen.kt:167`, Dialog message) | **same** |
| `"Clear \(byteLabel(footprint.cacheBytes))"` (`PrivacyDataView.swift:168`, Dialog confirm button) | `"Clear ${bytes(footprint?.cacheBytes)}"` (`PrivacyDataScreen.kt:175`, Dialog confirm button) | **same** |
| `"Cancel"` (`PrivacyDataView.swift:173`, Dialog cancel button) | `"Cancel"` (`DestructiveConfirmation.kt:29`) | **same** |
| `"Remove AO3 Session?"` (`AO3AuthService.swift:657`, Logout dialog title) | `"Remove AO3 Session?"` (`LogOutConfirmation.kt:21`, Logout dialog title) | **same** |
| `"Kudos signs out of your AO3 account on this device. Your downloaded works, reading positions and history stay here."` (`AO3AuthService.swift:659`, Logout dialog message) | `"Kudos signs out of your AO3 account on this device. Your downloaded works, reading positions and history stay here."` (`LogOutConfirmation.kt:22`, Logout dialog message) | **same** |
| `"Remove Session"` (`AO3AuthService.swift:661`, Logout dialog confirm button) | `"Remove Session"` (`LogOutConfirmation.kt:23`, Logout dialog confirm button) | **same** |
| `"Cancel"` (`AO3AuthService.swift:664`, Logout dialog cancel button) | `"Cancel"` (`LogOutConfirmation.kt:24`, Logout dialog cancel button) | **same** |

---

## Pair 3: Comments & Threads

- **Android**: `comments/CommentsScreen.kt`, `comments/CommentThreadComponents.kt`, `comments/CommentComposerSheet.kt`, `comments/CommentMarkup.kt`, `comments/CommentThreadScreen.kt`, `comments/CommentsViewModel.kt`
- **iOS**: `Features/Comments/CommentsView.swift`, `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentThreadRow.swift`, `Features/Comments/CommentThreadScreen.swift`, `Features/Comments/CommentMarkup.swift`, `Features/Comments/CommentsErrorMessages.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Comments"` (`CommentsView.swift:476`, Header kicker) | `workTitle` (`CommentsScreen.kt:394`, Header kicker: defaults to work title) | **differs** (iOS kicker: `"AO3 Comments"`, Android kicker: `workTitle`) |
| `"Comments"` (`CommentsView.swift:477`, Header title) | `"Comments"` (`CommentsScreen.kt:395`, Header title) | **same** |
| Subtitle pattern: `total == 1 ? "1 comment" : "\(total.formatted()) comments"` (`CommentsView.swift:478, 488-490`) | Subtitle pattern: `total == 1 ? "1 comment" : "${total.formatted()} comments"` (`CommentsScreen.kt:396, 403-405`) | **same** |
| `"Comments"` (`CommentsView.swift:520`, Stat cell label) | `"Comments"` (`CommentsScreen.kt:412`, Stat cell label) | **same** |
| `"\(total.formatted()) comments on AO3"` (`CommentsView.swift:521`, Accessibility label) | `"${cell.value} Comments"` (`SubjectComponents.kt:591`, TalkBack semantics) | **differs** (iOS VoiceOver: `"\(total.formatted()) comments on AO3"`, Android TalkBack: `"${cell.value} Comments"`) |
| `"Threads"` (`CommentsView.swift:527`, Stat cell label) | `"Threads"` (`CommentsScreen.kt:420`, Stat cell label) | **same** |
| `"\(figures.threads.formatted()) conversations loaded"` (`CommentsView.swift:528`, Accessibility label) | `"${cell.value} Threads"` (`SubjectComponents.kt:591`, TalkBack semantics) | **differs** (iOS VoiceOver: `"\(figures.threads.formatted()) conversations loaded"`, Android TalkBack: `"${cell.value} Threads"`) |
| `"Yours"` (`CommentsView.swift:538`, Stat cell label) | `"Yours"` (`CommentsScreen.kt:427`, Stat cell label) | **same** |
| `"\(figures.mine.formatted()) of the loaded comments are yours"` (`CommentsView.swift:540`, Accessibility label) | `"${cell.value} Yours"` (`SubjectComponents.kt:591`, TalkBack semantics) | **differs** (iOS VoiceOver: `"\(figures.mine.formatted()) of the loaded comments are yours"`, Android TalkBack: `"${cell.value} Yours"`) |
| `"Latest"` (`CommentsView.swift:547`, Stat cell label) | `"Latest"` (`CommentsScreen.kt:436`, Stat cell label) | **same** |
| `"Newest loaded comment \(latest)"` (`CommentsView.swift:548-549`, Accessibility label) | `"${cell.value} Latest"` (`SubjectComponents.kt:591`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Newest loaded comment \(latest)"`, Android TalkBack: `"${cell.value} Latest"`) |
| `"Threads, Yours and Latest count only this page. The comment total covers the whole work."` (`CommentsView.swift:559`, Scope footnote) | `"Threads, Yours and Latest count only this page. The comment total covers the whole work."` (`CommentsScreen.kt:451`, Scope footnote) | **same** |
| `chapterPillTitle`: `"All comments"`, `"Chapter \(pos)"`, `"By chapter"` (`CommentsView.swift:576, 635-639`, Pill text) | `chapterPillTitle`: `"All comments"`, `"Chapter ${pos}"`, `"By chapter"` (`CommentsScreen.kt:472-474`, Pill text) | **same** |
| `"Browse comments by chapter"` (`CommentsView.swift:585`, Accessibility label) | `contentDescription = "Browse comments by chapter"` (`CommentsScreen.kt:480`) | **same** |
| `chapterPillTitle` (`CommentsView.swift:586`, Accessibility value) | — | **missing on Android** (TalkBack does not expose accessibility value on chapter pill) |
| `newestFirst ? "Newest" : "Oldest"` (`CommentsView.swift:618`, Sort pill text) | `if (order == CommentSortOrder.NewestFirst) "Newest" else "Oldest"` (`CommentsScreen.kt:492`, Sort pill text) | **same** |
| `"Sort comments"` (`CommentsView.swift:629`, Accessibility label) | `contentDescription = "Sort comments"` (`CommentsScreen.kt:498`) | **same** |
| `newestFirst ? "Newest First" : "Oldest First"` (`CommentsView.swift:630`, Accessibility value) | — | **missing on Android** (TalkBack does not expose accessibility value on sort pill) |
| `"Oldest First"` (`CommentsView.swift:604`, Sort menu item) | `"Oldest First"` (`CommentsScreen.kt:510`, Sort menu item) | **same** |
| `"Newest First"` (`CommentsView.swift:613`, Sort menu item) | `"Newest First"` (`CommentsScreen.kt:523`, Sort menu item) | **same** |
| `"Couldn't Load Comments"` (`CommentsView.swift:665`, Error title) | `"Couldn't Load Comments"` (`CommentsScreen.kt:547, 559`, Error title) | **same** |
| `"Try Again"` (`CommentsView.swift:669`, Error button) | `"Log in to AO3"` when `CommentsUiState.AuthRequired` (`CommentsScreen.kt:562`); `"Try Again"` when `CommentsUiState.Error` (`CommentsScreen.kt:550`) | **differs** (iOS: `"Try Again"`, Android auth failure: `"Log in to AO3"`) |
| `"You're offline. These comments are from \(fetched) and may be out of date."` (`CommentsView.swift:760`, Stale cache banner) | — | **missing on Android** |
| `"No Comments Yet"` (`CommentsView.swift:687`, Empty title) | `"No Comments Yet"` (`CommentsScreen.kt:573`, Empty title) | **same** |
| `"You can be the first to comment on this work."` (`CommentsView.swift:689`, Empty message) | `"You can be the first to comment on this work."` (`CommentsScreen.kt:574`, Empty message) | **same** |
| `"Comments"` (`CommentsView.swift:699`, Section rule header) | `"Comments"` (`CommentsScreen.kt:588`, Section rule header) | **same** |
| `"Previous"` (`CommentsView.swift:776`, Pagination button) | `"Previous"` (`CommentsScreen.kt:614`, Pagination button) | **same** |
| `"Page \(model.currentPageNumber) of \(page.totalPages)"` (`CommentsView.swift:784`, Pagination text) | `"Page ${thread.currentPage} of ${thread.totalPages}"` (`CommentsScreen.kt:627`, Pagination text) | **same** |
| `"Next"` (`CommentsView.swift:793`, Pagination button) | `"Next"` (`CommentsScreen.kt:639`, Pagination button) | **same** |
| `auth.isLoggedIn ? "Write a comment" : "Log in to comment"` (`CommentsView.swift:823`, Write button text) | `if (isLoggedIn) "Write a comment" else "Log in to comment"` (`CommentsScreen.kt:656`, Write button text) | **same** |
| `title` (`CommentsView.swift:869`, Accessibility label) | `contentDescription = null` (inherits visible text `title`, `CommentsScreen.kt:656`) | **same** |
| `"Delete this comment?"` (`CommentsView.swift:299`, Delete dialog title) | `"Delete this comment?"` (`CommentsScreen.kt:255`, Delete dialog title) | **same** |
| `"This removes the comment on AO3. It cannot be undone."` (`CommentsView.swift:303`, Delete dialog message) | `"This removes the comment on AO3. It cannot be undone."` (`CommentsScreen.kt:256`, Delete dialog message) | **same** |
| `"Delete"` (`CommentsView.swift:300`, Delete dialog button) | `"Delete"` (`CommentsScreen.kt:265`, Delete dialog button) | **same** |
| `"Cancel"` (`CommentsView.swift:301`, Delete dialog cancel) | `"Cancel"` (`CommentsScreen.kt:270`, Delete dialog cancel) | **same** |
| `"AO3"` (`CommentsView.swift:305`, Banner alert title) | `"AO3"` (`CommentsScreen.kt:280`, Banner alert title) | **same** |
| `"OK"` (`CommentsView.swift:306`, Banner alert button) | `"OK"` (`CommentsScreen.kt:284`, Banner alert button) | **same** |
| `"Browse Comments by Chapter"` (`CommentsView.swift:978`, Chapter picker title) | `"Browse Comments by Chapter"` (`CommentsScreen.kt:733`, Chapter picker title) | **same** |
| `"All Comments"` (`CommentsView.swift:904`, Chapter picker row) | `"All Comments"` (`CommentsScreen.kt:763`, Chapter picker row) | **same** |
| `"AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments."` (`CommentsView.swift:951`, Chapter picker footnote) | `"AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments."` (`CommentsScreen.kt:827`, Chapter picker footnote) | **same** |
| `"Couldn't Load Chapters"` (`CommentsView.swift:966`, Chapter picker error title) | — | **missing on Android** |
| `model.chaptersFailureMessage ?? "Check your connection and try again."` (`CommentsView.swift:969-970`, Chapter picker error message) | — | **missing on Android** |
| Title: `isEdit ? "Edit comment" : (isReply ? "Reply to \(parent.author)" : "New comment")` (`CommentsView.swift:1220-1222`) | Title: `when { isEdit -> "Edit comment"; isReply -> "Reply to ${replyTarget.author.name}"; else -> "New comment" }` (`CommentComposerSheet.kt:93-97`) | **same** |
| Action button: `isEdit ? "Save" : "Post"` (`CommentsView.swift:1207-1209, 1311`) | Action button: `if (isEdit) "Save" else "Post"` (`CommentComposerSheet.kt:99, 157`) | **same** |
| `"Cancel"` (`CommentsView.swift:1298`, Composer cancel) | `"Cancel"` (`CommentComposerSheet.kt:124`, Composer cancel) | **same** |
| Placeholder: `isReply ? "Write your reply…" : "Share your thoughts…"` (`CommentsView.swift:1373`) | Placeholder: `if (isReply) "Write your reply…" else "Share your thoughts…"` (`CommentComposerSheet.kt:229`) | **same** |
| `isEdit ? "Edit comment text" : "Comment text"` (`CommentsView.swift:1383`, Accessibility label) | — | **missing on Android** (TalkBack does not expose label on composer text editor) |
| `"New comments post to the whole work. AO3 shows them on its latest chapter."` (`CommentsView.swift:1255`, Honesty note) | `"New comments post to the whole work. AO3 shows them on its latest chapter."` (`CommentComposerSheet.kt:261`, Honesty note) | **same** |
| `auth.username.map { "as \($0)" } ?? "Not signed in"` (`CommentsView.swift:1389`, Identity text) | `currentUsername?.let { "as $it" } ?: "Not signed in"` (`CommentComposerSheet.kt:273`, Identity text) | **same** |
| `"\(remainingCharacters.formatted()) left"` (`CommentsView.swift:1395`, Budget text) | `"$remainingCharacters left"` (`CommentComposerSheet.kt:278`, Budget text) | **same** |
| `"Drag the sheet taller"` (`CommentsView.swift:1264`, Composer footer) | `"Drag the sheet taller"` (`CommentComposerSheet.kt:286`, Composer footer) | **same** |
| `"We're checking whether this posted before trying again…"` (`CommentsView.swift:1499`, Verifying status banner) | — | **missing on Android** |
| `"Check Again"` (`CommentsView.swift:1513`, Re-verify button) | — | **missing on Android** |
| `"Posted."` (`CommentsView.swift:1523`, Success status banner) | — | **missing on Android** |
| `"AO3 answered but didn't confirm the comment posted. Checking whether it went through…"` (`CommentsErrorMessages.swift:32-33`, Ambiguous submit message) | — | **missing on Android** |
| `"The connection dropped while posting. Checking whether the comment went through…"` (`CommentsErrorMessages.swift:35`, Ambiguous submit message) | — | **missing on Android** |
| — | `"You just posted this. Reload to see if it appeared."` (`CommentsViewModel.kt:556`, Duplicate submit alert message) | **Android only** |
| — | `"Couldn't confirm this posted — reloading to check."` (`CommentsViewModel.kt:597`, Unconfirmed submit alert message) | **Android only** |
| `"Comment deleted."` (`CommentsView.swift:1012`, via `actionBanner`) | `"Comment deleted."` (`CommentsViewModel.kt:535`, via `_message`) | **same** |
| `"Reply to \(comment.author)"` (`CommentThreadRow.swift:1433`, Accessibility label) | `contentDescription = "Reply"` (`CommentThreadComponents.kt:753`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Reply to \(comment.author)"`, Android TalkBack: `"Reply"`) |
| `"Show \(count) more replies"` (`CommentThreadRow.swift:1617`, Button label) | `"Show ${item.hiddenCount} more"` (`CommentThreadComponents.kt:339`, Button label) | **differs** (iOS: `"Show \(count) more replies"`, Android: `"Show ${item.hiddenCount} more"`) |
| `"Expands nested replies for this comment"` / `"Reveals more replies for this comment"` (`CommentThreadRow.swift:1627`, Accessibility hint) | — | **missing on Android** |
| `isCollapsed ? "Show \(count) reply[ies]" : "Hide replies"` (`CommentThreadRow.swift:402-404, 1288`, Accessibility label) | `if (isCollapsed) "Show $replyCount" else "Hide"` (`CommentThreadComponents.kt:515`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Show \(count) replies"` / `"Hide replies"`, Android TalkBack: `"Show $replyCount"` / `"Hide"`) |
| `role == .me ? "Your comment" : "Work author"` (`CommentThreadRow.swift:323-324`, Accessibility label) | `contentDescription = role.label` (`"Me"` / `"Author"`) (`CommentThreadComponents.kt:665`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Your comment"` / `"Work author"`, Android TalkBack: `"Me"` / `"Author"`) |
| `"Opens the rest of this thread on the AO3 website"` (`CommentThreadRow.swift:1172`, Accessibility hint) | — | **missing on Android** |
| `"Reply to your comment"` / `"Reply to \(author)"` (`CommentThreadRow.swift:1357-1358`, Accessibility hint) | — | **missing on Android** |
| `"Opens author profile"` (`CommentThreadRow.swift:1681`, Accessibility hint) | — | **missing on Android** |
| `"More formatting"` (`CommentMarkup.swift:290`, Accessibility label) | `contentDescription = "More formatting options"` (`CommentMarkup.kt:214`, TalkBack semantics) | **differs** (iOS VoiceOver: `"More formatting"`, Android TalkBack: `"More formatting options"`) |
| `"Formatting"` (`CommentMarkup.swift:410`, Format tray title) | `"Format Comment"` (`CommentMarkup.kt:250`, Format tray title) | **differs** (iOS: `"Formatting"`, Android: `"Format Comment"`) |
| `"Done"` (`CommentMarkup.swift:418`, Format tray button) | — | **missing on Android** |
| Group titles: `"Text"` and `"Blocks & links"` (`AO3Markup.swift:41-42`, `CommentMarkup.swift:436`) | Group titles: `"TEXT FORMATTING"` and `"BLOCKS & ELEMENTS"` (`CommentMarkup.kt:94-95, 260`) | **differs** (iOS: `"Text"` and `"Blocks & links"`, Android: `"TEXT FORMATTING"` and `"BLOCKS & ELEMENTS"`) |
| Heading tag label: `"h1–h6"` (`CommentMarkup.swift:104`) | Heading tag label: `"h3"` (`CommentMarkup.kt:88, 303`) | **differs** (iOS: `"h1–h6"`, Android: `"h3"`) |
| `"Heading \(level)"` (`CommentMarkup.swift:489`, Accessibility label) | `contentDescription = "Heading $level"` (`CommentMarkup.kt:326`, TalkBack semantics) | **same** |
| `"Thread"` (`CommentThreadScreen.swift:43`, Screen title) | `"Thread"` (`CommentThreadScreen.kt:78`, Screen title) | **same** |
| `threadSubtitle`: `[chapterLabel, author].joined(" · ")` (`CommentThreadScreen.swift:113-121`) | `threadSubtitle`: `listOfNotNull(chapterLabel, author).joinToString(" · ")` (`CommentThreadScreen.kt:47-51`) | **same** |
| `"Thread Unavailable"` (`CommentThreadScreen.swift:81`, Unavailable title) | `"Thread Unavailable"` (`CommentThreadScreen.kt:88`, Unavailable title) | **same** |
| `"This comment is no longer on this page. Go back to Comments to continue."` (`CommentThreadScreen.swift:83`, Unavailable description) | `"This comment is no longer on this page. Go back to Comments to continue."` (`CommentThreadScreen.kt:89`, Unavailable description) | **same** |

---

## Pair 4: Account Inbox

- **Android**: `account/AccountInboxPane.kt`, `account/AccountInboxViewModel.kt`
- **iOS**: `Features/Account/AccountInboxScreen.swift`, `Features/Account/AccountInboxViews.swift`, `Features/Account/AccountInboxFilterSheet.swift`, `Models/AO3InboxModels.swift`, `Features/Account/AccountView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Account"` (`AccountInboxScreen.swift:37`, Header kicker) | `"AO3 Account"` (`AccountInboxPane.kt:211`, Header kicker) | **same** |
| `"Inbox"` (`AccountInboxScreen.swift:38`, Header title) | `"Inbox"` (`AccountInboxPane.kt:212`, Header title) | **same** |
| Header tally pattern: `<total> comment[s] · <unread> unread · <awaiting> awaiting your reply[ on this page]` (`AO3InboxModels.swift:280-290`) | Header tally pattern: `<total> comment[s] · <unread> unread · <awaiting> awaiting your reply[ on this page]` (`AccountInboxPane.kt:1075-1088`) | **same** |
| `"All"` (`AO3InboxModels.swift:223`, Filter pill) | `"All"` (`AccountInboxPane.kt:378`, Filter pill) | **same** |
| `"Unread"` (`AO3InboxModels.swift:224`, Filter pill) | `"Unread"` (`AccountInboxPane.kt:382`, Filter pill) | **same** |
| `"Awaiting reply"` (`AO3InboxModels.swift:225`, Filter pill) | `"Awaiting reply"` (`AccountInboxPane.kt:386`, Filter pill) | **same** |
| `"Replied"` (`AO3InboxModels.swift:226`, Filter pill) | `"Replied"` (`AccountInboxPane.kt:390`, Filter pill) | **same** |
| `"Inbox Filters"` (`AccountInboxScreen.swift:222`, Toolbar button accessibility label) | `contentDescription = if (badgeCount > 0) "Filter, $badgeCount active" else "Filter"` (`SubjectComponents.kt:920`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Inbox Filters"`, Android TalkBack: `"Filter"` / `"Filter, $badgeCount active"`) |
| `"Select"` (`AccountInboxScreen.swift:231`, More menu item) | `"Select"` (`AccountInboxPane.kt:481`, More menu item) | **same** |
| `"Select Inbox Items"` (`AccountInboxViews.swift:116`, Accessibility label) | `"Select Inbox Items"` (`AccountInboxPane.kt:474`, `accessibilityName`) | **same** |
| `allSelected ? "Deselect All" : "Select All"` (`WorkBulkActionBar.swift:196`, Select all button) | `if (state.allCurrentPageSelected) "Deselect All" else "Select All"` (`AccountInboxPane.kt:433`, Select all button) | **same** |
| — | `"${state.selectedItems.size} selected"` (`AccountInboxPane.kt:437`, Selection toolbar count text) | **Android only** |
| — | `"Loading Inbox"` (`AccountInboxPane.kt:263`, Initial loading card) | **Android only** |
| `"Couldn't load your inbox"` (`AccountInboxViews.swift:528`, Failure title) | `"Couldn't load your inbox"` (`AccountInboxPane.kt:271`, Failure title) | **same** |
| `"Try Again"` (`AccountInboxViews.swift:531`, Failure button) | `"Try Again"` (`AccountInboxPane.kt:273`, Failure button) | **same** |
| `"No comments yet"` (`AccountInboxViews.swift:535`, Empty title) | `"No comments yet"` (`AccountInboxPane.kt:283`, Empty title) | **same** |
| `"Comments on your works and replies to your comments appear here from your AO3 inbox."` (`AccountInboxViews.swift:537-538`, Empty message) | `"Comments on your works and replies to your comments appear here from your AO3 inbox."` (`AccountInboxPane.kt:284-285`, Empty message) | **same** |
| `"Couldn't load page \(requestedPage)"` (`AccountInboxViews.swift:545`, Pagination failure title) | — | **missing on Android** |
| `"Try Again"` (`AccountInboxViews.swift:548`, Pagination failure button) | — | **missing on Android** |
| `"Showing cached AO3 data"` (`AccountInboxViews.swift:713`, Stale cache row) | — | **missing on Android** |
| `"A comment here is unavailable"` (`AccountInboxViews.swift:271, 278`, Unavailable tombstone text and accessibility label) | `"A comment here is unavailable"` (`AccountInboxPane.kt:725`, Unavailable tombstone text) | **same** |
| `"Unread"` (`AccountInboxViews.swift:351`, Indicator accessibility label) | — | **missing on Android** (TalkBack does not announce unread circle indicator) |
| `"Replied"` (`AccountInboxViews.swift:487, 496`, Badge text and accessibility label) | `"Replied"` (`AccountInboxPane.kt:838, 954`, Badge text) | **same** |
| `role == .me ? "Your comment" : "Work author"` (`CommentThreadRow.swift:323-324`, Role accessibility label) | `contentDescription = when (role) { Me -> "Your comment"; Author -> "Work author"; else -> role.label }` (`AccountInboxPane.kt:826-829`, TalkBack semantics in AX font scale) | **same** |
| `"on"` (`AccountInboxViews.swift:382`, Subject line) | `"on"` (`AccountInboxPane.kt:907, 922`, Subject line) | **same** |
| `"of \(item.workTitle)"` (`AccountInboxViews.swift:398`, Subject line) | `"of ${item.workTitle}"` (`AccountInboxPane.kt:910, 936`, Subject line) | **same** |
| `"on \(item.subjectTitle)"` (`AccountInboxViews.swift:405`, Subject line without chapter) | `"on ${item.subjectTitle}"` (`AccountInboxPane.kt:896`, Subject line without chapter) | **same** |
| `item.excerpt` (`AccountInboxViews.swift:213`, Notification excerpt) | `item.excerpt` (`AccountInboxPane.kt:751`, Notification excerpt) | **same** |
| `CommentReplyButton(accessibilityLabel: "Reply to \(item.commenterName)")` (`AccountInboxViews.swift:226-228`, Inline card Reply button) | — | **missing on Android** |
| `"Reply"` (`AccountInboxViews.swift:249`, Card custom accessibility action) | — | **missing on Android** |
| Card accessibility container: summary `.accessibilityLabel(accessibilitySummary)`, `.accessibilityHint("Open the comment's thread")` (`AccountInboxViews.swift:239-241`) | — | **missing on Android** (TalkBack does not group the notification card into a single summary element) |
| Selection card accessibility semantics: `.accessibilityValue(isSelected ? "Selected" : "Not selected")`, `.accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this notification.")` (`AccountInboxViews.swift:163-164`) | — | **missing on Android** (TalkBack does not announce selection value or hint on card) |
| `"Open Comment"` (`AccountInboxViews.swift:433`, Overflow menu item when workID is nil) | — | **missing on Android** (when workID is null, no Open item is rendered in menu) |
| `"Open Thread"` (`AccountInboxViews.swift:433`, Overflow menu item when workID is non-nil) | `"Open Thread"` (`AccountInboxPane.kt:987`, Overflow menu item) | **same** |
| `"Chapter Comments"` (`AccountInboxViews.swift:439`, Overflow menu item) | `"Chapter Comments"` (`AccountInboxPane.kt:996`, Overflow menu item) | **same** |
| `"Copy Link"` (`AccountInboxViews.swift:251, 442`, Overflow menu item and accessibility action) | — | **missing on Android** |
| `"Inbox"` / `"Link copied."` (`AccountInboxViews.swift:171, 478`, Copy link feedback alert) | — | **missing on Android** |
| `item.isUnread ? "Mark Read" : "Mark Unread"` (`AccountInboxViews.swift:448`, Overflow menu item) | `if (item.isUnread) "Mark Read" else "Mark Unread"` (`AccountInboxPane.kt:1005, 1014`, Overflow menu item) | **same** |
| `"Delete From Inbox"` (`AccountInboxViews.swift:455`, Overflow menu item) | `"Delete From Inbox"` (`AccountInboxPane.kt:1023`, Overflow menu item) | **same** |
| `"More actions for \(item.commenterName)'s Inbox comment"` (`AccountInboxViews.swift:463`, Accessibility label) | `contentDescription = "More actions for ${item.commenterName}'s inbox comment"` (`AccountInboxPane.kt:981`, TalkBack semantics) | **differs** (iOS VoiceOver: `"More actions for \(item.commenterName)'s Inbox comment"`, Android TalkBack: `"More actions for ${item.commenterName}'s inbox comment"`) |
| `"Delete this notification from your AO3 Inbox?"` (`AccountInboxViews.swift:912`, Single delete confirmation title) | `"Delete this notification from your AO3 Inbox?"` (`AccountInboxPane.kt:131`, Single delete confirmation title) | **same** |
| `"This removes the notification from your AO3 Inbox. The comment stays on AO3."` (`AccountInboxViews.swift:919`, Single delete confirmation message) | `"This removes the notification from your AO3 Inbox. The comment stays on AO3."` (`AccountInboxPane.kt:136`, Single delete confirmation message) | **same** |
| `"Delete From Inbox"` (`AccountInboxViews.swift:916`, Single delete confirm button) | `"Delete From Inbox"` (`AccountInboxPane.kt:141`, Single delete confirm button) | **same** |
| `"Delete \(n) notification\(n == 1 ? "" : "s") from your AO3 Inbox?"` (1: `"Delete 1 notification from your AO3 Inbox?"`, 2+: `"Delete 2 notifications from your AO3 Inbox?"`) (`AccountInboxViews.swift:888-889`, Bulk delete confirmation title) | `if (pendingDelete?.items?.size == 1) "Delete this notification from your AO3 Inbox?" else "Delete ${size} notifications from your AO3 Inbox?"` (1: `"Delete this notification from your AO3 Inbox?"`, 2+: `"Delete 2 notifications from your AO3 Inbox?"`) (`AccountInboxPane.kt:130-134`, Bulk delete confirmation title) | **differs** (for 1 item bulk delete, iOS: `"Delete 1 notification from your AO3 Inbox?"`, Android: `"Delete this notification from your AO3 Inbox?"`) |
| `"This removes the selected notifications from your AO3 Inbox. Your works in Kudos aren't deleted."` (`AccountInboxViews.swift:898-899`, Bulk delete confirmation message) | `"This removes the selected notifications from your AO3 Inbox. Your works in Kudos aren't deleted."` (`AccountInboxPane.kt:138-139`, Bulk delete confirmation message) | **same** |
| `"Delete From Inbox"` (`AccountInboxViews.swift:893`, Bulk delete confirm button) | `"Delete From Inbox"` (`AccountInboxPane.kt:141`, Bulk delete confirm button) | **same** |
| `"Cancel"` (`AccountInboxViews.swift:896, 917`, Delete cancel button) | `"Cancel"` (`DestructiveConfirmation.kt:29`, Delete cancel button) | **same** |
| `"Delete"` (`AccountInboxViews.swift:848`, Bulk bar button visible label) | `"Delete"` (`AccountInboxPane.kt:539`, Bulk bar button visible label) | **same** |
| `"Mark Read"` (`AccountInboxViews.swift:862`, Bulk bar button accessibility label) | `contentDescription = "Mark Read"` (`AccountInboxPane.kt:548`, TalkBack semantics) | **same** |
| `"Mark Unread"` (`AccountInboxViews.swift:873`, Bulk bar button accessibility label) | `contentDescription = "Mark Unread"` (`AccountInboxPane.kt:557`, TalkBack semantics) | **same** |
| `"Done"` (`AccountInboxViews.swift:885`, Bulk bar button accessibility label) | `contentDescription = "Done"` (`AccountInboxPane.kt:563`, TalkBack semantics) | **same** |
| `"Inbox Filters"` (`AccountInboxFilterSheet.swift:61`, Sheet title) | `"Inbox Filters"` (`AccountInboxPane.kt:599`, Sheet title) | **same** |
| `"Done"` (`AccountInboxFilterSheet.swift:70`, Sheet button accessibility label) | `contentDescription = "Done"` (`AccountInboxPane.kt:607`, TalkBack semantics) | **same** |
| `field.title` (`AccountInboxFilterSheet.swift:18`, Filter group label) | `field.title` (`AccountInboxPane.kt:622`, Filter group label) | **same** |
| `option.label` (`AccountInboxFilterSheet.swift:27`, Filter option label) | `option.label` (`AccountInboxPane.kt:629`, Filter option label) | **same** |
| VoiceOver trait `.isSelected` (`AccountInboxFilterSheet.swift:49`) | `contentDescription = "Selected"` (`AccountInboxPane.kt:635`, TalkBack semantics) | **differs** (iOS VoiceOver: `.isSelected` trait, Android TalkBack: `"Selected"` icon description) |
| `"Couldn't update Inbox"` (`AccountInboxScreen.swift:114`, Error alert title) | `"Couldn't update Inbox"` (`AccountInboxPane.kt:173`, Error alert title) | **same** |
| `model.actionError ?? "AO3 couldn't update your Inbox."` (`AccountInboxScreen.swift:117`, Error alert message) | `state.actionError ?: "AO3 couldn't update your Inbox."` (`AccountInboxPane.kt:174`, Error alert message) | **same** |
| `"OK"` (`AccountInboxScreen.swift:115`, Error alert button) | `"OK"` (`AccountInboxPane.kt:176`, Error alert button) | **same** |
| — | `"Previous"` (`AccountInboxPane.kt:1055`, Inline pagination button) | **Android only** |
| — | `"Page $page of $totalPages"` (`AccountInboxPane.kt:1058`, Inline pagination text) | **Android only** |
| — | `"Next"` (`AccountInboxPane.kt:1070`, Inline pagination button) | **Android only** |
| — | `state.actionNotice?.let { ... }` inline banner with message and `"OK"` button (`AccountInboxPane.kt:248, 253`) | **Android only** |

---

## Pair 5: Pagination Bar & Page Sheet

- **Android**: `ui/components/KudosPaginationBar.kt`
- **iOS**: `Features/Search/SearchPaginationBar.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"First page"` (`SearchPaginationBar.swift:181, 217`, Previous chevron context menu) | `"First Page"` (`KudosPaginationBar.kt:82`, First page icon button TalkBack semantics) | **differs** (iOS context menu: `"First page"`, Android button: `"First Page"`) |
| `"Previous page"` (`SearchPaginationBar.swift:220`, Previous chevron accessibility label) | `contentDescription = "Previous Page"` (`KudosPaginationBar.kt:85`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Previous page"`, Android TalkBack: `"Previous Page"`) |
| `"Next page"` (`SearchPaginationBar.swift:220`, Next chevron accessibility label) | `contentDescription = "Next Page"` (`KudosPaginationBar.kt:102`, TalkBack semantics) | **differs** (iOS VoiceOver: `"Next page"`, Android TalkBack: `"Next Page"`) |
| `"Last page"` (`SearchPaginationBar.swift:181, 217`, Next chevron context menu) | `"Last Page"` (`KudosPaginationBar.kt:105`, Last page icon button TalkBack semantics) | **differs** (iOS context menu: `"Last page"`, Android button: `"Last Page"`) |
| Visible position text: `"Page \(currentPage)"` and `"/ \(totalPages.formatted())"` (`SearchPaginationBar.swift:135, 142`) | Visible position text: `"Page $currentPage of $totalPages"` (`KudosPaginationBar.kt:92`) | **differs** (iOS: `"Page \(currentPage) / \(totalPages)"`, Android: `"Page $currentPage of $totalPages"`) |
| `"Page \(currentPage) of \(totalPages)"` (`SearchPaginationBar.swift:63`, Accessibility label) | `Text("Page $currentPage of $totalPages")` (`KudosPaginationBar.kt:92`, Inherited TalkBack label) | **same** |
| `"Opens the page picker."` (`SearchPaginationBar.swift:64`, Accessibility hint) | — | **missing on Android** |
| `"Go to page"` (`SearchPaginationBar.swift:343`, Sheet header title) | — | **missing on Android** |
| `"Cancel"` (`SearchPaginationBar.swift:339`, Close icon button accessibility name) | `"Cancel"` (`KudosPaginationBar.kt:244`, Bottom outlined button text) | **same** |
| `"Go to page \(draftPage)"` (`SearchPaginationBar.swift:350`, Confirm icon button accessibility name) | `"Go"` (`KudosPaginationBar.kt:254`, Bottom confirm button visible text) | **differs** (iOS VoiceOver name: `"Go to page \(draftPage)"`, Android visible text: `"Go"`) |
| `"Page number"` (uppercased `"PAGE NUMBER"`) (`SearchPaginationBar.swift:374`, Section label) | — | **missing on Android** |
| `"Page"` (`SearchPaginationBar.swift:376`, Text field placeholder) | — | **missing on Android** |
| `"of \(totalPages.formatted())"` (`SearchPaginationBar.swift:392`, Total text beside field) | `"of $totalPages"` (`KudosPaginationBar.kt:162`, Slider readout subtitle) | **same** |
| — | `"$draftPage"` (`KudosPaginationBar.kt:157`, Slider readout display text) | **Android only** |
| `"Nearby"` (uppercased `"NEARBY"`) (`SearchPaginationBar.swift:411`, Section label) | `"Nearby"` (`KudosPaginationBar.kt:186`, Section label) | **same** |
| `"Page \(page)"` (`SearchPaginationBar.swift:425`, Tile accessibility label) | `contentDescription = "Page $page"` (`KudosPaginationBar.kt:205`, Tile TalkBack semantics) | **same** |
| `"First page"` (`SearchPaginationBar.swift:449`, End button label) | `"First page"` (`KudosPaginationBar.kt:229`, End button label) | **same** |
| `"Last (\(totalPages.formatted()))"` (`SearchPaginationBar.swift:451`, End button label) | `"Last (${"%,d".format(totalPages)})"` (`KudosPaginationBar.kt:235`, End button label) | **same** |

---

## Pair 6: Collection Form

- **Android**: `account/AO3CollectionFormScreen.kt`, `account/AO3CollectionFormState.kt`, `network/ao3/account/AO3CollectionForm.kt`
- **iOS**: `Features/Account/AO3CollectionFormView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Account › Collections"` (`AO3CollectionFormView.swift:225`, Header kicker) | `"AO3 Account › Collections"` (`AO3CollectionFormScreen.kt:76`, Header kicker) | **same** |
| `isNew ? "New collection" : "Edit collection"` (`AO3CollectionFormView.swift:226`, Header title) | `if (slug == null) "New collection" else "Edit collection"` (`AO3CollectionFormScreen.kt:75`, Header title) | **same** |
| `"Your changes are saved to AO3"` (`AO3CollectionFormView.swift:227`, Header subtitle) | `"Your changes are saved to AO3"` (`AO3CollectionFormScreen.kt:76`, Header subtitle) | **same** |
| `"Couldn't open the form"` (`AO3CollectionFormView.swift:77`, Error label) | `"Couldn't open the form"` (`AO3CollectionFormScreen.kt:83`, Error section label) | **same** |
| `"Try Again"` (`AO3CollectionFormView.swift:81`, Error retry button) | `"Try Again"` (`AO3CollectionFormScreen.kt:85`, Error retry action) | **same** |
| `"Header"` (`AO3CollectionFormView.swift:132`, Section header) | `"Header"` (`AO3CollectionFormScreen.kt:98`, Section header) | **same** |
| `"The collection name is part of its web address. Use letters, numbers and underscores. You can't change it after creating the collection."` (`AO3CollectionFormView.swift:382-383`, Header footnote) | `"The collection name is part of its web address. Use letters, numbers and underscores. You can't change it after creating the collection."` (`AO3CollectionFormScreen.kt:98-99`, Header footnote) | **same** |
| `"Display title"` (`AO3CollectionFormView.swift:133`, Row label) | `"Display title"` (`AO3CollectionFormScreen.kt:100`, Row label) | **same** |
| `"Required"` (`AO3CollectionFormView.swift:134`, Placeholder) | `"Required"` (`AO3CollectionFormScreen.kt:105`, Placeholder) | **same** |
| `"Collection name"` (`AO3CollectionFormView.swift:300`, Row label) | `"Collection name"` (`AO3CollectionFormScreen.kt:100`, Row label) | **same** |
| `"Required"` (`AO3CollectionFormView.swift:305`, Placeholder) | `"Required"` (`AO3CollectionFormScreen.kt:105`, Placeholder) | **same** |
| `"Name is available"` (`AO3CollectionFormView.swift:332`, Accessibility label on checkmark icon) | `"Name is available"` (`AO3CollectionFormScreen.kt:113`, Visible text below row) | **differs** (iOS VoiceOver label: `"Name is available"`, Android visible text: `"Name is available"`) |
| `"Name is taken"` (`AO3CollectionFormView.swift:336`, Accessibility label on xmark icon) | `"Name is taken"` (`AO3CollectionFormScreen.kt:114`, Visible text below row) | **differs** (iOS VoiceOver label: `"Name is taken"`, Android visible text: `"Name is taken"`) |
| `"Name is not a valid collection name"` (`AO3CollectionFormView.swift:340`, Accessibility label on warning icon) | `"Name is not a valid collection name"` (`AO3CollectionFormScreen.kt:115`, Visible text below row) | **differs** (iOS VoiceOver label: `"Name is not a valid collection name"`, Android visible text: `"Name is not a valid collection name"`) |
| `"Parent collection"` (`AO3CollectionFormView.swift:138`, Row label) | `"Parent collection"` (`AO3CollectionFormScreen.kt:101`, Row label) | **same** |
| `"None"` (`AO3CollectionFormView.swift:139`, Placeholder) | `"None"` (`AO3CollectionFormScreen.kt:106`, Placeholder) | **same** |
| `"Contact email"` (`AO3CollectionFormView.swift:141`, Row label) | `"Contact email"` (`AO3CollectionFormScreen.kt:101`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:142`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:107`, Placeholder) | **same** |
| `"Tagline"` (`AO3CollectionFormView.swift:144`, Row label) | `"Tagline"` (`AO3CollectionFormScreen.kt:101`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:145`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:107`, Placeholder) | **same** |
| `"Images"` (`AO3CollectionFormView.swift:148`, Section header) | `"Images"` (`AO3CollectionFormScreen.kt:127`, Section header) | **same** |
| `"Header image URL"` (`AO3CollectionFormView.swift:149`, Row label) | `"Header image URL"` (`AO3CollectionFormScreen.kt:128`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:150`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:131`, Placeholder) | **same** |
| `"Header image alt text"` (`AO3CollectionFormView.swift:152`, Row label) | `"Header image alt text"` (`AO3CollectionFormScreen.kt:128`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:153`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:131`, Placeholder) | **same** |
| `"Icon alt text"` (`AO3CollectionFormView.swift:155`, Row label) | `"Icon alt text"` (`AO3CollectionFormScreen.kt:129`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:156`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:131`, Placeholder) | **same** |
| `"Icon comment"` (`AO3CollectionFormView.swift:158`, Row label) | `"Icon comment"` (`AO3CollectionFormScreen.kt:129`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:159`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:131`, Placeholder) | **same** |
| `"Preferences"` (`AO3CollectionFormView.swift:162`, Section header) | `"Preferences"` (`AO3CollectionFormScreen.kt:137`, Section header) | **same** |
| `"Closed to new items"` (`AO3CollectionFormView.swift:163`, Row label) | `"Closed to new items"` (`AO3CollectionFormScreen.kt:140`, Row label) | **same** |
| `"Moderated"` (`AO3CollectionFormView.swift:165`, Row label) | `"Moderated"` (`AO3CollectionFormScreen.kt:140`, Row label) | **same** |
| `"Unrevealed"` (`AO3CollectionFormView.swift:167`, Row label) | `"Unrevealed"` (`AO3CollectionFormScreen.kt:140`, Row label) | **same** |
| `"Anonymous"` (`AO3CollectionFormView.swift:169`, Row label) | `"Anonymous"` (`AO3CollectionFormScreen.kt:141`, Row label) | **same** |
| `"Email new items"` (`AO3CollectionFormView.swift:173`, Row label) | `"Email new items"` (`AO3CollectionFormScreen.kt:141`, Row label) | **same** |
| `"You can turn on any combination of these settings. Unrevealed shows each work as Mystery Work, Anonymous hides its creators, and new-item emails go to the contact email."` (`AO3CollectionFormView.swift:387-388`, Preferences footnote) | `"You can turn on any combination of these settings. Unrevealed shows each work as Mystery Work, Anonymous hides its creators, and new-item emails go to the contact email."` (`AO3CollectionFormScreen.kt:137-138`, Preferences footnote) | **same** |
| `"Challenge"` (`AO3CollectionFormView.swift:178`, Section header) | `"Challenge"` (`AO3CollectionFormScreen.kt:151`, Section header) | **same** |
| `"Set up a challenge"` (`AO3CollectionFormView.swift:180`, Row label) | `"Set up a challenge"` (`AO3CollectionFormScreen.kt:153`, Row label) | **same** |
| `"None"` (`AO3CollectionFormView.swift:186`, Option placeholder) | `"None"` (`AO3CollectionFormScreen.kt:155, 160`, Option placeholder) | **same** |
| `"Profile"` (`AO3CollectionFormView.swift:198`, Section header) | `"Profile"` (`AO3CollectionFormScreen.kt:170`, Section header) | **same** |
| `"Introduction"` (`AO3CollectionFormView.swift:199`, Row label) | `"Introduction"` (`AO3CollectionFormScreen.kt:171`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:200`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:174`, Placeholder) | **same** |
| `"FAQ"` (`AO3CollectionFormView.swift:202`, Row label) | `"FAQ"` (`AO3CollectionFormScreen.kt:171`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:203`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:174`, Placeholder) | **same** |
| `"Rules"` (`AO3CollectionFormView.swift:205`, Row label) | `"Rules"` (`AO3CollectionFormScreen.kt:171`, Row label) | **same** |
| `"Optional"` (`AO3CollectionFormView.swift:206`, Placeholder) | `"Optional"` (`AO3CollectionFormScreen.kt:174`, Placeholder) | **same** |
| `isNew ? "Create Collection" : "Save Changes"` (`AO3CollectionFormView.swift:397`, Save button text) | `if (slug == null) "Create Collection" else "Save Changes"` (`AO3CollectionFormScreen.kt:71, 180`, Save button text) | **same** |
| `"Collection actions"` (`AO3CollectionFormView.swift:419`, Section header) | `"Collection actions"` (`AO3CollectionFormScreen.kt:183`, Section header) | **same** |
| `"Open AO3 to close this collection. Deleting the collection leaves its works on AO3."` (`AO3CollectionFormView.swift:421`, Section footnote) | `"Open AO3 to close this collection. Deleting the collection leaves its works on AO3."` (`AO3CollectionFormScreen.kt:184-185`, Section footnote) | **same** |
| `"Open Collection Settings on AO3"` (`AO3CollectionFormView.swift:426`, Action row) | `"Open Collection Settings on AO3"` (`AO3CollectionFormScreen.kt:186`, Action row) | **same** |
| `"Delete Collection"` (`AO3CollectionFormView.swift:436`, Action row) | `"Delete Collection"` (`AO3CollectionFormScreen.kt:187`, Action row) | **same** |
| `"Delete “\(deletionName)”?"` (`AO3CollectionFormView.swift:93`, Alert title) | `"Delete “${form.deletionName}”?"` (`AO3CollectionFormScreen.kt:196`, Dialog title) | **same** |
| `"This removes the collection, its challenge settings and any gift assignments from AO3. The works stay with their creators. Unrevealed works become visible, and anonymous works show their creators. Type the collection name to confirm."` (`AO3CollectionFormView.swift:598-600`, Alert message) | `"This removes the collection, its challenge settings and any gift assignments from AO3. The works stay with their creators. Unrevealed works become visible, and anonymous works show their creators. Type the collection name to confirm."` (`AO3CollectionForm.kt:32-34`, `AO3CollectionFormScreen.kt:198`, Dialog message) | **same** |
| — | `"Collection name"` (`AO3CollectionFormScreen.kt:199`, Text field label in deletion dialog) | **Android only** |
| `deletionName` (`AO3CollectionFormView.swift:96`, Alert text field placeholder) | `form.deletionName` (`AO3CollectionFormScreen.kt:199`, Dialog text field placeholder) | **same** |
| `"Cancel"` (`AO3CollectionFormView.swift:98`, Alert cancel button) | `"Cancel"` (`AO3CollectionFormScreen.kt:207`, Dialog cancel button) | **same** |
| `"Delete on AO3"` (`AO3CollectionFormView.swift:99`, Alert confirm button) | `"Delete on AO3"` (`AO3CollectionFormScreen.kt:205`, Dialog confirm button) | **same** |
| `"Not saved: your AO3 session changed since this form opened. Your edits are still here, and Save works again once \(formUsername ?? "that account") is signed in. To edit as another account, reopen the form."` (`AO3CollectionFormView.swift:515-517`, Save error) | `"Not saved: your AO3 session changed since this form opened. Your edits are still here, and Save works again once ${formUsername ?: "that account"} is signed in. To edit as another account, reopen the form."` (`AO3CollectionFormState.kt:165-166`, Save error) | **same** |
| Cancellation on save: `"Not saved: your AO3 session changed since this form opened. Your edits are still here, and Save works again once \(formUsername ?? "that account") is signed in. To edit as another account, reopen the form."` (`AO3CollectionFormView.swift:515-517`) | Cancellation on save: `"Not saved: your AO3 session changed since this form opened."` (`AO3CollectionFormState.kt:138`) | **differs** (iOS reports full explanation, Android truncates) |
| `"Not deleted: your AO3 session changed since this form opened."` (`AO3CollectionFormView.swift:586`, Delete error) | `"Not deleted: your AO3 session changed since this form opened."` (`AO3CollectionFormState.kt:156`, Delete error) | **same** |
| `"You need to log in to AO3 to do this."` (`AO3Error.authenticationRequired`, Load error) | `"Log in to AO3 first."` (`AO3CollectionFormState.kt:59`, Load error) | **differs** (iOS: `"You need to log in to AO3 to do this."`, Android: `"Log in to AO3 first."`) |
| — | `"AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."` (`AO3CollectionForm.kt:31`, `AO3CollectionFormState.kt:178`, Unconfirmed write error) | **Android only** |

---

## Missing on Android (Most Visible First)

1. **Card Reply button and action in Account Inbox**: On iOS, every inbox notification row for a comment that allows replies has an inline `"Reply to \(commenter)"` button (`AccountInboxViews.swift:226-228`) and a `"Reply"` custom accessibility action (`AccountInboxViews.swift:249`). Android (`AccountInboxPane.kt:760-778`) omits the Reply button entirely from the item card and the overflow menu.
2. **"Copy Link" in Account Inbox card overflow menu**: On iOS, the overflow menu has `"Copy Link"` (`AccountInboxViews.swift:442`), custom accessibility action `"Copy Link"` (`AccountInboxViews.swift:251`), and feedback alert `"Inbox"` / `"Link copied."` (`AccountInboxViews.swift:171, 478`). Android (`AccountInboxPane.kt:984-1031`) omits Copy Link from the overflow menu entirely.
3. **"Open Comment" in Account Inbox card overflow menu**: On iOS, when `item.workID == nil`, the menu action reads `"Open Comment"` instead of `"Open Thread"` (`AccountInboxViews.swift:433`). On Android, if `workId == null`, no open action is rendered in the overflow menu at all (`AccountInboxPane.kt:985`).
4. **Offline stale cache banner in Comments**: On iOS, when comments are viewed from cache while offline, a banner displays: `"You're offline. These comments are from \(fetched) and may be out of date."` (`CommentsView.swift:760`). Android (`CommentsScreen.kt`) has no stale cache banner.
5. **Stale cache row in Account Inbox**: On iOS, when inbox comments are displayed from cache, the first row of the panel reads: `"Showing cached AO3 data"` (`AccountInboxViews.swift:713`). Android (`AccountInboxPane.kt`) omits this row.
6. **Chapter picker error state in Comments**: On iOS, when chapters fail to load, `ChapterPickerSheet` shows a full error view with title `"Couldn't Load Chapters"` (`CommentsView.swift:966`) and message `"Check your connection and try again."` (`CommentsView.swift:970`). Android (`CommentsScreen.kt:781`) renders an empty list with no error card.
7. **Number input field in Pagination Jump Sheet**: On iOS, `PageJumpSheet` features a section header `"Page number"` / `"PAGE NUMBER"` (`SearchPaginationBar.swift:374`) with an exact number text field placeholder `"Page"` (`SearchPaginationBar.swift:376`). Android (`KudosPaginationBar.kt:156-179`) uses a continuous slider without a manual number input field or section label.
8. **Sheet header title in Pagination Jump Sheet**: On iOS, `PageJumpSheet` displays a navigation title `"Go to page"` (`SearchPaginationBar.swift:343`). Android's `PageScrubberSheet` (`KudosPaginationBar.kt:147`) has no header bar or title.
9. **"Done" button in Comment Formatting Tray**: On iOS, the formatting tray header has a `"Done"` dismissal button (`CommentMarkup.swift:418`). Android (`CommentMarkup.kt:249-256`) has no Done button in the header.
10. **Pagination failure state in Account Inbox**: On iOS, when turning to an inbox page fails, a status row appears below the loaded items: `"Couldn't load page \(requestedPage)"` with action `"Try Again"` (`AccountInboxViews.swift:545, 548`). Android (`AccountInboxPane.kt`) has no pagination failure state.
11. **Submission status banner in Comment Composer**: On iOS, `CommentComposerSheet` renders a live submission status banner: `"We're checking whether this posted before trying again…"` (`CommentsView.swift:1499`), button `"Check Again"` (`CommentsView.swift:1513`), `"Posted."` (`CommentsView.swift:1523`), and ambiguous error messages `"AO3 answered but didn't confirm the comment posted. Checking whether it went through…"` and `"The connection dropped while posting. Checking whether the comment went through…"` (`CommentsErrorMessages.swift:32-35`). Android (`CommentComposerSheet.kt`) omits the submission status banner entirely.
12. **Inbox card VoiceOver container and hint**: On iOS, the entire notification card is folded into an accessible element with summary label, rotor actions, and hint `"Open the comment's thread"` (`AccountInboxViews.swift:241`). Android (`AccountInboxPane.kt`) does not group card children or announce the hint.
13. **Inbox selection card accessibility value and hint**: On iOS, the select-mode card announces `.accessibilityValue(isSelected ? "Selected" : "Not selected")` and `.accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this notification.")` (`AccountInboxViews.swift:163-164`). Android (`AccountInboxPane.kt:707`) uses `WorkSelectionBubble` which has no accessibility value or hint.
14. **Unread circle indicator accessibility label in Account Inbox**: On iOS, the unread circle carries `.accessibilityLabel("Unread")` (`AccountInboxViews.swift:351`). On Android (`AccountInboxPane.kt:809, 860`), the unread box has no contentDescription.
15. **Comment composer text editor accessibility label**: On iOS, the editor carries `.accessibilityLabel(isEdit ? "Edit comment text" : "Comment text")` (`CommentsView.swift:1383`). On Android (`CommentComposerSheet.kt:236`), `BasicTextField` has no contentDescription.
16. **Filter rail pills accessibility values in Comments**: On iOS, the chapter pill carries `.accessibilityValue(chapterPillTitle)` (`CommentsView.swift:586`) and the sort pill carries `.accessibilityValue(model.newestFirst ? "Newest First" : "Oldest First")` (`CommentsView.swift:630`). Android (`CommentsScreen.kt:481, 499`) omits accessibility values.
17. **Pagination position button accessibility hint**: On iOS, the centre position label on `SearchPaginationBar` carries `.accessibilityHint("Opens the page picker.")` (`SearchPaginationBar.swift:64`). Android (`KudosPaginationBar.kt:90`) has no accessibility hint.
18. **Expand nested replies button accessibility hint**: On iOS, `"Show \(count) more replies"` carries `.accessibilityHint("Expands nested replies for this comment")` (`CommentThreadRow.swift:1627`). Android (`CommentThreadComponents.kt:339`) has no accessibility hint.
19. **Deep thread cutoff accessibility hint**: On iOS, the deep thread row carries `.accessibilityHint("Opens the rest of this thread on the AO3 website")` (`CommentThreadRow.swift:1172`). Android (`CommentThreadComponents.kt:603`) has no accessibility hint.
20. **Parent attribution container accessibility hint**: On iOS, parent attribution carries `.accessibilityHint("Reply to your comment")` / `"Reply to \(author)"` (`CommentThreadRow.swift:1357-1358`). Android (`CommentThreadComponents.kt:468`) has no accessibility hint.
21. **Author profile avatar accessibility hint**: On iOS, commenter avatars carry `.accessibilityHint("Opens author profile")` (`CommentThreadRow.swift:1681`). Android (`CommentThreadComponents.kt:652`) has no accessibility hint.

---

## Differs (Most Visible First)

1. **Comment header kicker**:
   - iOS: `"AO3 Comments"` (`CommentsView.swift:476`)
   - Android: `workTitle` (work title text) (`CommentsScreen.kt:394`)
2. **Comment formatting tray title**:
   - iOS: `"Formatting"` (`CommentMarkup.swift:410`)
   - Android: `"Format Comment"` (`CommentMarkup.kt:250`)
3. **Comment formatting tray group titles**:
   - iOS: `"Text"` and `"Blocks & links"` (`AO3Markup.swift:41-42`, `CommentMarkup.swift:436`)
   - Android: `"TEXT FORMATTING"` and `"BLOCKS & ELEMENTS"` (`CommentMarkup.kt:94-95, 260`)
4. **Comment formatting tray heading tag label**:
   - iOS: `"h1–h6"` (`CommentMarkup.swift:104`)
   - Android: `"h3"` (`CommentMarkup.kt:88, 303`)
5. **Pagination bar position button visible text**:
   - iOS: `"Page \(currentPage)"` and `"/ \(totalPages.formatted())"` (`SearchPaginationBar.swift:135, 142`)
   - Android: `"Page $currentPage of $totalPages"` (`KudosPaginationBar.kt:92`)
6. **Expand nested replies button label**:
   - iOS: `"Show \(count) more replies"` (`CommentThreadRow.swift:1617`)
   - Android: `"Show ${item.hiddenCount} more"` (`CommentThreadComponents.kt:339`)
7. **Comment error retry button under authentication failure**:
   - iOS: `"Try Again"` (`CommentsView.swift:669`)
   - Android: `"Log in to AO3"` (`CommentsScreen.kt:562`)
8. **Collection form name availability indicators**:
   - iOS: Checkmark/xmark/exclamation icons with accessibility labels `"Name is available"`, `"Name is taken"`, `"Name is not a valid collection name"` (`AO3CollectionFormView.swift:332, 336, 340`)
   - Android: Visible text rows below the field: `"Name is available"`, `"Name is taken"`, `"Name is not a valid collection name"` (`AO3CollectionFormScreen.kt:113-115`)
9. **Collection form save error under cancellation**:
   - iOS: `"Not saved: your AO3 session changed since this form opened. Your edits are still here, and Save works again once \(formUsername ?? "that account") is signed in. To edit as another account, reopen the form."` (`AO3CollectionFormView.swift:515-517`)
   - Android: `"Not saved: your AO3 session changed since this form opened."` (`AO3CollectionFormState.kt:138`)
10. **Collection form signed-out load error**:
    - iOS: `"You need to log in to AO3 to do this."` (`AO3Error.authenticationRequired`)
    - Android: `"Log in to AO3 first."` (`AO3CollectionFormState.kt:59`)
11. **Inbox bulk delete confirmation title when 1 item selected**:
    - iOS: `"Delete 1 notification from your AO3 Inbox?"` (`AccountInboxViews.swift:888-889`)
    - Android: `"Delete this notification from your AO3 Inbox?"` (`AccountInboxPane.kt:131`)
12. **Pagination sheet confirm action**:
    - iOS: Checkmark icon button with VoiceOver label `"Go to page \(draftPage)"` (`SearchPaginationBar.swift:350`)
    - Android: Button with visible text `"Go"` (`KudosPaginationBar.kt:254`)
13. **Pagination bar previous/next buttons TalkBack / VoiceOver labels**:
    - iOS: `"Previous page"`, `"Next page"` (`SearchPaginationBar.swift:220`)
    - Android: `"Previous Page"`, `"Next Page"` (`KudosPaginationBar.kt:85, 102`)
14. **Pagination bar first/last page buttons on bar**:
    - iOS: Long-press context menu items `"First page"`, `"Last page"` (`SearchPaginationBar.swift:181, 217`)
    - Android: Dedicated icon buttons with TalkBack labels `"First Page"`, `"Last Page"` (`KudosPaginationBar.kt:82, 105`)
15. **Comment participant role badge TalkBack / VoiceOver label**:
    - iOS: `role == .me ? "Your comment" : "Work author"` (`CommentThreadRow.swift:323-324`)
    - Android: Literal badge text `role.label` (`"Me"` / `"Author"`) (`CommentThreadComponents.kt:665`)
16. **Comment collapse toggle TalkBack / VoiceOver label**:
    - iOS: `isCollapsed ? "Show \(count) reply[ies]" : "Hide replies"` (`CommentThreadRow.swift:402-404, 1288`)
    - Android: `if (isCollapsed) "Show $replyCount" else "Hide"` (`CommentThreadComponents.kt:515`)
17. **Comment row Reply button TalkBack / VoiceOver label**:
    - iOS: `"Reply to \(comment.author)"` (`CommentThreadRow.swift:1433`)
    - Android: `"Reply"` (`CommentThreadComponents.kt:753`)
18. **Comment formatting bar "More" button TalkBack / VoiceOver label**:
    - iOS: `"More formatting"` (`CommentMarkup.swift:290`)
    - Android: `"More formatting options"` (`CommentMarkup.kt:214`)
19. **Account Inbox card overflow menu TalkBack / VoiceOver label**:
    - iOS: `"More actions for \(item.commenterName)'s Inbox comment"` (`AccountInboxViews.swift:463` — capitalized `"Inbox"`)
    - Android: `"More actions for ${item.commenterName}'s inbox comment"` (`AccountInboxPane.kt:981` — lowercase `"inbox"`)
20. **Account Inbox toolbar filter button TalkBack / VoiceOver label**:
    - iOS: `"Inbox Filters"` (`AccountInboxScreen.swift:222`)
    - Android: `contentDescription = if (badgeCount > 0) "Filter, $badgeCount active" else "Filter"` (`SubjectComponents.kt:920`)
21. **Account Inbox filter sheet selected option TalkBack / VoiceOver semantics**:
    - iOS: `.accessibilityAddTraits(isSelected ? .isSelected : [])` (`AccountInboxFilterSheet.swift:49`)
    - Android: Checkmark icon with `contentDescription = "Selected"` (`AccountInboxPane.kt:635`)
22. **Comments stat strip cell TalkBack / VoiceOver labels**:
    - iOS: `"\(total.formatted()) comments on AO3"`, `"\(figures.threads.formatted()) conversations loaded"`, `"\(figures.mine.formatted()) of the loaded comments are yours"`, `"Newest loaded comment \(latest)"` (`CommentsView.swift:521, 528, 540, 549`)
    - Android: `"${cell.value} Comments"`, `"${cell.value} Threads"`, `"${cell.value} Yours"`, `"${cell.value} Latest"` (`SubjectComponents.kt:591`)
