# Brief 3bi — Prompt Meme prompts, reading only

## Reads counted first

iOS `PromptMemeView.loadPrompts` calls `challengeSettings` before the listing when its close-date string is empty. That client rewrites the supplied meme-edit request to **GET `/collections/SLUG/gift_exchange/edit`**, then, only for 404 or an unparseable gift form, **GET `/collections/SLUG/prompt_meme/edit`**. Finally it reads **GET `/collections/SLUG/requests`**. A normal signed-in meme opening therefore makes **three sequential logical reads**. A non-fallback schedule error makes it two; a successful gift form also makes it two. Schedule failure is silent and omits the close date; listing failure shows the failure panel. Signed out: **one public listing GET**, no schedule attempt. No public fallback is added for a failed signed-in session.

Android shares the smallest settings-form portion of 3ba's existing `getChallengeSettings`, avoiding its additional profile read (and gift-only first/last sign-up tally). Thus normal meme opening and pull-to-refresh = **three**, each further page = **one** listing GET (`?page=N` for N > 1). A page replaces the previous page, as iOS; it does not append. No profile, assignment, claims, user or individual prompt read, prefetch, page walk or POST. Counts exclude shared transport retries. Every read uses the existing AO3Client with its pacing, slots, host checks, auth-qualified coalescing, transient-only retries and cancellation. The policy's explicit foreground collection navigation permits the two schedule form attempts and the selected listing page; further pages/refresh/retry require the reader's explicit action. No uncapped walk occurs here; question 16 does not apply.

## iOS side — repeated failed schedule lookup

The real iOS code tests `closeDateText.isEmpty`, not whether a lookup has already been attempted. On every further page (and claim/release reload) it repeats a missing/failed schedule lookup, potentially making three reads instead of one. **Claude, who runs the port, answered; the owner has not been asked:** attempt the schedule once per opening and once per pull-to-refresh, never on further pages; a missing date stays absent and refresh retries it. This also governs the later Claim/Release brief. Android follows that correction. iOS otherwise wins over the brief's loose “load more” wording: `SearchPaginationBar` selects and replaces one page.

## iOS inventory, read from code

Reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/PromptMemeView.swift`, `ChallengeSettingsView.promptsRows`, `Features/Account/AO3CollectionDetailView`, `Services/AO3Client+Challenges.swift`, `Services/AO3ChallengeActions.swift`, `Models/AO3ChallengeModels.swift` and `Features/Challenges/ChallengeSignUpView.swift`. Reference tree is read only.

Reached from Challenge Settings's Prompt Meme **Prompts / Claim and fill** disclosure and collection detail Manage's **Prompts** row whenever AO3 supplies a prompts URL (not maintainer-gated). Both pass slug and title; no origin/role-specific header. Kicker = passed collection title, falling back to slug; title **Prompts**. Subtitle = `N prompt(s) · U unclaimed`, adding ` on page P of T` only for several pages, and ` · open until DATE` only after a nonempty schedule close date (unparseable served date text remains verbatim). Counts are the unfiltered current page, not totals. Initial header says `0 prompts · 0 unclaimed`. Refresh/failure retains prior page/counts. No top action buttons in this view; the Android shell supplies its usual Material Back icon.

Segment: **All**, **Unclaimed**, **Yours**, local filtering only. Unclaimed = no claimants and no viewer claim. Yours = viewer's Drop Claim signal OR posted by their login (case-insensitive trimmed exact byline or suffix `(login)`); anonymous posters never match. Section heading is selection plus filtered count.

Each panel, in order: first fandom's bare title uppercased (accent, 9pt bold tracking .99), `+N` for extra fandoms (accent at .6), then **claimed**/**unclaimed** (secondary at .6, 9pt semibold tracking .45). Fandom kicker is one line. Optional title (15pt semibold), omitted for AO3's stand-in **Request**. Full summary as plain text (14.5pt), no description truncation. Chosen non-optional `ul.tags` anchor/tag-li texts join with comma-space (11.5pt secondary .65), one line with tail truncation normally, unlimited at accessibility size. No category prefixes: warning/rating/category/relationship/character/freeform texts keep AO3's own words; fandoms stay in the kicker. Optional tag lists are excluded. Poster (11.5pt secondary) = **Posted anonymously** if parsed owner is Anonymous, otherwise served byline or **Unknown poster**. Neither poster, title, description nor tags opens anything in iOS. Own claim adds **Claimed by you** (accent, 12.5pt medium) and **Release**. Otherwise an AO3 claim form with numeric `prompt_id` adds **Claim** even if others claimed it (multiple claims are allowed). Otherwise claimed prompts add **Fill it** with Safari glyph. No numeric claimant count is printed. Claim uses accent fill/on-accent label; Release and Fill it use accent text over accent .14 capsule. Claim/Release disable while any write is in flight, selected action spins.

Paging uses `SearchPaginationBar`: previous and next arrows; centre **Page P / T** opens the page picker, and a spinner replaces the picker glyph while loading. Arrows can also jump to ends by their existing long-press behavior; no page is read while choosing. Controls disable during load. Success replaces rows/page/total. Failure with nonempty old prompts retains them and old page, with **Couldn't load that page: REASON** above; failure without prompts shows **Couldn't load prompts**, reason, **Try Again** (retries current successful page, initially 1). Initial loading: spinner and **Loading prompts…**; existing rows remain during a later load. Empty All: **No prompts yet** / **Prompts will appear here once someone posts one.** Empty filter: **No unclaimed prompts** or **No yours prompts** / `No prompts on this page match the "FILTER" filter.` Signed out has the same public screen/filter/paging/error states, with no New prompt bar and no bespoke sign-in sentence. Pull-to-refresh loads page 1.

Footnote: **A Prompt Meme has no matching or assignments. You can claim a prompt here and release it later. Add a new prompt through your sign-up, and post fills on AO3.** Android retains the first sentence only: the rest advertises unavailable native writes. No replacement sentence. Signed-in bottom bar **New prompt** pushes `ChallengeSignUpView`; it does not write on navigation. **Fill it** merely opens `/collections/SLUG/prompt_meme` in the browser, so Android retains it and the exact address. It is not a write.

## iOS writes and New prompt — for the next brief

**Claim**: tap calls `auth.claimPrompt`; requires sign-in, fresh authenticated CSRF GET `/collections/SLUG/requests` (page 1), then single POST `/collections/SLUG/claims` with `authenticity_token` and `prompt_id`. CSRF header/Referer use requests, non-Ajax. **Release**: requires own claim ID; fresh CSRF GET `/collections/SLUG/claims?for_user=true`, then single POST `/collections/SLUG/claims/ID` with `_method=delete`, `authenticity_token`, CSRF header/Referer from for-user claims. Success in either reloads current prompts page, with no success notice; the iOS schedule caveat above applies. Failure retains cards and displays red dismissible **Couldn't claim that prompt: REASON** or **Couldn't release that prompt: REASON**. In-flight flag clears afterward.

Both use challenge verdict: AO3 error text wins; success flash or bare 3xx succeeds; non-2xx uses **AO3 couldn't claim that prompt.**/**AO3 couldn't release that prompt.**; unconfirmed 2xx = **AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.** Signed out = **Log in to AO3 first.** Actual shared CSRF helper missing-token words = **Couldn't prepare the request. Try again, or open the work on AO3.** No write retries/coalescing.

**New prompt** opens the sign-up editor (`Your sign-up`), authenticated GET `/collections/SLUG/signups/new` through `ownChallengeSignUp`; existing form can be returned. A meme takes requests only. **Submit sign-up** validates locally first; invalid form retains errors and sends nothing. Save fetches fresh CSRF from `/signups/new` or `/signups/ID/edit`, then one POST to served form action (fallback `/signups` for new, `/signups/ID` for existing). Sends token, nonempty `_method`, nonempty `challenge_signup[pseud_id]`, every nested request/offer's ID when persisted, title, description, URL, anonymous, four tag-name strings, four any flags and destroy flag using `challenge_signup[{requests|offers}_attributes][INDEX]`. Nested keys are `[id]` only for positive IDs, `[title]`, `[description]`, `[url]`, `[anonymous]`, `[any_fandom]`, `[any_character]`, `[any_relationship]`, `[any_freeform]`, `[_destroy]`, and `[tag_set_attributes][{fandom|character|relationship|freeform}_tagnames]`; booleans are `1`/`0`, tags join with a literal comma, including empty lists. AO3 parsed field/general errors retain form; AO3 error text becomes general error; success flash/3xx returns parsed form or posted form, with **Sign-up submitted successfully!**; otherwise unconfirmed words above. No sign-up writes or editor navigation are ported here.

## Decided without asking

- New remote parser/model/URLs: `network/ao3/account/AO3PromptMeme.kt`; screen/state in existing `account/`. In-memory snapshots only; no Room, library or backup changes.
- Reuse settings-form reader, existing client, subject panels/header, challenge section/footnote, local filtering, tokens.scopePalette and app tag chips. No second HTTP path or new dependency.
- Two original Summer fixtures keyed by page; one shared DemoNetwork answer per address, native and browser. Existing other collections' requests fixture remains intact.
- No Claim, Release or New prompt controls, editors or explanatory substitutes. Retain claimed/unclaimed and Claimed by you state. Retain browser-only Fill it because the iOS code wins over treating it as a possible write.
- Wire collection Manage's existing Prompts row to the same screen too, matching iOS's second entry. It adds no row or request. Gift Exchange's Challenge Settings layout/destinations stay as before.
- Keep the iOS comma-separated tag-summary wording together in one app `SubjectChip`; one line/ellipsis normally, fully wrapping at accessibility scale. This needs a default-preserving `maxLines = 1` parameter on the existing chip (3be's earlier addition was removed on landing because it had no remaining use; this screen does need it). No shared line heights or other defaults change. Android chip styling/13sp type replaces iOS's plain 11.5pt tag line, as the brief requires app chips.
- Use the app's existing segmented track normally; at accessibility scale render the same three options in a wrapping challenge panel with selection semantics. The fandom kicker and claim state stack at that scale, so no short state is displaced by a long fandom. No new top action. All text declared in the new screen has explicit line height; reused shared components remain unchanged except the chip's optional wrapping.
- Reuse `KudosPaginationBar`, including its existing First/Previous/Next/Last icon buttons and page-picker sheet, rather than creating another paging component. Its Android position wording is **Page P of T**. Picker draft changes do not read; selection reads one page. This is an existing app-chrome difference from iOS's **Page P / T**. Use stacked paging at accessibility scale and token-backed Material colors for refresh/picker/retry chrome.

## Implementation and destinations

- `AO3PromptMemeParser.parse` mirrors iOS's exact card/container selectors, byline split, untitled Request suppression, owner privacy, own Drop Claim ID, anonymous claimant maximum, claimable numeric form parameter, chosen tag order and pagination. Missing IDs have negative row-only identities. Recognized empty pages stay empty; unrecognized/login/overload HTML fails without touching stored works.
- `AO3CollectionDetailRepository.getChallengeSettingsForm` extracts the existing gift→meme form sequence; both 3ba's `getChallengeSettings` and this screen call it. Calling full 3ba `getChallengeSettings` for a normal meme would make **three schedule-related reads** (gift, meme, profile) plus prompts = **four**. The extracted part makes **two** plus prompts = **three**, with no new parsing or form-read implementation. For an unexpectedly returned Gift Exchange form, extraction avoids profile and first/last sign-up reads too (full 3ba can make four settings reads; extraction makes one). The existing 3ba counts and failure behavior are preserved.
- `getPromptMemePrompts` fetches exactly the selected page through the shared `fetch`/AO3Client. Signed-in headers remain authenticated; signed-out public reads explicitly use empty headers, matching iOS and 3be's precedent. Required signed-in auth errors do not silently retry anonymously.
- `AO3PromptMemeState` fences results by opening generation, prevents duplicate in-flight loads, cancels on screen disposal, retains old rows/page on listing failure, and attempts schedule only on opening/refresh. Optional schedule failure clears/omits the date without showing an error. Try Again makes just the listing read, a deliberate sparing extension of Claude's no-schedule-on-pages answer. Refresh returns to page 1 and retries schedule even if a previous date existed; iOS keeps a nonempty date without rereading it.
- `AO3PromptMemeScreen` uses the lazy list, subject header, challenge sections/footnote, SettingsPanel and app chips, `tokens.scopePalette`, token-only ink/wash/panel/state colors and `statusBars + 76dp` clearance. Each card is a lazy item. Full descriptions/titles/posters wrap; normal tag summary and fandom kicker truncate deliberately, accessibility values wrap. Claimed by you remains accent-colored; claimed/unclaimed is secondary at .6. The browser-only Fill it uses a token-tinted app chip, browser icon and 44dp hit height.
- `Routes.ao3PromptMeme(slug, title)` and AppNavHost register subject-header chrome and hide the tab bar. Challenge Settings passes the effective collection title only in its meme branch; CollectionManageRow's existing Prompts row uses the same native route. Browser-only Fill it goes through `Routes.webFallback` to `/collections/SLUG/prompt_meme`. Tag/title/poster/description are not tappable. No writing repository is accepted by this screen/state, and no POST implementation was added.

## Read-by-read policy accounting

| Logical read | Trigger/order | Policy basis / failure |
| --- | --- | --- |
| `/collections/SLUG/gift_exchange/edit` | First schedule attempt on signed-in opening/refresh | Explicit foreground challenge navigation through the existing authenticated client. 404/parse alone permits meme fallback; other errors omit date and continue to listing unless session changed. |
| `/collections/SLUG/prompt_meme/edit` | Second schedule read only after gift 404/parse | Same selected challenge's fallback form, sequential, no additional profile/tally. Failure silently omits date; session change retires load. |
| `/collections/SLUG/requests` | After schedule attempt; sole read for signed-out opening/refresh or Try Again | Explicit selected public listing. Authenticated when signed in; existing public client when signed out. Failure shows required-error panel if no old prompts, otherwise old content plus page warning. |
| `/collections/SLUG/requests?page=N` | Only explicit page selection, never prefetch | Explicit foreground paging, exactly one GET. Failure leaves successful page number/rows/total intact so reader can retry the same selected page. |

All inherit policy pacing/coordinator, host allow-list, retry/429/403 handling and cancellation; no new retry loop, fan-out, sweep or local-data mutation. A session change observed in any read stops the sequence and prevents stale model installation. Counts are logical page attempts, not the client's permitted transient transport retries.

## Demo walkthrough and routes (for Claude, not executed here)

Fixtures are original fictional filler: `ao3_demo_meme_requests_1.html` and `ao3_demo_meme_requests_2.html`. Summer's `/requests`, `?page=1` and `?page=2` share one answer per address between native client and demo browser via `DemoNetworkRoutes.fixtureName(HttpUrl)`. Other collection requests fixtures are unchanged. Unknown Summer pages and missing assets are terminal local 404s. The schedule reuses the existing `ao3_demo_meme_settings.html` and local gift 404, without changing that fixture or any profile. The local demo session's account is **AO3_Reader**.

Direct route has **one query argument**, with no `&` for the device shell to cut off:

`nav:ao3-prompt-meme/summer_meme?title=Summer%20Prompt%20Meme`

After Claude builds/installs, launch the existing fixture-only demo in airplane mode:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosDebugRoute 'nav:ao3-prompt-meme/summer_meme?title=Summer%20Prompt%20Meme'
```

