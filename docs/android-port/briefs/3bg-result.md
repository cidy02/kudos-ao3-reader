# Brief 3bg — Add tags and Reject

## iOS writes, read again before implementation

Read line by line from the read-only `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`: `Features/Challenges/TagSetView.swift` (tag count navigation, editor, save/reject controls, loader and actions), `Services/AO3ChallengeActions.swift` (`saveTagSetFields`, `reportRejectedTag`, verdict wrapper), `Services/AO3Client+Challenges.swift` (parser, parameters), `Services/AO3WriteActions.swift` (CSRF, headers, encoder, dispatch), `Services/AO3CollectionActions.swift` (verdict), and `AO3AuthService.authenticatedRequest`.

**Visibility/taps:** iOS has no ownership, moderator, sign-in, visibility or nominations-open gate on either control. Moderator changes only the header kicker. Each of Fandoms, Characters, Relationships and Additional tags pushes the same Add tags editor without a read or write. Each unreviewed nomination offers Reject immediately, without a confirmation dialog. Approved/Rejected have badges. Opening/refresh retains 3be's reads; neither triggers a write. A refused edit read (44) silently retains the public model, including its empty field values/missing action, and still exposes Add tags. Save subsequently attempts its fresh token read; a refused read surfaces that failure, before checking the missing action.

**Editor:** header kicker `Tag set`, title `Add tags`, subtitle effective title. Fields start with the loaded model's strings (edit-form model when that optional read succeeds; otherwise public values). Labels/placeholders in order:

| Label | Placeholder |
| --- | --- |
| Fandom tags to add | Comma-separated fandom names… |
| Character tags to add | Comma-separated character names… |
| Relationship tags to add | Comma-separated relationships… |
| Additional tags to add | Comma-separated additional tags… |

Footnote, verbatim: `Enter each tag type as its own comma-separated list, as on AO3. If AO3 rejects a tag, Kudos shows which list it came from.` Primary action `Save tags`. Saving clears old error/notice, shows a spinner and disables Save; fields remain editable on iOS. Success says `Tags saved.` and preserves the typed fields; it does not change tag counts, clear fields, dismiss, or fetch another page. Refusal shows the reason directly and preserves input. Returning/reopening the editor keeps the same screen-owned draft.

**Save sequence:** require sign-in (`Log in to AO3 first.`), authenticated GET `/tag_sets/{id}/edit`, parse fresh **meta** csrf-token (not input), then check the **loaded model's** action (`Couldn't find AO3's tag-set form.` if absent). POST that captured resolved action, with `authenticity_token={fresh meta token}`, `_method={loaded model override}` only when nonempty, then all four `owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]`, `[character_tagnames_to_add]`, `[relationship_tagnames_to_add]`, `[freeform_tagnames_to_add]` with the respective current strings, verbatim including whitespace and empty strings. No visibility, limits, nominated flag, commit field or title is sent. The fresh form supplies only the token, never replacement action/method/input.

**Reject sequence:** require sign-in, authenticated GET `/tag_sets/{id}/nominations`, fresh meta csrf-token, POST that same nominations address with `_method=put`, `authenticity_token={fresh meta token}`, `{field wire name}_reject_{tag name}=1`. Wire names: fandom/character/relationship/freeform. Replace literal `[` with `#LBRACKET`, `]` with `#RBRACKET` **before** form encoding; no tag trimming or other name transformation. All Reject controls disable while one is in flight; its control shows a spinner and retains `Reject`. On confirmed success mark only that row Rejected and derive Awaiting review/Approved/Rejected counts from the updated queue, with no GET. On failure retain queue/counts and show `Couldn't reject “{tag name}”: {reason}`; no success notice.

**Headers/transport:** authenticated explicit Cookie and shared identifiable User-Agent; POST `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`, `X-CSRF-Token: {fresh token}`, `Referer: {token page URL}`. `ajax: false`: no X-Requested-With or AJAX Accept header. iOS percent-encodes each key/value allowing alphanumerics and `-._~`. Android uses the existing form-post encoder/client. Prepared-session fence, pacing, trusted-host and redirect-cookie rules stay in the shared path. At most one POST per explicit tap; never retry/coalesce a POST or automatically retry a refused write. Preparation GETs retain shared read policy; no extra screen retry loop or post-success read.

