# Priority list — A64 actions audit

1. **F04 · Different · high:** keep bulk Save’s operation/result alive when Cancel or Back dismisses its screen: Android cancels the per-work loop after some writes may have landed and drops the opener’s completion/refresh; iOS’s unstructured save task continues (`I Writing/EditMultipleWorksView.swift:147,367`; `A writing/WritingBulkEditScreen.kt:36,41,73,76`, `writing/WritingBulkEditState.kt:45,46,56`, `network/ao3/writes/AO3WriteRepository.kt:171,417`).
2. **F02 · Different · medium:** make sign-up pull-to-refresh apply the newly read form (with explicit handling of unsaved edits): iOS replaces it; Android always keeps the existing form, so even a clean screen never reflects changes made on AO3 (`I Challenges/ChallengeSignUpView.swift:626,634,641`; `A account/AO3ChallengeSignUpScreen.kt:96`, `account/AO3ChallengeSignUpState.kt:50`).
3. **F03 · Missing in error state · low:** allow explicit Try Again after a sign-up form parse/validation read failure: iOS offers retry; Android makes these failures terminal and disables the retry (`I Challenges/ChallengeSignUpView.swift:604,626`; `A account/AO3ChallengeSignUpScreen.kt:127`, `account/AO3ChallengeSignUpState.kt:37,51`). Keep the recorded refusal/session safeguards.
4. **F01 · Different · low:** restore tag-picker content order: iOS offers “Recently used” before “From your other works”; Android reverses them (`I Writing/WritingTagsEditor.swift:119,125`; `A writing/WritingTagsEditorScreen.kt:111`).

# Scope and method

Dispatch override: this report is `A64-actions-result.md`; Claude’s `A64-result.md` is untouched. Android baseline: `android/agent-codex-a64b`, `ed560f2d845c9f75af910f9b547b14f5289f8e99`, initially clean. iOS checkout revision: `83626d46bf4a52074039f108a446fcee76107f2f`. Static source audit only: no build, runtime UI verification, sign-in, or AO3 contact. No task-board edits or git mutations.

Paths below use **I** = `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/`, **A** = `android/app/src/main/java/io/github/cidy02/kudos/`. Each quoted reference is relative to that root. Line references identify the action and its handler; missing actions cite the compared Android surface, not a claimed implementation. Android navigation/chrome differences alone are not findings. “same” means the inspected action and its outcome agree; it does not assert live AO3 verification.

DECISIONS.md entries from 2026-10-10 onward were reviewed. Recorded differences (including preserving unmodeled AO3 controls, conservative challenge totals, post-write refresh, and checkpoint recovery limits) are separated from actionable regressions.

## WritingDraftsView / Writing destinations

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “New Work” `Writing/WritingDraftsView.swift:121` | “New Work”, `account/WritingDraftsScreen.kt:108` | **same** — opens native new-work form. |
| Tap draft → `WritingWorkDestination(workID:)`, `Writing/WritingDraftsView.swift:88` | `WritingWorkDestination.route(work.id)`, `account/WritingDraftsScreen.kt:185` | **same** — edits the tapped draft; no list-level Post/Delete on either. |
| “Try Again”, `Writing/WritingDraftsView.swift:63`; pull refresh `:130` | “Try Again” `account/WritingDraftsScreen.kt:175`; `KudosRefreshBox` `:129` | **same** — reload current page. Empty state has no additional action on either (`I :72`, `A :182`). |
| `SearchPaginationBar`, `Writing/WritingDraftsView.swift:100` | `KudosPaginationBar`, `account/WritingDraftsScreen.kt:192` | **same** — shared page navigation, including exact page selection. |
| Form/tag/bulk/chapter loader “Try Again”, `Writing/WritingDraftsView.swift:349,409,460,505,555` | `model.load(retry = true)`, `writing/WritingWorkFormScreen.kt:230`, `writing/WritingEditTagsScreen.kt:102`, `writing/WritingBulkEditScreen.kt:92`, `writing/WritingChapterFormScreen.kt:93` | **same** — retry the requested form, preserve already-open forms across child-editor round trips. |

## WorkEditView (new work, draft, posted work)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “Title”, “Rating”, “Archive warnings”, “Fandoms”, “Language”, `Writing/WorkEditView.swift:266` | Same five controls, `writing/WritingWorkFormScreen.kt:240` | **same** — typed title, single choices, warning/fandom pickers; required fields retained. |
| “Categories”, “Relationships”, “Characters”, “Additional tags”, `Writing/WorkEditView.swift:285` | Same four rows, `writing/WritingWorkFormScreen.kt:261` | **same** — edits the corresponding tag field, not the prose. Nested pickers audited below. |
| “Series”, “Add to collections”, “Gift recipients”, “Co-creators”, “Inspired by”, `Writing/WorkEditView.swift:306,314,319,328,333` | Same destinations, `writing/WritingWorkFormScreen.kt:278,281,284,287,290` | **same** — collections and gifts intentionally share one screen on both. |
| “Summary”, “Beginning notes”, “End notes”, conditional “Work text”, “Work skin”, `Writing/WorkEditView.swift:424,428,430,433,472` | `WorkFormTextRow`, conditional content, skin, `writing/WritingWorkFormScreen.kt:297,299,301,304,320` | **same** — no empty work-text editor for a multi-chapter draft whose AO3 form omitted the textarea. |
| Posted “Chapters”, “Add chapter”, “Edit tags”, `Writing/WorkEditView.swift:446,453,464` | Same three rows, `writing/WritingWorkFormScreen.kt:310,313,316` | **same** — posted-only. Saved child changes refresh only corresponding parent fields, preserving unsaved metadata (`I :164,183`; `writing/WritingWorkFormState.kt:183,230`). |
| “Reload chapter totals”, `Writing/WorkEditView.swift:125` | Same, `writing/WritingWorkFormScreen.kt:325` | **same** — failed child refresh blocks Save until reload succeeds. |
| Chapter total; “Work is complete”, `Writing/WorkEditView.swift:650,663` | Same, `writing/WritingWorkFormScreen.kt:332,348` | **same** — complete sets total to posted count; off clears total. |
| “Set a different publication date” and date picker, `Writing/WorkEditView.swift:493,500` | Same, `writing/WritingWorkFormScreen.kt:353,356,411` | **same** — enables date, defaults empty date to today, edits chapter date. |
| “Only show to registered users”, “Enable comment moderation”, “Who can comment”, `Writing/WorkEditView.swift:511,516,521` | Same, `writing/WritingWorkFormScreen.kt:361,363,365` | **same** — changes those publication settings. |
| Toolbar “Save”, `Writing/WorkEditView.swift:204,567` | “Save”, `writing/WritingWorkFormScreen.kt:183`; `writing/WritingWorkFormState.kt:70` | **same** — draft save or posted update; confirmed success closes and notifies opener; failure “AO3 could not save the change” + OK (`I :210`; `A screen :191`). No undo on either. |
| “Post work” → “Post this work?” / “Post work”, “Cancel” or “Fill in what is missing”, `Writing/WorkEditView.swift:218,716,771` | Same, `writing/WritingWorkFormScreen.kt:192,374`; `writing/WritingWorkFormState.kt:475` | **same** — warns subscribers are notified and cannot return to draft; missing requirements do not dispatch. Success closes; no undo. |
| “Preview on AO3”, `Writing/WorkEditView.swift:591,720` | Same, `writing/WritingWorkFormScreen.kt:377`; `writing/WritingWorkFormState.kt:78` | **same** — AO3 preview; adopts new draft ID before future Post/Save, avoiding duplicate work. |
| “Delete draft” / “Delete work on AO3”, `Writing/WorkEditView.swift:723,531,791` → caution and Cancel/Delete `:228` | Same, `writing/WritingWorkFormScreen.kt:383,392,200`; `writing/WritingWorkFormState.kt:82,89` | **same** — reads implications first, shows caution, dispatches only confirmed delete; closes on success, error retains form. No undo. |
| No manual tag-refresh row (only automatic refresh/error), `Writing/WorkEditView.swift:183` | “Reload tags”, `writing/WritingWorkFormScreen.kt:255` | **Android only**, useful: explicit retry after failed tag reload. Android is right to keep Save blocked and offer recovery. |

