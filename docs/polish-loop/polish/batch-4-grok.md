# Batch 4 — Collections polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html`. Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic — anything that needs a running screen is called out as unverified.

Where `docs/REDESIGN_DECISIONS.md` or `docs/audits/2026-09-24/brief-C2.md` already supersedes an artboard, that is recorded under the screen’s checked list, not filed as a defect to revert.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1bk | Local collection, new and edit | `NewCollectionSheet.swift`, `Collections.swift` (`CollectionDetailView`), `CollectionReorderSheet` |
| 1r | AO3 collections list | `AO3CollectionsList.swift`, `AO3CollectionCard`, `AO3CollectionScreenDecisions.swift` |
| 1s | Manage collection items | `AO3CollectionItemsView.swift`, `AO3CollectionItemCard` |
| 1bl | AO3 collection, new / edit / delete | `AO3CollectionFormView.swift` |
| 1bm | Sort and filter sheet | `AO3CollectionsFilterPanel.swift`, `AO3CollectionsFilter.swift` |
| 1ci | Collection as a reader sees it | `AO3CollectionDetailView.swift`, `AO3WorkRow.swift` (`.searchLedger`) |
| 1cd | Collection moderation | `CollectionModerationView.swift`, `CollectionModerationCopy` |
| 1ce | Reject | The alert on `CollectionModerationView` (no separate sheet) |
| 1cg | Collection settings | Not a view. “Collection Settings” pushes `AO3CollectionFormView` (`AO3CollectionDetailView.swift:339`) |
| 1ch | Tag set | `TagSetView.swift` |
| 1bx | Maintainers (queue folded into 1cd) | `CollectionMaintainersView.swift` |

---

## Findings

### batch-4-1 — P1 — 1bl — `AO3CollectionFormView.swift:83`

**Artboard:** delete confirmation title **Delete “Slow Burn Exchange 2026”?** Body: **“The collection, its challenge settings and its 31 gift assignments are removed from AO3. The works stay with their creators — but any that were unrevealed become revealed, and any that were anonymous show their creators. Type the collection name to confirm.”** Buttons **Delete on AO3** (15.5 semibold, `#FF453A`) and **Cancel**. Caption: “The delete alert names what AO3 actually does — unrevealed works become revealed and anonymous creators are shown.”

**Code:** title `Delete “\(name)”?` matches the shape. The message is **“This permanently deletes the collection from AO3. Its works remain on AO3. This cannot be undone.”** The button is **Delete Collection**. There is no type-to-confirm field, no mention of challenge settings or gift assignments, and no mention that unrevealed works become revealed or that anonymous creators are shown. `REDESIGN_DECISIONS` says build the destructive alert naming the collection; it does not waive those consequences.

**Smallest fix:** Put the unrevealed/anonymous sentences in the alert message (with the live work count when the form has one). Require the typed collection name before **Delete on AO3** enables. Keep the native delete.

---

### batch-4-2 — P1 — 1cd — `CollectionModerationView.swift:357`

**Artboard 1cd:** third action is a text pill **Message creator** (`600 12.5px`, white on `rgba(255,255,255,.1)`, height 34, radius 99), equal width with Approve and Reject. Footnote: **“The message button sends a comment on the work instead, for a fix rather than a refusal.”** 1bx draws the same job as a 34px comment-bubble circle and the same sentence.

**Code:** the control is a `GlassCircleButton` labelled **Message creator** (`bubble.left`). The action is `UIApplication.shared.open(workURL)` / `NSWorkspace.shared.open` — the work’s public URL in Safari or the system browser. Nothing opens the in-app comment composer, and nothing is sent. `brief-C2` already flags this as an open owner question; as shipped the name is still false.

**Smallest fix:** Either push the native comment composer, or rename the button **Open work** and route it through `AppRouter` like every other “open on AO3” row. Do not keep the label **Message creator** on a browser open.

---

### batch-4-3 — P2 — 1bk — `Collections.swift:256` / `:391` / `NewCollectionSheet.swift:191`

**Artboard edit:** the same sheet as create, titled **Edit collection** (17 semibold) over the collection name. Groups: **Collection** (Name, Description, Colour), **Behaviour** (Keep downloads, Show on Home), **Contents** (**Reorder works** · **14**, **Remove works** · **14**), **Delete** (**Delete collection**, `#FF453A`). Footer: **“Deleting keeps the works — the collection goes to Recently Deleted for 30 days and the 14 works stay in your library.”**