From `nav:ao3-collections`: **Summer Prompt Meme → Manage → Challenge Settings → Prompts / Claim and fill**. Also **Summer Prompt Meme → Manage → Prompts** opens this screen directly, as iOS.

Page 1: **4 prompts · 1 unclaimed on page 1 of 2 · open until Jun 30, 2026** in an English-US locale. Lanterns after closing is unclaimed and has two fandoms plus warning/rating/category/relationship/characters/additional tags (optional suggestion excluded). A borrowed constellation is claimed by you. The last ferry home is claimed by ReedMapmaker and offers browser-only Fill it. The anonymous untitled Request has two anonymous claimants and a Claim form in HTML, which supplies state only on Android. Unclaimed filters to Lanterns; Yours filters to A borrowed constellation. Next/Last explicitly reads page 2 and replaces rows: two unclaimed prompts, including EveningInk (AO3_Reader)'s long Orchard prompt (879 characters, full ending retained) and an anonymous untitled prompt. Yours on that page shows Orchard. No Claim/Release/New prompt appears on either page. Inspect Light, Dark, Sepia, OLED and large font; screenshots remain pending.

Signed out (omit the demo signed-in extra) the real loader makes only one public read and shows no schedule suffix or login sentence. Demo fixtures are static viewer-shaped HTML: their served Drop Claim signal is still parsed as in iOS; signed-out UI tests instead supply public empty HTML with no private controls. Session switching is separately tested to drop the old snapshot before public reloading.

