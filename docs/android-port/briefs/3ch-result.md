# 3ch result: the writer's own totals on their Works list (audit A34-1)

Landed 2026-10-11 by Claude, alone (Codex and Gemini were out). Gate 2,559.

## Where the line is, before and after

`author/AuthorProfileScreen.kt`, the header of the signed-in writer's own profile, under the
title "Works".

- Before: the account's name ("AO3_Reader").
- After, on the plain Works list with no pseud chosen: "3 works · 248,400 words · 3,812 kudos"
  (iOS 1u's words and order). The count is AO3's own heading for the list; the words and kudos
  come from `/users/<name>/stats`.
- Until the totals arrive, or if that read fails: "3 works · AO3_Reader".
- If AO3's page gave no count: the name alone, as before.
- Under "In collections" or "Gifts", or narrowed to complete or unfinished works: the name
  alone, because AO3's count is then of a different list (iOS drops it there too).

## The requests for one opening

| | iOS | Android |
| --- | --- | --- |
| 1 | the dashboard | the dashboard |
| 2 | the selected tab (Works) | the selected tab (Works) |
| 3 | `/users/<name>/stats`, own account only | the same |

The third is made only when the route is the signed-in account's and has no pseud
(`AO3AuthorRepository.loadOwnStats` returns null without a request otherwise), once per
opening, through the page cache, and says nothing when it fails. Pull to refresh reads it
again past the cache.

## One thing Android does that the brief did not ask for

After a confirmed write to the writer's own works (a delete, a saved bulk edit, a saved row
edit or tags) the header and list were already read again past the cache. The totals are now
read again too, after the list: a deleted work's words and kudos are no longer in them, and
the line would otherwise show the new count beside the old totals. Not done on iOS (checked
by reading: `stats` is cleared only when the route or the session changes).

## Tests

`author/OwnStatsTest.kt`: the parser on both fixtures; the three conditions by counting
requests (another author, a pseud, signed out: none; own: one; again: none; refresh: one
more); the line in each of its states. `OwnWorksScreenTest` and `Brief3caScreenTest` now
expect the third read and pin its place (after the list) and its repeat after a delete.

Not tested: a session change while the read is out (the fence is the same two comparisons
the header and tab loads use; by reading only).

## Seen on the emulator (demo)

The line on the writer's own Works at the ordinary and at double text size; the name alone
under "In collections"; another author's page unchanged. The demo's works page did not carry
AO3's count heading, so the demo adds it (`demoAuthorWorksPage`).

## Left alone

- The fixtures are byte for byte iOS's (`ao3_user_stats.html`, `ao3_user_stats_none.html`).
- iOS takes the count from its dashboard counts cache; Android has no such cache and takes it
  from the list's own heading, which is the same number for the plain list.
