# Brief 3be — Tag set, read only

## Reads counted first

Read from `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/TagSetView.swift`, especially `loadTagSet()`:

- Signed-in owner, moderator, or other viewer: **three sequential read attempts** per opening or refresh: `/tag_sets/{id}`, `/tag_sets/{id}/edit`, `/tag_sets/{id}/nominations`. The edit and nominations attempts are gated by being signed in and successfully constructing their authenticated requests, **not by ownership or moderator status**. If the first read fails, the two later reads are not attempted.
- The first read is required. Its failure shows **“Couldn't load tag set”**, the user-facing error, and **“Try Again”** instead of the sections. The edit read is optional: failure retains the entire public-page model. Success replaces that model with the edit-form model. The nominations read is optional: failure retains the current model's queue; success replaces only its queue. Neither optional failure gets a separate error message.
- Signed out: **one anonymous public-page read**, with no edit or nominations read, following iOS and Claude's answer below. Android uses the existing `AO3Client.get(url)` with empty headers; it never asks for authenticated headers in this case.
- These are explicit screen-opening reads, allowed by the networking policy's foreground explicit-navigation rule, subject to the existing client's host restrictions, pacing, cancellation, session scope and retry behavior. No live request was made. The iOS client methods each fetch one page and do not inspect pagination. Both parsers operate only on the supplied HTML. Android likewise reads no later page, even when the fixture advertises page 2. Shared client retry/overload behavior remains in force; these counts count logical page reads, not transport retries.

## iOS screen contract, read from the code

References read: `Features/Challenges/TagSetView.swift`, the tag-set models/URLs in `Models/AO3ChallengeModels.swift`, tag-set methods and parsers in `Services/AO3Client+Challenges.swift`, `Services/AO3ChallengeActions.swift`, CSRF preparation in `Services/AO3WriteActions.swift`, and the push in `Features/Challenges/ChallengeSettingsView.swift`.

The screen takes a tag set's own numeric `tagSetID`, not a collection slug. Its source comment identifies `collectionTagSets`, parsing Tag Set links on the collection profile, as the source of the ID. Challenge Settings and Challenge Settings Edit push it; the comment says both pass `isModerator = true`.

The header title is **“Tag set”**. Kicker is **“Tag set · moderator”** when `isModerator` is true, otherwise **“Tag set · owner”**. There is no third kicker for an unrelated viewer. Subtitle is **“{effective title} · {compact total} tags”**, including zero and one with the same “tags” word. Effective title prefers the passed nonempty title, then the loaded nonempty title, then **“Tag Set {id}”**. Total adds the four tag counts.

Every content section is rendered in the same order regardless of ownership, nominations being open/closed, or visibility:

1. **Ownership**: **Title** / effective title; **Visible to everyone** / disabled boolean toggle, defaulting true without a loaded model. There is no owner roster.
2. **Tags**, with total as section count: **Fandoms**, **Characters**, **Relationships**, **Additional tags**, each with its integer count (default zero). Every row opens the same native **Add tags** screen. That screen has kicker **Tag set**, title **Add tags**, subtitle effective title; four editable comma-separated fields, prefilled from the model: **Fandom tags to add**, **Character tags to add**, **Relationship tags to add**, **Additional tags to add**. Placeholders respectively **“Comma-separated fandom names…”**, **“Comma-separated character names…”**, **“Comma-separated relationships…”**, **“Comma-separated additional tags…”**. Its footnote is **“Enter each tag type as its own comma-separated list, as on AO3. If AO3 rejects a tag, Kudos shows which list it came from.”** It has a **Save tags** button and write feedback.
3. **Nominations**: **Nominations open** / disabled boolean toggle (default false); **Fandoms per person**, **Characters per person**, **Relationships per person**, **Additional tags per person** / integer limits (default zero).
4. **Review**: **Awaiting review**, **Approved**, **Rejected** / counts of the corresponding queue states. Queue groups sort by localized standard fandom order, placing the empty-fandom bucket last, titled **No fandom listed**. Rows show tag name and **Fandom**, **Character**, **Relationship**, or **Additional tag**. Unreviewed rows have **Reject**; approved/rejected rows have **Approved**/**Rejected** badges. Empty queue: **“No nominations yet”** and **“Nothing has been nominated to this tag set.”** Footnote: **“Before you approve a nominated character or relationship, it must be linked to a fandom. The review list groups nominations by fandom.”**
5. **At AO3**: **Associate nominations** / **Opens AO3**, opening the model's association address or `/tag_sets/{id}/associations`; **Delete tag set** / **Opens AO3**, opening `/tag_sets/{id}/edit` with destructive styling.

Loading replaces sections with **“Loading tag set…”** and a spinner, retaining the header. Failure retains the header and replaces sections with the failure panel described above. There is no special signed-out panel in this iOS view. Pull-to-refresh calls the same loader. There are no top action buttons defined by this view.

## Both iOS writes — recorded for the later brief, not implemented on Android

- **Save tags** constructs `AO3TagSetSave` with the four current strings (`fandomTagnames`, `characterTagnames`, `relationshipTagnames`, `freeformTagnames`) and calls `auth.saveTagSetFields(tagSet:fields:)`. While saving, it shows a spinner and disables the button. It clears previous notice/error first; success shows **“Tags saved.”** without a reload or local count update; failure shows the user-facing error and retains fields. The service requires sign-in, makes a fresh authenticated GET of `/tag_sets/{id}/edit` via `fetchCSRFPage` for the **meta csrf-token**, then sends one POST to the loaded model's `actionURL`. Missing action gives **“Couldn't find AO3's tag-set form.”** Fields: `authenticity_token`, nonempty model `_method` if present, and the four `owned_tag_set[tag_set_attributes][{fandom|character|relationship|freeform}_tagnames_to_add]` strings, including empty values. CSRF header and Referer use that edit page; `ajax: false`. No visibility, nominated flag or nomination limit is sent. The shared challenge verdict uses collection-write semantics, with fallback **“AO3 couldn't save that tag set.”**
- **Reject** calls `auth.reportRejectedTag(tagSetID:field:tagName:)`. While in flight all Reject buttons are disabled, with a spinner on the selected row. Success marks that nomination rejected locally, updating counts without a reload. Failure leaves its state intact and shows **“Couldn't reject “{tag name}”: {reason}”**. The service requires sign-in, makes a fresh authenticated GET of `/tag_sets/{id}/nominations` for the same meta token, and sends one POST to that nominations address. Fields: `_method=put`, `authenticity_token`, and `{field}_reject_{tagName}=1`; literal `[`/`]` in the tag name are replaced with `#LBRACKET`/`#RBRACKET` before form encoding. CSRF header and Referer use the nominations page; `ajax: false`. The fallback verdict message is **“AO3 couldn't reject that tag.”**
- Both writes are tap-only, each one fresh CSRF GET followed by at most one POST; no retry/coalescing and no read after success. Signed-out write failure is **“Log in to AO3 first.”** The shared `fetchCSRFPage` actually throws `AO3WriteError.noCSRFToken`, whose words are **“Couldn't prepare the request. Try again, or open the work on AO3.”** (the “work” wording is the actual iOS code here). Verdict priority: AO3 error text first; success flash or bare 3xx succeeds; other non-2xx uses the operation's fallback; plain unconfirmed 2xx gives **“AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”** Reject prefixes that reason with its tag-specific failure sentence; Save displays it directly.
- Android must render the four field values without editors or Save, and unreviewed nomination values without Reject. No replacement sentence is to be added. The entire Add tags footnote is omitted: its entry/rejection instructions are untrue on the read-only Android screen. The Review footnote is retained because it describes AO3's association dependency and the rendered grouping.

## Claude's answers (not owner decisions)

1. **Signed out:** Claude, who runs this port, answered to follow iOS: one anonymous GET of the public `/tag_sets/{id}` through the existing public-page client, with zero authenticated reads. This replaces the original zero-read signed-out test. The answer also described signed-in-only sections; the real iOS view has **no section visibility gate** for role/sign-in/open nominations/visibility. Under the brief's precedence rule, Android shows all five sections after a successful public read, using only values parsed from that page. No private edit data or dedicated queue is carried across sessions.
2. **Summer ID:** Claude authorized changing only Summer Prompt Meme's local profile tag-set link from 42 to **44**, retaining **Summer Prompt Tags**, and updating existing tests pinning its old ID. Winter remains 42/43. This permits three cases and one shared answer per address.

## Decided without asking

- Remote types/parser/URLs live together in `network/ao3/account/AO3TagSet.kt`; screen/state use the existing account repository. No new persistent model or separate HTTP client.
- Existing `ChallengeSection`, `ChallengeFootnote` and `ChallengeReadOnlyToggle` become package-visible and are used by both screens in their existing file; shared form and panel styling stays intact.
- The four tag-name fields are a local detail within the tag-set screen using already-loaded values. Its title reuses **Tag set**, omitting the unavailable **Add tags** action wording; field labels still identify the actual `tagnames_to_add` values returned by AO3. System Back and the shell's Material Back button return to the main tag-set view. Opening any of its four count rows makes no request.
- The existing SubjectChip gets a default-preserving `maxLines` option; this screen opts into wrapping. No shared line heights, spacing, colors or defaults change. New text has explicit line height. The screen uses `tokens.scopePalette`; Approved/Rejected/destructive accents derive from the existing theme palette hue function.
- Demo fixtures use original fictional names. The existing general tag-set fixture remains available to other addresses. 44/edit is a terminal local 403 with a refusal fixture; native and browser share the same refusal HTML. No replacement of a collection page fixture.

## Implementation and handoff

Initial tree was clean on `android/agent-gemini-3be`. Mandatory docs, the 3ba/3ay landing notes, iOS screen/models/client parsers/write services and actual Kotlin client/auth/UI symbols have been read. Implementation written:

- `AO3TagSet.kt`: one remote snapshot, field/state/nomination types, numeric URL builders and the iOS parsers. Counts use heading digits then category list length; additional count adds freeform plus additional just as iOS does. Form absence yields visible=true, nominations=false, zero limits and empty field strings. Empty or missing queue markup yields an empty queue as on iOS. Login/overload guards follow existing Android parsers. Nomination field/state derive from row text, with checkbox/radio parameter fallback, bracket decoding and field+name deduplication. Both parse forms leave `parentTagName` empty, just as iOS's code does; every parsed nomination therefore appears under **No fandom listed**, even when HTML contains a parent span.
- `AO3CollectionDetailRepository.getTagSet`: exactly the counted reads using the **existing** shared `AO3Client`, with its GET coordinator/pacing, header-qualified coalescing, retry/rate-limit and overload handling. Signed out calls the same public-client `get(url)` used by `AO3WorkMetadataRepository` with no headers; no authenticated-header lookup or raw request construction. Signed in uses the repository's existing authenticated headers. Optional failures retain the previous values. Generation checks prevent private responses being installed or later reads continuing after an observed session change. No later-page follow, background job, extra profile/read, write repository dependency or new transport.
- `AO3TagSetState`: opening-generation load state, busy guard and disposal cancellation; public reads are fenced too. The composable replaces state on authentication scope changes and drops private fields/queue/detail before a new public load. The existing client can finish a request already handed to its coalescer; this screen does not continue its read sequence or install that stale result.
- `AO3TagSetScreen`: five sections in iOS order, always present on success regardless of role/flags/sign-in. Shared Challenge sections, footnotes and disabled toggle rows; existing SettingsPanel, SubjectFormRow, separators/header and tag chips. The main palette is `tokens.scopePalette`; Approved/Rejected/destructive hues come from theme palette tokens. No stock Material chips/cards or new dependencies. Loading and required failure replace content with iOS's words. Tag-count taps show the four returned comma-separated field values as wrapping app chips with no further read; both back paths return locally. No editable fields, Save or Reject. New text has explicit line height and large-font rows/badges stack; header clearance is `statusBars + 76dp`. The shell supplies its usual Material icon Back button and there are no new top buttons.
- `Routes.AO3TagSet` / `AppNavHost`: numeric ID, independent served title and moderator argument. Challenge Settings rows call `onOpenTagSet(id, title)` and push `Routes.ao3TagSet(id, title, true)` as iOS does, including for an owner. No collection slug is used as the tag-set ID. The route has subject chrome and hides the tab bar. The only browser taps **inside** the screen are `/tag_sets/{id}/associations` and `/tag_sets/{id}/edit`, both in-app.
- Demo routing is shared between native HTTP and browser HTML. 44/edit is a local 403, optional read fallback keeps the Summer screen intact. Tag-set demo POSTs for these IDs are refused locally. Existing generic tag-set fixtures remain unchanged for other addresses. The 3ba follow-up note and its actual row/parser/demo tests now reflect native navigation and Summer 44.

No Gradle, Xcode, compiler, tests, emulator, sign-in or AO3 request was run. No commits, pushes, branch switches, TASKS.md edits, backup/schema changes or iOS edits were made. No helper scripts, stubs or `.orig` files were created. Claude's build/test run and theme/accessibility screenshot review remain necessary; no compile, test-pass or visual-correctness claim is made.

## Open questions

None currently. Both raised questions were answered by Claude, not the owner.

## Read-by-read policy accounting

| Read | Who / when | Policy basis |
| --- | --- | --- |
| `/tag_sets/{id}` | Every explicit opening, refresh or Try Again; authenticated when signed in, otherwise one anonymous read | Explicit foreground navigation to the selected public page; Claude's signed-out correction uses the existing public-page client |
| `/tag_sets/{id}/edit` | Signed-in viewers only, after the successful base read, regardless of owner/moderator relationship | Foreground authenticated surface of the explicitly opened tag set; sequential and optional, no collection/index sweep |
| `/tag_sets/{id}/nominations` | Signed-in viewers only, after the edit attempt, including refused edits | Foreground review surface of the explicitly opened tag set; one supplied page, no queue crawl or prefetch |

No policy exception or pagination cap is needed: iOS's three client methods do not walk pages. Permission refusal does not trigger retries in this screen. GET retry behavior stays in the existing client; no screen retry loop is added. Try Again and pull-to-refresh are explicit reader actions.

## Write-only controls and words omitted

- Four editable tag-name controls become their read-only values, displayed as app chips. No input/textarea, editing gesture, keyboard or write-state draft.
- **Save tags**, its busy spinner, success **Tags saved.**, and save error feedback are absent.
- Each **Reject** button and its busy spinner/queue-write error feedback are absent. Tag name and field remain; approved/rejected badges and the three review counts remain. No replacement unreviewed badge or sentence is invented.
- The four comma-separated editor placeholders are absent; empty values stay empty.
- The entire editor footnote quoted in the iOS contract is absent because entering and reporting rejected save fields are unavailable on Android.
- The field-detail title **Add tags** is omitted because it is an unavailable action; it reuses the existing **Tag set** title, with **Tag set** kicker and effective-title subtitle. This is a deliberate read-only wording departure. The field labels describe the returned tagname-to-add lists rather than claiming a save is available.
- Disabled **Visible to everyone** and **Nominations open** toggles remain disabled values, as on iOS. At AO3 rows still navigate to the same pages and do not execute a delete/association themselves.

## Demo routes and walkthrough (not executed here)

After Claude builds and installs the debug APK, use the existing fixture-only demo in airplane mode with `kudosDemoLibrary=true` and optionally `kudosDemoSignedIn=true`. These extras create local demo state, not an AO3 sign-in. `kudosDebugRoute` accepts these exact `nav:` values:

| Case | Direct route | Via Challenge Settings |
| --- | --- | --- |
| Every tag kind, open nominations, ID 42 | `nav:ao3-tag-set/42?title=Winter%20Exchange%20Tags&moderator=true` | `nav:ao3-collections` → Winter Exchange 2026 → Manage → Challenge Settings → Winter Exchange Tags |
| Closed nominations, invisible, ID 43 | `nav:ao3-tag-set/43?title=Snowbound%20Characters&moderator=true` | Same Winter path → Snowbound Characters |
| Edit refused, ID 44 | `nav:ao3-tag-set/44?title=Summer%20Prompt%20Tags&moderator=true` | `nav:ao3-collections` → Summer Prompt Meme → Manage → Challenge Settings → Summer Prompt Tags |
| Public signed-out case | `nav:ao3-tag-set/42?title=Winter%20Exchange%20Tags&moderator=false` | Launch the direct route without the signed-in demo extra |

Direct Challenge Settings routes are `nav:ao3-challenge-settings/winter_exchange?title=Winter%20Exchange%202026&owner=true` and `nav:ao3-challenge-settings/summer_meme?title=Summer%20Prompt%20Meme&owner=true`.

ID 42 signed in: title/count **Winter Exchange Tags · 7 tags**, disabled visibility/open toggles on, counts 2/2/1/2, limits 2/3/2/4. The dedicated first-page queue has five entries: three unreviewed, one approved, one rejected; all under No fandom listed. Its pagination advertises page 2, which is never fetched. Each category count opens the same four value groups (seven original fictional tags), without Save or Reject.

ID 43: **Snowbound Characters · 2 tags**, both toggles off, category counts 1/1/0/0, limits 1/2/0/0, empty review queue with iOS's two empty-state sentences. All sections and both browser rows remain present.

ID 44: **Summer Prompt Tags · 3 tags**, local edit GET refused with 403; public defaults remain (visible true, nominations false, limits zero, field values empty), while successful dedicated nominations replace the public queue with two rows. No edit-refusal error panel is shown. This is a collection maintainer viewing a tag set they do not own, not a signed-out session. Its `/edit` browser row displays the same local refusal HTML.

Signed out ID 42: one anonymous public page; 7 tags, visible true, nominations false, zero limits, empty field values and only the public page's one nomination. It never sees the owner edit values or dedicated queue. Role argument changes only the header kicker, following iOS's code.

## Offline tests written, not run

**22 new test methods** across `AO3TagSetTest` (8), `AO3TagSetScreenTest` (12), and `DemoTagSetTest` (2), plus an added real-navigation round-trip in `RoutesNavigationTest` and changes to existing 3ba tests. This is a source count, not passing tests.

- Parser tests cover every new fixture, all four categories/limits/field values, open/closed/invisible defaults, empty review, refused markup, row/parameter nominations, state/field mapping, bracket decoding, deduplication, parent-name omission, count fallbacks, blank title, trimmed textarea/input fallbacks and login/malformed pages.
- Memory-client state tests count owner and other-viewer opening/refresh reads with explicit Cookie headers; signed out counts one public read and zero authenticated ones. Required failure stops after one read; each optional failure retains prior values and allows subsequent reads. Session changes after each response and disposal suppress stale rows and later reads. The POST implementation throws, and every path asserts zero POSTs.
- Compose tests use tall windows, 15-second waits, `@GraphicsMode(NATIVE)` and a repository built with **`parseDispatcher = Dispatchers.Unconfined`**. They cover main content/browser addresses, no writable controls or extra field reads, shell Back, signed out, closed/empty, refused edit, optional queue failure, loading/failure/retry, logout discarding private fields, and all four themes at 2× font scale with an actual text-layout overflow assertion on a long fictional tag.
- Existing Challenge Settings screen tests now assert Winter IDs 42/43 and Summer ID 44 request native routes with title/moderator argument; other browser/external destinations and opening counts remain checked. Real NavController tests assert numeric-ID/title/moderator argument round trips, default values, title and shell chrome.
- Real demo interceptor tests install a downstream interceptor that throws before any socket. HTTP and browser HTML match at every served tag-set address, including refusal; shared collection profile links point to the three IDs; missing assets/unknown subpages fail terminally locally.

Claude must build Android debug, run these three suites plus `AO3ChallengeSettingsTest`, `AO3ChallengeSettingsScreenTest`, `DemoChallengeSettingsTest`, `RoutesNavigationTest`, the existing demo/client/auth-generation suites, and the normal full Android gate. All compile, parser/runtime/read-count/no-write/navigation/theme assertions still require that test run. Then inspect the demo in Light/Dark/Sepia/OLED and at accessibility sizes: all row destinations, four value groups and local Back, long names/chips/badges, both optional failures, signed-out public content, session transition privacy, and screenshots. No visual correctness is claimed.

## Checks actually performed

- Read actual Swift/Kotlin declarations and callers for all production APIs used, including public work metadata's `client.get`, collection authenticated reads, auth-generation handling, parser helpers, shell Back/chrome, theme tokens, rows/toggles/panels and chips.
- `git diff --check` passed. Standard-library source scans checked changed/new-file trailing whitespace and conflict markers, unique new type names across Kotlin source sets, project-owned symbol presence, and explicit line heights on each new Text call.
- Standard-library HTML checks confirmed fixture heading/nomination structure, open fixture's two checked controls, refused edit with no fabricated tag-set heading, and original fictional nomination rows. These are HTML structure checks, **not Kotlin parser execution**.
- Source comparison confirmed the Summer profile transformer changes only its 42 link to 44; the original shared Winter profile asset and TASKS.md match HEAD. No helper/stub/.orig files were left behind. Branch remains `android/agent-gemini-3be`; all work is uncommitted for Claude.

**Next step:** Claude builds/tests, reviews screenshots and commits after verification. **Open questions:** none; the signed-out correction and Summer demo address were answered by Claude, not the owner. No reader-stored data, Room schema or backup format changed.

**Landing note (Claude, 2026-10-07).** Landed with one change. Gate green (1,793 tests).

**The reads were counted first.** Signed in, one opening or refresh reads the tag set's page,
then its edit form, then its nominations, one after another, for any signed-in viewer (iOS does
not ask whether the viewer owns the set); a refused edit form or a failed nominations read
leaves the rest of the screen as it was. Signed out, one public read of the tag set's page and
nothing else. No second page of anything is read. Nothing is sent.

**Changed on landing: the Tags rows open nothing.** Codex made each count row open a page
showing the four "tags to add" boxes read-only. Those boxes are AO3's inputs for adding tags;
AO3 serves them empty, so on a real tag set the page would have been four headings with nothing
under them. On iOS the rows open the Add tags editor, which is the write; it arrives with the
write brief. The rows now show their counts and are not tappable, the chip component's new
`maxLines` option is gone again (nothing else needed it), and three screen tests were rewritten
to match (the rows have no click action; a long nominated tag wraps at double text size; a
logout reads only the public page). The model still carries the four values and iOS's field
labels for the write brief.

Seen on the emulator in airplane mode against the demo's local answers: tag set 42 in Dark and
Light (all five sections, "Approved" and "Rejected" badges, the footnote, both At AO3 rows),
43 in Sepia (closed, no nominations, iOS's two empty-state sentences), 44 in OLED (edit form
refused: the public values and the nominations stay, no error panel), and the path from
Winter Exchange 2026's Challenge Settings, which arrives with "Tag set · moderator". Not seen:
the signed-out case (covered by tests), where the two At AO3 rows lead, large text on the
emulator.

For emulator scripts: an `&` inside a `kudosDebugRoute` is cut off by the device's shell, so
`moderator=true` never arrived by `tapshot.sh`; go through Challenge Settings instead, or leave
the second argument off.
