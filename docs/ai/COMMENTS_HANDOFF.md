# AO3 Comments Feature — Working Notes (living doc)

Branch: `feature/ao3-comments` (from `release-hardening`, 2026-07-09).
Owner spec: native comments UI (view all/by-chapter, threads, reply, compose,
actions), AO3-respectful networking, never-double-post. Mockups are directional,
not pixel-specs. Update this file as work lands so any agent can resume.

## AO3 endpoints & markup (verified live, 2026-07-09, ~8 recon GETs)

| Purpose | Request | Notes |
|---|---|---|
| All comments, page N | `GET /works/<wid>?page=N&show_comments=true&view_full_work=true[&view_adult=true]#comments` | Multichapter needs `view_full_work=true` (else 302 → ch.1). Page includes fic text (heavy) — same as a browser; fetch on demand only, cache. |
| Chapter comments, page N | `GET /works/<wid>/chapters/<cid>?page=N&show_comments=true[&view_adult=true]` | Shows only that chapter's comments. |
| Chapter index | `GET /works/<wid>/navigate` | `ol.chapter.index.group > li > a[href=/works/<wid>/chapters/<cid>]` "N. Title" + `span.datetime`. Small page. No comment counts. |
| Thread page | `GET /comments/<comment_id>` | Standalone thread; also no-JS reply form host via `?add_comment_reply_id=<id>`. |
| Top-level post | `POST /works/<wid>/comments` | Already implemented (`AO3WriteActions.postComment`). Fields: `authenticity_token`, `comment[comment_content]`, `comment[pseud_id]` (logged in) / `comment[name]`+`comment[email]` (guest). |
| Reply post | `POST /comments/<parent_id>/comments` | Verified via no-JS form `form#comment_for_<parent_id>`. Same fields as top-level. |
| `comments/show_comments` partial | ✗ | 302 for plain HTML (JS-format only) — do not use. |

Comment markup (inside `div#comments_placeholder`):
- `ol.thread` > `li.comment[id=comment_<id>]` (classes: `odd/even`, `guest`, `user-<uid>`).
- Replies: **sibling** `li` (no id) containing nested `ol.thread`.
- Byline `h4.heading.byline`: registered → `a[href^=/users/]`; guest → `span` +
  `span.role` " (Guest)". Chapter ctx: `span.parent a[href*=/chapters/]`.
  Time: `span.posted.datetime` (abbr day/month + span date/year/time/timezone).
- Body: `blockquote.userstuff` (p-paragraphs, limited HTML).
- Actions `ul.actions#navigation_for_comment_<id>`: Reply
  (`/comments/add_comment_reply?chapter_id=<cid>&id=<id>`), Thread, Parent.
  Logged-in own comments add Edit (`/comments/<id>/edit`) / Delete — **parse by
  label, expose only what's present** (unverified without live session).
- Deep threads: server cuts recursion; a `Thread`/`Parent Thread` link remains.
- Pagination: standard `ol.pagination.actions` (existing parser works).
- Author badge: AO3 does NOT mark work authors in comment markup — derive
  client-side by comparing byline username to the work's author list.
- Sort: AO3 work comments have **no server sort/flat options** (oldest-first,
  paginated). Any Newest-first / flat view is a local rendering choice.

## Architecture (planned → mark ✅ as landed)

- [x] `Models/AO3CommentModels.swift` — `AO3Comment` (tree), `AO3CommentsPage`,
  `AO3ChapterRef`, `AO3CommentContext` (work/chapter/parent identity).
- [x] `Services/AO3Client+Comments.swift` — fetchers (via the client's polite
  `getHTML` — made internal for extensions — or `authenticatedPageHTML` when
  signed in) + SwiftSoup parsers. URL builders tested.
- [x] `Services/CommentSubmission.swift` — `CommentSubmissionPhase` +
  `CommentSubmissionGuard` (single-flight, recent-success window, ambiguity
  lock), `CommentSubmissionKey` (normalized body), `CommentDraftStore`.
- [x] `Services/AO3CommentActions.swift` — `postCommentReply` (POST
  `/comments/<parent>/comments`), `editComment` (`_method=put`),
  `deleteComment` (`_method=delete`); `verifyCommentPosted` →
  `.found/.absent/.unknown` (work-level newest page, author+normalized-body
  match, parent-aware); `AO3WriteActions.writeRequest` made internal for reuse.
- [x] `Features/Comments/CommentsModel.swift` — screen state, TTL cache
  (`CommentsPageCache`, 5 min, session-scoped), offline/stale handling, the
  defensive submit flow + `reverify` ("Check Again").
- [x] `Features/Comments/CommentsView.swift` — card-styled screen (All /
  By Chapter, chapter sheet, local Oldest/Newest order, pagination row,
  skeletons, empty/failed/offline-stale states), recursive `CommentThreadCell`
  (Author/Guest badges, chapter chips, parse-gated actions menu),
  `CommentComposerSheet` (parent quote, drafts-as-you-type, status banners,
  Check Again), delete confirm, copy-link/open-thread/report-abuse.
