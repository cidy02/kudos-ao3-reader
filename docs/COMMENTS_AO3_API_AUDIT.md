# Comments & Inbox vs. `ao3_api` — Review-Only Audit

**Status: IMPLEMENTATION IN PROGRESS.** The owner-approved staged implementation
has landed CAA-1/CAA-2 (T-99, Part A) and CAA-4/CAA-5/CAA-6 (T-102, Part B).
All other findings remain unchanged and unimplemented.

| Audited side | Commit |
|---|---|
| Kudos (this worktree HEAD, `release-fixes` tip) | `4e57337c5e17fe88f5d7df9d44abd2bcc8c2178f` |
| `wendytg/ao3_api` `master` | `02e349985d927bd8693f905f440e1ef0539f1984` (v2.3.1 era, 2025-01-26) |
| `otwcode/otwarchive` `master` (tie-breaker authority) | `41d3878b41e90140271ccabc7dfe6d822ab076da` (2026-07-14) |

Audit date: 2026-07-14. Method: source inspection of all three trees plus the stored fixtures (`KudosTests/Fixtures/ao3_comments_page.html`, `ao3_inbox_manage.html`). **Zero live AO3 requests were made.** No tests were modified; no live writes, edits, or deletes were performed.

---

## 1. Executive summary

Kudos's comments/inbox **retrieval architecture is materially stronger than `ao3_api`'s** — single-page parsing with no per-thread fan-out, TTL caching, pacing/coalescing/Retry-After honored, single-shot writes, per-write CSRF, and a duplicate-submission guard `ao3_api` entirely lacks. None of that should regress.

The audit still found **three High findings**, all Classification 2 (probable Kudos defects), all in territory the project has never been able to live-verify:

1. **CAA-1 — Comment POSTs omit the required `comment[pseud_id]`.** otwarchive's `comments_controller#create` builds `Comment.new(comment_params)` with **no server-side pseud defaulting**; a signed-in POST without `comment[pseud_id]` is validated as a *guest* comment (name/email required) and rejected. Kudos's `parseDefaultPseudID` reads only the `<select>` — but AO3 renders a **hidden input** for single-pseud accounts, and the plain `/comments/<parent>` page Kudos fetches before a reply renders **no comment form at all**. Net effect, per otwarchive source: **every native reply fails for every signed-in account, and top-level comments fail for the common single-pseud account.** `ao3_api` gets this right (hidden-input-first `get_pseud_id`, refuses to post without a pseud).
2. **CAA-2 — Write "success" is inferred from the absence of known error selectors**, but AO3 reports blocked comments and failed deletes via `div.flash.comment_error`, which `writeErrorMessage` does not match, and `deleteComment` never scans the body at all. A rejected write can report success, close the composer, and clear the draft.
3. **CAA-3 — Comments retrieval and its caches are not isolated across authentication generations.** The page cache is keyed by username without `sessionGeneration`; the chapter-index cache is keyed by work id only (session-lifetime, crosses accounts and sign-out — and otwarchive's `/navigate` includes the owner's **draft chapters**); `try? authenticatedRequest` silently downgrades a broken signed-in session to an anonymous fetch stored under the signed-in key. T-96 closed exactly this class for Inbox and account lists; Comments was left out.

A significant **moderating discovery**: otwarchive enforces a server-side uniqueness validation on comment content (`comment.rb:84-88`, scoped to commentable + pseud/name/email). A byte-identical re-POST to the same target is **rejected by AO3 itself**, which converts most residual guard-escape paths (CAA-4, CAA-10, CAA-12, CAA-16) from "duplicate lands on AO3" into "doomed second POST returns a validation error." The duplicate-guard machinery remains correct defense-in-depth — the practical severity of its residue findings is Medium/Low, not release-blocking.

Verification (`verifyCommentPosted`) has real false-verdict classes in both directions: false-`absent` (displayed-pseud vs. account-username matching, moderated works whose comments never render on the commentable, rich-text body mismatch, >600 s skew) and one false-`found` (top-level search includes reply descendants), the latter being the only silent data-loss path (draft cleared for a comment that never posted).

The prompt's two "genuinely open" questions are answered: **deleted comments with surviving replies are handled correctly today** (they keep `id="comment_<id>"` upstream; the parser's tombstone path is right and test-pinned — the handoff's "id-less deleted placeholder" note is outdated), and the **id-less `li.comment` that does exist** is otwarchive's deep-thread cutoff ("N more comments in this thread"), which Kudos currently renders as colliding "couldn't be read" tombstones (CAA-7). Chapter-targeted posting is confirmed to exist server-side as `POST /chapters/<cid>/comments` (routes.rb:434-441) with the same form fields — one live form capture remains to confirm rendering.

Findings: **3 High, 8 Medium, 5 Low** (12 probable-defect/adaptation findings, 4 both-sides-fragile). No issues found in: URL/query construction, pagination extraction, sibling reply-wrapper attachment, standalone-thread fail-closed parsing, request pacing/coalescing/UA policy compliance, write single-shot discipline, optimistic-state absence, Newest-first ordering, or the T-95/T-96 fixes (all verified still in place).

---

## 2. Files and code paths inspected

**Kudos @ `4e57337c`** — `Services/AO3Client.swift` (pacing, retry, `check`, coalescers, `submitWrite`, `parseCSRFToken`, `parseDefaultPseudID`, `parsePostingPseudOptions`, `writeErrorMessage`), `Services/AO3Client+Comments.swift` (all URL builders/fetchers/parsers), `Services/AO3WriteActions.swift`, `Services/AO3CommentActions.swift`, `Services/CommentSubmission.swift`, `Services/AO3Client+Inbox.swift`, `Services/AO3InboxActions.swift`, `Services/AO3RequestCoordinator.swift`, `Services/RequestCoalescer.swift`, `Services/AO3AuthService.swift` (auth requests, session generation, logout, posting pseud), `Models/AO3CommentModels.swift`, `Models/AO3CommentTimestamp.swift`, `Models/AO3InboxModels.swift`, `Models/AO3Models.swift` (`AO3Error`), `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentsView.swift`, `Features/Comments/CommentThreadRow.swift`, `Features/Account/AO3InboxModel.swift`, `Features/Account/AccountInboxViews.swift`; tests `AO3CommentsParseTests`, `CommentSubmissionTests`, `AO3InboxParseTests`, `AO3WriteActionsTests`, `AO3ClientPolicyTests`; fixtures `ao3_comments_page.html`, `ao3_inbox_manage.html`.

**`ao3_api` @ `02e34998`** — `AO3/comments.py`, `AO3/works.py` (`get_comments`), `AO3/chapters.py` (`get_comments`), `AO3/threadable.py`, `AO3/requester.py`, `AO3/session.py` (`refresh_auth_token`), `AO3/utils.py` (`comment`, `delete_comment`, `get_pseud_id`), `AO3/users.py` (skim).