## WritingChaptersView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Tap named chapter → editor with its ID/count, `Writing/WritingChaptersView.swift:61` | `openChapter(chapter, rows.size)`, `writing/WritingChaptersScreen.kt:82,85` | **same** — opens that chapter; refreshes list and parent after confirmed child save. |
| “Try Again”, `Writing/WritingChaptersView.swift:40` | “Try Again”, `writing/WritingChaptersScreen.kt:95` | **same** — retry list. Neither has list-level delete, reorder, swipe, or refresh action. |

## AddChapterView (new and existing chapters)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “Title”, “Expected chapter total” / “Chapter number”, “Position” after chapter, `Writing/AddChapterView.swift:151,158,176` | Same, `writing/WritingChapterFormScreen.kt:102,106,114`; conversion `writing/WritingChapterFormState.kt:81,82,83,206` | **same** — position is after-chapter + 1; total remains writer-editable. |
| “Chapter text”, “Summary”, “Beginning notes”, “End notes”, `Writing/AddChapterView.swift:224,236,238,240` | Same field entries, `writing/WritingChapterFormScreen.kt:123`; `writing/WritingChapterFormState.kt:17` | **same** — individual text editor; empty Chapter text explains the editor. Preview/Delete menu lives in chapter-text editor, audited below. |
| Date enable/picker; “Post without preview”; “This is the last chapter”, `Writing/AddChapterView.swift:264,275,284,289` | Same, `writing/WritingChapterFormScreen.kt:138,142,147,150` | **same** — date can clear; last-chapter causes separate work-total update. “Custom publication date” versus row label is spoken wording only, already dismissed in Claude’s earlier pass. |
| “Post chapter now” / “Save chapter changes”, `Writing/AddChapterView.swift:304` | Same, `writing/WritingChapterFormScreen.kt:163` | **same** — new/draft defaults to preview; without-preview posts directly; existing posted chapter updates. iOS asks no extra posting confirmation here, Android correctly does not add one. |
| “Save as draft”, `Writing/AddChapterView.swift:329` | Same, `writing/WritingChapterFormScreen.kt:172` | **same** — new/draft only, no posted-to-draft action. |
| “Retry updating the work total”, `Writing/AddChapterView.swift:299,373` | Same, `writing/WritingChapterFormScreen.kt:156`; `writing/WritingChapterFormState.kt:107,118` | **same** — after partial success retries total only, never reposts chapter; message says chapter saved. No undo. |
| Failure OK, `Writing/AddChapterView.swift:127` | `WritingErrorAlert("AO3 could not save the chapter")`, `writing/WritingChapterFormScreen.kt:76` | **same** — keeps form, distinguishes partial save; success closes and refreshes opener. |

## WritingPreviewView (AO3 preview)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “Post work” / “Post chapter” / “Update”, `Writing/WritingPreviewView.swift:48` | `WritingPostRow(postTitle)`, `writing/WritingAO3PreviewScreen.kt:74` | **same** — calls owning form’s one save path; work Post retains “Post this work?” + Cancel; chapter/update no extra confirm. Success closes form; no undo. |
| “Edit”, `Writing/WritingPreviewView.swift:53` | “Edit”, `writing/WritingAO3PreviewScreen.kt:79` | **same** — back to form, retains edits. |
| “AO3 could not post this” → OK, `Writing/WritingPreviewView.swift:67` | Same alert, `writing/WritingAO3PreviewScreen.kt:48` | **same** — preview stays available after failure. |

