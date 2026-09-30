# Batch 7 — Account hub polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html` (inline styles, px = pt). Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic — nothing here was seen on a device. Where `docs/REDESIGN_DECISIONS.md`, `docs/REDESIGN_PLAN.md`, or an in-code owner comment already supersedes an artboard, that is under the screen’s checked list, not filed as a defect to revert.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1m | Signed-in hub | `AccountView.swift`, `AccountComponents.swift` (`AccountProfileCard`), `AccountShortcuts.swift` |
| 1n | Signed out | Same; `signedOutCard`, `signedOutPreviewSection` |
| 1o | Marked for Later | `AO3MarkedForLaterWorksBrowser.swift`, host `AO3AccountWorksList.swift` |
| 1q | Bookmarks | `AO3BookmarksWorksBrowser.swift` (`AO3BookmarkFootnote`) |
| 1t | History | `AO3HistoryWorksBrowser.swift`, `AO3Client+Readings.swift` |
| 1p | Subscriptions | `AO3SubscriptionsWorksBrowser.swift`, `AO3Client+NamedSubscriptions.swift` |
| 1l | Inbox | `AccountInboxScreen.swift`, `AccountInboxViews.swift`, `AO3InboxModels.swift` |
| 1y | Dashboard | `AO3DashboardView.swift` → `AuthorProfileView.swift` (`showsDashboard`), `AuthorDashboardSections.swift` |
| 1z / 1bb | AO3 Preferences + toast | `AO3PreferencesView.swift`, `AO3PreferencesActions.swift` |
| 1ab | Settings hub | `SettingsHubView.swift`, `SettingsRoute.swift`, `SettingsHeaderBlock.swift`, `SettingsAccountPages.swift` |
| 1ac | Privacy | `PrivacyDataView.swift` |
| 1aa | More on AO3 | `AccountMoreOnAO3View.swift`, `AccountExternalNavCard.swift` |

Shared chrome: `SubjectHeaderBlock` (title 32pt bold, subtitle 15.5pt, `SubjectSurface.swift:467`), `SectionRuleHeader`, `SubjectStatStrip`, `subjectScreenWash`. Account lists pass `gutter: SubjectMetrics.accountGutter` (16).

---

## Findings

### batch-7-1 — P1 — 1l — `AccountInboxScreen.swift:36` / `AccountInboxViews.swift:60` / `:633`

**Artboard:** one hero. Title **Inbox** `700 32px`. Subtitle **118 comments · 12 unread · 4 awaiting a reply** `400 15.5px`.

**Code:** `AccountInboxScreen` draws `SubjectHeaderBlock(title: "Inbox", subtitle: tally)` from `AO3InboxTally.headerLine`, which says **comments** (`AO3InboxModels.swift:280`). When the feed is showing, the list then inserts `AccountInboxFeedHeader`, whose own comment calls it “The second Inbox title.” That second block is another 32pt **Inbox**, and its subtitle is `headerTallyLine`, which says **messages** (`AccountInboxViews.swift:612`: `"\(shown) messages"`). One screen, two page titles, two nouns for the same tally.

**Smallest fix:** Delete the `AccountInboxFeedHeader` call at `AccountInboxScreen.swift:60`. Keep the one hero and `AO3InboxTally.headerLine`. The page clause already lives on that line.

---

### batch-7-2 — P2 — 1q — `AO3BookmarksWorksBrowser.swift:195` / `:236` / `:350`

**Artboard:** subtitle **38 bookmarks · 6 private · 11 recs** `400 12.5px`. Each bookmark is the search-result card: fandom eyebrow, disclosure, rule, title `600 19px`, author `400 13.5`, a 2×2 signal grid, and a stats row with the bookmark date pushed right. The note sits where a summary would, **on an accent rail**. AO3 tags are pills, distinct from local User Tags. A private bookmark puts a **lock chip in place of the note**.

**Code:** the subtitle is `"\(count) works"` plus `" · page X of Y"` when there is more than one page. `bookmarkDetails` already has `isPrivate`, `isRecommendation`, `notes`, `tags`, and `date`, and none of those counts are in the line. The default `@AppStorage("account.displayMode")` is `.compact` (`AO3AccountWorksList.swift:162`). Compact still calls `rowStack(entry, ledger: true)` inside `subjectCard` (`:236`), so the row is a ledger, not the 19px search card. `AO3BookmarkFootnote` sits **under** that card: badges **Rec** / **Private** (`lock.fill`) / the date, then captions **Bookmark Tags** and **Bookmark Notes**. The note is not an accent rail in the summary slot. Private does not replace the note. The date is a calendar badge, not the trailing end of the stats line.

**Smallest fix:** Count private and recs from `bookmarkDetails` for the subtitle (`N bookmarks · N private · N recs`, page clause kept). Draw the note as an accent-rail in the summary slot, and the lock chip in that slot when the bookmark is private. Put the date on the meta line. Drop the **Bookmark Notes** / **Bookmark Tags** captions. Keep the mature-blur that hides the footnote with the row (`AO3BookmarksMatureBlur`, `:275`).

---

### batch-7-3 — P2 — 1p — `AO3SubscriptionsWorksBrowser.swift:16` / `:29` / `:185` / `:238`

**Artboard:** one pill rail, **Works** / **Series** / **Authors** / **Reset**. New-since-visit is the same 164×232 cover as 1o, with a **NEW** badge and a chapter range instead of the ring. Everything followed is a ledger row. Section titles **New since you last looked** and **All works**. **Unsubscribing is a swipe; the card has no button.**

