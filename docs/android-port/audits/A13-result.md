# A13: Android controls a screen reader cannot name

## 1. Counts

* **Files read:** 449
* **Hits examined:** 285
* **Findings by kind:**
  * Kind 1: 0
  * Kind 2: 0
  * Kind 3: 4
  * Kind 4: 0

## 2. Findings

| File | Kind | Code | What it does | iOS Label |
|---|---|---|---|---|
| `android/app/src/main/java/io/github/cidy02/kudos/library/CollectionDetailScreen.kt:1062` | 3 | `modifier = Modifier.fillMaxWidth().clickable { val current = selectedIds[work.id] ?: false; selectedIds[work.id] = !current }.padding(vertical = 4.dp)` | Toggles whether the work is selected to be added to or removed from the collection | no iOS counterpart found |
| `android/app/src/main/java/io/github/cidy02/kudos/library/WorkMembershipDialogs.kt:167` | 3 | `modifier = Modifier.fillMaxWidth().clickable(enabled = membershipLoaded) { val next = !isMember; memberIds = if (next) { memberIds + collection.id } else { memberIds - collection.id }; onSetMembership(collection.id, next) }.padding(vertical = 2.dp)` | Toggles whether a work is a member of the collection | `"In this collection"` (`kudos-ao3-reader/Features/Library/Collections.swift:624`) |
| `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt:693` | 3 | `modifier = Modifier.fillMaxWidth().clickable { includeSeriesInQueue = !includeSeriesInQueue }.padding(vertical = 8.dp)` | Toggles whether to also add works from the same AO3 series to the new queue | no iOS counterpart found |
| `android/app/src/main/java/io/github/cidy02/kudos/works/DownloadDateImportConfirmation.kt:166` | 3 | `modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(10.dp)` | Selects a choice for batch applying a download date | no iOS counterpart found |

## 3. What I did not read

I did not read files with "Demo" or "Debug" in their name, files outside `android/app/src/main/java/io/github/cidy02/kudos/`, and Swift files in `kudos-ao3-reader/` outside of searching for iOS counterparts. I also did not examine rows where the container explicitly merges text or sets `semantics { contentDescription = … }` or `.toggleable`/`.selectable` modifiers, as these are correctly announced by TalkBack.

## Triage (Claude, 2026-10-08)

**Not a clean bill.** The check reported no icon-only or colour-only control without a name,
and missed one already known from audit A7: the highlight colour swatches in the reader's
older annotation sheet (`reader/ReaderScreen.kt`), a tappable colour with a name only on the
chosen swatch's tick. So "0 of kinds 1, 2 and 4" means "none found", not "none there".

Fixed: its four findings (two checkbox rows, a switch row and a radio row whose state was not
announced: now `toggleable` / `selectable` with a role, one control each) and the swatches
(a radio role, a name and a selected state on every swatch). Not checked with TalkBack on a
device.

Seen and left: a section header's collapse arrow is a 10sp touch target
(`ui/subject/SubjectComponents.kt`, `SectionRuleHeader`).
