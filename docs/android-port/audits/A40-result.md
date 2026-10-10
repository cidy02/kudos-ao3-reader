54 fields found, 17 FLOW, 0 SNAPSHOT, 30 LOCAL

### Wrappers
- `ui/components/GlassFieldBar.kt:30`
- `settings/SettingsChrome.kt:110`
- `auth/AO3NativeLoginScreen.kt:392`
- `library/LibraryFilterPanel.kt:275`
- `search/FilterRangeSlider.kt:124`
- `search/TagSuggestField.kt:34`
- `search/SearchFilterSheet.kt:345`
- `writing/WritingChapterFormScreen.kt:185`

### Calls
**account/AO3ChallengeSettingsEditScreen.kt:164**
- value: `value`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: account/AO3ChallengeSettingsEditScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**account/AO3CollectionFormScreen.kt:174**
- value: `form.challengeOptions.firstOrNull {`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: account/AO3CollectionFormScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**account/AO3PreferencesScreen.kt:305**
- value: `label`
- onValueChange: `{}`
- Traced to: **FLOW**. Stored at: account/AO3PreferencesScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**account/AO3PreferencesScreen.kt:340**
- value: `texts[field.name] ?: field.value`
- onValueChange: `{ 
343:                                                         texts[field.name] = it
344:                                                         hasEdits = true
345:                                                         status = null
346:                                                     }`
- Traced to: **FLOW**. Stored at: account/AO3PreferencesScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**account/AO3ChallengeSignUpScreen.kt:160**
- value: `caption`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: account/AO3ChallengeSignUpScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**account/AO3CollectionMaintainersScreen.kt:133**
- value: `state.role.title`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: account/AO3CollectionMaintainersScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:135**
- value: `""`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:161**
- value: `""`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:202**
- value: `"1 work") }`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:212**
- value: `"") }`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:215**
- value: `"") }`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingAssociationPickers.kt:217**
- value: `form.languageOptions.firstOrNull { it.value == form.parentWork.languageID }?.title`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingAssociationPickers.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingSeriesScreen.kt:173**
- value: `if (name == "summary") form.summary else form.notes`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingSeriesScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingSeriesScreen.kt:179**
- value: `if (name == "summary") form.summary else form.notes`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingSeriesScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingWorkFormScreen.kt:238**
- value: `workFormCount(form.warnings)`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingWorkFormScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**writing/WritingWorkFormScreen.kt:333**
- value: `""`
- onValueChange: `model::chapterTotal`
- Traced to: **FLOW**. Stored at: writing/WritingWorkFormScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the MutableStateFlow without side effects.

**writing/WritingBulkEditScreen.kt:140**
- value: `= changes.scalars[entry.second] }?.title ?: "Leave as is"`
- onValueChange: `(unknown)`
- Traced to: **FLOW**. Stored at: writing/WritingBulkEditScreen.kt:? `val state by model.state.collectAsState()`
- Write-back updates the flow.

**reader/ReaderScreen.kt:1190**
- value: `note`
- onValueChange: `{ note = it }`
- Traced to: **LOCAL**. Stored at: reader/ReaderScreen.kt:1137 `var note by remember { mutableStateOf("") }`

**reader/ReaderSearchSheet.kt:161**
- value: `query`
- onValueChange: `{
164:                         query = it
165:                         model.search(it, chapterKey)
166:                     }`
- Traced to: **LOCAL**. Stored at: reader/ReaderSearchSheet.kt:110 `var query by remember(publication) { mutableStateOf("") }`

**settings/SettingsPages2.kt:873**
- value: `draft`
- onValueChange: `{ draft = it }`
- Traced to: **LOCAL**. Stored at: settings/SettingsPages2.kt:846 `var draft by remember { mutableStateOf(accentHex) }`

**home/HomeSectionsUi.kt:141**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: home/HomeSectionsUi.kt:133 `var name by remember { mutableStateOf("") }`

