# 3a result — Home

Home follows the iOS section order: Continue Reading (hero plus up to four more), Reading Queues, each `showsOnHome` collection, Recently Updated, Subscriptions. `SectionRuleHeader` supplies the count, collapse, and See all. Pull to refresh still runs the update check and subscription reload, and refreshes metadata for up to 24 visible works. Tap opens the reader when a file exists, otherwise work details. Long-press, select mode, and the bulk bar keep the actions Home already had.

## iOS → Kotlin

| iOS | Kotlin |
|---|---|
| `HomeResumeHero` | `home/HomeResumeHero.kt` |
| `WorkCoverCard` / `CarouselCardStyle` | `home/HomeCoverCard.kt` (`SubjectWorkCoverCard`; the old Material card is untouched) |
| `ReadingQueueCard` | `home/HomeQueueCard.kt` |
| `WorkReadingOrDownloadRing`, `downloadDimmed` | `ui/subject/WorkReadingRing.kt` |
| `WorkCarouselSection` | `home/HomeSectionsUi.kt` |
| `LocalWorkContextMenuModifier` | `home/HomeWorkMenu.kt` |
| Home select bar | `home/HomeBulkBar.kt` (Library's shared bar is unchanged) |
| Cover hue, queue footer, reading order, subscription copy | `home/HomeFacts.kt` |
| `+` / `…` on the large title | `home/HomeShellChrome.kt`, drawn by `MainScaffold` |

`HomeViewModel` still owns the dashboard. Queues load from `ReadingQueueRepository`. `createQueue` takes optional hue and keep-offline.

## Differences

- Favorites and Recently Opened stay on `HomeDashboardState` for the existing tests. They are not Home shelves; iOS does not draw them there. Select those works from Library.
- The queue face is the next work's wash. `hue` / `colorHex` tint the glass backs (`carouselQueueTint`). A queue with neither stays plain glass.
- Continue Reading's See all opens the existing Home section list. Android has no Library "reading now" route. The chevron shows only when more than five works are in progress.
- New Queue is a name, the five preset hues, and an optional "Keep works offline" box. There is no system colour picker, so `colorHex` stays null. Unchecked keep-offline leaves the flag null (keep stays on).
- The download ring sweeps while the queue says Queued or Downloading. There is no byte fraction, so it is indeterminate, and the card desaturates.
- Menu labels follow live `WorkActionLabels`: "Remove from Saved for Later", "Mark as Still Reading", "Kept Offline by {name}". The spec's shorter strings are not used.
- The author byline is text. The status tray is four signals (rating, a short category, warning, completion), not iOS's icon set.
- Fandom kickers drop one trailing ` (…)`, not the full peel table.
- Cards are a fixed 164×232. Compose shadow has no separate y, so elevation stands in. The strip's −8pt pull is an `offset`; Compose rejects negative padding.
- Subscriptions are not enriched with an extra fetch. A remote card shows the AO3 capsule and its updated date. Logged-out, failed, and empty copy match iOS. Local works in that shelf are not selectable.

## Verify

`:app:assembleDebug` and `:app:testDebugUnitTest` passed offline (`HomeFactsTest`, `HomeDashboardTest`). The Pixel keyguard was up, so shots are from `emulator-5554` (Dark and Sepia, unscrolled and scrolled) in `docs/android-port/shots/3a/`. That emulator already held the demo, so seed left those rows; the hero place line and percents follow stored locator and progress.