**Code:** two rails. `AO3SubscriptionsScopeRail` is Works / Series / Authors, and `AO3SubscriptionsFilterRail` adds All / Updated / Reset (`:238`). Group titles are **Updated since you looked** and **Everything else** (`:29`). Every row is a ledger. The chapter line is a footnote, **Chapter N new** / **Chapters N-M new** (`AO3SubscriptionsChapterRange`, `:103`). The cover, the **N NEW** badge, and the reading ring are not on this screen. The comment at `:185` says the grid cannot host the chapter line or the swipe. The swipe itself is there (`:363`, `allowsFullSwipe: false`) and then confirms (**Unsubscribe?**, `AO3AccountWorksList.swift:419`). The card has no button. That confirm matches checklist B; it is not the defect.

**Smallest fix:** One rail: Works / Series / Authors / Reset. Section titles **New since you last looked** / **All works**. Draw the updated run as covers (164×232, the existing `newChapterBadge` at `AO3AccountWorksList.swift:742`, chapter range on the cover the way 1o draws **Ch. 30–31**). Keep the unsubscribe swipe on the ledger rows. The artboard’s card has no button, so the cover does not need a control.

---

### batch-7-4 — P2 — 1o — `AO3MarkedForLaterWorksBrowser.swift:333` / `:351` / `:382` / `docs/REDESIGN_DECISIONS.md:91`

**Artboard:** the updated run is a 164×232 cover with **2 NEW** (`600 11px`, fandom colour) and **Ch. 30–31** (`500 10px` mono). The rest are ledger rows. The frame contains no Unmark control. The footer says unmarking here unmarks there.

**Decision 1o.4:** Unmark is a swipe, confirmation-free, like AO3’s button.

**Code:** the write is confirmation-free. `startUnmark` (`AO3AccountWorksList.swift:1195`) posts and removes the row only on AO3’s confirmed success; the only alert is **Couldn't unmark** after a failure (`:445`). The control is not a swipe. `unmarkButton` is a `SubjectChip` **Unmark** (`clock.badge.xmark`) under every cover and on every ledger row (`:351`, `:382`). The comment says the screen is a `ScrollView`, so a swipe will not attach. `AccountWorksCompactGrid` (`AccountComponents.swift:452`) draws `SensitiveWorkCoverCard` / `EnrichingAO3WorkCoverCard` and the Unmark accessory. It does not draw **N NEW** or the chapter range. `newChapterBadge` exists (`AO3AccountWorksList.swift:742`) and is overlaid only on the generic list branch this kind does not use (`:554` routes Marked for Later into the browser first). Cover size matches: `CarouselCardMetrics.width` is 164 and height is `164 * √2` (`CarouselCardStyle.swift:33`).

**Smallest fix:** Drop the chip. Put Unmark on a trailing swipe (a `List` for the ledger run; the cover grid can keep unmark in the long-press menu it already opens). Overlay `newChapterBadge` and the chapter range on the updated covers. Leave the write confirmation-free.

---

### batch-7-5 — P2 — 1t — `AO3HistoryWorksBrowser.swift:31` / `:241` / `AO3AccountWorksList.swift:162`

**Artboard:** hairline rows. Each row pairs the progress ring against the visit count. The version line is coloured: **Update available** `#FF9F0A`, **Minor edits since then** `#8E8E93`, **Latest version** `#30D158`. Chips **Marked for later** and **Flagged to skip**. Meta is **Visited 7 times · Ch. 14 of 24** and **Last visited 2d ago** on their own, not one grey sentence. Time buckets are the section kickers. Clearing is in the overflow.

**Code:** `@AppStorage("account.displayMode")` defaults to `.compact`, and this browser honours it (`:31`). Compact draws `AccountWorksCompactGrid` covers (`:50`), not hairline rows. The display-mode picker is in the `...` menu for history only (`AO3AccountWorksList.swift:310`). Detailed mode is a ledger card. `AO3HistoryReadingFootnote` joins `visitCountDisplay`, local progress, `versionDisplay`, and `lastVisitedDisplay` into one `11.5pt` `.secondary` line (`:246`). The later / skip chips are 11pt secondary labels (`:268`). Nothing colours the version line. Nothing draws a ring opposite the visit count. The strings themselves match: **Visited once** / **Visited twice** / **Visited N times**, **Update available** / **Minor edits since then** / **Latest version**, **Last visited … ago**, **Finished** / **Ch. N of M** (`AO3Client+Readings.swift:46`).

**Smallest fix:** Default this screen to the hairline / ledger row regardless of `account.displayMode`. Draw the local progress ring opposite `visitCountDisplay`. Colour the version line (orange / gray / green) and draw the later / skip chips in that same treatment, not as grey captions. Leave the swipe and the Clear History confirm (see checked).

---

### batch-7-6 — P2 — 1m — `AccountComponents.swift:50` / `:72` / `:96` / `:163`

**Artboard:** kicker **AO3 Account** `700 10px` tracking `.13em`. Name **AddictedFicLover** `700 27px` tracking `-.02em`, stated as the title. Under it, **Session verified 4 min ago** `500 11.5px` `.55`, and a pill **Posting as Account Default** `500 13px`.

**Code:** the comment at `:50` says the block is “then the pseud pill under it.” There is no pill. `SubjectKicker` becomes `"Posting as \($0)"` whenever a pseud is set, and **AO3 Account** only when it is not (`:72`). The 27pt username is the label of `postingAsMenu` (`:96`), with a chevron, not a static title. The session line is `.caption` (about 12pt regular), not 11.5 medium (`:163`). Healthy copy is **Session verified \(relative numeric)** (`:190`), which is the right sentence. The account ellipsis beside it is a `.bordered` `.small` capsule (`:258`), not a glass circle, and its last item is **Log Out** with no confirm (`:253`).

