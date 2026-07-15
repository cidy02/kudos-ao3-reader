# AO3 Comments Feature — Working Notes (living doc)

Branch lineage: `feature/ao3-comments` (initial build, 2026-07-09) →
`comments-ui-polish` (Codex functional polish) →
`comments-ui-visual-regression-fix` (restores the mockup/Kudos visual language
the polish lost) → **`comments-thread-nesting-polish`** (current: reply-depth,
connector, inline timestamp, and action-row correction — see T-85 below).
Owner spec: native comments UI (view all/by-chapter, threads, reply, compose,
actions), AO3-respectful networking, never-double-post. Mockups are directional,
not pixel-specs. Update this file as work lands so any agent can resume.

## Visual regression fix (comments-ui-visual-regression-fix, 2026-07-09)

Screenshots showed the polish branch drifting dark/murky/heavy. Root causes and
fixes (all in the view layer; no networking or submission-flow changes):
- **Murk**: NOT the fill color itself (`carouselCardSurface` and `cardSurface`
  resolve to the same color — a first draft of these notes misstated that).
  The murk came from the treatment around it: every comment as its own
  fragmented bubble, an accent-tinted wash over reply bubbles, hue-tinted
  carousel borders, the red thread rail, and the opaque CTA slab stacking
  similar dark layers. All replaced; thread cards now use the Library's
  `cardSurface` via the shared internal ReaderTheme surfaces in
  `AppThemeSurface.swift` so feature card treatments can't drift again.
- **Card-within-a-card (core mockup ask)**: rows stay flat + lazy (polish's
  perf architecture, stable IDs), but each top-level thread now shares ONE
  continuous card via `commentThreadGroupRow(depth:isLastInThread:)`
  (`UnevenRoundedRectangle` opens on the depth-0 row, closes on the thread's
  last row — `AO3CommentRow.isLastInThread`, set at flatten time, tested).
  Replies render as nested bubbles inside it: `nestedCardSurface` (new, one
  elevation step past the card: tertiary grouped in Light/Dark, paper in
  Sepia) + hairline border + a 2pt `.quaternary` connector (red rail removed).
- **Controls card**: count + sort collapsed to one quiet secondary footnote
  line ("N comments · Oldest First ˅", `.tint(.secondary)`) — sort no longer
  a bright red control. Title/segmented/chapter-row hierarchy unchanged.
- **CTA**: opaque `carouselCardSurface` slab removed — capsule
  `.borderedProminent` floating on the page backdrop with a soft shadow; the
  safe-area inset + trailing spacer still guarantee no content overlap.
- **Composer field**: `cardSurface` fill + hairline that brightens on focus +
  placeholder + auto-focus on open (was a gray-on-gray slab that read as
  disabled). Composer titles stay short ("Reply" / "New Comment" /
  "Edit Comment") so the header never truncates.
- **Chapter picker**: honesty note moved from a boxed row to a plain Section
  footer (quiet help text); fitted detent tightened for short works.
- **Avatars**: placeholder is now neutral (`.quaternary` disk, `.secondary`
  glyph) — the red disk read as a giant accent per row. Real parsed AO3 icons
  unchanged (AsyncImage, lazy, no profile fetching).
