# 3ek: Codex's A50 review, screen-state findings F2, F3; F7 left (Android)

Done 2026-10-15 by Claude. Gate 2,667.

- **F2 (P2, real):** after Subscribe or Unsubscribe succeeded, the button came back on while
  the author's page reloaded, still holding the old form, so a tap resent it. The button
  stays off until the page has reloaded (`subscriptionBusy || headerLoading`). Seen on the
  emulator: Subscribe, "Subscribed.", then Unsubscribe.
- **F3 (P2, real):** after Clear History succeeded, only the page that was on screen when Clear
  was confirmed was hidden; a page opened meanwhile went on showing cleared history. The
  screen remembers that the history was cleared, so every page reads empty.
- **F7 (P2, real, not fixed yet):** a comments page with no list of comments (an interstitial,
  a changed page) reads as "No Comments Yet". iOS fails closed (`#comments_placeholder` with
  its direct `ol.thread`, which AO3 always prints, even empty). The same rule on Android broke
  other comments tests, whose made-up pages lack the list, and one then spun at full CPU; the
  change was backed out. **To do:** bring those test pages in line with AO3's real markup,
  then apply iOS's rule.

A50's tally: eleven findings; ten real and fixed (3ei, 3ej, 3ek), F7 real and still open.
3ch, Clear History's write itself, and 3cf's save looked right to Codex.