**Smallest fix:** Kicker stays **AO3 Account**. Username stays 27pt bold and is not the menu. Add the posting pill (**Posting as Account Default**, or **Posting as {pseud}**) as its own control. Session line at 11.5 medium. Keep Verify Session / Open on AO3 / Log Out in one menu; see batch-7-11 for the missing confirm.

---

### batch-7-7 — P2 — 1l — `AccountInboxViews.swift:233` / `:241` / `:375` / `:452` / `AO3InboxModels.swift:28`

**Artboard:** the action strip is accent **Reply** (`500 12.5px` `#E39B9B`, with an arrow), then **Mark read** / **Mark unread** (`500 12.5px` `.55`). **Replied** (`600 10px` `#30D158`) sits inline beside the timestamp. The reader’s own reply is quoted on an accent rule: **You:** plus the body `400 12.5px`.

**Code:** Reply is `CommentReplyButton`, a quaternary capsule, caption semibold, SF Symbol `arrowshape.turn.up.left` (`CommentThreadRow.swift:328`). **Mark Read** / **Mark Unread** are in the overflow (`:452`) and on a trailing swipe that refuses full swipe (`:701`). They are not labels in the strip. `InboxRepliedBadge` is in that same action row (`:241`), while the timestamp stays in the byline (`:375`). There is no quoted reply. `AO3InboxItem` has `excerpt` and `isReplied` and no field for the reader’s own reply text (`AO3InboxModels.swift:28`). Whether the inbox HTML contains that sentence was not checked; the row has nowhere to put it.

**Smallest fix:** Put **Mark read** / **Mark unread** in the strip next to Reply, as 12.5pt text, and move **Replied** onto the byline beside the timestamp. Keep the swipe. Do not invent the **You:** quote until the model has a place for the body.

---

### batch-7-8 — P2 — 1y — `AuthorDashboardSections.swift:27` / `AO3AuthorModels.swift:286`

**Artboard:** **Fandoms** is rows. Name `500 13px`, count `600 11px` mono (5, 3, 2, 1, 1), then **Expand**.

**Code:** a `FlowLayout` of `SubjectChip`s of `fandom.name`, first five, then a dashed Expand / Collapse. The comment says “Fandom totals are not in the account counts cache.” They do not need to be. `AO3AuthorFandom.workCount` is `Int?` (`AO3AuthorModels.swift:286`) and the chip never reads it.

**Smallest fix:** A row (or a chip suffix) that prints `workCount` when it is non-nil. Leave the chip as the bare name when the count is nil. Do not invent one.

---

### batch-7-9 — P2 — 1z — `AO3PreferencesView.swift:131`

**Artboard:** toggles stay in AO3’s groups. **Site skin** stays in Display. **Time zone**, **Language**, and **Page title format** stay in the locale group, with their values (**Europe/Lisbon**, **English**, **TITLE - AUTHOR - FANDOM**).

**Code:** every `<select>` and text field is pulled out of its fieldset into one synthetic group labelled **Display options**, after the toggle sections (`:131`). The toggle groups themselves keep AO3’s headings and a collapse chevron (`sectionHeader`, `:190`).

**Smallest fix:** Leave each select and text field in the fieldset it was parsed from. Do not rename that group to “Locale and format” unless that is AO3’s own heading. The defect is lifting them out.

---

### batch-7-10 — P2 — 1z — `AO3PreferencesView.swift:54`

**Checklist E:** a loading state is a skeleton shaped like the content. An error has a retry.

**Artboard:** the form is the content. 1bb forbids a row-level spinner and a banner that pushes the form.

**Code:** loading is `ProgressView("Loading preferences…")` centred in the frame (`:54`). Failure is `ContentUnavailableView` **Couldn't load preferences** with **Try Again** (`:57`). The Save toolbar swaps in a `ProgressView` while `isSaving` (`:84`). That is the bar button, not a row, and the toast does not push the list (see checked).

**Smallest fix:** Replace the centred spinner with a skeleton of the header plus a few `SubjectFormRow` groups. Keep Try Again. Leave the toolbar Save spinner.

---

### batch-7-11 — P2 — 1ac / 1ab / 1m — `PrivacyDataView.swift:367` / `SettingsAccountPages.swift:145` / `AccountComponents.swift:253`

**Checklist B:** a destructive action uses the shared `destructiveConfirmation`.

**Code:** every clear row on Privacy asks first (`confirmClearDownloads` and the three siblings, `:304`). **Remove AO3 session** calls `auth.logout()` on the tap (`:371`). Settings → AO3 Account’s **Log Out** does the same (`SettingsAccountPages.swift:145`). The hub’s account menu **Log Out** does the same (`AccountComponents.swift:253`). None of the three presents a dialog.

**Smallest fix:** One `destructiveConfirmation` before `auth.logout()` at all three call sites. Title it for what it does (the session leaves this device). Do not add a second copy of the logout.

---

### batch-7-12 — P2 — 1aa — `AccountExternalNavCard.swift:81` / `AccountComponents.swift:367` / `AccountMoreOnAO3View.swift:83`

**Artboard:** subtitle **Opens ao3.org in your browser**. The caption says the external glyph means the row leaves the app.

**Code:** the subtitle is **Opens on AO3 in Browse** (`:83`). `open()` builds an archiveofourown.org URL and hands it to `router.open` (`AccountExternalNavCard.swift:106`), which is the in-app Browse web view. Every row still passes `opensExternally: true`, so `AccountNavCardLabel` draws `arrow.up.forward.square` (`AccountComponents.swift:367`). The accessibility hint on that same label is **Opens on AO3 in Browse** (`:442`). The glyph says you leave; the hint and the navigation say you do not.

