# Brief: C2 — collections moderation and account-settings collections

_Written 2026-09-25 by Codex (gpt-5.6-sol), read-only against 92480fab, from the two C2 audits, critic-wave2.json, otwarchive-facts.json and the cloud session's earlier partial brief (which it replaces). The collections session-fence work it names as in progress landed in 7870da71._

Source of truth: snapshot `92480fab`, the two C2 audits, `critic-wave2.json` corrections, `otwarchive-facts.json`, and the partial `brief-C2.md`. Paths are under `kudos-ao3-reader/` unless prefixed otherwise.

## Re-checked against 92480fab

- **Dropped as already fixed: no audited C2 gap was fully closed.**
- Do not reopen T-240’s adjacent fixes: account-wide Collection Items now defaults to **Awaiting you**, collection rows/items/drafts are session-generation-owned, and collection-item writes are fenced around their CSRF fetch.
- T-240 did **not** fix 1s Reset: its action computes `defaultTab(slug:)`, but opacity and disabled state still compare only with `.unreviewed`.
- T-252 changed local reading queues, not these AO3 collection screens.
- The older 1bk **collection colour** gap is fixed: `WorkCollection.hue` and the create/edit swatches exist. Only the stored-but-inert Keep downloads / Show on Home effects remain.
- Q6 wins over board 1ce: AO3 has no rejection-reason field and sends no rejection email.
- Q7 wins over 1ci’s source comment: collection work blurbs do print gift recipients.
- Q8 wins over 1bx: participant rows expose no added/request date.
- Q10 confirms native deletion is technically buildable, but it remains an owner-gated new AO3 write.

## Integration fence

Another session is changing these files now:

- `Features/Account/AO3CollectionFormView.swift`
- `Services/AO3CollectionActions.swift`
- `Features/Account/AO3CollectionsList.swift`

That fix makes create/update re-check the AO3 session generation around the CSRF fetch and treats `.loading` as unsettled in the list reload rule. Rebase C2 onto it. Do not replace, weaken, or duplicate those guards.

C2-1 touches `AO3CollectionActions.swift`; C2-6 and C2-11 touch `AO3CollectionsList.swift`; C2-9 and C2-10 touch `AO3CollectionFormView.swift`.

Never contact AO3 during implementation or verification. Every AO3 write below may be built and fixture-tested, but agents must not exercise it live.

---

## Bugs

### C2-1 — Reject asks for a reason AO3 discards and falsely promises an email (1ce)

- **Files:** `Features/Challenges/RejectReasonSheet.swift:3-72,83-176`; `Features/Challenges/CollectionModerationView.swift:86-96`; `Services/AO3CollectionActions.swift:14-33,119-135`.  
  **Session-fence overlap:** `AO3CollectionActions.swift`.
- **Wrong today:** the sheet says “AO3 emails your reason,” makes the field required, and calls `rejectCollectionItem(...reason:)`. That method validates the text and then posts only `collection_approval_status=rejected`.
- **Ground truth:** Q6: AO3 neither accepts/stores a reason nor emails on rejection.
- **Spec quote superseded:** “AO3 emails your reason to kestrelmoon. It cannot be edited afterwards.”
- **Exact change:** remove the reason editor entirely. Replace the sheet with a destructive confirmation alert from `CollectionModerationView`: explain that AO3 sends no reason, the work remains on AO3, and only collection approval changes. Button label: **Reject**. Change the action to `rejectCollectionItem(slug:itemID:)`; remove `emptyRejectReason` and the unused reason parameter. C2-4 deletes the second caller.
- **AO3 WRITE — build only; never agent-exercise.**
- **Proving test:** extend `KudosTests/AO3CollectionItemsScopeTests.swift` to assert that a rejected moderator draft encodes only the existing approval field—no reason/comment parameter. `git grep` must find neither “emails your reason” nor `emptyRejectReason`.

### C2-2 — Reset is disabled on the wrong Collection Items tab (1s)

- **Files:** `Features/Account/AO3CollectionItemsView.swift:49-63,238-270`; `KudosTests/CollectionItemsWriteVerificationTests.swift`.
- **Wrong today:** Reset performs `defaultTab(slug:)`, but its opacity and `.disabled` still compare with `.unreviewed`. On the account-wide page, the default is `.invited`, so Reset is enabled on its default and disabled while it has work to do.
- **Spec quote:** “Reset.”
- **Exact change:** single-source the default tab in a small pure rule, then use it for the action, opacity, and disabled state. Collection scope: `.unreviewed`; account scope: `.invited`.
- **Proving test:** add the four combinations: account/invited disabled, account/unreviewed enabled, collection/unreviewed disabled, collection/invited enabled.

