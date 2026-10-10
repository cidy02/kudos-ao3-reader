# Brief 3ba — Challenge Settings (read only)

**3cc follow-up (unbuilt Codex handoff, 2026-10-09).** Assignments and Defaults/pinch hits now request the native assignments screen; see [3cc-result.md](3cc-result.md) for request admission/counts, the two owner writes and pending verification. Settings still reads no assignment list for its own tally rows. The Sign-ups join still reads only Complete/Open/Defaults; its parser and shared Winter fixtures are extended, not duplicated. Historical browser-destination statements below describe the earlier landing.


**3be follow-up (Codex, 2026-10-05; unbuilt handoff).** Tag-set rows now request the
native numeric-ID Tag set screen, passing the served title and `isModerator = true`
as iOS does. Their earlier browser detour in the historical notes below is superseded.
Summer's shared demo profile now links **Summer Prompt Tags** to **44**, as authorized
by Claude, rather than sharing Winter's 42. All other Summer profile content is unchanged.
See [3be-result.md](3be-result.md) for the read counts, fixtures and pending verification.

**Landing note (Claude, 2026-10-05).** Landed with one fix. Gate green (1,687 tests).

**The reads were counted first.** For one opening or refresh `getChallengeSettings` reads, one
after another: the gift exchange form (and, only when that is missing or is not a gift form,
the prompt meme form); the collection's profile; and, for a gift exchange, the first page of
sign-ups and the last page when there is more than one. Four at most. **No assignment page is
read, and nothing is sent.** iOS's screen goes on to read every page of three assignment lists;
Android does not, and shows those two rows without values (owner question 16).

Changed on landing: the patch declared `AO3ChallengeKind` a second time in a package that
already had it, which did not compile. The existing type now carries the address segment the
new code needs, and the new screen uses its existing name.

