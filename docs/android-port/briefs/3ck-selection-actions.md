# Brief 3ck: what a selection of works can do on a queue's page, a collection's page and in the Library (Android)

Found 2026-10-11 by comparing the two apps' menus (61 iOS menu and toolbar labels with a fixed
title; these were the ones with no counterpart outside Read Aloud). **Android only. P2.**

## What differs

| Where, in Select mode | iOS | Android |
|---|---|---|
| A queue's page | **Download · Move to · Tag · Remove from Queue**, and "…" with Save / Favorite / Saved for Later / Add to Queue / Add to Collection / Mark Finished (`ScopedRemovalBulkActionBar`, `showsQueueActions`, artboard 1bg) | Select All, **Remove**, Done |
| A collection's page | **Remove from Collection**, and "Actions" with the same five, **Move to Queue**, **Tag**, **Download missing copies**, Mark Finished | Remove from Collection, Done |
| The Library | Delete, and "Actions" with … Add to Queue, Add to Collection, **Tag** (`WorkBulkActionBar.swift:94`) | Delete, Actions (no Tag) |

So on Android a selection in a queue or a collection can only be removed, and **there is no
way to tag several works at once anywhere**.

## What iOS does

- `UIComponents/ScopedRemovalBulkActionBar.swift`: the bar for both pages. Removal is asked
  first: "Remove N work(s)?", "Kudos will remove the selected works from this queue
  (collection). They will stay in your Library.", Remove / Cancel.
- **Move to** (`startMove`): the Add to Queue picker; when it closes, the works leave this
  queue **only if the selection joined something** (the count of memberships before and
  after), so Cancel moves nothing.
- **Tag** (`UIComponents/WorkBulkTagSheet.swift`, artboard 1af): a "New tag" field with Add;
  "Your changes apply to all N selected works."; "Your tags", each in one of three states
  across the selection (on every work, on some, on none), a tap putting it on all or taking
  it off all. Local only: nothing touches AO3.
- **Download** / **Download missing copies** (`bulkDownload`): for the selected works with no
  readable copy, one after another (never in parallel), a failure on one not stopping the
  rest. Off when none is missing.

## What to build

1. `WorkBulkTagSheet` for Android (a bottom sheet): the three states, the new-tag field,
   iOS's words. Pure rules apart from the drawing (coverage of a tag across works; what a tap
   does) with tests. It writes through the existing user-tag functions of `WorkRepository`.
2. The Library's Actions gets **Tag**.
3. A queue's page in Select mode: Download, Move to, Tag, Remove from Queue, and a "More"
   menu with the Library's actions. Reuse `ui/components/WorkBulkActionBar.kt`'s operations
   rather than writing them again (it needs a `WorkRepository`; the queue page has none
   today: pass it from the nav host).
4. A collection's page in Select mode: Remove from Collection and an Actions menu with the
   same items.
5. Move to: `ReadingQueueRepository.addWork` to the chosen queue, then `removeWork` from this
   one, only for works that did join.
6. Download missing copies: `DownloadQueue.enqueueLocal(..., force = false)` for selected
   works with no EPUB and an AO3 address, through the queue (paced, one at a time). A
   user-started download of works already in the Library: within the networking policy as
   it stands; say so in the result.
7. iOS's words for the removal confirmation on both pages.

Tests: the tag coverage rule; Move to moves only what joined and Cancel moves nothing;
Download asks only for works without a copy; the removal words. Look at each on the emulator.
