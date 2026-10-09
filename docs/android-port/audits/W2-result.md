# W2 Audit: Words on Newly Ported Android Screens Checked Against iOS

This audit compares every reader-visible and reader-audible string (titles, kickers, subtitles, section headers, row labels, values, placeholders, footnotes, buttons, menu items, alerts, empty/loading/failure states, and accessibility labels, hints, and action names) across the 11 screen pairs ported on 2026-10-08 and 2026-10-09.

- **iOS path**: `kudos-ao3-reader/`
- **Android path**: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`

Excluded from "differs":
- Words naming platform-specific features Android does not have (e.g. iOS drag-to-reorder gestures vs Android reorder buttons).
- Changes recorded in `/Users/cidy02/kudos-android-lane/docs/android-port/DECISIONS.md`:
  - `## 2026-10-08: the work form's Chapters list reads only, and reads once (brief 3bm)`
  - `## 2026-10-08: a challenge sign-up can be filled in and submitted (brief 3bl)`
  - `## 2026-10-08: Reading History is grouped (brief 3bp)`
  - `## 2026-10-08: the work form saves (brief 3bo)`
  - `## 2026-10-08: Favorites has its four scopes (brief 3bq)`
  - `## 2026-10-08: a posted work's tags can be edited (brief 3bt)`
  - `## 2026-10-08: More on AO3 has iOS's rows, and they open`
  - `## 2026-10-09: a writer's series can be edited (brief 3bw)`
  - `## 2026-10-09: chapters can be added, edited, posted and deleted (brief 3bu)`
  - `## 2026-10-09: the Account shortcuts editor, and an author's works sorted (brief 3by)`
  - `## 2026-10-09: a write that has been sent is never called "not saved" (audit A24)`
  - `## 2026-10-09: what a sent write says, continued (audit A26)` (unconfirmed chapter delete and series removal omit prefix "was not deleted" / "was not removed").
  - `## 2026-10-09: no Account shortcuts is a choice (audit A27-11)`

---

## Pair 1: Writing Work Form

- **Android**: `writing/WritingWorkFormScreen.kt`, `WritingWorkFormState.kt`
- **iOS**: `Features/Writing/WorkEditView.swift`, `WritingFormFields.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Writing"` (`WorkEditView.swift:65`, Header kicker) | `"Writing"` (`WritingWorkFormScreen.kt:144`) | **same** |
| `state.isNewWork ? "New Work" : "Edit Work"` (`WorkEditView.swift:66`, Header title) | `if (state.isNewWork) "New Work" else "Edit Work"` (`WritingWorkFormScreen.kt:145`) | **same** |
| `subtitle(for: form)` (`WorkEditView.swift:400-405`, Header subtitle: `"<title> · never posted"` or `"<title> · <n> chapter[s]"`) | `subtitle` pattern (`WritingWorkFormState.kt:66-70`) | **same** |
| `"Rating"` (`WorkEditView.swift:76`, Section header) | `"Rating"` (`WritingWorkFormScreen.kt:151`) | **same** |
| `"Rating"` (`WorkEditView.swift:265`, Row label) | `"Rating"` (`WritingWorkFormScreen.kt:153`) | **same** |
| `"Select…"` (`WritingFormFields.swift:17`, Choice placeholder) | `"Select…"` (`WritingWorkFormScreen.kt:371`) | **same** |
| Rating options: `"Not Rated"`, `"General Audiences"`, `"Teen And Up Audiences"`, `"Mature"`, `"Explicit"` (`AO3WorkForm.swift:23`) | Rating options: `"Not Rated"`, `"General Audiences"`, `"Teen And Up Audiences"`, `"Mature"`, `"Explicit"` (`WritingWorkFormScreen.kt:371`) | **same** |
| `"Archive Warnings"` (`WorkEditView.swift:80`, Section header) | `"Archive Warnings"` (`WritingWorkFormScreen.kt:156`) | **same** |
| `"Archive warnings"` (`WorkEditView.swift:268`, Row label) | `"Archive warnings ∗"` (`WritingWorkFormScreen.kt:158`, Row label) | **differs** (iOS: `"Archive warnings"`, Android: `"Archive warnings ∗"`) |
| `"Archive warnings, required"` (`WritingFormFields.swift:75`, Accessibility label) | `contentDescription = "Archive warnings ∗"` (inherits row text, `WritingWorkFormScreen.kt:158`) | **differs** (iOS accessibility label: `"Archive warnings, required"`, Android TalkBack: `"Archive warnings ∗"`) |
| `"AO3 warns readers about these four topics. Choose 'Choose Not To Use Archive Warnings' if your story has warnings you prefer not to list."` (`WorkEditView.swift:84`, Footnote) | `"AO3 warns readers about these four topics. Choose 'Choose Not To Use Archive Warnings' if your story has warnings you prefer not to list."` (`WritingWorkFormScreen.kt:160`, Footnote) | **same** |
| Warning options: `"Choose Not To Use Archive Warnings"`, `"Graphic Depictions Of Violence"`, `"Major Character Death"`, `"No Archive Warnings Apply"`, `"Rape/Non-Con"`, `"Underage"` (`AO3WorkForm.swift:24`) | Warning options: `"Choose Not To Use Archive Warnings"`, `"Graphic Depictions Of Violence"`, `"Major Character Death"`, `"No Archive Warnings Apply"`, `"Rape/Non-Con"`, `"Underage"` (`WritingWorkFormScreen.kt:371`) | **same** |
| `"Categories"` (`WorkEditView.swift:87`, Section header) | `"Categories"` (`WritingWorkFormScreen.kt:162`) | **same** |
| `"Categories"` (`WorkEditView.swift:280`, Row label) | `"Categories"` (`WritingWorkFormScreen.kt:164`, Row label) | **same** |
| Category options: `"F/F"`, `"F/M"`, `"Gen"`, `"M/M"`, `"Multi"`, `"Other"` (`AO3WorkForm.swift:25`) | Category options: `"F/F"`, `"F/M"`, `"Gen"`, `"M/M"`, `"Multi"`, `"Other"` (`WritingWorkFormScreen.kt:371`) | **same** |
| `"Tags"` (`WorkEditView.swift:90`, Section header) | `"Tags"` (`WritingWorkFormScreen.kt:168`) | **same** |
| `"Fandoms"` (`WorkEditView.swift:271`, Row label) | `"Fandoms ∗"` (`WritingWorkFormScreen.kt:170`, Row label) | **differs** (iOS: `"Fandoms"`, Android: `"Fandoms ∗"`) |
| `"Fandoms, required"` (`WritingFormFields.swift:75`, Accessibility label) | `contentDescription = "Fandoms ∗"` (inherits row text, `WritingWorkFormScreen.kt:170`) | **differs** (iOS accessibility label: `"Fandoms, required"`, Android TalkBack: `"Fandoms ∗"`) |
| `"Separate fandoms with commas. At least one fandom is required."` (`WorkEditView.swift:94`, Footnote) | `"Separate fandoms with commas. At least one fandom is required."` (`WritingWorkFormScreen.kt:172`, Footnote) | **same** |
| `"Relationships"` (`WorkEditView.swift:282`, Row label) | `"Relationships"` (`WritingWorkFormScreen.kt:174`, Row label) | **same** |
| `"Use / for romantic or sexual pairs (A/B) and & for platonic relationships (A & B)."` (`WorkEditView.swift:97`, Footnote) | `"Use / for romantic or sexual pairs (A/B) and & for platonic relationships (A & B)."` (`WritingWorkFormScreen.kt:176`, Footnote) | **same** |
| `"Characters"` (`WorkEditView.swift:284`, Row label) | `"Characters"` (`WritingWorkFormScreen.kt:178`, Row label) | **same** |
| `"Separate characters with commas."` (`WorkEditView.swift:100`, Footnote) | `"Separate characters with commas."` (`WritingWorkFormScreen.kt:180`, Footnote) | **same** |
| `"Additional tags"` (`WorkEditView.swift:286`, Row label) | `"Additional Tags"` (`WritingWorkFormScreen.kt:182`, Row label) | **differs** (iOS: `"Additional tags"`, Android: `"Additional Tags"`) |
| `"Freeform tags: genres, tropes, themes, or warnings not covered above."` (`WorkEditView.swift:103`, Footnote) | `"Freeform tags: genres, tropes, themes, or warnings not covered above."` (`WritingWorkFormScreen.kt:184`, Footnote) | **same** |
| `"Title and Creators"` (`WorkEditView.swift:106`, Section header) | `"Title and Creators"` (`WritingWorkFormScreen.kt:187`, Section header) | **same** |
| `"Title"` (`WorkEditView.swift:261`, Row label) | `"Title ∗"` (`WritingWorkFormScreen.kt:189`, Row label) | **differs** (iOS: `"Title"`, Android: `"Title ∗"`) |
| `"Title, required"` (`WorkEditView.swift:261`, Accessibility label) | `contentDescription = "Title ∗"` (inherits row text, `WritingWorkFormScreen.kt:189`) | **differs** (iOS accessibility label: `"Title, required"`, Android TalkBack: `"Title ∗"`) |
| `"Title"` (`WorkEditView.swift:262`, Placeholder) | `"Title"` (`WritingWorkFormScreen.kt:189`, Placeholder) | **same** |
| `"Author / Pseud"` (`WorkEditView.swift:265`, Row label) | `"Author / Pseud"` (`WritingWorkFormScreen.kt:192`, Row label) | **same** |
| `"Choose which of your pseuds will be listed as the author."` (`WorkEditView.swift:110`, Footnote) | `"Choose which of your pseuds will be listed as the author."` (`WritingWorkFormScreen.kt:194`, Footnote) | **same** |
| `"Language"` (`WorkEditView.swift:273`, Row label) | `"Language"` (`WritingWorkFormScreen.kt:196`, Row label) | **same** |
| `"Series and Collections"` (`WorkEditView.swift:113`, Section header) | `"Series and Collections"` (`WritingWorkFormScreen.kt:199`, Section header) | **same** |
| `"This work is part of a series"` (`WorkEditView.swift:301`, Toggle label) | `"This work is part of a series"` (`WritingWorkFormScreen.kt:201`, Toggle label) | **same** |
| `"Add to an existing series or create a new one when you post."` (`WorkEditView.swift:117`, Footnote) | `"Add to an existing series or create a new one when you post."` (`WritingWorkFormScreen.kt:203`, Footnote) | **same** |
| `"Post to collections / challenges"` (`WorkEditView.swift:309`, Toggle label) | `"Post to collections / challenges"` (`WritingWorkFormScreen.kt:205`, Toggle label) | **same** |
| `"Give the collection's short name, separated by commas."` (`WorkEditView.swift:120`, Footnote) | `"Give the collection's short name, separated by commas."` (`WritingWorkFormScreen.kt:207`, Footnote) | **same** |
| `"Text"` (`WorkEditView.swift:104`, Section header) | `"Text"` (`WritingWorkFormScreen.kt:210`, Section header) | **same** |
| `"Summary"` (`WorkEditView.swift:420`, Row label) | `"Summary"` (`WritingWorkFormScreen.kt:212`, Row label) | **same** |
| `"Beginning notes"` (`WorkEditView.swift:423`, Row label) | `"Beginning Notes"` (`WritingWorkFormScreen.kt:215`, Row label) | **differs** (iOS: `"Beginning notes"`, Android: `"Beginning Notes"`) |
| `"End notes"` (`WorkEditView.swift:425`, Row label) | `"End Notes"` (`WritingWorkFormScreen.kt:218`, Row label) | **differs** (iOS: `"End notes"`, Android: `"End Notes"`) |
| `"Work text"` (`WorkEditView.swift:428`, Row label) | `"Work Text"` (`WritingWorkFormScreen.kt:222`, Row label) | **differs** (iOS: `"Work text"`, Android: `"Work Text"`) |
| `"Chapters"` (`WorkEditView.swift:442`, Row label) | `"Chapters"` (`WritingWorkFormScreen.kt:226`, Row label) | **same** |
| `"Add chapter"` (`WorkEditView.swift:448`, Row label) | — | **missing on Android** (only inside `WritingChaptersScreen.kt`) |
| `"Edit tags"` (`WorkEditView.swift:459`, Row label) | `"Edit tags"` (`WritingWorkFormScreen.kt:233`, Row label) | **same** |
| `"Work skin"` (`WorkEditView.swift:468`, Row label) | `"Work skin"` (`WritingWorkFormScreen.kt:237`, Row label) | **same** |
| `"Default"` (`WorkEditView.swift:470`, Work skin fallback title) | `"Default"` (`WritingWorkFormScreen.kt:238`) | **same** |
| `form.isDraft ? "When posted" : "Publication"` (`WorkEditView.swift:111`, Section header) | `if (form.isDraft) "When posted" else "Publication"` (`WritingWorkFormScreen.kt:241`, Section header) | **same** |
| `"Chapters posted"` (`WorkEditView.swift:647`, Row label) | `"Chapters posted"` (`WritingWorkFormScreen.kt:243`, Row label) | **same** |
| `"Total chapters"` (`WorkEditView.swift:655`, Row label) | `"Total chapters"` (`WritingWorkFormScreen.kt:248`, Row label) | **same** |
| `"AO3 marks a work in progress when its total chapters are higher than the number posted. Complete sets both numbers to the same value."` (`WorkEditView.swift:124`, Footnote) | `"AO3 marks a work in progress when its total chapters are higher than the number posted. Complete sets both numbers to the same value."` (`WritingWorkFormScreen.kt:252`, Footnote) | **same** |
| `"Reload chapter totals"` (`WorkEditView.swift:120`, Button) | `"Reload chapter totals"` (`WritingWorkFormScreen.kt:254`, Button) | **same** |
| `"Set a different publication date"` (`WorkEditView.swift:488`, Row & toggle label) | `"Set a different publication date"` (`WritingWorkFormScreen.kt:257`, Row label) | **same** |
| `"Publication date"` (`WorkEditView.swift:494`, Row label) | `"Publication date"` (`WritingWorkFormScreen.kt:260`, Row label) | **same** |
| — | Date picker sheet: `"Year"`, `"Month"`, `"Day"`, `"Done"` (`WritingWorkFormScreen.kt:333-356`) | **Android only** |
| `"Privacy and Visibility"` (`WorkEditView.swift:128`, Section header) | `"Privacy and Visibility"` (`WritingWorkFormScreen.kt:265`, Section header) | **same** |
| `"Only show to registered users"` (`WorkEditView.swift:506`, Row & toggle label) | `"Only show to registered users"` (`WritingWorkFormScreen.kt:267`, Row label) | **same** |
| `"Hides this work from guests and search engines."` (`WorkEditView.swift:131`, Footnote) | `"Hides this work from guests and search engines."` (`WritingWorkFormScreen.kt:269`, Footnote) | **same** |
| `"Enable comment moderation"` (`WorkEditView.swift:511`, Row & toggle label) | `"Enable comment moderation"` (`WritingWorkFormScreen.kt:272`, Row label) | **same** |
| `"You will review comments before they appear on the work."` (`WorkEditView.swift:134`, Footnote) | `"You will review comments before they appear on the work."` (`WritingWorkFormScreen.kt:274`, Footnote) | **same** |
| `"Who can comment"` (`WorkEditView.swift:517`, Row label) | `"Who can comment"` (`WritingWorkFormScreen.kt:277`, Row label) | **same** |
| `"Post"` (`WorkEditView.swift:133`, Section header) | — | **missing on Android** |
| `"Post work"` (`WorkEditView.swift:709`, Row action) | — | **missing on Android** |
| `"Preview on AO3"` (`WorkEditView.swift:713`, Row action) | — | **missing on Android** |
| `"Delete draft"` (`WorkEditView.swift:716`, Row action) | — | **missing on Android** |
| `"AO3 deletes an unposted draft 30 days after it is created."` (`WorkEditView.swift:137`, Footnote) | — | **missing on Android** |
| `"Delete"` (`WorkEditView.swift:142`, Section header) | — | **missing on Android** |
| `"Delete work on AO3"` (`WorkEditView.swift:526`, Row action) | — | **missing on Android** |
| `"Save"` (`WorkEditView.swift:199`, Toolbar button) | `"Save"` (`WritingWorkFormScreen.kt:94`, Toolbar button) | **same** |
| `"AO3 could not save the change"` (`WorkEditView.swift:205`, Alert title) | `"AO3 could not save the change"` (`WritingWorkFormScreen.kt:133`, Alert title) | **same** |
| `"OK"` (`WorkEditView.swift:208`, Alert button) | `"OK"` (`WritingWorkFormScreen.kt:137`, Alert button) | **same** |
| `"Post this work?"` (`WorkEditView.swift:213`, Post confirmation alert title) | — | **missing on Android** |
| `"Post work"` / `"Fill in what is missing"` (`WorkEditView.swift:215, 217`, Alert button) | — | **missing on Android** |
| `"Cancel"` (`WorkEditView.swift:219`, Post alert cancel button) | — | **missing on Android** |
| Post confirmation message (`WorkEditView.swift:221-222`) | — | **missing on Android** |
| `form.isDraft ? "Delete this draft?" : "Delete this work?"` (`WorkEditView.swift:224`, Delete dialog title) | — | **missing on Android** |
| `form.isDraft ? "Delete" : "Delete on AO3"` (`WorkEditView.swift:228`, Delete dialog button) | — | **missing on Android** |
| `"Cancel"` (`WorkEditView.swift:231`, Delete dialog cancel button) | — | **missing on Android** |
| `imp.cautionText` (`WorkEditView.swift:234`, Delete dialog message) | — | **missing on Android** |
| `"Reload chapter totals before saving this work. "` (`WorkEditView.swift:175`, Error message prefix) | `"Reload chapter totals before saving this work. "` (`WritingWorkFormState.kt:125`) | **same** |
| `"Reload tags before saving this work. "` (`WorkEditView.swift:194`, Error message prefix) | `"Reload tags before saving this work. "` (`WritingWorkFormState.kt:137`) | **same** |
| `"Your AO3 session changed. Reopen this form before saving."` (`WorkEditView.swift:587`, Error message) | `"Your AO3 session changed. Reopen this form before saving."` (`WritingWorkFormState.kt:149`) | **same** |
| — | Initial loading state: `"Loading work form…"` (`WritingWorkFormScreen.kt:114`) | **Android only** |
| — | Initial failure card: `failure`, `"Try Again"` (`WritingWorkFormScreen.kt:105, 108`) | **Android only** |
| — | Choice sheet titles: `"Rating"`, `"Who can comment"`, `"Work skin"` (`WritingWorkFormScreen.kt:319`) | **Android only** |
| — | Option selection semantics: `contentDescription = "Selected"` (`WritingWorkFormScreen.kt:377`) | **Android only** |

