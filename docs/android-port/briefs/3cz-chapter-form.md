# 3cz: the chapter form and the chapters list beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,631. Pictures: `shots/3cz/`.

They could not be compared until iOS's demo had the pages. It has them now (iOS **T-400**:
four of Android's demo pages copied into `KudosTests/Fixtures` and four addresses added to
`DemoNetworkBlock.routes`). iOS's parsers read Android's pages as written. On Android the
chapter form is in the demo for works 995006 and 995001; 3cx tried 995008, which has none.

## Compared

- **Add chapter** and **Edit chapter**, top to foot: the same sections (Chapter, Text,
  Publication, Post) and the same rows and notes in each.
- **Chapters**: the same list (a chapter, its date, a chevron).

## Fixed

1. **The form's Post rows were two plain lines of text.** iOS draws "Post chapter now"
   and "Save chapter changes" in green behind an up arrow, and "Save as draft" behind a
   page, as both apps' work form does. Android's chapter form uses the work form's row now
   (`WritingPostRow`), which also carries the spinner while it sends.
2. **"Publication date" looked fixed.** 3cr marked the work form's date as a choice; the
   chapter form has a row of its own, missed then. It is in the accent with "⌄" now.

Seen in Sepia beside the iPhone's, in Dark, and at 2.0×; the date row opens its sheet.

## Found, for the next pass (3da)

**A series's page.** iOS opens it with the series's own card at the top (its creator,
fandom, summary, "3 works · 45,678 words · 62 bookmarks", Complete, Restricted, the date)
over "WORKS 2". Android's has the title and "Works · Page 1 of 1" and none of the rest,
though the page it reads carries the creator, the description and the figures. And each
work's card there has its date on iOS and none on Android.

## Not checked

- A series's edit form on iOS: its "…" menu on the series page has no "Edit series" for
  the demo's series (Android offers Edit and Reorder from the series card's menu).
- Posting or saving a chapter (a write; fixtures only, and not run here).
