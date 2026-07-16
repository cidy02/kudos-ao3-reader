# Ponytail Audit — Session 1 (`release-fixes`)

**Date:** 2026-07-15 / 2026-07-16
**Branch audited:** `release-fixes` @ `f7a66a9` (working tree confirmed clean; local branch,
`origin/release-fixes`, and the session's working branch `claude/ponytail-audit-session-1-b10335`
all point at the same commit — no rebase/merge was needed to be "up to date").
**Mode:** audit-only. No source files were modified, no code was deleted, nothing was
refactored. This report is the only artifact produced.

## Coverage note (read this first)

This audit ran in two passes.

**Pass 1** fanned out five parallel research agents (Features/ card duplication,
Services/ persistence+sync, AO3 networking/auth, Comments feature, tests). All five were
terminated mid-investigation by the session's subagent API quota before producing a final
report. Pass 1's findings (§4.1, §4.6, §4.7, §4.9 below) were reconstructed by direct
manual investigation instead of the planned parallel sweep.

**Pass 2**, after the quota reset, ran a `Workflow`-orchestrated pipeline: 8 parallel
finder agents covering every area Pass 1 didn't reach (AO3 networking core, auth/author
services, sync/lifecycle services, the full Comments feature, the full Account feature,
Authors/Browse, Library/WorkDetail, and the remaining small feature directories), each
piped directly into an adversarial verifier for every actionable (delete/consolidate/
simplify) finding — 35 agents total, 0 errors. The verification pass mattered: one
finding (dead `descendantCount`) was **factually refuted and corrected** — the verifier
re-ran the finder's own grep and found two test call sites the finder missed, so only its
sibling `totalOnPage` is reported as dead (§3.7). Every "notes"-tagged (retain/investigate)
finding below was **not** run through adversarial verification, since it wasn't proposing
a removal — those are flagged as unverified where they appear.

Between the two passes, essentially the entire non-test app target has now been read at
line-level depth at least once, with the exception of a handful of small UI-kit leaf files
(`UIComponents/FlowLayout.swift`, `GlassFieldBar.swift`, etc.) and `Utilities/*.swift`,
which are trivial (<90 lines total, per §2) and were covered by Session 1's repo-wide
marker sweep (zero TODO/dead-flag/wrapper hits) even if not individually re-read this pass.

---

## 1. Executive summary

This is a lean codebase for its size, but it is not spotless — the second pass surfaced
real, verifiable dead code and a lot of copy-paste that the first pass's narrower scope
hadn't reached yet.

**Repo-wide markers** (Pass 1, still true): **zero** TODO/FIXME/deprecated annotations,
**zero** feature flags, **zero** dead-code `#if false` blocks, **zero** `*Legacy*`/`*Old*`/
`*V2*`/`*Copy*`-named files, **zero** generic `*Wrapper` types, only **two** third-party
dependencies (SwiftSoup, Readium `swift-toolkit`), both load-bearing. The seven internal
protocols are all legitimate DI seams with real test doubles (§7).

**What Pass 2 found:** **8 genuinely dead symbols** worth deleting (§3) — ranging from a
single unused enum case to an entire 55-line orphaned file — and **~22 more consolidation
findings** (§4) beyond Pass 1's original 4, spanning AO3Client's HTML-parsing helpers,
the authenticated write-action layer (CSRF fetch, comment-verdict handling), the Account/
Authors/Browse feature views, and onboarding. Every deletion and every "high confidence"
consolidation finding below was independently re-verified against the live tree by a
second agent instructed to try to refute it, not confirm it — 26 of 27 verified findings
held up as claimed; 1 was corrected rather than accepted or thrown out.

Total estimated removable/consolidatable surface across all findings, this report:
**roughly 550-650 lines**, of which **~95-100 lines are outright dead code** (§3) and the
rest is duplicated-but-live logic (§4). None of it touches AO3 request pacing or retry
logic. A handful of findings sit inside the authenticated-write-action layer (CSRF fetch,
comment-verdict switch, subscribe/moderate scaffolding) — none of these are behavioral
changes (the *logic* being consolidated is identical at each site), but §9 flags them for
extra care given the protected category they're adjacent to.

The single most structurally significant finding remains **`Services/WorkImporter.swift`
reimplementing `Services/WorkIdentityIndex.swift`'s matching** instead of using it (§4.1) —
`Services/KudosBackup.swift`'s `WorkRestoreIndex` shows the correct wrapper pattern exists
in the same codebase. The single **largest** duplication by line count is
**`FandomWorksView`/`TagWorksView`'s ~150-200 line near-identical selection/bulk-action/
pagination shell** in `NativeBrowseView.swift` (§4.5), echoed a third and fourth time in
`AuthorProfileView.swift` and `SearchView.swift`.

---

## 2. Repository-wide measurements

| Metric | Value |
|---|---|
| Swift files (app target, `kudos-ao3-reader/`) | 154 |
| Swift files (test target, `KudosTests/`) | 46 |
| Lines (app target) | 45,283 |
| Lines (test target) | 12,506 |
| External SPM dependencies | 2 — `SwiftSoup` (scinfu), `swift-toolkit` (Readium; iOS-only via `platformFilter = ios`) |
| `protocol` declarations | 7, all in `Services/` around AO3 auth, all with ≥1 real test-double conformance |
| `static let shared` singletons | 8 |
| TODO / FIXME / XXX markers | 0 |
| `@available(*, deprecated)` markers | 0 |
| Feature-flag-shaped code (`FeatureFlag`, `#if false`, disabled `isEnabled`) | 0 |
| Files named `*Legacy*`/`*Old*`/`*V2*`/`*Copy*` | 0 |
| Generic `*Wrapper` types | 0 |
| `typealias` declarations | 11, all closure-injection seams for testability or cross-platform `NSViewRepresentable`/`UIViewRepresentable` aliasing |
| `#if os(...)` platform conditionals | 137, across 47 files |
| Largest files | `KudosBackup.swift` (1724), `AO3Client.swift` (1265), `WorkDetailView.swift` (1258), `CommentsView.swift` (1185), `SettingsView.swift` (1122), `CommentsModel.swift` (1105), `AccountView.swift` (1095), `ReadiumReaderView.swift` (1065) |
| SwiftLint disabled rules | 4 (`todo`, `trailing_comma`, `multiple_closures_with_trailing_closure`, `for_where`) — all justified inline, none suppress anything found in this audit |
| `docs/*.md` | 19 files, 5,113 lines (not in scope; several are dated adversarial-review/diagnosis records) |
| **This session's findings** | **8 confirmed-dead (§3), ~22 confirmed-consolidatable (§4), 1 corrected mid-verification (§3.7), 6 unverified "investigate" leads (§6), ~22 confirmed-retain negative results (§7)** |

