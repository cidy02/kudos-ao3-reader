# 3dv: a fandom's works page takes the results' own head (Android)

Done 2026-10-14 by Claude, alone. Gate 2,648. Pictures: `shots/3dv/`. Follows 3du.

## What differed

From Browse, a fandom's works page on iOS opens with spec 1k's page head, as Search does:
"Search results", the count as the title, the subject with a sort menu beside it, the
four-figure strip, the active filters. Android stacked three heads: "Browse / <fandom>",
the older results card (subject, count, "Sort: Date Updated", 1–20), and "Works · Page 1 of
3".

## Fixed

The page draws `SearchResultsHero` in its page shape (`SearchHeroPresentation.SubjectPage`,
as Search), with the sort menu (no Best Match: a tag listing has none, as iOS). The fandom's
name heads the page only until the works are in. The list lost its side padding (the head
carries its own margins, as on Search); the rows and pagers took it. The sort was changed.

Seen in Sepia, Dark and at 2.0×.

## Found

`TagWorksScreen` is unreachable: nothing navigates to `Routes.tagWorks` (a tag tapped opens
Search, 3z). Left in place for now; a candidate for removal like 3ds.

## Left

- The page's wash is the fandom list's hue on Android and the subject's on iOS.
- iOS's demo shows one filter (a fandom) the Android demo does not.
