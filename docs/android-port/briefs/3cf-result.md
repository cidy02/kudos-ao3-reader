# Brief 3cf — Challenge Settings edit (unbuilt handoff)

## iOS first: R8 corrections

Read the actual Swift under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, unchanged: `ChallengeSettingsEditView.swift`, `ChallengeSettingsEditSections.swift`, `ChallengeSettingsView.swift`, `AO3ChallengeModels.swift`, `AO3ChallengeScreenModels.swift`, `AO3Client+Challenges.swift`, `AO3ChallengeActions.swift` and collection actions called by Save.

R8's first section is unreliable. The code wins:
- No top Save, Cancel or Done. One bottom **Save changes**, enabled for owners with a form, even without changes; disabled while saving. Back leaves. No discard confirmation.
- The dialog is **Reveal now?**, not “Save and Reveal”. **Save and reveal** / **Cancel**. Message: “Turning off Unrevealed makes every work visible. Turning off Anonymous shows every creator. You can't reverse either change in Kudos.” It is asked only when a loaded collection's unrevealed or anonymous switch changes from true to false, on tapping Save. Dates do not trigger it. No request before confirmation.
- Save is a challenge POST, then a separate collection POST only if one of four collection switches changed. This contradicts the brief's single-write wording; iOS wins.
- No type explanation or unsaved-date warning in this edit view. R8's prose about prompt memes and matching belongs to the read-only view.
- The sections are Basics, Schedule, Sign-up limits, conditional Tag set(s), Matching, Anonymity and moderation, At AO3.
- R8's four-read count misses the meme probe and the conditional last-page sign-up read. The order is settings, sign-ups, profile, collection edit.
- The footnote says a past reveal cannot move earlier, but no code disables a past reveal date or validates it against the loaded date/now. Only adjacent deadline order is validated. The implementation follows the code, not that unsupported claim.

Only `viewerIsOwner` is offered **Edit settings**, from the read-only Challenge Settings screen (`AO3CollectionOwnerControls.areVisible`); a moderator without the owner hint is not offered it. Header kicker: “Gift exchange · moderator” / “Prompt meme · moderator”; title “Challenge settings”; subtitle title (slug fallback), plus `N sign-up(s)` if the count succeeds.

### Reads for one opening, in order

1. Authenticated GET `/collections/SLUG/gift_exchange/edit`. Only 404 or a non-gift form falls back to GET `/collections/SLUG/prompt_meme/edit`.
2. Best-effort authenticated GET `/collections/SLUG/signups`, for BOTH kinds. Swift reads the last page if pagination has more than one, computing first-page count × (pages − 1) + last-page count. No assignment pages or page-by-page walk here.
3. Best-effort authenticated GET `/collections/SLUG/profile` for tag-set links.
4. Best-effort authenticated GET `/collections/SLUG/edit` for Basics and collection switches.

Single-page success: gift **4**, meme **5**. Paginated success: gift **5**, meme **6** in Swift. Android reads **only page one** under owner question 16; it omits the total when there are further pages (never mislabels page-one count as a total). Required form failure stops the chain; failed optional attempts are remembered. No write on opening.

### Every section and row

| Header | Rows, wording and edits |
| --- | --- |
| Basics | Name = collection title; Tagline = description or “None”; Introduction = HTML-stripped word count (“None”, “1 word”, “N words”); FAQ = “Set” or “None”. All four push the existing collection edit form; unavailable collection shows a single “Collection settings” / “Loading…” or “Couldn't load” link. Sign-up instructions is multiline challenge `signup_instructions_general`, placeholder “Describe the challenge for people signing up…”. |
| Schedule | Sign-ups open, Sign-ups close, Assignments sent, Works due, Works revealed, Creators revealed, Time zone. Dates omitted if their inputs were not served. Assignments sent is read-only abbreviated date/time if known, otherwise “Manual”. Zone is read-only selected zone or “Unavailable”. Readable dates edit wall-clock digits, empty dates have “Set”; unreadable nonempty text remains verbatim/read-only. Condition: `!settings.scheduleIsEditable` (parser sets this when selected zone is empty). |
| Sign-up limits | Requests = required “to” allowed (two 0…20 menus); gift only Offers same. Request restrictions: URL allowed in a request, Description required, Optional tags allowed. Disabled when `!settings.requestRestriction.isEditable(field)`, meaning served disabled or absent controls. |
| Tag set / Tag sets | Each served numeric profile link/title pushes the existing native tag-set screen with moderator=true. Entire section absent for zero links/profile failure. |
| Matching | If `matchSettings != nil`: Match on = nonzero required tag types joined by comma, or “Nothing required”; Requests that must match = All/1…5; Fandoms, Characters, Relationships, Additional tags, Categories, Ratings, Warnings = All/0…5. Count optional tags for: same seven switches. Request fandoms: Fandoms required per request, Fandoms allowed per request = 0…10 steppers; Allow any fandom switch, all gated by served restriction control state. Swift draws Request fandoms and its footnote even for a meme. |
| Anonymity and moderation | Collection switches: Anonymous until reveal, Unrevealed until reveal, Moderated sign-ups, Closed to new sign-ups. Disabled when `collectionForm == nil`. Meme adds Prompts posted anonymously, from challenge `anonymous`. |
| At AO3 | Run matching / “Opens AO3” → `/collections/SLUG/potential_matches`; Delete challenge / “Opens AO3” → kind's edit page. Android uses in-app browser as requested. No native matching/delete writes. |

