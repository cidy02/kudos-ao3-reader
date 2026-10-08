# Brief 3bl — challenge sign-up form and Submit sign-up

## iOS first: hidden-field audit and payload risks

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:
`Features/Challenges/ChallengeSignUpView.swift`, `PromptTagsEditorView.swift`,
`PromptMemeView.swift`, `ChallengeSignUpsView.swift`,
`Features/Account/AO3CollectionDetailView.swift`, `Services/AO3Client+Challenges.swift`,
`AO3ChallengeActions.swift`, `Models/AO3ChallengeModels.swift`,
`AO3ChallengeScreenModels.swift`, and `KudosTests/AO3ChallengeFormTests.swift`.

**A4 is correct.** `parseChallengeSignUpForm` collects every hidden input except
authenticity_token into hiddenFields. `challengeSignUpParameters` never reads
hiddenFields. The reference fixture `ao3_challenge_signup.html` contains prompt IDs
but does not contain a nested tag-set ID; it cannot disprove A4. The richer Android
existing fixture below explicitly serves that ID. Android preserves every served
control with the 3bb snapshot and replays successful controls not set by the iOS
branch. No live AO3 HTML was read; whether omission creates another tag set or is
refused is a server-side risk, not an observed outcome.

| Served control / condition | Browser | iOS encoder | Can change an untouched sign-up? Android decision |
|---|---|---|---|
| challenge_signup[requests_attributes][N][tag_set_attributes][id], offers equivalent | Hidden ID | Omitted, despite captured hiddenFields | Risk: nested update loses identity. Replay exactly. |
| Other unknown hidden inputs, arrays and repeated names | Every successful pair, in order | Omitted | Risk: identity/state/multiplicity lost. Replay exactly. |
| Repeated modeled scalar/text/checkbox name | All successful values; Rails last scalar | First input/checkbox/selected option interpreted, one modeled pair emitted | Risk: a malformed/duplicated modeled control can change untouched state. Follow iOS for modeled names; raw snapshot remains whole. |
| Unknown text/textarea/select/checkbox/radio | Successful values (checkbox hidden twin plus checked value) | Omitted | Risk: unmodeled state omitted. Replay exactly. |
| utf8 | Checkmark | Omitted | Encoding sentinel, no sign-up attribute effect. Replay. |
| commit (chosen Submit) | Served label | Omitted | May select server behavior; the fixture Submit matches native Save intent, but no live metadata effect is verified. iOS omits it; Android replays the first enabled submitter exactly. |
| Four *_tagnames per prompt | Original comma string | Trimmed nonempty components joined with comma, no space | Delimiter spacing only in fixtures; intentional iOS representation. |
| anonymous, any_fandom, any_character, any_relationship, any_freeform, _destroy | Hidden 0 then checked 1, or 0 | One scalar 0/1 | Same Rails last-scalar value for ordinary twins. |
| title, description, url left empty | Empty | Empty, always | Same. No local URL/title/length validation. |
| Served title/URL/pseud input whitespace | Literal input value | Trimmed by inputValue | Risk: untouched surrounding whitespace changes. Follow iOS; no extra test normalization. |
| Served description whitespace/line breaks | Literal textarea value | SwiftSoup text().trim(), normalized text | Risk: untouched formatting can change. Android uses Jsoup text().trim() to match; edited text is posted literally. No whitespace round-trip normalization. |
| Prompt id positive / draft negative | Served id / no id | Positive id only | Draft identity is local. Omitted served controls still replay. |
| Nested indices not contiguous | Original indices | Enumerated 0…N | iOS reindexes; Android remaps replay by prompt's original index to the encoded index so IDs follow their prompt. |
| pseud select without explicit selected | First option | First option (selectedOptionValue fallback) | Same; no pseud picker drawn. |
| Modeled field absent or disabled | Nothing | Default/empty fields still emitted | Potential replacement/refusal; follow iOS for modeled fields, retain raw snapshot. |
| Form/meta token disagree | Served form token | Meta token preferred; Save replaces with fresh meta | Preparation consistency risk, no attribute effect. Follow iOS. |