**Verdict — exact iOS code** (`AO3CollectionActions.collectionWriteVerdict`, called by the challenge wrapper):

```swift
if let error = AO3Client.writeErrorMessage(in: body) {
    return .rejected(error)
}
if AO3Client.writeSuccessMessage(in: body) != nil { return nil }
if (300...399).contains(status) { return nil }
guard (200...299).contains(status) else {
    return .rejected(fallback)
}
return .unconfirmed
```

AO3 error text wins even over a success flash/redirect. A success flash or bare 3xx confirms; a plain 2xx is unconfirmed: `AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.` Other status fallback: Save `AO3 couldn't save that tag set.`, Reject `AO3 couldn't reject that tag.` Missing meta token actually throws **AO3WriteError.noCSRFToken**, `Couldn't prepare the request. Try again, or open the work on AO3.` The challenge enum's unused `challenge` wording does not win. Reject prefixes each reason as above. Token-read HTTP/transport failures use the existing scoped iOS error mapping (403: `AO3 refused the request (HTTP 403). Wait a while before trying again.`); no POST follows failed preparation.

## Policy accounting

Both explicit Save and Reject are permitted by **Writes** in `docs/AO3_NETWORKING_POLICY.md`: authenticated CSRF page, single-shot/non-coalesced POST, preparing-session dispatch fence. Their one foreground preparation GET is also within explicit navigation to the selected tag set; no bulk/private sweep. Existing pacing/concurrency, host allow-list, shared UA, cancellation and Retry policy remain. **429** is surfaced without write retry; **403** is never retried. Neither write touches reader-stored works or makes a background request.

## Work log

Clean tree on `android/agent-gemini-3bg`. Read 3be including its landing correction (count rows intentionally inert), 3an/3aw/3ay including landing/integration notes, 3at form components, mandatory project docs and actual Swift/Kotlin APIs. This brief overrides task claiming, commit/push/branch/build requirements. Implementation and offline tests are written; Claude’s compilation, test run and visual review remain. No builds or AO3 contact.

## Decided without asking

- Keep remote action/method and request parameter helpers in the existing `network/ao3/account/AO3TagSet.kt`; writes in the existing `AO3WriteRepository`, drafts/write state in `AO3TagSetState`, editor in its existing screen. No Room or backup change.
- Reuse `SubjectTextFieldRow(multiline = true)` and the collection form's `SettingsActionRow` primary action; use screen-local editor navigation with both system Back and the shell's Material Back button. No extra top actions (iOS defines none).
- Use existing fictional `Letters [Winter]` as an accepted Reject (exercises brackets) and `Paper Harbor` as a refused Reject. Use fictional `Uncharted Lantern` in any Save list as the local refusal trigger; the answer names that list.
- Demo mutation belongs to the existing interceptor's process lifetime and resets on relaunch. Browser fixture-only behavior remains terminal/local.

## Open questions

None.

## Implementation written