### C2-3 — Moderation presents page-one queue counts as the whole queue (1cd)

- **Files:** `Features/Challenges/CollectionModerationView.swift:119-160,625-644`; `Services/AO3Client+Collections.swift:112-132`; `Models/AO3CollectionDetailModels.swift:387-395`.
- **Wrong today:** `collectionModeration` fetches unreviewed page 1. The header and section print `awaitingReview.count` as “N works awaiting review,” and no later page is reachable.
- **Spec quote:** “4 works awaiting review.”
- **Exact change:** retain the `itemsForm.currentPage/totalPages` already returned by the parser. Add `SearchPaginationBar` for the review queue. Page changes fetch only `collectionItems`; do not refetch participants or collection show data. Copy must say **“N works awaiting review on this page · page X of Y”** whenever paged. Preserve the current page after approve/reject unless it becomes empty, then move to the nearest valid page.
- **Proving test:** add a pure moderation-tally test for single-page and multi-page wording, plus parser coverage that the pager’s `totalPages` reaches `AO3CollectionModeration`.

### C2-4 — `ModeratedItemsView` is an orphaned duplicate with dishonest totals and rejection copy (1bx screen 1)

- **Files:** delete `Features/Challenges/ModeratedItemsView.swift`; remove its stale references from comments in `CollectionModerationView.swift:203-208`.
- **Wrong today:** no route instantiates it. It duplicates reachable 1cd, calls page-one approved/rejected counts totals, and repeats the false “AO3 emails” claim.
- **Spec quote:** “Moderated items … Waiting for review … Recently decided.”
- **Exact change:** delete it. Keep `CollectionModerationView` as the single moderation surface. Do not move its “Recently decided” figures into 1cd: AO3 supplies paged rows, not exact totals.
- **Proving test:** both platform builds prove removal; `git grep -F 'ModeratedItemsView'` must be empty.

### C2-5 — Collection detail hides later pages and labels loaded-row counts as totals (1ci)

- **Files:** `Features/Account/AO3CollectionDetailView.swift:30-42,127-140,168-188,227-243,365-403`; `Services/AO3Client+Collections.swift:12-53,187-258`; `KudosTests/AO3CollectionParsingTests.swift`.
- **Wrong today:** Works, Bookmarks, and People discard `currentPage/totalPages`; only page 1 is reachable. Section headers show `rows.count` without saying it is page-limited. Members uses `people.count`, also page 1.
- **Spec quotes:** “Recent 168”; “The collection page is its own paged list”; “Members 41.”
- **Exact change:** keep page state per segment and reuse `SearchPaginationBar`. Parse Works/Bookmarks totals from the collection show stats when present; title work/bookmark sections **Recent** and use those exact totals. For People, show “N on this page · page X of Y”; remove the Members stat until an exact total exists rather than presenting page 1 as a total.
- **Proving test:** fixture-test show-page Works/Bookmarks stat parsing and each segment’s pager. Add a pure count-label test proving paged People never prints its loaded count as a total.

### C2-6 — Collections sort/filter runs on one server page while presenting itself as a list-wide operation (1bm)

- **Files:** `Features/Account/AO3CollectionsList.swift:16-53,78-84,248-259,349-411`; `Features/Account/AO3CollectionsFilter.swift:3-8,80-145`; `KudosTests/AO3CollectionSessionReloadTests.swift`.  
  **Session-fence overlap:** `AO3CollectionsList.swift`.
- **Wrong today:** computed sorting and filtering operate only on `displayedCollections`, which is the current server page.
- **Spec quote:** “Need the full collection list in memory first — several paged fetches before the first sort.”
- **Exact change:** after the user applies any non-default client sort/filter, fetch all collection-index pages sequentially through the paced client, preserving AO3 order before applying `AO3CollectionsFilter`. Fetch once per session generation; subsequent filter changes reuse the full in-memory index. Every page must retain the current load-generation/session-generation checks. Cancel promptly on dismissal, sign-out, or account switch.
- **Proving test:** add a pure `needsWholeIndex` rule and a page-accumulation test that preserves server order and discards a stale-generation result. Extend T-240’s reload tests so `.loading` remains unsettled.
- **AO3 reads:** fixture-test only; do not contact AO3.