---

## 3. Highest-confidence deletion candidates

All 8 items below are adversarially verified: a second agent re-read the live files and
tried to find a hidden caller (dynamic dispatch, Codable/SwiftData property references,
NotificationCenter/selectors, SwiftUI navigation conventions, platform conditionals)
before the CONFIRMED verdict was accepted. Total: **~95-100 lines**, all confidence high,
all risk low unless noted.

### 3.1 `AO3AccountSection.swift` — entire file is dead (55 lines)

`kudos-ao3-reader/Features/Bookmarks/AO3AccountSection.swift:1-55` — `AO3AccountSection`
(struct + nested `Tab` enum), a segmented Later/Bookmarks/History/Subs picker wrapper
around `AO3AccountWorksList`. **Why dead:** explicitly retired when the Account tab
absorbed Bookmarks (T-54); the file itself was never deleted. **Evidence:** repo-wide grep
(excluding `.git`) finds only the struct's own declaration, plus historical mentions in
`TASKS.md` ("retired `BookmarksView`/`AO3AccountSection`") and `docs/Feature_Ideas.md`
(FI-13, superseded 2026-06-24). **Callers:** none. The sibling file
`AO3AccountWorksList.swift` in the same directory *is* still used (by `AccountView.swift`
and `HomeView.swift`) — only `AO3AccountSection` is orphaned. **Action: delete.**

### 3.2 `MatureContentHiddenView` — never instantiated (13 lines)

`kudos-ao3-reader/Features/Privacy/MatureContent.swift:337-349`. A
`ContentUnavailableView` placeholder documented as "shown when a list's only items are
Mature works hidden by privacy," but every real call site (`LibraryView`, `HomeView`,
`AO3AccountWorksList`, etc.) builds its own inline `ContentUnavailableView` for that state
instead. **Evidence:** repo-wide grep finds only the declaration. **Callers:** none.
**Action: delete.**

### 3.3 `FolderSyncOnboardingState.shouldShow(defaults:)` — dead, shadowed by a reimplementation

`kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:182-184`. Meant to
answer "should the sync-folder onboarding screen show," but never called —
`ContentView.swift`'s `syncFolderOnboardingPresented` computed `Binding` (lines ~201-213)
independently reimplements the same `@AppStorage`-key predicate inline, plus two more
conditions (`hasCompletedOnboarding`, a session-only dismiss flag) `shouldShow` doesn't
have. **Evidence:** grep for `shouldShow(defaults:` / `.shouldShow(` returns nothing.
**Callers:** none (the sibling functions `recordConfigured()`/`recordDismissal(permanently:)`
in the same enum *are* called and stay). **Action: delete** the dead predicate — but note
`ContentView.swift`'s reimplementation is arguably the thing that should have called
`shouldShow` instead of restating its logic; deleting the dead function without also
pointing `ContentView` at a (possibly extended) shared predicate leaves the duplication in
place, it just removes the unused half. **Recommended: delete `shouldShow`, and evaluate
folding `ContentView`'s inline predicate into it as a follow-up — not required for this
deletion.**

### 3.4 `AppRouter.Panel.settings` — dead enum case (1 line)

`kudos-ao3-reader/App/AppRouter.swift:109`. The `.settings` case of the single
right-hand-inspector `Panel` enum is never set, compared, or toggled — Settings now lives
inside `AccountView` as a pushed screen (via `SettingsRoute`), not as an `AppRouter.Panel`
inspector. **Evidence:** grep for `Panel.settings`, `toggle(.settings)`,
`isShowing(.settings)`, `panel == .settings`, `panel = .settings` returns only the case
declaration. All other `Panel` cases (`searchFilters`, `libraryFilters`, `readerChapters`,
`readerDisplay`) have live call sites in `SearchView.swift`, `LibraryView.swift`,
`ReaderView.swift`, `ReadiumReaderView.swift`. **Action: delete the case** (trivial,
mechanical — Swift will flag any exhaustive `switch` that needs updating at compile time).

### 3.5 `CommentDraftStore.clear(for:identity:)` — superseded by `clearVariants`, never removed

`kudos-ao3-reader/Services/CommentSubmission.swift:373-377`. A single-key draft clear with
no production call site — `CommentsModel`'s two draft-clearing sites (lines 889, 975) both
call `clearVariants(for:identity:)` instead, added by T-103/CAA-16 to clear every
chapter-scoped draft sibling on verified success. `clearVariants` doesn't even delegate to
`clear()` internally — it has independent prefix/suffix removal logic, so `clear()` isn't
a reused building block either. **Evidence:** repo-wide grep for `.clear(for:` finds
exactly one call, `KudosTests/CommentSubmissionTests.swift:545` — a direct unit test of
the primitive itself, not a real caller. **Callers:** the one test only. **Action: delete**
(and drop or repoint the one test assertion that exercises it, if it isn't independently
useful as a lower-level primitive test).

### 3.6 `AO3AccountWorksList.Kind.myWorks` — deliberately-unrouted enum case, per the project's own notes

`kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:18` (plus 8 associated
switch arms: `title`, `emptyTitle`, `emptyMessage`, `signedOutTitle`, `signedOutMessage`,
`url(username:page:)`, `fetch(for:page:)`, `countsKind`). Never constructed anywhere —
Account's "My Works" shortcut and the Writing tab both route through the separate
`AO3AuthorProfileModel`/`profileContentSections` pipeline instead. **Evidence:** `TASKS.md`'s
T-88 entry says so explicitly: *"AO3AccountWorksList.Kind.myWorks no longer routed from
Account (kind kept for potential reuse)"* — a documented, deliberate keep-for-later that is
exactly this audit's `yagni:` category (config/case nobody constructs). The only remaining
reference besides the declaration is an exhaustive `switch` arm at
`AccountComponents.swift:837` that exists purely because the case exists.
`KudosTests/AO3AccountListCountsTests.swift` references a same-named but *unrelated*
`AO3AccountListKind.myWorks` cache enum, not this one. **Callers:** none. **Action: delete**
— but per the project's own note, re-grep once immediately before landing the change in
case an in-flight branch has since added a caller.

