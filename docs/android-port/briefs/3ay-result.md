# Brief 3ay — collection Maintainers

**Landing note (Claude, 2026-10-05).** This screen was finished once, against a lane that did
not yet have the Moderation screen (brief 3aw), and overlapped it: two parsers for the same
page and two demo answers for the same address. It was sent back to Codex to be merged onto
the lane (the section "Merge onto 3aw" below); the merged work is what landed. It applied
cleanly, compiled and passed; gate green (1,633 tests).

Both writes were read against iOS's `inviteMaintainer` and `leaveCollection` and against
`docs/AO3_NETWORKING_POLICY.md`: one fresh token read, then one request, sent only by the tap
(after the confirmation for leaving), the session checked on entry and after the read, never
retried. **Never run against AO3.**

Changed on landing: when the fresh token cannot be read, iOS says "…or open the work on AO3"
on this collection screen (it borrows the work screens' sentence). Android says "collection",
as its other collection actions do.

Copied from iOS and put to the owner (question 15): "Invite as: Moderator / Owner" changes
nothing in what is sent.

Seen on the emulator in airplane mode against the demo's local answers, in Light and Dark: the
screen from Manage › Maintainers (two owners, two moderators, "4 people"); an invitation
accepted ("Invitation sent to lanternkeeper.", the field cleared); one refused ("We couldn't
find an account named unknown_username.", said once, the field kept); Step down as owner
behind its confirmation, cancelled; on a collection with one owner, "Cannot Step Down"; and
the Moderation screen's maintainers row opening this screen, with its count now four.
Checked later the same day: confirming Step down closes the screen and returns to the
collection. Not checked: a moderator's view ("Leave collection"), large text.

## iOS reference, read from code before implementation

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift`, `Services/AO3Client+Collections.swift`, `Services/AO3CollectionActions.swift`, `Services/AO3WriteActions.swift`, and `Models/AO3CollectionDetailModels.swift`.

Header: kicker **“AO3 Account”**, title **“Maintainers”**, subtitle **“{collection title} · 1 person”** / **“{collection title} · N people”**. Empty title falls back to slug. Count includes only owners and moderators. No top buttons.

Sections in order:

1. **Owners**, omitted when empty. Each noninteractive row has an initial avatar, pseud, **“OWNER”** badge. The reader's owner row adds **“You · created the collection”**; other owners have no subtitle. There are no profile taps, remove controls or role-change actions.
2. **Moderators**, omitted when empty. Each noninteractive row has initial avatar, pseud, **“Can approve works, cannot delete the collection”**, **“MODERATOR”** badge.
3. **Invitations**, always present. Field **“Invite by username”**, placeholder **“Add a username”**; autocorrection/capitalization off, trailing alignment. **“Invite as”** choice: **“Moderator”** (default), **“Owner”**. Blank/whitespace-only username hides the send row. Otherwise **“Send invitation to {trimmed username}”**; during the request the same words with a spinner, disabled. No invitation confirmation. Success **“Invitation sent to {username}.”**, clears field and reloads participants. Failure keeps field and shows the error once. Footnote: **“AO3 sends the other account an invitation. Nothing changes until they accept it. An owner can remove a moderator, but the last owner can't step down.”**
4. **Leave**, always present. Owner sees **“Step down as owner”**, everyone else **“Leave collection”**, with exit icon and a busy spinner/disabled row during leave. Failure appears below the panel. Success dismisses the screen.

Last-owner tap (owner count <= 1): alert **“Cannot Step Down”**, **“You're the last owner. Appoint another owner before you step down.”**, **“OK”**. Sends nothing. Other owners: confirmation **“Step down as owner?”**, **“You will relinquish owner privileges for {title}. Another owner must maintain the collection.”**, destructive **“Step Down”**, **“Cancel”**. Moderator: **“Leave collection?”**, **“You will no longer be a moderator for {title}.”**, destructive **“Leave”**, **“Cancel”**. Unidentified current participant on confirm: **“Could not identify your maintainer record.”**

Owner vs moderator: only owner identification/subtitle, leave words/confirmation and last-owner guard differ. Both see both invite-role choices. No owner-only invitation/removal UI exists.

Loading replaces all content sections: spinner + **“Loading maintainers…”**. Failure replaces them with **“Couldn't load maintainers”**, user-facing error, **“Try Again”**. No special empty card: zero participants leaves Invitations and Leave visible, header says **“0 people”**. Pull-to-refresh uses the same loading/failure states.

Signed-out authenticated-request error is **“Log in to AO3 before using this feature.”** (`AO3AuthenticatedRequestError.notAuthenticated`). These two writes' missing-meta failure comes from the shared `fetchCSRFPage` → `AO3WriteError.noCSRFToken`: **“Couldn't prepare the request. Try again, or open the work on AO3.”** It says “work”, even on this collection screen; the iOS code wins here too. Username and role remain editable while a write is out, as on iOS; Android blocks all competing write taps as this brief requires.

**iOS code wins over the brief:** pending `Invited` records are fetched but never rendered here. The role choice changes local `inviteRole` only: `sendInvitation` calls `inviteMaintainer(slug:byline:)` without role. Android must likewise not invent a role field or a second promotion request. The footnote mentions removing moderators, but there is no such action in this screen. No unresolved question is needed to copy this explicit behavior.

## Reads, writes, verdict and policy

- Open / pull-to-refresh / Try Again: one authenticated GET `/collections/{slug}/participants`, `collectionParticipants` → `parseCollectionParticipants`. Rows come from `ul.participant.index li, li[id^=participant_]`; numeric ID from element ID or form action, pseud from byline/user link, role from selected `collection_participant[participant_role]` (suffix fallback), unknown role defaults Member. No paging, background reads or username lookup while typing.
- Invite tap: fresh authenticated GET of participants for `fetchCSRFPage`'s **meta `csrf-token`**; POST `/collections/{slug}/participants/add`, `authenticity_token`, `participants_to_invite={trimmed username}`; **no `_method`, no role**. CSRF header and Referer use that fresh page. After confirmed success, reread participants; after failure, no reread or optimistic mutation.
- Confirmed leave: fresh authenticated GET `/collections/{slug}` (show, **not profile or participants**) for the same meta token; POST `/collections/{slug}/participants/{current ID}`, `_method=delete`, `authenticity_token`; same CSRF header / show Referer. Success dismisses without another read.
- `collectionWriteVerdict`: AO3 error first, then success flash or bare 3xx succeeds; other non-2xx uses **“AO3 couldn't invite that maintainer.”** / **“AO3 couldn't leave that collection.”**; plain 2xx is **“AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”**

`docs/AO3_NETWORKING_POLICY.md` permits these explicitly opened pages and tap-only writes. Existing authenticated read client and `AO3WriteRepository` dispatch retain shared host checks, explicit cookies, User-Agent, pacing/coordinator and single-shot writes. Android will fence the session on entry, after preparation reads and after responses, and block repeat taps. No live AO3 access or sign-in is performed.

## Work log

Clean initial tree on `android/agent-codex-3ay`. Read 3as, 3at and 3av with landing notes, plus mandatory repository docs. In the original 3ay worktree, `3aw-result.md` and a Moderation screen were absent; Manage → Moderation opened items. The “Merge onto 3aw” section below records the subsequent integration on 3ay2. TASKS.md, branches, commits/pushes, iOS reference, backup format and Room remain untouched. Gradle/Xcode are prohibited here; compilation/test/runtime claims require Claude's pass.

## Implementation written

- Own `AO3CollectionMaintainersScreen`, wired from Manage → Maintainers through `Routes.AO3CollectionMaintainers` / `AppNavHost`. On the merged 3ay2 worktree, both Moderation maintainers rows use the same native `Routes.ao3CollectionMaintainers(slug, title)` route; the owner-bearing Moderation route and Approved-items destination are retained.
- `AO3CollectionParticipantsParser` in `AO3CollectionModeration.kt` is the one shared parser/model, preserving the landed String role API and iOS IDs, role selectors/fallbacks and row order. Like iOS, missing participant markup yields an empty list. No stricter empty-page heuristic or pagination is invented. `AO3CollectionDetailRepository.getCollectionParticipants` uses the existing authenticated read client, and `getModeration` calls it for the middle read of its three sequential requests.
- `AO3CollectionMaintainersState` captures the opening generation, owns invite/leave busy gates and dialogs, blocks Cancel/last-owner/duplicate writes, only installs refreshed server rows, and ignores responses after session changes or screen disposal. The composable replaces its entire state immediately on auth-generation changes, including private rows, text, notices and dialogs.
- `AO3WriteRepository.inviteMaintainer` / `leaveCollection` take fresh **meta** tokens from participants/show respectively and use the existing generation-fenced `postAuthenticatedInSession`, headers and collection verdict. No role or invitation override is encoded. Each action sends one POST, never retried. Error text is installed in one place; duplicate AO3 representations are not repeated. Invite success reloads; failure does not; leave success closes.
- Subject header, section rule headers, collection panels/separators, `SubjectFormRow`, the landed `SubjectTextFieldRow`, and `SettingsActionRow` are reused. The role menu occupies a separate row. Custom initial avatars and role pills use glass/collection palette tokens, with explicit text line heights. Large-font participant badges stack beneath the name; form controls use the shared accessibility layout. Dialogs use themed `AlertDialog`; destructive hue is token-derived and supplied to the existing settings row. No top buttons, Material chips/cards/default field chrome or new dependency.

## Local demo written

`DemoNetwork.kt` now has one `DemoCollectionParticipants` state/handler for accept, decline, invite and leave. The shared bundled Winter page is **`ao3_demo_moderation_participants.html`**, with reader owner **AO3_Reader** (101), owner **frostledger** (102), moderators **emberpost** (103) and **duskatlas** (104), membership requests **mapfold** (105) and **ashletter** (106), and pending **snowink** (107). All seven names/IDs are distinct. One meta token **demo-participants-token** serves that page; the deliberately wrong row input is not used. The obsolete `ao3_demo_maintainers.html` was removed.

`ao3_demo_maintainers_last_owner.html` still supplies Rare Pairs' sole owner. Winter's show/token comes from **`ao3_demo_moderation_show.html`**, through 3aw's existing `DemoCollectionForms`, preserving mutable reveal/anonymity and deletion answers and leaving Winter's `/profile` response alone. **`ao3_demo_maintainers_show.html`** is now used only for Rare Pairs' show/profile. Accepted participant writes mutate the one in-memory server page; membership decisions, invitation and leaving survive later reads together and reset on process restart. Missing assets are terminal local failures. All content/tokens remain original fictional filler.

After Claude builds/installs the debug APK, launch the existing local demo, in airplane mode:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true
```

This is a fixture-only demo session, **not a sign-in**; commands were not executed here. Account → Collections → **Winter Exchange 2026** → Manage → **Maintainers** shows two owners/two moderators and “4 people”. The pending snowink and the two membership requests are parsed but not displayed here, matching iOS. Manage → Moderation shows the two requests and “Owners and moderators” / “4”; either that row or “Invite a maintainer” opens native Maintainers. Type **lanternkeeper**, optionally choose Owner, tap **Send invitation to lanternkeeper**: success, cleared field and a refreshed pending record, still no extra maintainer and no pending-row UI. Either role sends the same username-only request, matching iOS.

Type **unknown_username**, tap send: original simulated AO3 refusal **“We couldn't find an account named unknown_username.”**, shown once although the demo response carries it twice; field/participants remain. Step down as owner → Cancel does nothing; Step Down succeeds and closes. Restart to restore the two-owner case. On Moderation, Accept **mapfold** or confirm Decline **ashletter**; subsequent Maintainers reads still show four people, and a successful invite does not resurrect a decided request. A confirmed step-down then leaves three maintainers on a refreshed Moderation page. Account → Collections → **Rare Pairs Week** → Manage → **Maintainers** shows “1 person”; Step down as owner opens Cannot Step Down / OK, with no token read or POST. The existing list already contains Rare Pairs Week; its profile now has a local fixture answer for that collection instead of Winter Exchange's generic title.

## Offline tests written, not run

21 new test methods across four test classes (state/parser/writes, real screen controls, demo interceptor, Manage navigation). This is the source count, not a passing-test count.

`AO3CollectionMaintainersTest`: fixture parsing/role and ID fallbacks/empty behavior; open/refresh reads and zero username lookups; fresh meta tokens, exact invite/leave endpoints/fields/override/header/generation; no POST on Cancel/last owner or a second tap; owner/moderator/unidentified-reader behavior; success-only invite refresh and leave dismissal; refusal once with unchanged field/participants; missing meta rejection; iOS verdict branches and transport errors with no retry; stale entry, session changes during token reads/POSTs and screen disposal; loading/empty/failure/signed-out/stale reads. Memory-only clients.

`DemoCollectionMaintainersTest`: real interceptor plus a downstream interceptor that throws before a socket; fixture reads, invite acceptance/refusal, wrong token/role rejection, fresh show token, step-down persistence, sole-owner refusal, unknown/missing-asset failures.

`AO3CollectionMaintainersNavigationTest`: the actual Manage row dispatches the native route rather than browser/moderation/settings; route argument encoding, title, subject-header and tab-bar chrome. Robolectric/Compose, no client.

`AO3CollectionMaintainersScreenTest` (same test file as the state suite): real screen/dialog controls with the memory client; owner Cancel versus confirmed leave, pending-row omission, Sepia at 2× font scale with role-menu/send separation and exactly one refusal text, OLED sole-owner alert/OK with zero extra requests. This adds assertions for drawing/interaction; they still require execution and do not replace screenshot review.

Compilation, tests and visual correctness are **not claimed**. Claude must build debug and run `:app:testDebugUnitTest` (the four new suites plus existing write-dispatch/session-generation, demo block, collection parser/items/form and navigation suites), then exercise demo Cancel/confirm, success/refusal, same-role-choice request behavior, only-owner alert and session changes. Check Light/Dark/Sepia/OLED and enlarged accessibility fonts on the emulator, including long usernames, role-menu/send-row tap separation and screenshots. No live endpoint compatibility has been verified; as on iOS, live writes remain an owner release gate, and this brief forbids AO3 contact.

## Checks actually performed and handoff

Read real Kotlin/Swift symbols used and their callers, including the shared dispatch fence and theme/form row implementations. Python standard-library HTML structure checks passed: seven unique Winter participant IDs with Owner/Owner/Moderator/Moderator/None/None/Invited and seven distinct pseuds, one sole-owner ID, exact synthetic meta tokens, row input tokens different from those meta tokens. This is **not** a Kotlin parser run. `git diff --check` passed. Final source review checked that all new text specifies line height and all screen/refresh/menu/dialog colors come from theme/subject tokens; rendering remains unverified.

No Gradle, Xcode, compiler, emulator, test suite, sign-in or AO3 request was run. No commits, pushes, branch switches, TASKS.md edits, backup/schema changes, iOS edits, helper scripts, stubs or `.orig` files. All changes remain uncommitted in this worktree for Claude's build, tests and review. The 3aw maintainers-row integration is now included; see the merge section below.

## Merge onto 3aw

Work resumed on `android/agent-codex-3ay2`, with 3aw already landed and 3ay applied by `git apply -3`. Read 3aw's landing note, including the injectable parser dispatcher and the instruction to leave shared component spacing alone. Resolved the five conflict files while retaining landed item-tab/Moderation routing, write functions, and reveal demo state. The two screens now share one participants parser/model/read and one Winter participants fixture/state. No commits, pushes, branch changes, Gradle, sign-in, AO3 contact or TASKS.md edits.

- Retained 3aw's participant model and parser location in `AO3CollectionModeration.kt`, with its membership/maintainer predicates and login/overload guards. Folded in iOS's exact prefixed-ID/form-action and role-suffix fallbacks from 3ay. `AO3CollectionParticipants.kt` now contains only role choices and shared URL builders; the landed Moderation URL helpers delegate to them. Maintainers uses the model's String role without a second participant type/parser.
- `getModeration` calls `getCollectionParticipants`; both use the existing `fetch` and injectable `parseDispatcher`. Production remains `Dispatchers.Default`; both Compose screen hosts explicitly pass `Dispatchers.Unconfined`, following 3aw's landing correction.
- Preserved 3aw's owner callback, queue tab parameter and all its routes. Added native Maintainers alongside them and wired both `onMaintainers` rows in production `AppNavHost`. The Moderation screen test host opens the real Maintainers screen and asserts the encoded native route for **both** rows; its earlier hub/Approved-items/confirmation/non-owner assertions remain.
- Combined the demo's participants into the seven-person Winter page listed above and one mutable handler. Renamed request 106 from emberpost to **ashletter** so moderator emberpost remains unique. Accept/decline/invite/leave compose on the same page. Root Winter show remains under `DemoCollectionForms`, with a fresh show meta token, so reveal/removal of anonymity/deletion behavior stays intact. Rare Pairs' last-owner fixture remains separate. Removed unused Winter `ao3_demo_maintainers.html` and updated both briefs' walkthroughs and both fixture/demo suites to the shared page.
- Kept all landed `AO3WriteRepository` methods byte-for-byte and added only `inviteMaintainer`/`leaveCollection` plus their import. Reused the one existing `requireCollectionSession` and `collectionWriteVerdict`; no second private helpers. Did not touch `ui/subject/SubjectComponents.kt` or add line heights to shared components.
- Tests retain the existing cases/guards and now assert four maintainers, the two distinct request names, exact seven-person fixture roles/IDs, and participant decisions/invites/leaving surviving in either order. Added two native-route screen assertions. No test or compilation run is claimed; Claude must run both briefs' state/screen/demo/navigation suites and the full Android gate, then verify all four themes and the two entry points on the emulator.

Merge checks actually performed: the requested `grep -rn '^<<<<<<<\|^>>>>>>>' android` returned no matches, and a source/asset scan also found no separator markers. No duplicate non-private top-level Kotlin class/interface/object declaration was found across Android source sets; specifically, the participant type, parser, role enum and demo handler each have one declaration. Source checks resolved project imports in all six affected test files and found their fixture references on disk. HTML structure checks confirmed the seven distinct IDs/names, four maintainers, two requests, one invitation and one participants meta token. Removing only the two new methods and their import from `AO3WriteRepository` produced a byte-for-byte match with HEAD; `SubjectComponents.kt` and TASKS.md also match HEAD. `git diff --check` and new-file whitespace checks pass. These are static checks, **not** Kotlin compilation, a test run or visual verification. The obsolete fixture is removed, no helper/stub/.orig file was left behind, and the branch remains `android/agent-codex-3ay2` with the changes uncommitted.
