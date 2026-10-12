# 3de: a work's comments beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,633 (one new test). Pictures: `shots/3de/`.
Both demos answer with the same comments page. (iOS's `comments` debug route is a
component preview, not the page: the page is reached from an AO3 work's "All comments".)

## Fixed

1. **Two creators read as one name.** The header said "Calytrix Second Pseud". iOS:
   "Calytrix, Second Pseud". The comma is there now.
2. **"Latest" was not the latest, and was a day.** The figure took the first comment's
   date, which under "Oldest" is the oldest one, and printed "Jul 8, 2026". iOS takes the
   newest and says how long ago: "3mo ago". Android does now
   (`AO3CommentTimestamp.relativeNarrow`, with a test).
3. **A guest was not said to be one.** iOS draws "Guest" beside a guest's name. Android's
   thread drew a pill for the author and the reader only. A guest has a quiet pill now.
4. **The chapter pill said "on Chapter 3".** That is AO3's phrase in a sentence. The pill
   says "Chapter 3", as iOS's.
5. **The composer's count said "10000 left".** "10,000 left", as iOS.

Seen in Sepia beside the iPhone's, in Dark and at 2.0×; the composer opened for its count.

## Found, not fixed here: the order (next, 3df)

**iOS opens comments newest first; Android opens oldest first, and Android's "Newest" is
not iOS's.** iOS's newest-first starts at the work's *last* page (it reads page 1 once to
learn how many there are, then the last) and turns that page over. Android's "Newest
First" only turns over the page it already has, which is AO3's first, so it shows the
newest of the oldest twenty. To match, Android reads two pages where it reads one when
comments are opened, as iOS does. That is a change to what is asked of AO3, so it gets a
brief of its own, with the count of reads tested.

## Left

- Android writes "Reply" beside the reply arrow; iOS shows the arrow alone.
- The page's title is the comments page's own on Android ("A Test Work" in the demo) and
  the work's as it was opened on iOS. On AO3 the two are the same.

## Not checked

- Replying, editing, deleting, a collapsed thread, "Browse comments by chapter", a
  chapter's comments, the Inbox's comment rows (they have their own badge code).