- `network/ao3/account/AO3TagSet.kt`: keeps the served/resolved action and trimmed optional method override in the transient snapshot; encodes only the four tag strings and fresh token, including empties; Reject replaces brackets before passing its field to the shared encoder. No persisted model, schema or backup change.
- `network/ao3/writes/AO3WriteRepository.kt`: two new methods, using the same `DefaultAO3AuthenticatedClient`, fresh meta-only token parsing, `writeHeaders`, `postAuthenticatedInSession`, `NonCancellable` sent POST and `collectionWriteVerdict` as 3aw/3ay. Existing write methods and verdict helpers are unchanged. Entry/read/response generation checks plus the existing dispatch fence prevent stale preparation or publication. Signed-out and missing-token words follow the actual iOS action being called, including `work` rather than 3ay's landed Android `collection` wording.
- `account/AO3TagSetState.kt`: screen-owned draft, independent Save/Reject busy/error state as on iOS; no optimistic count or row mutation. Save snapshots the request's strings but leaves fields editable, preserving later typing through either verdict. Confirmed Reject changes the first matching queue entry as iOS does. Preparation remains cancellable; a sent POST finishes once and an exited/replaced screen never receives it. Refresh cannot replace a draft/queue while either write is busy; otherwise its existing reads/reset operate. No automatic refresh after either success.
- `account/AO3TagSetScreen.kt`: all four count rows open one local Add tags screen, with exact labels/placeholders/footnote and keyboard inset padding; existing collection `SubjectTextFieldRow(multiline = true)` and `SettingsActionRow`. Save feedback/spinner, Reject chips with accessible nomination names and selected spinner, token-derived destructive color, all Reject controls disabled while one runs. Both Android system Back and the shell's existing Material icon Back return to the tag-set screen locally; no extra top action. Every newly authored Text specifies line height. Shared typography/components remain untouched, including the shared header's existing subtitle typography, following 3aw's landing note. Long queues now use one lazy item per nomination while reconstructing continuous fandom panels with the existing panel glass/radius tokens; accessibility rows stack as before.
- `app/AppNavHost.kt`: supplies the existing container `writeRepository`; no extra route or client.
- `network/ao3/DemoNetwork.kt`: the interceptor owns one `DemoTagSetWrites` answer. Only **POST `/tag_sets/42`** and **POST `/tag_sets/42/nominations`** replace the old 405; all other tag-set write addresses/methods retain the local refusal. Missing assets fail locally. Accepted additions update later native GET counts; accepted Reject changes later native nominations. Browser interception is unchanged: bundled read-only snapshots or a terminal local failure, never network. The new handler never calls `proceed`. New interceptor/process resets all mutations.

## Remaining error words, verbatim

Save shows the applicable reason directly; Reject wraps it in `Couldn't reject “{tag name}”: {reason}`. Server-provided reasons remain AO3's exact text (deduplicated by the existing parser). Besides the action/verdict strings recorded above, the existing scoped `moderationMessage` preserves these iOS words for typed preparation/transport failures:

| Failure | Reason |
| --- | --- |
| 403 | AO3 refused the request (HTTP 403). Wait a while before trying again. |
| 404 | That work or page couldn't be found (it may be restricted). |
| Expired session | Your AO3 session expired. Please log in again. |
| 400 | AO3 returned an unexpected response (HTTP 400). |
| 429 | AO3 is rate-limiting requests. Wait a moment and try again. |
| 5xx | AO3 had a server problem (HTTP {status}). Try again shortly. |
| Other typed HTTP failure | AO3 returned an unexpected response (HTTP {status}). |
| Parse | AO3's page format wasn't what the app expected. |
| Offline | You're offline. Connect to the internet and try again. |
| Timeout | AO3 took too long to answer. Try again. |
| TLS | Couldn't make a secure connection to AO3. |
| Other transport | Couldn't reach AO3. Check your connection and try again. |
| Existing Android overload state | AO3 is busy. Try again shortly. |

No new confirmation dialog, success sentence for Reject, refusal dialog title, retry button, ownership restriction, or sign-in button is invented. iOS code wins over an owner-only interpretation of the editor and over the unused challenge enum's missing-token sentence. There is no further brief/iOS conflict needing an answer.

## Further decisions without asking

- Change only 42's edit fixture to four empty served lists, matching AO3's normal Add tags form. Keep 43's existing nonempty fields to exercise actual served prefills; 44 retains the refused edit/public empty fallback. Add a synthetic nominations meta token to 42's existing fixture. No new asset files.
- Put write/state/transport tests together in `account/AO3TagSetWritesTest.kt` alongside the existing read and screen suites; extend existing `DemoTagSetTest` rather than add a second demo fixture/state or test helper file. Recording client support stays in the existing tag-set test file.
- Keep busy Save fields editable, preserve notices/drafts through editor Back/reopening, and keep Save and Reject separate in-flight states, following iOS. An explicit refresh resets draft values from the served form, not from a locally guessed tag list.

## Demo routes and taps (for Claude, not executed here)