## Offline tests written, requiring Claude's run

- `AO3PromptMemeTest`: both fixtures and every claim/anonymous/tag/byline field; optional-tag exclusion, full description, any-type bare tag, malformed versus empty, negative ID fallback, filter matching/privacy, three-read opening/refresh and single-read page changes, missing/refused/verbatim schedule, required initial failure/retry, retained failed page, signed-out headers/counts, session changes and cancellation/duplicate suppression. Fake client implements POST by throwing and counts every GET/POST.
- `AO3PromptMemeScreenTest`: tall `w411dp-h1800dp` window, NATIVE graphics, 15-second waits, shared setup using `parseDispatcher = Dispatchers.Unconfined`; real Challenge Settings and collection Manage row callbacks, filters, owner/anonymous/claim states, exact browser destination, one-read page replacement/full description, retained failed page warning/retry, loading/initial failure words, signed-out empty/filter words, absent write controls, four themes at 2× font scale. Text checks use `!didOverflowHeight` and nonellipsized last line, never `hasVisualOverflow` for a short label.
- `DemoPromptMemeTest`: OkHttp demo interceptor with a socket interceptor that throws; both parsed pages, browser/native equality, explicit page-one equivalence, unchanged other collection fixture, terminal missing/unknown-page responses.
- Existing `AO3ChallengeSettingsScreenTest` updates meme Prompts to the native callback/route and verifies gift destinations and absence of a Prompts row. `AO3CollectionModerationScreenTest` only receives the new callback needed by its existing collection-detail host. Re-run 3ba parser/read-count tests after the shared settings extraction.