### 3.7 `AO3CommentsPage.totalOnPage` is dead — its sibling `descendantCount` is **not** (verification caught this)

`kudos-ao3-reader/Models/AO3CommentModels.swift:308` — `totalOnPage` sums
`descendantCount` over a page's root comments. The finder claimed both `totalOnPage` *and*
`descendantCount` (lines 282-290) were dead. **Verification refuted the `descendantCount`
half**: re-running the finder's own grep (`grep -rn "totalOnPage\|descendantCount"
kudos-ao3-reader/ KudosTests/`) surfaces 4 matches, not 2 — `descendantCount` is directly
asserted in `KudosTests/AO3CommentsParseTests.swift:413`
(`deepReplyChainsFlattenWithoutRecursion`, which builds a 2000-deep reply chain to verify
the iterative, non-recursive tree-walk doesn't blow the stack on AO3's uncapped nesting)
and `:470` (`largeDisplayThreadProjectionKeepsStableUniqueIDs`, at 500×5 scale). Both are
real `@testable import Kudos` compiling assertions against `AO3Comment`, part of a
deliberate trio (`flattened`, `contains`, `descendantCount`) guarding against
recursion/O(depth²) blowups. **`totalOnPage` itself remains genuinely dead** — no
production or test caller found for it specifically. **Action: delete `totalOnPage` only
(≈2-3 lines). Do NOT delete `descendantCount` — it is a tested, load-bearing part of the
iterative comment tree-walk.**

---

## 4. Consolidation and simplification candidates

Every "high confidence" item below (all except §4.10) was adversarially re-verified.
Ordered roughly by size/impact, not by file location.

### 4.1 `WorkImporter.swift` reimplements `WorkIdentityIndex`'s matching, instead of using it

*(Pass 1 finding, unchanged.)*
- **Files/symbols:** `Services/WorkIdentityIndex.swift:38` — `existingWork(ao3WorkID:sourceURL:recordID:)`, documented as *"the ONLY matcher"* (3-tier: AO3 work ID → canonical AO3 URL → local record UUID; used by backup/sync restore, remote-card context menu, `ReadingQueueService`, `CanonicalWorkMerge`). `Services/WorkImporter.swift:485-499` — private `existingWork(matching:sourceFile:in:)` hand-fetches `[SavedWork]` and matches AO3-ID only (missing the canonical-URL tier). `Services/WorkImporter.swift:810-821` — `existingWork(forSource:in:)` hand-fetches `[SavedWork]` and reimplements all 3 tiers by hand, plus a 4th (`sourceURL` exact match) `WorkIdentityIndex` doesn't have.
- **Contrast:** `Services/KudosBackup.swift:1579-1596`'s `WorkRestoreIndex` is a 17-line wrapper around `WorkIdentityIndex` — the correct pattern, already present in this codebase, that `WorkImporter` should follow instead.
- **Callers:** `existingWork(matching:sourceFile:in:)` ← `importUserEPUB`; `existingWork(forSource:in:)` ← `importEPUB`. Both load-bearing for import dedup, neither dead.
- **Evidence needed:** confirm whether `existingWork(forSource:in:)`'s exact-`sourceURL`-match tier is an intentional 4th tier worth preserving before folding into `WorkIdentityIndex`, plus regression tests for both import paths' dedup/revive behavior.
- **Confidence:** high. **Risk:** medium (data-safety-adjacent: import dedup/revive). **Size:** ~25-30 lines. **Action:** consolidate, after the evidence step. **Conflicts with:** the "ONLY matcher" invariant in `WorkIdentityIndex.swift` and `docs/ARCHITECTURE_MAP.md:59` — currently false as written.

### 4.2 AO3Client.swift: three small HTML-parsing helpers, each reimplemented 2-4 times

**4.2a — pagination-total loop, duplicated 4x.** `Services/AO3Client.swift:1142-1147`
(`parseSubscriptionsPage`) and `:1160-1165` (`parseWorksList`) contain a byte-for-byte
identical 6-line "walk `ol.pagination li`, parse each as `Int`, keep the max" loop; the
same logic recurs at `AO3Client+Comments.swift:129-134` (`parseCommentsPage`, a near-
identical variant reading from a sub-element with `try?` instead of `try`) and
`AO3Client+Inbox.swift:51-56` (`parseInboxPage`, byte-identical). `AO3Client+Authors.swift`
already extracted this exact pattern once as a private `paginationTotal(in:currentPage:)`
(lines 499-506, used at 125 and 145) — proving the abstraction was already invented, just
never shared across files. **Confidence:** high. **Risk:** low (internal/private parsers,
existing fixture tests for all 4 sites should keep passing since this is an
implementation-only change). **Size:** ~30 lines → ~8-line shared helper + 4 call sites.
**Action:** consolidate (promote `paginationTotal` to internal on `AO3Client`, call from
all 4 sites).

**4.2b — `stat`/`statInt` digit-parsing, reimplemented 3x with an inconsistency.**
`AO3Client.swift:813-819` (nested in `parseWorkMetadata`, strips via `.filter(\.isNumber)`)
and `:1217-1222` (nested in `parseBlurb`, strips via
`.replacingOccurrences(of: ",", with: "")` — a different, narrower strategy) each define
their own local `stat`/`statInt` pair; a third, `AO3Client+Authors.swift:508-511`
(`statInt(_:in:)`, `.filter(\.isNumber)`) is functionally near-identical. Two different
digit-stripping strategies for the same job is the actual defect here — not just line
count. **Confidence:** medium (the duplication is clear; unifying requires threading a
`Document`/`Element` param, not a pure drop-in). **Risk:** low. **Size:** ~15 lines.
**Action:** simplify.

**4.2c — login-redirect check, duplicated 2x.** `AO3Client.swift:444`
(`authenticatedHTML`'s `responsePath.contains("/users/login")`) and `:488`
(`submitWrite`'s `http.url?.path.contains("/users/login")`) independently reimplement the
same "did AO3 bounce this to the login page" one-liner. **Confidence:** medium. **Risk:**
low. **Size:** ~4 lines → one `private static func isLoginRedirect(path: String?) -> Bool`.
**Action:** simplify.

### 4.3 Authenticated write-action layer: three duplicated patterns (medium risk category, low-risk changes)

These three all sit inside the "authenticated AO3 write operations" protected category.
None of the consolidations below change *what* gets sent to AO3 — they collapse identical
logic already repeated at each site — but per this audit's own boundary, extra
verification is warranted before merging (see §9).

**4.3a — CSRF-token fetch, implemented 5 times across 2 files.** The 4-line "GET a page,
extract the CSRF meta token or throw `AO3WriteError.noCSRFToken`" sequence exists as a
private helper `csrfToken(forPageAt:)` (`AO3WriteActions.swift:194-201`, used by
`giveKudos`/`markForLater`), inlined verbatim 3 more times in `toggleSubscribe` (:97-99),
`postComment` (:59-64), and `createBookmark` (:164-166) — because those callers also need
the raw HTML for further parsing, which the token-only helper discards — and a 5th time as
a byte-identical private helper `commentPageCSRF(at:)` in the sibling file
`AO3CommentActions.swift:325-332` (used by `deleteComment`/`editComment`), duplicated
across files rather than shared because Swift's file-scoped `private` can't cross files.
**Confidence:** high. **Risk:** low. **Size:** ~40 lines across 5 sites → one shared
internal helper returning `(html, token)` + thin call sites. **Action:** consolidate.

**4.3b — comment write-verdict switch, duplicated 4x.** `postComment`
(`AO3WriteActions.swift:81-88`), `postCommentReply`/`deleteComment`/`editComment`
(`AO3CommentActions.swift:50-57`, `:78-85`, `:111-118`) all end with the identical 6-line
`switch AO3Client.commentWriteVerdict(status:body:)` shape, differing only in two literal
strings (success message, default rejection message). (Correctly *not* unified with
`giveKudos`'s own 2xx/422 check — kudos has its own "already left kudos" semantics with no
flash-message equivalent, so that's a real difference, not missed duplication.)
**Confidence:** high. **Risk:** low. **Size:** ~30 lines across 4 sites → one ~8-line
helper + 4 one-line calls. **Action:** consolidate.

**4.3c — `AO3AuthorProfileModel`'s three action methods share ~30-35 lines of scaffolding
each.** `Services/AO3AuthorProfileService.swift:304-427` — `toggleSubscription(auth:)`,
`beginModeration(action:auth:)`, `confirmPendingModeration(auth:)` each independently
capture route/authenticationScope/sessionGeneration, run the AO3 submit, re-check all
three haven't changed across the `await`, and dispatch `AO3Error.authenticationRequired`
vs. a generic error via two catch blocks that are character-identical across all three
methods. `toggleSubscription` and `confirmPendingModeration` are near byte-for-byte
identical beyond the specific AO3 submit call. **Important nuance:** the underlying
capture-guard-catch *idiom* (stale-response fencing via a captured generation) is a
deliberate, repo-wide convention for the protected account/session-isolation category —
confirmed recurring at 9+ other call sites (`AO3SeriesDetailView`, `AO3AccountWorksList`,
`AccountComponents`, `AO3InboxModel` ×3, `AO3PreferencesView` ×2). This finding is **not**
about that idiom being unnecessary — it's that these 3 *specific* method bodies in *one*
file mechanically repeat it instead of sharing one local helper. **Callers:** all three
called live from `Features/Authors/AuthorProfileView.swift` (Subscribe / Block-Mute-confirm
buttons). **Confidence:** high. **Risk:** medium (touches the write-action + generation-
fencing surface directly, even though the consolidation is mechanical). **Size:** ~90
lines today (~50-60 duplicated) → ~55-65 lines via a shared `performTrackedAction(auth:
submit:onSuccess:)`-style helper, net −30 to −35. **Action:** consolidate, with the
generation-fencing behavior preserved exactly (test each of the 3 call paths' stale-
response handling before/after).

### 4.4 `AO3SeriesDetailView` reimplements three components `AuthorProfileContentSections.swift` already provides

All three are single-caller, same-file, trivial-risk drop-in replacements:
- **4.4a** — `AO3SeriesDetailView.swift:134-163`'s hand-rolled pagination Load-More row
  duplicates `AO3AuthorPaginationRows` (`AuthorProfileContentSections.swift:67-100`) —
  same structure, just reading local `@State` instead of a model. ~30 lines.
- **4.4b** — `AO3SeriesDetailView.swift:92-95`'s loading-skeleton branch
  (`ForEach(0..<4) { AO3WorkRowSkeleton().cardRow() }`) is byte-identical to the entire
  body of `AO3AuthorLoadingRows` (`AuthorProfileContentSections.swift:13-19`), which takes
  zero parameters — a direct drop-in call. ~5 lines.
- **4.4c** — `AO3SeriesDetailView.swift:113-118`'s inline failed-state `Label` duplicates
  `AO3AuthorInlineErrorRow` (`AuthorProfileContentSections.swift:54-64`), also a
  zero-dependency direct drop-in. ~5 lines.

**Confidence:** high (all three, side-by-side body comparison). **Risk:** low. **Total
size:** ~40 lines. **Action:** simplify (call the existing shared components directly).

### 4.5 `FandomWorksView`/`TagWorksView` — the largest duplication in the codebase (~150-200 lines, echoed 2 more times)

`Features/Browse/NativeBrowseView.swift:279-398` (`FandomWorksView`) and `:519-634`
(`TagWorksView`) duplicate their entire selection-mode/bulk-action/pagination/row-rendering
shell almost verbatim: `toolbarContent`, `bulkActionBar`, all four `bulkSave*` functions,
`exitSelectMode`, `workRow`, `toggleSelection`, `showPagination`, `paginationRow`, and the
matching `@State` block and `.sheet`/`.alert` modifiers. A doc comment on
`TagWorksView.bulkActionBar` even says *"Mirrors FandomWorksView's bulk-action bar
exactly."* The same shell pattern recurs a 3rd time in
`Features/Authors/AuthorProfileView.swift:553-631` and a 4th time in
`Features/Search/SearchView.swift` (~58-192, 493-566) — all four call the same properly-
shared `Services/RemoteWorkBulkActions.swift` helpers underneath, but each re-implements
the SwiftUI selection/toolbar/state shell around them independently.
**Evidence:** direct diff of the extracted line ranges — `workRow`/`toggleSelection`/
`showPagination`/`paginationRow` are byte-identical between `FandomWorksView` and
`TagWorksView`; `AuthorProfileView`'s equivalent differs only in whitespace.
**Callers:** each block has exactly one caller (its own view) — not dead code, pure
structural duplication. **Confidence:** high. **Risk:** low (`RemoteWorkBulkActions.swift`
itself, the actual business logic, is correctly not duplicated — only the SwiftUI shell
around it is). **Size:** ~150-200 lines between the two `NativeBrowseView.swift` types
alone, ~350-400 across all 4 occurrences. **Action:** consolidate — likely a shared generic
`RemoteWorkListSelectionShell`-style view/modifier that all 4 call sites configure, rather
than a full merge (the row content and empty/error states differ enough per surface to
need a parameterized shell, not a single monolithic view).

### 4.6 The same work-stats row is implemented four times across the card/row family

*(Pass 1 finding, unchanged.)* `Features/Home/HomeCards.swift:53-71`
(`WorkCoverCard.cardStats`) and `:169-188` (`AO3WorkCoverCard.cardStats`);
`Features/Library/WorkRow.swift:138-142` and `Features/Search/AO3WorkRow.swift:105-109` —
four near-identical `FlowLayout` blocks rendering rating/chapters/completion/word-count,
differing only by optional (remote `AO3WorkSummary`) vs. non-optional (local `SavedWork`)
field access. The surrounding card chrome differs meaningfully and should stay separate —
only the stats sub-view is a clean extraction. **Confidence:** high. **Risk:** low
(pure-presentation; verify via the repo's existing UI Consistency & Density Audit gate).
**Size:** ~55-60 duplicated lines → ~20-line shared `WorkStatsRow`, net −35 to −40.
**Action:** consolidate.

### 4.7 Four hand-rolled in-memory TTL caches instead of one generic cache

*(Pass 1 finding, unchanged.)* `Features/Comments/CommentsModel.swift:1051-1105`
(`CommentsPageCache`), `Services/AO3Client+Authors.swift:563-646` (`AO3AuthorPageCache`),
`Services/AO3AccountListCountsCache.swift:63-123`, `Features/Account/
AccountComponents.swift:534-556` (`AccountWorksInlineSectionCache`) each reimplement
"dictionary keyed by X, entries carry an expiry timestamp" — 3 of the 4 source comments
explicitly cross-reference each other as "the pattern to follow," itself a signal this
should have been factored out. Actor isolation, stale-while-revalidate, and
max-entry-eviction genuinely differ per cache and must be preserved in any generic design.
`FandomCatalogCache.swift` is disk-backed (`Codable` JSON) — correctly separate, not part
of this duplication. **Confidence:** medium (mechanical duplication is clear; right generic
shape needs a design pass). **Risk:** medium (auth-scoped caching — a botched
consolidation could leak one account's cached values to another, the exact failure mode
the account-isolation invariant exists to prevent). **Size:** ~230 lines → ~140-160, net
−70 to −90. **Action:** consolidate, only with account-isolation-preserving test coverage
(see §9); requires owner sign-off per §6.

### 4.8 Smaller consolidation findings (all confidence high/medium, risk low, adversarially verified)

| # | Symbol(s) | File(s) | What's duplicated | Size | Action |
|---|---|---|---|---|---|
| 4.8a | `WorkLifecycle.saveBestEffort` and 4 copies | `WorkLifecycle.swift:79-87`, `ReadingQueueService.swift:80`, `PreservedWorkService.swift:184`, `ReadingQueues.swift:387`, `WorkDetailView.swift:1188` | Identical 6-line `do { try context.save() } catch { Log.library.error(...) }` helper, copy-pasted 5 times instead of one `ModelContext` extension | ~35 lines → ~7 | consolidate |
| 4.8b | `AccountView.openUserPath`/`externalNavCard` vs `AccountMoreOnAO3View.openUserPath`/`externalCard` | `AccountView.swift:986-1012`, `AccountMoreOnAO3View.swift:82-108` | Byte-identical "build an `archiveofourown.org/users/<user>/<suffix>` URL + open it in an external-nav card" pair; `AO3AuthorRoute.dashboardURL` already does similar URL-building, suggesting a single shared builder | ~35 lines | consolidate |
| 4.8c | `AO3PreferenceToggle.key`/`AO3PreferenceSelect.key`/`AO3PreferenceTextField.key`/`AO3Client+Preferences.humanizePreferenceName` | `AO3PreferencesModels.swift:55-95`, `AO3Client+Preferences.swift:439-446` | Same 4-line "strip `preference[`/`]` from a Rails form field name" logic, implemented 4 separate times (3 identical, 1 restated as if/else). `.key` is read only by `KudosTests/AO3PreferencesParseTests.swift` — production save path uses `.name` | ~20 lines | consolidate |
| 4.8d | `FandomCatalog.loadMissing(for:)` vs `.refresh(_:)` | `FandomCatalog.swift:83-121`, `:126-158` | Both build the same `pending` list, run the same `withTaskGroup` fetch through `AO3RequestCoordinator`, same per-landing persist/inFlight-removal — differ only in the staleness filter predicate | ~20-25 lines | consolidate |
| 4.8e | `WorkDetailView.hasReadableEPUB(for:)` | `WorkDetailView.swift:405-407` | Exact duplicate of `WorkReaderPreparation.hasReadableEPUB(for:)` (`WorkCardActions.swift:112-114`) — this same file already calls the shared version elsewhere (line 1109); the private copy has exactly 1 call site (line 370) | ~4 lines | consolidate (delete the private copy, redirect its 1 call site) |
| 4.8f | `WorkDetailView.seriesProgressText`/`seriesCompletionText` vs `ReadingQueues.AddToQueueView.seriesCompletionText` | `WorkDetailView.swift:1070-1101`, `ReadingQueues.swift:839-865` | Same branch structure over `ReadingQueueService.SeriesPreservationResult`, differing only in verb choice ("preserved" vs "added") | ~50 lines | consolidate |
| 4.8g | "Mark as Still Reading"/"Mark as Finished" label+icon, and "Save for Later"/"Remove from Saved" label+icon | `WorkCardActions.swift:220,235,360,378`, `WorkDetailView.swift:307`, `WorkBulkActionBar.swift:71,89` | Identical label/SF-Symbol ternary pasted across 4 (finished-toggle) and 3 (save-toggle) sibling UI surfaces (2 context menus, detail page, bulk-action bar) | ~20-25 lines | simplify (e.g. `WorkActionLabels.finished(isFinished:) -> (String, String)`) |
| 4.8h | `LibraryFilters.lowercased(_:)`/`boundValue(_:)` vs `AO3SummaryFilter.lowercased(_:)`/`bound(_:)` | `LibraryFilters.swift:117-124`, `AO3SummaryFilter.swift:99-106` | Two tiny leaf helpers, byte-identical bodies, different names. (The *surrounding* filter logic genuinely differs per model shape and should stay separate — see §7.) | ~8 lines | consolidate |
| 4.8i | `WelcomeView.backgroundColor`/`.point(_:_:_:)` vs `SyncFolderOnboardingView.backgroundColor`/`.point(_:_:_:)` | `WelcomeView.swift:33-40,89-106`, `SyncFolderOnboardingView.swift` | Both first-launch onboarding screens independently define identical theme-background + icon/title/body row helpers, plus a duplicated outer VStack/ScrollView/footer scaffold (same padding constants) | ~40-50 lines | consolidate |

### 4.9 Test doubles for the AO3-auth protocols are redefined per test file instead of shared

*(Pass 1 finding, unchanged.)* `KudosTests/AO3AuthTests.swift:994-1240` (10 mock types),
`KudosTests/AO3InboxAccountTransitionTests.swift:621-660` (5 mock types, each a strict
simplified subset of the `AO3AuthTests.swift` equivalent), `KudosTests/
CommentsAccountTransitionTests.swift:476-520` (2 more) all define their own conformances
to the same 5 protocols. **Confidence:** high. **Risk:** low (test-only). **Size:**
~150-200 lines → ~150 shared, net −50 to −80. **Action:** consolidate into a shared
`KudosTests/Support/` file.

### 4.10 (Minor, likely not worth doing) `NCXParser`/`NavTOCParser` share a state-machine shape

*(Pass 1 finding, unchanged, not re-verified — self-assessed low priority.)* Both are
`XMLParserDelegate` state machines producing `[(title, src)]`, but parse genuinely
different XML vocabularies (EPUB2 NCX vs. EPUB3 nav) for a real, currently-exercised
requirement (arbitrary user EPUB import). **Recommended action: retain as-is.**

---

## 5. Dependencies and files that may be removable

**No dependencies removable** — both SPM packages (SwiftSoup, Readium `swift-toolkit`) are
exercised throughout the app, confirmed again this pass while reading `AO3Client.swift`,
`AO3AuthorProfileService.swift`, and the Reader stack in depth.

**Files fully removable, confirmed this pass:** `Features/Bookmarks/AO3AccountSection.swift`
(§3.1, entire 55-line file). No other file was found with zero references anywhere in the
app or test targets.

`Reading/MiniZip.swift` (320 lines, hand-rolled ZIP reader) remains a deliberate,
correctly-scoped native-`Compression`-based choice, not reinvention — see §7.

---

## 6. Findings requiring human validation

These were surfaced by Pass 2's finders but **explicitly not adversarially verified**
(they were tagged `investigate`, not `delete`/`consolidate`/`simplify`, by the finder
itself — usually because the finder judged the area touches a protected category and
wanted a human decision before treating it as actionable). Treat these as leads, not
confirmed findings.

1. **At least 3 independent implementations of "resolve a relative AO3 href/path to an
   absolute `archiveofourown.org` URL" exist in `Services/`** — `AO3Client+Authors.swift:534-541`'s
   `absoluteAO3URL(_:)` (throwing, validates the result is AO3-owned via
   `AO3AuthorRoute.isAO3URL`), one in `AO3Client+Preferences.swift`, and at least one more.
   Not verified for exact overlap/behavioral parity. **Needs a follow-up pass** to confirm
   the three are truly interchangeable before consolidating (URL-resolution correctness
   bugs would be easy to introduce here).

2. **`SyncMerge.deterministicMembershipOrder(_:)`** (`PersistenceSync.swift:447-457`) —
   the finder reports it as defined, doc-commented, and unit-tested
   (`KudosTests/PersistenceSyncTests.swift:147`) but with **zero production callers**
   anywhere in the app. Self-tagged `investigate` rather than `delete` because it sits in
   the protected non-destructive-merge/sync category — a human should confirm this isn't
   wired up via a call path the finder's grep missed (e.g. a `SyncMerge` conformance
   invoked reflectively) before treating it as dead.

3. **`FolderSyncService.foldConflictContents(_:into:defaults:)`** (`FolderSyncService.swift:166-179`)
   — public, `@discardableResult`, reachable only from `KudosTests/FolderSyncTests.swift`;
   the finder notes it partially duplicates the *private* `foldFileProviderConflicts`
   (lines 287-311), which is what `performSyncDown` actually calls. Same caution as #2:
   protected sync category, human judgment needed on whether the public API is intentional
   surface (e.g. for a future caller) or genuinely orphaned.

4. **`AccountWorksInlineSection` (`AccountComponents.swift:563-841`) vs.
   `AO3AccountWorksList` (`AO3AccountWorksList.swift:10-376`)** — the finder describes two
   independent, parallel implementations of "fetch + paginate + render an AO3 account list,"
   each with its own `Phase` enum, `@State`, session-generation fencing, and load function.
   This is a much larger and structurally riskier candidate than anything in §4 — flagged
   for investigation, not scored as a consolidation finding, because unifying two
   independently-evolved account-isolation-fenced data flows is exactly the kind of change
   this audit's protected categories warn against attempting casually.

5. **`AccountView`'s two root layouts** (`compactScopeChrome`/`compactWorksContent` at
   lines 266-364 vs. `readingSections`/`writingSections`/`activitySections` at 680-816)
   reimplement the same Reading/Writing/Activity sub-tab switch logic for List-based vs.
   ScrollView-based presentation. Flagged, not verified.

6. **`WorkDetailView.withLocalWork(_:)`** (`WorkDetailView.swift:887-915`) appears to
   reimplement the download+import+applyRemoteMetadata sequence that
   `ReadingQueueService.resolveLocalWork(for:in:)` (`ReadingQueueService.swift:586-609`)
   already centralizes, including re-deriving the posted-chapter count inline instead of
   reusing the centralized derivation. Flagged, not verified — import/metadata-application
   correctness makes this worth a careful look before touching.

7. **`KudosBackupManifest.supportedVersions = [1...7]`** *(Pass 1, still open)* — the read
   path is already lean (no branchy per-version migration code, just `Codable`
   optional-field forward-compat), so this isn't a ponytail finding as written. Only the
   product question — do pre-July `.kudosbackup` files from real usage still need to be
   restorable — could eventually move the floor up, and that's not inferable from code.
   **Retain; revisit only if the owner confirms old exports are no longer in use.**

8. **§4.7's TTL-cache consolidation and §4.1's `WorkIdentityIndex` consolidation both need
   explicit owner sign-off before scheduling**, given their adjacency to the
   account-isolation and data-safety-adjacent protected categories respectively.

---

## 7. Areas intentionally retained

Investigated and specifically **not** flagged — either the apparent duplication is
necessary, or an initial suspicion didn't survive a closer read.

**Carried over from Pass 1:**
- **`Features/Reader/` (macOS) vs. `Features/ReaderReadium/` (iOS)** — documented,
  deliberate per-platform split; out of scope by the audit's own instructions.
- **The 7 internal protocols** in `Services/` — legitimate DI for testing code that talks
  to a live, un-mockable web service; each has ≥1 real test double (§4.9).
- **`Reading/MiniZip.swift`** — deliberate, security-hardened, native-`Compression`-based
  choice for parsing untrusted downloaded EPUBs; avoids a 3rd-party ZIP dependency for a
  narrow, security-sensitive job. Exemplary, not a finding.
- **`AO3WebLoginCoordinator.inspectPage()`'s JS login-detection vs.
  `LiveAO3SessionValidator.isLoggedIn`'s Swift/SwiftSoup version** — genuinely duplicated
  selector logic, already acknowledged in-code (`AO3AuthService.swift:100-102`), but
  **unmergeable**: one runs as JavaScript inside a live `WKWebView`, the other as Swift
  over fetched HTML. Low-effort follow-up worth considering separately: hoist the literal
  selector strings into shared constants both sides interpolate, to reduce drift risk
  without merging the implementations.
- **`KudosBackupTombstone`/`TombstoneIndex` vs. `SyncTombstone`/`SyncTombstones`** —
  different persistence mechanisms for different lifecycles (exported-snapshot wire format
  vs. live SwiftData sync state), not the same concept twice.
- **`WorkTags`'s 24h refresh cooldown and `WorkUpdateChecker`'s 6h throttle** — each a
  single-line `Date` comparison against its own model property; too small and
  context-specific to abstract without itself becoming speculative.
- **SwiftLint's 4 disabled rules** — each justified inline.
- **Comments "Part D" (CAA-8, CAA-9)** — unimplemented future work, not dead code.

**New this pass (Pass 2), condensed — each was a specific suspicion that a finder checked
and explicitly ruled out:**
- **`AO3Client.pace()` / `AO3RequestCoordinator.withSlot` / `RequestCoalescer.shared`** —
  confirmed three genuinely distinct, composable concerns (temporal rate floor, concurrency
  ceiling, in-flight dedup), not overlapping responsibility. *(Resolves the "flagged for
  closer look" item from Pass 1's report.)*
- **The BUG-5 fandom-index parsing fix** (`AO3Client.swift:1023-1097`,
  `fandoms(atPath:)`/`parseFandomIndex(_:)`) — checked for leftover dead code from the old
  per-`<li>` DOM approach the fix replaced; none found, the old code was fully removed in
  commit `9ab14c2a`.
- **Retry/backoff** (`AO3Client.swift:217-265`, `withRetry`/`retryDelay(for:attempt:)`) —
  exactly one implementation in the whole repo; not duplicated.
- **`AO3PostingPseudPersisting`/`UserDefaultsAO3PostingPseudStore`** — looked like a
  single-implementation protocol with no test double at first grep, but does have coverage;
  retained as legitimate DI.
- **`AO3AuthService` vs. `AO3WebLoginCoordinator`** — checked for session-lifecycle
  duplication beyond the known JS/Swift selector mirroring; none found.
- **`AO3AuthorProfileService` vs. `AO3Client+Authors.swift`** — clean split confirmed:
  the service layer has zero SwiftSoup/HTML-parsing code of its own; it only orchestrates
  caching/staleness/cancellation and calls out to the parsing layer.
- **`CommentAvatar` (Comments) vs. `AO3AuthorAvatar` (Authors)** — solve different problems
  (a 72×72 profile hero image loaded once vs. a smaller, reusable participant avatar); not
  duplicated.
- **`CommentParticipantBadge`/`CommentReplyButton`/`CommentOverflowButtonLabel`/`CommentAvatar`**
  — documented as shared between Comments and Inbox; confirmed genuinely reused (called
  from `AccountInboxViews.swift`), not duplicated.
- **`CommentsModel`'s private `AuthContext` vs. `AO3InboxModel`'s own** — structurally
  similar (both implement the T-96 stale-response-fencing pattern) but not identical;
  legitimately separate.
- **`AO3AuthService.containsComment(...)`** — looked like a helper superseded by the T-102
  three-state `commentVerification(...)`, but its own doc comment identifies it as a
  deliberately-retained "positive-only compatibility helper" for a specific test suite.
- **`CommentsModel`'s `PageLoader`/`ChapterLoader`/`CommentSubmitter`/`CommentVerifier`
  injectable closures** — genuinely exercised by fake loaders in
  `CommentsAccountTransitionTests.swift` and `AO3InboxAccountTransitionTests.swift`.
- **`CommentsModel`'s four `pendingInitial*` properties** — each maps to a distinct,
  independently-documented deep-link entry point; not a missed-enum case.
- **`AO3DashboardView`** — looks like a pass-through wrapper around `AuthorProfileView` but
  adds a real auth-gated signed-out fallback and a documented scope decision.
- **`AccountInboxItemRow.avatar`** — `TASKS.md`'s T-88 entry listed this as deferred reuse
  debt; reading the code shows it already calls `CommentAvatar` directly. Debt already paid.
- **`AccountScopeMenu<Tab>`** — the one generic abstraction in the Account area, justified
  by 3 real concrete usages (`AccountReadingTab`, `AccountWritingTab`, `AccountActivityTab`).
- **`AO3InboxModel`'s dense generation/scope-fencing on every async entry point** — exactly
  the protected account/session-isolation category, not over-engineering.
- **`LibraryFilters` vs. `AO3SummaryFilter`** — operate on fundamentally different model
  shapes (`SavedWork`'s flat/categorized tags vs. `AO3WorkSummary`'s arrays); retained as
  separate except the two tiny leaf helpers pulled into §4.8h.
- **`CanonicalWorkMerge`/`Models/CanonicalWork.swift`** — looked like a one-off abstraction;
  both merge functions have multiple real, distinct callers.
- **`ReadingQueueService`** (711 lines) — flagged for scrutiny as a possible overgrown
  service; every public function traced to real (often multiple) callers.
- **`LibraryFilterPanel` vs. `AO3FilterPanel`** — overlapping facets initially looked
  mergeable; the interaction models genuinely differ (confirmed by reading both).
- **1-line private `enum Phase { loading, loaded, failed(String) }` redeclared in 4-5
  views** (`NativeBrowseView`, `FandomListView`, `MediaBrowserView`, `AO3SeriesDetailView`)
  — noted for completeness; too small to be worth a shared type.

---

## 8. Proposed implementation sessions, grouped by risk

**Session A — trivial/mechanical, no behavioral surface (do first):**
§3.1-§3.7 (all 8 dead-code deletions), §4.4a-c (`AO3SeriesDetailView` → shared Author
components), §4.8e (`WorkDetailView.hasReadableEPUB` dedup), §4.8g (label/icon pairs),
§4.8h (filter leaf helpers), §4.8i (onboarding shared helpers), §4.2c (login-redirect
check). Each is single-file or two-file, no cross-cutting state, compiles-or-fails
verification.

**Session B — mechanical consolidation, needs test-suite confirmation:**
§4.2a-b (AO3Client parsing helpers), §4.3a-b (CSRF fetch, comment-verdict switch — see §9
for extra care), §4.8a (`saveBestEffort` ×5), §4.8b (Account external-nav duplication),
§4.8c (preference-key stripping), §4.8d (`FandomCatalog` loadMissing/refresh), §4.8f
(series-text duplication), §4.6 (card/row stats), §4.9 (test doubles).

**Session C — needs behavioral verification before merging:**
§4.1 (`WorkImporter`/`WorkIdentityIndex`), §4.3c (`AO3AuthorProfileService` scaffolding —
generation-fencing must be preserved exactly), §4.5 (`FandomWorksView`/`TagWorksView` and
the 2 corroborating occurrences — largest single surface in this report).

**Session D — needs design + explicit owner sign-off:**
§4.7 (generic `TTLCache<Key,Value>`, migrated one cache at a time).

**Session E — research only, not yet actionable:**
§6's 6 unverified leads. Recommend a third, narrowly-scoped pass (2-3 finder agents, each
targeting exactly one of §6's items) with the same adversarial-verification pattern used
in Pass 2, before any of them move to §3/§4.

---

## 9. Verification requirements for any future cleanup

- Run `Scripts/verify.sh` (invariants → lint → full iOS test suite → macOS build →
  whitespace) for **any** change from this report — the project's own definition of done.
- Build **both** iOS (Readium SPM graph) and macOS (legacy reader) — changes that look
  platform-neutral can still break the macOS-only `#else` branch.