Use the existing fixture-only demo extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true` in airplane mode. These create local state, not an AO3 sign-in. Never use the login screen. Relaunch/force-stop resets all answers.

- **42:** Account → Collections → Winter Exchange 2026 → Manage → Challenge Settings → Winter Exchange Tags. Direct debug route: `nav:ao3-tag-set/42?title=Winter%20Exchange%20Tags` (avoid shell truncation of `&`, as 3be's landing note warns). Any Tags row → **Add tags**. Type `New Lantern Harbor` in Fandom tags to add → **Save tags** → **Tags saved.** Fields stay typed; Back still shows 7 tags. Only an explicit refresh shows the local server's increased count and empty Add tags inputs. Empty-list Save also succeeds.
- **Save refusal:** enter `Uncharted Lantern` in any one list (alone or comma-separated), Save once. Exact local reason: `{that field's editor label}: Uncharted Lantern could not be added.` Typed values stay, no Tags saved notice. Remove that name and tap Save explicitly to make a different write; there is no automatic retry.
- **Reject success:** on 42's Review queue, tap **Reject** for **Letters [Winter]**. No confirmation dialog; on success that row says **Rejected**, counts change from Awaiting review/Approved/Rejected **3/1/1** to **2/1/2**. No post-success GET. Refresh/revisit preserves the interceptor's decision; restart resets it.
- **Reject refusal:** tap **Reject** for **Paper Harbor**. Exact screen feedback: `Couldn't reject “Paper Harbor”: Paper Harbor is locked for this review.` Row and counts stay. Other unsupported nominations receive the terminal local reason `That nomination was not accepted.`
- **44:** Summer Prompt Meme → Manage → Challenge Settings → Summer Prompt Tags; direct `nav:ao3-tag-set/44?title=Summer%20Prompt%20Tags`. Edit opening refuses silently, all Tags rows still open Add tags with empty fields. Type anything and Save: one fresh refused edit GET, zero POSTs, retained input and `AO3 refused the request (HTTP 403). Wait a while before trying again.`
- **Signed out:** direct 42 route without the signed-in extra. One public opening read; editor and Reject remain visible, each tap shows its iOS `Log in to AO3 first.` reason without another request.

## Offline tests written, not run

**26 added test methods:** 17 in the new `AO3TagSetWritesTest`, six added to `AO3TagSetScreenTest`, three added to `DemoTagSetTest`. Existing read/parser/screen tests were updated for the editor and 42's empty fields. This is a source count, not passing tests.

Coverage includes:

- Captured action/method versus different freshly served ones; meta rather than input token; every Save field including all empties/whitespace; every Reject wire type and bracket/ampersand name; exact request order, headers and encoded bytes. One logical token GET and at most one POST per tap, no verification GET or duplicate POST.
- Success flash/redirect, AO3 refusal priority even over a success flash/redirect, unconfirmed 200/204, fallback refusal, missing meta, failed token read, signed out, transport/rate-limit failure. Exact words and retained draft/queue/counts.
- Held Save/Reject results: screen unchanged before confirmation, Save notice only after confirmation, only the nominated row/counts changed after Reject, duplicates suppressed, every other Reject disabled. Served prefills and explicit refresh reset without writes. Session transitions during token reads/POSTs and disposal suppress late publication.
- Real `OkHttpAO3Client` with **terminal application interceptors**: shared User-Agent/Cookie/CSRF/Referer/body media type, exact percent-encoded payloads, 429/503 POSTs never retried, session change during the real shared pacing wait prevents both write dispatches. These interceptors cannot open sockets.
- Actual screen taps for all four entry rows, shell Back, held write success, refusal/input retention, 44 edit refusal and signed-out actions. Light/Dark/Sepia/OLED at 2× font scale assert wrapping/no text layout overflow in long nomination text, all four editor placeholders and Save. Tall `w411dp-h2000dp` window, 15-second waits, `@GraphicsMode(NATIVE)`, `parseDispatcher = Dispatchers.Unconfined`.
- Real demo interceptor acceptance/refusal for each Save list, bracketed Reject and refused row, later native server answers/reset, unsupported writes, malformed fields/tokens, missing assets, initial HTTP/browser parity. Downstream interceptor throws before any socket.

## Checks actually performed and handoff

`git diff --check` passes. Added-line whitespace/conflict scans pass for all 13 changed/new files. Standard-library HTML structure checks confirm four empty served fields, both synthetic meta tokens and the bracketed nomination input. Read actual Kotlin/Swift declarations and all affected call sites, including `container.writeRepository`, form/chip/chrome APIs, shared dispatch, encoder, HTTP error mapping and exact iOS verdict. Inspected cached Compose test APIs with `javap` for sibling/text matchers and enabled/text/count assertions; temporary extraction was removed. These are static checks, **not compilation, Kotlin parser execution, tests or visual verification**.

Claude must run Android debug compilation, these four suites (`AO3TagSetTest`, `AO3TagSetWritesTest`, `AO3TagSetScreenTest`, `DemoTagSetTest`), existing write-dispatch/session-generation, collection form/Moderation/Maintainers, demo browser/block and navigation suites, then the normal full Android test gate. Every compile/runtime/request/count/coroutine/Compose/layout assertion needs that run. Then inspect the demo in Light, Dark, Sepia and OLED at normal and accessibility text sizes: both editor back paths, every field/placeholder, Save success/refusal, Reject success/refusal, busy spinners/disabled controls, long lazy queue, 44 and signed out/session changes. Capture screenshots for the human review; visual correctness is not claimed.

No Gradle, Xcode, Kotlin compiler, tests, emulator, sign-in or AO3 request was run. No commits, pushes, branch switches, TASKS.md edits, iOS edits, backup/schema changes, stubs, helper scripts or `.orig` files. Work remains uncommitted in this worktree on `android/agent-gemini-3bg` for Claude.

**Next step:** Claude builds, tests, reviews screenshots and commits. **Open questions:** none.

**Landing note (Claude, 2026-10-07).** Landed with one change to the code and three to the
tests. Gate green (1,856 tests).

**Both requests were read against iOS's code line by line** (`AO3ChallengeActions.swift`
`saveTagSetFields` and `reportRejectedTag`; `AO3Client+Challenges.swift`
`tagSetSaveParameters` and `rejectedTagParam`):

