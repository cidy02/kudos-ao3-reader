# 3df: comments open on the newest, as on the iPhone (Android)

Done 2026-10-12 by Claude, alone. Gate 2,635 (two new tests). Picture: `shots/3df/`.
Found in 3de. A change to what Android asks of AO3, so it has its own brief, tests of the
number of reads, and a line in `docs/AO3_NETWORKING_POLICY.md` ("Comments").

## What was wrong

iOS opens a work's comments newest first. AO3 has no order to ask for and keeps its newest
comments on the last page, so iOS reads page 1 for the count of pages and then the last
page, and turns that page over. Android opened oldest first, and its "Newest First" only
turned over the page it already had, AO3's first: the newest of the oldest twenty. And a
comment the reader had just posted was not on the page Android then showed (page 1), on
any work with more than one page of comments.

## What it does now (`CommentsViewModel`)

- **Opens newest first**, on the work's last page (`loadStart`, iOS `CommentsModel.load`).
  Page 1 is read once for the count, then the last page. A work with one page of comments
  is one read.
- **Pages are kept while the screen is open**, five minutes each, this screen's and this
  reader's only (iOS `CommentsPageCache`). Going back a page, or changing the order, asks
  AO3 nothing it was just asked. Android re-read a page every time it was shown, so
  across a visit this asks AO3 for less than before, not more.
- **Changing the order goes to that order's first page** (page 1 or the last). One
  comment's own thread (opened from the Inbox) has one page and is only turned over.
- **A write empties what is kept**, and a new comment on the work is followed by the
  order's first page read again, which is where AO3 put it.
- Try Again and pull to refresh repeat what was asked: the page on screen, or the order's
  start if that is what failed.

Nothing is read ahead. Reads stay the reader's own: opening comments, turning a page.

## Checked

- Tests (`CommentsViewModelContextTest`): three pages of comments open with exactly two
  reads (page 1, then `page=3`), newest at the top; page 1, Oldest First and Newest First
  again are served from what was kept (still two reads); pull to refresh reads page 3
  only. One page of comments is one read.
- The emulator, beside the iPhone's: opens on "Newest", the same comment first, "Page 3
  of 3" with Previous live and Next spent; "Oldest First" shows page 1.

## Not checked

- Against AO3 (never contacted). After posting a comment (a write; not run).
- The five-minute limit itself (no test moves the clock).
- The order is not remembered between visits, on either app.