Adversarial-review verdicts on this pass (workflow finders + inline
verification after its verify agents hit a usage limit):
- FIXED: the reply connector collapsed to a ~10pt stub (HStack sibling shape
  under a List row's nil height proposal) — now an overlay sized by the bubble.
- FIXED: the CTA shadow ignored the theme's shadow language — now Dark is
  shadow-free like every other card, Light/Sepia keep the soft lift.
- ACCEPTED TRADEOFF: multi-row thread cards omit `cardBorder`/`cardShadow`
  (per-row strokes/shadows would draw seams at row joins). Dark is identical
  to `.cardRow()` anyway (no border/shadow there); Light/Sepia rely on fill
  contrast like system grouped lists. Revisit only if the owner's screenshot
  pass flags it.
- NOT DEFECTS: the composer field on a Light sheet is hairline-delineated
  (native pattern; focus ring + placeholder make it read editable); Dark reply
  bubbles rely on the system's tertiary-vs-secondary nesting contrast.

Preserved from the polish branch (verified untouched): unified entry points,
legacy composer + Report Abuse removal, avatar support, flattened lazy rows +
stable IDs, cancellable loads, debounced draft saves, chapter-aware reader
entry, honesty notes (reworded quieter, still present), the submission guard,
and all networking behavior. Not restored from `feature/ao3-comments`: the
recursive-render thread cell (replaced by the flat-row group treatment — perf)
and the always-on "View thread" screen idea (thread/parent links live in the
overflow menu). No fake hearts/likes added.

## T-85 thread nesting and timestamp correction (2026-07-09)

- `AO3CommentRow.flatten` still produces shallow, stable-ID lazy rows, but now
  carries only the connector facts each row needs: direct children, next
  sibling, and ancestor depths that must remain open through a branched
  subtree. Logical depth remains unbounded; `CommentThreadGeometry` caps only
  visual indentation at depth 3 so phone-width comment text stays readable.
- `CommentThreadConnector` draws thin neutral avatar-to-avatar elbow paths.
  Lines stop at avatar edges, continue through branched descendants, and use
  the real avatar center for each visual depth instead of a fixed far-edge rail.
- `AO3CommentTimestamp` parses the timestamp already present in the fetched
  comment markup (no new request), keeps the raw text as a failure fallback,
  and renders under-24-hour relative time, local-calendar Yesterday, or compact
  localized absolute date/time with the user's timezone abbreviation.
- Timestamp now sits inline after author/Guest/Author; Reply owns the left side
  of the action row when the session can reply, overflow stays neutral/right,
  and signed-out users get only the explicit Log in to Reply menu action.
- Coverage added for named-zone/offset parsing, recent/yesterday/older output,
  local-midnight boundaries, invalid fallback, branched connector projection,
  and visual-depth capping. `Scripts/verify.sh` ALL GREEN: **279 tests / 33
  suites**, iOS + macOS builds, invariants, lint gate, whitespace.
- Launch-only production-row fixture was inspected on iPhone 17/iOS 26.5 in
  Light and Dark: parent → reply → reply-to-reply indentation/connectors,
  inline Guest/Author timestamps, left Reply, and right overflow were readable.
  The fixture hooks were removed before verification/commit. Deleted-parent
  visual state was not available (the existing parser skips id-less AO3 deleted
  placeholders); owner screenshot approval and live action targeting remain.

## AO3 endpoints & markup (verified live, 2026-07-09, ~8 recon GETs)

| Purpose | Request | Notes |
|---|---|---|
| All comments, page N | `GET /works/<wid>?page=N&show_comments=true&view_full_work=true[&view_adult=true]#comments` | Multichapter needs `view_full_work=true` (else 302 → ch.1). Page includes fic text (heavy) — same as a browser; fetch on demand only, cache. |
| Chapter comments, page N | `GET /works/<wid>/chapters/<cid>?page=N&show_comments=true[&view_adult=true]` | Shows only that chapter's comments. |
| Chapter index | `GET /works/<wid>/navigate` | `ol.chapter.index.group > li > a[href=/works/<wid>/chapters/<cid>]` "N. Title" + `span.datetime`. Small page. No comment counts. |
| Thread page | `GET /comments/<comment_id>` | Standalone thread; renders **no** comment form. |
| **Reply form host (CSRF+pseud GET)** | `GET /comments/<parent_id>?add_comment_reply_id=<parent_id>` | The **only** no-JS page that renders `form#comment_for_<parent_id>` (otwarchive `_comment_actions.html.erb` gates it on `focused_on_comment`). The plain thread page above has no form and no pseud control — so `postCommentReply` must GET *this* URL, not `/comments/<parent_id>` (T-99 / CAA-1). |
| **Top-level form host (CSRF+pseud GET)** | `GET /works/<wid>?view_adult=true` | The interstitial hides the comment form (and its `comment[pseud_id]` control) without `view_adult=true`, though the CSRF meta is still present — so `postComment` must GET with it (T-99 / CAA-1). |
| Top-level post | `POST /works/<wid>/comments` | `AO3WriteActions.postComment`. Fields: `authenticity_token`, `comment[comment_content]`, **`comment[pseud_id]` (always, for signed-in — hidden input for single-pseud accounts, select for multi)** / `comment[name]`+`comment[email]` (guest, unused — Kudos requires login). |
| Reply post | `POST /comments/<parent_id>/comments` | `AO3CommentActions.postCommentReply`. Same fields as top-level. |
| `comments/show_comments` partial | ✗ | 302 for plain HTML (JS-format only) — do not use. |

Comment markup (inside `div#comments_placeholder`):
- `ol.thread` > `li.comment[id=comment_<id>]` (classes: `odd/even`, `guest`, `user-<uid>`).
- Replies: **sibling** `li` (no id) containing nested `ol.thread`.
- Byline `h4.heading.byline`: registered → `a[href^=/users/]`; guest → `span` +
  `span.role` " (Guest)". Chapter ctx: `span.parent a[href*=/chapters/]`.
  Time: `span.posted.datetime` (abbr day/month + span date/year/time/timezone).
- Body: `blockquote.userstuff` (p-paragraphs, limited HTML).
- Icon: `div.icon img.icon[src]` for registered users; guests carry AO3's
  visitor placeholder. Kudos uses only this already-present URL and never visits
  profiles to discover icons.
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
  skeletons, empty/failed/offline-stale states), lazy flattened comment rows
  (`CommentThreadRow`, stable AO3 IDs, nested bubbles/guide lines, parsed icons
  with placeholders, Author/Guest badges), `CommentComposerSheet` (parent
  quote, debounced drafts-as-you-type, status banners, Check Again), delete
  confirm, Copy Link, and parse-gated Thread / Parent Thread actions. `Report
  Abuse` is intentionally absent until a real native AO3 report flow exists.