**PLAN B:** `…` order is Show/Hide mature · Select · Reorder (a mode; off under filters with a reason) · display mode · Expand/Collapse · page items · destructive last. **No always-on drag handles; no “Drag to reorder” hints.**

**Code:** create (`NewCollectionSheet`) matches the two groups, the placeholders **Comfort reads** / **Optional**, both toggles, and both footnotes word for word. Edit does not. `detailsSheet` is a system `Form` titled with the collection name and a **Done** button: Colour, Description, Behaviour only. Name is a separate alert **Rename Collection**. Reorder, remove, and delete live in the work-list `…` menu, in this order: Mature · **Expand All** · **Select** · Rename · Details · Reorder works · **Delete Collection**. No display-mode picker. Reorder stays enabled while a filter is on (`works.count > 1`, not the filtered list) and has no disabled reason. `CollectionReorderSheet` forces `.editMode` active (`NewCollectionSheet.swift:252`) and its subtitle is **“\(name) · drag to change the reading order”** (`:193`).

The 30-vs-90 day line is the artboard that is stale: Recently Deleted is 90 days everywhere else (`PreservedWorkService`, the alert at `Collections.swift:489`). Keep 90.

**Smallest fix:** Make Details the edit sheet from the artboard (Name included, Contents rows, red **Delete collection**, 90-day footer). In the work-list `…` menu use Mature · Select · Reorder (disabled, with a reason, while `filters.hasActiveFilters`) · display mode · Expand/Collapse · Rename/Details · Delete last. Drop the drag sentence and the forced edit-mode handles; enter reorder as a mode the way other lists do.

---

### batch-4-4 — P2 — 1bl — `AO3CollectionFormView.swift:119`

**Artboard new:** Header rows **Display title**, **Collection name**, **Byline** (placeholder **Your username**), **Parent collection**, **Contact email**. Images include **Collection icon** · **Choose** (edit: **Replace**). Preferences are exactly four switches. Profile rows are disclosures reading **Empty**, not inline editors. Edit adds **Maintainers and items** (**Owners and moderators** · 3, **Moderated items** · **4 waiting**, **Works and bookmarks** · 31, **Challenge settings** · **Gift Exchange**), a **Reveal** group (**Reveal all 31 works** and **Un-anon all creators**, `#30D158`), and a **Delete** group (**Delete collection on AO3**, `#FF453A`). Chrome is an X and a check (dimmed until the form can post). Caption: nothing dropped, nothing invented.

**Code:** pushed page, 32pt title **New collection** / **Edit collection**, bottom **Create Collection** / **Save Changes**. Header has no Byline (`ownerPseudIDs` is on `AO3CollectionForm` and never bound). Images have alt and comment and no icon row (`REDESIGN_DECISIONS`: no multipart upload — the row is simply gone, with no “on AO3” substitute). Preferences add **Email new items** (1cg’s row, relabelled; see batch-4-5). Profile fields are inline `TextField`s, placeholder **Optional**, not **Empty** disclosures. Edit has no maintainers, moderation, challenge-settings, or reveal rows (those exist on 1ci’s Manage section and on 1cd, not on this form). Delete is a secondary text button inside a card titled **Collection actions**, next to **Open Collection Settings on AO3**. Name lock on edit and the name footnote match. Challenge menu matches when AO3 sent options.

**Smallest fix:** Add the Byline row bound to the pseuds the form already parses. Keep icon upload off, but show **Collection icon · On AO3** so alt/comment are not orphaned. On edit, add the four disclosure rows into the screens that already exist (1bx, 1cd, 1ci, challenge settings) and a green Reveal/Un-anon pair that uses 1cd’s existing confirms. Sentence-case the save button.

---

### batch-4-5 — P2 — 1cg — `AO3CollectionDetailView.swift:339`

**Artboard:** its own page, kicker **Collection · maintainer**, title **Collection settings**, subtitle **Tidewrack · 168 works · 41 members**. Sections: **Basics** (Title, Collection URL, Byline, Tagline, Parent collection), **Description** (Introduction · **86 words**, FAQ · **Empty**, Rules · **214 words**, Icon · **Set**), **Membership** (**Who can join** · **By request**, **Who can add works** · **Members and invited**, **Moderated works**, **Email new members**), **Anonymity and reveal** (Anonymous, Unrevealed, **Reveal date** · **20 Dec**), **Maintainers** (named rows **Owner** / **Maintainer**, **Add a maintainer**), **At AO3** (**Close collection** · **Opens AO3**, **Delete collection** · **Opens AO3**). `brief-C2` left the regroup as an owner decision and only asked to surface Tagline and the email toggle on the existing form.