- [x] Entry points: Work Detail stats "Comments" row → pushed screen;
  `AO3WorkActionsMenu` "View Comments" (sheet via `.ao3WorkActions` host —
  covers the macOS legacy reader); iOS Readium reader toolbar bubble button →
  sheet.
- [x] Tests (17): `AO3CommentsParseTests` (threading, guest/registered bylines,
  chapter refs, pagination/totals, parse-gated edit/delete, empty region,
  chapter index, URL shapes, verification matcher incl. parent-awareness) +
  `CommentSubmissionTests` (key normalization, single-flight, duplicate window
  + expiry, ambiguity lock incl. `.unknown` keeping resubmit blocked, retry
  after verified absence, ambiguity classification, drafts). Fixture:
  `KudosTests/Fixtures/ao3_comments_page.html` (sanitized live markup).

## Respect rules implemented
- Fetch only on user intent (open screen / switch chapter / page / refresh).
- TTL cache serves repeat views; no background refresh, no polling, no
  prefetching other chapters, no per-chapter count harvesting.
- Reuses AO3Client's single UA, coalescer, retry/backoff, 429 Retry-After.
- Writes are single-shot, never retried/coalesced (existing submitWrite).

## Double-post prevention
- `CommentSubmissionGuard` (pure, tested): key = work+chapter+parent+identity+
  normalized body. `begin()` rejects while in-flight OR while an identical key
  succeeded recently (5 min). Timeout/ambiguous network result → state
  `.ambiguous`, resubmit blocked until a **verification fetch** (newest page of
  the commentable, match by author+normalized body within window) resolves it.
  Post button disabled from first tap; draft kept until verified success.

## Scope decisions
- Guest commenting: **out** — posting requires login (existing app model);
  signed-out users see a clear sign-in state. (AO3 guest flow needs
  name/email + moderation; revisit if owner asks.)
- Edit/Delete: implemented but **needs live-session verification** (markup for
  own-comments not observable logged-out) — UI only shows them when the links
  are parsed from AO3's HTML, so nothing is invented. Edit prefills the
  *rendered* text (limited-HTML comments lose markup if re-saved — noted).
- "Newest first": local re-ordering starting from the last page (AO3 has no
  server sort). Flat/threaded toggle **not built** (AO3 has no flat view; a
  local one adds little over threaded rendering).
- Kudos on comments (mockup hearts): AO3 has no comment-kudos — **not built**.
- Top-level comments post via the existing work-level form (AO3 shows them on
  the newest chapter) even in By Chapter scope — the composer says so. Posting
  *to a specific chapter* needs the chapter-page form's fields captured from a
  live session first (candidate next step).
- Mockup's per-chapter counts in the picker: **not shown** — AO3 exposes no
  cheap per-chapter counts and harvesting them would mean fetching every
  chapter (forbidden by the respect rules).
- Deep-thread "cut" (AO3 stops nesting very deep threads server-side): rendered
  as parsed; the per-comment "Open Thread on AO3" action covers the tail.

## Adversarial self-review findings (fixed pre-commit)
1. Scope switch double-fetched (scope onChange + selectedChapter onChange both
   loaded) → chapter assignment now returns early; one GET per user action.
2. Scope/chapter switch showed the previous scope's comments until the new
   fetch landed → `resetForContextChange()` clears to the skeleton.
3. Verification failure was treated as "absent" → would have unlocked a re-POST
   after a 429/offline check (the double-post path). Now three-way
   `.found/.absent/.unknown`; `.unknown` keeps resubmission blocked and offers
   "Check Again" (re-runs the read, never the POST). Guard-tested.
4. Verification checked the selected chapter's page, but top-level posts are
   work-level → a By-Chapter ambiguous post would always "verify absent".
   Verification now always reads the work-level newest page.
5. Composer in By Chapter scope implied chapter-targeted posting → honesty
   note added (posts to the work; AO3 shows it on the newest chapter).

Edge accepted (documented): a *different* comment may be submitted while an
earlier one is still ambiguous; the pending ambiguous key is then dropped
(its "Check Again" context closes with the composer). Same-key re-posts stay
blocked throughout.

## Manual test checklist (owner, live session — from the task spec)
- View comments: single-chapter work, multichapter (All + By Chapter), switch
  chapters, no-comments work, high-comment work (pagination, Newest First).
- Threaded replies render nested; deep threads readable; "Open Thread on AO3".
- Post top-level comment; reply to a comment; confirm **exactly one** appears.
- Double-tap Post rapidly → one request (button disables, guard single-flight).
- Kill connectivity right after tapping Post (timeout) → app must NOT re-POST;
  verification runs; if unreachable, "Check Again" flow; draft preserved.
- Edit + Delete own comment (verifies the parse-gated markup + endpoints).
- Copy Link / Report Abuse.
- Signed-out: browse public work's comments; composer shows sign-in state.
- Offline: previously-viewed page shows with stale banner; posting disabled.
- Adult/restricted work behavior matches existing app handling.

