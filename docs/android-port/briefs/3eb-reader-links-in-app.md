# 3eb: an AO3 link tapped in a work opens in the app (Android)

Done 2026-10-14 by Claude, alone. Gate 2,657 (two new tests).

## The fault

A link tapped in a work's text (its preface's tags, an author, another work) went to the
phone's browser, every kind: `ReaderLinkHandler` sorted them, but the tag case said "wiring
deferred" and the work case built an AO3 address and opened it outside. In the demo that
browser reached AO3, which the demo must never do. iOS (`AppRouter.openAO3Link`) opens an
author's page, a tag's works page or a work's page in the app.

## Now

- An author (`/users/<name>`, with or without a pseud) opens the author's page.
- A work opens its page (`WorkDetailSource.Ao3WorkId`).
- A tag opens the tag's works page (`TagWorksScreen`, registered but reached by nothing
  until now). Its name is read as AO3 writes it: `*s*` `*a*` `*d*` `*q*` `*h*` are
  "/" "&" "." "?" "#", and a "+" stays a "+" (it was turned into a space).
- Any other link still opens outside, as before.

`ReaderLinkHandlerTest`: authors and pseuds, AO3's tag spelling. Not seen on the emulator
with a tap: no demo work has a link in its text.

## Next

`TagWorksScreen` has never been put beside iOS's `TagWorksView` (which shares the shell of
`FandomWorksView`, done for Android in 3dv).
