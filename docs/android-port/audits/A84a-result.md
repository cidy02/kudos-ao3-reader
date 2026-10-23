Counts: **35/35 screens reviewed · 56 P2 differences · 43 P3 differences · 7 screens same in scope**. Counts are per-screen findings; shared defects repeated on two screens are counted on both. 3 P2 entries include a **suspected** visual consequence (identified in the notes); the underlying code difference is verified.

## P2 findings

1. **newqueue — Duplicate name ignores the new queue’s choices.** [Evidence](#newqueue).
2. **newqueue — Save-failure feedback absent on iOS.** [Evidence](#newqueue).
3. **newqueue — Name field loses its spoken name.** [Evidence](#newqueue).
4. **newqueue — Start-from radio buttons lack their spoken option labels/counts.** [Evidence](#newqueue).
5. **editqueue — Save-failure feedback absent on iOS.** [Evidence](#editqueue).
6. **editqueue — Spoken Name.** [Evidence](#editqueue).
7. **queuetagedit — Exact-name rename globally merges.** [Evidence](#queuetagedit).
8. **queuetagedit — Merge destinations lack counts and action labels.** [Evidence](#queuetagedit).
9. **queuetagedit — Merge confirmation loses affected scope.** [Evidence](#queuetagedit).
10. **addtoqueue — Work Detail cannot remove a membership.** [Evidence](#addtoqueue).
11. **addtoqueue — Library series preview is missing.** [Evidence](#addtoqueue).
12. **collectiondetails — Write-failure feedback absent on iOS.** [Evidence](#collectiondetails).
13. **newcollection — Duplicate name silently drops the draft.** [Evidence](#newcollection).
14. **newcollection — Save-failure feedback absent on iOS.** [Evidence](#newcollection).
15. **collectionreorder — Creator byline cut.** [Evidence](#collectionreorder).
16. **addtocollection — Typing an existing name changes another action.** [Evidence](#addtocollection).
17. **fandomlist — Refresh can return the same disk cache.** [Evidence](#fandomlist).
18. **fandomlist — Family aliases are cut/omitted.** [Evidence](#fandomlist).
19. **fandomlist — Unknown work count becomes zero.** [Evidence](#fandomlist).
20. **fandomlist — Group variants is not persisted globally.** [Evidence](#fandomlist).
21. **fandomlist — Refresh failure replaces the list.** [Evidence](#fandomlist).
22. **fandomlist — Download badge stops at 99.** [Evidence](#fandomlist).
23. **fandomlist — Largest-text stacking missing.** [Evidence](#fandomlist).
24. **fandomworks — Selection drops result information.** [Evidence](#fandomworks).
25. **fandomworks — A matching local work changes the row and tap action only on Android.** [Evidence](#fandomworks).
26. **fandomworks — Family fallback differs.** [Evidence](#fandomworks).
27. **fandomworks — Selection survives a page/sort change.** [Evidence](#fandomworks).
28. **fandomworks — Paging discards visible results while loading.** [Evidence](#fandomworks).
29. **tagworks — Selection drops result information.** [Evidence](#tagworks).
30. **tagworks — A matching local work changes the row and tap action only on Android.** [Evidence](#tagworks).
31. **tagworks — Selection survives changed results.** [Evidence](#tagworks).
32. **tagworks — Paging/refresh replaces the usable results.** [Evidence](#tagworks).
33. **tagworks — Fandom filter cannot be chosen.** [Evidence](#tagworks).
34. **fandomfilter — Dismiss applies unconfirmed edits.** [Evidence](#fandomfilter).
35. **savesearch — Name field has no persistent spoken label.** [Evidence](#savesearch).
36. **savesearch — Long filter summaries cannot scroll.** [Evidence](#savesearch).
37. **tagpicker — One-character AO3 search is missing.** [Evidence](#tagpicker).
38. **tagpicker — Typed, unverified names offered as results.** [Evidence](#tagpicker).
39. **readercontents — Empty-TOC fallback differs.** [Evidence](#readercontents).
40. **readercontents — Synthesized Summary missing.** [Evidence](#readercontents).
41. **readercontents — Bookmark notes disappear from the list.** [Evidence](#readercontents).
42. **readercontents — Highlight previews lose text.** [Evidence](#readercontents).
43. **readerfind — Same-page bookmark can be duplicated.** [Evidence](#readerfind).
44. **readerfind — Search field loses its spoken label when nonempty.** [Evidence](#readerfind).
45. **readerdisplay — Read Aloud controls missing in this sheet.** [Evidence](#readerdisplay).
46. **readerdisplay — Pack state/disclosure omitted.** [Evidence](#readerdisplay).
47. **readerdisplay — Two switches have no spoken label.** [Evidence](#readerdisplay).
48. **pronunciations — Storage errors are only explained on Android.** [Evidence](#pronunciations).
49. **pronunciations — Saved corrections do not change speech on current Android.** [Evidence](#pronunciations).
50. **pronunciations — Guessed-word list missing.** [Evidence](#pronunciations).
51. **pronunciations — Scan this chapter missing.** [Evidence](#pronunciations).
52. **pronunciationedit — Failed save is visible only on Android.** [Evidence](#pronunciationedit).
53. **pronunciationedit — Respelling conversion and preview missing.** [Evidence](#pronunciationedit).
54. **formattingtray — Ordinary formatting closes the tray.** [Evidence](#formattingtray).
55. **chapterpicker — Long list has no scroll container.** [Evidence](#chapterpicker).
56. **chapterpicker — Detailed failure reason lost.** [Evidence](#chapterpicker).

## Per-screen notes

Code-only audit, completed 2026-10-23. `iOS` paths are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`; `Android` paths are relative to `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`. References include current callers/helpers where the original A82 map was stale. Source checkout HEADs at final verification: iOS `7dc23568`, Android `933b9bed`; reviewed working files, not historical copies.

Compared content, order, control effects and conditional/loading/empty/error/accessibility/privacy branches. Read DECISIONS in the Android checkout for exclusions. Platform navigation/chrome, control styling, font appearance, demo fixtures and sheet accents are excluded. Documented extra Android information is not treated as a gap. Known missing functions are identified as known where appropriate; a documented limitation is distinguished from an extra explanatory notice. No app was launched, no account was used, no build/test command was run, and no AO3 request was made. This is not visual verification. No code, task board, branches or other files were edited.

### libpicker

Same in scope: live multi-selection, sorted library facets, case/diacritic-insensitive search, empty/no-match text, and Done. Sources: iOS `Features/Library/LibraryFilterPanel.swift:246–324`; Android `library/LibraryFilterPanel.kt:301–351`. No size-specific content branch in either picker.

### queuesettings

- **P3 — Origin text:** iOS receives an origin kicker (default Library), Android hard-codes Home. Opening details from Library therefore names Home on Android. iOS `Features/Library/ReadingQueueSettingsView.swift:30,124`; Android `library/QueueSettingsScreen.kt:167`.
- **P3 — Current colour choice:** iOS marks the selected preset with a checkmark; Android lists presets without a selected state. iOS `Features/Library/ReadingQueueSettingsView.swift:205–215`; Android `library/QueueSettingsScreen.kt:261–283`.

Description writes through, tag removal, offline toggle, progress/legend, Order, Last read, and vocabulary count otherwise match. Both retain concealed works in aggregate counts; neither displays work titles here.

### newqueue

- **P2 — Duplicate name ignores the new queue’s choices:** iOS always constructs a new queue; Android returns an active custom queue with the same name (ignoring case) before applying colour, offline choice, tags or Saved for Later seed. Create can therefore close without creating the configured queue. iOS `Services/ReadingQueueService.swift:166–195`; Android `library/QueueEditorSheet.kt:140–151`, `library/ReadingQueueRepository.kt:269–275`.
- **P2 — Save-failure feedback absent on iOS:** Android keeps the form and shows “Could not save” after a failed repository write; iOS’s service saves best-effort and the sheet’s Create callback completes without a visible error state. iOS `Features/Library/NewReadingQueueSheet.swift:143`, `Services/ReadingQueueService.swift:194`; Android `library/QueueEditorSheet.kt:149–153,259–265`.
- **P3 — Keyboard submit:** iOS submits the queue name from Return; Android’s name field has no submit action. iOS `Features/Library/NewReadingQueueSheet.swift:226`; Android `library/QueueEditorSheet.kt:172–178`.

- **P2 — Name field loses its spoken name:** iOS explicitly labels the example-placeholder field “Name”; Android has only the separate heading and “Case fic pile” placeholder, with no field label/semantics. iOS `Features/Library/NewReadingQueueSheet.swift:217–226`; Android `library/QueueEditorSheet.kt:171–178`.
- **P2 — Start-from radio buttons lack their spoken option labels/counts:** iOS exposes the title, subtitle (including count or why disabled), and selected trait as one control. Android's RadioButton has no label/semantics and its title/subtitle are sibling Text nodes; only the radio itself is clickable. iOS `Features/Library/NewReadingQueueSheet.swift:258–290`; Android `library/QueueEditorSheet.kt:302–323`.
- **P3 — Initial seed state:** iOS withholds the Saved for Later subtitle while its count is unknown; Android initially says there are no works and disables the choice until the read completes. iOS `Features/Library/NewReadingQueueSheet.swift:72,158–161,312–320`; Android `library/QueueEditorSheet.kt:79,83–90,223–232`.

Fields, section order, default offline-on/Empty, colour persistence, tag reuse, and explicit Create otherwise match. The older Android `home/HomeSectionsUi.kt:129` NewQueueDialog has no callers (source search); it is not the live comparator.

### editqueue

- **P2 — Save-failure feedback absent on iOS:** iOS dismisses after the best-effort save, with no error displayed; Android remains open with “Could not save”. iOS `Features/Library/NewReadingQueueSheet.swift:376–380`, `Services/ReadingQueueService.swift:236`; Android `library/QueueEditorSheet.kt:124–153,259–265`.
- **P3 — Keyboard submit:** iOS Return saves via the shared name field; Android has no submit action there. iOS `Features/Library/NewReadingQueueSheet.swift:226,368–376`; Android `library/QueueEditorSheet.kt:172–178`.

- **P2 — Spoken Name:** same field-label gap as newqueue. iOS `Features/Library/NewReadingQueueSheet.swift:217–226,368`; Android `library/QueueEditorSheet.kt:171–178`.

Same draft/save/cancel behavior and fields; Start from omitted on both. iOS `Features/Library/NewReadingQueueSheet.swift:335–384`; Android `library/QueueEditorSheet.kt:70–91,120–162,213`.

### addworks

- **P3 — Selection after re-concealing mature works:** iOS’s Add count/enabled state uses all selected IDs, even if hiding mature works removes them from eligibility; its eventual add uses eligible works only. Android counts/enables Add from the eligible chosen works, so it does not promise to add a now-concealed selection. iOS `Features/Library/AddLibraryWorksSheet.swift:116–117,168–171`; Android `library/AddLibraryWorksSheet.kt:82,160–161`.

- **P3 — Selection wording:** iOS says “Selected”/“Not selected” with a select/deselect hint; Android exposes a checkbox's checked state. iOS `Features/Library/AddLibraryWorksSheet.swift:149–157`; Android `library/AddLibraryWorksSheet.kt:130–142`.

Same candidate ordering, search, add count, author links, empty/no-match/hidden-only states, and exclusion of both blurred and hidden works until revealed. Sources: iOS `Features/Library/AddLibraryWorksSheet.swift:28–175`; Android `library/AddLibraryWorksSheet.kt:38–166`. Both cap work titles at two lines, including large text.

### queuetag

- **P3 — Keyboard submit:** iOS submits the text field from Return (Add, or Rename in the editor); Android’s corresponding field has no keyboard submit callback. iOS `Features/Library/QueueTagSheet.swift:132–139`; Android `library/QueueTags.kt:195–215`.

- **P3 — Applied status text:** iOS shows only a checkmark for all and lowercase “some” for partial coverage; Android adds “All” and capitalizes “Some”. iOS `Features/Library/QueueTagSheet.swift:157–175`; Android `library/QueueTags.kt:251–267`.
- **P3 — Spoken status:** a single queue's iOS status is “on this queue”/“not on this queue”; Android says “on every selected queue”/“not applied” even for one queue. For multiple queues its none state also loses “not on the selected queues”. iOS `Features/Library/QueueTagSheet.swift:178–185`; Android `library/QueueTags.kt:83–87,98–113,253`.

Same immediate writes, add-only typed tag reuse, three-state toggle rule, empty state, footnotes and Done.

### queuetags

- **P3 — Keyboard submit:** iOS submits the text field from Return (Add, or Rename in the editor); Android’s corresponding field has no keyboard submit callback. iOS `Features/Library/QueueTagManagerView.swift:240–250`; Android `library/QueueTags.kt:366–386`.

- **P3 — Copy with no destination:** iOS disables Copy tag to another queue when there are no other queues; Android opens a “No other queues.” dialog. iOS `Features/Library/QueueTagManagerView.swift:205–225`; Android `library/QueueTags.kt:403–428,488`.
- **P3 — Count wording/accessibility:** iOS shows compact counts and speaks “N works in this queue”; Android shows the raw integer and “Tag actions”, without explaining the count's unit/scope. iOS `Features/Library/QueueTagManagerView.swift:168–181,218`; Android `library/QueueTags.kt:477–514`.
- **P3 — Removal question:** Android adds the scope explanation to the manager's removal confirmation; iOS's manager asks the title only (its editor does explain scope). iOS `Features/Library/QueueTagManagerView.swift:114–128`; Android `library/QueueTags.kt:430–458`.

Same used/unused groups, descending use counts, Add, rename/merge/show/copy/remove actions. Show-only returns to the queue on both (Android `app/AppNavHost.kt:307–310`; iOS `Features/Library/QueueTagManagerView.swift:199–203`).

### queuetagedit

- **P3 — Keyboard submit:** iOS submits the text field from Return (Add, or Rename in the editor); Android’s corresponding field has no keyboard submit callback. iOS `Features/Library/QueueTagManagerView.swift:368–370`; Android `library/QueueTags.kt:547`.

- **P2 — Exact-name rename globally merges:** iOS blocks Save for every existing other tag, ignoring case, and points to the queue-scoped merge list when appropriate. Android allows Save when the conflict name exactly equals the typed name and merges every work/queue link into that other tag, deleting the old tag. iOS `Features/Library/QueueTagManagerView.swift:356–358,418,520–541`; Android `library/QueueTags.kt:535–552,587–596`, `library/ReadingQueueRepository.kt:507–531`.
- **P2 — Merge destinations lack counts and action labels:** iOS each sibling shows its use count and speaks “Merge into [tag]”, “N works in this queue”; Android offers only the sibling's name. iOS `Features/Library/QueueTagManagerView.swift:475–487`; Android `library/QueueTags.kt:559–569`.
- **P2 — Merge confirmation loses affected scope:** iOS repeats whether zero/one/N works will be retagged and the tag removed from this queue. Android's question gives only tag names and “You can't undo this in Kudos.” (even at zero, where iOS intentionally omits that warning). iOS `Features/Library/QueueTagManagerView.swift:436–448,499–511`; Android `library/QueueTags.kt:600–615`.

### bulktag

- **P3 — Keyboard submit:** iOS submits the text field from Return (Add, or Rename in the editor); Android’s corresponding field has no keyboard submit callback. iOS `UIComponents/WorkBulkTagSheet.swift:32–36`; Android `library/QueueTags.kt:195–215`.

- **P3 — Headers:** Android adds an “Add” heading and keeps “Your tags” even when no tags exist; iOS has no Add heading and omits Your tags in the empty branch. iOS `UIComponents/WorkBulkTagSheet.swift:29–54`; Android `library/QueueTags.kt:189,218–220`.

Otherwise same add-only text entry, all/some/none toggle semantics, immediate writes, spoken coverage, empty copy, footer and Done. iOS `UIComponents/WorkBulkTagSheet.swift:71–154`; Android `library/QueueTags.kt:122–139,202–250`.

### addtoqueue

The map's `QueuePickerDialog` is now the Move-to picker; Add to Queue uses `QueueMembershipDialog` / `WorkDetailQueueForm` (Android `ui/components/WorkBulkActionBar.kt:217–220`, `library/WorkMembershipDialogs.kt:166–244`). Compared the current forms and their callers.

- **P2 — Work Detail cannot remove a membership:** iOS tapping a checked queue removes the work; Android Work Detail's callback deliberately only adds, so a checked row cannot be unchecked. The Library's Android form does toggle correctly. iOS `Features/Library/ReadingQueues.swift:666–679`; Android `works/WorkDetailScreen.kt:962–967`, `library/WorkMembershipDialogs.kt:211–216`.
- **P2 — Library series preview is missing:** iOS checks series size and shows the preview/error-derived prompt before adding; Android's shared Library form passes `false, null` for checking/preview and goes straight to preservation after the explicit Add Series action. iOS `Features/Library/ReadingQueues.swift:505–516,619–628`; Android `library/WorkMembershipDialogs.kt:202–204,219–232`.
- **P3 — Bulk series choice:** iOS offers the series group only for one work; Android offers it for a multiple-work selection with a series and iterates all distinct series. iOS `Features/Library/ReadingQueues.swift:604–613`; Android `library/WorkMembershipDialogs.kt:185,203,225–229`.
- **P3 — Busy controls:** iOS tracks work per queue and Done stays available; Android's shared Library form blocks the whole form/Done while changing membership, and queue rows are also blocked during series addition. iOS `Features/Library/ReadingQueues.swift:483–488,555–560,674–679`; Android `library/WorkMembershipDialogs.kt:195–204,237`, `works/detail/WorkDetailForms.kt:220–240`.

### queuestorage

- **P3 — Queue-only removal explanation:** iOS explains that an unsaved/unfavorited work is removed if not in another queue; Android uses the shared work-deletion message instead. Button and underlying remove-from-all-queues action match. iOS `Features/Library/ReadingQueues.swift:409–423`; Android `settings/QueueStorageScreen.kt:151–168`.

Same summary, preserved-file test, per-work byte size/Queue badge, empty/footer copy, conditional Keep Download and mandatory removal confirmation. iOS `Features/Library/ReadingQueues.swift:257–434`; Android `settings/QueueStorageScreen.kt:67–294`. Neither screen applies mature Blur/Hide to the named storage rows.

### collectiondetails

- **P2 — Write-failure feedback absent on iOS:** description/colour/behaviour failures are only best-effort saves on iOS; Android exposes “Could not save” and does not close after a failed Done write. iOS `Features/Library/Collections.swift:194–205,225–228,248,265,293`; Android `library/CollectionEditorSheet.kt:140–144,296–302`.

- **P3 — Extra footer and different colour wording:** Android repeats New Collection's “This collection stays on this device…” footer in Details, which iOS omits. Its unpicked-colour sentence says “a colour” where iOS says “this colour”. iOS `Features/Library/Collections.swift:212–214,279–295`; Android `library/CollectionEditorSheet.kt:228–234,289–291`.

Same colour → description → behaviour order, immediate writes, no rename field, Done, and both behaviour toggles. iOS `Features/Library/Collections.swift:183–299`; Android `library/CollectionEditorSheet.kt:81–148,187–287`.

### newcollection

- **P2 — Duplicate name silently drops the draft:** iOS creates a new collection. Android’s repository returns an existing case-insensitive name match, without applying the description, colour or behaviour choices just entered, and the sheet reports it saved. iOS `Features/Library/NewCollectionSheet.swift:149–161`; Android `library/CollectionEditorSheet.kt:129–144`, `works/WorkRepository.kt:945–951`.
- **P2 — Save-failure feedback absent on iOS:** iOS saves best-effort and dismisses; Android retains the form and displays the write failure. iOS `Features/Library/NewCollectionSheet.swift:159–161`; Android `library/CollectionEditorSheet.kt:95–144,296–302`.

- **P3 — Explicit Colour heading:** Android inserts “Colour” above the swatches; iOS has name, description and swatches together under Collection without that label. iOS `Features/Library/NewCollectionSheet.swift:99–117`; Android `library/CollectionEditorSheet.kt:204–227`.
- **P3 — Description entry:** iOS's new-collection Description is a single-line field; Android accepts multiline text (minimum two lines). iOS `Features/Library/NewCollectionSheet.swift:106–108`; Android `library/CollectionEditorSheet.kt:187–195,215`.

Same fields, defaults (both behaviour switches off), section order, footnotes and Create/Cancel. Sources: iOS `Features/Library/NewCollectionSheet.swift:15–162`; Android `library/CollectionEditorSheet.kt:56–305`.

### collectionreorder

- **P2 — Creator byline cut:** iOS deliberately leaves the entire creator text visible; Android caps it at one ellipsized line at every font scale. Multi-creator works can become indistinguishable visually, especially at the largest text. iOS `Features/Library/NewCollectionSheet.swift:307–325`; Android `library/CollectionReorderSheet.kt:179–195`.

Same position/title/creator information in the spoken label, draft changes saved only on Done, Cancel and explanatory footer. Both display mature titles without Blur/Hide in this reorder surface. iOS `Features/Library/NewCollectionSheet.swift:174–327`; Android `library/CollectionReorderSheet.kt:62–236`.

### addtocollection

- **P3 — Order:** iOS lists newest-created collections first; Android's single-work picker sorts alphabetically ignoring case. iOS `Features/Library/Collections.swift:620–624`; Android `library/WorkMembershipDialogs.kt:120–122`.
- **P3 — Empty wording:** iOS “You have no collections yet. Create one above to group works together.”; Android “No collections yet. Create one above to start grouping works.” iOS `Features/Library/Collections.swift:639–643`; Android `library/WorkMembershipDialogs.kt:108–113`.
- **P2 — Typing an existing name changes another action:** iOS's New collection/Add always creates a new collection, even with the same name. Android create-or-matches by name and attaches the work to the existing collection instead. iOS `Features/Library/Collections.swift:719–730`; Android `library/WorkMembershipDialogs.kt:97–103`, `works/WorkRepository.kt:1046–1047` (creation path verified at `works/WorkRepository.kt:945–951`).

Membership checklists write immediately on both. Android uses checked-state semantics where iOS speaks “In this collection”.

### fandomlist

- **P2 — Refresh can return the same disk cache:** iOS explicitly invalidates responses and rereads the fandom index; Android’s refresh calls the same repository method that immediately returns a fresh catalog entry, with no forced-refresh option. Pulling to refresh can leave the list unchanged until cache expiry. iOS `Features/Search/FandomListView.swift:243–245,437–439`, `Services/AO3Client.swift:1672–1677`; Android `browse/FandomListScreen.kt:93–98,166`, `network/ao3/browse/AO3BrowseRepository.kt:51–60`, `app/KudosAppContainer.kt:311–312`.
- **P2 — Family aliases are cut/omitted:** iOS renders every header alias and allows it to wrap; Android takes only the first two and truncates each to one line, including at the largest text. iOS `Features/Search/FandomFamilyRows.swift:57–61,185–186`; Android `browse/FandomListChrome.kt:300–302`.
- **P2 — Unknown work count becomes zero:** for a single fandom with no parsed work count, iOS omits the figure; Android’s Member turns null into 0 and always draws it, asserting zero works rather than unknown. iOS `Features/Search/FandomListView.swift:938–961`; Android `browse/FandomFamily.kt:72`, `browse/FandomListChrome.kt:243–251`.

- **P2 — Group variants is not persisted globally:** iOS stores `browse.fandoms.groupsVariants` across launches/categories; Android keeps it only in this navigation entry and starts each new entry at true. iOS `Features/Search/FandomListView.swift:47`; Android `browse/FandomListScreen.kt:71,200–202`.
- **P2 — Refresh failure replaces the list:** iOS preserves existing fandoms and only logs a refresh error. Android replaces Loaded with Error, removing the usable rows. iOS `Features/Search/FandomListView.swift:437–459`; Android `browse/FandomListScreen.kt:93–98,176–191`.
- **P2 — Download badge stops at 99:** iOS formats the real count compactly; Android clamps the visible number to 99 without a plus sign (its spoken count remains real). iOS `Features/Search/FandomListView.swift:967–976`; Android `browse/FandomListChrome.kt:80–96`.
- **P2 — Largest-text stacking missing:** iOS moves counts and download badges below single-fandom names at accessibility sizes, and its family rows also branch for accessibility. Android keeps the single/family rows horizontal with fixed count columns; no accessibility-scale branch in these rows. The resulting clipping is **suspected**, not rendered here; the missing layout branch is verified. iOS `Features/Search/FandomListView.swift:864–873,876–961`, `Features/Search/FandomFamilyRows.swift:24`; Android `browse/FandomListChrome.kt:213–251,285–378`.
- **P3 — Spoken work-count unit:** iOS labels the single-fandom count “N works”; Android's count is bare digits and the work glyph is silent. iOS `Features/Search/FandomListView.swift:938–960`; Android `browse/FandomListChrome.kt:243–265`.

### fandomworks

- **P2 — Selection drops result information:** iOS keeps the full ledger row while selecting (fandom/series, summary, rating/category/warning/completion signals, statistics/date and expand/tag access). Android replaces it with only a one-line title and author beside a checkbox; no accessibility-size branch restores the omitted information. iOS `Features/Browse/NativeBrowseView.swift:224–234`, `UIComponents/RemoteWorkSelection.swift:204–219`, `Features/Search/AO3WorkRow.swift:235–256,286–299,541–620`; Android `browse/FandomWorksScreen.kt:295–312`, `ui/components/RemoteWorkSelection.kt:303–342`.
- **P2 — A matching local work changes the row and tap action only on Android:** these iOS browse views render AO3WorkRow directly; Android resolves matching local works, renders their local metadata/reading state and opens the reader rather than the remote work detail. In Blur mode Android obscures that matched local work until reveal, while the iOS browse row stays a plain remote row; entering Android selection bypasses the local/blur wrapper. Unmatched remote works remain visible on both, including Hide mode. iOS `Features/Browse/NativeBrowseView.swift:224–234`, `UIComponents/RemoteWorkSelection.swift:204–222`, `Features/Search/AO3WorkRow.swift:59–65`; Android `browse/FandomWorksScreen.kt:295–311`, `ui/components/WorkRowActions.kt:135–137,180–188`, `ui/components/SensitiveWorkRow.kt:711–719`.

- **P2 — Family fallback differs:** if a sibling’s numeric filter ID cannot be resolved, iOS still loads the intersection using the sibling names and avoids caching it as an exact family count. Android returns a parse error and no works. iOS `Features/Browse/NativeBrowseView.swift:360–366,393–411`; Android `network/ao3/browse/AO3BrowseRepository.kt:122–127`.
- **P2 — Selection survives a page/sort change:** iOS clears selected IDs when paging or changing sort. Android replaces the results without clearing its selected IDs; the action bar still counts previous-page IDs, although actions resolve only selections on the current page. iOS `Features/Browse/NativeBrowseView.swift:283–287,343–348`; Android `browse/FandomWorksScreen.kt:127–137,280,291`, `ui/components/RemoteWorkSelection.kt:65–66,91–93,140–150`.

- **P2 — Paging discards visible results while loading:** iOS retains results/hero and disables the pager while fetching another page; Android replaces Loaded with Loading and the entire list with placeholders. A failed page/refresh on iOS leaves the old results under the error overlay, Android retains no rows. iOS `Features/Browse/NativeBrowseView.swift:195–245,277–287,369–437`; Android `browse/FandomWorksScreen.kt:127–151,220–228`.

Same default Date Updated, baseline reset, explicit filter Apply/dismiss rollback, empty/error wording, retry and upper/lower pagination. The ordinary result-row replacement/local-match differences are identified above; accepted extra affinity/author-link details are not separate findings.

### tagworks

- **P2 — Selection drops result information:** iOS keeps the full ledger row while selecting (fandom/series, summary, rating/category/warning/completion signals, statistics/date and expand/tag access). Android replaces it with only a one-line title and author beside a checkbox; no accessibility-size branch restores the omitted information. iOS `Features/Browse/NativeBrowseView.swift:581–591`, `UIComponents/RemoteWorkSelection.swift:204–219`, `Features/Search/AO3WorkRow.swift:235–256,286–299,541–620`; Android `browse/FandomWorksScreen.kt:295–312`, `ui/components/RemoteWorkSelection.kt:303–342`.
- **P2 — A matching local work changes the row and tap action only on Android:** these iOS browse views render AO3WorkRow directly; Android resolves matching local works, renders their local metadata/reading state and opens the reader rather than the remote work detail. In Blur mode Android obscures that matched local work until reveal, while the iOS browse row stays a plain remote row; entering Android selection bypasses the local/blur wrapper. Unmatched remote works remain visible on both, including Hide mode. iOS `Features/Browse/NativeBrowseView.swift:581–591`, `UIComponents/RemoteWorkSelection.swift:204–222`, `Features/Search/AO3WorkRow.swift:59–65`; Android `browse/FandomWorksScreen.kt:295–311`, `ui/components/WorkRowActions.kt:135–137,180–188`, `ui/components/SensitiveWorkRow.kt:711–719`.

- **P2 — Selection survives changed results:** same stale selection/count behavior as fandomworks when paging, sorting or applying filters. iOS clears it on pagination, sort and reload. iOS `Features/Browse/NativeBrowseView.swift:664,725,746–754`; Android `browse/FandomWorksScreen.kt:127–137,280,291,343`, `ui/components/RemoteWorkSelection.kt:65–66,91–93,140–150`.

- **P2 — Paging/refresh replaces the usable results:** same behavior difference as fandomworks. iOS `Features/Browse/NativeBrowseView.swift:553–601,655–665,757–782`; Android `browse/FandomWorksScreen.kt:127–151,220–228`.
- **P2 — Fandom filter cannot be chosen:** iOS's tag result panel leaves the Fandoms picker enabled (the panel default); Android passes `showFandomPicker = false` for both fandom and tag pages. On a generic tag page the reader cannot narrow to a fandom through that picker. iOS `Features/Browse/NativeBrowseView.swift:613–620`; Android `browse/FandomWorksScreen.kt:335–345`.

Same tag-specific empty wording, sort baseline and apply/dismiss rule. Both remote listings retain mature works rather than applying local-library Hide to AO3's result set; the matched-local Blur behavior differs as noted above.

### fandomfilter

- **P2 — Dismiss applies unconfirmed edits:** iOS changes a draft and copies it only on Show N tags; Android's `onDismissRequest` calls `onApply(draft)` too, so Back/swiping the sheet away applies it. iOS `Features/Search/FandomListView.swift:138–154`; Android `browse/FandomListChrome.kt:456–463,534–535`.

Same Minimum works → Tag kinds → Yours → Grouping order, counts, explanatory copy, disabled grouping filter and Reset. iOS `Features/Search/FandomListFilterSheet.swift:23–194`; Android `browse/FandomListChrome.kt:448–596`.

### savesearch

- **P3 — Date/Updated summary order:** iOS puts the Updated preset before After/Before date bounds; Android puts date bounds before Updated. This affects What gets saved and the browse result summaries too. iOS `Models/AO3Models.swift:559–567`; Android `search/SearchFilterHelpers.kt:217–230`.

- **P2 — Name field has no persistent spoken label:** iOS's TextField is titled Name. Android uses an unlabeled BasicTextField; “Name” exists only as a decoration when the value is empty, and a proposed name is normally already present. iOS `Features/Search/SaveSearchSheet.swift:37`; Android `search/SaveSearchSheet.kt:101–115`.
- **P2 — Long filter summaries cannot scroll:** iOS uses List for the entire sheet. Android uses nested ordinary Columns and FlowRow without a scrolling container, so many selected filters/largest text can put the remainder beyond the sheet's bounds (**suspected clipping**, verified lack of scroll). iOS `Features/Search/SaveSearchSheet.swift:35–84`; Android `search/SaveSearchSheet.kt:67–166`.

Name helper, What gets saved, empty summary, chip creation/order and final footer otherwise match.

### pagejump

Same in scope: page input starts at current, ASCII digits only, invalid/zero falls back to current, upper bound clamps to last, nearby choices edit the draft, First/Last edit the draft, and only Go commits. Both expose Page N and selected state. iOS `Features/Search/SearchPaginationBar.swift:295–488`; Android `ui/components/KudosPaginationBar.kt:194–281,305–310`. Platform control differences excluded.

### languagepicker

Same picker behavior in scope: native language names/codes searched case/diacritic-insensitively, Any language, checkmarked current choice, live selection without auto-dismiss, no special no-match message. iOS `Features/Search/FilterLanguagePicker.swift:10–74`; Android `search/FilterLanguagePicker.kt:41–95`. The current Android path is a searchable picker, despite the older map describing it as inline. Compared the ordered language code/title tuples in iOS `Models/AO3Models.swift:1064–1107` and Android `network/ao3/search/AO3SearchFilters.kt:273–434`: all 162 are identical.

### tagpicker

The current Android counterpart is `search/FilterTagPicker.kt`, a searchable picker; the map's “none as its own page” is stale.

- **P2 — One-character AO3 search is missing:** iOS searches every nonempty term after 300 ms; Android calls autocomplete only for at least two characters. iOS `Features/Search/TagSelectField.swift:355–368`; Android `search/FilterTagPicker.kt:114–127`.
- **P2 — Typed, unverified names offered as results:** iOS offers the AO3 autocomplete response; Android prepends the typed comma-separated text and local candidates even after a failed/empty remote response. Thus “No tags found” can become an actionable nonexistent name. iOS `Features/Search/TagSelectField.swift:200–204,355–368`; Android `search/FilterTagPicker.kt:130–136`.
- **P3 — Selected/result order:** iOS shows selected tags as capsules and leaves selected names in Popular/Results so their include/exclude state can be cycled there; Android shows selected rows and removes those names from results. iOS `Features/Search/TagSelectField.swift:171–204,280–305`; Android `search/FilterTagPicker.kt:136,156–185`.
- **P3 — Loading content:** iOS draws four placeholder lines for searches/popular tags; Android says “Loading…”/“Searching…”. iOS `Features/Search/TagSelectField.swift:270–276`; Android `search/FilterTagPicker.kt:167–170`.

Both have include → exclude → clear, Selected, contextual popular tags, empty-fandom guidance and live writes. The picker itself has no account gate or mature-work content.

### downloaddate

Same user-facing content and save/cancel rule: Downloaded date, initially downloadedAt or dateAdded, cannot select a future day. iOS `Features/WorkDetail/WorkDetailSections.swift:571–608`; Android `works/detail/WorkDetailMyCopySheet.kt:530–551` (date conversion/caller also checked). Platform date controls excluded.

### seriespreserve

Same prompt, pacing explanation, auto-preserve toggle and threshold explanation, Preserve Entire Series, Only This Work, and Cancel. iOS `Features/WorkDetail/WorkDetailView.swift:1209–1272`; Android `works/detail/WorkDetailForms.kt:171–194`. Android's caller copies the current threshold into the prompt (`works/WorkDetailScreen.kt:939–944`), so these are not different defaults.

### bookmarkform

Same in scope: new/edit title, Notes → Tags/helper → Private → Recommend → error, one explicit Save, Cancel and busy/dismiss restrictions; notes/tags disabled while saving, toggles remain editable on both. iOS `Features/WorkDetail/AO3WorkActionsModel.swift:189–247`; Android `works/detail/WorkDetailForms.kt:128–166`. Signed-out entry is gated by the caller, not an extra form state.

### readercontents

- **P2 — Empty-TOC fallback differs:** if the publication has no TOC, Android lists its reading-order files using their titles or Section N; iOS’s builder assigns those unlisted files Other and Contents filters them all out. iOS `Features/ReaderReadium/ReadiumBook.swift:643–654`, `Reading/ReaderSection.swift:112–115`, `Features/ReaderReadium/ReaderContentsSheet.swift:105`; Android `reader/ReaderTocBuilder.kt:21–30`.

- **P2 — Synthesized Summary missing:** iOS’s Contents uses normalized spine sections, including a Summary synthesized for the unlisted file between an AO3 Preface and Chapter 1. Android’s sheet uses raw TOC entries and does not include that file when any TOC exists. iOS `Reading/ReaderSection.swift:103–110`, `Features/ReaderReadium/ReaderContentsSheet.swift:105`; Android `reader/ReaderTocBuilder.kt:21–22`, `reader/ReaderScreen.kt:376,948`.
- **P3 — TOC order/hierarchy:** iOS has one outermost entry per spine item in spine order; Android flattens the EPUB TOC in document order, keeps nested entries sharing the same file/fragment, and indents by depth. This can show different chapter rows/order for imported EPUBs with nested/grouping entries. iOS `Features/ReaderReadium/ReadiumBook.swift:643–654`, `Reading/ReaderSection.swift:86–101`; Android `reader/ReaderTocBuilder.kt:21–45`, `reader/ReaderContentsSheet.kt:150`.

- **P2 — Bookmark notes disappear from the list:** iOS's shared annotation row displays selected text and up to three lines of note for bookmarks as well as highlights; Android's BookmarkRow displays only chapter and percent. A bookmark created with Contents → Add Note can have a real note but no preview in Android's Bookmarks tab. iOS `Features/ReaderReadium/ReaderContentsSheet.swift:183–187,206–251`; Android `reader/ReaderContentsSheet.kt:227–262`, `reader/ReaderScreen.kt:416–419`.
- **P2 — Highlight previews lose text:** iOS permits two chapter-title lines and three note lines; Android permits only one title line and two note lines, at all text sizes. iOS `Features/ReaderReadium/ReaderContentsSheet.swift:219–251`; Android `reader/ReaderContentsSheet.kt:294–300,335–341`.
- **P3 — Empty Contents:** Android says “No Chapters / No chapters available.”; iOS renders an empty list. iOS `Features/ReaderReadium/ReaderContentsSheet.swift:103–169`; Android `reader/ReaderContentsSheet.kt:116–122`.
- **P3 — Bookmark percent order:** beside chapter title on iOS, below it on Android. iOS `Features/ReaderReadium/ReaderContentsSheet.swift:218–232`; Android `reader/ReaderContentsSheet.kt:244–257`.

Same three tabs, chapter title limits (2 ordinary/5 accessibility), known-start percentages and conditional Go/Bookmark/Add Note. Highlight and bookmark deletion are immediate on both. Reader-local content has no mature Blur/Hide branch on these sheets.

### readerfind

- **P2 — Same-page bookmark can be duplicated:** iOS resolves a search locator to a Readium position and reuses the bookmark already at that position. Android only deduplicates identical stored locator strings, so a toolbar bookmark and a Find result bookmark for the same page can coexist. Repeating the identical Find result is deduplicated on current Android (the older DECISIONS entry’s identical-result gap is fixed). iOS `Features/ReaderReadium/ReadiumReaderView.swift:779–817`; Android `reader/ReaderScreen.kt:886–896`, `reader/AnnotationRepository.kt:74–79`.

- **P2 — Search field loses its spoken label when nonempty:** iOS names its TextField Find in Work; Android's BasicTextField has no label/semantics and its decoration disappears once typing begins. iOS `Features/ReaderReadium/ReaderSearchView.swift:287–296`; Android `reader/ReaderSearchSheet.kt:161–201`.

Same one-letter work search, 350 ms debounce, current-chapter-first grouping, up to 40 automatic pages to reach that chapter, near-end loading, five-line excerpts, Go/Bookmark/Copy and matching idle/error states. iOS `Features/ReaderReadium/ReaderSearchView.swift:34–444`; Android `reader/ReaderSearch.kt:24–190`, `reader/ReaderSearchSheet.kt:98–371`. Both current excerpt wrappers cap leading context at 70 characters; different toolkit-produced surrounding text was not inferred to be an app-code defect.

### readerdisplay

- **P2 — Read Aloud controls missing in this sheet:** iOS includes Audition Voice, Engine, Read author's notes, Developer Settings, Reset Read Aloud, and (on the non-Core-ML path) Kokoro model/compute choices and their conditional notices. Android Display includes only voice, pronunciations, speed, pitch and a not-installed pack action. Some missing controls exist in Android's separate Listening/Read Aloud sheet, but they cannot be used from Display as on iOS. iOS `Settings/SettingsView.swift:54–62`, `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:65–199`; Android `reader/ReaderScreen.kt:1187–1252`.
- **P2 — Pack state/disclosure omitted:** iOS's separate pack section reports ready/installing/downloading/failure and explains where the download comes from and what connection information the provider sees; Android Display hides the pack row entirely once installed and omits the section's disclosure/footer. Its download action does ask before fetching (caller), so this is a missing in-sheet status/explanation, not an unconfirmed download. iOS `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:236–310,313–407,483–491`; Android `reader/ReaderScreen.kt:1241–1251`.
- **P2 — Two switches have no spoken label:** iOS titles Two-page spread and Keep screen awake. Android's trailing SubjectToggle calls provide no contentDescription, and SubjectFormRow does not merge its separate label into that switch. iOS `Settings/SettingsView.swift:128–138`; Android `reader/ReaderScreen.kt:1167–1183`, `ui/subject/SubjectToggle.kt:31–67`, `ui/subject/SubjectForm.kt:152–197`.
- **P3 — Voice metadata missing:** iOS's picker shows each voice's quality/language and what Automatic currently selects; Android's Display voice chips show names only. It hides Voice entirely if the list is empty, while iOS retains its Voice destination. iOS `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:136–140,578–638`; Android `reader/ReaderScreen.kt:1189–1217`.
- **P3 — Speed value words:** iOS says Default at 1.0 and otherwise a percentage, and names the control “Read-aloud speed”; Android says e.g. 1.0× and labels it Speed. Pitch otherwise has the matching spoken name. iOS `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:160–184,641–648`; Android `reader/ReaderScreen.kt:1220–1237`.
- **P3 — Two-page availability:** iOS offers the toggle on iPad independently of current width (the reader calls ReaderOptionsForm with its default availability); Android normally hides it below 600 dp and only checks scroll mode for enabling. iOS `Settings/SettingsView.swift:109–114,128–130`, `Features/ReaderReadium/ReadiumReaderView.swift:1666`; Android `reader/ReaderScreen.kt:1091,1167–1175`.

Appearance → Text Size → Reading → Read Aloud → Font ordering matches apart from iOS's speech audition/pack groups preceding its Read Aloud controls. Font face differences are excluded as requested.

### readernote

Same in scope: optional Highlighted passage, Note, six colour/underline choices, immediate colour changes and last-used colour, Cancel restores the opening colour and discards draft, Done trims/saves, other dismissal saves draft, immediate Delete Highlight, focus on opening. iOS `Features/ReaderReadium/ReaderNoteEditor.swift:8–111`; Android `reader/ReaderNoteEditor.kt:59–169`, `reader/ReaderScreen.kt:905–929`. No missing state-specific content verified.

### pronunciations

- **P2 — Storage errors are only explained on Android:** it reports unreadable corrections, failed Paste saves and failed deletes. iOS substitutes an empty override set or ignores store-write errors, and Paste still announces Added N corrections. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:188–191,217–225,245–253,331–332`; Android `settings/PronunciationSettings.kt:82–87,113–119,145–151`.

- **P2 — Saved corrections do not change speech on current Android:** iOS installs the resolved custom lexicon before synthesizing; Android passes a lexicon path to a frontend its own code states ignores it, and the device voice has no word-to-IPA API. This is a **known documented functional gap**, not new discovery; its extra explanatory notice is excluded from wording findings. iOS `Features/ReaderReadium/CoreMLKokoroTTSService.swift:74–79`; Android `reader/speech/KokoroTTSController.kt:93–108`, `reader/speech/AutomaticTTSService.kt:117`; DECISIONS 2026-10-20.

- **P2 — Guessed-word list missing:** iOS can show “Words I guessed at”, frequency counts, dictionary explanation, tap-to-correct and dismiss actions, with guessed words hidden once corrected. Android only loads saved corrections and never renders guesses. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:74–135,188–214,269–271`; Android `settings/PronunciationSettings.kt:76–89,131–160`.
- **P2 — Scan this chapter missing:** when opened from the reader's speech settings, iOS offers the scan action, busy state and success/error messages; Android's pronunciation sheet accepts no chapter/scan callback. This row is correctly absent on iOS when opened from general Settings. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:24–30,55–71,274–323`, `Features/ReaderReadium/ReadiumReaderView.swift:270`; Android `settings/PronunciationSettings.kt:53–72,131–160`.
- **P3 — Natural sort:** iOS uses localized standard ordering (numeric portions naturally ordered), Android sorts lowercase keys lexically then exact key. For word2/word10 the order differs. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:188–191`; Android `settings/PronunciationSettings.kt:84–85`.
- **P3 — Import/copy result presentation:** iOS opens “Pasted Corrections” with the result after either Paste or Copy; Android appends the same result text as a footnote at the list's end. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:165–168,233–265`; Android `settings/PronunciationSettings.kt:106–125,159`.

Add/edit/delete, Paste format, Copy All and empty wording otherwise match. Android's extra engine-limit/backups notice is excluded per DECISIONS, 2026-10-20; the functional limitation is identified above as a known gap.

### pronunciationedit

- **P2 — Failed save is visible only on Android:** iOS dismisses after its callback even when the store write failed; Android keeps the editor and says “Could not save correction. Try again.” iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:217–225,407–409`; Android `settings/PronunciationSettings.kt:195–205`.

- **P2 — Respelling conversion and preview missing:** with the voice pack installed, iOS accepts syllable respellings, previews Phonemes, and saves resolved IPA; Android saves the raw typed value and never provides a Phonemes preview. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:356–395,407–409,425–437`; Android `settings/PronunciationSettings.kt:172–205`. The documented Android engine limitation explains its different helper/notice; those extra words are not separate findings.
- **P3 — Title follows different text:** iOS title follows the edited word, changing from Add Pronunciation as soon as it is typed; Android title uses the word passed when opening and stays Add Pronunciation for a new entry. iOS `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:400`; Android `settings/PronunciationSettings.kt:182`.

### customizetheme

- **P3 — Preview scrolls only on Android:** iOS explicitly disables scrolling of the sample WebView; Android hides the scrollbars but leaves its WebView scrollable, so dragging within the preview can reveal other sample paragraphs. iOS `Features/Reader/CustomizeThemeView.swift:287–295`; Android `reader/CustomizeThemeSheet.kt:150–168`.
- **P3 — Extra visible values:** iOS prints a numerical value only for Line Spacing (all four sliders expose numerical accessibility values). Android prints two-decimal values on all four sliders. iOS `Features/Reader/CustomizeThemeView.swift:82–90,227–254`; Android `reader/CustomizeThemeSheet.kt:223–237,257–261`.

Same preview/theme choices, Text → Accessibility & Layout → Reset Theme order, Bold independent of Customize, disabled layout controls while Customize is off, exact layout ranges/defaults and immediate persistence. Reset leaves theme/text size/reading mode unchanged on both. iOS `Features/Reader/CustomizeThemeView.swift:56–270`, `Features/Reader/ReaderStyle.swift:236–252`; Android `reader/CustomizeThemeSheet.kt:82–261`, `data/preferences/SettingsRepository.kt:295–305`. Font faces and platform slider/chrome differences excluded.

### formattingtray

- **P2 — Ordinary formatting closes the tray:** iOS applies every tile and stays open for another format until Done. Android dismisses after every tile except Heading, making multi-step formatting behave differently. iOS `Features/Comments/CommentMarkup.swift:415–418,457–465`; Android `comments/CommentMarkup.kt:290–296`.

Same 15 tags, Text then Blocks & links order, h1–h6 controls/default h3, caret placement for link URL/spoiler summary, selected-text preservation for Divider and one-item-per-line lists. Accessibility grids match the documented mapping (4 → 2 → 1 columns); iOS `Features/Comments/CommentMarkup.swift:343–358`; Android `comments/CommentMarkup.kt:226–238`. Both retain full tag/action names for accessibility; platform icon/control appearance excluded.

### chapterpicker

- **P2 — Long list has no scroll container:** iOS lists all chapters in a scrolling List. Android puts every chapter in an ordinary Column/for loop with no scrolling modifier. Many chapters or the largest text can put chapters and the footer outside the sheet's reachable area (**suspected clipping**; missing scroll is verified). iOS `Features/Comments/CommentsView.swift:1004–1063`; Android `comments/CommentsScreen.kt:771–900`.
- **P2 — Detailed failure reason lost:** iOS shows the actual `chaptersFailureMessage` with the connection sentence only as fallback; Android accepts only a failed Boolean and always shows “Check your connection and try again.” An authentication/refusal/parser failure therefore loses its explanation. iOS `Features/Comments/CommentsView.swift:1072–1080`; Android `comments/CommentsScreen.kt:752–761,828–838`.
- **P3 — All Comments selection mark missing:** iOS includes a checkmark when All is selected; Android indicates All only by colour/fill/weight, with no selected semantics. Its chapter checkmarks are also silent rather than exposing selection. iOS `Features/Comments/CommentsView.swift:1021–1024,1046–1048`; Android `comments/CommentsScreen.kt:787–823,849–887`.
- **P3 — Total number formatting:** iOS formats All Comments' count for the locale; Android uses an ungrouped integer string. iOS `Features/Comments/CommentsView.swift:1015–1016`; Android `comments/CommentsScreen.kt:815–820`.
- **P3 — Empty-success state:** iOS shows a spinner whenever chapters remain empty and no failure is recorded; Android's spinner requires `chaptersLoading`, so an empty successful response leaves only All Comments and the footer. iOS `Features/Comments/CommentsView.swift:1071–1085`; Android `comments/CommentsScreen.kt:828–844`.

Both choose a scope immediately and close the picker; same chapter names (one-line limit even at large text), All Comments first and no per-chapter totals. The shared failure/list state is populated for the current signed-in or signed-out session by the callers.
