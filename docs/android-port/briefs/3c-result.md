# 3c result — Reading queues

Home's queue See all opens the organizer. A queue page uses that queue's wash, Up Next and In Line, list and compact grid, and a top-right toolbar (Add Works, Filter, …). New Queue and Edit Queue are one sheet. Long-press on a Home deck card or an organizer row offers Edit, Pin/Unpin, and Delete. Queue details and the tag manager edit notes, colour, keep-offline, and tags. `ReadingQueueRepository` gained update, pin, reorder, and tag functions, each covered by a unit test.

## iOS → Kotlin

| iOS | Kotlin |
|---|---|
| `AllReadingQueuesGridView` | `library/QueueOrganizerScreen.kt` |
| `ReadingQueueBrowser` | `library/QueuePageScreen.kt`, `ReadingQueueBrowserScreen.kt` |
| `ReadingQueueFacts` | `library/ReadingQueueFacts.kt` |
| Progress strip, peek tile, ledger, header details, card menu, swipe | `library/QueueChrome.kt` |
| `NewReadingQueueSheet` / Edit Queue | `library/QueueEditorSheet.kt` |
| `SubjectHueSwatchRow` | `ui/subject/SubjectForm.kt` |
| `ReadingQueueSettingsView` | `library/QueueSettingsScreen.kt` (the route stays `QueueDetailScreen`) |
| `QueueTagManagerView`, `QueueTagSheet` | `library/QueueTags.kt` |
| `ReadingQueueService.updateQueue` and tag edits | `library/ReadingQueueRepository.kt` |
| Home toolbar circles, `WorkStatusIconGrid` | `GlassCircleButton` diameter at tab roots; `home/HomeCoverCard.kt` |

## Differences

- Android has no system colour picker. The dashed "+" opens an HSV square and a hue slider. The picked colour is stored as `colorHex`, and `hue` is set from it. The sheet wash follows that colour.
- There is no queue `lastModifiedAt` column. Writes stamp `dateUpdated`. Reordering works already stamps each membership's `lastModifiedAt`.
- Turning keep-offline on stores the flag and does not start EPUB fetches. A switch that is still on leaves a never-asked null alone. Create from the sheet stores an explicit boolean. A duplicate custom name returns the existing row and does not apply the new sheet.
- Tab-root glass circles are visibly 44dp, with 17sp glyphs, and "+" uses the accent. iOS draws a 34pt circle inside a 44pt hit target, and Home's iOS toolbar is the system bar.
- The bottom `QueueSwitcherBar` is gone (T-343). Select and reorder live in "…".
- Hide mature is not on the page menu. Wiring it would edit Library and privacy.
- The DAO still breaks membership ties by `queuedAt` ascending. The page sorts `queuedAt` descending when it loads.
- "Show only this tag" sets `QueueShowOnlyTag`. The page reads it once when details pops.
- Pull to refresh calls metadata refresh when that callback is set. These screenshot runs did not pull.

## Verify

`:app:assembleDebug` and `:app:testDebugUnitTest` passed offline. The Pixel `66140DLKX007NK` was on the lock screen, so the shots are from `emulator-5554`, Dark and Sepia, in `docs/android-port/shots/3c/`. The organizer and the Neon reread page fit on one screen, so those scrolled shots match the unscrolled ones. The New Queue sheet's scrolled shots show tags, keep-offline, description, and Start from. This emulator's offline total is 25 KB. This file is `3c-result.md` so the Home result in `3a-result.md` stays as it is.