## What iOS actually draws (1ca)

Collection Manage → **Your Sign-up** is present when the dashboard has a sign-ups
link and auth.isLoggedIn; it is independent of maintainer status. Prompt meme's
bottom **New prompt** NavigationLink opens the same screen, without existing ID.
The sign-ups list also opens it with the own ID matched against the login; that
list entry point is not part of this brief. Both requested entry points normally
GET signups/new (AO3 may redirect an existing participant to edit).

Header in every case: kicker collection title (slug fallback), title **Your sign-up**.
New/existing and closed have no separate header wording. With printed limits:
`Request {live} of {allowed} · Offer {live} of {allowed}` for gift exchange;
requests only for meme. Without limits: `0 requests · 0 offers`, singular at one.
No closed-state heading exists in this iOS view. It reads the form once, and failure
shows **Couldn't load sign-up**, UserFacingError's message and **Try Again**.
No schedule, collection, tag-set or account-pseud enrichment read exists here.

Ordered content: header; success notice; general errors; loading/failure OR
request count error, each **Request N** heading, that prompt's tag error, request
tags panel, description panel; requests footnote; **Offers**, offer count/tag
errors, each offer summary row then **Add an offer**, offers footnote; existing
only **Withdraw** heading and **Withdraw sign-up** row; bottom actions
**Add request**, **Submit sign-up**. Android omits the entire Withdraw section.

Requests panel: **Fandoms** → joined names / **None chosen**; **Relationships**,
**Characters**, **Additional tags** → **Optional** or `{count} chosen`; all four
open the same Tags sheet. Then **Any of these is fine** switch, caption
**Any relationship matches, not only the ones chosen**; this sets any_relationship
only. Description label **Prompt**, placeholder **Describe what you would love to
receive…**, footer **Visible to your recipient only**, count `{characters} / 1000`.
1000 is displayed, not enforced or validated. Offer summary is first fandom's bare
title or **Any Fandom**, followed by ` · N tag(s)` counting relationships,
characters and freeforms. Offers open the same tags editor; no offer description
editor exists on this screen.

Tags sheet header: **Request N** / **Offer N**, **Tags**, **Comma-separated tag names**;
sections **Fandoms**, **Relationships**, **Characters**, **Additional tags**;
placeholders **Good Omens, Supernatural**, **Aziraphale/Crowley**,
**Aziraphale, Crowley**, **slow burn, domestic**; **Done** writes split comma names,
trims each, drops empties. All four kinds are drawn regardless of challenge limits.
There are no offered tag-set choices or autocomplete reads in iOS. Android reuses
the work form's editor components locally, with no autocomplete repository or
recent-tags store; its field accepts comma-separated names with the iOS placeholder.

The model also preserves/sends title, URL, anonymity, any_fandom, any_character,
any_freeform, offer description and _destroy; **iOS draws no controls for these**.
No title/URL placeholders or length limits can therefore be claimed. Restrictions
come only from the form headings (`Requests (1 - 3)`, `Offers (2)`) and each tag
label's `(low - high)` / `(exact)` range. A missing type in a present prompt block
allows zero; no prompt labels means no tag validation. New blank form gets one
request if none; one offer if none and takesOffers. Add request/offer disabled at
allowed counts; drafts use negative IDs below the minimum in both lists. **There
is no remove prompt control** in this iOS view/editor. _destroy remains modeled
and encoded for already served destroyed prompts; no Android removal action added.

Requests footnote: `The challenge asks for L to H requests[ and L to H offers] per
sign-up.` when limits exist; `Each request takes ….` for printed nonzero tag ranges
in fandoms, characters, relationships, additional tags order; finally **Kudos checks
these limits before you submit your sign-up.** Offers footer: **You can edit your
sign-up until sign-ups close. After they close, you can only withdraw it.**

## Exact local validation

