# 3cm: six pages put beside the iPhone's (Android)

Done 2026-10-11 by Claude, alone (Codex and Gemini were out). Gate 2,603. Two commits.
Method: the same page in the demo on both, at the ordinary text size in Sepia, the two
pictures joined. It found 3cl; this is the next six. Pictures: `shots/3cm/`.

## Fixed

1. **Inbox, a name cut with room to spare.** "Driveby Guest" was "Driveby…". The name and a
   spacer had equal weight, so the name was held to half the row. The name and its badge now
   share what the date and "Replied" leave.
2. **Inbox, "User" on every commenter.** iOS gives a chip only to a role that says something
   (Author, Me, Guest); Android's Inbox still drew "User". It no longer does. (The comment
   thread's own badge already left it out.)
3. **A commenter with no icon is their first letter**, in the Inbox and in comment threads,
   as on iOS; a guest keeps the silhouette. `avatarInitial` takes a whole character (an
   emoji is one letter); `AvatarInitialTest`. The letter is sized with the circle, not with
   the text size, and is not spoken.
4. **AO3 Preferences, a section folds away.** iOS has a chevron beside each section's "?";
   Android had the state for it and nothing that used it. It is there now ("Collapse
   Privacy" / "Expand Privacy"), kept for the visit only, as on iOS.
5. **AO3 Preferences, the Account rows have their icons** (`SubjectFormRow` may lead with
   one).
6. **Queues, the search field is the app's glass field**, not an outlined box.
7. **Collections, the header stood 26dp in from its tiles.** The header took its own gutter
   inside a grid that was already padded.

8. **AO3 collections, the card is the collection's own** (second commit). Each card takes
   its hue from its title, as on iOS and as a queue carries a colour; the glyph is a box; a
   maintainer's name is in the accent and opens their profile; and the "by" line is drawn
   only when it adds someone to the kicker (you own it, or there are several), so "by
   festrunner" no longer repeats "FESTRUNNER" (`AO3CollectionCardCopy.showsByline`, tested).
   The chevron had its padding inside its size and was squeezed; it is a form row's 18dp.
   Looked at in Sepia, Dark and at twice the text size, and a name tapped (it opened the
   maintainer's works in the demo).

## Seen, and left

- **Chevrons at 12dp** (the fandom list's among them) draw an arrow about half the size of
  the iPhone's. Not changed across the app; a lead.
- **A fandom's works.** The pair was not like for like (Android's fandom page beside iOS's
  search results), so nothing is concluded. To be paired properly.
- Page controls: Android's row of four arrows where iOS has a pill. Android's own bar, kept.
- Collections: iOS centres its two tiles; Android's start at the left edge. Left.

## Not checked

- The letters in a comment thread were not looked at (the Inbox's were; the same composable).
- Nothing was looked at in Dark or at a larger text size. The Inbox row's large-text layout
  is a separate branch and was not changed.
- **A mistake caught by looking:** the Collections fix was also applied to Home's section
  pages from reading the code. "Reading Now" then stood flush against the screen edge (that
  page is not the padded grid). Taken back before the gate that was committed on.