**Code:** the Manage row **Collection Settings** pushes `AO3CollectionFormView` (1bl). There is no Who can join, Who can add works, Reveal date, inline roster, or Close row. Tagline is a Header text field. The email toggle is labelled **Email new items**, and the preferences footnote says mail goes to the contact address, not to members. Close is the generic **Open Collection Settings on AO3** button (`AO3CollectionFormView.swift:413`), which opens the edit URL.

**Smallest fix:** Until the owner picks the 1cg layout, rename that button **Close collection** with value **Opens AO3**, and label the toggle with AO3’s own checkbox text (the code comment says it is item-added mail, so **Email new items** may be the honest label — then the artboard’s **Email new members** should be treated as wrong). Do not leave Close unnamed inside “Collection actions”.

---

### batch-4-6 — P2 — 1r — `AO3CollectionsList.swift:275` / `:307` / `AO3CollectionScreenDecisions.swift:14`

**Artboard:** swipe labels **Edit** and **Delete**. Scope pills **Collections** and **Your items**, the second carrying an orange count (**3**, `700 10.5px`, height 18). Card eyebrow **You moderate** (or the owner’s name). Status chips **3 to approve**, **Revealed**, **Anonymous**. Meta **124 works · 3 awaiting approval** and **812 works · 2 of your works**, plus the date. Toolbar is three 34px glass circles: back, funnel, plus.

**Code:** trailing swipe is **Edit** only (`allowsFullSwipe: false`). No Delete swipe; delete is owner-only inside the form. **Your items** is a plain pill — the comment at line 306 says nothing caches a pending count, so there is no badge. Eyebrow is **You own** when `viewerIsOwner`, never **You moderate**. `statusLabels` always emits **Revealed** or **Unrevealed**, plus **Anonymous** when set. `metaFacts` is works, bookmarks, **Moderated**, **Closed**, challenge name. The card comment (`AO3CollectionsList.swift:630`) says approval queues and “works of yours” are not on the blurb and are not drawn. Plus and funnel are system toolbar items (`Label` plus, `FilterButton`’s `line.3.horizontal.decrease`), not 34px glass circles. Context menu is **Edit Collection** and **Manage Items**.

**Smallest fix:** Owner-only **Delete** swipe that presents batch-4-1’s alert. Badge **Your items** from the account items page’s “need a decision” count once that page has been loaded (do not invent it before then). Say **You moderate** when the viewer maintains the collection. Leave awaiting-approval and “your works” off the card until a real field exists; don’t add a second request per row.

---

### batch-4-7 — P2 — 1bm — `AO3CollectionsFilterPanel.swift:72`

**Artboard:** row **Sort by** · **Recently updated**; row **Order** as a segment **Oldest** | **Newest**. Group **My role** with chips **Maintainer**, **Member**, **Invited**. **Show only:** **Open to new works**, **Has works of mine**, **Unrevealed**. Footer: **“AO3 sorts collections by title and date only. Recently updated and Works in collection are computed here, so they need the whole list fetched before the first sort.”** Toolbar: back, a circular-arrow reset, accent check.

**Code:** group label **Sort by**, row label **Order by**, direction row labelled **Direction** (Oldest/Newest only when the sort is recently updated — that part is right). Sorts also include **AO3 order**, **Title**, **Works**, **Bookmarks**. **My role** is absent; a footnote explains the index has no role (honest, and it replaces the artboard footer). **Show only** is **Open to new works**, **Has works** (any collection with `worksCount > 0`, not works of mine), **Moderated** (not on the board), **Unrevealed**. Reset is a bottom **Reset** bar; cancel is an X, not back-plus-undo.

**Smallest fix:** Rename **Direction** to **Order** and **Order by** to **Sort by**. Rename **Has works** only if it ever means the viewer’s works; until then keep the honest label and drop **Has works of mine** from the spec. Drop **Moderated** or add it to the artboard on purpose. Keep **My role** off, but put the artboard’s sort-cost sentence back as the footer (the role explanation can be the second sentence).

