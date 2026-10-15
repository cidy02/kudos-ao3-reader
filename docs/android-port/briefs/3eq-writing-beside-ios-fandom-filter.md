# 3eq: Writing beside the iPhone's; an author's fandom filter (Android)

Done 2026-10-15 by Claude. Gate 2,673. Pictures: `shots/3eq/`.

## Compared (never before): Drafts, Works, Series, Edit work

- **Edit work**, top to bottom against iOS's `acct:workedit:`: the same sections in the same
  order (Required, Tags, Association, Text, Publication, Delete), the same rows and switches,
  and the menu rows show their value in the accent with Android's choice mark (3cr). Android's
  subtitle adds the chapter count. Nothing to change.
- **Drafts:** the same head, note and rows (the demos' drafts differ).
- **Series:** the same rows. Android pages with Previous/Next where iOS loads more (recorded
  in 3ce); Android's own Series page carries the profile tabs (Works, Series, Bookmarks, About)
  that iOS's account list has not: the profile page design (3l), kept.
- **Works:** iOS has a **Fandom** row of chips (All, then each fandom with its count) under the
  scope chips. Android read that list from AO3 (`AO3AuthorHeader.fandoms`) and had the read
  for one fandom's works (`loadFandomWorks`), but no screen ever offered it.

## Fixed: the fandom filter on an author's Works

`AuthorProfileScreen`: under Works / In collections / Gifts, on the plain Works list only (as
iOS: AO3 offers the facet there alone), "Fandom" and a row of chips, "All" and each fandom's
bare title with its count. A chip reads that fandom's works; the totals line under "Works"
gives way to the name while one is chosen (it counts the whole list). Seen on the emulator:
the row, and Star Wars (12) chosen.

## Lead

Opening an author's page, the "Loading author profile" card sits under the top bar for a
moment.