**Smallest fix:** Pass `opensExternally: false` (the chevron) for these rows. Keep the subtitle **Opens on AO3 in Browse**. Do not point them at Safari to match the artboard’s “ao3.org” line.

---

### batch-7-13 — P3 — 1o 1q 1t 1p 1y 1z 1ab 1ac 1aa — `SubjectSurface.swift:468`

**Artboard:** those subtitles are `400 12.5px/1.4` at `.55`. 1l’s subtitle is the exception, `400 15.5px`, and it matches this component.

**Code:** `SubjectHeaderBlock` sizes every subtitle at 15.5, scaled with `.subheadline` (`:468`), and colours it `.secondary` (`:494`). Account screens pass the string and do not pass a size. 1o, 1q, 1t, 1p, 1y, 1z, 1ab, 1ac, and 1aa therefore render a 15.5pt line where the frame is 12.5.

**Smallest fix:** A subtitle size on `SubjectHeaderBlock`, defaulting to 15.5, set to 12.5 by those nine screens. Leave Inbox on 15.5.

---

### batch-7-14 — P3 — 1o — `AO3MarkedForLaterWorksBrowser.swift:472`

**Artboard:** **Downloaded · 1.4 MB** is `500 10.5px` mono `#7FC9E0`.

**Code:** `AO3MarkedForLaterDownloadFootnote` is 11.5pt medium monospaced, `.secondary` (`:476`). The words match (`AO3MarkedForLaterDownloadLine`, `:207`).

**Smallest fix:** 10.5pt mono in the account accent (the same teal the frame uses for that one line). Do not retint the whole page.

---

### batch-7-15 — P3 — 1bb — `AO3PreferencesView.swift:503` / `AO3PreferencesActions.swift:55`

**Artboard:** a transient toast, text **Saved to AO3** `500 14px` white, sitting over the page and leaving on its own. Failure uses the same slot with a red wash and **Retry**. No row-level spinner, no banner that pushes content.

**Code:** the overlay does not push the list. Success dismisses after 3 seconds (`:519`). Failure stays, with **Retry** (`:508`). The string is AO3’s flash notice, or the hardcoded **Your preferences were successfully updated.** (`AO3PreferencesActions.swift:55`), or **Preferences updated.** on a redirect (`:60`). The capsule is `.regularMaterial` wrapping `bannerView`, which is itself a filled capsule (`:514` and `:549`). Failure swaps the check for a red triangle (`:541`). It does not change the wash.

**Smallest fix:** Success text **Saved to AO3** when the flash is the generic success (keep a specific AO3 error string on failure). One capsule. Failure fill goes red. Leave the 3-second dismiss and Retry.

---

### batch-7-16 — P3 — 1y — `SubjectSurface.swift:804` / `AuthorDashboardSections.swift:118` / `AuthorProfileView.swift:289`

**Artboard:** the four-cell strip’s labels are lowercase **kudos / comments / hits / bookmarks**, `600 8px` tracking `.09em` at `.5`. Values are `600 12px` `#fff` on the card wash (the caption’s “tinted to each card’s accent” is the wash, not the digits). **See all 12 works** is one `500 13px` accent link. Pseud switching and **New work** sit in the header.

**Code:** `AO3AuthorPerformanceStrip` passes labels **Kudos** / **Comments** / **Hits** / **Bookmarks** into `SubjectStatStrip`, which uppercases them and draws them at 9pt tracking 0.63 (`SubjectSurface.swift:804`). Values are 13pt semibold. Cells are not highlighted, so the digits stay `.primary`, which matches the white figures. `heading` sets `onSeeAll` on `SectionRuleHeader` (a trailing chevron, accessibility **See all …**) and `seeAll` draws a second button, **See all {count} {tab}** (`AuthorDashboardSections.swift:118` and `:123`). Both call the same destination. Recent series and recent bookmarks are `.ledger` / `.searchLedger` rows (`:84`, `:101`), not the board’s 15pt lines. `pseudSelector` and the **New work** chip are siblings under `SubjectHeaderBlock` (`AuthorProfileView.swift:289`), not inside it.

**Smallest fix:** On this strip only, lowercase 8pt labels and 12pt values. Keep the digits `.primary`. Drop either the header chevron or the text button, not both. Move the pseud control and **New work** into the header row. Leave series and bookmarks on the shared ledger row if a 15pt variant would be a second row style; the duplicate control is the part to remove either way.

---

### batch-7-17 — P3 — 1ac — `PrivacyDataView.swift:199`

**Artboard:** headline **No analytics, no tracking, no accounts but yours** `600 17px`.

**Code:** **No ads, no analytics, no tracking, no accounts but yours** at 15pt semibold (`:199`). The body under it is the rewritten sentence (see checked). The comment justifies that body. It does not add “No ads”.

**Smallest fix:** Drop **No ads, ** and set the headline to 17pt semibold. Leave the body as written.

---

### batch-7-18 — P3 — 1m — `AccountView.swift:1166` / `:1218`

**Artboard:** section labels (**Shortcuts**, and the scope names once the owner flattened the segments) carry no tally of how many rows are in the group. Counts sit on the rows.

**Code:** `scopeGroup` passes `destinations.count` into `SectionRuleHeader` (`:1218`). Reading prints **4**, Writing **3**, Activity **2**, in the same mono slot a work tally uses, next to rows that already show their own counts. Shortcuts does not do this (`onSeeAll` opens the editor; no count).

**Smallest fix:** Pass `count: nil` for Reading, Writing, and Activity. Keep the collapse chevron.

---

### batch-7-19 — P3 — 1o 1q 1t 1p / 1z — `AO3AccountWorksList.swift:21` / `:464` / `AO3PreferencesView.swift:76`