## WritingTextEditor / WritingNativeTextView (shared prose editor)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Type, select, cut/copy/paste using native text view, `Writing/WritingNativeTextView.swift:135,161,170` | Native Editable operations, `writing/WritingNativeTextField.kt:88,100,108` | **same** at source level — preserves HTML string, native selection and IME; device keyboard behavior untested. |
| “Preview” / “Edit”, `Writing/WritingTextEditor.swift:121,229` | Same toggle, `writing/WritingTextEditorScreen.kt:121`; `writing/WritingEditorSession.kt:134` | **same** — local preview, no AO3 write; retains underlying editor/selection, disables formatting and undo/redo during preview. Render failure says text unchanged and offers return via Edit. |
| “Undo”, “Redo”, `Writing/WritingTextEditor.swift:127,129` | Same, `writing/WritingTextEditorScreen.kt:124,125` | **same** — native undo/redo. |
| Every tag-bar formatting action, `AO3MarkupTag.writing`, `Writing/WritingTextEditor.swift:258,338` | `WritingMarkup.tags`, `writing/WritingTextEditorScreen.kt:189`; `writing/WritingMarkup.kt:13` | **same dispatch; unsure exact generated catalog** — each tag button inserts its element around the selection; Link opens URL entry. Android lists Bold, Italic, Underline, Strike, Superscript, Subscript, Small, Code, Paragraph, Line break, Quote, Bullets, Numbers, Heading, Divider, Link, Spoiler (`comments/CommentMarkup.kt:75,85`; `writing/WritingMarkup.kt:15`). iOS generates from `AO3MarkupTag.writing`, whose definition is outside the two scoped folders; exact catalog/markup payload equivalence is not claimed. Mac-only Format repeats that generated set (`I :283`). |
| Link → URL, “Insert”, “Cancel”; invalid URL → “Editor error”/OK, `Writing/WritingTextEditor.swift:167` | Same, `writing/WritingTextEditorScreen.kt:224,217` | **same** — HTTP/HTTPS/mailto validation before insertion; escaping in markup helper. |
| More → “Paste as plain text” (also keyboard shortcut), `Writing/WritingTextEditor.swift:187` | Same menu/native paste, `writing/WritingTextEditorScreen.kt:129`; `writing/WritingNativeTextField.kt:110` | **same** — native plain-text paste, undoable. |
| Chapter More → “Preview on AO3”, `Writing/WritingTextEditor.swift:190` | Same, `writing/WritingTextEditorScreen.kt:132` | **same** — checkpoints into parent then invokes chapter preview. |
| Chapter More → “Delete chapter” → named “Delete …?” / “Delete on AO3” / Cancel, `Writing/WritingTextEditor.swift:194,138` | Same, `writing/WritingTextEditorScreen.kt:134,206` | **same** — only existing chapter with count >1; warns all chapter comments are deleted and cannot be undone. Parent save error handles failure; confirmed success closes chapter. No undo. |
| “Done” and Back/departure checkpoint, `Writing/WritingTextEditor.swift:134,298,465` | “Done” `writing/WritingTextEditorScreen.kt:140`, Back `:116`, dispose `:160`; `writing/WritingEditorSession.kt:149,157` | **same** — commits composition and current text to form; queued recovery writes survive disposal. No implicit AO3 save. |
| Recovery “Local copy” selection and selectable copy text, `Writing/WritingTextEditor.swift:348,360` | Dated selectors and SelectionContainer, `writing/WritingTextEditorScreen.kt:256,269` | **same** — choose/review per-account, per-target, per-field recovery copy. |
| “Restore local copy”, `Writing/WritingTextEditor.swift:361`; undoable `Writing/WritingNativeTextView.swift:190` | Same, `writing/WritingTextEditorScreen.kt:276`; `writing/WritingEditorSession.kt:111`; undoable `writing/WritingNativeTextField.kt:101` | **same** — replaces editor text, immediate checkpoint, native Undo can restore prior text. |
| “Keep form text”; “Delete this local copy”, `Writing/WritingTextEditor.swift:368,369` | Same, `writing/WritingTextEditorScreen.kt:277,278`; `writing/WritingEditorSession.kt:118,120` | **same** — first dismisses recovery without deleting disk copies; second deletes selected copy without extra confirmation or undo on either. Sheet cannot be interactively dismissed on either. |
| Read/write recovery error → “Editor error”/OK, `Writing/WritingTextEditor.swift:162,424,458` | Same, `writing/WritingTextEditorScreen.kt:217`; `writing/WritingEditorSession.kt:71,85` | **same** — failure is visible. Recorded checkpoint-only recovery limit (DECISIONS.md:1762) is not a new finding. |

## WritingTagsEditor / WritingFormFields (shared tag and choice screens)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “Add a tag” submit; Clear; typed-name “Posts as typed”; canonical suggestion Add, `Writing/WritingTagsEditor.swift:162,168,309,329,456` | Same, `writing/WritingTagsEditorScreen.kt:132,136,170,174`; `writing/WritingTagsEditorState.kt:121` | **same** — adds chosen literal or canonical name, avoids duplicates, clears accepted input; suggestions failure still allows typed names. No AO3 write until parent Save. |
| Chosen chip “Remove …”, `Writing/WritingTagsEditor.swift:215` | Same, `writing/WritingTagsEditorScreen.kt:265` | **same** — removes only that selection; no confirm or undo on either (re-add available). |
| Drag reorder; “Move Earlier” / “Move Later”, `Writing/WritingTagsEditor.swift:199,209,212` | Long-press drag; same accessibility actions, `writing/WritingTagsEditorScreen.kt:246,260` | **same** — updates posted tag order. |
| Tap “Recently used” or “From your other works” chip, `Writing/WritingTagsEditor.swift:119,125,243` | Same two chip sources/add handler, `writing/WritingTagsEditorScreen.kt:111,159` | **different · F01** — actions themselves correct, but Android reverses the two groups. Owner requires content order parity. |
| Warning/category option toggle, `Writing/WritingTagsEditor.swift:400,416` | `WorkFormTagChoices`, `writing/WritingWorkFormScreen.kt:175`; `writing/WritingWorkFormState.kt:341` | **same** — append on/select, remove off; multiple warnings remain possible. |
| Single-choice option, `Writing/WritingFormFields.swift:23` | `WorkFormChoiceSheet`, `writing/WritingWorkFormScreen.kt:403,409` | **same** — sets one value, returns to form. |

## EditTagsView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Rating single choice; warnings multi-choice; categories toggles, `Writing/EditTagsView.swift:150,163,195` | Same, `writing/WritingEditTagsScreen.kt:118,129,140` | **same** — repeated rating stays selected; warnings do not clear one another. |
| Fandoms, Relationships, Characters, Additional tags inline Remove/Add, `Writing/EditTagsView.swift:218`; `Writing/WritingFormFields.swift:98,112` | Same, `writing/WritingEditTagsScreen.kt:153,170,178` | **same** — opens matching tag picker/add or removes named chip. |
| Save; failure OK, `Writing/EditTagsView.swift:131,267,124` | Save/OK, `writing/WritingEditTagsScreen.kt:62,70`; `writing/WritingWorkFormState.kt:70,105` | **same** — tags-only write, prose untouched; success closes/notifies opener, failure keeps edits. No confirmation or undo on either. |

## WorkCollectionsGiftsView (WorkAssociationPickers.swift)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Search collections by name, `Writing/WorkAssociationPickers.swift:131` | Same, `writing/WritingAssociationPickers.kt:135` | **same** — on-demand search; no matches explains state. |
| Add search result to offered list, then select/deselect collection, `Writing/WorkAssociationPickers.swift:163,192` | Same, `writing/WritingAssociationPickers.kt:149`; `writing/WritingWorkFormState.kt:302,305` | **same** — found collection is added **unticked**, not silently submitted; explicit next tap selects. State (open/closed/moderated) shown before selection. |
| Gift username/pseud entry, keyboard submit or Add; Remove recipient, `Writing/WorkAssociationPickers.swift:237,246,253` | Same, `writing/WritingAssociationPickers.kt:161,163,176`; `writing/WritingWorkFormState.kt:309,320` | **same** — trims, prevents duplicate recipients, edits parent form. Gift-email/no-take-back caution on both; no separate confirm/undo on either. |