Clears prior errors, ignores destroyed prompts, checks counts when printed, then
each request and offer's tags in fandom/character/relationship/freeform order.
Count messages: `This challenge requires at least N request(s).`,
`This challenge allows at most N request(s).`, same with `offer(s)`.
Per-prompt messages prefixed `Request N: ` / `Offer N: ` and joined with a space:
`Choose fandoms or “Any”, not both.` (substitute type plural);
`This challenge takes no fandoms.`; `Choose exactly N fandoms (you have C).`;
`Choose L to H fandoms (you have C).` Types: **fandoms**, **characters**,
**relationships**, **additional tags**. Any with zero tags bypasses the range.
No validation of description, URL, title, anonymity, pseud, 1000 characters,
required description, or allowed_any is implemented in this iOS method.
Failed local validation sends nothing, including no token read.
The challenge error enum also defines **That sign-up doesn't meet this challenge's
limits, so nothing was posted.** (invalidForm) and **Couldn't prepare the request.
Try again, or open the challenge on AO3.** (noCSRFToken); this Save method does not
throw either case. Its local errors return the checked form, and its token helper
throws the shared AO3WriteError with **work** in the sentence instead.

## Reads and Save, in order

**Count first: one opening = one requested authenticated form GET; signed out = zero.**
These are client read calls; AO3 redirects (new → existing edit), and the shared
transient GET retry policy, remain transport behavior exactly as on iOS. No
independent follow-up reads or per-screen retry loop are added.
No extra tag-set/schedule/profile read. Without existing ID:
`/collections/{slug}/signups/new`; with ID:
`/collections/{slug}/signups/{id}/edit`. Auth request construction failure does not
fall back to anonymous. An AO3 refusal must not be asked twice on refresh/retry;
Android remembers an attempt and makes refused/login/closed failures terminal for
that opening. No entry point supplies a known closed/no-own signal in the inspected code; no
additional private read is made to discover one. After AO3 refuses this opening,
that state is terminal and no second probe is allowed. This is the sparing choice
where the brief asks for a closed-state decision that iOS does not provide. Collection.closed is not signup_open and must not be
used as a sign-up permission signal. This screen has no trusted schedule data on
entry; server refusal is the authoritative fallback.

Save is iOS **Submit sign-up**, despite the brief calling it Save:
1. Check signed in (`Log in to AO3 first.`); validated() returns errors without sending.
2. GET referer: new form URL or edit URL based on parsed signUpID, not the entry ID.
   fetchCSRFPage requires fresh nonblank meta csrf-token. Missing uses AO3WriteError's
   **Couldn't prepare the request. Try again, or open the work on AO3.**
3. Replace token on validated draft; do not reparse fresh page over user's edits.
4. POST captured action (AO3 trusted host only), with form override when present.
   If the supplied action is empty, iOS falls back to `/collections/{slug}/signups`
   for new or `/collections/{slug}/signups/{id}` for existing; Android does the same.
   Body: authenticity_token=fresh; _method=served nonempty; pseud_id=parsed nonempty;
   requests then offers enumerated from 0. Each positive id; title, description,
   url verbatim including empty; anonymous + four any flags + _destroy as 1/0;
   four tag_set_attributes *_tagnames joined by comma in fandom, character,
   relationship, freeform order, empty lists sent as empty. Android then replays
   every successful unmodeled control exactly, preserving multiplicity and order.
5. Headers: shared explicit Cookie and UA; Content-Type application/x-www-form-urlencoded;
   X-CSRF-Token=fresh, Referer=form GET address; ajax:false (no X-Requested-With).
   Shared trusted redirect/session fences and pacing remain in force.
6. First parsed returned form errors win; then shared writeErrorMessage; then
   flash notice or 300…399 confirmation. Page without notice/redirect is unconfirmed:
   **AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.**
7. Confirmed result replaces form when parseable, otherwise keeps posted draft;
   displays **Sign-up submitted successfully!**; no dismiss or verification GET.
   Refusal retains typed form and errors; no success notice. Android retains every
   typed value even if AO3's returned form differs, attaching its errors instead.
   Pending token/POST do not replace the form. Never retry/coalesce the POST.

