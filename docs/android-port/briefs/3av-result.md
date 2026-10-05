# Brief 3av — Your items and collection row actions

**Landing note (Claude, 2026-10-05).** Landed as written; it compiled and passed first time.
Gate green (1,571 tests). The write was read against iOS's `updateUserCollectionItems` and
`draftAO3WillStore` line by line and against `docs/AO3_NETWORKING_POLICY.md`: one read of the
account's default page for a fresh token and the form's address, then one POST per staged item
in order, never in parallel, never retried, the first refusal stopping the rest; only fields
the served page lets the reader change are sent. **Never run against AO3.**

Seen on the emulator in airplane mode against the demo's local answers: "Your items" opens on
Awaiting you with items from two collections, the moderators' side shown as facts; one approval
submitted and accepted; three staged with the first accepted, the second refused ("AO3 couldn't
update that collection item.") and the third left staged and unsent; a long press on a
collection's row offers Edit Collection and Manage Items, and both open. Checked later the
same day: the other three tabs (Awaiting collection, Rejected, Approved), each with its own
item and count; and the screen in Dark. Not checked: large text.

As on iOS, the two row actions are offered on every collection, including ones the reader
cannot edit; AO3's answer decides. (In the demo, editing a collection other than Winter
Exchange 2026 opens an older fixture's form under another name.)

## iOS differences between account and collection items

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Account/AO3CollectionsList.swift`, `AO3CollectionItemsView.swift`, `AO3CollectionItemStaging.swift`, `AO3CollectionScreenDecisions.swift`, `Models/AO3CollectionDetailModels.swift`, `Services/AO3Client+Collections.swift`, and `Services/AO3CollectionActions.swift`.

| Concern | One collection | Your items (account scope) |
|---|---|---|
| Destination | Non-nil collection slug and title | `slug: nil`, title “Your items”; same screen |
| Read | `/collections/{slug}/items` | `/users/{login}/collection_items` |
| Default / Reset | Awaiting collection; omits status | Awaiting you; omits status |
| Awaiting collection query | Omitted | `status=unreviewed_by_collection` |
| Awaiting you query | `status=unreviewed_by_user` | Omitted |
| Other tabs | Rejected → rejected_by_collection; Approved → approved | Same; no rejected_by_user tab on screen |
| Subtitle scope | Collection title | “Your works in AO3 collections” |
| Card collection | Rows ordinarily name that collection | Each row names its own collection; its card retains that collection's hue |
| Editable controls | Served HTML determines editability | Same parser/rules; creator approval/removal may be enabled, moderator approval/Unrevealed/Anonymous are facts when served disabled. No role-based override is invented. |
| Submit form read | Collection default page 1 | Account default Awaiting-you page 1 |
| Fallback action | `/collections/{slug}/items/update_multiple` | `/users/{login}/collection_items/update_multiple`; parsed action wins, patch is method fallback |
| Submit action | updateCollectionItems | updateUserCollectionItems |

Both use identical local staging, toolbar count, Submit, Discard, Remove/Keep, paging, empty/error/signed-out states and session isolation. Only current-page drafts that differ and are editable count/submit. Off-page drafts survive. Disabled controls are excluded. Removal replaces other edits. Account AO3 stores user_approval_status/remove and strips maintainer fields; iOS uses served disabled controls to filter those fields before its action encodes the draft. Missing controls keep iOS's existing absent-control editability rule.

**One POST per staged item**, not one combined POST: `pendingDrafts` sorts by item ID; `updateUserCollectionItems` reads one fresh CSRF page then sends drafts sequentially, in that order, each paced/coordinator-limited, stopping on the first refusal/failure. Session generation is captured for the batch and checked after the read and before subsequent items; Android's shared dispatch fence also checks after pacing. No write retry/coalescing. The misleading combined-POST view comments lose to the actual action code: **iOS code wins**.

`collectionWriteVerdict`: error flash first; success flash or bare 3xx confirms; other non-2xx uses “AO3 couldn't update that collection item.”; plain 2xx is “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.” Successful iOS submission clears sent drafts and rereads current page; failure retains drafts without a reread.

The 3as landing note records existing Android confirmation and refresh-after-failure deviations as Claude's decisions, not owner approvals. This brief explicitly keeps the Android question “Submit N staged change(s) to AO3?” in account scope. Reusing the current shared screen also retains its verification read after partial failure; this is existing Android behavior, not an iOS scope difference. No other owner approval is inferred. 3at's landed form is reused unchanged, including its corrected toolbar, refusal deduplication and text alignment.

## iOS collection-list row actions and conditions

`AO3CollectionsList.collectionRow` attaches a context menu to **every rendered collection row**, with “Edit Collection” (pencil) and “Manage Items” (tray.full). It also attaches a trailing swipe “Edit” with full swipe disabled. `editDestination(for:)` passes that row's name as the form slug. `itemsDestination(for:)` passes name and display title to the existing collection items screen. Neither helper nor menu/swipe condition checks viewerIsOwner, viewerIsMember, challenge kind, or collection flags. AO3's fetched pages govern permission. Android uses its existing long-press DropdownMenu idiom, with these two context-menu words/destinations and no owner-only restriction or swipe imitation.

## Networking policy

`docs/AO3_NETWORKING_POLICY.md` permits explicitly opened own-account lists and collection pages under “No background or bulk scraping”. Reads remain visible/on-demand, cancellable, with no page walks, prefetch or polling. Shared User-Agent/contact, host allow-list, pacing, concurrency cap, GET coalescing and transient-only GET retries apply. Writes follow “Writes”, “Batch behavior”, “Cancellation” and “What agents must NOT implement”: authenticated explicit-cookie, fresh CSRF, generation checks before preparation and at dispatch after pacing, sequential single-shot POSTs, no retries/coalescing, cancellation between items. Neither requested action is forbidden. No local works, backup format or Room schema is involved.

## Work log

Started with a clean tree on `android/agent-gemini-3av`; read the 3at/3as landing notes and current source, including the shared items state/parser/write repository, collection card, routes, local Collections long-press menu, and DemoNetwork interceptor. The latest on-disk history already contains the landed 3at form and palette change; no earlier uncommitted form code is being reapplied. No commits, pushes, branch switches, TASKS.md edits, sign-in, AO3 requests, Gradle/Xcode execution, helper scripts or .orig files.

## Implementation

- `AO3CollectionItemsScreen` / `AO3CollectionItemsState` accept nullable slug. The new account route supplies nil and “Your items”; the Collections chip opens it. Account defaults and Reset select Awaiting you. The same cards, creator/maintainer permission facts, confirmation, staging and session-bound lifecycle serve both scopes.
- `AO3CollectionItemsUrls` builds the account read/update addresses and scope-specific queries. `AO3CollectionDetailRepository.getUserCollectionItems` uses its existing authenticated, generation-fenced read. `parseUser` shares the actual items parser, with account base URL and trusted fallback action. Blank collection-link titles now fall back to that link's slug, as iOS does (especially relevant when the account's fallback slug is empty).
- `AO3WriteRepository.updateUserCollectionItems` checks generation at entry and after the one fresh default-page read; uses the fresh **meta** token, parsed action/method or iOS's account fallback; then shares the existing ordered, single-shot dispatch loop. Each item gets only its filtered changes (or removal), authenticity_token and _method. The batch stops on first refusal, transport failure or unconfirmed reply. The displayed form's old token/action are not used for the write.
- Every collection card opens “Edit Collection” / “Manage Items” on long press. The same row slug/title drive existing destinations. Normal tap still opens collection detail. The existing card and DropdownMenu components are reused; the new menu explicitly uses token fill/ink, subject accent icons and text line height. No new screen, chip style, card style or role heuristic.
- `DemoNetwork` owns a separate account-items state alongside collection-items state. All matching account GETs/POSTs, including missing-fixture failures, terminate in the local interceptor. The original-fiction fixture spans Winter Exchange 2026 and Summer Prompt Meme; creator approval/removal are enabled where served, while maintainer/Unrevealed/Anonymous controls are disabled. One fully locked item exercises read-only display. No production persistence changes.

## Demo navigation and expected local answers

After Claude builds/installs the Android debug app, launch its existing **local demo account** (these commands are instructions, not executed here):

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true
```

Open Account → Collections → **Your items**. Awaiting you opens by default. Page 1 has “The Lantern Keeper” (61, Winter Exchange), “A Window Full of Stars” (62, Summer Prompt Meme), and “The Quiet Ferry” (63, Winter Exchange). Page 2 has the locked “The Locked Attic” (67). Awaiting collection shows “Letters to the Rain” (66), Rejected shows “The Paper Bridge” (65), and Approved initially shows “A Pocket of Daylight” (64). Reset returns to Awaiting you.

For a successful batch, approve only “The Lantern Keeper”, tap Submit, then confirm Submit. Its one POST succeeds; it leaves Awaiting you and appears under Approved. Removal of “The Quiet Ferry” also succeeds locally.

For the stop-on-refusal scenario, restart the app to reset local server state. Stage Approved on all three page-1 items, in any order; Submit then confirm. Requests are **61 then 62**, with no POST for 63. 61 succeeds; 62 returns “AO3 couldn't update that collection item.” The shared Android verification read removes 61 from this default list; the entries for 62 and 63 remain staged. A later Submit is a new explicit user action, never an automatic retry. Cancel at the confirmation sends nothing; Discard clears all staged tabs/pages without a request.

On the Collections list, long-press Winter Exchange 2026 → **Edit Collection** opens the landed edit form; **Manage Items** opens the existing collection-scope items screen. The same two actions appear on every row, including rows where the reader is neither owner nor member. Normal tap still opens collection detail. Account and collection demo mutations are independent. A process restart resets both.

## Offline tests added (not run)

| Suite | Cases | Coverage |
|---|---:|---|
| `AO3UserCollectionItemsTest` | 13 | Account URLs/queries/defaults/route chrome; fixture parsing, link-title fallback and disabled permissions; creator-only body/removal; fresh meta token/action/method and iOS parse fallback; sorted sequential requests with no item after refusal; busy duplicate confirmation; success/failure staging and current-page refresh; off-page drafts/Discard; signed-out and stale read/write/session fences; all row-action conditions |
| `AO3CollectionRowMenuTest` | 1 | Real themed card long press exposes both actions for a non-owner/non-member; taps return existing routes; normal tap opens detail |
| `DemoUserCollectionItemsTest` | 2 | Real demo interceptor answers account filters/paging and accepts/refuses creator decisions; rejects wrong tokens and disabled controls; mutation persists locally; missing fixture GET/POST cannot fall through |

State/write tests use memory-only clients. Interceptor tests install a downstream interceptor that throws before any socket request. The menu test has no repository/client. All fixtures are original filler.

## Verification and handoff

Performed here: read the real referenced Kotlin/Swift symbols and callers; checked the fixture's structure with Python's standard-library HTML parser (seven unique items, two distinct collection links, 14 approval selects, 21 checkboxes, six enabled creator selects/removals, one refusal, matching meta token); `git diff --check` passes. No Gradle, Xcode, emulator, test suite, sign-in or AO3 traffic was run. **Compilation, test passing and visual correctness are not claimed.**

Claude must build Android debug and run `:app:testDebugUnitTest`, including the three added suites and existing collection items, write dispatch, demo block, navigation and large-text coverage. Request ordering/stop-on-refusal, duplicate prevention, session isolation, token/form bodies and menu interaction are supported by added tests but require that run. The existing collection dispatch loop was extracted without changing its behavior; its regression tests still need execution.

Claude must exercise the demo routes and confirmation Cancel/Submit, all four tabs/paging/Reset, permissions and partial failure, the list's long-press and ordinary tap, and Light/Dark/Sepia/OLED plus accessibility font scale. Screenshot review is still required; no visual verification occurred here. Live endpoint compatibility remains unexercised (as on iOS); this handoff does not authorize live AO3 calls.

Both requested features are implemented. The landed form, Manage → Moderation routing (3aw), TASKS.md, iOS tree, backup format and Room schema are untouched. Changes remain uncommitted for Claude's build/test/review/commit pass.