---

## Small gaps with no owner decision

### C2-7 — Finish the existing moderation card and section copy (1cd)

- **Files:** `Features/Challenges/CollectionModerationView.swift:139-190,203-229,428-558`; `KudosTests/AO3CollectionParsingTests.swift`.
- **Spec quotes:** “kestrelmoon · … · submitted 3 Nov”; “Owners and moderators 4”; “Invite a maintainer ›”; “Creators are hidden from everyone but maintainers.”
- **Exact change:**
  - Use the already-parsed `item.itemDateText`: `"<creator> · submitted <date>"`; omit the suffix when empty.
  - Do not invent word count or tags.
  - Show the maintainers value as the bare number and render Invite as a `SubjectFormRow` with disclosure.
  - Add the anonymity explanation below the Creators row.
  - Add honest footnotes: rejection sends no reason; reveal and remove-anonymity are separate confirmed AO3 writes.
- **Proving test:** add a pure byline formatter test for present/absent dates. Screenshot the screen in all four themes.
- **AO3 WRITES already present — never agent-exercise:** approve, reject, reveal, un-anon, accept, decline.

### C2-8 — Add the missing Tag Set review footnote (1ch)

- **Files:** `Features/Challenges/TagSetView.swift:173-189`.
- **Spec quote:** “Nominated characters and relationships have to be associated with a fandom before they can be approved. The queue groups by fandom for that reason.”
- **Exact change:** render that caption immediately after `reviewQueueList`, using the existing secondary-footnote styling.
- **Proving test:** visual screenshot with a fixture-backed review queue; no new logic test.
- **AO3 WRITES already present — never agent-exercise:** tag-set save and nomination reject are unchanged.

### C2-9 — Surface the collection form’s existing Challenge field (1bl)

- **Files:** `Features/Account/AO3CollectionFormView.swift:110-129`; `Models/AO3CollectionDetailModels.swift:223-267`; `Services/AO3Client+Collections.swift:580-730`; `KudosTests/AO3CollectionParsingTests.swift`.  
  **Session-fence overlap:** `AO3CollectionFormView.swift`.
- **Spec quote:** “Set up a challenge · None ›” and “Gift Exchange or Prompt Meme.”
- **Exact change:** add Challenge between Preferences and Profile. Parse the existing select’s options from the fetched AO3 form and bind a menu to `challengeType`; do not hard-code labels or add another request.
- **Proving test:** fixture with None/Gift Exchange/Prompt Meme options; assert selected value parses and the existing form encoder round-trips the changed value.
- **AO3 WRITE — save/create only; build and fixture-test, never agent-exercise.**

### C2-10 — Expose two fields already parsed and silently round-tripped (1cg)

- **Files:** `Features/Account/AO3CollectionFormView.swift:83-129`; `Services/AO3Client+Collections.swift:648-658,689-730`; `KudosTests/AO3CollectionParsingTests.swift`.  
  **Session-fence overlap:** `AO3CollectionFormView.swift`.
- **Spec quotes:** “Tagline Coastal fic, all fandoms”; “Email new members.”
- **Exact change:** add a Tagline text row bound to `form.description` and an Email new members toggle bound to `emailNotify`. Keep AO3’s existing form order; do not start the owner-dependent 1cg regroup.
- **Proving test:** extend the collection-form fixture to parse both values, mutate them, and assert `collectionFormParameters` posts the mutations without losing unrelated fields.
- **AO3 WRITE — save/update only; build and fixture-test, never agent-exercise.**

### C2-11 — Bring Collections list/filter chrome to the existing sheet grammar (1bm, 1r)

- **Files:** `Features/Account/AO3CollectionsFilterPanel.swift:16-141`; `Features/Account/AO3CollectionsList.swift:78-90,151-185,238-305,503-520`; `Features/Account/AO3CollectionScreenDecisions.swift:19-42`.  
  **Session-fence overlap:** `AO3CollectionsList.swift`.
