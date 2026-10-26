# Kudos iOS — current-app screenshots (evidence for the design critique)

Captured from the current iOS build (branch `claude/polish-loop`, DEBUG demo library) on an
iPhone 17 Pro simulator, iOS 27.0, unless noted. The demo library seeds a few sample works; its
EPUBs are placeholders, so the reader screenshot (06) is from an earlier session's real book.
The simulator had no network, so AO3-backed pages show their offline state.

| File | What it shows | Caveats |
|---|---|---|
| 01-home.jpg | Home tab: Continue Reading hero (fandom-tinted card, progress ring, Resume), Reading Now cards (one blurred mature work, "Tap to reveal"), Reading Queues shelf, tab bar | Demo data |
| 02-library-reading-now-list.jpg | Library › Reading Now list: hero wash header, kicker "LIBRARY", filter pills, work cards with tag chips and stats | Demo data |
| 03-reading-queue.jpg | A Reading Queue ("Neon reread"): header stats, filter pills, Up Next card, blurred In Line cards | Demo data |
| 04-account-signed-out.jpg | Account tab signed out: log-in card, inert preview of rows | |
| 05-reader-display-sheet.jpg | Reader "Display & Themes" sheet (Light/Sepia/Dark/OLED, text size, scrolled/paged) over an error page | The error behind it is the demo's placeholder EPUB, not a real state |
| 06-reader-page-chrome.jpg | The reading page with its chrome: top capsule (back, title/author, menu), position card at the bottom (page, time left, slider, chapter and % of work) | Earlier session, real book |
| 07-browse-offline.jpg | Browse tab offline error state | Offline only because the simulator had no network |
| 08-sync-onboarding.jpg | "Protect Your Library" first-run sheet | |
| 09-account-signed-in-duo-cover.jpg | Signed-in Account hub (on the iPhone Duo cover display, tab rail on the right): profile header, shortcuts grid, Reading rows | Duo cover width |
| 10-home-duo-inner.jpg | Home on the Duo inner display (wider) | Duo |
| 11-library-wide-sidebar.jpg | Library on a wide screen with the sidebar | Wide layout |
| 12-add-to-queue-sheets-sepia.jpg | Add to Queue / Add to Collection sheets in the Sepia theme | |
| 13-writing-form.jpg | A writing form (Edit Work › Inspired by): hero wash, kicker, large title, grouped form | |
| 14-work-context-menu.jpg | Long-press menu on a Home card: Read, Select, Unfavorite, Save for Later, Add to Queue, Mark as Finished, Add to Collection, Work Details, Delete | |
| 15-reader-open-error.jpg | Reader opened on a demo work: "Couldn't open this EPUB" with a raw error string and no visible close button | The failure itself is the demo's placeholder file; the bare error screen is real |
| 16-work-detail.jpg | Work Detail (Winter Garden): fandom-tinted wash, kicker, title, author, Rating/Warnings/Category/Complete stat row, Reading card with ring and play, archive warnings, fandoms, language and words, kudos and hits, Mark as Finished, My copy | Demo data |
| 17-work-detail-scrolled.jpg | Same page scrolled: the large title slides under the back button instead of collapsing into a toolbar title | |
| 18-home-after-visiting-green-work.jpg | Home after returning from that work: the "+" toolbar button is now green (it was purple) | Tint follows the last fandom viewed |