---

## Pair 2: Writing Edit Tags

- **Android**: `writing/WritingEditTagsScreen.kt`
- **iOS**: `Features/Writing/EditTagsView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Account"` (`EditTagsView.swift:39`, Header kicker) | `"AO3 Account"` (`WritingEditTagsScreen.kt:85`) | **same** |
| `"Edit tags"` (`EditTagsView.swift:40`, Header title) | `"Edit tags"` (`WritingEditTagsScreen.kt:85`) | **same** |
| `workTitle.isEmpty ? "changes here do not touch the text" : "\(workTitle) · changes here do not touch the text"` (`EditTagsView.swift:142-145`, Header subtitle) | `listOf(trimWritingTag(workTitle), "changes here do not touch the text").filter(String::isNotEmpty).joinToString(" · ")` (`WritingEditTagsScreen.kt:86-87`) | **same** |
| `"Rating"` (`EditTagsView.swift:54`, Section header) | `"Rating"` (`WritingEditTagsScreen.kt:108`) | **same** |
| Rating options: form.ratingOptions (`EditTagsView.swift:151`) | form.ratingOptions (`WritingEditTagsScreen.kt:109`) | **same** |
| `"Archive warnings"` (`EditTagsView.swift:63`, Section header) | `"Archive warnings"` (`WritingEditTagsScreen.kt:119`) | **same** |
| `"Choose at least one warning. Choose the first option if you don't want to name a specific warning."` (`EditTagsView.swift:73-74`, Footnote) | `"Choose at least one warning. Choose the first option if you don't want to name a specific warning."` (`WritingEditTagsScreen.kt:130`, Footnote) | **same** |
| Warning options: form.warningOptions (`EditTagsView.swift:163`) | form.warningOptions (`WritingEditTagsScreen.kt:120`) | **same** |
| `"Categories"` (`EditTagsView.swift:85`, Section header) | `"Categories"` (`WritingEditTagsScreen.kt:131`) | **same** |
| Category options: form.categoryOptions (`EditTagsView.swift:195`) | form.categoryOptions (`WritingEditTagsScreen.kt:132`) | **same** |
| `"Tags"` (`EditTagsView.swift:94`, Section header) | `"Tags"` (`WritingEditTagsScreen.kt:141`) | **same** |
| `"Fandoms"` (`EditTagsView.swift:218`, Row label) | `"Fandoms ∗"` (`WritingEditTagsScreen.kt:147`, Row label) | **differs** (iOS: `"Fandoms"`, Android: `"Fandoms ∗"`) |
| `"Relationships"` (`EditTagsView.swift:221`, Row label) | `"Relationships"` (`WritingEditTagsScreen.kt:147`, Row label) | **same** |
| `"Characters"` (`EditTagsView.swift:223`, Row label) | `"Characters"` (`WritingEditTagsScreen.kt:147`, Row label) | **same** |
| `"Additional tags"` (`EditTagsView.swift:225`, Row label) | `"Additional tags"` (`WritingEditTagsScreen.kt:147`, Row label) | **same** |
| Chip count: `"None"` or `"\(values.count)"` (`WritingFormFields.swift:71, 91`) | `workFormCount(values)`: `"None"` or `"${values.size}"` (`WritingEditTagsScreen.kt:148`) | **same** |
| `"Add"` (`WritingFormFields.swift:116`, Add chip label) | `"Add"` (`WritingEditTagsScreen.kt:161`, Add chip label) | **same** |
| `"Add \(title)"` (`WritingFormFields.swift:124`, Accessibility label) | `contentDescription = "Add ${tagKind.title}"` (`WritingEditTagsScreen.kt:163`) | **same** |
| `"Remove \(value)"` (`WritingFormFields.swift:110`, Accessibility label) | `contentDescription = "Remove ${chip.name}"` (`WritingEditTagsScreen.kt:173`) | **same** |
| `"As you type, AO3 suggests its canonical tags first. You can still post a tag that isn't canonical, and removing one here doesn't delete it from AO3."` (`EditTagsView.swift:100-101`, Footnote) | `"As you type, AO3 suggests its canonical tags first. You can still post a tag that isn't canonical, and removing one here doesn't delete it from AO3."` (`WritingEditTagsScreen.kt:180`, Footnote) | **same** |
| `"Save"` (`EditTagsView.swift:131`, Toolbar button) | `"Save"` (`WritingEditTagsScreen.kt:63`, Toolbar button) | **same** |
| `"AO3 could not save the change"` (`EditTagsView.swift:124`, Alert title) | `"AO3 could not save the change"` (`WritingEditTagsScreen.kt:71`, Alert title) | **same** |
| `"OK"` (`EditTagsView.swift:127`, Alert button) | `"OK"` (`WritingEditTagsScreen.kt:73`, Alert button) | **same** |
| — | Initial loading: `"Loading tags…"` (`WritingEditTagsScreen.kt:103`) | **Android only** |
| — | Initial failure: `failure`, `"Try Again"` (`WritingEditTagsScreen.kt:95, 98`) | **Android only** |
| — | Option check icon: `contentDescription = "Selected"` (`WritingEditTagsScreen.kt:113, 124`) | **Android only** (iOS uses `.isSelected` trait) |