## WorkSeriesPickerView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Select/deselect one series, `Writing/WorkAssociationPickers.swift:445` | Same, `writing/WritingAssociationPickers.kt:100`; `writing/WritingWorkFormState.kt:293` | **same** — current memberships cannot be removed here; selected addition clears new title. |
| “Create a series from this work” title, `Writing/WorkAssociationPickers.swift:405` | Same, `writing/WritingAssociationPickers.kt:122`; `writing/WritingWorkFormState.kt:300` | **same** — nonblank title unpicks existing addition; parent Save creates it. |
| “Reorder the series”, `Writing/WorkAssociationPickers.swift:387`; loader `Writing/SeriesReorderDestination.swift:23` | Same, `writing/WritingAssociationPickers.kt:112`; `writing/WritingSeriesScreen.kt:35` | **same** — independent order screen/write, no silent order save from work form. Empty series state has no extra action on either. |

## WorkCreatorsPickerView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Pseud toggles, `Writing/WorkAssociationPickers.swift:578` | Same, `writing/WritingAssociationPickers.kt:196`; `writing/WritingWorkFormState.kt:321` | **same** — at least one selected pseud retained; no offered-pseuds empty-state action. |
| Co-creator byline, `Writing/WorkAssociationPickers.swift:590` | Same, `writing/WritingAssociationPickers.kt:202` | **same** — edits byline, parent Save sends invitation; no implicit send in picker. |

## WorkParentWorkPickerView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| URL, optional title, optional author, `Writing/WorkAssociationPickers.swift:681,693,698` | Same, `writing/WritingAssociationPickers.kt:212,215,217` | **same** — edits source-work association fields. |
| Translation toggle; language of source, `Writing/WorkAssociationPickers.swift:708,713` | Same, `writing/WritingAssociationPickers.kt:225,227` | **same** — retained in parent form, written only on Save. |

## EditMultipleWorksView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Add and Remove groups, each Fandoms / Relationships / Characters / Additional tags, `Writing/EditMultipleWorksView.swift:86,89,191` | Same, `writing/WritingBulkEditScreen.kt:102,104,155` | **same** — eight distinct picker destinations, additive/removal deltas on selected works. |
| Change-on-all Rating / Language with “Leave as is”, `Writing/EditMultipleWorksView.swift:215,235` | Same, `writing/WritingBulkEditScreen.kt:110,184` | **same** — only changed scalars replace all selected values. |
| Archive warnings / Categories tri-state, `Writing/EditMultipleWorksView.swift:221,228` | Same, `writing/WritingBulkEditScreen.kt:110,188,199` | **same** — cycle unchanged → add → remove → unchanged. |
| Add to collections; Remove from collections, `Writing/EditMultipleWorksView.swift:245,262` | Same, `writing/WritingBulkEditScreen.kt:123,126` | **same** — remove picker disabled when no current options; gifts “Per work” disabled on both. |
| Registered-only, moderation, comment permission with “Leave as is”, `Writing/EditMultipleWorksView.swift:290,296,302` | Same, `writing/WritingBulkEditScreen.kt:132,223` | **same** — on/off/untouched preserved, no accidental privacy reset when left alone. |
| Add co-creators; Remove me as co-creator, `Writing/EditMultipleWorksView.swift:317,331` | Same, `writing/WritingBulkEditScreen.kt:140,147` | **same** — changes only requested creator controls. |
| Save / Cancel; failure OK, `Writing/EditMultipleWorksView.swift:141,147,134` | Same, `writing/WritingBulkEditScreen.kt:73,76,80` | **same when kept open through completion** — Save applies chosen deltas, confirmed success closes and refreshes opener; Cancel before Save dismisses. No extra confirmation or undo on either. Departure during Save differs below. |
| Save, then Cancel/Back while request is running: Cancel stays enabled; `Task` continues and calls `onSaved()`, `Writing/EditMultipleWorksView.swift:147,367,372` | Save launched in `rememberCoroutineScope`, Cancel/Back drops `bulkModel`; disposal closes state, `writing/WritingBulkEditScreen.kt:36,41,69,73,76`; `author/AuthorProfileScreen.kt:407,408`; `writing/WritingBulkEditState.kt:40,46,56` | **different · F04** — confirmed by source lifecycle: removing this composable cancels its coroutine, and `active = false` also suppresses completion. The repository writes tags sequentially per selected work (`network/ao3/writes/AO3WriteRepository.kt:171,175`); an already dispatched POST is NonCancellable (`:417`) while subsequent work reads/dispatches remain cancellable (`:416`). Leaving after one POST can therefore leave only part of the requested bulk change on AO3, with no visible verdict and no opener refresh. iOS keeps running its task after dismissal. Retain the operation in an owner that survives departure, or prevent departure while saving and preserve/report partial results. No runtime write was attempted. |

## BulkTagStatePicker

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Tap option to cycle state, `Writing/BulkTagStatePicker.swift:44,75` | `BulkOptionsScreen` tri rows, `writing/WritingBulkEditScreen.kt:188,199` | **same** — three states and matching explanatory text; no write before parent Save. |

## BulkNameListEditor (inside BulkTagStatePicker.swift)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Type collection name and Add; remove an added name, `Writing/BulkTagStatePicker.swift:148,158,165` | Same Add and remove rows, `writing/WritingBulkEditScreen.kt:197,210,213` | **same** for touch actions — exact-name list, duplicate guard, only parent Save writes. |
| Keyboard submit adds name, `Writing/BulkTagStatePicker.swift:164` | `SubjectTextFieldRow` without `onSubmit`, `writing/WritingBulkEditScreen.kt:210` | **different**, minor keyboard convenience; Add touch equivalent exists. No lost capability; outside priority fixes. |