---

### batch-4-8 — P2 — 1s — `AO3CollectionItemCard.swift:542` / `AO3CollectionItemsView.swift:367`

**Artboard:** work title `600 19px`. Role is a chip **Member** (`600 9.5px`, uppercase, tracking `.05em`, fill `rgba(255,255,255,.1)`, radius 6, padding 2px 7px). Approval rows are a single coloured word: **Approved** `#30D158`, **Awaiting** `#FF9F0A`. **Remove from collection** is `600 11.5px` `#FF6961` on `rgba(255,69,58,.14)`, radius 8. Toolbar: **2 staged** (`500 12px`) and an accent check.

**Code:** title is 16.5 semibold. Role is plain 10pt semibold secondary text, not uppercased, no chip. Each approval row is a three-segment `SubjectSegmentedControl` (**Awaiting** / **Approved** / **Rejected**) in the default glass selection, not green/orange. Remove is plain 12pt semibold `.red` with no fill. Staged count and a checkmark exist and match the job; the check is a toolbar `Label`, not the 34px accent circle, and a **Discard** button appears beside it (not on the board). Empty tab is **Nothing in this tab.** with no action (`:349`). A failed load is red 12.5pt text with no **Try Again** (`:367`); pull to refresh is the only retry. Signed out is that same red card, **“Log in to AO3 to manage collection items.”**, with no login button — 1r’s signed-out state is a `ContentUnavailableView` with **Log In to AO3…**.

**Smallest fix:** One status menu (or a chip that opens one) coloured Approved/Awaiting/Rejected, title at 19 semibold, role as the uppercase chip. Give Remove the tinted chip. Give the error and signed-out cards the same **Try Again** / **Log In** actions 1r uses. `brief-C2` already says the segment vs chip is an owner choice; the 19pt title, the role chip, and the missing retry are not.

---

### batch-4-9 — P2 — 1ci — `AO3CollectionDetailView.swift:179` / `:117` / `AO3WorkRow.swift:208`

**Artboard:** stat strip **168 / Works**, **24 / Bookmarks**, **41 / Members** (`700 19px` figures, `400 10.5px` labels, sentence case). Segment **Works** | **Bookmarks** | **People**. Section **Recent** with the count in accent. A work row is a fandom kicker (`700 9px`), title `600 16.5px`, author `400 13px`, meta **“12/13 chapters · 84k · 2,104 kudos”** (`400 11.5px`). Badges **Anon** and **Gift** (`600 10px`, white, pill `rgba(255,255,255,.12)`), inline with the author. Caption: anonymous and unrevealed are collection state, so the badge sits on the card. Toolbar: back, magnifier, three-line menu.

**Code:** `SubjectStatStrip` draws 13pt semibold figures and 9pt uppercase labels (`SubjectSurface.swift:786`). Cells are Works and Bookmarks only — the comment at `:177` refuses a Members figure that isn’t an exact total. Rows are `EnrichingAO3WorkRow` `.searchLedger`: `.title3` title, `.subheadline` author, a 3-line summary, a 22pt status-icon tray, and caption metadata of language + `count.formatted()` words (**84,000 words**, not **84k**) + chapters + comments + kudos + bookmarks + hits (`AO3WorkRow.swift:335`). Anonymous is an overlay badge **ANON** in 10pt bold monospaced (`AO3CollectionDetailView.swift:257`), not **Anon** beside the byline. The row comment at `AO3WorkRow.swift:224` says Gift is drawn on the spec and no gift flag is parsed; `brief-C2` later says recipients are in the blurb HTML (Q7) and were left for later. No Unrevealed badge. `expandAll` is passed and never toggled. The `…` menu exists only while Hide Mature is on, and its only item is `MatureRevealToggle` — no Select, no display mode, no Expand/Collapse, no search.

**Smallest fix:** A collection-specific row (or a ledger mode flag) with the four lines the board draws and compact word counts (`84k`). Badge copy **Anon**, inline. Parse the gift link Q7 already confirmed and show **Gift**. Add Members only when a real total exists. Always show the `…` menu: Mature (when relevant) · Select · display mode · Expand/Collapse. Search can stay off until a collection search URL is real; the menu should not.

---

### batch-4-10 — P2 — 1cd — `CollectionModerationView.swift:277` / `:538` / `:207`