---

## Pair 3: Writing Chapters List and Chapter Form

- **Android**: `writing/WritingChapterFormScreen.kt`, `WritingChaptersScreen.kt`, `WritingChapterFormState.kt`
- **iOS**: `Features/Writing/AddChapterView.swift`, `WritingChaptersView.swift`

### Chapters Screen (`WritingChaptersScreen.kt` vs `WritingChaptersView.swift`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Writing"` (`WritingChaptersView.swift:51`, Header kicker) | `"Writing"` (`WritingChaptersScreen.kt:47`) | **same** |
| `"Chapters"` (`WritingChaptersView.swift:52`, Header title) | `"Chapters"` (`WritingChaptersScreen.kt:48`) | **same** |
| `workTitle.isEmpty ? "All posted chapters" : "\(workTitle) · All posted chapters"` (`WritingChaptersView.swift:132-135`, Header subtitle) | `listOf(workTitle, "All posted chapters").filter(String::isNotEmpty).joinToString(" · ")` (`WritingChaptersScreen.kt:49`) | **same** |
| `"Loading chapters…"` (`WritingChaptersView.swift:65`, Loading state) | `"Loading chapters…"` (`WritingChaptersScreen.kt:58`) | **same** |
| `"Couldn't load from AO3"` (`WritingChaptersView.swift:70`, Error state) | `"Couldn't load from AO3"` (`WritingChaptersScreen.kt:54`) | **same** |
| `"Try Again"` (`WritingChaptersView.swift:70`, Retry button) | `"Try Again"` (`WritingChaptersScreen.kt:55`) | **same** |
| `"Add Chapter"` (`WritingChaptersView.swift:75`, Action button) | `"Add Chapter"` (`WritingChaptersScreen.kt:66`) | **same** |
| `"Chapters"` (`WritingChaptersView.swift:83`, Section header) | `"Chapters"` (`WritingChaptersScreen.kt:73`) | **same** |
| `"Chapter \(chapter.position)"` (`WritingChaptersView.swift:150`, Row kicker) | `"Chapter ${chapter.position}"` (`WritingChaptersScreen.kt:93`) | **same** |
| `chapter.title.isEmpty ? "Untitled" : chapter.title` (`WritingChaptersView.swift:155`, Row title) | `chapter.title.ifEmpty { "Untitled" }` (`WritingChaptersScreen.kt:96`) | **same** |
| `"posted \(chapter.postedDate)"` (`WritingChaptersView.swift:159`, Row date) | `"posted ${chapter.postedDate}"` (`WritingChaptersScreen.kt:98`) | **same** |

### Chapter Form (`WritingChapterFormScreen.kt` vs `AddChapterView.swift`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Writing"` (`AddChapterView.swift:49`, Header kicker) | `"Writing"` (`WritingChapterFormScreen.kt:101`) | **same** |
| `isEdit ? "Edit Chapter" : "Add Chapter"` (`AddChapterView.swift:50`, Header title) | `if (isEdit) "Edit Chapter" else "Add Chapter"` (`WritingChapterFormScreen.kt:102`) | **same** |
| Subtitle pattern: `"Chapter \(position)"` + title + workTitle (`AddChapterView.swift:139-145`) | Subtitle pattern (`WritingChapterFormScreen.kt:103`, `WritingChapterFormState.kt:65`) | **same** |
| `"Details"` (`AddChapterView.swift:60`, Section header) | `"Details"` (`WritingChapterFormScreen.kt:143`) | **same** |
| `"Chapter title"` (`AddChapterView.swift:150`, Row label & placeholder) | `"Chapter Title"` (`WritingChapterFormScreen.kt:144`, Row label & placeholder) | **differs** (iOS: `"Chapter title"`, Android: `"Chapter Title"`) |
| `"Chapter number"` (`AddChapterView.swift:155`, Row label & placeholder) | `"Chapter number"` (`WritingChapterFormScreen.kt:149`, Row label & placeholder) | **same** |
| `"Total chapters"` (`AddChapterView.swift:162`, Row label & placeholder) | `"Total chapters"` (`WritingChapterFormScreen.kt:153`, Row label & placeholder) | **same** |
| `"Set a different publication date"` (`AddChapterView.swift:171`, Row label) | `"Set a different publication date"` (`WritingChapterFormScreen.kt:183`, Row label) | **same** |
| `"Custom publication date"` (`AddChapterView.swift:172`, Toggle accessibility label) | `contentDescription = "Set a different publication date"` (`WritingChapterFormScreen.kt:183`, Toggle content description) | **differs** (iOS accessibility label: `"Custom publication date"`, Android TalkBack: `"Set a different publication date"`) |
| `"Publication date"` (`AddChapterView.swift:177`, Row label) | `"Publication date"` (`WritingChapterFormScreen.kt:186`, Row label) | **same** |
| — | Date picker sheet: `"Year"`, `"Month"`, `"Day"`, `"Done"` (`WritingChapterFormScreen.kt:338-356`) | **Android only** |
| `"Notes"` (`AddChapterView.swift:72`, Section header) | `"Notes"` (`WritingChapterFormScreen.kt:191`) | **same** |
| `"Beginning notes"` (`AddChapterView.swift:195`, Row label) | `"Beginning Notes"` (`WritingChapterFormScreen.kt:192`, Row label) | **differs** (iOS: `"Beginning notes"`, Android: `"Beginning Notes"`) |
| `"End notes"` (`AddChapterView.swift:198`, Row label) | `"End Notes"` (`WritingChapterFormScreen.kt:195`, Row label) | **differs** (iOS: `"End notes"`, Android: `"End Notes"`) |
| `"Chapter Text"` (`AddChapterView.swift:80`, Section header) | `"Chapter Text"` (`WritingChapterFormScreen.kt:199`) | **same** |
| `"Chapter text"` (`AddChapterView.swift:204`, Row label) | `"Chapter Text"` (`WritingChapterFormScreen.kt:200`, Row label) | **differs** (iOS: `"Chapter text"`, Android: `"Chapter Text"`) |
| `"Post"` (`AddChapterView.swift:88`, Section header) | `"Post"` (`WritingChapterFormScreen.kt:205`) | **same** |
| `"Post without preview"` (`AddChapterView.swift:214`, Row label) | `"Post without preview"` (`WritingChapterFormScreen.kt:207`, Row label) | **same** |
| `"Preview on AO3"` (`AddChapterView.swift:222`, Row label) | `"Preview on AO3"` (`WritingChapterFormScreen.kt:212`, Row label) | **same** |
| `"Delete chapter"` (`AddChapterView.swift:233`, Row label) | `"Delete chapter"` (`WritingChapterFormScreen.kt:218`, Row label) | **same** |
| `isEdit ? "Save" : "Save Draft"` (`AddChapterView.swift:115`, Toolbar button) | `if (isEdit) "Save" else "Save Draft"` (`WritingChapterFormScreen.kt:66`, Toolbar button) | **same** |
| `"AO3 could not save the change"` (`AddChapterView.swift:122`, Alert title) | `"AO3 could not save the change"` (`WritingChapterFormScreen.kt:90`, Alert title) | **same** |
| `"OK"` (`AddChapterView.swift:125`, Alert button) | `"OK"` (`WritingChapterFormScreen.kt:94`, Alert button) | **same** |
| `"Delete Chapter \(position)?"` (`AddChapterView.swift:130`, Confirmation dialog title) | `"Delete Chapter $position?"` (`WritingChapterFormScreen.kt:111`, Confirmation dialog title) | **same** |
| `"Delete Chapter"` (`AddChapterView.swift:132`, Dialog destructive button) | `"Delete Chapter"` (`WritingChapterFormScreen.kt:118`, Dialog destructive button) | **same** |
| `"Cancel"` (`AddChapterView.swift:133`, Dialog cancel button) | `"Cancel"` (`WritingChapterFormScreen.kt:123`, Dialog cancel button) | **same** |
| `"Deleting this chapter cannot be undone."` (`AddChapterView.swift:135`, Dialog message) | `"Deleting this chapter cannot be undone."` (`WritingChapterFormScreen.kt:113`, Dialog message) | **same** |
| — | Initial failure card: `"Couldn't load from AO3"`, `"Try Again"` (`WritingChapterFormScreen.kt:78, 80`) | **Android only** |

---

## Pair 4: Writing Series

