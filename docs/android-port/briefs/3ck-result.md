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

## Still to do

- A queue's page in Select mode: Download, Move to, Tag, Remove from Queue, and More.
- A collection's page in Select mode: Remove from Collection and an Actions menu.
- Move to (add, then remove only what joined) and Download missing copies.
- iOS's words for the removal confirmation on both pages.