**Artboard:** the page name is the header: **Marked for Later**, **Bookmarks**, **History**, **Subscriptions**, **AO3 Preferences**. An empty list is still that page.

**Code:** macOS sets `.navigationTitle(kind.title)`. Bookmarks is **My AO3 Bookmarks**, History is **My AO3 History**, Subscriptions is **My Subscriptions** (`:24`). Marked for Later matches. Preferences is **My Preferences** (`AO3PreferencesView.swift:76`). iOS hides the bar and uses the header, so this is the macOS title only. Separately, a loaded empty list for every kind except subscriptions replaces the whole screen with `ContentUnavailableView` and no `actions` (`:464`). The header, the pills, and the footer go with it. Subscriptions keeps its screen so Series and Authors stay reachable (`:303`). Copy that is present: **Nothing marked for later** / **Tap “Mark for Later” on a work on AO3 to queue it up here.**, **No bookmarks yet**, **No reading history**. There is no in-app button those sentences can honestly point at.

**Smallest fix:** macOS titles match the headers (**Bookmarks**, **History**, **Subscriptions**, **AO3 Preferences**). Render the empty state inside the headed browser, the way subscriptions already does, so the title and the footer stay. Do not add a button that does not go anywhere.

---

### batch-7-20 — P3 — 1l — `AccountInboxScreen.swift:193`

**Artboard:** a 34px glass row: back, funnel, select, overflow.

**Code:** the bar is the system bar, on purpose (`:12`: Select All is `.confirmationAction` and the bulk bar is `.bottomBar`). The funnel (**Inbox Filters**, `line.3.horizontal.decrease`) and **Select Inbox Items** (`checklist`) are there (`:214`). There is no overflow item in that chrome. Per-row overflow still exists (`AccountInboxViews.swift:436`). Back is the system back button. The 34-vs-44 glass swap is staged everywhere else (see checked) and is not this finding.

**Smallest fix:** Leave the bar. If the artboard’s overflow only repeated Reply / Mark read / Delete, those already live on the row (batch-7-7) and do not need a second chrome menu. Do not add an empty overflow to match the frame.

---

## Checked, matches

### 1m — signed-in hub

- Flattened on purpose. `AccountView.swift:4` drops the Overview / Reading / Writing / Activity segmented control. Do not restore it. `libraryStyleCompactRoot` still builds that control (`:312`) and is unreachable: `usesLibraryStyleCompactLayout` requires `showsWorkListControls`, which is false for every tab (`:139`). Not on screen.
- Row orders: Reading Marked for Later, Bookmarks, Collections, Subscriptions (`:133`). Writing Works, Series, Drafts. Activity History, Inbox. Account is **Preferences** and **More on AO3** (`:662`).
- Rows are 15pt plus a 13pt medium mono count and a chevron (`:1227`). Collections renders **100+** when the cache stored a lower bound (`:1249`). Drafts subtitle **Deleted by AO3 after 30 days** (`:1118`). History subtitle **AO3’s own history, not the local reading log** (`:1131`). Inbox subtitle is the unread count only (`:1137`).
- Shortcuts default to the six tiles (`AccountShortcuts.swift:76`). The editor is the Shortcuts header’s see-all (`AccountView.swift:633`). Dashboard’s `countKind` is nil (`AccountShortcuts.swift:71`); the artboard’s **104** is not invented. The group-header row counts are batch-7-18.
- Signed-in wash is `subjectWash` in the account palette (`:260`). The kicker colour follows that palette, not a fixed crimson. 1m’s frame uses crimson because that user picked it.
- Toolbar while idle is the gear. Inbox filter and select are not on this tab: `isInboxVisible` is the old inline inbox (`:492`), and the inbox is now pushed. Gear is 44pt glass (`:892`), not the artboard’s 34. The comment records the 44pt floor. Not a defect.
- `subjectScreenWash` keeps the system bar transparent and is the staged stand-in for floating glass (`SubjectScreen.swift:98`). Account hides the bar and overlays the gear because the artboard’s circle is under the hit floor. Not reverted.
- Pull to refresh calls `refreshCurrentTab` (`:277`).
- Identity: 56pt circular avatar, 27pt bold name, tracking −0.5 (`AccountComponents.swift:23`, `:119`). Healthy session sentence matches. The kicker, the missing pill, the caption-sized session line, and the bordered ellipsis are batch-7-6. Log Out’s missing confirm is batch-7-11.
- Username is stated once, in the card. The old second `SubjectHeaderBlock` is gone (`:53`).

### 1n — signed out

- No wash (`AccountView.swift:262`). Title **Not signed in** at the same 27pt (`AccountComponents.swift:285`). Body matches: **Log in to use your AO3 works, bookmarks, subscriptions, history and inbox. Your session stays on this device.** Button **Log In to AO3**, and **Logging In…** while `.signingIn` (`:304`), `.borderedProminent` capsule.
- **No account, no colour** is omitted on purpose (`:276`). It is the artboard talking to itself.
- **What is waiting**, intro **Signed in, this tab fills in with your own account:**, groups built from `readingRowOrder` / `writingRowOrder` / `activityRowOrder`, values withheld, `allowsHitTesting(false)`, fade mask (`AccountView.swift:913`). The artboard’s preview is the old shorter list (no Subscriptions, no Drafts, no History). The code matches the live hub, which is what the caption asks for. Not a defect. The preview avatar is 44pt against the signed-in 56pt; measured, not filed on its own.
- The gear still shows while signed out (`:166`). That matches the caption.

### 1o — Marked for Later

