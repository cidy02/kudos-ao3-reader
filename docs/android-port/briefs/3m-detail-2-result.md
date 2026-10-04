# 3m-detail-2 result

## User-visible strings

- Header and figures: `Collection`; the fetched collection title; the fetched byline and summary joined with ` · `; `Works`; `Bookmarks`; and their exact counts.
- Segments and sections: `Works`, `Bookmarks`, `People`, `Manage`, `Recent`, and the accessibility label `Collection section`.
- Empty states: `This collection has no works yet.`, `This collection has no bookmarks yet.`, and `Nobody has joined this collection yet.`
- Work rows: AO3's work title, `by <authors>`, fandoms, summary, tags, rating/status and statistics from the shared `SensitiveWorkRow`; its `Show more` / `Show less` accessibility actions; `Open Work` and `Copy Link` in its existing long-press menu; `ANON`; and `Anonymous in this collection` for the badge's accessibility label.
- People: the fetched display name; `<count> work` / `<count> works`; and `<count> on this page · page <current> of <total>`.
- Manage: `Maintainers`, `Moderation`, `Collection Settings`, `Sign-ups`, `Assignments`, `Prompts`, `Your Sign-up`, and `Challenge Settings` when AO3's parsed permissions/links make each applicable.
- Failure/loading/paging: `Couldn't load this collection`, AO3's user-facing error text, and `Try Again`. The shared pager shows `Page <current> of <total>`, `First Page`, `Previous Page`, `Next Page`, `Last Page`; its long-jump sheet shows `<page>`, `of <total>`, `First`, `Last`, `Cancel`, and `Go`. Loading is an unlabeled progress indicator, matching iOS.

## Callbacks and interactions

- `onOpenWork(work)`: tapping a work opens that remote work in Work Detail through `AppNavHost`.
- `onOpenWebFallback(url)`: every Manage row opens its exact AO3 page in the existing web fallback. Maintainers uses `/participants`, Moderation `/items`, Collection Settings `/edit`, and the challenge rows use the parsed sign-up, assignment, request, or challenge-settings URLs. `Your Sign-up` uses the parsed sign-ups URL because Android has no native participant editor.
- Segment selection: switches Works / Bookmarks / People and lazily fetches that segment once.
- `Try Again`: retries the active segment at its current page; the already-loaded header remains visible.
- Pagination: fetches the selected page for the active segment and disables paging during that request.
- Work-row expand/collapse remains local to the shared row. Stale segment/page responses are ignored by a load-generation fence.
- The shared work-row menu's `Open Work` invokes `onOpenWork`; its existing `Copy Link` item currently only closes that menu because the shared component has no clipboard callback. This screen does not alter that component or any other screen.

## iOS differences

- All Manage destinations use web fallback as required; iOS has native maintainer, moderation, collection-form, sign-up, assignment, prompt, and challenge-settings screens that Android does not yet have.
- iOS's mature-content toolbar, pull-to-refresh gesture, auth-session-generation reset, and collection-deleted notification dismissal are not ported: this screen's required signature supplies no settings/auth/deletion state, and this detail adds no AO3 write path.
- The iOS source deliberately omits its design's `Gift` badge because a collection works page has no recipient data. Android makes the same omission and only shows the derivable `ANON` badge.
- The `ao3_collection_show` fixture contains no work blurb or People-segment rows: its work assertion therefore pins a positive exact Works total, while its person assertion pins a parsed maintainer identity. The parser now recognizes maintainers in AO3's collection `dl.meta` block so the fixture also supplies the screen byline.

No build or Gradle test was run in this sandbox, per the brief.
