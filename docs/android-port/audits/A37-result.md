# A37 — assignments, own works / bulk edit, and the page cache

Reviewed 2026-10-15. Android source is **651d2ead**, `android/redesign-parity`, in `/Users/cidy02/kudos-android-lane`. Compared the three landing commits (`c161a0bb`, `9e1fa2a8`, `f0bda512`), their result/landing notes, and the current code. iOS reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader`, worktree HEAD `af85ab09`. iOS has fixes newer than the landing notes; those are identified below.

Read-only source review. No build, test execution, emulator, login, AO3 contact, commit, push, or branch switch. Source quotations and failure interleavings below are static evidence, not claims of runtime reproduction. Other processes began editing the Android lane during this audit; affected files were subsequently read with `git show 651d2ead:<path>`. Their edits are outside this review. The existing A49/A50 files in the output worktree were left alone. This report is the only file written.

Path convention: **A/** means `android/app/src/main/java/io/github/cidy02/kudos/` in the Android lane; **T/** means `android/app/src/test/java/io/github/cidy02/kudos/`; **I/** means the iOS reference directory above. Thus, for example, `A/network/ao3/AO3PageCache.kt:79` identifies that exact source file and line at the reviewed revision.

## Findings, highest-priority paths first

### F1 — P2: own-work writes leave pre-write pages available to the cache

**Code.** `A/author/AuthorProfileScreen.kt:350`: `fun reloadAfterWorksWrite() = loadHeader(bypassCache = true) {`; lines 351–352 reload the current tab and stats with bypass. `A/network/ao3/writes/AO3WriteRepository.kt:415`: `movedOnAfterWrite(expectedGeneration, response)?.let { return it }`, then `return response` — no page removal. `A/network/ao3/AO3PageCache.kt:98`: `if (!bypassCache) value(key)?.let { ... }`; lines 90–94 still allow fallback when bypassing.

**Failure.** Read own Works pages 1 and 2, then successfully bulk-edit a rating, edit tags/a work, add or delete a chapter, or delete a work. The immediate successful reload replaces only the URLs it reads (normally dashboard, Works page 1, stats). Return to page 2 inside five minutes: the old rating/deleted work can be served as fresh. Alternatively let the immediate bypassed reload fail with a transport error: the old dashboard/list can return as stale even though its content predates the confirmed write. New-work/draft posting through `A/app/AppNavHost.kt:654` only notifies the Drafts destination; previously cached author lists remain too.

**Smallest fix.** Remove the writer's affected author-page variants at the shared work/chapter write boundary, before any post-write reload; retain the bypass. Include pseud routes and all pages/sorts/scopes, rather than just page one. Apply this to sent writes with an uncertain result as well: a partial tag run has already changed earlier works. Account dashboard/recent works, Works, Stats, and author series summaries can all carry changed work facts.

**iOS / note.** Current iOS `I/Services/AO3WorkActions.swift:581–583` does `await AO3AuthorPageCache.shared.removeAuthorPages(username: username)` after the returned write; `I/Services/AO3Client+Authors.swift:684–690` removes all account/pseud/query variants. Android lacks that newer fix. 3ce's landing note records the immediate bypass fix and explicitly says it removes nothing for these writes; it does **not** record that other variants and offline fallback remain wrong. 3cd's later emulator note records the immediate bulk-save reload, not this remaining defect.

### F2 — P2: series writes remove the show page, but leave the author's series lists

**Code.** `A/writing/WritingSeriesState.kt:36–39`: `seriesChanged()` sets `changed = true` and calls `removePages("/series/$id", ...Scope(auth.username(), generation))`. `A/author/AuthorProfileScreen.kt:405` bypasses the opener's header/current list; `A/app/SeriesWorksScreen.kt:119` bypasses the opener's series detail.

**Failure.** Cache your author Series list, open a series from another entrance, rename/reorder it or remove a work, then reopen the author list inside five minutes. The cached old title/order/count remains. Even when editing from the author list, a cached second page or pseud variant survives the opener's page-one reload. An unconfirmed series write removes nothing at all, although AO3 may have applied it.

**Smallest fix.** Extend series invalidation to all cached series-index variants for the creator, plus the series show-page variants. Invalidate for an uncertain sent write too. No additional AO3 read is needed merely to remove these entries.

**iOS / note.** Current iOS `I/Services/AO3Client+Authors.swift:670–678` removes the show pages and creator's series lists; `I/Services/AO3WorkActions.swift:240–243` also handles an unconfirmed save. Android's show-page removal is a later improvement over 3ce, whose note said no series invalidation was added; neither this remaining index omission nor the current iOS fix is recorded there.

### F3 — P2: a bypassed post-write GET can join a pre-write GET and mark its answer fresh

**Code.** `A/network/ao3/AO3Client.kt:101–107`: the GET key is `AO3RequestKey.get(url, headers)` and is sent through `coalescer.coalesce(key)`. `A/network/ao3/AO3RequestCoalescer.kt:42–46`: `inFlight[key] ?: CompletableDeferred<V>()` runs the operation in its own scope; line 57 awaits it. `A/network/ao3/AO3PageCache.kt:103–115` fetches, parses with `stale = false`, and inserts the answer. Its revision belongs to the cache read, not the underlying GET's start time.

**Failure.** Home/Account begins GET U and AO3 produces the old page, but its answer is delayed. A pushed screen completes a write affecting U, removes the cached entry, then re-reads U with bypass and the same cookie/headers while the first GET remains in flight. The new read joins that old operation. Its own cache revision is current, so the pre-write HTML can be installed and displayed as **fresh**. Canceling the older screen's job does not retire the coalescer's independent operation. This applies even to Inbox/series/author actions that correctly invalidate memory.

**Smallest fix.** Give invalidated/post-write GETs a new request epoch, or retire the affected in-flight GET key at invalidation so the read-back cannot join an operation begun before the write. Keep old-read insertion fencing too. `bypassCache` alone only bypasses memory.

**iOS / note.** iOS also coalesces GETs below its page cache (`I/Services/AO3Client.swift:791–799`, keyed by URL/cookie); the reviewed invalidation methods do not themselves retire a transport operation. Do not treat iOS parity or a memory-cache revision as proof against this ordering. Neither landing note records this transport-level race. This is distinct from a transport failure's stale fallback: that path correctly marks the copy stale (§13).

### F4 — P2: removing one cache key cancels unrelated page reads without a usable result

**Code.** `A/network/ao3/AO3PageCache.kt:42`: `fun remove(key: Key) { revision++; entries.remove(key) }`; line 79: `if (scope(auth) != viewerScope || version != revision()) throw CancellationException()`. Lines 119/126 call `remove(key)` after a non-fallback failure, even if no entry exists. Every key shares that revision.

**Failure.** Start a series-detail GET and a different author-page GET. Let the author page return 404/403 or fail parsing first; removing its key advances the global revision. The valid series answer now throws cancellation. `A/app/SeriesWorksScreen.kt:95–104` set `Loading` before the read and only installs a terminal state after a returned result: it stays loading. Two readers sharing one refused GET can also cause the second reader to receive cancellation instead of the refusal.

**Smallest fix.** Use key/path-specific invalidation epochs for selective removals, reserving a global epoch for a real clear/session transition. Each independently requested page must still receive its own failure/success.

**iOS / note.** iOS's `removeValue`/`removePages` only filter the matching entries (`I/Services/AO3Client+Authors.swift:654–665`); they do not cancel every other page read. The 3ce note describes the revision as protection against reinstalling invalidated data, but does not record this cross-page cancellation.

### F5 — P1: a tag edit re-sends untouched tag groups from an older snapshot

**Code.** `A/network/ao3/writes/AO3WriteRepository.kt:168–177` reads an edit-tags form and passes `changes.applying(form)` into `editWorkTags`. That method reads the form **again** at lines 231–245, then uses `fresh.withTagsFrom(desired)`. `A/network/ao3/writing/AO3WorkForm.kt:232–235` copies all seven tag fields. `A/network/ao3/writing/AO3WorkFormEncoder.kt:104–111` sends all served rating/warning/category/tag fields and the fresh language. `A/network/ao3/writing/AO3BulkEdit.kt:54–57` computes every tag list, including untouched ones.

**Failure.** In a bulk edit, add only freeform `Fluff`. First GET for work 1 sees relationship `A/B`. Before the second GET returns, another edit changes that work's relationship to `A/C`; the second GET correctly contains `A/C`. `withTagsFrom(desired)` replaces it with the first GET's `A/B`, and the POST writes `A/B` back despite Relationships being untouched. This is an unintended AO3 write/data loss. A no-change bulk save emits no POST; the fault appears once *any* tag group changes.

**Smallest fix.** Merge the bulk intent against the same fresh form used for dispatch (one preparation GET), and encode only tag groups that the reader changed. Do not copy all old tag groups over a fresher form. Preserve full replacement encoding within each changed tag group so explicit removals still work.

**iOS / note.** Shared with current iOS: `I/Services/AO3WorkActions.swift:418–422` computes the merged tag set; `editTags` at lines 149–153 loads again and assigns `form.tags = desired`; `I/Models/AO3WritingModels.swift:158–184` encodes the entire set. This is parity with an iOS fault, not evidence of safety. Neither landing note records it. The uniform bulk encoder correctly omits untouched groups; see §5 for the distinction.

### F6 — P2: missing bulk-form groups still get editable native controls

**Code.** `A/network/ao3/writing/AO3BulkEdit.kt:73–85` records option lists, not the served status of all groups. `A/writing/WritingBulkEditScreen.kt:123–125,139–147` always offers Add to collections/co-creators/Remove me. Lines 223–226 invent literal On/Off choices for restricted/comment moderation irrespective of the served form. `AO3BulkEditChanges.parameters` at lines 36–41 emits those choices without a served-field check.

**Failure/input.** Serve a recognized `edit_multiple` form with the correct selected IDs and CSRF, but omit `remove_me` and `work[restricted]`. The parser accepts it. Tap Remove me, or Visibility → Only show to registered users → Off → Save. Android sends `remove_me=1` or `work[restricted]=0` even though AO3 did not serve that group. Missing rating/language/comment-permission choices instead open a picker containing only Leave as is; missing warnings/categories/removal collections are disabled. An untouched missing group does emit nothing.

**Smallest fix.** Retain served/enabled group names in the parsed form; disable absent groups and restrict the diff to those groups. Preserve the three-state Leave as is/On/Off behavior for served booleans.

**iOS / note.** Current iOS also has unconditional literal boolean/creator/add-collection controls (`I/Features/Writing/EditMultipleWorksView.swift:244–249,289–335`) and no served-group restriction in `AO3BulkEditChanges.parameters`. Shared limitation, unrecorded in the landing note. This finding establishes the unserved request from source; it does not invent a particular AO3 server response to that malformed/limited form.

### F7 — P2: a partial bulk tag run reports no progress and Save starts over

**Code.** `A/network/ao3/writes/AO3WriteRepository.kt:166–182` returns on the first failed read/write; only afterwards can lines 184–190 submit the uniform request. `A/writing/WritingBulkEditState.kt:45–47` retains the original changes and stores only `saveError`; `A/writing/WritingBulkEditScreen.kt:81` titles the alert `AO3 could not save the change`.

**Failure.** Select seven works; add `Fluff` and set language. Let works 1–3 confirm their tag writes, then fail the read for work 4. The uniform language POST is correctly **not sent**. The screen only shows the work-4 error, with the original seven-work form intact. Dismiss and tap Save: all seven tag operations start again, then the uniform POST if all succeed. If the *third write itself* refuses, only two are confirmed and five remain; if the run stops after three confirmed, four remain. No automatic retry occurs.

**Smallest fix.** Record/show the confirmed IDs/count and explicitly say the uniform changes were not sent and Save currently retries the whole selection. A resume option must use those confirmed IDs; do not silently claim a four-work resume that the code does not implement.

**iOS / note.** No fault in stopping before the uniform POST: iOS's throwing loop has precisely that ordering (`I/Services/AO3WorkActions.swift:415–433`). iOS's view also retains the original changes after failure (`I/Features/Writing/EditMultipleWorksView.swift:367–377`). The 3cd landing note **already records** the missing partial-progress explanation on both platforms; the all-seven retry behavior is not explained there.

### F8 — P2: a list refusal hides loaded rows but leaves their write candidates usable

**Code.** `A/account/AO3ChallengeAssignmentsState.kt:146–150`: a refusal sets `stopped = ... lists.dropWhile { it != list }`, assigns its error to every stopped list, and blocks all of them. `A/account/AO3ChallengeAssignmentsScreen.kt:140–152` renders the error instead of the rows whenever that segment has an error. But `AO3ChallengeAssignmentsState.kt:47–48` still derives `reportable` and `candidates` from the retained pages, and `AO3ChallengeAssignmentsScreen.kt:218–223` enables the owner actions from those rows without consulting `blocked`/list errors. A list refusal does not set global `terminal`.

**Failure.** As owner, load all four lists successfully, including defaulted candidates and a reportable Open row. Refresh; Complete succeeds, Open returns Forbidden. Defaults and PinchHits are not re-read, but both get Open's error and become blocked. Their previously loaded rows remain in the model yet disappear from their segments, for the rest of this opening. Nevertheless Claim a pinch hit and Report a default still open the old candidates; confirming initiates the supposedly blocked list's token GET again. A persistent refusal stops that preparation before a POST, so this is not evidence that a forbidden POST bypasses AO3. It is a broken fail-closed control/read policy after the refusal.

**Smallest fix.** Exclude blocked/failed source lists from write candidates and disable their owner actions. Keeping the old pages in memory must not make them permission evidence. If hiding previously loaded lists is the chosen shared-permission policy, apply it consistently to the pickers as well.

**iOS / note.** iOS clears loaded state and independently reads its three display groups (`I/Features/Challenges/ChallengeAssignmentsView.swift:478,487–500`), so failed groups do not retain the previous load's candidates. Android's landing note records the intentional fewer-read policy; it does **not** record the hidden-but-actionable retained rows. Hiding the lists itself is a conservative consequence of that recorded policy, not an access leak.

### F9 — P2: the works-due retry is repaired only when closed state was unknown

**Code.** `A/account/AO3ChallengeAssignmentsState.kt:87–89`: `if (!owner || dueAttempted) return null`, followed by `dueAttempted = true; dueSucceeded = false`. Line 105 resets the attempted flag on refresh only when `dueSucceeded` is true. Lines 119–127 reset failed attempts only in the `closed == null && owner` path.

**Failure.** Owner arrives with `knownClosed=true`. Lists load; the best-effort settings read at line 154 times out. Pull refresh: lists are read, but settings are never tried again because `dueAttempted=true`, `dueSucceeded=false`, and `closed` is already true. The due date and Late badges remain absent until reopening. A successful optional due-date read *is* retried on refresh, perversely giving failures less opportunity than successes.

**Smallest fix.** Reset the failed, non-refused due attempt on explicit full refresh too; retain refusal suppression separately. Loading/busy guards still serialize it.

**iOS / note.** iOS attempts the optional due read on each load (`I/Features/Challenges/ChallengeAssignmentsView.swift:502–508`). The note records the owner's repaired unknown-closed retry, not this known-closed failure path.

### F10 — P2: a lost assignment POST answer is presented as a reason to try again

**Code.** `A/network/ao3/writes/AO3WriteRepository.kt:462–463` passes a same-session transport failure through `collectionWriteVerdict`; its line 845 returns the failure unchanged. `A/account/AO3ChallengeAssignmentsState.kt:175` installs `answer.error.moderationMessage()` and clears pending. `A/account/AO3CollectionModerationState.kt:32`: timeout copy is `AO3 took too long to answer. Try again.`

**Failure.** AO3 applies a confirmed Claim/Report-default tap but the connection drops before the answer arrives. Busy clears, the old lists remain, and the screen says to try again, without saying the write may have landed. Choosing the same candidate and confirming again performs a new token GET and sends the same `cover_<id>`/`default_<id>` POST. This is a user-triggered repeat, not an automatic retry; AO3 may now refuse it because the first action succeeded.

**Smallest fix.** Convert post-dispatch transport uncertainty to the existing unconfirmed-write wording, with Check/Reload before trying again. Keep preparation-GET failures as ordinary retryable reads.

**iOS / note.** iOS also propagates a transport throw from `submitWrite` into the generic action failure UI (`I/Features/Challenges/ChallengeAssignmentsView.swift:689–693`). Neither note records that distinction; matching the success/refusal verdict rules does not solve a missing answer.

### F11 — P2: a failed next series page replaces the already loaded page with an error

**Code.** `A/app/SeriesWorksScreen.kt:96`: `state = SeriesWorksState.Loading`; lines 99–103 replace it with `SeriesWorksState.Error(...)` on failure. Neither state retains the displayed detail/works. Lines 208–221 show one state exclusively.

**Failure.** Display series page 1 from stale fallback. Tap page 2, which has never been cached, while offline. Page 1 and its banner disappear; the screen becomes Couldn't load series. The same happens starting with fresh page 1. The failed request cannot use page 1's cache entry because full URLs distinguish pages.

**Smallest fix.** Keep the last loaded series page during pagination/refresh, recording a separate requested-page error; clear it only for a real session reset or a policy that explicitly revokes display.

**iOS / note.** iOS preserves existing works and sets `loadMoreError` when a later read fails (`I/Features/Authors/AO3SeriesDetailView.swift:298–307`). The note records replacement pagination versus iOS append pagination, but not this loss on failure. No live UI appearance is claimed here.

### F12 — P3: the own-works/profile route still uses stock popup/dialog roles and unspecified text line height

**Code.** `A/author/AuthorProfileScreen.kt:460`: `DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false })`, with no token container; line 467: `Text("My Works")`; lines 493/497/502 likewise omit explicit color/line height. The series-row menu at line 908 is also untinted. Later native-action dialogs use AlertDialog defaults; line 548 explicitly uses `MaterialTheme.colorScheme.error`. `A/ui/theme/Theme.kt:66–77` sets OLED surface/surfaceVariant but leaves Material's surfaceContainer roles at their defaults; its error role is also unset. These are real current-lane sites, not claims that every one was introduced by 3cd.

**Failure/taps.** Open the own-profile More menu in OLED, or an own-series row's action menu. The popup's surfaceContainer role falls back to Material's default rather than the subject card token. Sepia explicitly maps those container roles (`Theme.kt:92–97`), so it should not be called an entirely stock Sepia popup. The named labels inherit Material typography rather than an explicit subject line height; they are not literally rendered without any line spacing. Unsubscribe/Block dialogs on another author's profile also use the unset stock error role.

**Smallest fix.** Supply the existing subject container/ink/accent tokens and explicit label line heights to these menus/dialogs. Bulk-edit's own Text calls and `OwnWorksControls.kt` already supply line heights; the bulk bar uses FlowRow and wraps.

**iOS / note.** iOS uses its subject-screen palette/native controls; these Android stock Material fallbacks have no iOS equivalent. Neither landing note records them. This is a source-level theme-role finding; no screenshot/contrast measurement was made.

## Answers to all requested checks

### 1. 3cc's four landing changes

- **(a) no fault:** owner/moderator admission is checked before reads, participants/signed-out viewers stop at `A/account/AO3ChallengeAssignmentsState.kt:106–109`; owner-only selection/write checks are at 77/81/164. A moderator with unknown closed state reads lists but never the owner-only settings form. The screen captures the admitted session (`AO3ChallengeAssignmentsScreen.kt:51–54`), so changing accounts does not reuse those role booleans. It cannot gain a participant read or expose a moderator owner-write control through this change. Compared with iOS, Android deliberately makes fewer participant/settings/refused-list reads; the landing note records this.
- **(b)** Only typed `Forbidden` and `AuthenticationRequired` count as refusal (lines 123/146), including the real client's conversion of a login page to AuthenticationRequired. 404, 400/other HTTP, rate limiting, parse errors, network failures, busy and 5xx do **not** stop all independent lists. Complete failure of any kind skips Open for that matched group (line 135), as iOS groups them. F8 covers hiding already loaded later lists. A 403 on Load more only blocks that requested list; it does not start any others.
- **(c) no fault in serialization:** `load` checks both `loading` and `busy` and sets loading before its first suspension (lines 101/112); `perform` checks both and sets busy before its first suspension (164/166). A double Retry or Retry during a write does not dispatch a second read. Unknown-closed transient failures reset the attempt and can be retried. F9 is the still-broken optional due-date retry.
- **(d) no fault:** `AO3ChallengeAssignmentsScreen.kt:278–282` spells out complete/open/defaulted assignments and pinch hits. iOS has no Load more labels here because it walks all pages; the note records that difference. The paged totals on Android describe the rows loaded, not a fabricated full AO3 total.

### 2. Claim and default requests, token source and verdict

Both native actions are owners' `update_multiple` fields, not the participant's separate `/assignments/:id/default` route. Comparison: Android `A/network/ao3/writes/AO3WriteRepository.kt:432–463`; iOS `I/Services/AO3ChallengeActions.swift:120–172`.

| Part | Claim a pinch hit | Report a default |
|---|---|---|
| Fresh token GET / Referer | `/collections/<slug>/assignments` (Defaults, page 1) | `/collections/<slug>/assignments?unfulfilled=true` (Open, page 1) |
| Token | `meta[name=csrf-token]` from that fresh authenticated page, not a cached form/list token | Same |
| POST address | `/collections/<slug>/assignments/update_multiple` | Same |
| Ordered fields | `_method=put`, `authenticity_token=<fresh>`, `cover_<assignmentID>=<trimmed signed-in username>` | `_method=put`, `authenticity_token=<fresh>`, `default_<assignmentID>=1` |
| Explicit action headers | `X-CSRF-Token`, that list Referer; no AJAX header/JSON Accept | Same |
| Verdict | Error flash wins; success flash or 3xx succeeds; unadorned 2xx is unconfirmed; typed refusal is failure | Same |

**no fault:** request shape/token selection match iOS, one token read plus one non-retried POST per confirmed action. No readback before the verdict. F10 covers a lost POST answer. A generation change before/after the token read stops the request, and the real authenticated client checks again at queued dispatch (`A/network/ao3/writes/AO3AuthenticatedClient.kt:53–62`; `A/network/ao3/AO3Client.kt:171–173`). Nothing is sent under a replacement session. After a dispatched POST, `movedOnAfterWrite` returns unconfirmed (or the actual AuthenticationRequired refusal), not a claim that nothing was sent (`AO3WriteRepository.kt:833–837`). The screen replaces/closes the old-generation model. These fences are stronger than merely checking at tap time and agree with the note's intent.

### 3. Assignment re-reads, late results and Load more

**no fault:** within this model, loads and writes are serialized by the pre-suspension flags; a write cannot begin during a pre-write list read. Busy clears and the confirmed write calls the full refresh inline (`AO3ChallengeAssignmentsState.kt:180–184`), with no suspension in the gap. Load more cannot overlap that refresh. Appended rows are `distinctBy { it.id }` (142); replacement refreshes do not append old pages. Matched display uses `index:id` keys; pinch-hit display uses `openFlag:id`, distinguishing the two sources (`AO3ChallengeAssignmentsScreen.kt:153,183`); candidates come from one list (or non-fulfilled Open rows). No duplicate-key crash from the requested load/write interleaving was found. iOS additionally uses a load-generation fence and de-duplicates its all-page walk; Android instead prevents this overlap. The landing note records paging, not these implementation details.

### 4. Demo assignment routes versus settings/moderation fixtures

**no fault:** `A/network/ao3/DemoNetwork.kt:1605–1607` accepts exactly Winter `/assignments` and `/assignments/update_multiple`. It does not take `/signups` or `/items`. `fixtureName:257–271` preserves the two sign-up pages separately and chooses each assignment list/page via fulfilled/unfulfilled/pinch_hit/page. Moderation still uses `/items` at 521–525; Challenge Settings still reads `/signups` through `AO3CollectionDetailRepository.kt:203–213`. The assignment fixture adds pagination, not sign-up/item ownership.

The demo checks the literal token/body/headers (1625–1632), mutates Defaults versus Open/PinchHits, and supplies refusals for IDs 85/86. It is a local scenario, not an AO3 protocol oracle. **P3 demo finding:** input = Load more defaulted assignments, choose page-two Ember Atlas (assignment **93**), confirm Claim. `A/network/ao3/DemoNetwork.kt:1636–1637` says `val allowed = if (claim) setOf(82, 88, 84) else setOf(84)` and `if (id !in allowed) return refused("This assignment cannot be changed.")`. The served page-two candidate is always refused. Its lookup also searches only the first source-page fixture (1623/1638), so adding 93 to the allow-list alone would not repair it. Smallest fix: support the served page-two ID and resolve/mutate its actual page document. Evidence: `android/app/src/debug/assets/fixtures/ao3_demo_winter_assignments_defaults_2.html:1` serves `cover_93`; ID 88 is on page one, not page two. iOS has no matching Kotlin demo fixture; the landing note does not record this limitation.

### 5. Bulk parser, every group and outgoing transformations

The parser verifies a trusted form action, a nonempty token, and the exact requested ID set/size (`A/network/ao3/writing/AO3BulkEdit.kt:64–72`). The served order of `work_ids[]` becomes save order, even if AO3 reordered the request. It reads option values literally; visible titles come from the first title link in each abbreviated-work `dt`. iOS's parser reads the same group selectors (`I/Services/AO3Client+Works.swift:460–500`), but Android additionally rejects mismatched selected IDs.

| Group | Untouched / undo edit | Explicit change or clear | Absent from bulk HTML |
|---|---|---|---|
| Rating | No uniform field; Leave as is maps to empty/omitted | Selected nonempty literal `work[rating_string]`; no blank “clear rating” distinct from Leave as is | Only Leave as is available |
| Warnings | No uniform field, no per-work run unless some tag intent exists | Tri-state Add/Remove/Unchanged; merged per work. Removing all sends served `work[archive_warning_strings][]=` | Picker disabled with no options |
| Categories | Same as warnings | Removing all sends served `work[category_strings][]=` | Picker disabled with no options |
| Language | Empty/Leave as is omitted from uniform POST | Literal nonempty `work[language_id]`; no separate blank clear choice | Only Leave as is available |
| Fandom / relationship / character / freeform | No field in uniform POST. Empty intent lists alone cause no tag run | Add/remove intent becomes per-work replacement strings; removing the last value sends an empty served `*_string` | Native intent editor still offered; per-work encoder omits an absent/disabled tag control on the fresh edit-tags page |
| Collections | Empty add/remove selections emit nothing | Add names joined into `work[collections_to_add]`; each chosen removal emits `work[collections_to_remove][]`. Clearing the *intent* cancels it; this is not “remove all memberships” | Remove picker disabled; Add still offered (F6) |
| Creators | Empty pseud string + false Remove me emit nothing | Pseud string sent literally as `work[pseuds_to_add]`; true emits `remove_me=1`; turning it back off cancels intent | Still offered (F6) |
| Visibility | Empty/Leave as is emits nothing; undoing On/Off via Leave as is emits nothing | `work[restricted]=1` or `0`, never a fabricated boolean default | Literal options still offered (F6) |
| Comment settings | Empty/Leave as is emits nothing | Moderation `1`/`0`; literal Who-can-comment value. No blank clear distinct from Leave as is | Moderation options still offered; comment-permission picker has only Leave as is (F6) |

**no fault in the uniform diff:** `AO3BulkEditChanges.parameters:31–41` omits unchanged groups, including all tag fields. An entirely untouched form returns success without a mutating POST (`AO3WriteRepository.kt:184`). F5 is the exception the word “untouched” must not hide: once a tag run happens, every served tag group is sent, even ones the reader left alone. Served language is also carried unchanged from the second fresh edit-tags form (`AO3WorkFormEncoder.kt:111`). This follows iOS's tags encoder, but violates a strict “untouched groups send nothing” reading and creates the concrete stale-snapshot wrong write above.

Transformations: `trimWritingTag` trims the explicit Foundation-style whitespace set (`AO3WorkForm.kt:224–227`). Per-work merges trim current/add names, discard empty names, remove case-insensitively, de-duplicate case-insensitively, preserve surviving current order/spelling, then append surviving additions (`AO3BulkEdit.kt:45–51`). Nothing is lower-cased on the wire; Kotlin's case-insensitive comparison is used for identity, whereas iOS uses lower-cased comparison keys (`I/Models/AO3WritingModels.swift:231–261`). This is not proof that their Unicode equivalence rules are identical. There is no outgoing alphabetical sort. Collection additions are trimmed/empty-filtered/joined in entry order; exact duplicate entries are prevented by the picker (screen line 214). Collection-removal values/scalars/pseud text are emitted unchanged. Tokens are not lower-cased. Selected work IDs use AO3's form order. The landing note does not discuss these parser/normalization details.

### 6. Per-work tags followed by the uniform POST

See F7. **no fault in stop order or pacing:** no uniform request after a failed tag run; no automatic retry; all calls use the shared paced client. This matches current iOS. The form and intents stay intact; Save restarts every selected work rather than resuming the tail. The landing note already acknowledges the missing progress explanation.

### 7. Bulk-delete confirmation, IDs and partial refusal

**no fault in target capture:** `A/author/OwnWorksControls.kt:37–48` copies the named summaries with `works.toList()` into pending and dispatches exactly their IDs, not a later live selection. The dialog reads that same list (`AuthorProfileScreen.kt:409–415`). A changed selection or a refreshed list from which a work disappeared cannot silently substitute another ID. A still-named disappeared work remains in the confirmed request, which is consistent with what the reader approved; AO3 decides whether it exists/is owned.

**no fault in request count:** one token GET from `/users/<username>/works/show_multiple`, one POST to `delete_multiple` with `authenticity_token`, repeated `work_ids[]`, and `commit=Yes, Delete Works` (`AO3WriteRepository.kt:193–204`). Not one POST per work. Matches iOS (`I/Services/AO3WorkActions.swift:454–469`).

If AO3 deletes some and includes an error for the rest, error wins (`workVerdict:422–426`), selection remains, and no success-triggered reload occurs (`OwnWorksControls.kt:49–51`; `AuthorProfileScreen.kt:376–377`). **P2 partial-delete finding:** confirm A/B/C; AO3 deletes A/B and returns a refusal naming C; the list still offers A/B and the dialog/error gives no native accounting of completed deletions. Smallest fix: preserve the authoritative error but re-read/invalidate the affected list after any sent bulk-delete result, with wording that some deletions may already have happened. Do not infer per-work success from one flash. iOS likewise treats an error as failure and refreshes only on successful deletion; this is shared behavior, not a wrong set of IDs. The note mentions the demo's full refusal and kept selection, not a partial real response. F1 describes the additional cache obstacle to a truthful reload.

### 8. Selection admission and lifetime after the hand merge

**no fault in writer-action admission:** `isOwnWorks` compares the signed-in login to the route's **username**, not the displayed pseud (`OwnWorksControls.kt:22`; `AuthorProfileScreen.kt:97–100,144–145`). Editing/deleting is available only for own Works (excluding Gifts/dashboard), so another account's pseud named like the viewer does not gain those controls. A pseud of the same login belongs to that account and is correctly eligible, as in iOS `AuthorProfileView.swift:542–550`.

The phrase Select Works is **also** offered from More for another author/signed-out browsing (`AuthorProfileScreen.kt:461–463`). That is the pre-existing remote selection flow: its bottom bar saves to the local library/Saved for Later, not AO3 bulk edit/delete (`1023–1036`). **no fault:** generic local selection is not an authorization leak. This distinction is not explained in the landing note.

Selection resets on route, session generation, tab, or works scope (`375`), and after confirmed deletion. It survives a page turn and refresh as an ID set; available actions use only `selectedIn(works)` from the currently loaded page (`1022`), so missing/off-page rows are excluded and can reappear selected on returning (`A/ui/components/RemoteWorkSelection.kt:79–80`). It also survives a successful bulk edit, as the later landing note says. This is safe target intersection, not cross-page bulk targeting. iOS accumulates pages instead of replacing them and likewise resolves targets from its loaded works at action time (`I/Features/Authors/AuthorProfileView.swift:634,845`). Whether Android should preserve invisible selections on page replacement is a product choice; no wrong ID write was found. New session state cannot inherit the previous selection through the generation reset.

### 9. Own-works and bulk-edit layout

**no fault found in the bulk bar's wrapping:** `OwnWorksControls.kt:67` is FlowRow, not a fixed-height row, and the hand-merged screen places it below a weighted refresh/list area (`AuthorProfileScreen.kt:588–605,1021–1027`). Bulk edit is a vertically scrollable LazyColumn; its Text calls specify line heights and its dialog/button/progress colors use subject tokens. F12 lists the actual stock Material/missing-line-height sites on the profile route.

One unverified narrow-layout boundary remains explicit: `WritingBulkEditScreen.kt:168–169` supplies the row value as a custom `trailing` Text with `widthIn(max = 160.dp)`. Consequently `A/ui/subject/SubjectForm.kt:147` cannot use its accessibility stacked-value branch (`value` is null); lines 185–194 give the label the remaining weighted width. At very narrow width/large type a long selected rating/language can consume the space needed by its label. Smallest fix if reproduced: use the row's normal value/stacked layout or a responsive Column for this value. **Not promoted to a visually verified clipping finding:** no emulator or layout execution was permitted. Ordinary bulk-header/footer controls were not proved missing from source alone. The landing note leaves large-text bulk-edit verification open.

### 10. Four banner hosts, appearance and clearing

The fourth host is the **Account tab's profile header/hub** (`AccountScreen`/`AccountViewModel`), not a comment thread or collection screen. Own-profile/Dashboard routes also reuse AuthorProfileScreen.

| Host | Appears | Leaves / can remain sticky | Failed read after stale content |
|---|---|---|---|
| Author profile | Loaded header and `headerStale || tabStale` (`AuthorProfileScreen:739–741`). Header success assigns its stale bit; successful tabs OR theirs in (`181,216,225,234,243`) | Full fresh header + selected-tab refresh clears; session/route reload resets. Fresh tab-only loads do **not** clear a previously true tabStale. Header-only success clears tabStale even without re-reading other tabs | Header failure clears header/banner (`184`); Works page-one load clears works before reading (`204`), and a failure shows the error. Same-key transient failures normally fall back instead; missing-key/refusal/parse failures cannot |
| Inbox | Successful parsed page assigns result.isStale (`AccountInboxViewModel:157`), including an empty page. Two exclusive rendering positions cover empty/nonempty lists (`AccountInboxPane:267,304`) | Fresh success assigns false; session transition resets; initial activation and refresh bypass. No sticky OR | Existing nonempty items survive ordinary failure except AuthenticationRequired (`166–176`); empty feed becomes failed. Post-write failed reload clears items (`384–388`) |
| Series | Loaded detail with isStale (`SeriesWorksScreen:99–100,221`) | Fresh success false; a replacement load removes the banner while loading/error; session resets state | Can replace old page outright (F11) |
| Account hub | `state.isShowingStaleCache` under signed-in profile header (`AccountScreen:234–237`); `AccountViewModel:150` assigns result.isStale | Fresh success and auth transitions clear (`127,150`); no OR | Failed header read discards header/stale bit (`151–153`); only NotFound supplies profile-unavailable, otherwise identity remains from auth state |

**no fault in the intentionally sticky author tab flag:** iOS's model ORs stale tab results too (`I/Services/AO3AuthorProfileService.swift:710,752,794,815`) and resets via the dashboard; 3ce explicitly records that a fresh tab alone need not clear the banner. Series replacement versus iOS appended pages is also recorded. F11 covers the additional failure behavior. A refusal/parser failure is not permission to substitute stale HTML; the shared cache correctly removes that key. The Inbox plain-URL versus filter-form-URL first-refresh cache miss is already recorded in 3ce's later emulator note; it remains a distinct-address miss, not evidence that every failed refresh ignores a saved copy.

### 11. Inbox invalidation, single and bulk actions

**no fault:** Mark Read, Mark Unread and Delete, for a row or a selection, all reach `AO3InboxRepository.performBulkAction`. On confirmed success it removes **every query/page/filter variant** with the account Inbox path in the captured viewer/generation (`A/network/ao3/inbox/AO3InboxRepository.kt:90–97`; `AO3PageCache.kt:46–48`), plus the exact differing form-action URL key. It does not remove another account/session's pages. The view model re-reads with bypass (`AccountInboxViewModel.kt:355–362`). No successfully invalidated Inbox variant survives merely because it was page 2/unread-only/read-only. Unconfirmed/refused writes retain the entries, as the brief says; that is not proof AO3 did nothing. F3 covers an older coalesced GET re-entering after removal, and F4 the overly broad cancellation fence. iOS removes the same Inbox path variants; the note records the intended removals, though Claude had not read them line by line.

### 12. App-wide writes versus this cache

The repository call-site search covers every production caller of the cached author/dashboard/About/Works/Series/Bookmarks/Stats/detail methods, plus Inbox load. `AO3PageCache` does not intercept arbitrary HTTP addresses: the repository must call `read`. Same hostname or even overlapping source HTML is not enough to make another repository cache-backed.

| Write / following read | Can AO3PageCache return the pre-write page? | Verdict and source |
|---|---|---|
| Own bulk edit, row work/tag edit, row chapter changes, own single/bulk delete → header/Works/Stats | **Yes:** old variants survive; bypass still permits stale fallback; F1/F3 | Immediate success reloads have bypass (`AuthorProfileScreen:350–352,376–395`), but no writer-page removal |
| Work/draft creation/posting through Writing destination → return to account/profile later | **Yes** on subsequent cached author read; no general profile-change notification | `AppNavHost:654–660` only updates Drafts' saved-state revision. Forms/publication re-reads themselves use `AO3WorkFormRepository` directly and are not cache hits |
| Series save/reorder/remove → series detail or author's Series list | Show-page entries removed on confirmed success; **author list variants still yes**, and F3 can rejoin old GET | `WritingSeriesState:36–39,119–127,146`; opener bypasses at `SeriesWorksScreen:119` / `AuthorProfileScreen:405`. F2 |
| Native author Subscribe/Unsubscribe → author's dashboard | **no fault in ordinary memory invalidation:** target account/pseud dashboards removed in captured scope, then bypass | `AuthorProfileScreen:280–285`. Current iOS equivalent invalidates dashboards and bypasses (`AO3AuthorProfileService:426`). 3ce's old “web handoff only” statement is now obsolete; this is a later native port, not its landing behavior |
| Native Block/Mute and served undo forms → author's dashboard | **no fault in ordinary memory invalidation:** same target-dashboard removal + bypass | `AuthorProfileScreen:328–333`; form preparation is direct authenticated GET. Same caveats F3/F4 |
| Inbox row/bulk read/unread/delete → Inbox | **no fault in matching variant removal**, see §11; transport race F3 remains | Repository invalidates then view model bypasses |
| Top-level comment/reply/edit/delete → comments page/thread | **No through this cache.** Separate comment offline store can supply a stale copy after transport failure | `CommentsViewModel:712–724,738,802`; pinned `network/ao3/comments/AO3CommentRepository:44–77` directly GETs first and only consults its own cache on network failure. Comment-thread URLs never enter AO3PageCache. No five-minute fresh hit from 3ce |
| Approve/reject/remove a collection item; user collection-item changes → item list; membership/reveal/moderation changes → collection panels | **No through this cache** | `AO3CollectionItemsState:106–118` re-reads even partial failure; `AO3CollectionDetailRepository:309–313` direct client GET. Collection lists/profiles/forms are not cached author profiles |
| Unsubscribe from the subscriptions index (work/creator/series) → subscription list | **No through this cache** | `SubscriptionUnsubscribeState:27–28`; `AccountListRepository:32–42,71–87` direct GET; named-loader removal at `AccountWorksListScreen:1349–1351`. A previously cached author's Subscribe button is a separate view and is not invalidated by this index operation; reopening it can show the old form until refresh/expiry. The index read itself is not stale due to 3ce |
| Withdraw sign-up; sign-up save/default; assignments claim/default; challenge-settings write; prompt claim/release; tag-set/nomination writes → respective sign-up/assignment/settings/request/tag-set pages | **No through this cache** | `AO3ChallengeSignUpState:111–117`; `AO3ChallengeAssignmentsState:169–184`; all use the collection-detail/direct authenticated paths, not cached author/Inbox/series-detail methods |
| Work edited → edit/publication form, or work metadata page | **No through this cache** | `AO3WorkFormRepository:127` direct authenticated GET; local/public work detail uses the work metadata path. The affected *author/series listing* may still be stale (F1), which is a different consumer |
| Work kudos / work Subscribe / Mark for Later / create Bookmark; reading-history deletion/clear; collection create/edit/delete/invite/leave | No subsequent target-page read via AO3PageCache at these action sites | Write/action-state and account-list repositories use their direct paths (`AO3WriteRepository:970–1072,1143–1263`; `AccountListRepository:42,87,140`). They do not acquire 3ce's fresh memory answers. Cached author bookmark/recent-work aggregates are not automatically invalidated by these unrelated operations |

No unlisted production cached-method caller was found: the additional ones are AccountSeriesViewModel (ordinary list load) and the Favorites newest-work store (`KudosAppContainer:171`), not post-write readbacks. The important current faults are the writer-page removal omissions and the transport race, not hypothetical caching of every AO3 GET. iOS's newer writer/series invalidations differ as F1/F2 describe. The landing note records the narrower immediate bypass fix, not that app-wide policy.

### 13. Two readers, freshness, and session movement

**no fault in failure freshness marking:** the cache itself does not combine requests, but the shared production OkHttp client coalesces overlapping same-address/same-header GETs (`AO3Client:97–113`; `AO3RequestCoalescer:42–57`), so Home and a pushed screen normally share one in-flight operation (which may perform the configured GET retries). Different client instances or header sets can make two operations. Each cache consumer parses independently. Fallback explicitly calls `parsed(copy, true)` (`AO3PageCache:90–94`); it neither inserts the fallback as a fresh entry nor extends its lifetime. One reader's transport failure cannot itself give the other a stale page marked fresh. An earlier successful fresh-memory entry is correctly fresh until its deadline unless invalidated; F1/F3 explain how that can nevertheless be pre-write data.

**no fault in session retention:** keys include address, page kind, viewer and generation (`AO3PageCache:16–18,75–79,135`). The real auth repository clears the singleton on every generation advance (`AO3AuthRepository:363–367`). A suspended read checks scope/revision after fetch and parsing and again while inserting; it cannot retain the answer once its session has moved on. Cancellation does not trigger stale fallback. iOS's ordinary author keys have weaker same-username reuse semantics; Android's physical clear/generation on all keys is an intentional stricter difference recorded in 3ce. F4 concerns unrelated-key cancellation within the same session, not cross-session leakage.

### 14. Default-cache test inventory

Searched all Android source sets for constructions of the three cache-backed repositories, then read which entry points the tests call. A default constructor alone is not proof of order dependence: the `seriesPage`/`seriesWorks` paths bypass this cache entirely, and several suites already clear it before each test.

| Test file / construction | Actual exposure at 651d2ead |
|---|---|
| `T/author/AuthorProfileSortScreenTest.kt:57` (all tests using `show`) | Default author cache; explicitly cleared by `@Before` at line 35. No sequential cross-test fresh-hit fault established |
| `T/account/Brief3caScreenTest.kt:102` (`authorRepo`, author/dashboard/profile cases) | Default author cache; explicit clear at 57, plus real fake-session restore in setup. No sequential order fault established |
| `T/network/ao3/author/AuthorWorksSortTest.kt:23,78` (`everySortDirectionAndCompletionMatchesSwiftQueryAndMakesOnePageRead`, `authenticatedRefusalIsNotRetriedAnonymouslyAndSignedOutReadsOnlyPublic`) | Default author cache; explicit clear at 12. These clients produce failures rather than seed success entries; protected against earlier-suite seeds by the clear |
| `T/author/OwnWorksScreenTest.kt:61` (all tests calling `show`, including saved-bulk/row reload tests and theme wrapping test) | Default author cache, no explicit suite clear. **Implicit clear is real:** `show:46` calls `workFormSetup`; `WritingWorkFormStateTest.kt:238–240` constructs auth and calls restore; `AO3AuthRepository:94–96,363–367` clears shared cache even for signed-out restore. Do not falsely report this suite as an existing sequential-order flake. Injecting its own cache would make isolation clearer |
| `T/network/ao3/series/AO3SeriesRepositoryTest.kt:144`, `signedInDetailUsesOneAuthenticatedReadWithoutAnonymousFallback` | Still a default-cache detail reader, but the enclosing `AO3SeriesRepositoryParseTest` clears at line 13. Its fake viewer scope is `AO3_Reader/null`; no sequential predecessor can seed it past that clear |
| Same file lines 21,48,65,72 (`parsesSeriesPageBlurbsWithFixture`, `seriesWorksPaginatesAcrossPages`, `invalidSeriesUrlFailsValidation`, `surfacesNetworkErrorsWithoutParsing`) | Default object but only uncached seriesPage/seriesWorks or URL validation. No cache-order exposure |
| `T/library/ReadingQueueRepositorySeriesTest.kt:215,232,246` (`completePreviewIsReusedWithoutASecondSeriesRead`, `multiPagePreviewDoesNotReadAheadAndExplicitChoiceCrawlsInOrder`, `failedSizeReadIsOneAttemptAndNoAutomaticCrawlOrDownload`) | Default series cache object, but preview/preservation use uncached seriesPage/seriesWorks. No cache-order exposure |
| `T/works/DownloadQueueTest.kt:284,311` (`enqueueSeriesFetchesWorksAndDownloadsEach`, plus default helper) | Default series repository; queue uses uncached seriesWorks. No cache-order exposure |
| `T/works/WorkDetailSaveForLaterTest.kt:96` (the seven scenarios using `open`) | Default series repository for size preview/preservation, uncached seriesPage/seriesWorks. No cache-order exposure |
| `T/works/WorkDetailShareTest.kt:68`, `linklessImportStillHasNeitherShareNorOriginalViewerOnTheActualWorkPage` | Default series repository is supplied to work detail, not used for a cached detail read. No cache-order exposure |

The repaired same-test series factories at `AO3SeriesRepositoryTest.kt:88–89,116` use new caches. `OwnStatsTest`, `InboxFailedPageTest`, `CachedAO3PagesRepositoryTest` and `CachedAO3PagesScreenTest` also inject private caches. No other direct default Inbox construction was found in tests. `CachedAO3SessionTest` and `WritingSeriesTest` intentionally operate on the singleton to test clearing/removal; they are not accidental default-repository cache consumers.

**no fault proven for current sequential test order:** all active default-cache readers found either clear before reading (explicitly or through restore) or use uncached methods. They still share process-global state by construction, so new tests should inject a private cache, as the note says. Parallel tests/global clears could interfere with in-flight reads (F4); this audit did not run a parallel suite or claim such a failure occurred. An inventory of default constructors without these qualifications would overstate what is wrong.

## Limits and verdict

All 14 requested areas were traced statically. No runtime/UI pass is claimed, and the narrow custom-trailing-value layout boundary remains unrendered. Fix the confirmed wrong-write path F5 and the cache/readback faults F1–F4 before treating these screens as audited. The request field parity, role gating, assignment serialization, delete target snapshot, uniform-field omission, and ordinary Inbox cache removals are supported by code; they should not be rewritten merely because the original landing review was incomplete.