Footnotes, word for word:
- “Dates use the challenge’s time zone shown on AO3. After a reveal happens, you can't move it to an earlier time in Kudos.”
- Without selected zone: “Kudos couldn't read the challenge's time zone. Dates are view-only and won't be saved.” (Android keeps untouched successful controls, including date strings, instead of deleting them.)
- Disabled request restriction controls: “Prompts have been added so these settings can no longer be changed.”
- Allow any fandom: “Choosing “any” can match you with anything in the tag set.”
- Matching: “AO3 does the matching. Save these settings here, then use Open on AO3 to run or rerun the match. If potential matches already exist, your changes take effect after you regenerate them on AO3.”

Loading: “Loading challenge settings…”. Failure: “Couldn't load challenge settings”, reason, “Try Again”. General errors above sections, schedule/limit errors alongside their sections. Local validation words: “This date is before the previous deadline.”; “At least one request is required.”; “Allowed requests cannot be fewer than required requests.”; gift only “At least one offer is required.”; “Allowed offers cannot be fewer than required offers.”


### Save, field for field in Swift

`updateChallengeSettings` first calls `form.validated()`, then `fetchCSRFPage(at: kindEditURL)`: **one fresh authenticated GET of the same challenge edit page, solely for its meta csrf-token**. It keeps the opening's settings/action/method; it does not replace them with the fresh form. `writeRequest` sends **POST** to the opening's `actionURL` (normal addresses `/collections/SLUG/gift_exchange` or `/collections/SLUG/prompt_meme`), URL-encoded body, `X-CSRF-Token` and `Referer`; no Ajax headers. Token and method override are in the body.

Let `P` be `gift_exchange` or `prompt_meme`. Ordered Swift parameters:

| Name(s) | Value source / condition |
| --- | --- |
| `authenticity_token` | Fresh page's meta token |
| `_method` | Opening's hidden method override, only if nonempty |
| `P[signup_open]` | Opening's checked state, 1/0; no row edits this |
| `P[time_zone]` | Selected opening zone, only `scheduleIsEditable` |
| `P[signups_open_at_string]`, `P[signups_close_at_string]`, `P[assignments_due_at_string]`, `P[works_reveal_at_string]`, `P[authors_reveal_at_string]` | Only if schedule editable AND instant.isOnForm. Parsed wall-clock container formatted `yyyy-MM-dd HH:mm:ss`; unparsed source retained. The UI edits those digits. No assignments_sent_at is posted. |
| `P[requests_num_required]`, `P[requests_num_allowed]` | Local limits (initial parsed integer/default 1) |
| `P[signup_instructions_general]`, `P[signup_instructions_requests]`, `P[request_url_label]`, `P[request_description_label]` | General instructions can change; other opening strings never drawn/edited here |
| Gift only: `P[offers_num_required]`, `P[offers_num_allowed]`, `P[signup_instructions_offers]`, `P[offer_url_label]`, `P[offer_description_label]`, `P[requests_summary_visible]` | Offer limits editable; other opening strings/bool retained; bool 1/0 |
| Meme only: `P[anonymous]` | Prompts posted anonymously switch, 1/0 |
| `P[request_restriction_attributes][…]` and gift-only `P[offer_restriction_attributes][…]` | Details below; offers not edited on this screen |
| `P[potential_match_settings_attributes][id]` | Nonempty matcher ID only, when matcher exists |
| `P[potential_match_settings_attributes][num_required_prompts]` | Requests that must match, integer (-1 = All) |
| `P[potential_match_settings_attributes][num_required_TYPE]`, `P[potential_match_settings_attributes][include_optional_TYPE]` | For TYPE in fandoms, characters, relationships, freeforms, categories, ratings, archive_warnings, in that order; required integer, optional 1/0 |
| Remaining hidden fields | Opening's `hiddenFields`, except names already explicitly encoded. Enabled checked checkbox replaces its hidden twin's stored value. Unmodeled visible controls are **not** carried by Swift. |