## SeriesEditView / SeriesEditDestination

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Title; Creators byline; Series summary; Series notes, `Writing/SeriesEditView.swift:163,167,175,181` | Same, `writing/WritingSeriesScreen.kt:174,180,189` | **same** — prose opens same recovery-enabled editor; title required. |
| “Series is complete”, `Writing/SeriesEditView.swift:186` | Same, `writing/WritingSeriesScreen.kt:203` | **same** — does not prevent adding works later. |
| “Reorder works”; “Remove works”, `Writing/SeriesEditView.swift:194,208` | Same, `writing/WritingSeriesScreen.kt:210,214` | **same** — order disabled below two works; remove screen remains reachable. |
| “Delete series on AO3”, `Writing/SeriesEditView.swift:221` | Same, `writing/WritingSeriesScreen.kt:222` | **same** — opens series web page; no native deletion/confirmation on either. |
| Save; inline answer scrolled into view, `Writing/SeriesEditView.swift:149,251,136` | Same, `writing/WritingSeriesScreen.kt:93,85`; `writing/WritingSeriesState.kt:136` | **same** — stays open, shows AO3 notice or error. No undo/confirmation. |
| Loader Try Again, `Writing/SeriesEditView.swift:615` | Same, `writing/WritingSeriesScreen.kt:117,254` | **same** — retries required form. |

## SeriesReorderView / SeriesReorderDestination

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Drag numbered work, `Writing/SeriesEditView.swift:346` | Long-press drag plus Move Earlier/Later, `writing/WritingSeriesScreen.kt:136,143` | **same** — edits whole ordered list locally; Android accessibility alternatives are useful. |
| Save whole order; error retains screen, `Writing/SeriesEditView.swift:378,412` | Same, `writing/WritingSeriesScreen.kt:93`; `writing/WritingSeriesState.kt:126` | **same** — single verified order save; success returns to form and updates its list; no undo. |

## SeriesRemoveWorksView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Remove named work → named confirmation / “Remove from series” / Cancel, `Writing/SeriesEditView.swift:540,516` | Same, `writing/WritingSeriesScreen.kt:156,234` | **same** — explains work stays posted; no last-work removal; no undo. |
| Confirm removal and read verified rows, `Writing/SeriesEditView.swift:556` | Same, `writing/WritingSeriesState.kt:150` | **same** — correct serial-work ID, preserves metadata; unconfirmed response does not falsely say nothing was removed. |

## CollectionModerationView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| “Approve”, `Challenges/CollectionModerationView.swift:332` | “Approve”, `account/AO3CollectionModerationScreen.kt:161`; `account/AO3CollectionModerationState.kt:156` | **same** — immediate single-item decision without extra confirmation; success removes row, failure retains it with error; no undo on either. |
| “Reject” → “Reject this work?” / Reject / Cancel, `Challenges/CollectionModerationView.swift:346,119` | Same, `account/AO3CollectionModerationScreen.kt:165,88`; `account/AO3CollectionModerationState.kt:41,48` | **same** — names work; explains work stays posted and creator gets no reason/email. Confirmed success removes row; no undo. |
| “Message creator”, `Challenges/CollectionModerationView.swift:360` | Same, `account/AO3CollectionModerationScreen.kt:168`; `app/AppNavHost.kt:957` | **same** for parsed work IDs — opens comments with compose requested, never invents a message to send. iOS also resolves missing ID from URL; parser coverage not assumed for malformed rows. |
| Review pagination, `Challenges/CollectionModerationView.swift:210` | `KudosPaginationBar`, `account/AO3CollectionModerationScreen.kt:176` | **same** — reloads chosen review page; after emptied page moves to same/previous valid page (`I :965`; `account/AO3CollectionModerationState.kt:180`). |
| “Recently decided”, `Challenges/CollectionModerationView.swift:227` | Same, `account/AO3CollectionModerationScreen.kt:184` | **same** — opens collection items/decisions list. |
| Membership “Accept”, `Challenges/CollectionModerationView.swift:503` | Same, `account/AO3CollectionModerationScreen.kt:204`; `account/AO3CollectionModerationState.kt:159` | **same** — immediate accept; success removes request, failure keeps it. No confirmation/undo. |
| “Decline” → named Decline / Cancel, `Challenges/CollectionModerationView.swift:517,132` | Same, `account/AO3CollectionModerationScreen.kt:208,88`; `account/AO3CollectionModerationState.kt:42,49` | **same** — explains participant must apply again; no undo. |
| “Owners and moderators”, “Invite a maintainer”, `Challenges/CollectionModerationView.swift:557,568` | Same, `account/AO3CollectionModerationScreen.kt:223,227` | **same** — both open one maintainer screen. |
| “Reveal now” → “Reveal this collection?” / Reveal / Cancel, `Challenges/CollectionModerationView.swift:622,147` | Same, `account/AO3CollectionModerationScreen.kt:244,88`; `account/AO3CollectionModerationState.kt:43,50` | **same** — owner-only while unrevealed; warns visibility and no undo in Kudos; reload after success, error shown on failure. |
| “Remove anonymity” → Remove Anonymity / Cancel, `Challenges/CollectionModerationView.swift:655,156` | Same, `account/AO3CollectionModerationScreen.kt:251,88`; `account/AO3CollectionModerationState.kt:44,51` | **same** — owner-only while anonymous; irreversible warning preserved. |
| Pull refresh; Try Again; Dismiss error, `Challenges/CollectionModerationView.swift:116,719,740` | Same, `account/AO3CollectionModerationScreen.kt:98,126,136` | **same** — retries/reloads or clears visible action error. Empty queues have no extra action on either. |

## CollectionMaintainersView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Invite username; Invite as Moderator / Owner, `Challenges/CollectionMaintainersView.swift:304,316` | Same, `account/AO3CollectionMaintainersScreen.kt:133,138` | **same UI and same limitation** — selected role is not passed by either send handler (`I :487`; `account/AO3CollectionMaintainersState.kt:81`). This is not an Android-only parity defect; neither actually appoints an Owner through this selection. |
| “Send invitation to …”, `Challenges/CollectionMaintainersView.swift:331,480` | Same, `account/AO3CollectionMaintainersScreen.kt:149`; `account/AO3CollectionMaintainersState.kt:76` | **same** — explicit send, no additional confirmation; “Invitation sent to …”, clears username, refreshes roster. Error leaves input. No undo. |
| “Step down as owner” / “Leave collection”, `Challenges/CollectionMaintainersView.swift:381,497` | Same, `account/AO3CollectionMaintainersScreen.kt:175`; `account/AO3CollectionMaintainersState.kt:94` | **same** — last owner gets “Cannot Step Down” + OK, otherwise named privilege-loss confirmation with Step Down/Leave and Cancel (`I :102,107`; `A screen :192`). |
| Confirm leave, `Challenges/CollectionMaintainersView.swift:505` | `confirmLeave`, `account/AO3CollectionMaintainersState.kt:104` | **same** — acts on current participant ID, success closes/notifies list, failure shown; no undo. Android rechecks last owner before dispatch, which is right. |
| Pull refresh; Try Again, `Challenges/CollectionMaintainersView.swift:101,444` | Same, `account/AO3CollectionMaintainersScreen.kt:80,107` | **same** — rereads roster. Roster rows have no role-edit/remove action on either; explanatory prose does not create a missing Android action. |

