# 3cr: the account's Series row, and the work form beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,619 (one new test). Pictures: `shots/3cr/`.

## Fixed

1. **The account's Series row opened the reader's Works.** `AuthorProfileScreen` takes the
   tab to open on (`initialTab`), and an effect that runs when the page's author changes
   set the tab back to Works. It runs on the first composition too, so the tab asked for
   never showed. The effect sets the tab the page was opened on now, and the first load
   after the header reads whichever tab is selected (it read Works only).
   Test: `AuthorProfileSortScreenTest.aPageOpenedOnSeriesShowsTheSeriesAndNeverAsksForTheWorks`.
2. **A row that opens a choice looked like a value that cannot be changed.** Rating,
   Language, Work skin and Who can comment were grey text with nothing after them; iOS
   draws its pickers in the accent with a mark. `SubjectFormRow(showsChoice = true)` draws
   the value in the accent with a "⌄" after it (the mark the collection items' approval
   chip already uses). Also on: the publication date and its Year, Month and Day rows,
   "Language of the source", a challenge's dates, and "Invite as". Nothing is drawn while
   the row cannot be tapped.
3. **The required mark "∗" was in the ink colour.** iOS tints it. It is in the accent now,
   on every form row and field (`formLabelText`). What a screen reader says is unchanged.

## Compared and the same

The Edit work form, top to foot, for a posted work on both (Android "The Locked Lantern",
iOS "The Weight of Water"): the same sections in the same order (Required, Tags,
Association, Text, Publication, Delete) and the same rows in each. Android adds the
chapter count to the subtitle and to the Chapters row.

## Not checked

- A draft's form was pictured on Android only (iOS's side was a posted work).
- Edit tags, the chapter form and a series's edit form were not compared.
- The own Series page keeps the profile's four tabs on Android; iOS's is a plain list. Its
  cards differ (next: 3cs).
- Changing the text size while the form was open sent the emulator back to the page the
  debug route names. That is the debug route being applied again when the activity is
  recreated (debug builds only). **Lead, not checked:** whether a form being written
  survives the activity being recreated in ordinary use (the system switching to dark at
  sunset, a text-size change). Rotation does not recreate it (`configChanges`).