- **Android**: `writing/WritingSeriesScreen.kt`, `WritingSeriesState.kt`
- **iOS**: `Features/Writing/SeriesEditView.swift`, `SeriesReorderDestination.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Writing"` (`SeriesEditView.swift:42`, Header kicker) | `"Writing"` (`WritingSeriesScreen.kt:65`) | **same** |
| `"Edit Series"` (`SeriesEditView.swift:43`, Header title) | `"Edit Series"` (`WritingSeriesScreen.kt:66`) | **same** |
| `seriesTitle.isEmpty ? "All works in this series" : "\(seriesTitle) · All works in this series"` (`SeriesEditView.swift:125-128`, Header subtitle) | `listOf(seriesTitle, "All works in this series").filter(String::isNotEmpty).joinToString(" · ")` (`WritingSeriesScreen.kt:67`) | **same** |
| `"Series Details"` (`SeriesEditView.swift:51`, Section header) | `"Series Details"` (`WritingSeriesScreen.kt:126`) | **same** |
| `"Title"` (`SeriesEditView.swift:135`, Row label) | `"Title ∗"` (`WritingSeriesScreen.kt:127`, Row label) | **differs** (iOS: `"Title"`, Android: `"Title ∗"`) |
| `"Title, required"` (`SeriesEditView.swift:135`, Accessibility label) | `contentDescription = "Title ∗"` (inherits row text, `WritingSeriesScreen.kt:127`) | **differs** (iOS accessibility label: `"Title, required"`, Android TalkBack: `"Title ∗"`) |
| `"Creators"` (`SeriesEditView.swift:139`, Row label) | `"Creators"` (`WritingSeriesScreen.kt:131`, Row label) | **same** |
| `"None"` (`SeriesEditView.swift:140`, Value fallback) | `"None"` (`WritingSeriesScreen.kt:132`, Value fallback) | **same** |
| `"Description"` (`SeriesEditView.swift:144`, Row label) | `"Description"` (`WritingSeriesScreen.kt:135`, Row label) | **same** |
| `"Notes"` (`SeriesEditView.swift:148`, Row label) | `"Notes"` (`WritingSeriesScreen.kt:138`, Row label) | **same** |
| `"This series is complete"` (`SeriesEditView.swift:152`, Toggle label) | `"This series is complete"` (`WritingSeriesScreen.kt:142`, Toggle label) | **same** |
| `"Works in Series"` (`SeriesEditView.swift:60`, Section header) | `"Works in Series"` (`WritingSeriesScreen.kt:145`, Section header) | **same** |
| `"\(index + 1). "` (`SeriesEditView.swift:171`, Position prefix) | `"${index + 1}. "` (`WritingSeriesScreen.kt:151`, Position prefix) | **same** |
| `row.title.isEmpty ? "Untitled" : row.title` (`SeriesEditView.swift:172`, Work title) | `row.title.ifEmpty { "Untitled" }` (`WritingSeriesScreen.kt:151`, Work title) | **same** |
| Icon button (`minus.circle.fill`, `SeriesEditView.swift:164`) | `"Remove"` (`WritingSeriesScreen.kt:153`, Visible text button) | **differs** (iOS has no visible text; Android shows visible `"Remove"`) |
| `"Remove \(Self.title(row)) from the series"` (`SeriesEditView.swift:168`, Accessibility label) | `contentDescription = "Remove ${row.title.ifEmpty { "Untitled" }} from the series"` (`WritingSeriesScreen.kt:154`, Accessibility label) | **same** |
| `"Remove from series?"` (`SeriesEditView.swift:115`, Confirmation dialog title) | `"Remove from series?"` (`WritingSeriesScreen.kt:82`, Confirmation dialog title) | **same** |
| `"Remove"` (`SeriesEditView.swift:117`, Dialog destructive button) | `"Remove"` (`WritingSeriesScreen.kt:89`, Dialog destructive button) | **same** |
| `"Cancel"` (`SeriesEditView.swift:118`, Dialog cancel button) | `"Cancel"` (`WritingSeriesScreen.kt:94`, Dialog cancel button) | **same** |
| `"Removing \(title) will not delete the work from AO3. It will only remove it from this series."` (`SeriesEditView.swift:120`, Dialog message) | `"Removing $title will not delete the work from AO3. It will only remove it from this series."` (`WritingSeriesScreen.kt:84`, Dialog message) | **same** |
| `"Reorder Works"` (`SeriesEditView.swift:69`, Section header) | `"Reorder Works"` (`WritingSeriesScreen.kt:158`, Section header) | **same** |
| `"Reorder Works"` (`SeriesReorderDestination.swift:51`, Navigation title) | `"Reorder Works"` (`WritingSeriesScreen.kt:207`, Header title) | **same** |
| `"Writing"` (`SeriesEditView.swift:42`, Context) | `"Writing"` (`WritingSeriesScreen.kt:207`, Reorder header kicker) | **same** |
| `"Save Order"` (`SeriesReorderDestination.swift:56`, Toolbar button) | `"Save Order"` (`WritingSeriesScreen.kt:195`, Toolbar button) | **same** |
| `"Cancel"` (`SeriesReorderDestination.swift:54`, Toolbar button) | `"Cancel"` (`WritingSeriesScreen.kt:191`, Toolbar button) | **same** |
| — | Reorder item semantics: `stateDescription = "Drag to reorder."`, custom actions: `"Move Earlier"`, `"Move Later"` (`WritingSeriesScreen.kt:226-228`) | **Android only** |
| `"Save"` (`SeriesEditView.swift:99`, Toolbar button) | `"Save"` (`WritingSeriesScreen.kt:47`, Toolbar button) | **same** |
| `"AO3 could not save the change"` (`SeriesEditView.swift:105`, Alert title) | `"AO3 could not save the change"` (`WritingSeriesScreen.kt:73`, Alert title) | **same** |
| `"OK"` (`SeriesEditView.swift:108`, Alert button) | `"OK"` (`WritingSeriesScreen.kt:77`, Alert button) | **same** |
| — | Loading/saving states: `"Loading…"`, `"Saving…"`, failure card: `"Couldn't load from AO3"`, `"Try Again"` (`WritingSeriesScreen.kt:53, 56, 110, 113`) | **Android only** |

---

## Pair 5: AO3 Challenge Sign-Up