**Artboard:** one grouped card per section (radius 14, hairline between rows). Approve is a filled accent pill (`#E39B9B` / `#2b1417`, `600 12.5px`, height 34); Reject and Message creator are neutral text pills. Work line is title `600 16px`, **“kestrelmoon · 24,180 words · submitted 3 Nov”**, then the tag line **“Good Omens (TV) · Aziraphale/Crowley · slow burn, domestic”**. Membership secondary line **“Requested 2 Nov · 14 works on AO3”**; Accept is the accent pill, Decline the neutral pill. Reveal rows are **Works revealed** · **1 Dec 2026**, **Creators revealed** · **8 Dec 2026**, **Anonymous until reveal**, and **Reveal now** in the default 15pt white, not red. 1bx’s decided list is **Approved · 24** and **Rejected · 2**.

**Code:** each submission is its own `subjectPanel` in a `VStack` spacing 9. Approve is green-tinted and Reject is red-tinted (`:305`, `:335`) — 1bx’s queue colours, not 1cd’s accent/neutral pair — at 13pt semibold, height 34, with no `minimumHitTarget` (the glass message button has one; these pills do not). Kicker is `item.itemType`, not a fandom. Byline is creator and date only (`CollectionModerationCopy.byline`); the comment at `:275` says word count and tags are not on `AO3CollectionItem` and are not invented. Membership secondary line is **“Wants to join \(title)”** (`:413`). Reveal rows are **Works** / **Creators** with **Unrevealed until reveal** / **Revealed** and **Anonymous until reveal** / **Credited** — state, not dates (`:538`; `revealScheduleText` is flags, not a schedule). **Reveal now** and **Remove anonymity** are red. **Recently decided** is one row, value **Approved and rejected**, pushing `AO3CollectionItemsView` on the Approved tab (`:207`) — the creator’s staging screen (1s), not a decided list, and Rejected is only reachable by switching tabs there.

The Q6 footnote (**no reason, no email**) correctly replaces the artboard’s “Reject sends a reason by email”. Keep it.

**Smallest fix:** One panel per section, hairlines between rows. 1cd’s accent Approve and neutral Reject/Message (once batch-4-2 renames Message). Show words and tags when the item HTML already has them; don’t fetch a work page per row. Point **Recently decided** at two counts or two tabs, not at the staging editor. Keep reveal dates off until a challenge actually supplies them; don’t paint **Reveal now** red if the board’s one-way actions are the green pair on 1bl.

---

### batch-4-11 — P2 — 1bx — `CollectionMaintainersView.swift:183` / `:342`

**Artboard:** owner subtitles **You · created the collection** and **Added 12 Jun 2025**. Moderator subtitle **Can approve works, cannot delete the collection**. Footnote: **“An owner can remove a moderator, but the last owner cannot remove themselves.”** Role badges match the code (uppercase 10.5, tracking `.04em`, padding 5×10, radius 99). Invite rows **Invite by username** / **Add a username** and **Invite as** · **Moderator**. Leave row **Step down as owner**, `#FF453A`.

**Code:** badges, invite placeholders, the footnote text, the last-owner alert (`:92`), and **Step down as owner** / **Leave collection** match. Every other owner’s subtitle is the word **Owner**, which repeats the badge. **You · created the collection** is shown for whichever owner is the logged-in pseud (`:186`), with no created-the-collection fact behind it. There is no date. No row, swipe, or menu removes another maintainer. `leaveCollection` deletes by participant id (`AO3CollectionActions.swift:354`) and is only called for `currentParticipant` (`:481`). The accent check that would send the invite is an inline **Send invitation to …** row instead (`:315`), which is clearer than a nameless check; the missing remove is not.

**Smallest fix:** Subtitle **You** for the current owner, and nothing (or the role only) for the others, until an added-date exists. Swipe **Remove** on a moderator, confirmed, calling `leaveCollection` with that participant’s id. Keep the last-owner block.

---

### batch-4-12 — P2 — 1ch — `TagSetView.swift:119` / `:201` / `:324`

**Artboard:** kicker **Tag set · owner**. **Ownership:** **Title**, **Owners** · **saltandsilver**, **Moderators** · **meridian**, **Visible to everyone**. **Nominations:** **Nominations open** plus four “per person” rows with values and up/down chevrons. **At AO3:** **Associate nominations** · **Opens AO3**, **Delete tag set** · **Opens AO3** (label is 15pt white, not red).