Each restriction block encodes, in order, enabled/present controls only: nonempty `id`; booleans `optional_tags_allowed`, `title_required`, `title_allowed`, `description_required`, `description_allowed`, `url_required`, `url_allowed`; `fandom_num_required`, `fandom_num_allowed`, `allow_any_fandom`, `require_unique_fandom`; corresponding four for character, relationship, freeform; then `tag_sets_to_add`. Integers from parsed limits, booleans 1/0, strings from opening. Only request URL allowed, description required, optional tags allowed, fandom range and allow-any fandom have edit rows. The model has rating/category/warning properties, but this restriction encoder does not emit them.

**Untouched Swift fields are re-encoded**, sometimes normalized, sometimes synthesized even without a served control. Hidden names it does not model survive unless they collide with an explicit field. Unknown nonhidden controls do not survive. This conflicts with the explicit brief's browser-equivalence rule and with its “nothing invented, nothing dropped” requirement. Android follows the served-form preservation rule already landed in 3bl: untouched successful controls in original order, including hidden twins/repeated names/unknown text/textarea/select/radio/checkbox and the first enabled submitter. Disabled/unchecked controls are retained in memory but not submitted. Edited fields replace only their selected control; hidden twins remain. No absent modeled value is invented. Fresh token replaces token pairs (or is added if only meta was served). See Open questions.

After challenge confirmation, only if one of the four collection preferences differs, Swift does `updateCollection`: one fresh GET `/collections/SLUG/edit` for meta token, one POST to captured collection action. Body: optional `_method` first, `authenticity_token`; `collection[name]` (slug if locked), `collection[title]`, `collection[email]`, `collection[header_image_url]`, `collection[description]`, `collection[parent_name]`, `collection[icon_alt_text]`, `collection[icon_comment_text]`, `collection[tag_string]`, `collection[multifandom]`, `collection[delete_icon]`; `collection[collection_preference_attributes][moderated|closed|unrevealed|anonymous|show_random]`; `collection[collection_profile_attributes][intro|faq|rules|gift_notification|assignment_notification]`; optional preference id; `challenge_type` if options present; email_notify if served; optional profile id; each `owner_pseuds[]`. Only anonymous/unrevealed/moderated/closed are changed here. Swift ignores arbitrary hidden fields and header_image_alt. Android uses the same fresh-read/POST endpoints but its captured successful collection controls, preserving unknowns and untouched values; the existing standalone collection form/encoder is unchanged.

### Verdicts and what happens next

Swift's confirmation/refusal code in `AO3ChallengeActions.updateChallengeSettings`, in order:

```swift
if let error = AO3Client.writeErrorMessage(in: body) { /* .invalid, error prepended */ }
if let notice = AO3Client.writeSuccessMessage(in: body)
    ?? (body.localizedCaseInsensitiveContains("successfully")
        ? "Challenge was successfully updated." : nil) { /* .saved */ }
if (300...399).contains(status) {
    return .saved(message: "Challenge updated.", form: posted)
}
if (200...299).contains(status),
   let parsed = try? AO3Client.parseChallengeSettingsForm(body, slug: form.collectionSlug, kind: form.kind),
   !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty { return .invalid(parsed) }
throw AO3ChallengeWriteError.unconfirmed
```

`writeErrorMessage` selects the first `#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution` and its nonempty text. Success selects `.flash.comment_notice, .flash.notice`; a bare p.notice does not confirm. Named errors win even over notices/redirects. Collection verdict uses the same ordering, but fallback prose evidence is “successfully created”/“successfully updated”, rather than any “successfully”.