- **Spec quotes:** “✕ Sort and filter ✓”; status chip “Revealed”; “AO3 collections only … local collections live in Home.”
- **Exact change:**
  - Reuse the `WorksScopeAndSort` `NavigationStack`/inline-title/xmark/checkmark grammar.
  - Edit a draft filter: ✕ discards; ✓ commits; Reset changes the draft.
  - Draw Revealed/Unrevealed and Anonymous as status chips; remove Unrevealed from the metadata sentence.
  - Add an honest footer: **“AO3 collections. Local collections live in Library.”** Do not copy the spec’s “read-only” claim—the screen already has native edit/manage writes.
- **Proving test:** add pure tests for draft cancel/apply and status labels. Screenshot filter sheet and cards in all four themes.

### C2-12 — Give each account-wide Collection Item card its collection’s hue (1s)

- **Files:** `Features/Account/AO3CollectionItemsView.swift:303-320,507-559`.
- **Spec quote:** “Each card in its collection’s own hue.”
- **Exact change:** derive each card palette from `CoverArt.workHue(fandoms: [], title: item.collectionTitle)` instead of passing the screen-wide `theme.scopePalette`. Leave the page wash unchanged.
- **Proving test:** extend the existing cover-hue test with two collection titles and screenshot a fixture page containing at least two collections.

---

## Needs the owner

- **1cd — Message creator:** should this be a labelled route into the native comment composer—an additional AO3 write surface—or should it remain navigation to the work and be renamed **Open work**? Current icon-only “Message creator” opens the external work URL and sends nothing.
- **1cd / 1bx — unavailable moderation metadata:** AO3 exposes no participant request/added date (Q8). Should the spec permanently drop those dates? Should Kudos make extra People/work-summary reads for work counts, fandoms, tags, and word counts, or keep the honest lighter cards?
- **1cg — edit-form architecture:** should Edit Collection become a separate 1cg layout with Basics / Description / Membership / Anonymity / Maintainers / At AO3, or should one AO3-order form continue serving New and Edit? This decides the header counts, maintainers fetch, profile-editor pushes, and reveal-date placement.
- **1bl — presentation:** should New/Edit Collection change from navigation push to a modal xmark/checkmark sheet?
- **1bl — native delete:** should Kudos add the owner-only irreversible flow from Q10—GET `/collections/:slug/confirm_delete`, then one single-shot `_method=delete` submission—or keep opening AO3’s confirmation page? **New AO3 write; if approved, build but never agent-exercise.**
- **1bl — icon upload:** should Kudos take on PhotosPicker plus multipart `collection[icon]` upload, or explicitly leave icon replacement on AO3?
- **1s — approval control:** keep the denser three-way segmented control, or change to the board’s status chip plus menu? Both invoke the same existing staged AO3 write.
- **1bm / 1r — expensive account-wide facts:** approve extra collection/participant/item reads for Member/Invited filters, “Has works of mine,” the Your items badge, and per-card approval/own-work counts—or explicitly drop those board elements?
- **1ch — Tag Set ownership/full editing:** add a new owned-tag-set show/form parser and more AO3 writes for owners, moderators, visibility, nomination state, and limits—or keep the current four-field editor and read-only settings?
- **1bk — stored toggles with no effect:** should `keepsWorksOffline` exempt every member work from cleanup, and should `showsOnHome` create a Home shelf above Recently Updated? The fields and UI already exist; only behavior is missing.
- **1ab — retention and notifications:** should Settings gain a destructive download-retention sweep? Should the networking policy change to permit background subscription/inbox polling for notifications? Do not add inert controls.

## Later

- **1ci Gift badge:** Q7 confirms recipients are present. Add a transient recipient field to `AO3WorkSummary`, parse gift links from work-blurb headings, and draw the badge; no SwiftData migration is needed.
- **1ci exact Members total:** either discover a real total in known markup or crawl all People pages after owner approval; never reuse page-one count.
- **1cd reveal dates:** reuse `AO3ChallengeSettings.worksRevealAt/authorsRevealAt` for challenge collections; keep state-only rows for ordinary collections.
- **1bl Byline/parent/profile editors:** pseud-name mapping, parent chooser, and full-height Introduction/FAQ/Rules editors are useful but larger than C2.
- **1cg header counts and maintainers:** require show/participants data not available at two of the form’s three call sites; do after the owner chooses the edit-form architecture.
- **1r Your items count and per-card moderation facts:** defer with the account-wide request-budget decision above.
- **1ab visual redesign:** the broader Settings card conversion, consolidated Reading group, Downloads placement, and About/account regroup are outside this collections session.
- **1ch ownership rows and writable limits:** depend on the owner decision and new parser/write scope above.