**Code:** both push sites pass `isModerator: true` (`ChallengeSettingsView.swift:391`, `ChallengeSettingsEditView.swift:493`), and the header comment says that flag means the kicker **Tag set · moderator** even though those screens are the owner’s. Ownership is Title plus a disabled **Visible to everyone** toggle. No Owners or Moderators rows (the file header says `AO3TagSet` has no pseuds). **Nominations open** is a disabled toggle; the four limits are static monospaced 11pt values (`isMonospaced: true` → `SubjectFormValue` at 11pt, artboard values are 15px) with no stepper. **Delete tag set** is `isDestructive: true`, so the label is red. The four “tags to add” editors, the **Save tags** button, the fandom-grouped queue, and **Associate nominations · Opens AO3** match the build note and the caption. Counts and the association footnote match.

**Smallest fix:** Kicker **Tag set · owner** when the push is from the owner-only challenge screens. Draw Owners/Moderators when the model gains pseuds; until then don’t imply the toggle is editable — show **Visible to everyone** · **On/Off** and the limits as plain values, with one footnote that those settings are changed on AO3. Leave Delete’s value as **Opens AO3** and don’t paint the label red (it doesn’t delete here).

---

### batch-4-13 — P3 — 1r / 1s / 1ci / 1cd / 1bx / 1ch / 1bl — loading

**PLAN E:** a loading skeleton shaped like the content.

**Code:** first load is a centered `ProgressView` (`AO3CollectionsList.swift:185`, `AO3CollectionItemsView.swift:359`, `AO3CollectionDetailView.swift:405`, `AO3CollectionFormView.swift:67`) or a spinner plus “Loading …” (`CollectionModerationView.swift:641`, `CollectionMaintainersView.swift:392`, `TagSetView.swift:554`). Account inbox already has a skeleton (`AccountInboxViews.swift`). Empty and failed states exist on these screens (except 1s’s missing retry, batch-4-8).

**Smallest fix:** Reuse the account-list skeleton for the first load of 1r, 1s, and 1ci. A spinner is acceptable on a short form; a blank moderation page is not.

---

### batch-4-14 — P3 — every subject page in this batch — `SubjectSurface.swift:468` / `:340`

**Artboards:** the tally under the 32pt title is `400 12.5px`. Grouped cards are `border-radius: 14px`.

**Code:** `SubjectHeaderBlock.subtitleSize` is 15.5. `SubjectMetrics.rowRadius` is 16, and every `subjectPanel` / `subjectCard` in this batch uses it. Kickers (10pt bold, tracking 0.11), titles (32pt bold, about −0.02em), and form-group labels (11pt semibold, tracking 0.07) match the boards. This is one component, so it is the same “error” on 1r, 1s, 1bl, 1ci, 1cd, 1bx, 1ch.

**Smallest fix:** If 12.5 and 14 are still the spec, change those two metrics once. Don’t restyle each screen.

---

### batch-4-15 — P3 — 1bm — `AO3CollectionsFilterPanel.swift:162` / 1s section header

**Artboard 1bm** puts reset in the toolbar (circular arrow). **Code** uses a full-width bottom **Reset** plus an X. That X/check pair is what `brief-C2` asked for, so this is chrome drift against the board, not a broken filter.

**Artboard 1s** has no section title between the pills and the cards. **Code** inserts `SectionRuleHeader` of the tab name and the page count (`AO3CollectionItemsView.swift:335`), so the tab is named twice.

**Smallest fix:** Leave the X/check filter chrome (it’s the app’s sheet grammar) and drop the duplicate 1s section header, or keep the header and drop the pill’s job as the only title — not both.

---

## Checked, matches

### 1bk — local collection