Policy: opening GET is foreground explicit navigation to the participant's own
form (authenticated-read scope); token GET is the **Writes** CSRF preparation read;
POST is the **Writes** single-shot, non-coalesced dispatch. **403** never retried,
**429** surfaced on writes, shared read Retry policy stays centralized. No background
read, private crawl, account-list enrichment, or local-work mutation on errors.

## iOS encoder and verdict, quoted

```swift
    static func challengeSignUpParameters(_ form: AO3ChallengeSignUpForm) -> [(String, String)] {
        var params: [(String, String)] = [("authenticity_token", form.csrfToken)]
        if let method = form.httpMethodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        if !form.pseudID.isEmpty {
            params.append(("challenge_signup[pseud_id]", form.pseudID))
        }
        params.append(contentsOf: nestedPromptParameters(form.requests, key: "requests"))
        params.append(contentsOf: nestedPromptParameters(form.offers, key: "offers"))
        return params
    }

    private static func nestedPromptParameters(
        _ prompts: [AO3ChallengePrompt], key: String
    ) -> [(String, String)] {
        var params: [(String, String)] = []
        for (index, prompt) in prompts.enumerated() {
            let p = "challenge_signup[\(key)_attributes][\(index)]"
            if prompt.id > 0 { params.append(("\(p)[id]", String(prompt.id))) }
            params.append(contentsOf: [
                ("\(p)[title]", prompt.title),
                ("\(p)[description]", prompt.promptText),
                ("\(p)[url]", prompt.url),
                ("\(p)[anonymous]", prompt.isAnonymous ? "1" : "0"),
                ("\(p)[any_fandom]", prompt.anyFandom ? "1" : "0"),
                ("\(p)[any_character]", prompt.anyCharacter ? "1" : "0"),
                ("\(p)[any_relationship]", prompt.anyRelationship ? "1" : "0"),
                ("\(p)[any_freeform]", prompt.anyFreeform ? "1" : "0"),
                ("\(p)[_destroy]", prompt.destroy ? "1" : "0"),
                ("\(p)[tag_set_attributes][fandom_tagnames]", prompt.fandoms.joined(separator: ",")),
                ("\(p)[tag_set_attributes][character_tagnames]", prompt.characters.joined(separator: ",")),
                ("\(p)[tag_set_attributes][relationship_tagnames]", prompt.relationships.joined(separator: ",")),
                ("\(p)[tag_set_attributes][freeform_tagnames]", prompt.freeforms.joined(separator: ","))
            ])
        }
        return params
    }

```

```swift
        if let parsed = try? AO3Client.parseChallengeSignUpForm(body, slug: form.collectionSlug),
           !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
            return parsed
        }
        if let error = AO3Client.writeErrorMessage(in: body) {
            var invalid = posted
            invalid.generalErrors = [error]
            return invalid
        }
        if AO3Client.writeSuccessMessage(in: body) != nil || (300...399).contains(status) {
            return (try? AO3Client.parseChallengeSignUpForm(body, slug: form.collectionSlug)) ?? posted
        }
        _ = html
        throw AO3ChallengeWriteError.unconfirmed
    }
```

## Withdrawals — read, neither built

While open: GET `/collections/{slug}/signups/{id}/confirm_delete` for meta token,
POST `/collections/{slug}/signups/{id}` with _method=delete and authenticity_token;
non-AJAX headers; single-shot; shared collection verdict fallback **AO3 couldn't
withdraw that sign-up.** View confirms **Withdraw this sign-up?**, buttons
**Withdraw Sign-up**, **Cancel**, message `Withdrawing removes your requests and
offers from {title}.`; success **Sign-up withdrawn.**, dismiss; failure general
error keeps form. All those controls are omitted here.
After close: withdrawSignUpAfterClose delegates reportAssignmentDefault: GET
`/collections/{slug}/assignments?fulfilled=true` page 1 for token; POST
`/collections/{slug}/assignments/{assignmentID}/default` with _method=patch and token,
fallback **AO3 couldn't record the default.** AO3 refuses sign-up destroy after
close; this view does not implement/promote the after-close assignment default.
No withdrawal client method, screen control or demo write added on Android.