## ChallengeSettingsView (read view)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Owner “Edit settings”, `Challenges/ChallengeSettingsView.swift:125` | Same, `account/AO3ChallengeSettingsScreen.kt:110` | **same** — native challenge edit form, owner gate. |
| Prompt meme “Prompts”, `Challenges/ChallengeSettingsView.swift:198` | Same, `account/AO3ChallengeSettingsScreen.kt:175` | **same** — claim/fill screen. |
| Tag-set title link, `Challenges/ChallengeSettingsView.swift:395` | Same, `account/AO3ChallengeSettingsScreen.kt:166` | **same** — named tag set, moderator context. |
| “Sign-ups”; “Assignments”; “Defaults and pinch hits”, `Challenges/ChallengeSettingsView.swift:406,421,432` | Same, `account/AO3ChallengeSettingsScreen.kt:184,188,191` | **same** destinations — last two intentionally share assignments. Android’s conservative total/summary does not walk every assignment page (recorded decision, `DECISIONS.md:1368`, earlier policy). |
| “Run matching” / Opens AO3, `Challenges/ChallengeSettingsView.swift:455` | Same, `account/AO3ChallengeSettingsScreen.kt:199` | **same** — web fallback, no native matching. |
| Pull refresh; Try Again, `Challenges/ChallengeSettingsView.swift:88,493` | Same, `account/AO3ChallengeSettingsScreen.kt:71,99` | **same** — loads requested settings. Disabled display toggles are facts, not editable actions, on both (`I :358`; `A :221`). |

## ChallengeSettingsEditView / ChallengeSettingsEditSections

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Basics Name / Tagline / Introduction / FAQ → collection editor, `Challenges/ChallengeSettingsEditSections.swift:19,33` | Same, `account/AO3ChallengeSettingsEditScreen.kt:157,160` | **same** — edits collection on its own form. |
| Sign-up instructions text editor, `Challenges/ChallengeSettingsEditView.swift:277` | Same field, `account/AO3ChallengeSettingsEditScreen.kt:164` | **same** — edits instructions, written on explicit Save. |
| Schedule date/time pickers and empty-date Set; no edit when time zone unreadable, `Challenges/ChallengeSettingsEditView.swift:299,320,332` | Date editor/Set, `account/AO3ChallengeSettingsEditScreen.kt:175,178,85,99` | **same** — wall-clock digits in AO3 zone; preserves unreadable strings. Android Done/Cancel are native picker flow; Set stages chosen date only on Done. |
| Requests required/allowed, Offers required/allowed for exchange, `Challenges/ChallengeSettingsEditView.swift:406,409,431` | Same, `account/AO3ChallengeSettingsEditScreen.kt:190,197,201` | **same** — range choices 0…20; validation errors retained. |
| URL allowed in request; Description required; Optional tags allowed, `Challenges/ChallengeSettingsEditView.swift:447,454,461` | Same, `account/AO3ChallengeSettingsEditScreen.kt:211,214` | **same** — honors AO3 field editability/locked restrictions. |
| Tag-set link, `Challenges/ChallengeSettingsEditView.swift:512` | Same, `account/AO3ChallengeSettingsEditScreen.kt:225` | **same** — edits tag set separately. |
| Requests that must match; Fandoms / Characters / Relationships / Additional tags counts, `Challenges/ChallengeSettingsEditSections.swift:65,69` | Same, `account/AO3ChallengeSettingsEditScreen.kt:235,239` | **same** — All or supported count, match-on summary reflects requirements. |
| Count optional tags for each tag type, `Challenges/ChallengeSettingsEditSections.swift:83` | Same, `account/AO3ChallengeSettingsEditScreen.kt:245,247` | **same** — independent switches. |
| Fandoms required/allowed per request, Allow any fandom, `Challenges/ChallengeSettingsEditView.swift:528,537,547` | Same, `account/AO3ChallengeSettingsEditScreen.kt:253,260,263,273` | **same** — 0…10, locking preserved. |
| Anonymous / Unrevealed until reveal, Moderated sign-ups, Closed to new sign-ups, meme anonymous prompts, `Challenges/ChallengeSettingsEditSections.swift:141,143,145,147,150` | Same, `account/AO3ChallengeSettingsEditScreen.kt:281,284,290` | **same** — collection switches and challenge prompt flag stay separate. |
| Run matching; Delete challenge → AO3, `Challenges/ChallengeSettingsEditView.swift:590,594` | Same, `account/AO3ChallengeSettingsEditScreen.kt:295,297` | **same** — web fallback, no native delete. |
| Save changes; irreversible reveal confirmation, `Challenges/ChallengeSettingsEditView.swift:604,150,775` | Same, `account/AO3ChallengeSettingsEditScreen.kt:305,67`; `account/AO3ChallengeSettingsEditState.kt:78` | **same** — “Reveal now?” / “Save and reveal” / Cancel before turning off anonymity/unrevealed. Challenge first, collection only if changed; partial errors shown, stays on form, no undo. Android preserves AO3 controls iOS does not model (recorded `DECISIONS.md:1366`), correctly avoids erasing unknown fields. |
| Pull refresh; Try Again, `Challenges/ChallengeSettingsEditView.swift:149,667` | Same, `account/AO3ChallengeSettingsEditScreen.kt:128,148` | **same** — explicit reload; no added undo/discard warning on either. |

## TagSetView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Fandoms / Characters / Relationships / Additional tags count rows → Add tags, `Challenges/TagSetView.swift:223` | Same four rows → same editor, `account/AO3TagSetScreen.kt:122` | **same** — each opens the four-field editor, not a filtered tag browser. |
| “Reject” an unreviewed nomination, `Challenges/TagSetView.swift:506,728` | Same, `account/AO3TagSetScreen.kt:215`; `account/AO3TagSetState.kt:66` | **same** — immediate reject without extra confirmation; identified by field/tag; confirmed success marks Rejected, failure names tag and retains row. No undo on either; neither offers native Approve. |
| “Associate nominations” / “Delete tag set”, `Challenges/TagSetView.swift:570,580` | Same, `account/AO3TagSetScreen.kt:184,189` | **same** standard destinations — association page and edit page web fallback. Parsed alternative association URL versus generated URL is **unsure** for unusual AO3 markup; no live page contacted. |
| Pull refresh; Try Again, `Challenges/TagSetView.swift:127,617` | Same, `account/AO3TagSetScreen.kt:74,104` | **same** — reloads public/edit/nomination data. Visible-to-everyone and nomination-open switches are disabled display facts on both (`I :193,363`; `A :116,128`). |