- Header title **Marked for Later**. Subtitle `N work(s) · synced {phrase}` and `· page X of Y` when paged (`AO3MarkedForLaterCopy.subtitle`, `:152`). Phrases: just now / 1 min ago / N min ago / 1 hr ago / N hr ago / 1 day ago / N days ago. The line refreshes once a minute (`:277`).
- Pills All / Updated / Downloaded / Reset (`:7`, rail `:431`). Reset is quieter and labelled **Reset filters**.
- Groups **Updated since you looked** (covers) and **Everything else** (ledger) (`:28`). The Updated and Downloaded pills flatten to one run. The frame draws **Updated** selected over the All composition; the grouping comment says there is no second frame (`:77`). Not filed.
- Footer includes **unmarking here unmarks there** and clamps the page numbers (`:191`). The frame’s **12 of 4 pages** is not copied.
- Download words match. Size and colour are batch-7-14. The Unmark chip and the missing **NEW** / chapter range are batch-7-4.
- Display-mode menu is omitted for this kind (`AO3AccountWorksList.swift:310`). Correct: the screen is one layout.
- Filter chips use `minimumHitTarget(28)`. The modifier grows an invisible hit area and its comment allows a floor under 44 when 44 would overlap neighbours (`MinimumHitTarget.swift:28`). Not filed.
- Empty, when the whole list is empty, replaces the screen (batch-7-19). A filter with no rows keeps the header and offers **Reset** (`:315`). Error is **Couldn't load your list** with **Try Again** (`AO3AccountWorksList.swift:471`). First load is `AO3WorkRowSkeletonList` (`:480`). Pull to refresh is on the host (`:715`). Cover size 164 × 164√2 matches the 164×232 frame.
- Subtitle size is batch-7-13. macOS title matches this one kind (batch-7-19).

### 1q — Bookmarks

- Title **Bookmarks**. Pills All / Recs / Private / With notes / Reset (`:12`, rail `:303`).
- Footer: **Your bookmarks on AO3. Each row's note, tags, date, and private or rec mark are that bookmark's own.** (`:69`). That is the caption’s point (AO3’s note and tags, not local User Tags).
- Mature blur hides the footnote with the row (`:275`). Do not split them.
- The subtitle, the ledger-instead-of-search-card, and the footnote’s captions are batch-7-2. Subtitle size is batch-7-13. Empty-replaces-screen is batch-7-19. Chip floor 28 is the same allowed exception as 1o.
- Display mode is in the `...` menu. Compact still draws ledger content inside a card, so the menu does not reach the artboard’s card either way (batch-7-2).

### 1t — History

- Title **History**. Subtitle is the visible count, **N works**, plus **N in progress** only on Everything, plus the page clause (`headerTallyLine`, `AO3AccountWorksList.swift:854`). It is this page’s count. A grand **100+** was not found on the readings parse, so it is not filed as missing.
- Pills Everything / In progress / Finished / Reset (`AO3Client+Readings.swift:194`).
- Visit buckets Today, Yesterday, This week, This month, Earlier (`:256`). The caption asks for source-ordered kickers. The frame extract does not name them. The titles match the caption.
- Swipe **Delete from History**, `allowsFullSwipe: false`, only when `readingID != nil` (`AO3HistoryWorksBrowser.swift:139`). Overflow **Clear History** is destructive and last (`AO3AccountWorksList.swift:321`). Confirms: **Delete from History?** and **Clear your entire history?** (`:386`). That is the footer. Menu otherwise: mature reveal when Hide Mature is on, display mode, Expand all when not compact. No Select and no Reorder. Checklist B’s full library menu does not all apply to an AO3 history page. Not invented.
- The strings for visits, versions, last visited, and local **Finished** / **Ch. N of M** match (batch-7-5). The layout, the single grey line, and the uncoloured version are the finding.
- Empty, error, skeleton, and pull to refresh are the shared account-list states (batch-7-19 for the empty header). Subtitle size is batch-7-13. macOS title **My AO3 History** is batch-7-19.

### 1p — Subscriptions

- Title **Subscriptions**. Subtitle `N works · N with new chapters · page X of Y`, and the new-chapters clause only on All (`AO3SubscriptionsCopy`, `:150`). The index stores `totalPages` and no grand total (`AO3Client+NamedSubscriptions.swift:66`). **104 total** is not invented. The page clause is the honest substitute.
- Scope pills Works / Series / Authors match 1p.4, which the decisions say to build (`REDESIGN_DECISIONS.md:93`). The second All / Updated rail and the section titles are batch-7-3.
- Unsubscribe swipe, no button on the card, then **Unsubscribe?** (`AO3AccountWorksList.swift:419`). The confirm is checklist B, not a revert to a confirmation-free write. 1o.4’s “confirmation-free” is Unmark, not this.
- Origin kicker defaults to **AO3 Account**. Home passes **Home** (`AO3AccountWorksList.swift:128`). That is the build note.
- Empty **No work subscriptions** keeps the scope pills (`:303`). Filter mismatch offers **Reset**. Footer states that unsubscribing here unsubscribes there (`:175`).
- Subtitle size is batch-7-13. macOS title **My Subscriptions** is batch-7-19. The cover-versus-ledger gap is batch-7-3.

### 1l — Inbox