- Save tags: one fresh read of the tag set's edit page for its token, then one POST to the
  address the loaded form gave, with `authenticity_token`, the form's `_method` when it has
  one, and the four `owned_tag_set[tag_set_attributes][…_tagnames_to_add]` fields in iOS's
  order, empty ones included. The token read comes before the "Couldn't find AO3's tag-set
  form." check, as on iOS.
- Reject: one fresh read of the nominations page for its token, then one POST to that page
  with `_method=put`, `authenticity_token` and `{kind}_reject_{name}=1`, the name's brackets
  replaced as iOS replaces them.
- Neither is retried, neither reads again after success, and the screen changes only on AO3's
  confirmation. The verdict is the one the collection writes already use, as on iOS.

**Changed on landing.** The address Save tags posts to comes from AO3's page. It is now kept
only when it is one of AO3's own hosts, as Unsubscribe's captured address already is; anything
else reads as "Couldn't find AO3's tag-set form." One test. The three test changes: two count
checks matched more than one row (the three review counts share a panel, so equal numbers are
siblings of every label), and the large-text check used `hasVisualOverflow`, which reports a
width overflow for a short label narrower than its row; "Save tags" is not clipped.

Seen on the emulator in airplane mode against the demo's local answers (Dark): a Tags row
opening Add tags with iOS's four labels, placeholders and footnote; Save accepted ("Tags
saved.", what was typed kept); Save refused ("Fandom tags to add: Uncharted Lantern could not
be added.", nothing lost); Reject accepted (Letters [Winter] becomes Rejected, counts 3/1/1 to
2/1/2); Reject refused ("Couldn't reject “Paper Harbor”: Paper Harbor is locked for this
review.", row and counts unchanged). Not seen: tag set 44 (edit form refused), signed out, a
Reject held in flight, Light, Sepia, OLED, large text (all in tests).

**Never run against AO3**, like iOS's own two writes (its comments say so). Owed a try on a
real tag set by its owner before a release.

Left for polish (P3): the review list's rows are now lazy items, and each draws its own
border, so the lines between nominations are full-width and heavier than the hairlines in the
panels above; "Save tags" is the default accent on a dark panel (owner question 2).