## TagSetView.tagEditorScreen (Add tags)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Fandom / Character / Relationship / Additional tag text lists, `Challenges/TagSetView.swift:242,248,254,260,293` | Four tagname fields, `account/AO3TagSetScreen.kt:245,247` | **same** — comma-separated lists remain distinct. |
| “Save tags”, `Challenges/TagSetView.swift:334,708` | Same, `account/AO3TagSetScreen.kt:263`; `account/AO3TagSetState.kt:47` | **same** — explicit save, no extra confirm; “Tags saved.” or visible error; stays in editor; no undo. Back preserves staged fields while screen model remains open. |

## PromptMemeView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| All / Unclaimed / Yours filters, `Challenges/PromptMemeView.swift:245,85` | Same, `account/AO3PromptMemeScreen.kt:112,74` | **same** — page-local filters, Yours includes claimed-by-you or own displayed byline. |
| “Claim”, `Challenges/PromptMemeView.swift:373,578` | Same, `account/AO3PromptMemeScreen.kt:245`; `account/AO3PromptMemeState.kt:55` | **same** — immediate single claim of tapped prompt; no confirmation on either; confirmed success rereads current page, error shown. Release is the way back. |
| “Release”, `Challenges/PromptMemeView.swift:366,590` | Same, `account/AO3PromptMemeScreen.kt:236,241`; `account/AO3PromptMemeState.kt:62` | **same** — uses that prompt’s claim ID; no confirmation or automatic retry on either; reloads after success. |
| “Fill it”, `Challenges/PromptMemeView.swift:379` | Same, `account/AO3PromptMemeScreen.kt:246,170` | **same** — opens meme page on AO3, does not fabricate/post a fill. |
| “New prompt”, `Challenges/PromptMemeView.swift:193` | Same, `account/AO3PromptMemeScreen.kt:189` | **same** — signed-in only; opens sign-up form. |
| Pagination, `Challenges/PromptMemeView.swift:272` | Same, `account/AO3PromptMemeScreen.kt:179` | **same** — chosen page, no repeated schedule fetch per page/claim. |
| Pull refresh; Try Again; Dismiss error, `Challenges/PromptMemeView.swift:115,488,509` | Same, `account/AO3PromptMemeScreen.kt:93,144,125` | **same** actions — refresh page 1, retry current page, clear error; schedule retry only for eligible owner. Android keeps old rows on a failed further page (`A :154`); preserving prior content is right. Empty filters have explanatory text, no extra action on either. |

## ChallengeSignUpView (Your sign-up / New prompt)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Each request’s Fandoms / Relationships / Characters / Additional tags → tag editor, `Challenges/ChallengeSignUpView.swift:253,262,273,284` | Same, `account/AO3ChallengeSignUpScreen.kt:137,145,148` | **same** — edits identified request; all four links deliberately open same four-field editor. |
| “Any of these is fine”, `Challenges/ChallengeSignUpView.swift:298` | Same, `account/AO3ChallengeSignUpScreen.kt:154` | **same** — sets any-relationship flag, not any-fandom or every tag type. |
| Request prompt text, `Challenges/ChallengeSignUpView.swift:334` | Same, `account/AO3ChallengeSignUpScreen.kt:167` | **same** — writer’s description, with character count; no invented text. |
| Offer row → tag editor, `Challenges/ChallengeSignUpView.swift:397` | Same, `account/AO3ChallengeSignUpScreen.kt:188` | **same** — edits that offer, not a request. |
| “Add an offer”; “Add request”, `Challenges/ChallengeSignUpView.swift:411,489` | Same, `account/AO3ChallengeSignUpScreen.kt:196,220`; `account/AO3ChallengeSignUpState.kt:66` | **same** — limits respected, local negative draft IDs, no remote write until Submit. No remove action offered by iOS, so absence is correct on Android too. |
| “Submit sign-up”, `Challenges/ChallengeSignUpView.swift:510,675` | Same, `account/AO3ChallengeSignUpScreen.kt:228`; `account/AO3ChallengeSignUpState.kt:75` | **same** — validates, explicit save, returns field/general errors in form; “Sign-up submitted successfully!” on success; stays open. No extra confirmation/undo. Android replays unmodeled served controls (recorded `DECISIONS.md`, 2026-10-08 3bl), not a finding. |
| “Withdraw sign-up” → “Withdraw this sign-up?” / Withdraw Sign-up / Cancel, `Challenges/ChallengeSignUpView.swift:458,142,699` | Same, `account/AO3ChallengeSignUpScreen.kt:207,82`; `account/AO3ChallengeSignUpState.kt:101` | **same** — explains requests/offers removed; “Sign-up withdrawn.” then closes via callback (`A :60`); failure remains visible. No undo. |
| Pull refresh replaces form from AO3, `Challenges/ChallengeSignUpView.swift:141,626,634,641` | Pull reads then `form = state.value.form ?: result.value.withMinimumPrompts()`, `account/AO3ChallengeSignUpScreen.kt:96`; `account/AO3ChallengeSignUpState.kt:50` | **different · F02** — once form is non-null, every successful refresh discards the fetched form. Android is right to protect unsaved edits, but also keeps a clean, stale form indefinitely. Changes to existing requests, tags, limits, instructions or sign-up ID on AO3 cannot appear until reopening. A later submit can therefore use pre-refresh content. No recorded decision found for ignoring explicit refresh. |
| “Try Again” after failed load, `Challenges/ChallengeSignUpView.swift:604` | Same label, `account/AO3ChallengeSignUpScreen.kt:127`; terminal classification `account/AO3ChallengeSignUpState.kt:51` | **missing in parse/validation error state · F03** — disabled after Parse or Validation failures, and `load` rejects terminal retries (`A state :37`). iOS still retries. Refused/auth-invalid sessions are a separate, intentional fail-closed case; keep those guards. |

## PromptTagsEditorView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Four comma-separated fields (Fandoms, Relationships, Characters, Additional tags), `Challenges/PromptTagsEditorView.swift:38,45,52,59,91` | Same ordered fields, `account/AO3ChallengeSignUpScreen.kt:279,283` | **same** — edits local copies until Done. |
| “Done”, `Challenges/PromptTagsEditorView.swift:71,99` | Same, `account/AO3ChallengeSignUpScreen.kt:267` | **same** — splits comma lists, trims, drops empties, applies to correct parent request/offer, dismisses; no AO3 write. Dismissal/Back without Done discards this editor’s local changes on both. |