## Decided without asking

- Keep single task in this clean worktree on android/agent-gemini-3bl; explicit brief
  overrides TASKS claim, branches, commit/push and build rules. No iOS changes.
- New remote form model/parser in network/ao3/account; load in existing collection
  repository, Save in existing AO3WriteRepository; screen/state in account. No schema.
- Reuse 3bb's served-control snapshot/browser semantics instead of another parser.
- Preserve unmodeled nested tag_set_attributes[id] in requests/offers, commit=Submit
  from the first enabled submitter, and every other successful unmodeled control:
  deliberate difference from iOS, mandated by brief.
- Returned refusal errors attach to the submitted draft, keeping typed values and
  the whole opening snapshot as required; confirmed parseable forms remain authoritative.
- UI action says Submit sign-up; tags have no fetched tag-set choices; no URL/title/
  anonymity or remove editor. iOS code wins over broader wording in the brief.
- Original fictional Lantern Harbor / Tideglass tags and prompt prose only; use existing
  winter_exchange/summer_meme addresses and assets; local Save refusal triggered by
  description containing Uncharted Lantern. Relaunch resets interceptor state.

## Open questions

- Without an entry-state signup-open signal, fetching one extra schedule would violate
  iOS read count. Use no extra read and remember authoritative refusal; collection closed
  is a different flag. No known-refused repeat within the opening.
- iOS doesn't enforce 1000 or expose most modeled prompt fields; use its smaller UI and
  exact validations, keep hidden/unshown fields intact. Server limits remain authoritative.
- Reference fixture does not include a tag-set ID. Preserve it in richer local fixtures;
  server behavior of iOS's omission remains unverified. No AO3 contact authorized.

## Work log

Read 3bi/3bk/3bg and their landing notes and 3bb, required repo docs and actual Kotlin
symbols. Ponytail skill applied for component/parser reuse. No builds, sign-in or network.
Implementation written; runtime and visual assertions require Claude's test run.

## Android implementation and preservation boundary

- `network/ao3/account/AO3ChallengeSignUp.kt`: full in-memory form; iOS prompt
  fields, count/tag limits, stable draft IDs, exact validation/encoder, trusted
  AO3 action, captured controls. Existing `AO3WorkFormParser.servedControls` is
  factored out without changing its behavior; successfulValues has a string/null
  submitter overload (the existing work-action overload delegates to it).
- `AO3CollectionDetailRepository.getChallengeSignUp`: one authenticated selected
  form read. No tag-set, schedule, profile or pseud-list enrichment. Signed out
  returns before a client GET. Session-generation fencing in repository/state.
- `AO3WriteRepository.saveChallengeSignUp`: existing authenticated transport;
  local validation, fresh meta token, exact modeled payload followed by replay,
  one session-fenced POST; iOS verdict order. Shared writeErrorMessage reused,
  including #error li. Multi-reason returned forms retain their whole general list;
  without a form, iOS's shared parser takes the first reason. Unconfirmed is always
  AO3CollectionFields.UNCONFIRMED, including a page returned without a notice.
- `account/AO3ChallengeSignUpState.kt`: one opening attempt, no simultaneous Save,
  frozen edits while pending; typed draft/errors retained on refusal; only confirmed
  response replaces the draft. Terminal refused/login/parse/validation loads disable
  Try Again and refresh cannot repeat them. A forbidden token preparation also disables
  further Save for the opening. Transport failures allow an explicit retry.