- [x] Entry points: Work Detail stats "Comments" row → pushed screen;
  `AO3WorkActionsMenu` "Comments" (sheet via `.ao3WorkActions` host — covers the
  macOS legacy reader); iOS Readium reader toolbar bubble; and shared local /
  remote work-card context menus used by Home, Library, Browse, and Search.
  The former standalone "Leave a Comment" composer was removed.
- [x] Tests: `AO3CommentsParseTests` (threading, guest/registered bylines,
  chapter refs, pagination/totals, parse-gated edit/delete, recognized-empty vs.
  malformed/login pages, chapter index, URL shapes, canonical three-state
  verification incl. parent-awareness) +
  `CommentSubmissionTests` (key normalization, single-flight, duplicate window
  + expiry, ambiguity lock incl. `.unknown` keeping resubmit blocked, retry
  after verified absence, ambiguity classification, drafts). Fixture:
  `KudosTests/Fixtures/ao3_comments_page.html` (sanitized live markup) plus the
  template-shaped `ao3_comments_empty.html` recognized-empty fixture.

## Respect rules implemented
- Fetch only on user intent (open screen / switch chapter / page / refresh).
- TTL cache serves repeat views; no background refresh, no polling, no
  prefetching other chapters, no per-chapter count harvesting.
- Reuses AO3Client's single UA, coalescer, retry/backoff, 429 Retry-After.
- Writes are single-shot, never retried/coalesced (existing submitWrite).

## Double-post prevention
- `CommentSubmissionGuard` (pure, tested): key = work+parent+identity+normalized
  body (chapter scope is intentionally stripped). `begin()` rejects while
  in-flight or while an identical key succeeded recently (5 min), and timestamps
  the attempt before the form GET/POST. Timeout/unconfirmed POST → `.ambiguous`;
  a shared auth-scoped store keeps the key blocked across target/screen/guard
  recreation. A **verification fetch** returns `.found` only for the canonical
  account at the exact target level with no timing contradiction. Moderation /
  Anonymous Creator form evidence, rich-body transformation, ambiguous identity,
  timing disagreement, or an unreadable page stays `.unknown`, so no retry is
  unlocked on a guess. Post is disabled from first tap; draft survives until
  verified success.

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
  chapter (forbidden by the respect rules). The picker explains this instead of
  inventing counts; All Comments uses the already-parsed work total.
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

Distinct comment keys may proceed while an earlier one is ambiguous, but the
shared unresolved store retains every ambiguous key independently. Returning
to the original target/body restores its Check Again state and same-key block.

## Manual test checklist (owner, live session — from the task spec)
- View comments: single-chapter work, multichapter (All + By Chapter), switch
  chapters, no-comments work, high-comment work (pagination, Newest First).