**home/HomeWorkMenu.kt:342**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: home/HomeWorkMenu.kt:334 `var name by remember { mutableStateOf("") }`

**home/HomeWorkMenu.kt:370**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: home/HomeWorkMenu.kt:334 `var name by remember { mutableStateOf("") }`

**comments/CommentComposerSheet.kt:236**
- value: `textFieldValue`
- onValueChange: `{
239:                         textFieldValue = it
240:                         onDraftChange(it.text)
241:                     }`
- Traced to: **LOCAL**. Stored at: comments/CommentComposerSheet.kt:73 `var textFieldValue by remember {`

**library/CollectionDetailScreen.kt:515**
- value: `renameText`
- onValueChange: `{ renameText = it }`
- Traced to: **LOCAL**. Stored at: library/CollectionDetailScreen.kt:147 `var renameText by remember(collectionId) { mutableStateOf("") }`

**library/CollectionDetailScreen.kt:551**
- value: `filterText`
- onValueChange: `{ filterText = it }`
- Traced to: **LOCAL**. Stored at: library/CollectionDetailScreen.kt:154 `var filterText by remember(collectionId) { mutableStateOf("") }`

**library/CollectionDetailScreen.kt:1044**
- value: `searchQuery`
- onValueChange: `{ searchQuery = it }`
- Traced to: **LOCAL**. Stored at: library/CollectionDetailScreen.kt:1021 `var searchQuery by remember { mutableStateOf("") }`

**library/WorkMembershipDialogs.kt:126**
- value: `newName`
- onValueChange: `{ newName = it }`
- Traced to: **LOCAL**. Stored at: library/WorkMembershipDialogs.kt:100 `var newName by remember(workId) { mutableStateOf("") }`

**library/QueueSettingsScreen.kt:170**
- value: `notes`
- onValueChange: `{ notes = it }`
- Traced to: **LOCAL**. Stored at: library/QueueSettingsScreen.kt:81 `var notes by remember(queueId) { mutableStateOf("") }`

**library/QueueEditorSheet.kt:171**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: library/QueueEditorSheet.kt:70 `var name by remember(existing?.id) { mutableStateOf(if (editing) existing!!.name else "") }`

**library/QueueEditorSheet.kt:193**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: library/QueueEditorSheet.kt:70 `var name by remember(existing?.id) { mutableStateOf(if (editing) existing!!.name else "") }`

**library/QueueEditorSheet.kt:249**
- value: `notes`
- onValueChange: `{ notes = it }`
- Traced to: **LOCAL**. Stored at: library/QueueEditorSheet.kt:73 `var notes by remember(existing?.id) { mutableStateOf(existing?.notes.orEmpty()) }`

**library/QueueOrganizerScreen.kt:176**
- value: `search`
- onValueChange: `{ search = it }`
- Traced to: **LOCAL**. Stored at: library/QueueOrganizerScreen.kt:93 `var search by remember { mutableStateOf("") }`

**library/LibraryScreen.kt:324**
- value: `newName`
- onValueChange: `{ newName = it }`
- Traced to: **LOCAL**. Stored at: library/LibraryScreen.kt:318 `var newName by remember { mutableStateOf("") }`

**library/QueuePageScreen.kt:624**
- value: `text`
- onValueChange: `{ text = it }`
- Traced to: **LOCAL**. Stored at: library/QueuePageScreen.kt:615 `var text by remember { mutableStateOf(filter.text) }`

**library/QueueTags.kt:117**
- value: `draft`
- onValueChange: `{ draft = it }`
- Traced to: **LOCAL**. Stored at: library/QueueTags.kt:71 `var draft by remember { mutableStateOf("") }`

**library/QueueTags.kt:267**
- value: `draft`
- onValueChange: `{ draft = it }`
- Traced to: **LOCAL**. Stored at: library/QueueTags.kt:71 `var draft by remember { mutableStateOf("") }`

**library/QueueTags.kt:446**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: library/QueueTags.kt:430 `var name by remember(tag.id) { mutableStateOf(tag.name) }`