- One of the two heroes uses the right noun and the right size (15.5). The second hero is batch-7-1.
- `headerLine` is **N comments · N unread · N awaiting your reply**, and **on this page** when `totalPages > 1` (`AO3InboxModels.swift:280`). The artboard says **awaiting a reply** and does not say **on this page**. The test pins both the noun and the page clause (`AO3InboxParseTests.swift:422`). Checked, not a revert. The duplicate **messages** line is the defect.
- Pills All / Unread / Awaiting reply / Replied, plus the dashed Filter at the end of `SubjectFilterRail` (`AccountInboxScreen.swift:129`, titles `AO3InboxModels.swift:221`). Counts are not printed on the chips.
- Kicker is the account accent, not the frame’s `#7FC9E0`. 1t’s kicker in the same family extracts as `#E39B9B`. The app rule is the scope palette (`AO3AccountWorksList.swift:840`). Do not retint Inbox to teal.
- Row chrome that matches: 40pt avatar, name semibold, excerpt `.subheadline` line-limited to 3, **on** / chapter chip / **of {work}** (`AccountInboxViews.swift:358`). Reply is gated on `canReply`. The strip’s type, Mark read’s placement, the Replied badge’s placement, and the missing quote are batch-7-7.
- Toolbar funnel and select match the caption’s jobs. The system bar is kept so Select All and the bottom bar have a home (`AccountInboxScreen.swift:12`). Select All plus a bulk bar of Delete and Mark Read. No chrome overflow (batch-7-20). Swipe mark-read refuses full swipe because it posts to AO3 (`:701`). Delete stays in the overflow and the bulk bar, both of which confirm (`:655`).
- Loading is three avatar-and-line skeletons (`:578`). Empty **No comments yet** keeps the header (`:540`). Failure **Couldn't load your inbox** with **Try Again**. A failed later page keeps the loaded page (`:548`).
- The artboard’s build note that Mark read is device-side is stale. The swipe comment says the action posts to AO3. The code wins.

### 1y — Dashboard

- `AO3DashboardView` hosts `AuthorProfileView(..., navigationTitle: "Dashboard", showsDashboard: true)`. Signed out: **Not signed in** / **Log in to AO3 to open your dashboard.**
- Header kicker **AO3 Account**, title the username, 32pt. Subtitle is nil on the dashboard, or **Pseud of {username}** (`AuthorProfileView.swift:305`). `AO3AuthorHeader` has no `joinedDate` and no invitation count. `joinedDate` lives on `AO3AuthorAbout`. The comment refuses a fetch just to print the artboard’s date. **Joined 4 Mar 2019 · 2 pseuds · 3 invitations left** is not filed.
- Fandom chips and the unused `workCount` are batch-7-8. The strip, the duplicate See all, and the header placement are batch-7-16.
- See-all count comes from `AO3AccountListCountsCache` (`:132`). **See all 12 works** only when the cache has a number; otherwise **See all works**.
- Empty copy is present: **No fandoms listed on AO3.**, **No recent works visible on AO3.**, and the same shape for series and bookmarks, plus a “couldn’t read” line when the parse failed (`:31`, `:63`). Pull to refresh calls `model.refresh` (`:275`).
- Digits staying `.primary` matches the extract’s `#fff` figures on the fandom wash. Do not tint them.

### 1z / 1bb — AO3 Preferences

- Header: kicker **AO3 Account**, title **AO3 Preferences**, subtitle **Stored on AO3 · applies everywhere you read** (`AO3PreferencesView.swift:647`). Subtitle size is batch-7-13.
- Footnote: **Every switch here is a field on AO3’s own preferences form, in AO3’s own groups. App-only settings live in Settings.** (`:569`).
- Account links, all seven, no counts: Edit profile, Manage pseuds, Change username, Change password, Change email, Blocked users, Muted users (`:588`). The comment says the preferences page carries no counts (`:585`). The artboard’s **2** and **5** are not invented.
- Section chevrons collapse in memory (`:190`). Help is `questionmark.circle` at 44pt (`:233`).
- Toggle labels are the live AO3 strings. The view does not add the artboard’s 11.5pt footnotes under Show adult content and Keep reading history. Whether the parser drops a separate description was not confirmed, so those footnotes are not filed as missing.
- The synthetic **Display options** group is batch-7-9. The centred spinner is batch-7-10. Error has Try Again.
- Save is a toolbar text button because floating glass is staged. The in-button spinner is not a row spinner (1bb). Disabled until there are edits.
- Toast does not push content, success leaves after 3 seconds, failure stays with **Retry** (`:503`). Copy, the nested capsule, and the failure wash are batch-7-15. The pushed screen hides the tab bar via `subjectScreenWash`, so “above the tab bar” is not literal. Not filed.
- macOS title **My Preferences** is batch-7-19.
- Field labels were not compared to a fixture. Artboard paraphrases (**Hide my work from search engines**) are not flagged against AO3’s own wording.

### 1ab — Settings

- Header matches: kicker **AO3 Account**, title **Settings**, subtitle **App only · nothing here reaches AO3** (`SettingsHeaderBlock.swift:21`). The accessibility value says the settings stay on the device.
- The hub is the decision, not the long form (`REDESIGN_DECISIONS.md:17`, `SettingsRoute.hubGroups`, `:51`). Reading (Appearance, Font, Reader, Listening on iOS), Downloads & Storage (Downloads, Preservation, Reading Queues), Library & Sync (Library, Backup, Sync Folder, Import), Account & Privacy (AO3 Account, Privacy), About. **Library** is not in the decision table. The comment says it holds confirm-before-delete and show-zero-counts, and a reorganisation cannot drop them (`:47`). Checked.
- **Notifications** is absent. The decision says not to build it (`REDESIGN_DECISIONS.md:45`). Not a defect.
- Flat artboard rows (Theme, Accent colour, Text size, Keep screen awake, Storage used, Sign out, Privacy and local data) live on the pushed pages. **Privacy and local data** is a `NavigationLink` on the About section (`SettingsAccountPages.swift:94`) and `SettingsRoute.privacy` maps to `PrivacyDataView` (`SettingsHubView.swift:99`). **Log Out** is on AO3 Account (`:145`). Its missing confirm is batch-7-11, not a missing row.
- Hub rows are `SubjectFormRow` plus a disclosure. `SectionRuleHeader` has no count and no see-all. Wash is the scope palette. macOS title **Settings**.
- Pushed pages use `SettingsPageForm`: kicker **Settings**, title the route title, native Form, tab bar hidden. That kicker is not 1ac’s breadcrumb. Not filed against 1ac.
- Subtitle size is batch-7-13. Value-column strings (theme title, font name, **On subscribe** / **Manual**, and empty values on Listening, Preservation, Library, Backup, Import) were read as the hub’s summaries. They were not opened page by page, so a wrong value inside Downloads or Appearance is not claimed.