- `account/AO3ChallengeSignUpScreen.kt`: lazy requests/offers (offers keep one continuous panel using the work tags editor's
  writingSuggestionPanel end caps/separators); challenge headings,
  rows/panels/footnotes; collection primary action styling; all new Text with line
  heights; scopePalette; refusal red from SubjectPalette.fromHue(0.0, tokens.theme).
  Input/keyboard insets, statusBars + 76dp, four local comma fields in Tags, Material
  Done icon button in shell. ProvidePushedShellChrome registers each replacement
  screen, including Back from Tags, without manually restoring shared chrome.
  Bottom actions share a row normally and stack at accessibility scale. Request
  short tag counts are trailing content; long fandom/offer values wrap. Android ICU
  grapheme count is the platform counterpart of Swift String.count; count remains
  advisory. No withdrawal/remove/title/URL/anonymity editor added.
- Collection Manage now collects auth state and only shows Your Sign-up signed in;
  that row and signed-in Prompt Meme's New prompt navigate the new native route.
  Restored iOS's complete meme footer now that New prompt is available. Existing
  Claim/Release behavior and schedule-attempt rules are unchanged.

Preservation uses the names **actually emitted** by the iOS branch, as 3bb:
unknown successful controls replay exactly; unchecked/disabled/unnamed controls,
options and unchosen submits remain in the snapshot but do not submit. Snapshot
keeps browser defaults, external form-ID controls, duplicate and array controls,
raw text and attributes. Explicit and replay name sets are disjoint. Only nested
indices are remapped to follow the same prompt when iOS enumerates it; no UI removes
or reorders a prompt. The served nested tag-set ID therefore remains attached to
its original prompt. The first enabled served submitter is the native Submit counterpart (browser implicit-submit rule); its name/value replay exactly, including named commit. Other submitters are excluded by control identity, even if they share a name. No fresh-page unknown values overwrite typed opening data.

## Local demo routes and taps

Launch the existing fixture-only demo with `kudosDemoLibrary=true` and
`kudosDemoSignedIn=true`. This is a local fake session, not an AO3 sign-in; keep
airplane mode on for review. Pass each route as **one quoted argument** to the
existing debug navigation entry point:

- `nav:ao3-challenge-sign-up/winter_exchange?title=Winter%20Exchange%202026`
- `nav:ao3-challenge-sign-up/winter_exchange?title=Winter%20Exchange%202026&id=4`
- `nav:ao3-challenge-sign-up/summer_meme?title=Summer%20Prompt%20Meme`
- To exercise entries: `nav:ao3-collection-detail/winter_exchange?title=Winter%20Exchange%202026`
  → Manage → Your Sign-up; `nav:ao3-prompt-meme/summer_meme?title=Summer%20Prompt%20Meme`
  → New prompt. Neither tap POSTs.

Three original form assets: ao3_demo_signup_winter_new, winter_edit, summer_new.
Winter uses The Lantern Archipelago / Cloudbound Courier, Mira Vale / Oren Reed,
Mira Vale/Oren Reed, Winter Letters / Found Family from the existing tag-set 42/43
fixtures. No tag-set GET is added to offer choices iOS never offers. New/edit have
one request and one offer; Summer requests only. Existing id 4 has prompt IDs
21/22 and tag-set IDs 421/422, plus URL/title preserved but undrawn. Rich unknown
controls exercise exact replay, including textarea whitespace, duplicates, arrays,
select defaults, checkbox twins, radio, disabled and unnamed controls.

Tap Fandoms/another tag row → Tags → edit comma-separated fields → Done; edit Prompt;
Add request/Add an offer enforce the printed max counts; fill each new request's
required fandom before submitting. Submit sign-up confirms with **Sign-up submitted
successfully!**, retains typed data, and installs a local authoritative existing
form (ID 4). Subsequent Save uses edit token URL; no automatic reload. For refusal,
type **Uncharted Lantern** in a request Prompt and Submit: both reasons shown:
**Description contains Uncharted Lantern, which is not accepted for this challenge.**
**Please revise your prompt and submit again.** Typed fields remain. Clear that
phrase and Submit for confirmation. The saved server form is unchanged on refusal.