## ChallengeSignUpsView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| All / Matched / Unmatched, `Challenges/ChallengeSignUpsView.swift:166,83` | Same, `account/AO3ChallengeSignUpsScreen.kt:102`; `account/AO3ChallengeSignUpsState.kt:76` | **same when match evidence available**; **different, recorded** for moderator/unknown/open schedule: Android does not probe owner-only schedule and invent match state. `DECISIONS.md` 2026-10-09 3cb and networking policy row 28 explicitly retain this gate. Not a new finding. |
| Tap participant, `Challenges/ChallengeSignUpsView.swift:215` | Same, `account/AO3ChallengeSignUpsScreen.kt:142` | **same** — opens that already-loaded sign-up’s read-only requests/offers, no extra read. |
| “Load page N of M”, `Challenges/ChallengeSignUpsView.swift:331` | Same, `account/AO3ChallengeSignUpsScreen.kt:178` | **same** — appends next page; failure retains previous rows/page to retry. |
| “Your sign-up”, `Challenges/ChallengeSignUpsView.swift:356` | Same, `account/AO3ChallengeSignUpsScreen.kt:189,193` | **same** — uses own loaded sign-up ID, otherwise own-sign-up resolver. |
| “Create sign-up”, `Challenges/ChallengeSignUpsView.swift:382` | Same, `account/AO3ChallengeSignUpsScreen.kt:191,194` | **same** — opens form without explicit ID; existing own sign-up can be resolved by repository. |
| Pull refresh; Try Again, `Challenges/ChallengeSignUpsView.swift:139,439` | Same, `account/AO3ChallengeSignUpsScreen.kt:94`; failure component `:221` | **same** — resets list to page 1 and refreshes match evidence, within recorded role/refusal gates. Empty filters explain absence, no extra action on either. |

## ChallengeSignUpDetailView (inside ChallengeSignUpsView.swift)

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Read-only prompt detail, `Challenges/ChallengeSignUpsView.swift:549,562,563` | `ChallengeSignUpDetail`, `account/AO3ChallengeSignUpsScreen.kt:234,240` | **same** — no edit/delete/tag-navigation action; only platform Back. All requests/offers and optional/Any tags are content, not controls. |

## ChallengeAssignmentsView

| iOS action (I) | Android action (A) | Verdict / confirmation, undo, result |
|---|---|---|
| Matched / Unmatched / Pinch hits, `Challenges/ChallengeAssignmentsView.swift:184` | Same, `account/AO3ChallengeAssignmentsScreen.kt:110,116` | **same** segment actions; **different, recorded** loaded scope: iOS eagerly joins every page (`I :487,516`), Android reads first pages then Load More (`A :210`). `DECISIONS.md` 2026-10-09 3cc records this request-budget decision; do not count as missing rows/actions. |
| Owner “Report a default” → choose giver/recipient → confirmation / Report default / Cancel, `Challenges/ChallengeAssignmentsView.swift:703,132,145,768` | Same, `account/AO3ChallengeAssignmentsScreen.kt:225,77,90`; `account/AO3ChallengeAssignmentsState.kt:57,65,178` | **same** — only sent, unfulfilled, non-defaulted candidates from cleanly loaded lists; explains default and pinch-hit consequence; one confirmed write; reloads after success. No undo. |
| Owner “Claim a pinch hit” → candidate → confirmation, `Challenges/ChallengeAssignmentsView.swift:724,132,145` | Same, `account/AO3ChallengeAssignmentsScreen.kt:226,77,90`; `account/AO3ChallengeAssignmentsState.kt:67,185` | **same** — recipient/due date named; explicit Claim/Cancel; reload after success; no undo. |
| Inline pinch-hit “Claim”, `Challenges/ChallengeAssignmentsView.swift:659,353` | Same, `account/AO3ChallengeAssignmentsScreen.kt:199` | **same** — open row, owner-only, same confirmation/handler as picker. |
| Unmatched “Open on AO3”, `Challenges/ChallengeAssignmentsView.swift:415,431` | Same, `account/AO3ChallengeAssignmentsScreen.kt:185` | **same** — opens pinch-hits-filtered assignments page; does not pretend to submit a request for a pinch hitter. |
| Pull refresh; section Try Again; Dismiss error, `Challenges/ChallengeAssignmentsView.swift:131,594,615` | Same, `account/AO3ChallengeAssignmentsScreen.kt:101,152,132` | **same** within recorded refusal gates; refresh rereads due date unless refused. Successful writes reload lists; failed writes stay with error. |
| No manual list append because iOS loads all pages, `Challenges/ChallengeAssignmentsView.swift:516` | “Load more …” per list, `account/AO3ChallengeAssignmentsScreen.kt:210,212,285` | **Android only**, recorded request-budget control; keeps writes limited to loaded candidates and page failures out of candidate lists (`account/AO3ChallengeAssignmentsState.kt:53`). Android is right to exclude failed-list rows. |
| Pull refresh only, `Challenges/ChallengeAssignmentsView.swift:131` | “Refresh assignments” button, `account/AO3ChallengeAssignmentsScreen.kt:73` | **Android only**, same refresh operation; useful explicit touch equivalent, not a parity defect in chrome. |

## Coverage and limits

All screen types declared under the two iOS folders are represented above, including nested recovery, association, bulk-name, preview and participant-detail screens. `WritingCheckpoint.swift` and `WritingTagConvenience.swift` supply scheduling/data rather than independent screens; `WritingNativeTextView.swift` and `WritingFormFields.swift` are covered with their parent controls. No custom swipe/context-menu action was found in these scoped screens beyond the explicitly listed editor menu and long-press reorder gestures; native text-selection menus remain platform-owned.

Four new priorities: one departure-during-bulk-save lifecycle difference, one ignored sign-up refresh, one disabled error-state retry, one tag-group order mismatch. No confirmed missing ordinary writer/maintainer feature or missing destructive confirmation found in the inspected surfaces. Android correctly preserves the named destructive confirmations, undoable local text recovery, separate tag/prose writes, and total-only retries after chapter success. Recorded request-budget/role guards are not fixes requested by this audit.

Remaining **unsure**: exact external generated iOS markup catalog/payload equality, unusual parsed tag-set association destinations, and device/native keyboard timing. No builds, tests, runtime UI checks, authenticated operations, or AO3 requests were performed, per the brief. These are source findings, not claims of live AO3 verification.