- **Android**: `account/AO3ChallengeSignUpScreen.kt`, `AO3ChallengeSignUpState.kt`
- **iOS**: `Features/Challenges/ChallengeSignUpView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `effectiveTitle` (`ChallengeSignUpView.swift:166`, Header kicker) | `effectiveTitle` (`AO3ChallengeSignUpScreen.kt:145`, Header kicker) | **same** |
| `"Your sign-up"` (`ChallengeSignUpView.swift:167`, Header title) | `"Your sign-up"` (`AO3ChallengeSignUpScreen.kt:145`, Header title) | **same** |
| Subtitle pattern: `"Request \(live) of \(allowed)"` / `"\(live) requests"` + `" · Offer \(live) of \(allowed)"` (`ChallengeSignUpView.swift:175-181`) | Subtitle pattern (`AO3ChallengeSignUpScreen.kt:146-149`) | **same** |
| `"Request \(index + 1)"` (`ChallengeSignUpView.swift:195`, Section header) | `"Request ${index + 1}"` (`AO3ChallengeSignUpScreen.kt:156`, Section header) | **same** |
| `"Fandoms"` (`ChallengeSignUpView.swift:245`, Row label) | `"Fandoms"` (`AO3ChallengeSignUpScreen.kt:185`, Row label) | **same** |
| `"None chosen"` (`ChallengeSignUpView.swift:246`, Value fallback) | `"None chosen"` (`AO3ChallengeSignUpScreen.kt:186`, Value fallback) | **same** |
| `"Relationships"` (`ChallengeSignUpView.swift:254`, Row label) | `"Relationships"` (`AO3ChallengeSignUpScreen.kt:190`, Row label) | **same** |
| `"Optional"` / `"\(count) chosen"` (`ChallengeSignUpView.swift:256-257`, Value) | `"Optional"` / `"${prompt.relationships.size} chosen"` (`AO3ChallengeSignUpScreen.kt:191`, Value) | **same** |
| `"Characters"` (`ChallengeSignUpView.swift:265`, Row label) | `"Characters"` (`AO3ChallengeSignUpScreen.kt:195`, Row label) | **same** |
| `"Optional"` / `"\(count) chosen"` (`ChallengeSignUpView.swift:267-268`, Value) | `"Optional"` / `"${prompt.characters.size} chosen"` (`AO3ChallengeSignUpScreen.kt:196`, Value) | **same** |
| `"Additional tags"` (`ChallengeSignUpView.swift:276`, Row label) | `"Additional tags"` (`AO3ChallengeSignUpScreen.kt:200`, Row label) | **same** |
| `"Optional"` / `"\(count) chosen"` (`ChallengeSignUpView.swift:278-279`, Value) | `"Optional"` / `"${prompt.freeforms.size} chosen"` (`AO3ChallengeSignUpScreen.kt:201`, Value) | **same** |
| `"Any of these is fine"` (`ChallengeSignUpView.swift:291`, Toggle title) | `"Any of these is fine"` (`AO3ChallengeSignUpScreen.kt:206`, Toggle title) | **same** |
| `"Any relationship matches, not only the ones chosen"` (`ChallengeSignUpView.swift:295`, Toggle subtitle) | `"Any relationship matches, not only the ones chosen"` (`AO3ChallengeSignUpScreen.kt:207`, Toggle subtitle) | **same** |
| `"Title"` (`ChallengeSignUpView.swift:346`, Text placeholder) | `"Title"` (`AO3ChallengeSignUpScreen.kt:216`, Text placeholder) | **same** |
| `"Prompt details and description"` (`ChallengeSignUpView.swift:361`, Text placeholder) | `"Prompt details and description"` (`AO3ChallengeSignUpScreen.kt:222`, Text placeholder) | **same** |
| `"Optional tags, comma-separated"` (`ChallengeSignUpView.swift:383`, Text placeholder) | `"Optional tags, comma-separated"` (`AO3ChallengeSignUpScreen.kt:228`, Text placeholder) | **same** |
| `"Tags you'd like to see, separated by commas."` (`ChallengeSignUpView.swift:387`, Footnote) | `"Tags you'd like to see, separated by commas."` (`AO3ChallengeSignUpScreen.kt:230`, Footnote) | **same** |
| `"You can add more requests or delete optional ones before the challenge closes."` (`ChallengeSignUpView.swift:437`, Footnote) | `"You can add more requests or delete optional ones before the challenge closes."` (`AO3ChallengeSignUpScreen.kt:164`, Footnote) | **same** |
| `"Offers"` (`ChallengeSignUpView.swift:213`, Section header) | `"Offers"` (`AO3ChallengeSignUpScreen.kt:168`, Section header) | **same** |
| `"Offer \(index + 1)"` (`ChallengeSignUpView.swift:222`, Section header) | `"Offer ${index + 1}"` (`AO3ChallengeSignUpScreen.kt:170`, Section header) | **same** |
| `"Offers are the fandoms and tags you are willing to write or create for."` (`ChallengeSignUpView.swift:431`, Footnote) | `"Offers are the fandoms and tags you are willing to write or create for."` (`AO3ChallengeSignUpScreen.kt:177`, Footnote) | **same** |
| `"Withdraw"` (`ChallengeSignUpView.swift:229`, Section header) | — | **missing on Android** |
| `"Withdraw sign-up"` (`ChallengeSignUpView.swift:453`, Action button) | — | **missing on Android** |
| `"Withdraw this sign-up?"` (`ChallengeSignUpView.swift:134`, Dialog title) | — | **missing on Android** |
| `"Withdraw Sign-up"` (`ChallengeSignUpView.swift:138`, Dialog destructive button) | — | **missing on Android** |
| `"Cancel"` (`ChallengeSignUpView.swift:141`, Dialog cancel button) | — | **missing on Android** |
| `"Withdrawing removes your requests and offers from \(effectiveTitle)."` (`ChallengeSignUpView.swift:145`, Dialog message) | — | **missing on Android** |
| `"Add request"` (`ChallengeSignUpView.swift:478`, Button) | `"Add request"` (`AO3ChallengeSignUpScreen.kt:70`, Button) | **same** |
| `"Submit Sign-up"` (`ChallengeSignUpView.swift:502`, Button) | `"Submit sign-up"` (`AO3ChallengeSignUpScreen.kt:75`, Button) | **differs** (iOS: `"Submit Sign-up"`, Android: `"Submit sign-up"`) |
| `"Loading sign-up…"` (`ChallengeSignUpView.swift:40`, Loading text) | `"Loading sign-up…"` (`AO3ChallengeSignUpScreen.kt:100`, Loading text) | **same** |
| `"Couldn't load sign-up"` (`ChallengeSignUpView.swift:47`, Error text) | `"Couldn't load sign-up"` (`AO3ChallengeSignUpScreen.kt:107`, Error text) | **same** |
| `"Try Again"` (`ChallengeSignUpView.swift:49`, Retry button) | `"Try Again"` (`AO3ChallengeSignUpScreen.kt:111`, Retry button) | **same** |

---

## Pair 6: Account Shortcuts

- **Android**: `account/AccountShortcuts.kt`, `account/AccountShortcutsEditor.kt`
- **iOS**: `Features/Account/AccountShortcuts.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Shortcuts"` (`AccountShortcuts.swift:152`, Navigation title) | `"Shortcuts"` (`AccountShortcutsEditor.kt:50`, Header title; kicker `"AO3 Account"`) | **same** |
| `"On the grid"` (`AccountShortcuts.swift:127`, Section header) | `"On the grid"` (`AccountShortcutsEditor.kt:52`, Section header) | **same** |
| `"If you choose none, the grid is hidden. You can still find every destination in the sections below."` (`AccountShortcuts.swift:130-131`, Footnote) | `"If you choose none, the grid is hidden. You can still find every destination in the sections below."` (`AccountShortcutsEditor.kt:82`, Footnote) | **same** |
| `"Not on the grid"` (`AccountShortcuts.swift:136`, Section header) | `"Not on the grid"` (`AccountShortcutsEditor.kt:86`, Section header) | **same** |
| `"Reset to Default"` (`AccountShortcuts.swift:144`, Button) | `"Reset to Default"` (`AccountShortcutsEditor.kt:102`, Button) | **same** |
| `"Done"` (`AccountShortcuts.swift:160`, Confirmation button) | `"Done"` (`AccountShortcutsEditor.kt:45`, Confirmation icon button) | **same** |
| `"Remove \(shortcut.title)"` / `"Add \(shortcut.title)"` (`AccountShortcuts.swift:185`, Accessibility label) | `contentDescription = "${if (chosen) "Remove" else "Add"} ${shortcut.title}"` (`AccountShortcutsEditor.kt:115`) | **same** |
| Shortcut: `"Dashboard"` (`AccountShortcuts.swift:27`) | `"Dashboard"` (`AccountShortcuts.kt:10`) | **same** |
| Shortcut: `"Marked for Later"` (`AccountShortcuts.swift:28`) | `"Marked for Later"` (`AccountShortcuts.kt:11`) | **same** |
| Shortcut: `"Bookmarks"` (`AccountShortcuts.swift:29`) | `"Bookmarks"` (`AccountShortcuts.kt:12`) | **same** |
| Shortcut: `"Collections"` (`AccountShortcuts.swift:30`) | `"Collections"` (`AccountShortcuts.kt:13`) | **same** |
| Shortcut: `"Subscriptions"` (`AccountShortcuts.swift:31`) | `"Subscriptions"` (`AccountShortcuts.kt:14`) | **same** |
| Shortcut: `"Works"` (`AccountShortcuts.swift:32`) | `"Works"` (`AccountShortcuts.kt:15`) | **same** |
| Shortcut: `"Series"` (`AccountShortcuts.swift:33`) | — | **missing on Android** (`AccountShortcuts.kt:7`: "My series is not implemented yet.") |
| Shortcut: `"Drafts"` (`AccountShortcuts.swift:34`) | `"Drafts"` (`AccountShortcuts.kt:16`) | **same** |
| Shortcut: `"History"` (`AccountShortcuts.swift:35`) | `"History"` (`AccountShortcuts.kt:17`) | **same** |
| Shortcut: `"Inbox"` (`AccountShortcuts.swift:36`) | `"Inbox"` (`AccountShortcuts.kt:18`) | **same** |
| Shortcut: `"Preferences"` (`AccountShortcuts.swift:37`) | `"Preferences"` (`AccountShortcuts.kt:19`) | **same** |
| Shortcut: `"More on AO3"` (`AccountShortcuts.swift:38`) | `"More on AO3"` (`AccountShortcuts.kt:20`) | **same** |
| — | Reorder buttons: `contentDescription = "Move ${shortcut.title} up"`, `contentDescription = "Move ${shortcut.title} down"` (`AccountShortcutsEditor.kt:64, 68`) | **Android only** |

---

## Pair 7: Author Works Sort Fields

- **Android**: `author/AuthorWorksSortFields.kt`, `author/AuthorProfileScreen.kt`
- **iOS**: `Features/Search/AO3FilterPanel.swift` (the works sort), `Models/AO3WorksSort.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Sort by"` (`AO3FilterPanel.swift:641`, Row label) | `"Sort by"` (`AuthorWorksSortFields.kt:42, 44`, Row label) | **same** |
| `"\(sortPresentation.draft.column.title), \(AO3WorksSort.fieldsHint)"` (`AO3FilterPanel.swift:653`, Accessibility value) | `contentDescription = "Sort by, ${draft.column.label}, 9 fields"` (`AuthorWorksSortFields.kt:40`, Content description) | **same** (equivalent compound TalkBack description) |
| `"9 fields"` (`AO3WorksSort.swift:151`, Caption) | `"9 fields"` (`AuthorWorksSortFields.kt:42, 48`, Caption) | **same** |
| Column options: `"Creator"`, `"Title"`, `"Date Posted"`, `"Date Updated"`, `"Word Count"`, `"Hits"`, `"Kudos"`, `"Comments"`, `"Bookmarks"` (`AO3WorksSort.swift:26-34`) | Column options: `"Creator"`, `"Title"`, `"Date Posted"`, `"Date Updated"`, `"Word Count"`, `"Hits"`, `"Kudos"`, `"Comments"`, `"Bookmarks"` (`AO3AuthorModels.kt:90-98`) | **same** |
| `"Direction"` (`AO3FilterPanel.swift:655`, Picker / segment label) | `"Direction"` (`AuthorWorksSortFields.kt:64, 72`, Row label & control content description) | **same** |
| Direction options: `"Ascending"`, `"Descending"` (`AO3WorksSort.swift:57-58`) | Direction options: `"Ascending"`, `"Descending"` (`AO3AuthorModels.kt:109-110`) | **same** |
| `"Completion"` (`AO3FilterPanel.swift:665`, Section header) | `"Completion"` (`AuthorWorksSortFields.kt:75`, Section header) | **same** |
| `"AO3 applies this choice to all matching works, not only the page you can see."` (`AO3FilterPanel.swift:667`, Footnote) | `"AO3 applies this choice to all matching works, not only the page you can see."` (`AuthorWorksSortFields.kt:19, 75`, Footnote) | **same** |
| Completion options: `"Any"`, `"Complete"`, `"In progress"` (`AO3WorksSort.swift:79-81`) | Completion options: `"Any"`, `"Complete"`, `"In progress"` (`AO3AuthorModels.kt:114-116`) | **same** |
| `"Sort and filter"` (`AO3FilterPanel.swift:138`, Sheet title) | `"Sort and filter"` (`SearchFilterSheet.kt:110`, Sheet title) | **same** |
| `"Sort and filter"` (`AuthorProfileView.swift:816`, Toolbar button accessibility label) | `accessibilityName = "Sort and filter"` (`AuthorProfileScreen.kt:212`, Toolbar button) | **same** |
| `"Apply"` (`AO3FilterPanel.swift:228`, Sheet confirm button) | `"Apply"` (`SearchFilterSheet.kt:124`, Sheet confirm button) | **same** |
| `"Reset filters"` (`AO3FilterPanel.swift:192`, Sheet reset button accessibility label) | `"Reset filters"` (`SearchFilterSheet.kt:106`, Sheet reset button accessibility label) | **same** |

---

## Pair 8: Library History Grouping