**library/CollectionEditorSheet.kt:175**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: library/CollectionEditorSheet.kt:65 `var name by remember(existing?.id) { mutableStateOf(existing?.name.orEmpty()) }`

**library/CollectionEditorSheet.kt:184**
- value: `name`
- onValueChange: `{ name = it }`
- Traced to: **LOCAL**. Stored at: library/CollectionEditorSheet.kt:65 `var name by remember(existing?.id) { mutableStateOf(existing?.name.orEmpty()) }`

**works/WorkDetailScreen.kt:685**
- value: `newCollectionName`
- onValueChange: `{ newCollectionName = it }`
- Traced to: **LOCAL**. Stored at: works/WorkDetailScreen.kt:177 `var newCollectionName by remember { mutableStateOf("") }`

**browse/TagWorksScreen.kt:161**
- value: `refine`
- onValueChange: `{ refine = it }`
- Traced to: **LOCAL**. Stored at: browse/TagWorksScreen.kt:80 `var refine by remember { mutableStateOf("") }`

**browse/FandomListScreen.kt:182**
- value: `query`
- onValueChange: `{ query = it }`
- Traced to: **LOCAL**. Stored at: browse/FandomListScreen.kt:57 `var query by remember(category.name) { mutableStateOf("") }`

**account/BugReportScreen.kt:85**
- value: `summary`
- onValueChange: `{ summary = it }`
- Traced to: **LOCAL**. Stored at: account/BugReportScreen.kt:62 `var summary by rememberSaveable { mutableStateOf("") }`

**backup/PairingSheet.kt:259**
- value: `nameDraft`
- onValueChange: `{ nameDraft = it }`
- Traced to: **LOCAL**. Stored at: backup/PairingSheet.kt:237 `var nameDraft by remember(device.publicKeyHex) { mutableStateOf(device.label) }`

**backup/PairingSheet.kt:356**
- value: `pasteText`
- onValueChange: `{ pasteText = it; error = null }`
- Traced to: **LOCAL**. Stored at: backup/PairingSheet.kt:288 `var pasteText by remember { mutableStateOf("") }`

**backup/PairingSheet.kt:413**
- value: `trustLabel`
- onValueChange: `{ trustLabel = it }`
- Traced to: **LOCAL**. Stored at: backup/PairingSheet.kt:290 `var trustLabel by remember { mutableStateOf("") }`

**ui/components/GlassFieldBar.kt:42**
- value: `text`
- onValueChange: `onTextChange`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**ui/components/WorkBulkActionBar.kt:275**
- value: `newName`
- onValueChange: `{ newName = it }`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**settings/SettingsChrome.kt:149**
- value: `value`
- onValueChange: `onValueChange`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**search/TagSuggestField.kt:82**
- value: `value`
- onValueChange: `{ next ->
85:                 onValueChange(next)
86:                 expanded = true
87:             }`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**search/SearchFilterSheet.kt:263**
- value: `(unknown)`
- onValueChange: `(unknown)`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**search/SearchFilterSheet.kt:265**
- value: `(unknown)`
- onValueChange: `(unknown)`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

**search/SearchFilterSheet.kt:347**
- value: `label(selected)`
- onValueChange: `(unknown)`
- Traced to: **OTHER**. Stored at: Parameter `value`, traced from caller.