**otwarchive @ `41d3878b`** — `app/controllers/comments_controller.rb`, `app/controllers/works_controller.rb#navigate`, `app/models/comment.rb`, `app/decorators/comment_decorator.rb`, `app/helpers/comments_helper.rb`, `app/helpers/application_helper.rb` (`flash_div`), `app/views/comments/{_commentable,_comment_thread,_single_comment,_comment_form,_comment_actions,show}.html.erb`, `app/views/works/navigate.html.erb`, `config/routes.rb`, `config/config.yml` (`COMMENT_THREAD_MAX_DEPTH: 5`), `config/initializers/gem-plugin_config/sanitizer_config.rb`.

Note: otwarchive `master` moved between prompt authorship and this audit; line numbers cited below are at `41d3878b`.

---

## 3. Architecture comparison

| Dimension | Kudos | `ao3_api` | Verdict |
|---|---|---|---|
| Comment retrieval | One `show_comments=true` page per explicit user action; parses roots **and** replies from that single page; 5-min TTL cache | `Work.get_comments` fetches **every** pagination page up front; work-loaded comments have `_thread = None`, so materializing any thread costs **one more GET per root** (`Comment.reload`); no cache | **Kudos far stronger** |
| Thread construction | Recursive `parseThread` over nested `ol.thread`; sibling id-less wrapper `li` attaches to preceding comment (correct per otwarchive) | Recursive `_get_thread` keyed on the `role` attribute; crashes on otwarchive's cutoff `li` (`comment.ol` is `None`, `comments.py:158-159`) | Both fragile at edges (CAA-7, CAA-15); Kudos degrades, `ao3_api` crashes |
| Auth | Explicit per-request cookie header; login-redirect detection on authenticated GETs and writes; session generation counter (Inbox-wired) | Session-object cookies; session-wide `authenticity_token` refreshed manually | Kudos stronger; generation scoping not yet applied to Comments (CAA-3) |
| CSRF | Fresh token per write from the target page (`meta[name=csrf-token]`) | One session-wide token, manually refreshed (`session.py:76-100`); posts to the deprecated `/comments.js` route | **Kudos stronger** — a fresh per-write token can't go stale and pins the referer/page context; cost is one already-paced GET per explicit write |
| Pseud handling | Select-only parse; omits field when absent (CAA-1) | Hidden-input-first (`utils.py:533-534`), refuses to post without a pseud (`PseudError`) | **`ao3_api` reveals the defect** |
| Rate limiting | `pace()` ≥0.6 s between request starts + coordinator + coalescers + Retry-After | `Requester` defaults to **unlimited** (`rqtw=-1`); its "12/min" docstring is its own guess, not AO3 policy | Kudos stronger; `ao3_api` constants correctly not treated as policy |
| Duplicate submission | Single-flight guard + durable unresolved store + read-only verification | None — and its `/comments.js` handling maps *any* HTTP 200 to `DuplicateCommentError` (`utils.py:305-306`), implicitly confirming AO3's server-side dedup exists | Kudos stronger (see CAA-4/CAA-12 for residue) |
| Writes | `submitWrite` single-shot, never retried/coalesced; verified for all 5 comment writes + Inbox bulk | Plain `requests` POST, no retry (by luck, not policy); threadable fan-out available | Kudos stronger |

---

## 4. Findings table