- **Android**: `library/LibraryHistoryGrouping.kt`, `library/LibraryScreen.kt`
- **iOS**: `Features/Library/LibraryHistoryGrouping.swift`, `LibrarySectionListView.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Time"` (`LibraryHistoryGrouping.swift:22`, Scope title) | `"Time"` (`LibraryHistoryGrouping.kt:22`, Scope title) | **same** |
| `"State"` (`LibraryHistoryGrouping.swift:23`, Scope title) | `"State"` (`LibraryHistoryGrouping.kt:23`, Scope title) | **same** |
| `"Fandom"` (`LibraryHistoryGrouping.swift:24`, Scope title) | `"Fandom"` (`LibraryHistoryGrouping.kt:24`, Scope title) | **same** |
| `"Flat"` (`LibraryHistoryGrouping.swift:25`, Scope title) | `"Flat"` (`LibraryHistoryGrouping.kt:25`, Scope title) | **same** |
| Time kicker: `"Today"` (`LibraryHistoryGrouping.swift:168`) | `"Today"` (`LibraryHistoryGrouping.kt:34`) | **same** |
| Time kicker: `"Yesterday"` (`LibraryHistoryGrouping.swift:169`) | `"Yesterday"` (`LibraryHistoryGrouping.kt:35`) | **same** |
| Time kicker: `"This week"` (`LibraryHistoryGrouping.swift:170`) | `"This week"` (`LibraryHistoryGrouping.kt:36`) | **same** |
| Time kicker: `"This month"` (`LibraryHistoryGrouping.swift:171`) | `"This month"` (`LibraryHistoryGrouping.kt:37`) | **same** |
| Time kicker: `"Earlier"` (`LibraryHistoryGrouping.swift:172`) | `"Earlier"` (`LibraryHistoryGrouping.kt:38`) | **same** |
| Time kicker: `"Never opened"` (`LibraryHistoryGrouping.swift:173`) | `"Never opened"` (`LibraryHistoryGrouping.kt:39`) | **same** |
| State kicker: `"In progress"` (`LibraryHistoryGrouping.swift:114`) | `"In progress"` (`LibraryHistoryGrouping.kt:72`) | **same** |
| State kicker: `"Abandoned"` (`LibraryHistoryGrouping.swift:115`) | `"Abandoned"` (`LibraryHistoryGrouping.kt:73`) | **same** |
| State kicker: `"Read, not finished"` (`LibraryHistoryGrouping.swift:79`) | `"Read, not finished"` (`LibraryHistoryGrouping.kt:74`) | **same** |
| State kicker: `"Finished"` (`LibraryHistoryGrouping.swift:79`) | `"Finished"` (`LibraryHistoryGrouping.kt:75`) | **same** |
| State kicker: `"Not started"` (`LibraryHistoryGrouping.swift:79`) | `"Not started"` (`LibraryHistoryGrouping.kt:76`) | **same** |
| Flat kicker: `"All"` (`LibraryHistoryGrouping.swift:57`) | `"All"` (`LibraryHistoryGrouping.kt:77`) | **same** |
| Fandom fallback kicker: `"No fandom"` (`LibraryHistoryGrouping.swift:100`) | `"No fandom"` (`LibraryHistoryGrouping.kt:78`) | **same** |
| Base count pattern: `workCount == 1 ? "1 work" : "\(workCount) works"` (`LibraryHistoryGrouping.swift:124`) | `"$workCount ${if (workCount == 1) "work" else "works"}"` (`LibraryHistoryGrouping.kt:142`) | **same** |
| Time/Flat tally pattern: `\(works) · most recently read first` (`LibraryHistoryGrouping.swift:127`) | `"$works · most recently read first"` (`LibraryHistoryGrouping.kt:144`) | **same** |
| Fandom tally pattern: `\(works)` (`LibraryHistoryGrouping.swift:129`) | `works` (`LibraryHistoryGrouping.kt:145`) | **same** |
| State tally pattern: `\(works)` + (`" · \(inProgress) in progress"` if inProgress > 0) + (`" · \(abandoned) abandoned"` if abandoned > 0) (`LibraryHistoryGrouping.swift:131-136`) | State tally pattern (`LibraryHistoryGrouping.kt:146-154`) | **same** |
| `"Move back to In progress"` (`ReadingHistoryFactsStrip.swift:16`, Button) | `"Move back to In progress"` (`LibraryScreen.kt:1555`, Button) | **same** |
| — | Segmented control: `contentDescription = "History grouping"` (`LibraryScreen.kt:1578`) | **Android only** |

---

## Pair 9: Favorite Affinity Row and Reading Affinities

- **Android**: `library/FavoriteAffinityRow.kt`, `library/ReadingAffinities.kt`
- **iOS**: `Features/Library/FavoriteAffinityRow.swift`, `ReadingAffinities.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| Works read count pattern: `row.worksRead == 1 ? "1 work read" : "\(row.worksRead) works read"` (`FavoriteAffinityRow.swift:282`) | `"${row.worksRead} work${if (row.worksRead == 1) "" else "s"} read"` (`FavoriteAffinityRow.kt:62`) | **same** |
| Tags log suffix pattern: `row.worksRead == 1 ? " carries this tag" : " carry this tag"` (`FavoriteAffinityRow.swift:284`) | `if (row.worksRead == 1) " carries this tag" else " carry this tag"` (`FavoriteAffinityRow.kt:63`) | **same** |
| Fandom favorited count: `"\(row.favorited) favorited"` (`FavoriteAffinityRow.swift:288`) | `"${row.favorited} favorited"` (`FavoriteAffinityRow.kt:65`) | **same** |
| Duration pattern: `ReadingInsights.durationLabel(row.totalSeconds)` (`FavoriteAffinityRow.swift:291`) | `ReadingInsights.durationLabel(row.totalSeconds)` (`FavoriteAffinityRow.kt:66`) | **same** |
| Last read date pattern: `"last read \(date)"` (`FavoriteAffinityRow.swift:294`) | `"last read ${formattedDate}"` (`FavoriteAffinityRow.kt:67`) | **same** |
| Downloaded extra pattern: `"\(row.downloadedInLibrary) downloaded"` (`FavoriteAffinityRow.swift:321`) | `"${row.downloadedInLibrary} downloaded"` (`FavoriteAffinityRow.kt:72`) | **same** |
| Saved for Later extra pattern: `"\(row.savedForLater) in Saved for Later"` (`FavoriteAffinityRow.swift:322`) | `"${row.savedForLater} in Saved for Later"` (`FavoriteAffinityRow.kt:73`) | **same** |
| Unread label pattern: `row.unreadInLibrary == 1 ? "1 unread work" : "\(row.unreadInLibrary) unread works"` (`FavoriteAffinityRow.swift:314`) | `"${row.unreadInLibrary} unread work${if (row.unreadInLibrary == 1) "" else "s"}"` (`FavoriteAffinityRow.kt:77`) | **same** |
| Zero unread label: `"No unread works"` (`FavoriteAffinityRow.swift:162`) | `"No unread works"` (`FavoriteAffinityRow.kt:78`) | **same** |
| Zero unread library line: `"No unread works in your library"` (`FavoriteAffinityRow.swift:312`) | `"No unread works in your library"` (`FavoriteAffinityRow.kt:81`) | **same** |
| `"Shows these works in your Library"` (`FavoriteAffinityRow.swift:67`, Accessibility hint) | `onClickLabel = "Shows these works in your Library"` (`FavoriteAffinityRow.kt:106`) | **same** |
| `"Open author page"` (`FavoriteAffinityRow.swift:95, 147`, Accessibility action & label) | `customActions = listOf(CustomAccessibilityAction("Open author page") ...)` (`FavoriteAffinityRow.kt:109`), `IconButton(..., "Open author page")` (`FavoriteAffinityRow.kt:132`) | **same** |
| `"IN YOUR LIBRARY"` (`FavoriteAffinityRow.swift:156`, Tags block label uppercase) | `"IN YOUR LIBRARY"` (`FavoriteAffinityRow.kt:138`, Tags block label) | **same** |
| `"Everything tagged this way has been opened"` (`FavoriteAffinityRow.swift:178`, Tags block fallback) | `"Everything tagged this way has been opened"` (`FavoriteAffinityRow.kt:142`, Tags block fallback) | **same** |
| `"Newest work"` (`FavoriteAffinityRow.swift:188`, Authors newest work label) | — | **missing on Android** |
| `"UNREAD"` (`FavoriteAffinityRow.swift:205`, Authors newest work unread badge) | — | **missing on Android** |
| `"Open \(work.title)"` (`FavoriteAffinityRow.swift:223`, Authors newest work link accessibility label) | — | **missing on Android** |
| Newest work metadata: `"updated \(work.dateUpdated)"`, `"\(words) words"` (`FavoriteAffinityRow.swift:242, 245`) | — | **missing on Android** |
| Combined accessibility string: `text = "\(row.name). \(logLine)." + (newestWork or libraryText)` (`FavoriteAffinityRow.swift:251-259`) | `contentDescription = "${row.name}. $log. $library"` (`FavoriteAffinityRow.kt:108`) | **differs** (iOS includes Newest work details when present) |
| Empty card: `"Nothing read yet"` (`FavoriteAffinityRow.swift:360`) | `"Nothing read yet"` (`FavoriteAffinityRow.kt:229`) | **same** |
| Empty card detail: `"These \(noun) come from works you have read and are ranked by your reading. You don't need to favorite them first."` (`FavoriteAffinityRow.swift:372-373`) | `"These ${scope.title.lowercase()} come from works you have read and are ranked by your reading. You don't need to favorite them first."` (`FavoriteAffinityRow.kt:232`) | **same** |
| Empty card unread title: `"No unread works"` (`FavoriteAffinityRow.swift:360`) | `"No unread works"` (`FavoriteAffinityRow.kt:229`) | **same** |
| Empty card unread detail: `"Every work in your library under these tags has been opened. Tap All to see them again."` (`FavoriteAffinityRow.swift:366`) | `"Every work in your library under these tags has been opened. Tap All to see them again."` (`FavoriteAffinityRow.kt:231`) | **same** |
| Empty card author filter title: `"No new work"` (`FavoriteAffinityRow.swift:360`) | — | **missing on Android** |
| Empty card author filter detail: `"None of these \(noun) has posted something you have not already read. Tap All to see them again."` (`FavoriteAffinityRow.swift:368-370`) | — | **missing on Android** |
| Scopes: `"Works"`, `"Authors"`, `"Fandoms"`, `"Tags"` (`LibrarySectionListView.swift:52`, `FavoriteScope.allCases`) | Scopes: `"Works"`, `"Authors"`, `"Fandoms"`, `"Tags"` (`FavoriteScope.kt:12`) | **same** |
| Orders: `"Recent"`, `"Most read"`, `"Most time"` (`ReadingAffinities.swift:64-66`) | Orders: `"Recent"`, `"Most read"`, `"Most time"` (`ReadingAffinities.kt:49`) | **same** |
| Tags rail: `"All"`, `"Unread works"` (`LibrarySectionListView.swift:449`) | Tags rail: `"All"`, `"Unread works"` (`FavoriteAffinityRow.kt:162`) | **same** |
| — | Segmented control semantics: `contentDescription = "Favorites scope"`, `contentDescription = "Favorites order"` (`FavoriteAffinityRow.kt:155, 157`) | **Android only** |

---

## Pair 10: Account More on AO3

- **Android**: `account/AccountMoreOnAO3Screen.kt`
- **iOS**: `Features/Account/AccountMoreOnAO3View.swift`

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"AO3 Account"` (`AccountMoreOnAO3View.swift:82`, Header kicker) | `"AO3 Account"` (`AccountMoreOnAO3Screen.kt:58`) | **same** |
| `"More on AO3"` (`AccountMoreOnAO3View.swift:83`, Header title) | `"More on AO3"` (`AccountMoreOnAO3Screen.kt:59`) | **same** |
| `"Opens on AO3 in Browse"` (`AccountMoreOnAO3View.swift:84`, Header subtitle) | `"Opens on AO3 in Browse"` (`AccountMoreOnAO3Screen.kt:60`) | **same** |
| `"Post and manage"` (`AccountMoreOnAO3View.swift:97`, Section header) | `"Post and manage"` (`AccountMoreOnAO3Screen.kt:126`) | **same** |
| `"Post new work"` (`AccountMoreOnAO3View.swift:149`, Row label) | `"Post new work"` (`AccountMoreOnAO3Screen.kt:128`, Row label) | **same** |
| `"Import work"` (`AccountMoreOnAO3View.swift:156`, Row label) | `"Import work"` (`AccountMoreOnAO3Screen.kt:129`, Row label) | **same** |
| `"Edit works in bulk"` (`AccountMoreOnAO3View.swift:163`, Row label) | `"Edit works in bulk"` (`AccountMoreOnAO3Screen.kt:130`, Row label) | **same** |
| `"Manage collection items"` (`AccountMoreOnAO3View.swift:170`, Row label) | `"Manage collection items"` (`AccountMoreOnAO3Screen.kt:131`, Row label) | **same** |
| `"Related works"` (`AccountMoreOnAO3View.swift:177`, Row label) | `"Related works"` (`AccountMoreOnAO3Screen.kt:132`, Row label) | **same** |
| `"Drafts"` (`AccountMoreOnAO3View.swift:184`, Row label) | `"Drafts"` (`AccountMoreOnAO3Screen.kt:133`, Row label) | **same** |
| `"These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox in the Reading, Writing and Activity sections of Account."` (`AccountMoreOnAO3View.swift:250-253`, Footnote) | `"These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox in the Reading, Writing and Activity sections of Account."` (`AccountMoreOnAO3Screen.kt:135-136`, Footnote) | **same** |
| `"Challenges"` (`AccountMoreOnAO3View.swift:104`, Section header) | `"Challenges"` (`AccountMoreOnAO3Screen.kt:139`) | **same** |
| `"Sign-ups"` (`AccountMoreOnAO3View.swift:259`, Row label) | `"Sign-ups"` (`AccountMoreOnAO3Screen.kt:141`, Row label) | **same** |
| `"Assignments"` (`AccountMoreOnAO3View.swift:266`, Row label) | `"Assignments"` (`AccountMoreOnAO3Screen.kt:142`, Row label) | **same** |
| `"Claims"` (`AccountMoreOnAO3View.swift:273`, Row label) | `"Claims"` (`AccountMoreOnAO3Screen.kt:143`, Row label) | **same** |
| `"Gifts given and received"` (`AccountMoreOnAO3View.swift:280`, Row label) | `"Gifts given and received"` (`AccountMoreOnAO3Screen.kt:144`, Row label) | **same** |
| `"Your account"` (`AccountMoreOnAO3View.swift:110`, Section header) | `"Your account"` (`AccountMoreOnAO3Screen.kt:148`) | **same** |
| `"Profile"` (`AccountMoreOnAO3View.swift:205`, Row label) | `"Profile"` (`AccountMoreOnAO3Screen.kt:150`, Row label) | **same** |
| `"Invitations"` (`AccountMoreOnAO3View.swift:212`, Row label) | `"Invitations"` (`AccountMoreOnAO3Screen.kt:151`, Row label) | **same** |
| `"Skins and site styles"` (`AccountMoreOnAO3View.swift:219`, Row label) | `"Skins and site styles"` (`AccountMoreOnAO3Screen.kt:152`, Row label) | **same** |
| `"Pseuds"` (`AccountMoreOnAO3View.swift:226`, Row label) | `"Pseuds"` (`AccountMoreOnAO3Screen.kt:153`, Row label) | **same** |
| `"Co-Creator Requests"` (`AccountMoreOnAO3View.swift:233`, Row label) | `"Co-Creator Requests"` (`AccountMoreOnAO3Screen.kt:154`, Row label) | **same** |
| `"Statistics"` (`AccountMoreOnAO3View.swift:240`, Row label) | `"Statistics"` (`AccountMoreOnAO3Screen.kt:155`, Row label) | **same** |
| `"The archive"` (`AccountMoreOnAO3View.swift:116`, Section header) | `"The archive"` (`AccountMoreOnAO3Screen.kt:159`) | **same** |
| `"Support and feedback"` (`AccountMoreOnAO3View.swift:19`, Row label) | `"Support and feedback"` (`AccountMoreOnAO3Screen.kt:161`, Row label) | **same** |
| `"Report abuse"` (`AccountMoreOnAO3View.swift:20`, Row label) | `"Report abuse"` (`AccountMoreOnAO3Screen.kt:162`, Row label) | **same** |
| `"Terms of Service"` (`AccountMoreOnAO3View.swift:21`, Row label) | `"Terms of Service"` (`AccountMoreOnAO3Screen.kt:163`, Row label) | **same** |
| `"Content policy"` (`AccountMoreOnAO3View.swift:22`, Row label) | `"Content policy"` (`AccountMoreOnAO3Screen.kt:164`, Row label) | **same** |
| `"Privacy policy"` (`AccountMoreOnAO3View.swift:23`, Row label) | `"Privacy policy"` (`AccountMoreOnAO3Screen.kt:165`, Row label) | **same** |
| `"FAQs"` (`AccountMoreOnAO3View.swift:24`, Row label) | `"FAQs"` (`AccountMoreOnAO3Screen.kt:166`, Row label) | **same** |
| `"Donate to the OTW"` (`AccountMoreOnAO3View.swift:25`, Row label) | `"Donate to the OTW"` (`AccountMoreOnAO3Screen.kt:167`, Row label) | **same** |
| `"These public AO3 pages open in Browse. You don't need to sign in to view them."` (`AccountMoreOnAO3View.swift:307-309`, Footnote) | `"These public AO3 pages open in Browse. You don't need to sign in to view them."` (`AccountMoreOnAO3Screen.kt:169`, Footnote) | **same** |