Seen on the emulator in airplane mode against the demo's local answers, in Light and Dark:
Winter Exchange 2026 as a gift exchange (the type, five dates, the request ranges, two disabled
switches, two tag sets, "Sign-ups 4", Assignments and "Defaults and pinch hits" with no value,
Run matching); Summer Prompt Meme as a prompt meme ("Prompt requirements", "Prompts per
sign-up", one "Tag set"); Rare Pairs Week with "Sign-ups: Couldn't load" and the rest of the
screen intact. Not checked on the emulator: where each row leads (five of them open AO3's page
in the in-app browser until their screens exist; covered by tests), Sepia, OLED and large
text.

A saving left on the table, for both apps: a prompt meme's opening first asks for the gift
exchange form and gets "not found". The collection's page already says which kind it is.

## Corrected brief: values deliberately omitted

The corrected 2026-10-05 top section is binding. Android reads **no assignment page** and leaves the value absent for **Assignments** and **Defaults and pinch hits**. It omits every iOS walk-derived value: `N matched, M unmatched`, `None sent yet`, the defaults-plus-covered integer, and `Couldn't load` for either of these rows. Sign-ups retains its own count/failure wording. No sentence replaces the missing tallies. Owner question **16** (whether to permit the iOS assignment walk) remains deferred; this implementation does not depend on its answer.

The iOS loader calls, in order (`ChallengeSettingsView.swift`):

```swift
let sent = try? await assignmentRows(AO3ChallengeAssignmentList.sent)
let defaults = try? await assignmentRows([.defaults])
matchedCount = sent?.count
unmatchedCount = defaults?.count
if let sent, let defaults {
    defaultsCount = defaults.count + sent.filter(\.isCovered).count
} else {
    defaultsCount = nil
}
```

The walk (`Services/AO3Client+Challenges.swift`, `allChallengeAssignments`) has no cap:

```swift
for list in lists {
    var page = 1
    while true {
        try Task.checkCancellation()
        let result = try await fetchPage(list, page)
        assignments.append(contentsOf: result.assignments)
        guard page < result.totalPages else { break }
        page += 1
    }
}
```

`AO3ChallengeAssignmentList.sent` is `[.assignments, .unfulfilled]`, so Complete, then Open, then Defaults are walked. These short code quotations are from the local reference, not fetched from AO3.

## iOS reference inventory

Read `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift`, `Services/AO3Client+Challenges.swift`, `Services/AO3Client+Collections.swift` and `Models/AO3ChallengeModels.swift`. iOS code governs where prose differs.

Header: **AO3 Account** / **Challenge** / `TITLE · Gift Exchange` or `TITLE · Prompt Meme`; empty title falls back to slug. Before a form loads it defaults to Gift Exchange, and refresh retains the previous form's subtitle. No top buttons. Intro: “An AO3 challenge belongs to a collection and has its own sign-ups, assignments and deadlines. This page shows its settings in the same order as AO3.”

In order:

1. Owner only: disclosure **Edit settings**, no value or section header; opens `ChallengeSettingsEditView` with slug, title and owner hint. Non-owner otherwise has the same read layout; AO3 normally serves this form only to owners.
2. **Type**: both rows are always present. **Gift Exchange** / “Sign-ups are matched into assignments”; **Prompt Meme** / “Prompts are claimed freely”. Checkmark marks the actual kind; neither changes it.
3. **Dates**: **Sign-ups open**, **Sign-ups close**, **Works due** (assignments_due_at, NOT either reveal), **Works revealed**, **Creators revealed**. All show the abbreviated date of AO3's wall-clock digits, with no device-zone conversion/time, unparseable nonempty source text verbatim, empty/missing “Not set”. Footnote: “AO3 doesn't close the collection when a deadline passes. You close it yourself with the Closed setting.”
4. **Sign-up requirements** for Gift Exchange; **Prompt requirements** for Prompt Meme. Meme first adds **Prompts per sign-up** / `requestsRequired to requestsAllowed`. Both: **Fandoms per request/prompt**, **Relationships per request/prompt**, **Characters per request/prompt**, each `required to allowed`; **Additional tags** / “Optional” or “Not allowed”; **Allow any prompt**, disabled switch = OR of allow-any fandom/relationship/character/freeform. Exchange alone adds **Require a fandom match**, disabled switch = NOT allow_any_fandom. Restrictions are the request restriction, not offers. Missing integer ranges default 0 (requests default 1); absent checkboxes false.
5. **Tag set** for one, **Tag sets** for several, omitted for none or profile failure. Profile dt starting “Tag set” supplies numeric links, deduplicated by id; label is served title or “Tag set ID”. Each opens `TagSetView(id, title, isModerator: true)`.
6. Exchange: **Assignments**. **Sign-ups** / total or “Couldn't load”, opens `ChallengeSignUpsView`. **Assignments** / “N matched, M unmatched”, or “None sent yet” only if BOTH successful counts are zero, or “Couldn't load” if either failed; opens `ChallengeAssignmentsView` with owner hint. **Defaults and pinch hits** / defaults + covered sent count, or “Couldn't load” if either list walk failed; opens the SAME assignments screen. Matched = Complete + Open across every page; unmatched = Defaults; covered = giver ownText ends `* (pinch hitter)`. Footnote: “AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for a pinch hitter, but you can't run the match.”
7. Exchange: **At AO3**: **Run matching** / “Opens AO3”, opens `/collections/SLUG/potential_matches` using the external OS browser. No other matching row.
6. Meme replaces the entire lower half with **Prompts**: **Prompts** / “Claim and fill”, opens `PromptMemeView`; **Prompts posted anonymously** / “Yes” or “No”. Footnote: “A Prompt Meme has no matching or assignments. People post prompts and others claim them.” No Assignments or At AO3.

Loading retains header/intro, hides sections: “Loading challenge settings…”. Failure retains header/intro: “Couldn't load challenge settings”, user-facing error, “Try Again”. Signed out uses this same failure panel: “Log in to AO3 before using this feature.” No login button. Only the required settings read fails the whole screen; profile/count failures leave the loaded screen intact. Standard iOS user-facing transport/HTTP/session/parse messages use the mapping already ported for Moderation.

## iOS requests (reference, not the Android contract)

Opening, retry and pull-to-refresh use the same strictly sequential reads (NO requests made together):

1. Authenticated GET `/collections/SLUG/gift_exchange/edit`. On 404 OR a returned page that cannot parse as a gift form, GET `/collections/SLUG/prompt_meme/edit`. Other gift GET errors stop; meme failure fails the screen. Form parsing uses the first kind-action form, falling back to `#main form`, and requires meta or form-input CSRF even though this screen never submits it.
2. GET `/collections/SLUG/profile`, best effort. Failure omits tag sets. iOS permits an anonymous fallback only when building its optional authenticated request fails; normal signed-in opening is authenticated. Android keeps reads authenticated through its existing client.
3. Gift only: GET `/collections/SLUG/signups`; when totalPages > 1, GET ONLY its last page (`?page=N`). Total = first row count × (N−1) + last count. Not every sign-up page (the view comment differs; client code wins).
4. Complete assignments `/collections/SLUG/assignments?fulfilled=true`, all pages with `&page=N`, THEN Open `?unfulfilled=true`, all pages. Failure abandons this walk and leaves matched unknown.
5. Defaults `/collections/SLUG/assignments`, all pages with `?page=N`, even if sign-ups or sent assignments failed. Failure leaves unmatched unknown. No separate pinch-hit fetch: Open includes covers.

## Android requests and policy

The corrected brief removes iOS steps 4 and 5 entirely. Gift Exchange = form → profile → first sign-up page → last sign-up page only if paged: at most four logical reads. Prompt Meme = gift-form probe → meme form → profile: three. Each is sequential, authenticated, paced/coordinated/coalesced by the existing client, with only its existing transient GET retries. Profile failure omits tag sets; first/last sign-up failure leaves **Sign-ups** saying “Couldn't load”. Assignment rows have no values, since no assignment read was attempted.

The earlier draft incorrectly treated iOS's uncapped assignment walk as authorized by the policy; corrected here. **No background or bulk scraping** prohibits it absent owner question 16's decision. The retained reads are the explicitly opened challenge form/profile plus iOS's two-page sign-up tally, expressly authorized by the corrected brief. No intermediate sign-up pages, background work, prefetch, assignment GET, raw client, concurrency fan-out or write. Policy pacing, coordinator cap, coalescing, host allow-list, transient-only retry, cancellation and no-local-deletion rules remain intact.

## Work log

Started with clean tree on `android/agent-codex-3ba`. Read the 3aw/3ay landing notes and project/networking docs. Brief overrides task claims, branch switching, commits, pushes and build requirements. No sign-in, AO3 contact, Gradle or Xcode invocation. Implementation and test-run handoff to be recorded below.

## Implementation and destinations

- `network/ao3/account/AO3ChallengeSettings.kt` holds the read-only settings/count/tag-link models, parser and `ChallengeSettingsDestinations`. It contains **no assignment parser, tally fields or serializer**. It validates the sign-up landmarks so an unrecognized page is failed rather than zero; missing settings fields take iOS's defaults. Dates retain the AO3 form digits and are formatted as abbreviated local-language dates without converting the wall clock to the device zone; unparsed nonempty text stays visible.
- `AO3CollectionDetailRepository.getChallengeSettings` reuses its authenticated `fetch` and the existing `AO3Client` coordinator/pacing. Gift form → profile → first/last sign-up page, or gift probe → meme form → profile. No assignment GET, extra ownership probe or simultaneous request. One small cancellation check at the shared fetch entry prevents a cancelled coroutine starting another GET. Session generation is checked after every result and before installing the aggregate.
- `AO3ChallengeSettingsState` binds a load to the visible screen/session, prevents concurrent refresh/retry loads, and cancels on departure. Header kind survives refresh/failure, as iOS retains its form. Signed-out opening is the iOS failure panel without a login button. Required-form failure uses the already-ported iOS error mapping from Moderation; a profile/sign-up failure stays best effort (session changes still retire the screen's old model).
- `AO3ChallengeSettingsScreen` reuses SubjectHeaderBlock, SectionRuleHeader, SettingsPanel, SubjectFormRow, SubjectRowSeparator, SubjectToggle and KudosRefreshBox. Collection-title hue supplies the palette in Light/Dark/Sepia/OLED. Every new Text has a line height; no shared line heights changed. Values wrap; disabled switches stack under their labels at accessibility font scale. No top actions, Material cards/chips or editing control. Neither Type row is tappable. Read-only switches are disabled. Visual correctness is not claimed without screenshots.
- Manage › Challenge Settings routes to `Routes.ao3ChallengeSettings(slug, title, owner)`, registered in AppNavHost with subject-header chrome and hidden tab bar. Existing Manage › Maintainers and the Moderation screen's two maintainer rows already open native Maintainers; this work preserves them. iOS Challenge Settings has **no maintainer row**, so none was invented. A search of the updated Android lane found **no native Tag Set screen**; those rows use the browser.

All currently missing native destinations live together:

| Named destination | Eventual screen | In-app browser page |
|---|---|---|
| `challengeSettingsEditView` | ChallengeSettingsEditView | `/collections/SLUG/gift_exchange/edit` or `/prompt_meme/edit`, chosen from the loaded kind |
| `promptMemeView` | PromptMemeView | `/collections/SLUG/requests` |
| `tagSetView` | TagSetView | `/tag_sets/ID` |
| `challengeSignUpsView` | ChallengeSignUpsView | `/collections/SLUG/signups` |
| `challengeAssignmentsView` | ChallengeAssignmentsView | `/collections/SLUG/assignments` (both Assignments and Defaults and pinch hits) |

`runMatching` is separate: `/collections/SLUG/potential_matches` uses the **OS browser in live mode**, exactly iOS's own escape hatch. In fixture demo mode it opens the existing local in-app browser instead; an unavailable matching fixture yields the browser's local not-found page and can never contact AO3. These taps only navigate; this screen prepares/sends no write and performs no destination read itself.

Omitted Android wording: from iOS's assignments footnote, **“In Kudos, you can view sign-ups and assignments and ask for a pinch hitter, but you can't run the match.”** Android has neither the native views nor pinch-hitter requests. Only the true prefix **“AO3 matches participants.”** remains; no invented replacement sentence. The omitted tally values are enumerated at the top. The corrected brief's no-assignment-walk rule takes precedence over the older brief's requests/tallies language. Elsewhere iOS code wins: sign-up total reads first + last, not every page despite the view's comment; matching opens the external OS browser, not the in-app replacement used for missing native views.

## Shared local demo

Reused existing `ao3_challenge_settings.html` (added original requirement inputs), `ao3_challenge_signups.html` (the existing two-row/two-page answer, total 4), `ao3_collection_show.html` (added a second original tag-set link; kept every existing count/flag/navigation field), and `ao3_tag_set.html`. **No new assignment fixture or assignment tally** was added; the corrected brief excludes those reads. Existing assignment/browser fixtures remain available only if a user opens that destination.

New original asset: `ao3_demo_meme_settings.html`. Summer reuses the existing collection-profile fixture with one shared slug/title/kind substitution and one tag-set link, rather than a second copy of a page collection detail already reads. Summer's gift-form probe returns local 404, then the meme form succeeds. The collection's show/profile address uses this same derived profile answer for both the collection detail and Challenge Settings; the fixture supplies owner-visible settings navigation. Winter's profile keeps its existing shared answer. Rare Pairs reuses/enriches its existing `ao3_demo_maintainers_show.html` with the Challenge Settings link and Gift Exchange kind already present on its collection-list entry; counts and maintainers are preserved. Its sign-up address returns local 404 so the row displays “Couldn't load”. DemoNetworkRoutes supplies one answer per address; the read-only WebView uses the same answer (including Rare Pairs' existing slug/title substitution). The 3az draft-page date transformation is retained.

After Claude builds/installs, use airplane mode and the existing fixture-only launch extras; these do **not** sign in to AO3:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true
```

Account → Collections (in Reading):

- **Winter Exchange 2026 → Manage → Challenge Settings**: Gift Exchange, five dates, request requirements, **Tag sets** with Winter Exchange Tags and Snowbound Characters, Sign-ups **4**, both assignment disclosure rows with absent values, At AO3 / Run matching. Owner-only Edit settings opens the gift form in-app.
- **Summer Prompt Meme → Manage → Challenge Settings**: Gift probe then Meme, **Prompt requirements**, Prompts per sign-up, no Require a fandom match, **Tag set** singular, Prompts / Claim and fill, Prompts posted anonymously / Yes. No Assignments or At AO3; Edit settings opens the meme form.
- **Rare Pairs Week → Manage → Challenge Settings**: Gift Exchange with failed Sign-ups / **Couldn't load**; no “0” or invented assignment failure. No tag-set section. Manage › Maintainers remains native and still supports its pre-existing only-owner case.

Follow the five missing-native destinations in the local browser; both assignment rows share the same page. Run matching in demo shows local not-found, never an external browser. Inspect Light, Dark, Sepia, OLED and double font scale after build. Restart to reset the other screens' mutable demo state.

## Verification and handoff

**Not run:** Gradle, Kotlin compilation, JVM/Robolectric tests, emulator or Xcode; the brief forbids builds here. Read real symbols/callers for the repository, auth/client/result types, subject/settings components, refresh, routes, and test support. `git diff --check` and a whitespace scan of the new files pass. No sign-in, AO3 request, commit, push, branch switch, TASKS edit, backup-format/schema change, stub, helper script or `.orig` file.

Offline tests added:

- `account/AO3ChallengeSettingsTest.kt`: fixture settings/tag/count parsing, absent defaults, date formatting, every allow-any flag, malformed vs empty sign-ups, first/last-only four-read opening + refresh, authenticated headers, gift-404 and parse fallback, meme's three-read order, profile/first/last failures, zero versus unknown, required-form failure, signed-out no request, session change at each read, duplicate load and view-exit cancellation, destination URLs/slug encoding, no assignment GET and no POST.
- `account/AO3ChallengeSettingsScreenTest.kt`: real Manage row callback opening the screen, every gift disclosure's URL, OS-browser matching callback, meme differences and destinations, failed count wording with absent assignment values, loading/failure/retry/signed-out words, non-owner with disabled controls at double text scale in all four themes. Its repository uses **Dispatchers.Unconfined** through the shared setup. This exercises a small callback host; AppNavHost wiring is source-inspected, not executed.
- `network/ao3/DemoChallengeSettingsTest.kt`: terminal local responses for gift, meme probe, meme, profile, first/last counts, failed count and missing fixtures; same HTTP/browser answers; existing collection parser can see each demo challenge's Manage link. A downstream interceptor throws before any socket dispatch.
- `app/RoutesNavigationTest.kt`: real NavController round-trip of challenge slug/title/owner and shell metadata. Existing moderation screen test receives the added callback explicitly so its independent flow remains unchanged.

Claude needs to run the Android compilation/lint/test gate, including these tests and the existing collection/detail/demo/maintainers/navigation suites. All behavior asserted above by tests is **a test-to-run claim**, not a passing-test claim. Screenshots remain required for all four themes and accessibility size; check date wrapping, disabled switches, absence of tally values, and the three demo navigation paths. Inspect live-mode external-browser intent construction locally without opening an AO3 URL.

## Open questions

- **Owner question 16 remains deferred:** whether to permit iOS's uncapped Complete/Open/Defaults assignment walk (and restore its tallies). Android currently makes no assignment read. The corrected brief supplies the decision for this patch, so it is not blocked on that future product/policy decision.
- No additional implementation question remains.