| ID | Severity | Confidence | Area | Classification | Summary | Recommendation | Request impact |
|---|---|---|---|---|---|---|---|
| CAA-1 | High | High | 3 | 2 | Replies (always) and single-pseud top-level comments (common case) POST without the `comment[pseud_id]` AO3 requires; otwarchive then applies guest validations and rejects the write | Fetch a page that renders the actual form (`/comments/<parent>?add_comment_reply_id=<parent>`; work page with `view_adult=true`); parse hidden input **and** select; fail before POST when neither exists | Unchanged (1 GET + 1 POST); avoids doomed POSTs |
| CAA-2 | High | High | 3,4,7 | 2 | Success = "no known error selector": `.flash.comment_error` (blocked writes, failed deletes) unrecognized; delete never scans the body; maintenance/malformed 200s pass | Recognize `comment_error` (and `caution`); give delete the same body validation; require positive success evidence (`comment_notice`/expected redirect shape) for final-200 pages | None |
| CAA-3 | High | High | 1,7,8 | 2 | Comments page/chapter caches and in-flight fetches not isolated by `sessionGeneration`; chapter index cached across accounts (leaks owner draft-chapter titles from `/navigate`); `try?` silently downgrades signed-in fetches to anonymous under a signed-in cache key | Extend the T-96 pattern (immutable scope+generation snapshot, post-await guards, generation-scoped cache keys) to `CommentsModel`/`CommentsPageCache`; make auth-request failure an error, not a downgrade | None normally; ≤2 GETs after a real auth transition |
| CAA-4 | Medium | High | 5 | 4 | **FIXED — T-102 Part B (`4a05556`).** Verification false-`absent` classes unlock re-POST: displayed-pseud≠username match, moderated works (unreviewed comments never render on the commentable), rich-text body mismatch, >600 s skew, anonymous creator, session-expiry anonymous downgrade + CAA-6 fabricated-empty | Match registered authors via canonical `profileRoute`/`userPath` username; treat moderated/anonymous/rich-text/timing mismatches as `.unknown`, never `.absent`; anchor `submittedAt` at POST start | None (same 1–2 verification GETs) |
| CAA-5 | Medium | High | 5,8 | 3 | **FIXED — T-102 Part B (`4a05556`).** Top-level verification searches `flattened` (all descendants), so an identical recent reply can false-`found` a top-level comment → success reported, draft cleared, comment never posted | For `parentID == nil` match against `page.comments` (roots) only | None |
| CAA-6 | Medium | High | 1,7 | 4 | **FIXED — T-102 Part B (`4a05556`).** Missing `#comments_placeholder`/`ol.thread`/`ol.chapter.index` fabricates valid-empty results — otwarchive always renders all three (incl. zero comments), so their absence is drift/maintenance/login/interstitial, not emptiness; anonymous `getHTML` has no login-redirect detection | Require the authoritative container; recognized-empty = placeholder + empty thread (index + zero `li`); otherwise throw `.parse`; detect login-page markup on anonymous fetches | None (retry stays one explicit GET) |
| CAA-7 | Medium | High | 2,8 | 4 | Deep-thread cutoff (`<li class="comment">` with no id, "N more comments in this thread", depth ≥5 & >1 child) renders as "(This comment couldn't be read.)" tombstones that all share one FNV id (hash of "") → SwiftUI identity collision; disclosure count/link lost | Recognize the cutoff (id-less + single `p > a[href^=/comments/]`, no `role` attr) before tombstoning; represent it explicitly with identity derived from parent+link; never auto-fetch the tail | None |
| CAA-8 | Medium | High | 7 | 3 | Catch-all stale-cache fallback masks every error class (auth expiry, 403, 404, parse, 429, 5xx) with unbounded-age cache; banner shows only when offline | Never mask auth/403/404/parse behind cache; transient fallback only with a visible stale/error state and an age cap (mirror `AO3AuthorProfileService`'s 24 h same-scope rule) | None |
| CAA-9 | Medium | High | 2,4,5 | 2 | `blockquote.userstuff` bodies with any `<p>` drop all non-`<p>` block content (lists, `pre`, tables, headings — all sanitizer-allowed); corrupts display, edit prefill (re-save destroys content), and verification matching | Flatten the whole blockquote in document order with block boundaries; keep text-only rendering | None |
| CAA-10 | Medium | Medium | 5,7 | 3 | Ambiguity classification ignores write stage: form-GET timeouts marked ambiguous (wasted verification GET); POST-stage cancellation/`badServerResponse`/5xx treated definitive → key released (server dedup then rejects the identical re-POST, surfacing a confusing error) | Split stages: pre-POST failures definitive; post-POST-start transport errors and 5xx ambiguous | Slightly fewer verification GETs |
| CAA-11 | Medium | Medium | 5,8 | 2 | Drafts (`w<id>-c<id>-p<id>`, no identity), open composer text, and tap-time identity aren't account-scoped: account B sees/posts A's draft; a mid-flight account change can pair A's form with B's session or verify A's key as B | Scope draft keys by account identity; snapshot identity+generation at composer open/submit; abort on generation change between form GET and POST | None |
| CAA-12 | Low | Medium | 5 | 3 | Guard residue: no shared in-flight claim across guard instances (two scenes can both `begin` one key — the one true landed-duplicate race, since Rails uniqueness validation isn't DB-constraint-backed); success window instance-local; 1 h expiry and logout release unresolved keys without evidence; process death loses the block while the draft survives | Reserve keys in the shared store at `begin`; share the success window; retain identity-partitioned unresolved entries across logout (they're already isolated per account); consider a persisted write-ahead entry | Recovery ≤2 GETs after relaunch |
| CAA-13 | Low | High | 4 | 3 | Ambiguous edits are treated as definitive with a comment claiming re-PUT idempotence — false upstream: every update stamps `edited_at`, re-triggering emails/inbox items, rate-limit consumption, and spam recheck | Give edits an unresolved state; verify via one GET of `/comments/<id>/edit` textarea before re-enabling PUT | +1 GET only after an ambiguous edit |
| CAA-14 | Low | High | 2 | 4 | "Account Deleted" bylines (orphaned pseud, plain text, no role span) fall through to `isGuest = true`, `author = "Guest"` | Preserve "Account Deleted" as a non-guest, non-navigable identity | None |
| CAA-15 | Low | Medium | 2 | 4 | `parseThread` recursion is unbounded; AO3's depth-5 cutoff only fires with >1 child, so a long single-child chain recurses without server bound (model side is already iterative) | Convert the parser to an explicit stack preserving wrapper-attachment semantics | None |
| CAA-16 | Low | Medium | 5,8 | 2 | Draft keys keep `chapterID` while submission keys strip it: cross-scope verification clears only the live context's draft; the original scope's stale draft survives its resolved key and invites a doomed (server-rejected) re-POST | Record the originating draft context in the unresolved entry, or clear all context-equivalent drafts on verified success | None |

---

## 5. Detailed evidence

### CAA-1 — Comment POSTs omit the required `comment[pseud_id]`

**Kudos:** `AO3Client.parseDefaultPseudID` selects only `select[name="comment[pseud_id]"]` (`Services/AO3Client.swift:456-464`). The adjacent doc comment asserts single-pseud accounts "get a hidden input instead — AO3 then posts under the account default regardless" (`AO3Client.swift:469-470`) — that assumption is **contradicted by otwarchive**. `postCommentReply` fetches plain `/comments/<parent>` for CSRF+pseud (`Services/AO3CommentActions.swift:17-32`); `postComment` fetches `/works/<id>` **without `view_adult=true`** (`Services/AO3WriteActions.swift:48-64`, `215-217`). Both append `comment[pseud_id]` only if `resolvedPostingPseudID` finds one (`AO3AuthService.swift:321-348` — resolves via `parsePostingPseudOptions`/`parseDefaultPseudID`, both select-only).

**otwarchive:** the comment form renders a `<select>` only for multi-pseud users; single-pseud users get `f.hidden_field :pseud_id` (`app/views/comments/_comment_form.html.erb:50-60`). The standalone comment page renders **no form** (`app/views/comments/show.html.erb` renders heading + thread only); the reply form appears only when `add_comment_reply_id` focuses that comment (`_comment_actions.html.erb:62-74`, `comments_helper.rb:400-402`). Server side: `Comment.new(comment_params)` with no pseud defaulting (`comments_controller.rb:398-409`; `comment_params` permits `pseud_id, comment_content, name, email, edited_at`, `:767-771`); `check_pseud_ownership` validates only *present* pseuds (`:94-99`). Without `pseud_id`, `validates :name, presence: {unless: :pseud_id}` and the email validations fire (`comment.rb:17-18`) → **save fails**.

**Fixture confirmation:** `KudosTests/Fixtures/ao3_comments_page.html:61,106` show only empty hidden `add_comment_reply_placeholder_<id>` divs — no reply form on an ordinary page.

**`ao3_api`:** `get_pseud_id` checks the **hidden input first**, then the select (`AO3/utils.py:526-551`); `utils.comment` raises `PseudError` rather than posting pseud-less (`utils.py:262-276`).

**Current vs. expected:** replies always POST pseud-less (rejected); top-level POSTs are pseud-less for single-pseud accounts and for any account whose work page came back as an adult interstitial (the CSRF `<meta>` is still present, so the POST is attempted). Expected: every signed-in comment POST carries an AO3-authorized pseud id, or fails before POSTing.

**Request impact:** none — still one form GET + one POST; a correct form page avoids doomed POSTs. **Regression risk:** low; endpoints stay identical (endpoint synthesis itself is correct — see §7). **Fix direction:** GET `/comments/<parent>?add_comment_reply_id=<parent>` (renders `form#comment_for_<parent>` per the handoff's live recon) for replies; add `view_adult=true` to the top-level form GET; parse hidden input before select; throw a typed pre-POST error when no pseud control exists on a signed-in flow. **Tests (if approved):** `AO3WriteActionsTests` — sanitized fixtures for a hidden single-pseud form, a multi-pseud select, a focused reply form, and a form-less page (must refuse to POST). One new sanitized fixture (focused reply form) needed.

**Status: FIXED (T-99, Part A).** `parseDefaultPseudID` now reads the hidden input before the select (mirroring `ao3_api`'s `get_pseud_id`); `postComment` GETs `/works/<wid>?view_adult=true` and `postCommentReply` GETs `/comments/<parent>?add_comment_reply_id=<parent>`, so both scrape a page that actually renders the pseud control; new `AO3AuthService.requiredCommentPseudID` throws the typed pre-POST `AO3WriteError.noPseudControl` when no control exists (never POSTs pseud-less, never synthesizes an id). The false doc comment at the old `AO3Client.swift:469-470` is corrected. `createBookmark`'s `bookmark[pseud_id]` flows through the same parser and its test stays green. Endpoints (POST targets) unchanged. **Never live-verified by an agent — owner live test of one reply + one single-pseud top-level post is the release gate.**

### CAA-2 — False write success

**Kudos:** `writeErrorMessage` matches `.errorlist li, .error p, .flash.error` only (`Services/AO3Client.swift:515-520`). `postComment`/`postCommentReply`/`editComment` treat any 2xx/3xx-final status with no matched selector as success (`AO3WriteActions.swift:72`, `AO3CommentActions.swift:38`, `:84`); `deleteComment` accepts any 2xx/3xx **without reading the body** (`AO3CommentActions.swift:58-59`). Success closes the composer and clears the draft (`CommentsModel.swift:591-599`, `657-663`); delete shows "Comment deleted." + reload (`CommentsView.swift:730-738`).

**otwarchive:** blocked comments/replies set `flash[:comment_error]` and redirect (`comments_controller.rb:39-54`); failed deletes set `flash[:comment_error]` (`:479-481`); `flash_div` renders these as `div.flash.comment_error` (`application_helper.rb:134-149`) — the CSS selector `.flash.error` does **not** match class `flash comment_error`. URLSession follows the 302, so the final response is a 200 page containing the unmatched error flash → reported as success. (The Inbox-specific `.caution` gap is already recorded as **T91-RF9** — not re-counted here, but one fix should cover both.)

**`ao3_api`:** even it inspects the delete response body (`AO3/utils.py:337-345`).

**Impact:** a blocked/failed write reports success and destroys the user's draft — silent data loss with no duplicate-guard involvement. **Fix direction:** extend the selector set (`.flash.comment_error`, `.flash.caution`), scan delete responses, and prefer positive evidence (`.flash.comment_notice` / expected redirect target) before declaring a final-200 write successful. **Tests:** `AO3WriteActionsTests` — `comment_error` rejected for post/reply/edit/delete; `comment_notice` accepted; generic maintenance HTML not success.

**Status: FIXED (T-99, Part A).** `writeErrorMessage` now matches `.flash.comment_error` and `.flash.caution` in addition to the prior set (verified `.flash.caution` does **not** false-match otwarchive's static `div.caution.notice` confirm boxes, which carry no `flash` class — regression-tested so block/mute's confirm-page scan is unaffected). New `writeSuccessMessage` (`.flash.comment_notice`/`.flash.notice`, both classes required so the moderated-work `p.notice` can't read as success) plus `commentWriteVerdict(status:body:)` centralize the honest three-way read: `success` only with positive evidence, `rejected` on a recognized error, else `unconfirmed`. `postComment`/`postCommentReply`/`editComment`/`deleteComment` (delete now scans the body) and `performInboxBulkAction` all route through it. Per owner default 3, `unconfirmed` is treated as **ambiguous**, not success: posts/replies enter the existing `markAmbiguous` → verification path (`CommentsModel.isAmbiguousSubmitError` now also returns true for `AO3WriteError.unconfirmed`); edit/delete/Inbox surface `AO3WriteError.unconfirmed`'s "couldn't confirm" message. `giveKudos`'s existing 2xx/422 semantics are unchanged (it does not use the verdict). **Never live-verified by an agent.**

**Adversarial-review follow-up (2026-07-14):** this logic's positive-evidence requirement is only reachable on a redirect-based write if the redirect's `Set-Cookie` survives to the followed request — `AO3Client`'s session (T-93) discards it outright, and otwarchive uses Rails' `CookieStore` for `_otwarchive_session` (`config/initializers/session_store.rb`), so the write's flash rides that cookie, not server-side state. Confirmed as a real bug (not just plausible): a fully successful `editComment`/`deleteComment`/`performInboxBulkAction` would misreport `.unconfirmed`. Fixed in shared `AO3Client` plumbing by **T-100** (`AO3RedirectCookieRelay`, `AO3Client.swift`), not on this branch — the defect was in `performAuthenticatedFetch`/`submitWrite`, not in this finding's own `commentWriteVerdict` logic, which is correct as implemented.

### CAA-3 — No auth-generation isolation for Comments retrieval

**Kudos:** `CommentsPageCache.Key.sessionIdentity` is `"in:<username>"`/`""` with no generation (`CommentsModel.swift:424-429`, `471-473`, `718-726`); `AO3AuthService.sessionGeneration` exists precisely for this (`AO3AuthService.swift:231-237`) and T-96 wired it into Inbox (`AO3InboxModel.swift` `AuthContext` snapshot+post-await guards — verified in place) but not Comments. The chapter index is cached by `workID` alone for the whole session (`CommentsModel.swift:476-495`, `747-753`). Authenticated request construction is `try?` at every retrieval/verification site (`CommentsModel.swift:438`, `:483`, `:256`, `:267`; `AO3CommentActions.swift:148`, `:162`) — `authenticatedRequest` throws when signed in but no applicable cookie survives (`AO3AuthService.swift:585-604`), and the `try?` silently converts that to an anonymous fetch stored under the signed-in cache key. No Comments code observes `sessionGeneration` or reloads a mounted screen on account change (`CommentsView.swift` `onChange` handlers cover scope/chapter/order/text only, `:106-147`).

**otwarchive:** `WorksController#navigate` includes **draft chapters** for admins and owners/invited users (`works_controller.rb:234-240`); the view exposes their titles and ids (`navigate.html.erb:3-7`). So an owner's `/navigate` result cached by work id serves the owner's private draft-chapter titles to a different account (or signed-out use) on the same device for the rest of the session.

**`ao3_api`:** requests bind to the object's current session (`works.py` `set_session`); no global cross-session cache exists.

**Fix direction:** apply the T-96 pattern — capture scope+generation at load start, guard after each await, include generation in `CommentsPageCache.Key` and the chapter-index key, treat auth-request construction failure as `AO3Error.authenticationRequired`, and reset mounted Comments state on generation change. **Request impact:** zero normally; one fresh page GET + conditional `/navigate` after a real transition. **Tests:** model cases beside `AO3CommentsParseTests`' model coverage (deferred A→B result inert; owner index never served to B; same-username relogin misses old cache; invalid signed-in cookies surface auth error rather than anonymous downgrade).

**Status: FIXED (T-103, Part C).** `CommentsModel` captures an immutable
`AuthContext` snapshot (identity, cache scope, `sessionGeneration`) when a
load/submit/verification starts and re-checks it after every await; stale
continuations are inert. `CommentsPageCache.Key` and the chapter-index key
both carry authentication scope + generation, so a same-username relogin
cold-loads and an owner's `/navigate` draft-chapter titles never serve across
accounts or sign-out. Required Comments reads and verification surface
authenticated-request construction failure as `AO3Error.authenticationRequired`
(never a silent anonymous fetch); `CommentsView` resets or dismisses a mounted
screen on generation change, and Inbox destinations stay bound to the session
generation that created them. Deterministic A→B coverage:
`CommentsAccountTransitionTests`.

### CAA-4 — Verification false-`absent` classes

**Kudos:** `containsComment` matches `comment.author` (the **displayed pseud** byline text) case-insensitively against the **account username** (`AO3CommentActions.swift:196-206`), although the canonical username is available from `userPath`/`profileRoute` (`AO3CommentModels.swift:164-166`, `210-216`) — otwarchive renders registered bylines as `link_to pseud.byline, [user, pseud]` → `/users/<username>/pseuds/<pseud>` (`comments_helper.rb:54-66`). Any account whose posting pseud differs from its username never matches → `.absent` → `resolveAmbiguity` calls `fail` and releases the key (`CommentSubmission.swift:262-267`, `237-241`).

**Moderated works:** comments post as `unreviewed` (`comment.rb:425-432`); the commentable renders **reviewed threads only** (`comment_decorator.rb:54-56`, `66-68`), and otwarchive explicitly redirects a logged-in unreviewed poster to the comment's own page because it won't appear on the work (`comments_controller.rb:425-432`). Kudos's verification reads the work page / parent thread → guaranteed `.absent` for a successfully posted moderated comment.

**Rich text:** the pending key normalizes the raw submitted text (`<em>hello</em>`), while parsed `bodyText` is rendered text (`hello`) — never equal. **Timing:** `postedAt >= submittedAt − 600 s` (`AO3CommentActions.swift:190`, `:204-205`) false-negatives on >600 s device-ahead skew or long suspension, and `submittedAt` is stamped when the *error is handled*, not when the POST started (`CommentSubmission.swift:246-249`). **Session expiry:** `try? authenticatedRequest` (`AO3CommentActions.swift:162-164`) plus CAA-6's fabricated-empty means an expired session on a restricted work parses the login page as a valid empty page → `.absent`. (The reply path is protected by the parent-presence guard, `AO3CommentActions.swift:158-160` — that guard is the right pattern; top-level lacks an equivalent.)

**Moderating fact:** a released key re-POSTs *identical* text to the same commentable (work-level comments attach to `last_posted_chapter`, `comment.rb:486-488`), which otwarchive's uniqueness validation rejects (`comment.rb:84-88`). The realistic damage is a false "didn't reach AO3" message, a doomed second POST, and duplicate-error confusion — not a landed duplicate — hence Medium, not High. The invariant still deserves restoration; the server backstop is not scoped to protect edited-text near-duplicates and races (see CAA-12).

**Fix direction:** match canonical username from `userPath`; return `.unknown` for moderated-work top-level posts (the work context can carry the moderation flag from the form page — `#add_comment_placeholder` region), anonymous-creator identities, unparseable/mismatched rich bodies, and timing disagreement; stamp `submittedAt` at POST start; make top-level verification require the recognized comments container (per CAA-6). **Tests:** `AO3CommentsParseTests` (matcher: alternate pseud path, Anonymous Creator, entity/markup bodies, skew) and `CommentSubmissionTests` (each uncertain class stays blocked).

**Status: FIXED (T-102, Part B; `4a05556`).** Verification now produces a
three-state verdict from canonical `profileRoute.username`, the exact target
level, normalized body, and timing evidence. A visible canonical match still
wins, but moderation/Anonymous Creator form notices, ambiguous identity,
markup/entity transformation, and parsed timing disagreement remain `.unknown`
and therefore keep the durable duplicate-post guard blocked. The exact form GET
passes the notice signal for both top-level comments and replies; it survives
screen/guard recreation and repeated Check Again. `CommentSubmissionGuard.begin`
anchors `submittedAt` before the form GET/POST, and re-marking preserves it.
No additional AO3 request was added. The upstream template supports the shared
reply/top-level notice; an owner live moderated-comment/reply check remains manual.

### CAA-5 — Top-level verification false-`found`

`containsComment` with `parentID == nil` searches `page.comments.flatMap(\.flattened)` — every root **and descendant** (`AO3CommentActions.swift:211`; `flattened` = full subtree, `AO3CommentModels.swift:261-269`). A recent identical-body reply by the same author (e.g. the user replied with the same short text minutes earlier, then a top-level attempt timed out) verifies the missing top-level comment as `.found` → "posted" reported, draft cleared (`CommentsModel.swift:654`), comment never exists. This is the one verification path with **silent data loss** and no server-side backstop. Fix: roots only for top-level. Test: `AO3CommentsParseTests` — identical matching reply + no matching root must not verify.

**Status: FIXED (T-102, Part B; `4a05556`).** Top-level verification now
examines only `page.comments` roots. Reply verification still examines only the
requested parent's direct replies. A regression test proves that an identical
matching reply cannot verify a missing top-level submission.

### CAA-6 — Fabricated empty on missing landmarks

**Kudos:** missing `#comments_placeholder` → valid empty page (`AO3Client+Comments.swift:112-118`); placeholder present but no `ol.thread` → also empty (`:122-124`); `/navigate` without `ol.chapter.index` → `[]` (`:331-354`). Pinned by `missingCommentsRegionParsesAsEmpty` (`KudosTests/AO3CommentsParseTests.swift:595-600`), which feeds arbitrary HTML and expects empty. Anonymous `getHTML` performs no login-redirect detection (only `authenticatedHTML` does, `AO3Client.swift:390-392`), so a signed-out fetch of a restricted work renders AO3's login page as "No Comments Yet".

**otwarchive:** with `show_comments` the placeholder div, pagination, and the top `ol.thread` are **always** emitted, including zero comments (`_commentable.html.erb:140-148`; `_comment_thread.html.erb:2` always opens `<ol class="thread">`); `/navigate` always emits `ol.chapter.index.group` (`navigate.html.erb:3-7`). So absence of these containers is never "no comments" — it's an interstitial, login page, maintenance page, or markup drift. **`ao3_api`** blindly dereferences the same landmarks and crashes (`works.py:274-276`, `chapters.py:142-146`) — Classification 4; neither behavior is right.

This mirrors the author-index parsers' existing recognized-empty rule (`docs/AO3_NETWORKING_POLICY.md` "Parser fragility assumptions") — Comments predates that discipline. It also upgrades CAA-4: verification `.absent` requires a *recognized* comments region. **Tests:** `AO3CommentsParseTests` — valid zero-comment page (placeholder + empty thread) parses empty; absent placeholder throws `.parse`; placeholder-without-thread throws; login/maintenance HTML throws; valid single/empty chapter index vs. missing landmark. Fixture addition: sanitized zero-comment page.

**Status: FIXED (T-102, Part B; `4a05556`).** `parseCommentsPage` now requires
`#comments_placeholder` plus its direct, truly empty-or-parseable top
`ol.thread`; missing/nested/unexpected markup throws `.parse`, while a sanitized
template-shaped zero-comment fixture is the recognized-empty case. The main AO3
login form throws `.authenticationRequired`, so restricted-work bounces cannot
become "No Comments Yet." `parseChapterIndex` likewise requires
`ol.chapter.index` and distinguishes an empty index from a missing/login page.
No request behavior changed and no live AO3 request was made.

### CAA-7 — Deep-thread cutoff becomes colliding tombstones

**otwarchive:** at `depth >= 5` with more than one child, the thread renders `<li class="comment"><p>(<a href="/comments/<id>">N more comments in this thread</a>)</p></li>` — **no id, no `role` attribute** (`_comment_thread.html.erb:9-18`; depth constant `config/config.yml:198`). **Kudos:** any `li.comment` without a `comment_<digits>` id becomes an `isDeleted` placeholder reading "(This comment couldn't be read.)" (`AO3Client+Comments.swift:206-217`), whose fallback id hashes the id **attribute** — the empty string for every such node — so all cutoffs on a page share one negative id (`:299-311`), colliding as SwiftUI row identity (`CommentThreadRow.swift:75` uses `comment.id`). The count and the `/comments/<id>` continuation link are discarded. **`ao3_api`** treats the same node as a wrapper and crashes (`comments.py:125-160`, `comment.ol` is `None`). Real deleted comments are unaffected — they keep `id="comment_<id>"` (`_single_comment.html.erb:2`, `10-13`); Kudos's tombstone handling for them is correct and regression-tested (`AO3CommentsParseTests.swift:499-537`), so the handoff's "id-less deleted placeholder" premise is outdated. Note otwarchive also renders an id-carrying, byline-less **admin-hidden** variant (`_single_comment.html.erb:14-15`) which Kudos handles acceptably via the missing-byline tombstone with AO3's own message text. **Fix direction:** detect the cutoff shape (id-less, no `role`, single `p > a[href^=/comments/]`), model it explicitly (deterministic identity from parent id + link), keep the disclosure; never auto-fetch. **Tests:** `AO3CommentsParseTests` — exact cutoff markup, two independent cutoffs (unique stable ids, no false deleted nodes, link retained).

### CAA-8 — Stale cache masks all error classes

Every `fetchPage` failure serves the cache with TTL ignored — unbounded age (`CommentsModel.swift:452-463`); `isOffline` covers only `.notConnectedToInternet` (`:688-690`); the stale banner requires `isFromCache && isOffline` (`CommentsView.swift:471-472`). Auth expiry (`AO3Error.authenticationRequired` from `authenticatedHTML`), 403, 404, 429, 5xx, and parse drift all display silently-fresh-looking stale content with obsolete Reply/Edit/Delete affordances. The internal precedent is stronger: `AO3AuthorPageCache` caps same-scope stale fallback at 24 h and never hides session expiry (`docs/AO3_NETWORKING_POLICY.md` Author profiles row; `AO3AuthorProfileService.swift`). (Unbounded cache growth itself is already recorded — A8-F3.) **Fix direction:** surface auth/403/404/parse; allow transient (offline/5xx/429) fallback only with a visible stale indicator and age cap. **Tests:** model-level error matrix in `CommentSubmissionTests`' sibling model suite or a new `CommentsModelTests` beside `AO3CommentsParseTests`.

### CAA-9 — Rich bodies lose non-paragraph content

`parseComment` collects all descendant `<p>` and, when any exist, discards every non-`p` sibling (`AO3Client+Comments.swift:268-277`): `<p>Intro</p><ul><li>One</li></ul>` → `Intro`. otwarchive renders raw sanitized content (`_single_comment.html.erb:58-61`) and the sanitizer allowlist includes `ul/ol/li`, `pre`, `table`, headings, `details`, nested `blockquote`, and more (`sanitizer_config.rb:5-11`). `ao3_api` reads the whole blockquote (`comments.py:73-79`). Downstream damage: display, the documented edit-prefill caveat becomes destructive (prefilled text lacking the list → re-save erases it), and verification body matching (CAA-4). **Fix direction:** flatten the entire `blockquote.userstuff` in document order with block-boundary separators; retain text-only rendering. **Tests:** `AO3CommentsParseTests` — mixed p/list, `pre`, nested blockquote, ordering, unchanged existing paragraph fixtures. Regression risk medium (bodyText feeds edit prefill + verification).

### CAA-10 — Stage-blind ambiguity classification

The `submit` catch spans both the form GET and the POST (`CommentsModel.swift:587-611`); only `.timedOut`/`.networkConnectionLost` are ambiguous (`:678-686`, pinned by `CommentSubmissionTests`). A form-GET timeout (no POST ever started) is marked ambiguous → one wasted verification GET + "Check Again" friction. Post-POST `.cancelled` (task torn down), `.badServerResponse`, `.cannotParseResponse`, and any 5xx (returned as status by `submitWrite`, `AO3Client.swift:425-441`, then thrown as `AO3WriteError.rejected`) are treated definitive → `fail()` releases the key (`CommentSubmission.swift:237-241`) although the server may have persisted the comment (classic 502-after-commit). Server dedup (comment.rb:84-88) converts the re-POST into an error rather than a duplicate, so severity is Medium. **Fix direction:** carry the write stage in the thrown error (pre-POST definitive; post-POST-start transport/5xx ambiguous). **Tests:** `CommentSubmissionTests` — preflight timeout definitive; POST-stage cancellation/5xx stays blocked.

### CAA-11 — Drafts/composer/identity not account-scoped

Draft keys are `w<work>-c<chapter>-p<parent>` with no identity (`CommentSubmission.swift:306-308`); `startComposer` restores whatever draft exists (`CommentsModel.swift:511-525`); submission identity is read from live auth at tap time (`:578-585`, `:669-671`); verification uses live auth (`:642-655`). Consequences: account B's composer shows and can post account A's draft; an A-composed submission crossing an account transition builds its POST or its verification against B's session. The unresolved store itself is identity-partitioned (T-95) — this finding is about drafts and in-flight continuations, the part T-96 fixed for Inbox (`AO3InboxModel` `AuthContext` guards) but not Comments. Multi-account-per-device usage is the only exposure. **Fix direction:** identity-scoped draft keys (with same-account relogin recovery), identity+generation snapshot at composer open/submit, abort on mismatch. **Tests:** `CommentSubmissionTests` — A-draft invisible to B and restored for A; A→B mid-composer cannot post; stale-generation continuations inert.

**Status: FIXED (T-103, Part C).** Draft keys are account-scoped
(`<identity>|w-c-p`, canonical bare username; a signed-in session whose
username is unknown stays generation-local instead of collapsing into a shared
empty identity), and the same identity is used consistently by composer
adoption, submission keys, verification clearing, and logout cleanup.
`postComment`/`postCommentReply`/`editComment`/`deleteComment` take a required
expected session generation, re-checked immediately after the form GET and
before POST construction, so an account switch between form GET and POST
aborts pre-POST instead of pairing one account's CSRF/pseud with another's
cookie. Stale successful/failed submissions and stale verifications cannot
touch the replacement account's composer, drafts, guard, or page.

### CAA-12 — Duplicate-guard residue

At `4e57337c`: `begin` writes nothing to the shared store (`CommentSubmission.swift:206-223` — `.submitting` is instance-local), so two live guard instances (two windows/scenes on iPad/macOS) can both pass `begin` for one key and double-POST concurrently — the one path where even otwarchive's uniqueness validation can race (it's an application-level validation, not a DB constraint). `recentSuccesses` is instance-local by documented design (`:158-161`). Unresolved entries silently expire after 1 h (`:108`, `:116-119`) and are cleared on logout (`AO3AuthService.swift:488-494` — deliberate, T91-RF2-derived, but the store's identity partitioning already prevents cross-account leakage, so retention would be strictly safer for the same-user-relogs-in case). The store is process-lifetime memory by documented decision (`CommentSubmission.swift:78-82`), so process death between POST and verification drops the block while the UserDefaults draft survives — relaunch re-offers the text and a re-POST (identical → server-rejected; edited → user-authored new comment). Given the server dedup backstop and the narrowness of the true race, severity Low; the in-flight claim in the shared store is the piece genuinely worth adding. **Tests:** `CommentSubmissionTests` — two guards/one key (second blocked pre-ambiguity), success window shared across guards, expiry/logout policy as decided.

### CAA-13 — Edits are not idempotent upstream

`submit` routes every edit error to definitive `fail`, with the comment "re-PUTting the same text is idempotent" (`CommentsModel.swift:601-610`); `startEditing` resets the guard (`:554-560`). otwarchive: every update merges `edited_at: Time.current` (`comments_controller.rb:452-460`); `saved_change_to_edited_at?` fires commenter/parent/work-owner notification flows (`comment.rb:185-197`); updates consume comment rate limit (`comments_controller.rb:57-79`) and can re-enter moderation/spam checks (`comment.rb:76-82`, `174-183`). A timed-out-but-landed edit that the user manually retries re-notifies everyone. Low severity (own comments, explicit user action). **Fix direction:** unresolved state for ambiguous edits; verify via one `/comments/<id>/edit` textarea GET. **Tests:** `CommentSubmissionTests` (edit timeout blocked) + `AO3WriteActionsTests` (edit-form textarea parse).

### CAA-14 — "Account Deleted" mislabeled as Guest

otwarchive renders an orphaned registered pseud as plain text `Account Deleted` — no link, no role span (`comments_helper.rb:54-57`); true guests get `<span>Name</span><span class="role"> (Guest)</span>` (`:63-65`). Kudos's byline fallback forces `isGuest = true` and, finding no qualifying child span, `author = "Guest"` (`AO3Client+Comments.swift:229-247`). `ao3_api` crashes on the same byline (`comments.py:63-69`, `header.a` is `None`). Display-only. **Test:** `AO3CommentsParseTests` — orphan byline distinct from real Guest and Anonymous Creator.

### CAA-15 — Unbounded parser recursion

`parseThread` recurses per nesting level (`AO3Client+Comments.swift:183-193`); otwarchive's cutoff needs `depth >= 5 && child_comments.size > 1` (`_comment_thread.html.erb:10-11`), so a single-child chain of arbitrary length renders fully. The model layer was already converted to iterative traversal for exactly this reason (`AO3CommentModels.swift:257-269`); the parser wasn't. `ao3_api` shares the recursive shape (`comments.py:119-160`). Practical likelihood of stack exhaustion unknown → Low/Medium. **Test:** generated deep single-child + branched HTML asserting structure without recursion failure.

### CAA-16 — Cross-scope draft clearing

`CommentSubmissionKey` strips `chapterID` (deliberate, T-95: `CommentSubmission.swift:52-54`) while draft keys retain it (`:306-308`); `runVerification` clears only the live composer context's draft (`CommentsModel.swift:642-655`). An ambiguous attempt made from By-Chapter, verified `.found` from All scope, leaves the chapter-scoped draft alive after its key resolved; reopening that scope restores the stale text and a re-POST is possible (identical → server-rejected error; edited → user-authored). Escape from the settled chapter-normalization fix in the *draft* layer only. **Fix direction:** store the originating full context in the unresolved entry, or clear every chapter-variant of the context on verified success. **Test:** `CommentSubmissionTests` — chapter-scoped ambiguous → work-scoped verified found → no surviving stale draft.

**Status: FIXED (T-103, Part C).** `CommentDraftStore.clearVariants` removes
every chapter variant of the work/parent draft for the resolving identity, and
verification captures the pending key (and its identity) *before* resolution
nils it, so a chapter-scoped ambiguous attempt verified `.found` from work
scope leaves no stale sibling draft. Definitive POST success clears variants
the same way. Covered end-to-end (two models sharing one unresolved store) in
`CommentsAccountTransitionTests`, plus the store-level case in
`CommentSubmissionTests`.

---

## 6. Where Kudos is stronger — must not regress

- **Single-page retrieval, zero fan-out:** replies are parsed from the already-fetched page; no per-thread GETs, no profile discovery; avatars ride the paced client (`CommentThreadRow.swift:902` → `AO3Client.imageData`). `ao3_api` needs P page GETs for roots and +1 GET per root for threads.
- **Politeness stack verified end-to-end:** all comments/inbox reads route through `getHTML`/`authenticatedPageHTML` (paced ≥0.6 s starts, coalesced, transient-only retry, Retry-After honored, typed 403/404/429/5xx — `AO3Client.swift:60-210`); Inbox hydration is strictly sequential through `AO3RequestCoordinator`.
- **Write discipline:** all five comment writes + Inbox bulk actions go through single-shot `submitWrite` (never retried/coalesced, login-redirect + 429 aware, `AO3Client.swift:425-441`); grep-verified none is wrapped in `withRetry`.
- **Per-write fresh CSRF + referer** vs. `ao3_api`'s session-wide token: stronger (no stale-token 422 class; correct page context).
- **Parse-gated permissions:** Edit/Delete/Reply exposed only when AO3 rendered them (`AO3Client+Comments.swift:282-291`; UI gates on parsed paths) — never inferred from usernames.
- **Deleted-comment tombstones** keep surviving replies correctly attached (verified against current otwarchive markup; regression-tested).
- **Standalone thread parsing fails closed** (`parseStandaloneCommentThread` throws on missing/empty thread), protecting the Inbox reply-verification path.
- **Duplicate-submission machinery** (single-flight guard, durable unresolved store, three-way verification, verify-pending-key-not-composer-text, chapter-stripped keys, `postedAfter`) — `ao3_api` has nothing comparable.
- **No optimistic mutation:** every success path refetches (`finishIfSucceeded`, delete reload); local state never diverges by insertion.
- **Recognized-empty discipline in the Inbox parser** (`AO3Client+Inbox.swift:30-45`) — the model CAA-6 asks Comments to adopt.
- **T-95/T-96 fixes verified still in place:** `verificationPlan` exact-parent-thread reply verification, `UnresolvedCommentSubmissionStore` adoption across guard recreation, `verificationTarget` pending-key body, chapter-stripped keys, Inbox `AuthContext` generation guards, generation-scoped account-list caches.

## 7. `ao3_api` behaviors deliberately rejected

- **`POST /comments.js`** write route (`utils.py:290`) — deprecated JS-format endpoint; Kudos's synthesized nested HTML endpoints (`/works/<id>/comments`, `/comments/<parent>/comments`) match otwarchive routes (`routes.rb:385+`, `:575-595`) and the handoff's live recon. **The prompt's structural question — synthesis vs. exact-form submission: the endpoint/method synthesis is verified-correct and functionally equivalent (Classification 5); what is *not* equivalent today is the synthesized field set (CAA-1). The fix is to source the fields from the rendered form (closer to the `AO3InboxActions` pattern) while keeping the verified endpoints.**
- **Session-wide `authenticity_token`** (`session.py:23`, `76-100`) — weaker than per-write fresh tokens.
- **`Requester` defaults (unlimited; "12/min" docstring)** — their constants, not AO3 policy; Kudos's own pacing stack governs.
- **`threadable`/`ThreadPool` fan-out** (unbounded Python threads) — forbidden by the networking policy.
- **Eager all-pages `get_comments` + per-root `reload()`** — request-multiplying; Kudos's on-demand paging is the right shape.
- **Blind landmark dereferences and `header.a`/`comment.ol` crashes** — Kudos should fail *closed* (CAA-6), not crash like `ao3_api`.
- **`User(str(header.a.text))` author modeling** — conflates pseud display text with account identity; Kudos's `userPath`-based identity is correct (and CAA-4 asks verification to actually use it).
- **Any-200-means-duplicate** response reading (`utils.py:305-306`) — incidental confirmation that AO3 server-side dedup exists, but not a response protocol to copy.

## 8. Request-count comparison (major flows)

| Flow | Kudos (traced) | `ao3_api` equivalent |
|---|---|---|
| Open Comments from Work Detail (All) | 1 page GET (0 on fresh cache) | `Work.get_comments`: P page GETs |
| Reader Comments button (chapter-aware) | 1 `/navigate` + 1 chapter page (index cached/session) | n/a |
| Change page / switch chapter / scope | 1 GET each (0 on fresh cache; first By-Chapter adds the one `/navigate`) | n/a (everything pre-fetched) |
| Newest-first cold open | ≤2 GETs (page 1 for count, then last page) | P GETs |
| Focused Inbox thread | 1 thread GET + ≤1 parent-thread GET; Chapter destination adds 1 chapter-page GET (+ ≤1 `/navigate` fallback); sparse work summary adds ≤1 work GET | `Comment.reload` 1 GET + parent crawl GETs |
| Post top-level | 1 form GET + 1 POST (+1 refresh GET on success) | 1 `get_pseud_id` GET + 1 POST (+ token refresh GET when stale) |
| Reply | 1 thread GET + 1 POST (+1 refresh GET) | same as top-level |
| Edit | 1 edit-page GET + 1 POST (+1 refresh GET) | not supported |
| Delete | 1 thread GET + 1 POST (+1 refresh GET) | 0 GET + 1 POST (held token) |
| "Check Again" | reply: 1 GET; top-level: 1–2 GETs (page 1, + last page when multi-page) | n/a |
| Open Inbox | 1 GET + strictly sequential hydration of the visible page's unique work ids (cache-first, coordinator-paced) | n/a |

All flows comply with `docs/AO3_NETWORKING_POLICY.md`: no background polling, no eager page/thread loading, no cross-chapter fan-out, no write retries, coalescer prevents duplicate GETs, loads cancel on context change. The only above-one-GET-per-action shapes are documented and bounded (newest-first cold sizing, focused-thread chapter/summary extras, top-level verification's last-page hop). CAA-10's form-GET-timeout misclassification wastes one verification GET; CAA-1's fix costs nothing.

## 9. Recommended fixture and test additions (only if findings are approved)

- **Fixtures (`KudosTests/Fixtures/`, sanitized live markup):** focused reply form (`/comments/<id>?add_comment_reply_id=<id>` with hidden single-pseud field); zero-comment work page (placeholder + empty `ol.thread`); deep-thread cutoff page (two cutoffs); single-pseud hidden-input work-page form; a moderated-work comment form region.
- **`AO3WriteActionsTests`:** hidden-input pseud parsing; select precedence; form-less page refuses POST; `comment_error`/`caution` rejected; `comment_notice` accepted; maintenance HTML not success; delete body validation; edit-form textarea parse.
- **`AO3CommentsParseTests`:** recognized-empty vs. thrown `.parse` matrix (CAA-6, replacing the pinned `missingCommentsRegionParsesAsEmpty` expectation); cutoff markup identity/disclosure; mixed rich bodies; Account Deleted byline; deep single-child chain (iterative parser); matcher canonical-username/roots-only/timing cases.
- **`CommentSubmissionTests`:** stage-aware ambiguity classification; two-guard in-flight claim; cross-guard success window; identity-scoped drafts; cross-scope draft clearing; moderated/`unknown` verification classes stay blocked.
- **Comments model coverage** (new suite beside the existing ones): stale-fallback error matrix; generation-scoped cache keys; auth-downgrade surfaces as error.

## 10. Open questions and manual validation needs

1. **Live write verification remains the owner release gate** (unchanged; `docs/AO3_NETWORKING_POLICY.md` "Still unverified"). CAA-1 sharpens it: verify a reply and a single-pseud top-level post specifically, since source analysis says both currently fail.
2. **Chapter-targeted posting** (handoff follow-up): route confirmed as `POST /chapters/<cid>/comments` (`routes.rb:434-441`); the chapter page renders the same `_comment_form` (hidden/select pseud + `authenticity_token`). One live capture of a chapter page's form remains to confirm field names before implementing.
3. **Deleted-placeholder capture** (handoff open item): **resolved by source** — current otwarchive keeps `id="comment_<id>"` on deleted comments; Kudos handles it; the handoff note is outdated and can be corrected at implementation time. The genuinely id-less node is the CAA-7 cutoff; capturing one live deep thread would give the fixture.
4. **Moderated-work signal:** confirm on a live moderated work which form-page markup distinguishes it (for CAA-4's `.unknown` classification).
5. **AO3-production vs. master drift:** the duplicate-content validation (`comment.rb:84-88`) and guest-validation behavior are asserted from otwarchive master; production AO3 is assumed equivalent. The owner's live write test doubles as confirmation.
6. Already-recorded, still-open ledger items touching this area (verified still present, deliberately not re-reported): T91-RF6 (byline-less inbox rows), T91-RF7 (filter fail-closed), T91-RF9 (`caution` flashes), T91-RF10 (a11y), T91-RF11 (chapter retry), A6-F5/BUG-6 (newest-first rollover), A8-F3 (unbounded comments cache).

## 11. Proposed implementation sequence — **UNAPPROVED; do not start without explicit owner instruction**

1. **CAA-1 + CAA-2** (one branch: correct form sourcing + honest response reading — the write path's correctness core; highest user harm, smallest blast radius, fixture-testable).
2. **CAA-6 + CAA-4 + CAA-5** (parser recognized-empty discipline, then verification verdict hardening on top of it).
3. **CAA-3 + CAA-11 + CAA-16** (extend T-96 generation isolation to Comments: caches, in-flight guards, drafts).
4. **CAA-8** (stale-fallback honesty) and **CAA-9** (body flattening).
5. **CAA-7, CAA-10, CAA-12, CAA-13, CAA-14, CAA-15** (independent, small, test-first).

## 12. Human review checklist

- [ ] Confirm/deny each High (CAA-1..3) against a live signed-in session (owner-only; agents must not write to AO3).
- [ ] Decide severity acceptance for the verification-residue findings (CAA-4/5/10/12/16) given the otwarchive server-dedup backstop documented here.
- [ ] Decide whether logout should retain identity-partitioned unresolved entries (CAA-12) — reverses a deliberate T91-RF2-era choice.
- [ ] Decide whether the CAA-8 stale-fallback change should mirror `AO3AuthorPageCache`'s 24 h cap exactly.
- [ ] Approve the fixture-capture list (§9/§10) — all read-only GETs within the recon precedent.
- [ ] Choose which items enter TASKS.md as implementation rows and in what order (§11 is a proposal only).