---

## Pair 11: Work Detail Forms

- **Android**: `works/detail/WorkDetailForms.kt`
- **iOS**: `Features/WorkDetail/` (`BookmarkSheet` in `AO3WorkActionsModel.swift`, `AddToQueueView` in `ReadingQueues.swift`, `SeriesPreservationPromptSheet` in `WorkDetailView.swift`)

### Bookmark Form (`WorkDetailBookmarkForm` vs `BookmarkSheet` in `AO3WorkActionsModel.swift`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `actions.bookmarkIsUpdate ? "Edit Bookmark on AO3" : "Bookmark on AO3"` (`AO3WorkActionsModel.swift:228`, Navigation title) | `if (isEdit) "Edit Bookmark on AO3" else "Bookmark on AO3"` (`WorkDetailForms.kt:132`) | **same** |
| `"Cancel"` (`AO3WorkActionsModel.swift:234`, Toolbar button) | `"Cancel"` (`WorkDetailForms.kt:133`, Toolbar button) | **same** |
| `"Save"` (`AO3WorkActionsModel.swift:240`, Toolbar button) | `"Save"` (`WorkDetailForms.kt:136`, Toolbar button) | **same** |
| `"Notes"` (`AO3WorkActionsModel.swift:200`, Section header) | `"Notes"` (`WorkDetailForms.kt:138`, Section header) | **same** |
| — | Field label: `"Notes"` (`WorkDetailForms.kt:140`) | **Android only** |
| `"Tags"` (`AO3WorkActionsModel.swift:209`, Section header) | `"Tags"` (`WorkDetailForms.kt:144`, Section header) | **same** |
| `"Comma-separated tags"` (`AO3WorkActionsModel.swift:206`, Placeholder) | `"Comma-separated tags"` (`WorkDetailForms.kt:145`, Placeholder) | **same** |
| `"Separate your bookmark tags with commas."` (`AO3WorkActionsModel.swift:211`, Footnote) | `"Separate your bookmark tags with commas."` (`WorkDetailForms.kt:144`, Footnote) | **same** |
| `"Private"` (`AO3WorkActionsModel.swift:214`, Toggle label) | `"Private"` (`WorkDetailForms.kt:149`, Toggle label) | **same** |
| `"Recommend"` (`AO3WorkActionsModel.swift:215`, Toggle label) | `"Recommend"` (`WorkDetailForms.kt:151`, Toggle label) | **same** |
| `error` (`AO3WorkActionsModel.swift:219`, Error text) | `error` (`WorkDetailForms.kt:157`, Error text) | **same** |

### Series Preservation Prompt (`WorkDetailSeriesForm` vs `SeriesPreservationPromptSheet` in `WorkDetailView.swift`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Preserve Series?"` (`WorkDetailView.swift:1240`, Navigation title) | `"Preserve Series?"` (`WorkDetailForms.kt:172`, Navigation title) | **same** |
| `"Cancel"` (`WorkDetailView.swift:1246`, Toolbar button) | — | **missing on Android** (handled via back/dismiss on Only this work) |
| `"Kudos couldn't check how many works are in this series. Continuing may download many works. Kudos adds them one at a time."` (`ReadingQueueService.swift:62-63`, Prompt message fallback) | `"Kudos couldn't check how many works are in this series. Continuing may download many works. Kudos adds them one at a time."` (`SeriesPreservation.kt:48-49`, Prompt message fallback) | **same** |
| Complete preview pattern: `"This series has \(knownCount) work\(knownCount == 1 ? "" : "s"). Download every work in the series?"` (`ReadingQueueService.swift:66-67`) | `"This series has $knownCount work$s. Download every work in the series?"` (`SeriesPreservation.kt:53`) | **same** |
| Incomplete preview pattern: `"This series has at least \(knownCount) work\(knownCount == 1 ? "" : "s") and more may be on other pages. Download every work in the series?"` (`ReadingQueueService.swift:69-70`) | `"This series has at least $knownCount work$s and more may be on other pages. Download every work in the series?"` (`SeriesPreservation.kt:56`) | **same** |
| `"Kudos saves the series one work at a time, with the usual pause between visits to AO3."` (`WorkDetailView.swift:1206-1207`, Footnote) | `"Kudos saves the series one work at a time, with the usual pause between visits to AO3."` (`WorkDetailForms.kt:175`, Footnote) | **same** |
| `"Always auto-preserve series under \(threshold) works"` (`ReadingQueueService.swift:74`, Toggle label) | `"Always auto-preserve series under $threshold works"` (`SeriesPreservation.kt:60`, Toggle label) | **same** |
| `"Kudos saves a series automatically only when the first AO3 page shows the full series and it has \(threshold) works or fewer."` (`WorkDetailView.swift:1214-1215`, Footnote) | `"Kudos saves a series automatically only when the first AO3 page shows the full series and it has ${prompt.threshold} works or fewer."` (`WorkDetailForms.kt:179-180`, Footnote) | **same** |
| `"Preserve Entire Series"` (`WorkDetailView.swift:1225`, Action button) | `"Preserve Entire Series"` (`WorkDetailForms.kt:183`, Action button) | **same** |
| `"Only This Work"` (`WorkDetailView.swift:1232`, Action button) | `"Only This Work"` (`WorkDetailForms.kt:185`, Action button) | **same** |

