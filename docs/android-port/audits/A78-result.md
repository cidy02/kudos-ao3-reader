# A78 — W2 words re-checked against current source

Audit date: 2026-10-22. Status: complete (local source audit).

Android HEAD: `a5a2c7f453e3c87cdbfc963767dc464f19a279b1`, branch `android/agent-codex2-a78`. iOS HEAD: `618adae1a11174f0e3e11464326a896e70c894c6`. Android had an existing untracked `A78-recheck-W2-words.md`; iOS had untracked `Packages` and `Vendor`. Those are untouched.

Only this report is written. No code, task board, commits, builds, Gradle, sign-in, network requests or websites. This is a source audit, not a claim of runtime or visual verification.

## Evidence key and counting

`A/` = `android/app/src/main/java/io/github/cidy02/kudos/` in this worktree. `I/` = `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Every source citation below uses these exact roots. W2 references are line numbers in `docs/android-port/audits/W2-result.md`. Each table row below corresponds to one W2 table row, including grouped alternatives. W2's concluding lists repeat those rows and are not counted twice. “W2 was wrong” means the quoted literal is absent from the cited current rendering path; it does not infer historical source solely from today's code. “Same now” establishes present equality, not that the original report was correct.

Required markers are **visible on both apps**. iOS `I/UIComponents/SubjectForm.swift:249` and `I/Features/Writing/WritingFormFields.swift:133` draw `∗`; Android `A/ui/subject/SubjectForm.kt:109` styles it. Android `A/ui/subject/SubjectForm.kt:104` converts the marker to “, required” for speech, applied at lines 173/190; text inputs use `A/settings/SettingsChrome.kt:183`. iOS speech overrides are `I/UIComponents/SubjectForm.swift:252` and `I/Features/Writing/WritingFormFields.swift:75,89`.

## W2 row-by-row re-check

### Pair 1 — Work form

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P1-01 / 42 | W2 was wrong | Both visibly draw “Archive warnings ∗”, not iOS's claimed bare label. A `A/writing/WritingWorkFormScreen.kt:244`; I `I/Features/Writing/WorkEditView.swift:273` + `I/UIComponents/SubjectForm.swift:249`. |
| P1-02 / 43 | same now | Spoken “Archive warnings, required”. A `A/writing/WritingWorkFormScreen.kt:244` + `A/ui/subject/SubjectForm.kt:104,190`; I `I/Features/Writing/WorkEditView.swift:273` + `I/Features/Writing/WritingFormFields.swift:75`. |
| P1-03 / 50 | W2 was wrong | Both visibly draw “Fandoms ∗”. A `A/writing/WritingWorkFormScreen.kt:247`; I `I/Features/Writing/WorkEditView.swift:276` + `I/UIComponents/SubjectForm.swift:249`. |
| P1-04 / 51 | same now | Spoken “Fandoms, required”. A `A/writing/WritingWorkFormScreen.kt:247` + `A/ui/subject/SubjectForm.kt:104,190`; I `I/Features/Writing/WorkEditView.swift:276` + `I/Features/Writing/WritingFormFields.swift:75`. |
| P1-05 / 57 | W2 was wrong | Android's alleged “Additional Tags” is actually “Additional tags”, matching iOS. A `A/writing/WritingWorkFormScreen.kt:270`; I `I/Features/Writing/WorkEditView.swift:291`. |
| P1-06 / 60 | W2 was wrong | Both visibly draw “Title ∗”. A `A/writing/WritingWorkFormScreen.kt:240`; I `I/Features/Writing/WorkEditView.swift:266` + `I/UIComponents/SubjectForm.swift:249`. |
| P1-07 / 61 | same now | Spoken “Title, required”. A `A/writing/WritingWorkFormScreen.kt:240` + `A/settings/SettingsChrome.kt:183` + `A/ui/subject/SubjectForm.kt:104`; I `I/Features/Writing/WorkEditView.swift:266` + `I/UIComponents/SubjectForm.swift:252`. |
| P1-08 / 73 | W2 was wrong | Android's alleged “Beginning Notes” is “Beginning notes”. A `A/writing/WritingWorkFormState.kt:38`, rendered `A/writing/WritingWorkFormScreen.kt:299,442`; I `I/Features/Writing/WorkEditView.swift:428`. |
| P1-09 / 74 | W2 was wrong | Android's alleged “End Notes” is “End notes”. A `A/writing/WritingWorkFormState.kt:38`, rendered `A/writing/WritingWorkFormScreen.kt:301,442`; I `I/Features/Writing/WorkEditView.swift:430`. |
| P1-10 / 75 | W2 was wrong | Android's alleged “Work Text” row is “Work text”. A `A/writing/WritingWorkFormState.kt:39`, rendered `A/writing/WritingWorkFormScreen.kt:306,442`; I `I/Features/Writing/WorkEditView.swift:433`. |
| P1-11 / 77 | same now | “Add chapter”. A `A/writing/WritingWorkFormScreen.kt:313`; I `I/Features/Writing/WorkEditView.swift:453`. It is on the work form itself. |
| P1-12 / 95 | same now | “Post”. A `A/writing/WritingWorkFormScreen.kt:372`; I `I/Features/Writing/WorkEditView.swift:138`. |
| P1-13 / 96 | same now | “Post work”. A `A/writing/WritingWorkFormScreen.kt:374`; I `I/Features/Writing/WorkEditView.swift:720`. |
| P1-14 / 97 | same now | “Preview on AO3”. A `A/writing/WritingWorkFormScreen.kt:377`; I `I/Features/Writing/WorkEditView.swift:724`. |
| P1-15 / 98 | same now | “Delete draft”. A `A/writing/WritingWorkFormScreen.kt:383`; I `I/Features/Writing/WorkEditView.swift:727`. |
| P1-16 / 99 | same now | “AO3 deletes an unposted draft 30 days after it is created.” A `A/writing/WritingWorkFormScreen.kt:387`; I `I/Features/Writing/WorkEditView.swift:142`. |
| P1-17 / 100 | same now | “Delete”. A `A/writing/WritingWorkFormScreen.kt:390`; I `I/Features/Writing/WorkEditView.swift:147`. |
| P1-18 / 101 | same now | “Delete work on AO3”. A `A/writing/WritingWorkFormScreen.kt:392`; I `I/Features/Writing/WorkEditView.swift:534`. |
| P1-19 / 105 | same now | “Post this work?”. A `A/writing/WritingAO3PreviewScreen.kt:114`, called `A/writing/WritingWorkFormScreen.kt:194`; I `I/Features/Writing/WorkEditView.swift:218`. |
| P1-20 / 106 | same now | “Post work” / “Fill in what is missing”. A `A/writing/WritingWorkFormScreen.kt:194`; I `I/Features/Writing/WorkEditView.swift:220,222`. |
| P1-21 / 107 | same now | “Cancel” (post alert). A `A/writing/WritingAO3PreviewScreen.kt:116`; I `I/Features/Writing/WorkEditView.swift:224`. |
| P1-22 / 108 | same now | Both generate “Posting notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft.” Or “One thing is missing” / “Two things are missing” / “[N] things are missing”, then “. Add [localized list]. AO3 requires it/both/all of them. Posting also ” plus that consequence. A `A/writing/WritingWorkFormState.kt:475–484`; I `I/Features/Writing/WorkEditView.swift:775–792`. Same requirement phrases and locale list joining; W2's concluding “Posting makes this work visible…” wording is absent on both. |
| P1-23 / 109 | same now | “Delete this draft?” / “Delete this work?”. A `A/writing/WritingWorkFormScreen.kt:203`; I `I/Features/Writing/WorkEditView.swift:229`. |
| P1-24 / 110 | same now | “Delete” / “Delete on AO3”. A `A/writing/WritingWorkFormScreen.kt:206`; I `I/Features/Writing/WorkEditView.swift:233`. |
| P1-25 / 111 | same now | “Cancel” (delete dialog). A `A/writing/WritingWorkFormScreen.kt:208`; I `I/Features/Writing/WorkEditView.swift:236`. |
| P1-26 / 112 | same now | Both display AO3-derived `cautionText` without a local rewording. A `A/writing/WritingWorkFormScreen.kt:204`; I `I/Features/Writing/WorkEditView.swift:239`. No fixed literal can honestly be quoted for arbitrary server data; the exact bound property is `implications.cautionText` / `imp.cautionText`. |

### Pair 2 — Edit Tags

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P2-01 / 141 | W2 was wrong | Both visibly draw “Fandoms ∗”. A `A/writing/WritingEditTagsScreen.kt:153`; I `I/Features/Writing/EditTagsView.swift:219,236` + `I/Features/Writing/WritingFormFields.swift:133`. The spoken “Fandoms, required” also matches via A `A/ui/subject/SubjectForm.kt:104,190` and I `I/Features/Writing/WritingFormFields.swift:89`. |

### Pair 3 — Chapters list and chapter form

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P3-01 / 188 | W2 was wrong | Neither current field says “Chapter Title”; both label and placeholder are “Title”. A `A/writing/WritingChapterFormScreen.kt:102`; I `I/Features/Writing/AddChapterView.swift:151,152`. |
| P3-02 / 192 | same now | Spoken “Custom publication date”. A `A/writing/WritingChapterFormScreen.kt:142` (routed to toggle at `A/writing/WritingWorkFormScreen.kt:470`); I `I/Features/Writing/AddChapterView.swift:265`. |
| P3-03 / 196 | W2 was wrong | Android's alleged “Beginning Notes” is “Beginning notes”. A `A/writing/WritingChapterFormState.kt:19`, rendered `A/writing/WritingChapterFormScreen.kt:126`; I `I/Features/Writing/AddChapterView.swift:238`. |
| P3-04 / 197 | W2 was wrong | Android's alleged “End Notes” is “End notes”. A `A/writing/WritingChapterFormState.kt:19`, rendered `A/writing/WritingChapterFormScreen.kt:126`; I `I/Features/Writing/AddChapterView.swift:240`. |
| P3-05 / 199 | W2 was wrong | Android's alleged “Chapter Text” row is “Chapter text”. A `A/writing/WritingChapterFormState.kt:18`, rendered `A/writing/WritingChapterFormScreen.kt:126`; I `I/Features/Writing/AddChapterView.swift:225`. |

### Pair 4 — Series form

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P4-01 / 226 | W2 was wrong | Both visibly draw “Title ∗”. A `A/writing/WritingSeriesScreen.kt:174`; I `I/Features/Writing/SeriesEditView.swift:163` + `I/UIComponents/SubjectForm.swift:249`. |
| P4-02 / 227 | same now | Spoken “Title, required”. A `A/writing/WritingSeriesScreen.kt:174` + `A/settings/SettingsChrome.kt:183` + `A/ui/subject/SubjectForm.kt:104`; I `I/Features/Writing/SeriesEditView.swift:163` + `I/UIComponents/SubjectForm.swift:252`. |
| P4-03 / 236 | still differs | **Visible**: Android “Remove” (`A/writing/WritingSeriesScreen.kt:158`); iOS icon only (`I/Features/Writing/SeriesEditView.swift:541`). Both spoken labels say “Remove [title] from the series”: A `A/writing/WritingSeriesScreen.kt:159`; I `I/Features/Writing/SeriesEditView.swift:544`. |

### Pair 5 — Challenge sign-up

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P5-01 / 284 | same now | “Withdraw”. A `A/account/AO3ChallengeSignUpScreen.kt:207`; I `I/Features/Challenges/ChallengeSignUpView.swift:238`. |
| P5-02 / 285 | same now | “Withdraw sign-up”. A `A/account/AO3ChallengeSignUpScreen.kt:211`; I `I/Features/Challenges/ChallengeSignUpView.swift:467`. |
| P5-03 / 286 | same now | “Withdraw this sign-up?”. A `A/account/AO3ChallengeSignUpScreen.kt:89`; I `I/Features/Challenges/ChallengeSignUpView.swift:143`. |
| P5-04 / 287 | same now | “Withdraw Sign-up”. A `A/account/AO3ChallengeSignUpScreen.kt:94`; I `I/Features/Challenges/ChallengeSignUpView.swift:147`. |
| P5-05 / 288 | same now | “Cancel”. A `A/account/AO3ChallengeSignUpScreen.kt:96`; I `I/Features/Challenges/ChallengeSignUpView.swift:150`. |
| P5-06 / 289 | same now | “Withdrawing removes your requests and offers from [effective title].” A `A/account/AO3ChallengeSignUpScreen.kt:90`; I `I/Features/Challenges/ChallengeSignUpView.swift:154`. |
| P5-07 / 291 | same now | “Submit sign-up” (lowercase s on both now). A `A/account/AO3ChallengeSignUpScreen.kt:232`; I `I/Features/Challenges/ChallengeSignUpView.swift:520`. |

### Pair 6 — Account shortcuts

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P6-01 / 318 | same now | “Series”. A `A/account/AccountShortcuts.kt:18`; I `I/Features/Account/AccountShortcuts.swift:33`. |

### Pair 7 — Author works sort fields

W2 reports no differing or missing iOS rows in this pair. Omission sweep below.

### Pair 8 — Library History grouping

W2 reports no differing or missing iOS rows in this pair. Omission sweep below.

### Pair 9 — Favorite affinities

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P9-01 / 405 | same now | Visible “NEWEST WORK”. A `A/library/FavoriteAffinityRow.kt:179`; I `I/Features/Library/FavoriteAffinityRow.swift:188,191` (“Newest work” with `.textCase(.uppercase)`). |
| P9-02 / 406 | same now | “UNREAD”. A `A/library/FavoriteAffinityRow.kt:188`; I `I/Features/Library/FavoriteAffinityRow.swift:205`. |
| P9-03 / 407 | still differs | **Spoken only, link/action name**: A “Open this work” (`A/library/FavoriteAffinityRow.kt:177`); I “Open \(work.title)” (`I/Features/Library/FavoriteAffinityRow.swift:223`). The block exists; its label differs. |
| P9-04 / 408 | same now | “updated [date]” and “[compact number] words”. A `A/library/FavoriteAffinityRow.kt:98,99` + `A/home/HomeFacts.kt:178`; I `I/Features/Library/FavoriteAffinityRow.swift:242,245`. Number formatting is discussed under platform matters below. |
| P9-05 / 409 | still differs | **Spoken only, combined description**: A literal template `"${row.name}. $log. $library"` (`A/library/FavoriteAffinityRow.kt:134`); I `"\(row.name). \(logLine)."` followed, when present, by `" Newest work: \(newestWork.title), \(newestWorkMetadata(newestWork))."` and optional `" Unread."` (`I/Features/Library/FavoriteAffinityRow.swift:251–256`). Android always appends the library line, even with a newest work; its description never appends those newest-work sentences. Child TalkBack behavior is not assumed from this source audit. |
| P9-06 / 414 | same now | “No new work”. A `A/library/FavoriteAffinityRow.kt:359`; I `I/Features/Library/FavoriteAffinityRow.swift:362`. |
| P9-07 / 415 | same now | “None of these [noun] has posted something you have not already read. Tap All to see them again.” A `A/library/FavoriteAffinityRow.kt:364`; I `I/Features/Library/FavoriteAffinityRow.swift:375,376`. Both also have the unchecked-authors alternative (A line 363; I line 374). |

### Pair 10 — More on AO3

W2 reports no differing or missing iOS rows in this pair. Omission sweep below.

### Pair 11 — Work Detail forms

| ID / W2 line | Verdict | Exact present wording and both source locations |
|---|---|---|
| P11-01 / 491 | still differs | **Visible toolbar action**: I “Cancel” (`I/Features/WorkDetail/WorkDetailView.swift:1248`); A has no Cancel action in `A/works/detail/WorkDetailForms.kt:173–188` (the form is created without a leading/action slot). A visible alternative is “Only This Work” at line 186, which calls the same close callback; this is not the requested Cancel word. Shared dismiss/back behavior is addressed below. |
| P11-02 / 512 | still differs | **Spoken only, queue membership label**: I “In this queue” (`I/Features/Library/ReadingQueues.swift:488`); A renders `"✓"` without a content description (`A/works/detail/WorkDetailForms.kt:227`). No custom label or selected semantics is supplied by this row at line 224. |

## W2's sixteen “Android only” rows

These are separate from W2's **21 differs + 31 missing** rows above. They are included so “every row” does not silently exclude reverse-only claims. System-generated gesture instructions, selected traits, and native date-picker words are platform matters; authored group descriptions and status captions are still wording differences.

| ID / W2 line | Verdict | Current evidence on both sides |
|---|---|---|
| X1 / 88 | not applicable | **Android date-picker controls vs iOS native DatePicker.** A “Year”, “Month”, “Day” (`A/writing/WritingWorkFormScreen.kt:542,543`); I native “Publication date” picker (`I/Features/Writing/WorkEditView.swift:501–507`). W2's Android “Done” no longer exists in that sheet; it dismisses through the modal instead (`A/writing/WritingWorkFormScreen.kt:538–557`). |
| X2 / 116 | W2 was wrong | A has an unlabelled spinner, not the claimed “Loading work form…” (`A/writing/WritingWorkFormScreen.kt:225`); I also has an unlabelled spinner (`I/Features/Writing/WritingDraftsView.swift:559`, work loader call at line 350). |
| X3 / 117 | same now | “Couldn't load from AO3” + dynamic error + “Try Again”. A `A/writing/WritingWorkFormScreen.kt:227,229,232`; I `I/Features/Writing/WritingDraftsView.swift:552,554,556` (call at line 350). W2 overlooked the iOS loader. |
| X4 / 118 | same now | “Rating”, “Who can comment”, “Work skin”. A choice-sheet titles `A/writing/WritingWorkFormScreen.kt:404,406,407`; I titled Picker through `I/Features/Writing/WritingFormFields.swift:23`, supplied by `I/Features/Writing/WorkEditView.swift:270,525,473`. Menu vs sheet presentation is platform UI; these words are not absent on iOS. |
| X5 / 119 | not applicable | **TalkBack/VoiceOver selection representation.** A “Selected” icon description `A/writing/WritingWorkFormScreen.kt:500`; I native selected Picker option `I/Features/Writing/WritingFormFields.swift:23–29`. System selected-state announcements are not authored copy. |
| X6 / 153 | same now | “Loading tags…”. A `A/writing/WritingEditTagsScreen.kt:109`; I `I/Features/Writing/WritingDraftsView.swift:413`. |
| X7 / 154 | same now | Dynamic failure and “Try Again”. A `A/writing/WritingEditTagsScreen.kt:101,104`; I `I/Features/Writing/WritingDraftsView.swift:409,410`. |
| X8 / 155 | not applicable | **TalkBack/VoiceOver selection representation.** A “Selected” (`A/writing/WritingEditTagsScreen.kt:119,130`); I selected trait (`I/Features/Writing/EditTagsView.swift:189`, check image hidden at line 187). |
| X9 / 194 | not applicable | **Android date-picker controls vs iOS native DatePicker.** A “Year”, “Month”, “Day” through the shared sheet (`A/writing/WritingChapterFormScreen.kt:185`, `A/writing/WritingWorkFormScreen.kt:542,543`); I “Publication date” native picker (`I/Features/Writing/AddChapterView.swift:275`). W2's “Done” is absent from Android's current sheet. |
| X10 / 211 | same now | “Couldn't load from AO3” and “Try Again”. A `A/writing/WritingChapterFormScreen.kt:91,94`; I `I/Features/Writing/WritingDraftsView.swift:552,556` (chapter loader call at line 506). |
| X11 / 247 | not applicable | **Platform reorder interaction.** A state “Drag to reorder.” and custom actions “Move Earlier”, “Move Later” (`A/writing/WritingSeriesScreen.kt:141–144`); I `.onMove` with iOS edit mode (`I/Features/Writing/SeriesEditView.swift:346–348,370–371`). No authored iOS equivalents to quote; OS gesture/action wording is not in app source. |
| X12 / 251 | still differs | **Visible, Android extra captions:** A “Loading…” / “Saving…” (`A/writing/WritingSeriesScreen.kt:260`); I no loading caption (`I/Features/Writing/WritingDraftsView.swift:559`, series call `I/Features/Writing/SeriesEditView.swift:615`) and no saving caption (Save merely disabled at `I/Features/Writing/SeriesEditView.swift:149,150`; reorder Save at line 378). The failure strings “Couldn't load from AO3” / “Try Again” in this same W2 row **do** match: A `A/writing/WritingSeriesScreen.kt:252,255`; I `I/Features/Writing/WritingDraftsView.swift:552,556`. |
| X13 / 324 | not applicable | **Platform reorder interaction.** A “Move ${shortcut.title} up” / “Move ${shortcut.title} down” (`A/account/AccountShortcutsEditor.kt:64,68`); I `.onMove` in active iOS edit mode (`I/Features/Account/AccountShortcuts.swift:128,162`), with no app-authored counterpart. |
| X14 / 380 | still differs | **Spoken only, Android extra group label:** A “History grouping” (`A/library/LibraryScreen.kt:1640`, applied by `A/ui/subject/SubjectSegmentedControl.kt:58`); I no group description on the strip (`I/Features/Library/LibrarySectionListView.swift:639–644`, helper `I/UIComponents/SubjectForm.swift:395–409`). I announces option names such as “Time”, “State”, “Fandom”, “Flat” at `I/Features/Library/LibraryHistoryGrouping.swift:22–25`; those option words match A `A/library/LibraryHistoryGrouping.kt:22–25`. Extra group name is not a missing feature. |
| X15 / 419 | still differs | **Spoken only, Android extra group labels:** A “Favorites scope” / “Favorites order” (`A/library/FavoriteAffinityRow.kt:205,207,265`, shared application `A/ui/subject/SubjectSegmentedControl.kt:58`); I has option names only (`I/Features/Library/LibrarySectionListView.swift:422–432`, helper `I/UIComponents/SubjectForm.swift:395–409`). No custom iOS group-name strings. A's large-text alternative at lines 254–261 does not apply these descriptions. |
| X16 / 478 | W2 was wrong | A's “Notes” is the field's spoken name, not an extra visible field label: `fieldOnly = true` (`A/works/detail/WorkDetailForms.kt:141,142`, branch `A/settings/SettingsChrome.kt:193`). Both have the visible “Notes” section (A line 139; I `I/Features/WorkDetail/AO3WorkActionsModel.swift:200`), followed by an editor; iOS editor is at line 201. |

The dated decision relevant to the earlier marker claims is **“2026-10-09: a required field is spoken as ‘…, required’”**, `docs/android-port/DECISIONS.md:1231`. It explicitly says the markers are drawn and spoken as “required”. The source evidence above establishes present parity, so those speech rows remain “same now”, not exceptions excusing a gap.

## Omissions by screen pair

The sweep covers the eleven W2 pairs, their current main-screen helpers, loaders, dialogs, and status/error constructors, plus the challenge's tag sheet, the merged author sort/filter panel and the Library/Favorites toolbars and their More menus. Navigation to unrelated full screens (for example the general text editor, account destinations, or reader) is not recursively treated as another screen pair. Dynamic AO3 titles, tags, errors, counts and caution text are compared as bindings/templates, not invented fixture values. No new gap is asserted solely from an unsuccessful literal search; absent-side citations point to the rendering path.

### Pair 1 — Work form

**No additional iOS wording absent/different in Android found.** The current form is considerably different from W2's old “same” rows, but both apps moved together: “AO3 Account” (A `A/writing/WritingWorkFormScreen.kt:216`; I `I/Features/Writing/WorkEditView.swift:57`); “Required before posting” / “Required” (A line 238; I line 75); draft note (A lines 218–219; I lines 67–68); “Association”, “Series”, “Add to collections”, “Gift recipients”, “Co-creators”, “Inspired by” (A lines 276–290; I lines 102,306,314,320,328,334); “Reload tags” (A line 258; I line 86); “Work is complete” (A line 348; I line 666). “Empty” / “Set” row values agree (A line 442; I `I/Features/Writing/WritingTextEditor.swift:520`). Post-message wording is P1-22. Reload/session messages match A `A/writing/WritingWorkFormState.kt:211,245,382` and I `I/Features/Writing/WorkEditView.swift:180,199,575`. The HTTP/offline/timeout/TLS/parse messages at A `A/writing/WritingWorkFormState.kt:452–471` agree with I `I/Models/AO3Models.swift:1252–1259` and `I/Services/UserFacingError.swift:46,52,55,73`.

### Pair 2 — Edit Tags

**No additional gap found.** In particular the required spoken “Fandoms, required” is present via the helper (P2-01), “Loading tags…” and “Try Again” are shared (X6/X7), and chip actions “Add [title]” / “Remove [value]” agree (A `A/writing/WritingEditTagsScreen.kt:171,183`; I `I/Features/Writing/WritingFormFields.swift:124,110`). Current footnotes match A `A/writing/WritingEditTagsScreen.kt:136,193` and I `I/Features/Writing/EditTagsView.swift:73,100`. Save/error controls agree at A lines 64,72,74 and I lines 131,124,127.

### Pair 3 — Chapters list and chapter form

| ID | Verdict / kind | Exact iOS wording vs Android wording and evidence |
|---|---|---|
| O3-01 | still differs — visible chapter-list failure when authentication is unavailable | I “Log in to AO3 before using this feature.” (`I/Services/AO3AuthService.swift:39`, thrown by `authenticatedRequest` at line 730; called by `I/Features/Writing/WritingChaptersView.swift:86`, displayed at line 39). A “Your AO3 session expired. Please log in again.” (`A/writing/WritingWorkFormState.kt:452`), because chapter loading returns `AuthenticationRequired` (`A/writing/WritingWorkFormState.kt:270`, `A/network/ao3/writing/AO3WorkFormRepository.kt:38`); the list renders the mapped message at `A/writing/WritingChaptersScreen.kt:94`. This is an edge-state wording comparison, not a claim that the signed-out app offers the Chapters entry. |

Otherwise W2's list kicker/title/date descriptions are stale, but current list text matches: “AO3 Account”, “Chapters”, “[work title] · [N] chapter(s)” (A `A/writing/WritingChaptersScreen.kt:26,68`; I `I/Features/Writing/WritingChaptersView.swift:29,100`), chapter display name/date bindings (A lines 81–86; I lines 63–64), loading/retry (A lines 105,96; I lines 44,40). Current chapter form labels “Expected chapter total”, “Position”, “After chapter” and spoken “Position, after chapter” match A `A/writing/WritingChapterFormScreen.kt:105–118` and I `I/Features/Writing/AddChapterView.swift:158–185`. Empty chapter hint matches A line 130 with I line 226 + `I/Features/Writing/WritingTextEditor.swift:536`. Last-chapter/post footnotes match A lines 212–213 and I `I/Features/Writing/AddChapterView.swift:93,108`; “Retry updating the work total”, “The chapter was saved. Only the work total will be retried.”, “Post chapter now”, “Save chapter changes”, “Save as draft” match A lines 162,164,169,178 and I lines 300,302,315,336.

The old exception **“2026-10-09: what a sent write says, continued (audit A26)”**, `docs/android-port/DECISIONS.md:1137`, says iOS prefixed an uncertain chapter delete with “was not deleted”. Today's iOS explicitly avoids that prefix (`I/Features/Writing/AddChapterView.swift:455–457`), as Android does (`A/writing/WritingChapterFormState.kt:182,183`). Both now use “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.” (`I/Models/AO3WritingModels.swift:1071`; A shared `A/network/ao3/account/AO3CollectionForm.kt:31`). This is no remaining wording exception.

### Pair 4 — Series form

| ID | Verdict / kind | Exact iOS wording vs Android wording and evidence |
|---|---|---|
| O4-01 | still differs — visible, **loading/error header for reorder entry only** | I “Reorder series” (`I/Features/Writing/SeriesReorderDestination.swift:31`, passed to `I/Features/Writing/WritingDraftsView.swift:544`); A “Reorder” (`A/writing/WritingSeriesScreen.kt:112`, even while `form` and `rows` are null at line 116). Once loaded, both say “Reorder” (I `I/Features/Writing/SeriesEditView.swift:319`; A line 112). |

Otherwise current series fields/footnotes/removal dialog agree: A `A/writing/WritingSeriesScreen.kt:174,180,189,203,205,210,214,217,222,224,236–240` and I `I/Features/Writing/SeriesEditView.swift:163,167,177,181,186,96,195,208,236,221,111,517–525`. The removal's spoken label agrees (P4-03). Untitled and draft labels agree (A `A/network/ao3/writing/AO3SeriesForm.kt:24`; `A/writing/WritingSeriesScreen.kt:154`; I `I/Features/Writing/SeriesEditView.swift:393,402,552`). The A26 uncertain-removal prefix exception is also obsolete: I explicitly avoids it at lines 571–573, matching A `A/writing/WritingSeriesState.kt:163`; ordinary failures keep the prefix on both at I line 575 / A line 164.

### Pair 5 — Challenge sign-up

**No additional gap found.** W2's supposedly same title/description/optional-tags inputs are stale. Current iOS instead shows “Prompt”, “Describe what you would love to receive…”, “Visible to your recipient only”, “[N] / 1000”; all are in Android (A `A/account/AO3ChallengeSignUpScreen.kt:171,175,177`; I `I/Features/Challenges/ChallengeSignUpView.swift:323,327,346,353`). “Add an offer”, “Any Fandom”, offer tag count and the edit-until-close footnote agree (A lines 200,295–297,203; I lines 419,441–443,449). Request-limit footnote constructors agree (A lines 300–310; I lines 367–383). The tag sheet's “Tags”, “Comma-separated tag names”, four section labels, placeholders, and “Done” match A lines 272,280–288 + `A/network/ao3/account/AO3ChallengeSignUp.kt:14–17` against I `I/Features/Challenges/PromptTagsEditorView.swift:26–59,71`. Request/offer/tag validation messages match A `A/network/ao3/account/AO3ChallengeSignUp.kt:66–84` against I `I/Models/AO3ChallengeModels.swift:509–553`; success/withdrawal notices match A `A/account/AO3ChallengeSignUpState.kt:117,144` against I `I/Features/Challenges/ChallengeSignUpView.swift:693,709`.

The declared iOS challenge no-CSRF string says “open the challenge”, but it is **not** the string used by this save/withdraw path: these call `fetchCSRFPage` (`I/Services/AO3ChallengeActions.swift:41,77`), which throws `AO3WriteError.noCSRFToken` (`I/Services/AO3WriteActions.swift:410`). Its actual “Couldn't prepare the request. Try again, or open the work on AO3.” (I line 555) matches A `A/network/ao3/writes/AO3WriteRepository.kt:486,567`. No false difference is filed against the unused declaration.

### Pair 6 — Account shortcuts

**No additional iOS wording absent/different found.** All twelve title entries agree (A `A/account/AccountShortcuts.kt:10–23`; I `I/Features/Account/AccountShortcuts.swift:27–38`). “On the grid”, “Not on the grid”, “Reset to Default”, “Done” agree (A `A/account/AccountShortcutsEditor.kt:52,86,102,45`; I lines 134,143,151,166); footer agrees (A `A/account/AccountShortcuts.kt:29`; I lines 137–138); “Add [shortcut]” / “Remove [shortcut]” agree (A editor line 115; I line 192). Reorder wording is the platform matter X13.

### Pair 7 — Author works sort fields (including its merged refine panel)

| ID | Verdict / kind | Exact iOS wording vs Android wording and evidence |
|---|---|---|
| O7-01 | still differs — spoken only, warning/category facet states | I combines the facet title with “Included” / “Excluded” and **no status word** when clear (`I/Features/Search/AO3FilterPanel.swift:574`, `I/Models/AO3Models.swift:1289–1293`). A supplies state “Include” / “Exclude” / “Clear” (`A/search/FilterTagPicker.kt:199,252–256`); it additionally draws the same “Include” / “Exclude” text visibly at line 211. I's visible badge text is also “Include” / “Exclude” (`I/Features/Search/AO3FilterPanel.swift:561,565`), so this finding concerns speech, not visible capitalization. |
| O7-02 | still differs — spoken only, word-count range's combined value | I parent “Range” has value `"\(lowerAccessibilityValue) to \(upperAccessibilityValue)"` (`I/Features/Search/FilterRangeSlider.swift:33,34,170`), e.g. “Any to Any”, with bound fallbacks at lines 162,166. A's parent says only “Range” (`A/search/FilterRangeSlider.kt:101`); its two thumbs individually say “From” / “To” with value or “Any” (`A/search/FilterRangeSlider.kt:82,83,120`). The combined sentence is absent; each bound's information is present. This reports authored semantics, not a prediction of either OS's complete utterance. |
| O7-03 | still differs — spoken help/hint on iOS | I “Sort and filter the works on this page” (`I/Features/Authors/AuthorProfileView.swift:828`, passed to `.help(filterHelp)` at `I/UIComponents/WorkCardListControls.swift:96`). A names the button only “Sort and filter” (`A/author/AuthorProfileScreen.kt:460–463`); its shared chrome helper has no corresponding help string (`A/ui/subject/SubjectComponents.kt:863–874`). The short button label itself matches. |
| O7-04 | still differs — spoken active-filter count suffix | I value `"\(badgeCount) active"` (`I/UIComponents/WorkCardListControls.swift:91`, author caller `I/Features/Authors/AuthorProfileView.swift:832–834`). A supplies only the button name “Sort and filter” and numeric badge (`A/author/AuthorProfileScreen.kt:460–463`, helper `A/ui/subject/SubjectComponents.kt:874–876`); no “active” value is authored on that path. Library's separate FilterButton does include “active”, but this author toolbar uses ToolbarCircleButton instead. |

The actual sort fields remain equal: row labels, nine column names, directions, completion labels, caption and footer (A `A/author/AuthorWorksSortFields.kt:19,40–48,64–76`, `A/network/ao3/author/AO3AuthorModels.kt:90–116`; I `I/Features/Search/AO3FilterPanel.swift:637–670`, `I/Models/AO3WorksSort.swift:26–34,57–58,79–81,151`). The live count, Apply, Reset, group labels, tag instructions and range footer match (A `A/search/AO3SummaryFilter.kt:98–102`, `A/search/SearchFilterSheet.kt:110,128,169–278,392–395`; I `I/Features/Search/AO3FilterPanel.swift:169,170,192,229,270–334,433,486–509`).

### Pair 8 — Library History grouping

| ID | Verdict / kind | Exact iOS wording vs Android wording and evidence |
|---|---|---|
| O8-01 | still differs — visible reading-duration fact missing | I renders duration, e.g. “30 min”, “1h”, “1h 30m” (`I/Features/Library/ReadingHistoryFactsStrip.swift:76,77`, exact formatter `I/Services/ReadingInsights.swift:248,251`). A has **no duration text** in its History row: `A/library/LibraryScreen.kt:1025–1076`, called for History at lines 1563–1575; it renders normal work metadata/progress plus the optional Move back button. A's existing matching formatter (`A/library/ReadingStatistics.kt:304–309`) is not called by this row. I adds this strip under the normal work row (`I/Features/Library/LibrarySectionListView.swift:852,865–872`). |
| O8-02 | still differs — visible reread fact missing | I `"Read ×\(summary.finishCount)"`, when finish count > 1 (`I/Features/Library/ReadingHistoryFactsStrip.swift:82,83`); A **no reread label** in `A/library/LibraryScreen.kt:1025–1076` or its History call at lines 1563–1575. It does not pass a reading summary into this renderer. |
| O8-03 | still differs — visible new-chapter fact missing | I “1 new chapter” / `"\(newChapterCount) new chapters"` (`I/Features/Library/ReadingHistoryFactsStrip.swift:85–88`); A **no new-chapter text** in `A/library/LibraryScreen.kt:1025–1076`, called at lines 1563–1575. Its chapter metadata at line 1032 is the work's overall chapter count, not the since-last-visit fact. |
| O8-04 | still differs — visible More-menu layout wording | I “Layout”, with “Detailed” and “Ledger” options (`I/UIComponents/WorkCardListControls.swift:158,28,29`, called `I/Features/Library/LibrarySectionListView.swift:228`, History's allowed list at line 679). A one action “Display · Ledger” / “Display · Detailed” (`A/library/LibraryScreen.kt:1419`), with no “Layout” heading. |
| O8-05 | still differs — visible More-menu expand/collapse wording | I “Collapse All Cards” / “Expand All Cards” (`I/UIComponents/WorkCardListControls.swift:141`, called `I/Features/Library/LibrarySectionListView.swift:231`); A “Collapse All” / “Expand All” (`A/library/LibraryScreen.kt:1421`). Both show this only in Detailed mode. |
| O8-06 | still differs — visible More-menu privacy wording | I “Hide mature” / “Show mature” (`I/Features/Privacy/MatureContent.swift:363`, called `I/Features/Library/LibrarySectionListView.swift:219`); A “Hide mature works” / “Show mature works” (`A/library/LibraryScreen.kt:1414`). |
| O8-07 | still differs — spoken help/hint on iOS | I “Filter the works in this section” (`I/Features/Library/LibrarySectionListView.swift:213`, `.help` at `I/UIComponents/WorkCardListControls.swift:96`); A short “Filter” or `"Filter, $badgeCount active"` only (`A/ui/subject/SubjectComponents.kt:1006,1024`, called by `A/library/LibraryScreen.kt:1398–1402`). No hint is supplied. |

All grouping option/bucket/tally words match: A `A/library/LibraryHistoryGrouping.kt:22–39,72–78,142–153`; I `I/Features/Library/LibraryHistoryGrouping.swift:22–25,57,79,100,114,115,124–136,168–173`. “Move back to In progress” also matches (A `A/library/LibraryScreen.kt:1617`; I `I/Features/Library/ReadingHistoryFactsStrip.swift:16`). The 2026-10-08 decision “Reading History is grouped (brief 3bp)” (`docs/android-port/DECISIONS.md:1016`) records grouping and the override, not permission to omit these row facts.

### Pair 9 — Favorite affinities and Works scope

| ID | Verdict / kind | Exact iOS wording vs Android wording and evidence |
|---|---|---|
| O9-01 | still differs — visible duration missing in **Works scope** | Same duration strings as O8-01, separately missing on this surface. I adds the strip to Favorites Works with `.favorites` style (`I/Features/Library/LibrarySectionListView.swift:865–872`, duration at `I/Features/Library/ReadingHistoryFactsStrip.swift:76,77`); A uses `LibrarySubjectLedgerRow` for Favorites Works (`A/library/LibraryScreen.kt:1563–1575`) whose body has no strip at lines 1025–1076. Aggregate Authors/Fandoms/Tags **do** show duration (A `A/library/FavoriteAffinityRow.kt:77`; I `I/Features/Library/FavoriteAffinityRow.swift:291`). |
| O9-02 | still differs — visible “Read ×N” missing in **Works scope** | I `"Read ×\(summary.finishCount)"` (`I/Features/Library/ReadingHistoryFactsStrip.swift:83`, Favorites call `I/Features/Library/LibrarySectionListView.swift:866–871`); A no reread label in `A/library/LibraryScreen.kt:1025–1076`, called for Favorites at lines 1563–1575. Same underlying omission as O8-02, reported here because it affects a second requested pair. |
| O9-03 | still differs — visible More-menu layout wording in Works scope | I “Layout”, “Detailed”, “Ledger”, **“Compact”** (`I/UIComponents/WorkCardListControls.swift:158,28–30`; Favorites allows all modes at `I/Features/Library/LibrarySectionListView.swift:679`). A “Display · Ledger” / “Display · Detailed” only (`A/library/LibraryScreen.kt:1419`, Works shows this through the condition at line 1418). This includes the extra missing “Compact” option; the account-list-only Compact decisions do not cover this local Favorites list. |
| O9-04 | still differs — visible More-menu expand/collapse wording in Works scope | I “Collapse All Cards” / “Expand All Cards” (`I/UIComponents/WorkCardListControls.swift:141`, caller `I/Features/Library/LibrarySectionListView.swift:231`); A “Collapse All” / “Expand All” (`A/library/LibraryScreen.kt:1421`). Same shared-wording difference as O8-05. |
| O9-05 | still differs — visible More-menu privacy wording | I “Hide mature” / “Show mature” (`I/Features/Privacy/MatureContent.swift:363`, caller `I/Features/Library/LibrarySectionListView.swift:219`); A “Hide mature works” / “Show mature works” (`A/library/LibraryScreen.kt:1414`). Same shared-wording difference as O8-06. |
| O9-06 | still differs — spoken help/hint in Works scope | I “Filter the works in this section” (`I/Features/Library/LibrarySectionListView.swift:213`, `.help` at `I/UIComponents/WorkCardListControls.swift:96`); A “Filter” or `"Filter, $badgeCount active"` (`A/ui/subject/SubjectComponents.kt:1006,1024`, Works caller `A/library/LibraryScreen.kt:1398–1402`), without the hint. Same shared-wording difference as O8-07. |

No additional aggregate-affinity wording gap found beyond P9-03/P9-05. “All” / “With new work”, checking/failure captions and unavailable hints agree: A `A/library/FavoriteAffinityRow.kt:234–244`; I `I/Features/Library/FavoriteAuthorFilterRail.swift:60,68–81` (“All” / “With new work”: A `A/library/AuthorNewestWorkStore.kt:91`; I `I/Features/Library/FavoriteQuickFilter.swift:96,97`). Empty-card unchecked-author wording agrees at A lines 363–365 and I `I/Features/Library/FavoriteAffinityRow.swift:373–379`. The shared duration formatter matches (A `A/library/ReadingStatistics.kt:304–309`; I `I/Services/ReadingInsights.swift:246–251`).

### Pair 10 — More on AO3

**No additional gap found.** Header, all four groups, all 23 destinations and both footnotes agree (A `A/account/AccountMoreOnAO3Screen.kt:83–85,153–196`; I `I/Features/Account/AccountMoreOnAO3View.swift:19–25,82–84,97–116,149–184,205–252,259–280,308`). The helper actually used is `AccountNavCardLabel` (`I/Features/Account/AccountExternalNavCard.swift:83–87`), whose body has no authored accessibility hint (`I/Features/Account/AccountComponents.swift:390–430`), matching Android's title-only `SubjectFormRow` (`A/account/AccountMoreOnAO3Screen.kt:103–110`). The unrelated shortcut tile's “Opens in Account” hint is not used here and is not an omission on this pair.

### Pair 11 — Work Detail forms

**No additional gap found beyond P11-01/P11-02.** Bookmark notes/tags/privacy/recommendation match A `A/works/detail/WorkDetailForms.kt:133–152` and I `I/Features/WorkDetail/AO3WorkActionsModel.swift:200–240`. All preservation prompt sentences match A `A/library/SeriesPreservation.kt:48–60`, `A/works/detail/WorkDetailForms.kt:176,180,181` against I `I/Services/ReadingQueueService.swift:62–74`, `I/Features/WorkDetail/WorkDetailView.swift:1208,1216`. Queue progress, stopped/empty/already-added messages agree (A `A/library/SeriesPreservation.kt:75–79`; I `I/Features/Library/ReadingQueues.swift:685–693`). Summary fragments “[N] added/preserved”, “[N] already preserved”, “[N] unavailable”, “[N] failed”, “[N] skipped” agree (A `A/library/SeriesPreservation.kt:19–23`; I `I/Services/ReadingQueueService.swift:33–37`). Work Detail's “Preserving series…” / “Preserving series [N] of [N]…”, cancellation and completion messages agree (A `A/library/SeriesPreservation.kt:65–71`, `A/works/WorkDetailScreen.kt:1088`; I `I/Features/WorkDetail/WorkDetailView.swift:1021–1039`).

### Platform formatting and speech limits

**Not applicable — OS/locale rendering:** date-picker UI (X1/X9), number/date formatting (e.g. A newest-work words uses `A/home/HomeFacts.kt:181–190`; I Foundation compact-number formatting at `I/Features/Library/FavoriteAffinityRow.swift:245`), and OS-generated role/state/gesture announcements. These do not license changing app-authored labels. Dynamic date/number output can vary with locale, so the metadata row P9-04 establishes the same word templates rather than promising byte-identical locale formatting. Text marked “spoken only” above is taken from explicit accessibility properties; no TalkBack/VoiceOver runtime test was run.

## Local verification

- Enumerated the W2 tables before the repeated concluding lists: 21 differs, 31 missing, 16 Android only; every row has an entry here with both-side evidence.
- Opened current source and followed helpers for markers, field labels, loaders, date controls, menus, accessibility grouping, dynamic messages and write verdicts. Checked decision dates/titles locally. Did not treat unused error declarations as displayed text.
- Checked that every numbered A/I source path exists and every cited starting line is in range; checked report coverage and arithmetic with a local Python script. Source-only verification cannot determine the OS's full spoken utterance or on-screen clipping.
- No source edits, commits, Gradle, builds, sign-in, website access or network tools. Only `docs/android-port/audits/A78-result.md` was created/updated by this audit. The existing untracked brief remains untouched.

## Remaining “still differs” items, reader-visible first

Exact wording, conditions and both-side evidence are in the IDs above. This orders ordinary visible content before loading/error states, then spoken-only differences; it is not a severity ranking. Repeated surfaces are explicitly named.

| Order | Remaining item | IDs | Kind / surface findings |
|---|---|---|---|
| 1 | History lacks reading duration, “Read ×N”, and “N new chapter(s)” below each work. | O8-01–03 | Visible / 3 |
| 2 | Favorites Works also lacks duration and “Read ×N”. | O9-01–02 | Visible / 2 |
| 3 | History's More menu says “Display · Ledger/Detailed” rather than “Layout” with separate option names; Favorites Works also lacks “Compact”. | O8-04, O9-03 | Visible / 2 |
| 4 | “Collapse All” / “Expand All” omit iOS's “Cards”, in both lists' Detailed mode. | O8-05, O9-04 | Visible / 2 |
| 5 | “Hide mature works” / “Show mature works” add “works” to iOS's menu wording. | O8-06, O9-05 | Visible / 2 |
| 6 | Series removal shows “Remove”; iOS uses a minus icon with no visible word. Spoken title-specific labels match. | P4-03 | Visible / 1 |
| 7 | Preserve Series lacks the toolbar “Cancel”; Android offers “Only This Work” and dismiss/back. | P11-01 | Visible / 1 |
| 8 | Reorder's loading/error header says “Reorder” instead of “Reorder series”. | O4-01 | Visible / 1 |
| 9 | Series has extra “Loading…” / “Saving…” captions on Android. | X12 | Visible / 1 grouped W2 row |
| 10 | Unavailable-authentication error on the chapter list says “Your AO3 session expired. Please log in again.” rather than “Log in to AO3 before using this feature.” | O3-01 | Visible / 1 edge state |
| 11 | Favorite newest-work link says “Open this work” rather than naming the work. | P9-03 | Spoken only / 1 |
| 12 | Favorite card's combined description omits iOS's newest-work title/metadata/“Unread.” sentences and retains the library line. | P9-05 | Spoken only / 1 |
| 13 | Queue member checkmark lacks “In this queue”. | P11-02 | Spoken only / 1 |
| 14 | Warning/category facet states say “Include” / “Exclude” / “Clear” instead of “Included” / “Excluded” / no status word. | O7-01 | Spoken only / 1 grouped finding |
| 15 | Word-count range lacks the parent's “lower to upper” value; Android names the two bounds separately. | O7-02 | Spoken only / 1 |
| 16 | Author sort button lacks “Sort and filter the works on this page” help and the “active” suffix on its count. | O7-03–04 | Spoken only / 2 |
| 17 | History and Favorites Works filter buttons lack “Filter the works in this section” help. | O8-07, O9-06 | Spoken only / 2 |
| 18 | Android adds “History grouping” to its grouping strip. | X14 | Spoken only / 1 extra description |
| 19 | Android adds “Favorites scope” / “Favorites order” group descriptions at ordinary text sizes. | X15 | Spoken only / 1 grouped W2 row |

### Counts

Counts are **source rows / surface findings**, not individual literal alternatives or repeated instances. “Loading…” / “Saving…” remain W2's one grouped row; each new row above represents one control/fact on one requested pair. The same shared difference on History and Favorites is counted once per affected pair, and is cross-referenced rather than hidden in a deduplicated total.

| Set | same now | still differs | not applicable | W2 was wrong | Total |
|---|---:|---:|---:|---:|---:|
| W2 rows explicitly “differs” or “missing on Android” | 34 | 5 | 0 | 13 | 52 |
| W2 “Android only” rows, separately re-checked | 5 | 3 | 6 | 2 | 16 |
| New omissions from the eleven-pair source sweep | — | 19 | — | — | 19 |

**Still differs: 27 surface findings: 16 visible, 11 spoken only.** Five survive the original W2 difference/missing claims; three are its reverse-only rows; nineteen are new omissions. Six pairs have no newly found omission (1, 2, 5, 6, 10, 11); five have new omissions (3, 4, 7, 8, 9). These are wording/content findings, not 27 independently proposed code changes.


## Triage (Claude, 2026-10-22 05:20)

W2 was wrong on 15 of its rows. The 27 surface findings that remain are wording and content
gaps against iOS; all go to brief 3gp, the visible ones first (History and Favorites missing the
reading time, "Read ×N" and new-chapter line is the one a reader notices most). Android-only
spoken group names (X14, X15) are checked there against iOS's own accessibility before removal.