## Reader chapter-aware Comments button (QoL, 2026-07-09)

Tapping Comments from inside a reader opens `CommentsView` in **By Chapter** on the
AO3 chapter you're reading — not All / Chapter 1.

**Where the mapping lives (single source of truth):** `[ReaderSection]
.ao3StoryChapter(forSpineIndex:)` in `Reading/ReaderSection.swift`, alongside the
existing `pillLabel`/`storyChapterCount` used by the progress pill + TOC. Reuses the
T-76 normalization, so reader pill, TOC, and comments can't drift. **Never** uses a
raw `spineIndex + 1`.

**How EPUB sections map to AO3 chapters:**
- a real `.chapter` section → its own 1-based `storyChapterIndex` (front matter is
  already excluded from that count);
- **Preface / Summary / any `.other` before Chapter 1** → **Chapter 1** (no preceding
  `.chapter`);
- **Afterword / any `.other` after the last chapter** → the **last** story chapter
  (nearest preceding `.chapter`);
- single-chapter, empty section list, or out-of-range index → **1** (safe default).

**Reader → comments plumbing:**
- Readium reader (`ReadiumReaderView.currentAO3Chapter`): `book.readingPosition
  .chapter - 1` is the current spine index (same basis as the pill) → mapped → passed
  as `CommentsView(initialChapterPosition:)`. nil until a position + built sections
  exist.
- macOS legacy reader (`ReaderView.currentAO3Chapter`): `sections
  .ao3StoryChapter(forSpineIndex: currentIndex)`, threaded through
  `AO3WorkActionsMenu` → `AO3WorkActionsModel.startViewingComments(...:
  initialChapterPosition:)` → the modifier's `CommentsView`. Work Detail passes nil
  (opens All), so its behavior is unchanged.
- `CommentsModel.loadInitial(auth:)` applies it: fetches the `/navigate` index once,
  resolves the target via `chapterRef(forStoryPosition:)` (which **clamps** into the
  live chapter range via `clampedChapterPosition`, so an Afterword past the last real
  chapter lands on the last one), sets `.byChapter` + the ref, and does **one** page
  load. Falls back to **All** if the index is empty/unavailable (e.g. single-chapter
  works with no `/navigate`) — the same comments show either way. The
  `isApplyingInitialContext` flag suppresses the view's scope/chapter `onChange`
  reloads so the programmatic setup stays a single GET (+ the small index).

**Tests added** (`ReaderSectionTests`): the spec's mapping matrix over the reference
EPUB (Preface/Summary→1, chapters→own number, Epilogues→96–101, Afterword→101), plus
single-chapter-with-front-matter, no-Afterword, Preface-without-Summary-gap, non-AO3
(every item its own chapter), and unmappable/out-of-range/empty → 1; and
`clampedChapterPosition` (floor/ceil/single/none-→-nil).

**Remaining edge (documented):** the mapping assumes the EPUB's story-chapter count
matches AO3's live `/navigate` count; when they differ (stale EPUB, extra/fewer
posted chapters) the target is clamped into the live range rather than guessed — a
mid-story mismatch could land a chapter or two off, but never out of bounds or on the
wrong work. Manual check below covers the common shapes.

## Status / next steps
- [x] Live recon of endpoints + markup (table above is ground truth)
- [x] Models + parser + fixtures + parse tests
- [x] Submission guard + draft store + tests
- [x] Write actions (reply/edit/delete) + verification fetch
- [x] UI + entry points (Work Detail, actions menu, Readium reader toolbar)
- [x] Adversarial self-review (5 findings fixed — see above)
- [x] `Scripts/verify.sh` ALL GREEN — 265 tests / 33 suites, iOS + macOS builds,
      invariants, lint, whitespace (2026-07-09); TASKS.md row T-82
- [x] Reader chapter-aware Comments button (QoL) — mapping + both readers + tests;
      `Scripts/verify.sh` ALL GREEN, 272 tests / 33 suites (2026-07-09). See the
      "Reader chapter-aware Comments button" section above.
- [ ] Owner: live-session manual test (checklist above + reader chapter-mapping
      checklist below) — REQUIRED before merge
- [ ] Candidate follow-ups: chapter-targeted top-level posting (capture the
      chapter-page form live), native thread-page view for cut-off threads,
      comment pagination jump-to-page, persisted comment cache.

## Manual test checklist — reader chapter mapping (owner)
Use a real AO3 EPUB with Preface/Summary/Afterword. On iOS (Readium) and macOS (legacy):
- Open reader on Preface → tap Comments → **Chapter 1** selected, By Chapter.
- Open on Summary → Comments → **Chapter 1**.
- Open on Chapter 1 → Comments → **Chapter 1**.
- Open on a middle chapter → Comments → **that** AO3 chapter.
- Open on the final story chapter → Comments → **final** chapter.
- Open on Afterword → Comments → **final** chapter.
- Switch to All Comments still works; manually pick another chapter still works.
- Single-chapter work → opens All (no chapter index) showing the work's comments.
- Returning to the reader does not lose reading position.
