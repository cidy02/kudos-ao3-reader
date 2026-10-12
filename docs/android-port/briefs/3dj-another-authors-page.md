# 3dj: another author's page beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,639 (+4). Pictures: `shots/3dj/`. Follows 3di.

The same demo author ("Avery Writes", a pseud of Avery_Archive), opened from a work's
byline on both apps, tab by tab.

## Fixed

1. **A tapped name opened an account of that name.** The work page passed the byline's
   words, so "Avery Writes" was asked for as an account: the page said "AO3 user" and had
   none of the account's pseuds. iOS opens the account the link names. Android does now
   (`AO3AuthorIdentities.byline`, from the accounts already kept with the work); a name with
   no kept link is still read from its words, as before.
2. **A pseud of two words was kept as "Avery%20Writes".** It matched no chosen pseud, so it
   was listed twice among the chips and never ticked, and choosing it asked AO3 for
   "Avery%2520Writes", which is nobody. A fault on real pages, not only the demo. The
   address is decoded now (`routeFromPath`).
3. **A private bookmark of a work that names no fandom did not say "Private".** The badges
   were drawn on the fandom's line, and without a fandom there was no line. On the reader's
   own Bookmarks too. **iOS has the same fault** (T-402).
4. **Bookmarks tab:** the note, tags, Rec and the day are inside the work's card, as iOS and
   as the reader's own Bookmarks. They sat loose under it.
5. **About tab:** iOS's three sections, each a heading over a panel: Bio, Pseuds (a row
   each, the chosen one ticked), Account (Selected Pseud, Joined, User ID). They were loose
   lines under a second copy of the profile's title.
6. **The bio keeps its formatting**: bold, italics, lists and links (`AO3RichText`). It was
   one grey paragraph and a link could not be followed. An AO3 address opens in the app, any
   other in the browser, as iOS. The page is a stranger's writing: only plain formatting is
   kept, and a link is one only when it is http or https (`javascript:`, `intent:`, `mailto:`
   become plain words; tested).

Seen in Sepia and Dark, at 2.0×, beside the iPhone's; another pseud chosen. No link tapped.

## Left

- iOS has a "Scope" row to choose a pseud; Android has a row of chips. Android's own.
- iOS counts beside the headings ("Works 3", "Series 2"); Android has none here.
- "Load More" on iOS, Previous / Next on Android, as everywhere.
- Subscribe, Mute and Block are buttons in Android's header and in iOS's More menu.
- The cards' figures differ because the two demo pages do (Android's has more on it).
- A blank line stands between the bio's paragraph and its list.

## Leads, iOS

- T-402: the Private badge (above).
- An author's works show their day as "07/09/2026" where the series and bookmark cards say
  "08 Jul 2026". Not looked into.

## Not checked

- Comments, bookmark notes and collection introductions are still plain text on Android;
  iOS draws rich text only for the bio and the writing previews, so nothing is owed there.
- The Availability sweep's page; "Customize Theme…"; a tag's works.