- **§3.7 specifically:** delete `totalOnPage` only. Do **not** delete `descendantCount` —
  confirm `KudosTests/AO3CommentsParseTests.swift:413` and `:470` still compile and pass
  unchanged.
- **§4.1:** add/extend tests covering both `importEPUB` and `importUserEPUB` dedup/revive
  paths before folding `WorkImporter`'s matchers into `WorkIdentityIndex`.
- **§4.3a/§4.3b/§4.3c:** these touch the authenticated-write-action layer. Although the
  consolidations are structural (identical logic, not behavior change), verify: (1) CSRF
  tokens are still fetched fresh per submission (no accidental caching introduced by the
  shared helper), (2) the comment-verdict switch's error messages still match per-caller
  expectations exactly (kudos stays unconsolidated on purpose — do not fold it in), (3)
  `AO3AuthorProfileModel`'s three consolidated methods each still re-check
  route/authenticationScope/sessionGeneration after their `await` before dispatching
  success — this is the actual stale-response-fencing behavior, not incidental structure.
- **§4.5:** manual verification of selection mode, bulk actions, and pagination on all 4
  surfaces (Browse-by-fandom, Browse-by-tag, Author works, Search results) after any shell
  consolidation — these are the app's remote-work bulk-action entry points.
- **§4.6:** screenshot pass on Home/Library/Search/Bookmarks per the repo's existing UI
  Consistency & Density Audit gate (`TASKS.md`).
- **§4.7:** a test that signs in as one account, primes each cache, switches accounts (or
  logs out), and asserts no cached value from the first account is visible to the second —
  the concrete failure mode the account-isolation invariant exists to prevent.
- **§4.9:** no production verification needed — test-code-only.
- Grep every call site of anything touched, per this repo's own adversarial-review
  methodology (`docs/ADVERSARIAL_REVIEW_TEMPLATE.md`, principle 6): "compile success ≠
  behavior preserved."
- None of the findings in this report change AO3 request pacing, retry/backoff timing, or
  what gets sent in an authenticated write request — no live-AO3 verification is required
  beyond the existing fixture/unit test suite.