| Verdict | Exact visible words / screen action |
| --- | --- |
| Named refusal | AO3's reason, above sections; stays open. Android keeps every submitted value, not just Swift's explicit dates/limits restoration. No second collection POST. |
| Notice | AO3's notice; stays open, adopts confirmed form; then conditional collection Save. |
| Prose confirmation | “Challenge was successfully updated.”; second collection “Collection was successfully updated.” |
| Bare redirect | “Challenge updated.” / “Collection updated.” |
| Unconfirmed (including session changed after dispatch on Android) | “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.” No optimistic navigation or success. |
| Signed out at writer entry | “Log in to AO3 first.”, no preparation/POST |
| Opening while signed out | “Log in to AO3 before using this feature.”, no request |
| Missing fresh meta token | **“Couldn't prepare the request. Try again, or open the work on AO3.”** The reachable helper throws AO3WriteError.noCSRFToken; the unused AO3ChallengeWriteError.noCSRFToken has “challenge”, but is not what this Save throws. |
| Failed read | Existing UserFacingError/moderationMessage: offline “You're offline. Connect to the internet and try again.”; forbidden “AO3 refused the request (HTTP 403). Wait a while before trying again.”; expired “Your AO3 session expired. Please log in again.”; timeout “AO3 took too long to answer. Try again.” |
| Collection invalid with no general reason | “AO3 didn't save the collection settings.” |

Swift appends two success notices separated by a space. A caught collection error is prefixed “Collection settings: ” in Swift; Android leaves the repository's verdict as-is under the owner's 2026-10-09 standing rule. Swift's post-save `requireSessionGeneration` can discard an already-sent verdict; Android uses `movedOnAfterWrite(expectedGeneration, response)` immediately after dispatch, no throwing session check thereafter. Busy clears in `finally`, including cancellation/failure while active. No automatic retry.

## Android implementation and network policy

- `AO3CollectionDetailRepository.getChallengeSettingsEdit`: sequential foreground reads in the order above, through existing authenticated fetch/parse dispatcher; auth generation checked between them. No anonymous fallback after private read failure.
- `AO3ChallengeSettingsForm`: immutable served snapshot using existing `AO3WorkFormParser.servedControls` / `AO3ServedControl.successfulValues`; only local edits layered on it. Absent/disabled/readonly controls cannot change. Time-zone absence and unreadable nonempty dates lock date controls. Validation follows the Swift deadline/limit checks.
- `AO3WriteRepository.saveChallengeSettings`: same fresh meta-token read and captured action, existing single-shot `postAuthenticatedInSession`; conditional collection form uses the same function with `collectionSwitches=true`. No new live HTTP implementation.
- `AO3ChallengeSettingsEditState`: remembers attempted opening, denies non-owner/signed-out locally, keeps drafts on refresh, guards second tap, confirms reveal before any read, shows repository verdict and clears saving/loading in finally.
- `AO3ChallengeSettingsEditScreen`: own pushed shell provider, no toolbar Save/Cancel, bottom Save changes, lazy rows/options, form components and scope palette only, explicit line heights, stacked controls at accessibility scale, statusBars + 76dp before header. Date picker uses five numeric choice rows (Year/Month/Day/Hour/Minute), in AO3's wall clock; Done changes only the served date field, keeping its precision/separators/zone suffix. Cancel changes nothing. Empty date Set opens the picker using current UTC wall-clock digits, matching Swift's Date() default container.
- `AppNavHost`: same settings route hosts the owner editor; route-owned ViewModel and saveable opening identifier retain the draft while an AO3/tag-set/collection screen is pushed. Back closes it immediately, as Swift does.