Suggested run after Claude's build: the three new test classes plus `AO3ChallengeSettingsTest`, `AO3ChallengeSettingsScreenTest`, `DemoChallengeSettingsTest` and `AO3CollectionModerationScreenTest`; then the normal Android gate. AppNavHost navigation is source-inspected and tested through callback hosts, not an executed full navigation graph here. Pull-to-refresh gesture and shell Back/tab visibility need emulator checks. Theme/large-font visual correctness is unclaimed.

## Work log / verification

Clean initial tree on `android/agent-gemini-3bi`. Read required repo docs and both 3ba/3be landing notes. Brief overrides TASKS claims, branch/commit/push/build instructions. No Gradle, Xcode, sign-in or AO3 contact. Implementation and offline tests are written; builds, JVM/Compose tests and all theme/accessibility screenshots must be run by Claude. No visual correctness or test-pass claim.

Executed only source inspections, `git diff --check` and inline Python standard-library HTML/whitespace/scope audits: fixture card counts 4/2, long summary 879 characters ending in the expected sentence; final scope/whitespace audit clean across 19 changed/new files; 26 new `@Test` methods counted in source (13 model/parser, 11 Compose, 2 demo). TASKS.md untouched, no `.orig` files; screen/state contain no write calls or write-repository dependency. This does **not** execute the Kotlin parser or tests. No build/compiler, commit, push, branch switch, helper script, stub, schema/backup change or reference-tree edit. Final patch remains uncommitted for Claude.

## Open questions

None after Claude's schedule answer. Owner question 16 remains outside this screen's scope.

**Landing note (Claude, 2026-10-07).** Landed with the owner's rule applied. Gate green (1,913
tests). It compiled and passed first time; nothing else was changed.

**The owner's rule of 2026-10-07, applied here** (DECISIONS; iOS T-359,
`PromptMemeView.readsSchedule`): the close date is asked for only for a collection's owner
(AO3 serves the settings form to owners alone and refuses moderators too), only until a date
is known, once per opening and once more per pull to refresh. So the reads are now:

- an owner's opening: three (the gift-exchange form, "not found"; the prompt-meme form; the
  prompts), as Codex counted;
- anyone else's opening: **one**, the prompts;
- a further page: one, for everyone;
- a refresh: one, or three for an owner who still has no date.

`readsPromptMemeSchedule` in `account/AO3PromptMemeState.kt` is the rule, with iOS's test
cases. The route carries `owner`; the collection page passes what it knows about the viewer,
Challenge Settings passes its own flag. A saving still on the table for both apps: this is
always a prompt meme, so the first of an owner's three reads is always "not found".

Both of iOS's ways in work: the collection page's Prompts row (any participant) and Challenge
Settings' Prompts row.

Seen on the emulator in airplane mode against the demo's local answers: by the debug route
(not an owner), Dark: the header "4 prompts · 1 unclaimed on page 1 of 2" with no close
date, the All / Unclaimed / Yours control, four cards (fandom, "+1", unclaimed or claimed,
title, text, the tag line cut to one line, the poster, "Claimed by you", "Posted
anonymously", "Fill it"), the footnote and the page bar; from Summer Prompt Meme's page (its
owner), Light: the same with "· open until Jun 30, 2026". Not seen: page 2, the two filters,
"Fill it" opening the browser, Sepia, OLED, large text, signed out (all in tests).

No Claim, Release or New prompt: the next brief. Its reads are settled too: one per page.
