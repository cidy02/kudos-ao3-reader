# 3eo: the page cache after writes (A37 F1, F2, F4, Android)

Done 2026-10-15 by Claude. Gate 2,673. Each checked against the code and iOS first.

- **F4 (P2, real):** every removal from the shared page cache stopped every read in flight, so
  one page's 404 (or one write's removal) left an unrelated screen loading for good. A read is
  now stopped only when its own page was removed after it began (the last 64 removals are
  kept; an older read is stopped, to be safe), and a page dropped because it would not parse
  stops nothing. `AO3PageCacheTest.anotherPagesFailureOrRemovalDoesNotStopThisRead` fails
  with the old rule.
- **F1 (P2, real; iOS T-379):** after an own-work write (a work, a chapter, a draft, Edit
  multiple works, deleting works) the writer's other kept pages (Works page 2, a pseud's list,
  Series, Stats) were served from before it for five minutes. Every POST on that path now
  forgets every kept page under the writer's address, whatever AO3 answered, as iOS's
  `submitWorkForm` (`removeAuthorPages`).
- **F2 (P2, real; iOS T-378):** a series save removed only the series' own page, and only when
  confirmed. It now removes the series' pages and the creator's series lists, after a save
  or an answer that may hide one (unconfirmed or lost); a plain refusal keeps them
  (`WritingSeriesTest` already held that).

Both removals: `AO3PageCacheTest`. Left from A37: F3 (a post-write read joining a pre-write
read in flight), F6, F7, F8, F9, F11, F12.