Policy admission for **each read**: kind edit probe/fallback, first sign-ups page, profile and collection edit are user-opened, foreground private collection navigation (the policy's explicit-navigation allowance, no background/bulk scrape). Their optional failures count as attempts. Each fresh edit-page read is CSRF preparation for the user's Save, explicitly allowed by **Writes: “CSRF via authenticatedPageHTML”**. Each POST is allowed by **Writes: “single-shot: never retried, never coalesced”**, fenced before dispatch by the existing authenticated client, paced through the existing AO3 client, host allow-list/contact UA/cooldown untouched. Both links only navigate to the in-app browser; this brief adds no matching or delete operation. All code and test work here was local; AO3 was not contacted and no sign-in occurred.

## Demo routes and cases

Launch the existing local signed-in demo (`kudosDemoLibrary` and `kudosDemoSignedIn`), airplane mode. Account → Collections → Winter Exchange 2026 / Summer Prompt Meme → Manage → Challenge Settings → Edit settings. No real login.

Shared route fixtures (one answer per address, used by read-only and edit screens):
- `/collections/winter_exchange/gift_exchange[/edit]` → `ao3_demo_winter_settings.html`: instructions, five chronological dates, request/offer ranges, request restriction switches/fandom steppers, all seven matcher choices/optional switches, unknown text/textarea/repeated hidden IDs. Fandoms alone initially appears in Match on; changing required to All keeps it there; changing to 0 removes it (selection rule is nonzero).
- `/collections/summer_meme/gift_exchange/edit` → local 404; `/collections/summer_meme/prompt_meme[/edit]` → `ao3_demo_meme_settings.html`: five dates, Requests without Offers, own anonymous prompt switch, disabled fandom required/allowed/any and optional tags, producing the exact prompts-added lock note. No matcher num_required_prompts select, so no matcher choices/optional switches. Request fandoms still appears, as Swift draws it.
- `/collections/summer_meme/signups` → `ao3_demo_meme_signups.html` (recognized empty, total 0). Winter shares the existing two-page sign-ups answer, so editor omits its total under the first-page rule.
- Profiles share existing profile answers; Winter tag sets 42/43, Summer 44.
- `/collections/winter_exchange/edit` shares existing `DemoCollectionForms` and fixture; `/collections/summer_meme/edit` has the single `ao3_demo_meme_collection_edit.html` answer, reused by the existing standalone collection form.

Tap Save changes: challenge succeeds locally; if collection switch changed, collection succeeds locally afterwards. Turning off Anonymous until reveal asks Reveal now?, Cancel sends nothing; Save and reveal performs both saves. Put **refuse settings** in Sign-up instructions: the local challenge answer returns 422 with **“Sign-up instructions contain a refused demo phrase.”**, preserves typed text, and sends no collection update. Reload/reopen the same demo address reflects accepted challenge edits. Restart the app resets demo writes. Run matching and Delete challenge stay local in the in-app browser. Unreadable-zone/unreadable-date/missing-date cases use inline modified fixtures in unit tests, not extra demo routes.

## Decided without asking

- Reuse and enrich Winter/Summer settings assets; no duplicate address-specific form fixtures for different screens. Original fictional harbor/lantern filler only.
- Add Summer's own collection edit and empty sign-ups assets because the existing generic fallback served Winter's action and could not represent these routes correctly.
- Keep new model/parser in `network/ao3/account/AO3ChallengeSettingsForm.kt`; state/screen in `account/`; tests beside existing challenge and DemoNetwork tests. File names contain no “prompt”.
- Preserve captured successful controls, including unknowns; use no persistence/Room/backup changes or dependencies.
- No assignment reads, no last-page sign-up read, no fake total for a multipage index.
- Native date choices use existing row/choice/panel parts, not default Material date surfaces. Exact untouched wire dates remain unchanged.
- Keep UI behavior from Swift: bottom Save, no discard, reveal only on true→false collection switches, conditional second collection save, stay open after Save.

## Open questions (decisions implemented; no reply needed to finish this handoff)

1. Swift's encoder conflicts with the brief's exact browser-body requirement: it synthesizes some absent fields, normalizes modeled strings/dates, carries unknown hidden controls but drops unknown visible ones. Android chooses the explicit served-form rule, as 3bl did, preserving every successful control and inventing none. Confirm whether to align Swift's encoder later; this port does not change it.
2. Swift's past-reveal footnote promises a lock that its code does not enforce. Android follows the actual code (deadline order only), and retains the words. Decide whether that promise should be fixed on both platforms later.
3. The owner's first-page limit prevents an exact sign-up total for paginated openings; Android omits that subtitle count. Permission for a later-page read remains owner question 16.
4. A Save can partly succeed: challenge saved, collection refused/unconfirmed. Android shows the confirmed notice and the second verdict, retaining unsaved switches. Whether to make this operation atomic belongs to AO3; no compensating write or automatic resend is added.

## Verification and handoff

No Gradle, Xcode, emulator, sign-in, live request, commit, push, branch switch or TASKS.md edit was made. `git diff --check` passes. Symbols were read against the real Kotlin components/client and real Swift implementation; **compilation, execution and visual correctness are not claimed**.

Authored tests (must be run by Claude):
- `AO3ChallengeSettingsEditTest`: both counted opening chains, no writes on opening, attempted optional failures, owner/signed-out refusal, browser-equal bodies for both kinds, exact isolated edits and date formatting, disabled/absent/zone/unreadable fields, local Swift validation, notices/refusals/redirect/unconfirmed, token failures, session changes before/after dispatch, login verdict, reveal gating, duplicate Save, refresh draft preservation, conditional collection body/POST and no collection write after challenge refusal.
- `AO3ChallengeSettingsEditScreenTest`: owner form/links/choices/refusal text retained, meme locked rows and anonymous switch, reveal Cancel/confirm, Light/Dark/Sepia/OLED and 2× text layout assertions in tall native-graphics Compose windows with patient waits.
- `DemoChallengeSettingsEditTest`: both shared edit routes/browser answers, success/refusal/local reset and Summer routes, terminal no-socket interceptor.
- Existing `AO3ChallengeSettingsScreenTest` now checks the native edit callback rather than historical browser navigation.

Claude next: run Android verification (`android/Scripts/verify.sh`), fix compile/test failures, then inspect both demo forms and date menus in all themes and accessibility text, including returning from Basics/tag set/browser with an unsaved draft. Inspect shell Back and tab chrome after switching between read-only and edit. Validate raw submission differences against Swift/browser expectations before committing. New tests have no resource-closing @After.

## Landing note (Claude, 2026-10-10)

Codex's usage ran out as it finished its own last read of the diff (its limit now lifts on
**2026-10-14 at 21:59**); the code, the tests and this file were complete. It compiled and
passed first time. Gate: 2,527 tests.