### Add to Queue Form (`WorkDetailQueueForm` vs `AddToQueueView` in `ReadingQueues.swift`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Add to Queue"` (`ReadingQueues.swift:537`, Navigation title) | `"Add to Queue"` (`WorkDetailForms.kt:212`, Navigation title) | **same** |
| `"Done"` (`ReadingQueues.swift:546`, Toolbar button accessibility label) | `"Done"` (`WorkDetailForms.kt:212`, Toolbar button text) | **same** |
| `"New queue"` (`ReadingQueues.swift:453`, Placeholder) | `"New queue"` (`WorkDetailForms.kt:214`, Label & placeholder) | **same** |
| `"Add"` (`ReadingQueues.swift:455`, Button) | `"Add"` (`WorkDetailForms.kt:215`, Button) | **same** |
| `"Queues"` (`ReadingQueues.swift:482`, Section header) | `"Queues"` (`WorkDetailForms.kt:217`, Section header) | **same** |
| `"A queue with Keep works offline turned on keeps its works downloaded for you."` (`ReadingQueues.swift:484`, Footnote) | `"A queue with Keep works offline turned on keeps its works downloaded for you."` (`WorkDetailForms.kt:218`, Footnote) | **same** |
| `queue.displayName` (`ReadingQueues.swift:466`, Row label) | `queue.displayName` (`WorkDetailForms.kt:221`, Row label) | **same** |
| `"In this queue"` (`ReadingQueues.swift:474`, Checkmark accessibility label) | — | **missing on Android** (`WorkDetailForms.kt:224` renders `"✓"` without accessibility label) |
| `"Series"` (`ReadingQueues.swift:530`, Section header) | `"Series"` (`WorkDetailForms.kt:228`, Section header) | **same** |
| `"Kudos adds series works only after you choose Add Series, one work at a time."` (`ReadingQueues.swift:532`, Footnote) | `"Kudos adds series works only after you choose Add Series, one work at a time."` (`WorkDetailForms.kt:229`, Footnote) | **same** |
| `"Also add works from this AO3 series"` (`ReadingQueues.swift:489`, Toggle label) | `"Also add works from this AO3 series"` (`WorkDetailForms.kt:230`, Toggle label) | **same** |
| `"Checking series size…"` (`ReadingQueues.swift:496`, Progress text) | `"Checking series size…"` (`WorkDetailForms.kt:237`, Progress text) | **same** |
| `"Add Series to Selected Queues"` (`ReadingQueues.swift:508`, Button) | `"Add Series to Selected Queues"` (`WorkDetailForms.kt:240, 243`, Button) | **same** |
| `"Cancel Series Addition"` (`ReadingQueues.swift:519`, Button) | `"Cancel Series Addition"` (`WorkDetailForms.kt:245`, Button) | **same** |
| Progress text pattern: `"Adding \(completed) of \(total) series works…"` (`ReadingQueues.swift:671`) | `"Adding $completed of $total series works…"` (`SeriesPreservation.kt:75`) | **same** |
| Cancelled text pattern: `"Stopped adding the series. \(preserved) work\(preserved == 1 ? " was" : "s were") added."` (`ReadingQueues.swift:674-675`) | `"Stopped adding the series. $preserved work${if (preserved == 1) " was" else "s were"} added."` (`SeriesPreservation.kt:76`) | **same** |
| None found text: `"No series works were found."` (`ReadingQueues.swift:677`) | `"No series works were found."` (`SeriesPreservation.kt:77`) | **same** |
| Already added text: `"Series works are already in the selected queues."` (`ReadingQueues.swift:679`) | `"Series works are already in the selected queues."` (`SeriesPreservation.kt:78`) | **same** |

### Series Preservation Status on Work Detail (`WorkDetailSeriesStatus` vs `WorkDetailView.swift:330-365`)

| iOS String (`path:line`, Appearance) | Android String (`path:line`) | Status |
|---|---|---|
| `"Cancel Series Preservation"` (`WorkDetailView.swift:364`, Button) | `"Cancel Series Preservation"` (`WorkDetailForms.kt:261`, Button) | **same** |
| `queueNotice` (`WorkDetailView.swift:355`, Notice text) | `notice` (`WorkDetailForms.kt:260`, Notice text) | **same** |

---

## Complete List of Every "Differs" and "Missing on Android" (Most Visible First)

### 1. Missing on Android (Most Visible First)

1. **Pair 1: Post Section and Rows on Work Form**
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:133`**: Section header `"Post"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:709`**: Button/Row `"Post work"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:713`**: Button/Row `"Preview on AO3"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:716`**: Button/Row `"Delete draft"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:137`**: Footnote `"AO3 deletes an unposted draft 30 days after it is created."`

2. **Pair 1: Delete Section on Posted Work Form**
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:142`**: Section header `"Delete"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:526`**: Row `"Delete work on AO3"`

3. **Pair 1: Post Confirmation Alert**
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:213`**: Alert title `"Post this work?"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:215`**: Confirm button `"Post work"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:217`**: Missing fields button `"Fill in what is missing"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:219`**: Cancel button `"Cancel"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:221`**: Confirmation message `"Posting makes this work visible to readers on AO3 immediately."` / `"Fill in required fields before posting: <missing>."`

4. **Pair 1: Delete Confirmation Dialog**
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:224`**: Dialog title `"Delete this draft?"` / `"Delete this work?"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:228`**: Destructive button `"Delete"` / `"Delete on AO3"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:231`**: Cancel button `"Cancel"`
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:234`**: Message text from `deleteImplications.cautionText`

5. **Pair 1: Add Chapter Row on Work Form**
   - **`kudos-ao3-reader/Features/Writing/WorkEditView.swift:448`**: Row label `"Add chapter"` (on Android, only reachable inside `WritingChaptersScreen.kt`)

6. **Pair 5: Withdraw Sign-Up Section and Dialog**
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:229`**: Section header `"Withdraw"`
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:453`**: Action button `"Withdraw sign-up"`
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:134`**: Dialog title `"Withdraw this sign-up?"`
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:138`**: Destructive button `"Withdraw Sign-up"`
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:141`**: Cancel button `"Cancel"`
   - **`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:145`**: Dialog message `"Withdrawing removes your requests and offers from \(effectiveTitle)."`

7. **Pair 6: Series Shortcut Item**
   - **`kudos-ao3-reader/Features/Account/AccountShortcuts.swift:33`**: Shortcut title `"Series"`

8. **Pair 9: Authors Scope Newest Work Block and Filter Empty Card**
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:188`**: Section label `"Newest work"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:205`**: Badge text `"UNREAD"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:223`**: Navigation accessibility label `"Open \(work.title)"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:242`**: Metadata `"updated \(work.dateUpdated)"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:245`**: Metadata `"\(words) words"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:360`**: Empty card title `"No new work"`
   - **`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:368-370`**: Empty card detail `"None of these \(noun) has posted something you have not already read. Tap All to see them again."`

9. **Pair 11: Series Preservation Prompt Toolbar Cancel Button**
   - **`kudos-ao3-reader/Features/WorkDetail/WorkDetailView.swift:1246`**: Toolbar button `"Cancel"`

10. **Pair 11: Queue Membership Checkmark Accessibility Label**
    - **`kudos-ao3-reader/Features/Library/ReadingQueues.swift:474`**: Image accessibility label `"In this queue"` (Android `WorkDetailForms.kt:224` draws `"✓"` without semantics)

---

### 2. Differs (Most Visible First)

1. **Pair 5: Submit Sign-up Button Capitalization**
   - iOS: `"Submit Sign-up"` (`kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:502`)
   - Android: `"Submit sign-up"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSignUpScreen.kt:75`)

2. **Pair 3: Chapter Title Field Capitalization**
   - iOS: `"Chapter title"` (`kudos-ao3-reader/Features/Writing/AddChapterView.swift:150`)
   - Android: `"Chapter Title"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:144`)

3. **Pair 1: Writing Work Form Text Rows Capitalization**
   - iOS: `"Additional tags"` (`kudos-ao3-reader/Features/Writing/WorkEditView.swift:286`)
     Android: `"Additional Tags"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:182`)
   - iOS: `"Beginning notes"` (`kudos-ao3-reader/Features/Writing/WorkEditView.swift:423`)
     Android: `"Beginning Notes"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:215`)
   - iOS: `"End notes"` (`kudos-ao3-reader/Features/Writing/WorkEditView.swift:425`)
     Android: `"End Notes"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:218`)
   - iOS: `"Work text"` (`kudos-ao3-reader/Features/Writing/WorkEditView.swift:428`)
     Android: `"Work Text"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:222`)

4. **Pair 3: Chapter Form Notes and Text Rows Capitalization**
   - iOS: `"Beginning notes"` (`kudos-ao3-reader/Features/Writing/AddChapterView.swift:195`)
     Android: `"Beginning Notes"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:192`)
   - iOS: `"End notes"` (`kudos-ao3-reader/Features/Writing/AddChapterView.swift:198`)
     Android: `"End Notes"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:195`)
   - iOS: `"Chapter text"` (`kudos-ao3-reader/Features/Writing/AddChapterView.swift:204`)
     Android: `"Chapter Text"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:200`)

5. **Pair 4: Series Work Remove Button Visible Text**
   - iOS: No visible text (`minus.circle.fill` icon only, `kudos-ao3-reader/Features/Writing/SeriesEditView.swift:164`)
   - Android: Visible text `"Remove"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesScreen.kt:153`)

6. **Pair 1, 2, 4: Required Field Visible Asterisk vs Accessibility Announcement**
   - iOS: Visible label without asterisk; VoiceOver trait/suffix `", required"`:
     - `"Archive warnings, required"` (`kudos-ao3-reader/Features/Writing/WritingFormFields.swift:75`)
     - `"Fandoms, required"` (`kudos-ao3-reader/Features/Writing/WritingFormFields.swift:75, 89`)
     - `"Title, required"` (`kudos-ao3-reader/Features/Writing/WorkEditView.swift:261`, `SeriesEditView.swift:135`)
   - Android: Visible label includes `" ∗"`; TalkBack announces literal `"∗"` rather than `"required"`:
     - `"Archive warnings ∗"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:158`)
     - `"Fandoms ∗"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:170`, `WritingEditTagsScreen.kt:147`)
     - `"Title ∗"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:189`, `WritingSeriesScreen.kt:127`)

7. **Pair 3: Custom Publication Date Toggle Accessibility Announcement**
   - iOS accessibility label: `"Custom publication date"` (`kudos-ao3-reader/Features/Writing/AddChapterView.swift:172`)
   - Android content description: `"Set a different publication date"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:183`)

8. **Pair 9: Favorite Affinity Row Combined Accessibility Text**
   - iOS: `text = "\(row.name). \(logLine)." + (newestWork or libraryText)` (`kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:251-259`)
   - Android: `contentDescription = "${row.name}. $log. $library"` (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/library/FavoriteAffinityRow.kt:108`)
   - (Differs because iOS appends the author's newest work metadata to the VoiceOver element).

---

## First check (Claude, 2026-10-09)

**Not reliable row by row.** Of its 21 "differs", at least six are invented: Android's code
says "Beginning notes", "End notes", "Work text", "Additional tags" and "Chapter title" in
lower case, as iOS does, where this file reports capitals (`WritingWorkFormState.kt:38-39`,
`WritingChapterFormState.kt:19`, `WritingTagsEditorState.kt:20`). The "missing on Android"
rows for Post, Preview and Delete were true when it read the code and are not now (brief 3bx
landed the same afternoon, `5c01ce2b`). Every other row is to be checked against the code
before anything is changed.

Real, and still to fix: a required field's label carries its marker in the text ("Title ∗",
"Archive warnings ∗", "Fandoms ∗"), so TalkBack reads the marker; iOS draws the marker apart
and says "Title, required".