- Create sheet groups **Collection** / **Behaviour**, row labels, placeholders **Comfort reads** and **Optional**, both toggles, and both footnotes, including **“Local collections live on this device only…”** (`NewCollectionSheet.swift:17`, `:55`).
- **Create** stays disabled until the name is non-empty (`:71`). Text **Cancel** / **Create** matches the 1j decision (the board’s X and dimmed check were deliberately not built).
- Colour is chosen here (`SubjectHueSwatchRow`), not only derived. Show on Home really inserts a shelf above Recently Updated (`HomeView.swift:9`). Keep downloads enqueues missing EPUBs (`Collections.swift:231`). The file header that says neither behaviour is built is stale; the UI is not.
- Delete soft-deletes into Recently Deleted. The alert’s **90 days** matches the product invariant; the board’s **30 days** does not. Empty collection offers **Add Works**. Trailing swipe **Remove** uses `destructiveConfirmation` and does not delete the work (`:493`). Select mode has a bulk bar **Remove from Collection**. Pull to refresh is wired (`:322`).
- Not visually checked: sheet safe area, keyboard, Dynamic Type clipping. Row labels are the shared fixed 15pt `SubjectFormRow`.

### 1r — AO3 collections

- Header kicker **AO3 Account**, title **Collections**, `SubjectHeaderBlock`.
- Scope pills **Collections** / **Your items**; the second opens 1s (`:312`).
- Card title 19 semibold, archive-box tile 38×38 radius 10, hue from the title, date on the meta row (`AO3CollectionCard`).
- Footer **“AO3 collections. Local collections live in Library.”** is the C2 decision. The board’s “read-only” and “live in Home” are both wrong: local collections are `AllCollectionsDestination` in Library, and this screen edits.
- Signed-out prompt with **Log In to AO3…**. Failed load has **Try Again**. Filter-empty has **Clear Filters**. Pull to refresh and pagination (`SearchPaginationBar`) are wired. `hidesFloatingTabBar()` is set.
- Counts are exact integers, not `1.2K`. The board itself prints **4,102**, so exact is right; they are not thousands-grouped (`\(worksCount)`).

### 1s — collection items

- Kicker **AO3 Account › Collections**, title **Collection items**, subtitle pattern **Your works in AO3 collections · 3 need a decision** (`decisionPhrase`).
- Pills **Awaiting collection**, **Awaiting you**, **Rejected**, **Approved**, **Reset**, in that order (`:311`). Account-wide default tab is Awaiting you; a single collection defaults to Awaiting collection (`:56`).
- Rows **Approved by creator**, **Approved by moderators**, **Unrevealed**, **Anonymous**. Disabled AO3 controls render as text, not a live control (`:594`).
- Staging: toolbar count, check submits, removed row says **“Staged for removal from this collection. The work stays on AO3.”**
- Each card’s hue is the collection title (C2-12). Pull to refresh is wired.
- Pill hit targets use `minimumHitTarget(28)`, the app’s floor for a tight rail (`MinimumHitTarget.swift:28`), not 44.

### 1bl — AO3 collection form

- Section order Header, Images, Preferences, Challenge, Profile. The four switches are independent. Name footnote matches, including the locked-on-edit sentence (`:366`). Collection name is disabled when `nameIsLocked`, and availability is checked before create (`:523`).
- Failed open has **Try Again**. Save errors stay inline so a reload can’t wipe the draft (`:513`).
- Icon upload left out by decision. Delete is owner-gated (`allowsDelete`).

### 1bm — sort and filter

- Draft/cancel/apply: X discards, check commits, check disables when nothing changed (`:54`). Reset restores the draft only.
- Oldest/Newest, A–Z, Fewest/Most follow the sort (`AO3CollectionsFilter.swift:47`). Client-side sorts wait for the whole index. Unparsed dates keep AO3’s order.
- **My role** omitted on purpose, with a reason on screen (`:149`).

### 1ci — reader collection

- Kicker **Collection**, title from the collection, subtitle byline · summary (`:167`), which is the board’s “saltandsilver, meridian · Coastal fic, all fandoms” shape.
- Segments Works / Bookmarks / People, loaded independently. People rows exist (`AO3CollectionPersonRow`). Empty copy is specific (“no works yet”, “no bookmarks yet”, “Nobody has joined…”). Failure card has **Try Again**. Pull to refresh reloads the segment. Pagination is the shared bar.
- Anonymous detection is the whole byline equal to “Anonymous”, so a creator named “anonymously_yours” is not badged (`:275`).
- Manage rows are gated on maintainer/owner and only appear when AO3 offered the URL. No Tag Set row on this page, by the comment at `:316` (the id is fetched from the challenge screens instead).

### 1cd — moderation