Changed on landing:
- **The date picker and the number chooser could not be read.** Both are a panel in a
  `Dialog`, and a panel's fill is 9% glass made to sit on a page: the dimmed form showed
  straight through the rows. They now have a solid ground (`Modifier.dialogGround` in
  `ui/subject/SubjectComponents.kt`). The assignments screen's two pickers (brief 3cc) had the
  same fault and take the same ground, in their own commit.
- A missing fresh token says "…or open the collection on AO3", as the app's other collection
  writes do; iOS's shared helper says "the work" here.

Read line by line: `saveChallengeSettings` in `AO3WriteRepository.kt` (the session is checked
on entry and after the token read; one POST to the captured, trusted address; the verdict in
iOS's order; `movedOnAfterWrite`; the second, collection POST only after the first is
confirmed). **Not read line by line:** `AO3ChallengeSettingsForm.kt` (the parser and what it
sends for each control), the state holder and the screen. A review of the landed code is owed
when Codex is back.

Seen on the emulator, airplane mode, the demo's local answers: the gift exchange's form top to
bottom in Light; Save unchanged ("Challenge was successfully updated."); the demo's refusal
shown above the sections with the typed text kept; a collection switch changed and saved (both
notices); "Anonymous until reveal" turned off, "Reveal now?" with Cancel, then Save and reveal
(both notices); the date picker and its chooser after the fix, in Light; the prompt meme's form
in Sepia at twice the text size, with its locked rows and their note. Not seen: a date
actually changed and saved; returning from Basics or a tag set with unsaved changes; Dark and
OLED for the form itself; a moderator who is not the owner.

## Read line by line (Claude, 2026-10-10, 02:40)

`network/ao3/account/AO3ChallengeSettingsForm.kt` and `account/AO3ChallengeSettingsEditState.kt`,
beside iOS's `Models/AO3ChallengeModels.swift` (`validated`, `AO3ChallengeInstant`) and
`Services/AO3Client+Challenges.swift` (the parser and the posted fields). The screen file is
still read only where it draws the pickers.

Nothing wrong was found in what is sent:

- An untouched control goes back exactly as served, hidden twins and all; a change is applied
  only to the last visible control of its name; a select accepts only one of its enabled
  options; one submit button is sent; the token is the fresh one.
- **Dates.** Both apps read the same formats (ISO 8601, `yyyy-MM-dd HH:mm[:ss]`, `yyyy-MM-dd`,
  with an optional ` UTC` or `Z`). A date neither can read cannot be edited on Android and goes
  back as served; iOS posts its original text too. An edited date keeps the served precision
  on Android; iOS always posts `yyyy-MM-dd HH:mm:ss`. Neither has been tried against AO3's own
  form, which may serve another format (a release-gate item, as the networking policy says).
- **Validation** is iOS's, sentence for sentence (`AO3ChallengeModels.swift:297`).
- **The two-step save**: the collection's switches go in a second request only after AO3
  confirmed the first, never when the first failed, and never twice (`saving` is set before
  the first suspension).

One guard added: **a radio button cannot be changed.** A radio is one of several controls of
one name, and `parameters()` would have changed the last and left the checked one checked. No
row edits a radio today; one that tried is now refused, and the body stays the browser's (a
case added to `absentDisabledUnreadableZone…`).

Seen and left: when the session moves on between the two requests of a save, the second is
skipped without a word (the screen is dead for that session by then).