### 1ac — Privacy

- Header: kicker **AO3 Account › Settings**, title **Privacy**, subtitle **Nothing leaves your device** (`PrivacyDataView.swift:179`). Subtitle size is batch-7-13. Headline type is batch-7-17.
- The body is rewritten on purpose (`:202`). The artboard’s **The app talks to AO3 and to nothing else** is false once a Voice Pack host can see an IP. The replacement names AO3, the confirmed Voice Pack download, and what stays on the device. Not reverted.
- Stored rows the artboard does not draw — Original files kept, Imported fonts, Draft recovery, Caches, Saved searches — are the measured figures the file header defends (`:25`). **Search history** is **Not recorded** (`:293`). There is no **Clear search history**, because it is not stored. Checked.
- Clear rows: Clear downloads, Clear reading positions, Clear reading history, Clear browse cache. Each confirms, and each is disabled when empty (`:304`). The artboard’s third clear is search history, which does not exist. **Clear reading history** and **Clear browse cache** stay. Footnote matches: local, two-step, AO3 history is separate (`:352`).
- **AO3 session** and **Read Aloud downloads** stay. The file comment says dropping them would drop the hardest privacy facts (`:18`). Checked. The session row’s missing confirm is batch-7-11.
- Counts are **N work(s)** / **N file(s)**. Bytes use the footprint formatter, an em dash before the scan. Pull to refresh remeasures. Pending bytes are **—**, not a blank row.
- The promise body is 12.5pt secondary. The artboard’s body is `400 13px` `.76`. Measured, and left beside batch-7-17 rather than as its own finding: the sentence is the honesty override.

### 1aa — More on AO3

- Title **More on AO3**. Subtitle **Opens on AO3 in Browse** is the true destination (batch-7-12 is the glyph, not this sentence).
- Groups, in order: Post and manage, Challenges, Your account, The archive (`:95`).
- Post and manage: Post new work, Import work, Edit works in bulk, Manage collection items, Related works, then **Drafts** (`:145`). Drafts is not on the artboard. The comment keeps it at the end because the screen already offered it.
- Challenges: Sign-ups, Assignments, Claims, Gifts given and received (`:256`).
- Your account: Profile, Invitations, Skins and site styles, then **Pseuds**, **Co-Creator Requests**, **Statistics** (`:201`). **Fannish next of kin** is omitted on purpose (`:197`): no user route, and Support is already first in The archive.
- No count badges. The comment says the figures are not in `AO3AccountListCountsCache` and the screen does not fetch (`:133`). The artboard’s **12**, **3**, **4**, **1**, **7**, and **3 left** are not invented.
- The archive titles match `AO3ArchivePage.title` (`:17`): Support and feedback, Report abuse, Terms of Service, Content policy, Privacy policy, FAQs, Donate to the OTW.
- macOS title **More on AO3**. Subtitle size is batch-7-13.
- The external glyph on every row, including Preferences’ account links which share `AccountExternalNavCard`, is batch-7-12.

### Accessibility and platform (checked in code, not on a device)

- Unmark uses `minimumHitTarget()` at the default 44 (`AO3MarkedForLaterWorksBrowser.swift:397`). Filter chips on 1o, 1q, 1t, and 1p use 28, which the modifier documents as the overlap exception. Inbox Reply is the shared 44pt comment control. Privacy clear rows and the help glyph are 44pt. The hub gear is 44pt.
- Inbox rows collapse to one accessibility element and expose Reply, Mark Read, and Delete as actions (`AccountInboxViews.swift:251`). The session line combines its icon and text (`AccountComponents.swift:173`). Settings’ header has a value that restates the device-only promise.
- Reduce Motion was not found on these screens’ own toggles. Dynamic Type: header titles scale with `.title` and clamp at two lines until an accessibility size (`SubjectSurface.swift:467`). Cover cards scale and clamp (`CarouselCardStyle.swift:54`). Not watched at an accessibility size.
- iOS hides the account-list bar and states the name in the header. macOS keeps a window title (batch-7-19). iPad and macOS were not run. Keyboard avoidance on Preferences’ text fields was not watched. Pull to refresh is on the hub, the account lists, the dashboard, and Privacy’s remeasure.

---

## The three that matter

1. **batch-7-1.** Inbox draws two 32pt **Inbox** titles. The first says **comments**, which is the artboard and the tested tally. The second says **messages**. One of them has to go.
2. **batch-7-2.** Bookmarks is the screen the artboard spends the frame on — the note on an accent rail, the lock in place of that note, the date on the stats line, **N bookmarks · N private · N recs**. The shipped row is a ledger with a **Bookmark Notes** caption underneath, and the subtitle counts works.
3. **batch-7-3.** Subscriptions was the “needs building” frame: covers for what is new, a ledger for everything followed, one rail. It is two rails and a ledger of footnotes. History opening as cover cards (batch-7-5) and the always-on Unmark chip (batch-7-4) are the same kind of miss, on the two lists next to it.
