# 3ck result (in parts): what a selection of works can do on Android

## Part 1, landed 2026-10-11: the bulk Tag sheet, and Tag in the Library

Gate 2,598. By Claude, alone (Codex and Gemini were out).

- `library/QueueTags.kt`: the queues' tag sheet (1i) was already this design, so its body is
  now one shared sheet (`SharedTagSheet`) with two callers: `QueueTagSheet` as before, and
  **`WorkBulkTagSheet`** for a selection of works, in iOS's words ("Tag", "Your changes apply
  to all N selected works.", "You have no tags yet. Add one above to organize your
  Library."). The coverage rule is `BulkTags.coverage` (on every one, on some, on none);
  TalkBack hears "on every selected work", "on some selected works" or "not applied".
- `WorkRepository.toggleUserTag(workIds, name)`: a tag on every selected work comes off
  them all; otherwise it goes on the rest ("some" adds, the direction that cannot lose a tag
  already on a work). A new name is made once. `userTagIdsByWork` feeds the coverage.
  Local only: nothing touches AO3.
- The Library's Actions menu has **Tag**.

Tests: `library/BulkTagsTest` (3): the three states and what is spoken; a tap adds to the
rest and only a tag on every work comes off; a new name is made once, a work outside the
selection is never touched, an empty selection and a blank name do nothing.

Seen on the emulator (demo): Library › Select › two works › Actions › Tag: "Comfort" goes to
All on a tap and off on the next; a typed "Demo" is added to both; Done returns to the
selection. (The demo on the emulator now has a tag "Demo" on no work.)

## Parts 2 and 3, landed 2026-10-11: Select mode on a queue's page and a collection's page

Gate 2,600.

- `library/ScopedSelectionBar.kt` (iOS `ScopedRemovalBulkActionBar`), one bar for both:
  - **a queue's page** (artboard 1bg): Download · Move to · Tag · Remove, and More with
    Download or Remove Download, Favorite or Unfavorite, Save for Later, Add to Queue, Add to
    Collection, Mark Finished or Unfinished. Select All and Done stay in the top bar.
  - **a collection's page**: Remove from Collection, Actions (the same, with Move to Queue,
    Tag and Download missing copies), Done.
- **Move to**: `ReadingQueueRepository.moveWorks(from, to, ids)`: each work joins the other
  queue (or is there already) and then leaves this one; a work that cannot join stays. The
  picker lists every other queue; closing it moves nothing. From a collection, the works
  join the queue and then leave the collection.
- **Download** (missing copies): the selected works with no copy on the device and an AO3
  address go to the download queue (`enqueueLocal(force = false)`), which fetches one at a
  time. A download the reader started, of works already in the Library: the same path as one
  work's Download button, so nothing new for the networking policy. Off when none is missing.
- The removal is asked in iOS's words on both pages ("Remove N works?", "Kudos will remove
  the selected works from this queue. They will stay in your Library."). The collection page
  keeps its own dialog, which honours "Confirm before delete".
- `ui/components/WorkBulkActionBar.kt`: its download toggle, its queue picker and its
  add-to-collection dialog are now functions the new bar uses too, not copies.

Tests: `ReadingQueueRepositoryTest.moveToPutsWorksInTheOtherQueueAndTakesThemOutOfThisOne`;
`AddLibraryWorksTest.aSelectionsRemovalIsAskedInTheseWordsAndOnlyMissingCopiesAreFetched`.

Seen on the emulator (demo): the queue's bar and its More menu; Move to with the picker
closed (nothing moved) and then to "Late" (Neon reread 5 to 4, Late 1 to 2); Tag for one
work; the removal words; the collection's bar, its Actions menu and its removal words.
The first build drew the bar over glass and the rows showed through its labels: it is an
opaque surface now, as the Library's selection bar.

## Not done, and not checked

- **Download was not run**: every demo work in a queue has its copy, so the button was only
  seen switched off. By the test of which works it asks for, and by reading.
- "Save for Later" in the menus only adds; iOS's item toggles.
- Move to Queue from a collection, Add to Queue and Add to Collection from the new bar were
  not tapped through (the dialogs are the Library bar's own, now shared).
- No screen-level test of the bar.