- Threaded replies render nested; deep threads readable; "Open Thread on AO3".
- Post top-level comment; reply to a comment; confirm **exactly one** appears.
- Double-tap Post rapidly → one request (button disables, guard single-flight).
- Kill connectivity right after tapping Post (timeout) → app must NOT re-POST;
  verification runs; if unreachable, "Check Again" flow; draft preserved.
- On a moderated or Anonymous Creator work, repeat the ambiguous post/reply
  check: a hidden comment must remain blocked until verification can see it.
- Edit + Delete own comment (verifies the parse-gated markup + endpoints).
- Copy Link; Thread / Parent Thread only where AO3 rendered those links.
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

## Merge-clobber incident + restoration (2026-07-10)

Merge `b684e54` ("Merge comments thread nesting polish branch") resolved
`CommentThreadRow.swift` to the **older** T-85 nesting version (authored 09:52),
silently discarding the T-84 owner-corrected rounds from later that same day
(`3d573c8` 12:18 connector-follows-avatar-centers, `96b1827` 18:20 avatar
overlap, `08446cc` 21:21 "reply avatar back inside the bubble, per owner
correction"). The owner caught it pre-consolidation ("comment ui fixes …
aren't in this one").

**Restoration:** `CommentThreadRow.swift` is back to `bbf3116`'s state (T-84
final: card-within-card thread, avatar-inside-bubble replies, fixed-centerline
connector with bubble-fill occlusion, one-step depth cap) **plus one graft
from T-85**: the timestamp now renders via `AO3CommentTimestamp.displayText`
(relative within 24h, readable local date after) in T-84's owner-approved
placement (between Reply and the overflow menu). T-85's model-side work all
stays (`AO3CommentRow` projection metadata + `flatten`, `AO3CommentTimestamp`,
`postedAt` parsing, parse tests).

**Consciously dropped** (recoverable from `d0a51ea` if ever wanted): T-85's
row-level *drawing* of branched ancestor connector lines
(`continuingAncestorDepths` paths) and its per-depth avatar-centerline
geometry — superseded by the T-84 design the owner iterated to later that day,
which flattens depth 3+ and occludes via bubble fill instead. The geometry
regression test now pins T-84's invariant (bubble left edge ≤ connector
centerline at every depth).

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
- [x] T-83 UI/performance polish: parsed icons/placeholders; stable shallow rows;
      lazy per-row rendering; nested bubbles; clearer controls/chapter picker;
      non-overlapping signed-in CTA and no misleading signed-out CTA; compact
      Reply sheet; role/markup-gated menus; unified entry points; legacy composer
      and fake Report action removed.
- [ ] Owner: live-session manual test (checklist above + reader chapter-mapping
      checklist below) — REQUIRED before merge
- [ ] Candidate follow-ups: chapter-targeted top-level posting (capture the
      chapter-page form live), native thread-page view for cut-off threads,
      comment pagination jump-to-page, persisted comment cache.

## T-83 performance diagnosis

Code-path inspection plus a launch-only fixture pass found two concrete hot
paths:

1. `CommentsView` used a lazy outer `List`, but each visible
   `CommentThreadCell` recursively built its entire descendant tree. Presenting a
   menu/composer or changing screen state therefore diffed large nested value
   trees. `CommentsModel` now projects each fetched page once into
   `[AO3CommentRow]`; rows keep stable AO3 comment IDs and shallow comment values,
   and `List` instantiates them individually as they become visible.
2. `CommentComposerSheet.onChange` synchronously rewrote the full
   `UserDefaults` draft dictionary on every keystroke. Saves are now debounced by
   400 ms, with an immediate save on Cancel/disappear.

Avatar loading is tied to visible lazy rows through `AsyncImage`; it uses only
icon URLs already parsed from comment HTML and introduces no profile-page
scrapes. Comment sorting/thread projection no longer runs inside SwiftUI `body`.
The 2,500-row projection regression test verifies stable unique IDs and shallow
row payloads and completed in 0.003 seconds in the final full-suite run. No
Instruments before/after capture was available; the simulator fixture was used
for render/layout validation, while live large-work interaction timing remains
part of the owner pass. Rapid scope/sort/page changes now cancel the prior load,
and cancellation exits without flashing a failure state.

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