- Kicker is the collection name, title **Moderation**, subtitle **N works awaiting review · N membership requests**, with a page clause when paged (`CollectionModerationCopy.reviewTally`).
- Section order: Awaiting review, Recently decided, Membership requests, Maintainers (headcount + **Invite a maintainer**), Reveal and anonymity. Empty cards exist. Failure card has **Retry**. Pull to refresh is wired.
- Approve/Reject/Accept/Decline are separate writes. Reject does not drop the row before the request returns (`removeDecided` runs after success — verified by the call structure at `:752` following the write). Reveal and un-anon each have their own confirm and say they can’t be undone from the app.
- Q6 copy is intentional and correct: alert **Reject this work?** states that AO3 sends no reason and no email, and the work stays on AO3 (`:106`). That replaces 1ce’s sheet. See 1ce below.

### 1ce — reject

- There is no reason field, no 231/1000 counter, and no “AO3 emails your reason”. That matches `REDESIGN_DECISIONS` (**1ce** reject copy: confirmation alert, no reason field, no email claim) and contradicts the artboard on purpose. Not filed as a bug. The artboard’s **Reject this submission** / **Reject and send** / required reason should be treated as withdrawn.

### 1cg — collection settings

- Not implemented as drawn. The pieces that were explicitly requested without the regroup — Tagline, and an email toggle — are on the 1bl form. See batch-4-5.

### 1ch — tag set

- Title **Tag set**. Sections Ownership, Tags, Nominations, Review, At AO3, in that order. Tag counts Fandoms / Characters / Relationships / Additional tags. Nomination limit labels match. Review counts Awaiting review / Approved / Rejected. Footnote about associating with a fandom matches the caption (`:266`). Queue is grouped by fandom, with **No fandom listed** last.
- **Associate nominations · Opens AO3** and **Delete tag set · Opens AO3** use `router.open`, not an in-app delete. **Save tags** writes the four comma-separated fields together. Reject on an unreviewed nomination is a real write; approved/rejected rows are badges, not buttons. Empty queue and **Retry** exist. Pull to refresh is wired.
- The “to add” editors are AO3’s `fandom_tagnames_to_add` fields, so the label is the field, not a mistaken “append”.

### 1bx — maintainers

- Kicker **AO3 Account**, title **Maintainers**, subtitle **Name · N people** (`:121`). Sections Owners, Moderators, Invitations, Leave. Invite placeholders **Add a username** and **Invite as** default **Moderator**, with Owner as the other choice. Footnote text matches the board, including the last-owner sentence. Last-owner tap shows **Cannot Step Down** instead of posting (`:466`). Role badge metrics match. Avatar is 32px with a one-letter initial (the board’s circle is empty). The separate **Moderated items** artboard was deleted on purpose; its queue lives on 1cd (`REDESIGN_DECISIONS`). Pull to refresh and **Retry** exist.

### Checklist items verified as shared, not re-broken on each screen

- Form row label 15pt, value 15pt, padding 14×11/12, hairline separators (`SubjectFormRow`). Group label spacing on the hand-built screens is 18 then 8, which matches these boards’ `padding: 20px 4px 8px` more closely than PLAN’s “10 rule→content”.
- Destructive confirms that go through `destructiveConfirmation` or a role-destructive alert: local remove-from-collection, local delete, AO3 delete, reject, decline, reveal, un-anon, step down.
- No screen in this batch shows a permanent drag handle on the work list itself. The reorder sheet does (batch-4-3).
- Compact `1.2K` is not used on these cards. Pagination and prose totals stay exact, which is what PLAN D asks for those. The 1ci ledger’s full **84,000 words** is the mismatch (batch-4-9), not the pagination.
- macOS gets an inline navigation title on moderation, maintainers, and tag set (`#if os(macOS)`). iOS uses the in-scroll header. Not run on either platform.
- Keyboard avoidance, floating tab-bar overlap, and Reduce Motion were not exercised. Shimmer isn’t on these spinners, so Reduce Motion has nothing to disable there.

---

## Three that matter most

1. **batch-4-1** — Deleting an AO3 collection can reveal works and name anonymous creators, and the alert doesn’t say so. That is the one control on these screens that can undo someone else’s privacy.
2. **batch-4-2** — **Message creator** doesn’t message. A maintainer will think they asked for a fix and will have opened Safari instead.
3. **batch-4-3** — Local collection edit still isn’t the sheet the board calls “the same sheet”, and the work list’s `…` menu breaks the order and the no-drag-hint rule the rest of the app is being held to. This is the screen the owner actually lives in.
