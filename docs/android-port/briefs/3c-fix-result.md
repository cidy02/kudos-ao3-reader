# 3c-fix result

The queue page now follows the iOS Neon reread layout. Changes are uncommitted.

**Up Next** is a ledger card on the subject wash: Home's reading ring, fandom kicker, title, author · words · chapters, and the status icon grid. **In Line** defaults to compact, a two-column grid of Home cover cards. "…" › Display switches to list mode, which uses the same ledger for every row. The menu label shows the current mode (`Display · Compact` or `Display · List`).

**Hide mature** is the first overflow item when the saved privacy setting hides mature content. The label is "Show mature" or "Hide mature". It calls `PrivacyGate.toggleRevealAll` and does not write the setting. With the default Obscure mode, mature covers and list rows blur and show "Tap to reveal" until the session reveal.

**Keep works offline** fetches through the existing `DownloadQueue`. Turning the flag on, or adding a work to a queue that already keeps, enqueues AO3 works with no EPUB on disk that are not soft-deleted. A missing file whose `hasEpub` flag is set is enqueued with `force`, so the queue does not skip it. Turning the flag off enqueues nothing and deletes nothing. A work already in the queue is not fetched again. `ReadingQueueRepositoryTest.keepOfflineFetchesMissingAo3FilesOnlyWhenTurningOnOrAdding` covers this.

**SubjectToggle** (`ui/subject`) is a 51×31 switch: accent track when on, glass track when off, white thumb. The queue sheet and Queue details use it. The filter dialog still uses Material `Switch`.

Offline `:app:assembleDebug` and `:app:testDebugUnitTest` passed. Dark emulator shots are in `docs/android-port/shots/3c-fix/` (page, scrolled, menu, list, revealed list, sheet on/off, details). Pull to refresh was not exercised. Opening Sodium Lights during capture wrote its on-device progress to 0%; `dark-queue.png` was taken before that and shows the 42% ring.