### Summary Table
| # | Field | Screen | Type | Storage |
|---|---|---|---|---|
| 1 | `account/AO3ChallengeSettingsEditScreen.kt:164` | AO3ChallengeSettingsEditScreen | FLOW | account/AO3ChallengeSettingsEditScreen.kt:? |
| 2 | `account/AO3CollectionFormScreen.kt:174` | AO3CollectionFormScreen | FLOW | account/AO3CollectionFormScreen.kt:? |
| 3 | `account/AO3PreferencesScreen.kt:305` | AO3PreferencesScreen | FLOW | account/AO3PreferencesScreen.kt:? |
| 4 | `account/AO3PreferencesScreen.kt:340` | AO3PreferencesScreen | FLOW | account/AO3PreferencesScreen.kt:? |
| 5 | `account/AO3ChallengeSignUpScreen.kt:160` | AO3ChallengeSignUpScreen | FLOW | account/AO3ChallengeSignUpScreen.kt:? |
| 6 | `account/AO3CollectionMaintainersScreen.kt:133` | AO3CollectionMaintainersScreen | FLOW | account/AO3CollectionMaintainersScreen.kt:? |
| 7 | `writing/WritingAssociationPickers.kt:135` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 8 | `writing/WritingAssociationPickers.kt:161` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 9 | `writing/WritingAssociationPickers.kt:202` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 10 | `writing/WritingAssociationPickers.kt:212` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 11 | `writing/WritingAssociationPickers.kt:215` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 12 | `writing/WritingAssociationPickers.kt:217` | WritingAssociationPickers | FLOW | writing/WritingAssociationPickers.kt:? |
| 13 | `writing/WritingSeriesScreen.kt:173` | WritingSeriesScreen | FLOW | writing/WritingSeriesScreen.kt:? |
| 14 | `writing/WritingSeriesScreen.kt:179` | WritingSeriesScreen | FLOW | writing/WritingSeriesScreen.kt:? |
| 15 | `writing/WritingWorkFormScreen.kt:238` | WritingWorkFormScreen | FLOW | writing/WritingWorkFormScreen.kt:? |
| 16 | `writing/WritingWorkFormScreen.kt:333` | WritingWorkFormScreen | FLOW | writing/WritingWorkFormScreen.kt:? |
| 17 | `writing/WritingBulkEditScreen.kt:140` | WritingBulkEditScreen | FLOW | writing/WritingBulkEditScreen.kt:? |
| 18 | `reader/ReaderScreen.kt:1190` | ReaderScreen | LOCAL | reader/ReaderScreen.kt:1137 |
| 19 | `reader/ReaderSearchSheet.kt:161` | ReaderSearchSheet | LOCAL | reader/ReaderSearchSheet.kt:110 |
| 20 | `settings/SettingsPages2.kt:873` | SettingsPages2 | LOCAL | settings/SettingsPages2.kt:846 |
| 21 | `home/HomeSectionsUi.kt:141` | HomeSectionsUi | LOCAL | home/HomeSectionsUi.kt:133 |
| 22 | `home/HomeWorkMenu.kt:342` | HomeWorkMenu | LOCAL | home/HomeWorkMenu.kt:334 |
| 23 | `home/HomeWorkMenu.kt:370` | HomeWorkMenu | LOCAL | home/HomeWorkMenu.kt:334 |
| 24 | `comments/CommentComposerSheet.kt:236` | CommentComposerSheet | LOCAL | comments/CommentComposerSheet.kt:73 |
| 25 | `library/CollectionDetailScreen.kt:515` | CollectionDetailScreen | LOCAL | library/CollectionDetailScreen.kt:147 |
| 26 | `library/CollectionDetailScreen.kt:551` | CollectionDetailScreen | LOCAL | library/CollectionDetailScreen.kt:154 |
| 27 | `library/CollectionDetailScreen.kt:1044` | CollectionDetailScreen | LOCAL | library/CollectionDetailScreen.kt:1021 |
| 28 | `library/WorkMembershipDialogs.kt:126` | WorkMembershipDialogs | LOCAL | library/WorkMembershipDialogs.kt:100 |
| 29 | `library/QueueSettingsScreen.kt:170` | QueueSettingsScreen | LOCAL | library/QueueSettingsScreen.kt:81 |
| 30 | `library/QueueEditorSheet.kt:171` | QueueEditorSheet | LOCAL | library/QueueEditorSheet.kt:70 |
| 31 | `library/QueueEditorSheet.kt:193` | QueueEditorSheet | LOCAL | library/QueueEditorSheet.kt:70 |
| 32 | `library/QueueEditorSheet.kt:249` | QueueEditorSheet | LOCAL | library/QueueEditorSheet.kt:73 |
| 33 | `library/QueueOrganizerScreen.kt:176` | QueueOrganizerScreen | LOCAL | library/QueueOrganizerScreen.kt:93 |
| 34 | `library/LibraryScreen.kt:324` | LibraryScreen | LOCAL | library/LibraryScreen.kt:318 |
| 35 | `library/QueuePageScreen.kt:624` | QueuePageScreen | LOCAL | library/QueuePageScreen.kt:615 |
| 36 | `library/QueueTags.kt:117` | QueueTags | LOCAL | library/QueueTags.kt:71 |
| 37 | `library/QueueTags.kt:267` | QueueTags | LOCAL | library/QueueTags.kt:71 |
| 38 | `library/QueueTags.kt:446` | QueueTags | LOCAL | library/QueueTags.kt:430 |
| 39 | `library/CollectionEditorSheet.kt:175` | CollectionEditorSheet | LOCAL | library/CollectionEditorSheet.kt:65 |
| 40 | `library/CollectionEditorSheet.kt:184` | CollectionEditorSheet | LOCAL | library/CollectionEditorSheet.kt:65 |
| 41 | `works/WorkDetailScreen.kt:685` | WorkDetailScreen | LOCAL | works/WorkDetailScreen.kt:177 |
| 42 | `browse/TagWorksScreen.kt:161` | TagWorksScreen | LOCAL | browse/TagWorksScreen.kt:80 |
| 43 | `browse/FandomListScreen.kt:182` | FandomListScreen | LOCAL | browse/FandomListScreen.kt:57 |
| 44 | `account/BugReportScreen.kt:85` | BugReportScreen | LOCAL | account/BugReportScreen.kt:62 |
| 45 | `backup/PairingSheet.kt:259` | PairingSheet | LOCAL | backup/PairingSheet.kt:237 |
| 46 | `backup/PairingSheet.kt:356` | PairingSheet | LOCAL | backup/PairingSheet.kt:288 |
| 47 | `backup/PairingSheet.kt:413` | PairingSheet | LOCAL | backup/PairingSheet.kt:290 |
| 48 | `ui/components/GlassFieldBar.kt:42` | GlassFieldBar | OTHER | Parameter |
| 49 | `ui/components/WorkBulkActionBar.kt:275` | WorkBulkActionBar | OTHER | Parameter |
| 50 | `settings/SettingsChrome.kt:149` | SettingsChrome | OTHER | Parameter |
| 51 | `search/TagSuggestField.kt:82` | TagSuggestField | OTHER | Parameter |
| 52 | `search/SearchFilterSheet.kt:263` | SearchFilterSheet | OTHER | Parameter |
| 53 | `search/SearchFilterSheet.kt:265` | SearchFilterSheet | OTHER | Parameter |
| 54 | `search/SearchFilterSheet.kt:347` | SearchFilterSheet | OTHER | Parameter |

## Triage (Claude, 2026-10-10)

The index is rough (most rows say `onValueChange: (unknown)` and give no line for where the text
is stored), but its count is useful: 17 fields take their text straight from a state holder's
flow, and 14 of them through one composable, `SubjectTextFieldRow` (`settings/SettingsChrome.kt:110`),
which hands the string to `BasicTextField`.

**Tested on the emulator, and they do not have the composer's fault.** The same fast input that
garbled the composer (`adb shell input text`, one burst of about 70 characters) was typed into
the work form's Title (single line, row 15) and into a challenge's Sign-up instructions
(multi-line, row 1): 93 and 122 characters, every one in place. The composer's fault was its own
`LaunchedEffect(draft)`, which put a late echo back over the field (fixed in `e682a4f2`), not
the flow as such. **Nothing to change.** Not tested: the other fifteen fields one by one, the
`OutlinedTextField`s in AO3 Preferences (rows 3 and 4), and a slow device.