`DemoNetworkRoutes` shares initial form addresses between browser/native; existing
sign-ups listing and other collections retain their prior answers. Demo save state
belongs to its interceptor and resets with the process. Browser escape hatches are
read-only initial fixtures as in the existing demo, not a second editable server.
Saved/refused answers use their dedicated local assets. No withdrawal is accepted;
unknown sign-up subpages/missing assets are terminal local failures, never sockets.

## Tests written, execution deferred

Four new suites, **26 @Test methods** (parameterized loops cover each kind):
AO3ChallengeSignUpTest (7), AO3ChallengeSignUpWritesTest (8),
AO3ChallengeSignUpScreenTest (7), DemoChallengeSignUpTest (4).
All use local fixtures/fake clients or a local interceptor followed by a throwing
socket guard. Existing Prompt Meme screen noWrites assertion is updated to permit
the newly requested navigation button, still forbidding a Submit on the listing
and asserting zero POSTs.

Parser covers all fixtures/limits/known and unknown fields, nested ID remap,
external controls, trusted-action rejection, minimum drafts and error lists.
Independent DOM round-trip compares modeled fields in meaning with **only**:
(1) checkbox hidden twins by Rails last scalar; (2) comma-list spacing around commas;
(3) chosen submit by name presence. Unknown remainder compares exactly, preserving
value/multiplicity/order; explicit/replay name sets are disjoint. No general whitespace,
absent/empty, array, date, case, sorting or index normalizer is added. iOS emits no named submit for this save; Android deliberately preserves the first
enabled submitter and the independent browser oracle chooses that same browser
implicit-submit control. Its exact served name/value is in the replay comparison;
commit's iOS omission is inventoried, not disguised by normalization.

Changed-field assertions pin both prompt kinds' ID/title/description/URL/anonymous/
any flags/destroy/tags with exact ordered output, Unicode, empty values, and negative
draft IDs not posted. All count and all tag validation branches assert iOS words,
including exact/ranged counts, absent/zero types, Any conflict, Any-only, destroyed
prompts and absent limits. No artificial description/URL/title validation exists.

Reads/writes cover signed-out zero reads, one opening/no POST, repeated attempt guard,
refusal terminal behavior, new-page returning existing ID, correct new/edit token
referer, one token GET/one POST, all verdicts/error precedence, pending token/POST
with unchanged form and no duplicate Save, refusal retaining typed values,
missing-meta/token403/post429, session changes, and shared HTTP wire encoding/UA/
Cookie/headers with one POST even on 429/503. No post-confirmation read expected.
Demo covers three shared initial answers, accepted/refused Saves, both reasons,
no server mutation on refusal, process reset, missing assets and no withdrawal.

Compose tests use @GraphicsMode(NATIVE), a tall w411dp-h1800dp window and 15s waits:
both entry callbacks, one extra form GET and zero writes, request-only meme, existing
form without Withdraw, Tags shell registration/back, refusal values, success notice,
signed-out failure, and Light/Dark/Sepia/Oled accessibility action label height/last
line (no hasVisualOverflow assertion). Full visually faithful layout is **not claimed**.

## Verification and handoff

Performed: actual Swift/Kotlin symbol and caller inspection, route/header integration,
fixture inventory (new Winter 59 controls; existing Winter 64, with both nested tag-set
IDs; new Summer 38), delimiter typo checks, diff/whitespace review. No Gradle, Xcode, emulator, sign-in, network,
commit, push or branch switch. TASKS.md, iOS reference, Room and backups unchanged.
No scripts, stub files or .orig leftovers created. Changes remain uncommitted here.

Claude must compile Android debug/release and test sources, run the four new suites
and the existing WorkForm parser/encoder tests (shared snapshot refactor), Prompt Meme
screen/action/demo suites, CollectionDetail/Moderation routes and normal networking/
session regressions. Every behavioral assertion above needs that runtime test run;
passing tests and compilation are not claimed. Review airplane-mode demo in all four
themes at normal and accessibility scales, long fandoms/offers and keyboard focus,
Tags → Done/Back shell chrome, pending/refused Save and visible errors. No live AO3
verification is authorized. Existing iOS writes likewise remain live-unverified.
