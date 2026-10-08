# Brief 3bo — work form Save and native entrances

## iOS Save, reread from code before implementation

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Writing/WorkEditView.swift` (toolbar, `save`, `perform`), `Features/Writing/WritingDraftsView.swift` (including `WritingWorkDestination`), `Services/AO3WorkActions.swift` (`saveWork`, `requireWorkSession`, `submitWorkForm`), `Services/AO3WriteActions.swift` (`writeRequest`, `submitWrite`), `Services/AO3AuthService.swift` (`authenticatedRequest`), `Services/AO3Client+Works.swift` (`workWriteError`, `workWriteNotice`), and `Models/AO3WritingModels.swift` (`AO3WorkWriteError`).

- **Who/label:** every loaded work form has the toolbar text action **Save**, including an entirely empty new work. There is no required-field validation for saving a draft. The label does not become Save draft or Update. New and draft select `.saveDraft` (`save_button=1`); posted selects `.update` (`update_button=1`). iOS code wins over the brief's apparent alternative labels. Disabled for `isSaving || isPosting || needsPublicationRefresh || needsTagRefresh`. The entire list is disabled while saving/posting. No saving sentence or success alert is added; Save keeps its name.
- **Tap:** `save` guards busy/refresh state, starts a Task; `perform` guards busy again before dispatch so two taps cannot POST twice. It checks the generation that opened the form, rejecting with **Your AO3 session changed. Reopen this form before saving.**, then sets `isSaving` before awaiting `auth.saveWork`.
- **Request:** `saveWork` first `requireWorkSession` (`isLoggedIn`, otherwise **Log in to AO3 first.**). One POST to the loaded `form.actionURL`, referer exactly that action, body exactly `form.parameters(submit:)`. Token comes from the first `authenticity_token` in that body: the token carried by the loaded form, **no fresh GET**. `writeRequest` uses `authenticatedRequest` with explicit **Cookie**, shared contact **User-Agent**, **Content-Type: application/x-www-form-urlencoded; charset=UTF-8**, **X-CSRF-Token: TOKEN**, **Referer: ACTION**. `ajax: false`: no X-Requested-With or special Accept. A private prepared-session stamp is attached then stripped before transport. Shared `submitWrite` fences that stamp before and after pacing; an already dispatched write is not cancelled/retried. No local token replacement or field validation is added for Save.
- **Verdict, in order:** `workWriteError` finds the first nonempty `#main .flash.error` or `#main #error li`, excluding ancestors `#workskin`, `.userstuff`, `#previewpane`; a direct `#main > #previewpane` suppresses refusal extraction. Error throws `.rejected(error)`. Next `workWriteNotice` accepts only a nonempty direct **`#main > .flash.notice`** and returns it. Next **`(300 ... 399).contains(status)` → `return "Saved."`**. Next **`(200 ... 299).contains(status)` → `throw AO3WorkWriteError.unconfirmed`**. Otherwise **`AO3 didn't accept the change.`**. Quoted iOS comment: “Every AO3 work, chapter and series success flashes a notice. A 200 without one proves nothing — and a re-rendered form carries the writer's own text, "successfully" and all.” Android must not interpret authored flashes/words as confirmation.
- **Failure alert:** **AO3 could not save the change**, reason via `UserFacingError`, **OK**. Refusal shows AO3's first exact reason. Unconfirmed: **AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.** Token error enum: **Couldn't prepare the request. Try again, or open the form on AO3.** (Save itself does not fetch a token or invoke that error; a CSRF rejection is AO3's refusal.) Typed HTTP/network wording is recorded below. Failure resets saving and keeps the in-memory form, preview and recovery copies. No retry is automatic.
- **Success:** `preview = nil`, then `dismiss()`; no adoption/replacement of form fields, recovery deletion or local library mutation. Text editor recovery copies are not cleared on success or failure. The draft list has no onSaved callback, notification or reload counter change. Its `.task(id: generation:page:reload)` runs again on navigation reappearance and performs its one current-page GET. Android explicitly signals the underlying Drafts destination on confirmed Save to reproduce that read with retained navigation compositions. Opening a form costs one edit/new GET (Android's landed read scope); Save costs **zero GET + one POST**, then returning to Drafts costs **one current-page GET**, no per-work enrichment or verification read. Debug forms with no Drafts underneath simply close, costing no list read. Existing redirect handling may follow AO3's response; no verification request is added by Save.

iOS's User-Agent value comes from `AO3RequestDefaults.userAgent`: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 KudosReader/{app version} (+https://github.com/cidy02/kudos-ao3-reader)`. Cookie is the current session's scoped header merged by `mergedCookieHeader`; neither cookies nor the private preparation stamp are form fields. Android uses its existing single contact UA, explicit session Cookie, and the same Content-Type, CSRF and Referer headers through the shared client. This brief creates no HTTP implementation.

### Other failure words, verbatim

All Save failures use **AO3 could not save the change** / **OK**. AO3 validation reasons are shown verbatim, with first-reason selection matching iOS's work parser.

| Failure | Message |
|---|---|
| Signed out at entry | Log in to AO3 first. |
| Session changed | Your AO3 session changed. Reopen this form before saving. |
| Expired authentication | Your AO3 session expired. Please log in again. |
| CSRF preparation enum (not fetched on Save) | Couldn't prepare the request. Try again, or open the form on AO3. |
| 403 | AO3 refused the request (HTTP 403). Wait a while before trying again. |
| 404 | That work or page couldn't be found (it may be restricted). |
| 429 | AO3 is rate-limiting requests. Wait a moment and try again. |
| 5xx | AO3 had a server problem (HTTP {status}). Try again shortly. |
| Other HTTP, including 400 | AO3 returned an unexpected response (HTTP {status}). |
| Parse / unsafe captured action | AO3's page format wasn't what the app expected. |
| Offline | You're offline. Connect to the internet and try again. |
| Timeout | AO3 took too long to answer. Try again. |
| TLS | Couldn't make a secure connection to AO3. |
| Other transport | Couldn't reach AO3. Check your connection and try again. |
| Unconfirmed | AO3 replied but didn't confirm the change went through. Check on AO3 before trying again. |
| Remaining refusal | AO3 didn't accept the change. |

Android's shared client expires the session when a write returns AuthenticationRequired. That also advances generation; this form then shows the session-changed wording above and retains its fields. Initial/read authentication errors keep the landed loader wording. There is no automatic retry, fresh token read, or generic success sentence on the screen.

The iOS posted-work entries outside Drafts are Account's `editingWorkID` destination and AuthorProfile's owner work editor (plus its New Work entry). Those remain for their own brief. Post/panel, Delete, Preview on AO3, chapter/tag write refreshes are excluded here.

## Authorization and work log

The policy's existing **Write-session fence** and **No retry loops around writes** allow the explicit user Save through the shared authenticated, paced, single-shot path. **No background or bulk scraping of logged-in pages** allows the user-opened work form/account list, not any sweep. Captured actions must pass `AO3RedirectCookieRelay.isTrustedUrl`. No live operations are authorized in this session.

Initial tree clean on `android/agent-codex-3bo`. Read the required briefs and landing notes, project operational docs, and real Kotlin symbols. This brief overrides TASKS claiming, committing, pushing and build rules. No builds or AO3 calls.

## Decided without asking

- Extend the existing shared write repository and parser; do not alter 3bb's parser/model/encoder or introduce another HTTP path.
- Reuse existing new/draft/posted HTML and demo routes. Keep mutable demo answers inside the existing interceptor; no extra asset/helper files.
- Keep tests beside the writing/network/account suites; literals are synthetic, with exact Unicode/HTML/whitespace checks.
- Use **Save** for all three forms, following current iOS. No new empty-draft validation.
- The local new draft uses **995007**, appended to page one from the existing draft-row template; repeated new-work demo saves replace that one simulated draft. No new fixture asset. Existing demo 995001 and posted 995006 preserve their identities.
- Refusal trigger is the exact title **Refuse this draft**, returning AO3-style `#main form #error ul li` with **Title is too long (maximum is 255 characters)**. This is a deterministic local trigger, not a live title rule added to the app.
- Use the navigation saved-state revision to request one underlying current-page reload on confirmation; do not guess titles, dates, counts or creation times into the production drafts state. A new loader cancels any superseded page load.
- Pin the opening model/account once Save is tapped. On a session failure that exact form remains visible with its original recovery identity and cannot be written by another session. Before any Save, the prior generation-change behavior (remove the private form) stays intact. No additional account GET is made on a Save failure.
- Keep the existing form's parts and typography; add a palette-accent TextButton to shell trailing content and a token-colored app AlertDialog. Disable the title/total/toggles and remove field navigation actions while saving; state also rejects all in-flight edits. Pushed editor/chooser chrome remains its own `ProvidePushedShellChrome`.

## Open questions

- Does Back without saving need the same reappearance reload that iOS's task can make? The more sparing choice here is **no read on unsaved Back or failed Save**, one current-page read only on confirmed Save return. Explicit refresh/revisit retains its existing reads. This needs the local navigation comparison during Claude's review, not a question blocking implementation.
- No ambiguity about unjudged 2xx remains: current iOS explicitly rejects it. Android keeps the form open with those exact words.

## Implementation

`AO3WriteRepository.saveWork` chooses only SaveDraft/Update, trusts the captured action, takes the first body token, and calls the existing `postAuthenticatedInSession` once under the established NonCancellable dispatch pattern. Preparation/session checks and the shared after-pacing check prevent stale queued sends. The response is generation-fenced before publication. `AO3WriteFormParser` gains only work-scoped evidence extraction; existing collection/tag verdict helpers remain unchanged. 3bb's repository/parser/model/encoder are unchanged.

`WritingWorkFormState` owns busy/saved/error state and the synchronous duplicate guard. Every failure retains the original immutable form, including every untouched served control. Save has no recovery or library persistence dependency. `WritingWorkFormScreen` draws from collected state, retains **Save** while waiting and uses iOS's alert. Success invokes the one close callback. `Routes.WritingWork` and `WritingWorkDestination.route` now take both Drafts entrances to the form; other browser callers are untouched. `AppNavHost` only advances the previous Drafts entry's saved revision on confirmed success. Drafts retains its page with `rememberSaveable` so that return reads the page the writer left.

## Local demo routes and taps (not run here)

Use existing local extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true` in airplane mode. These are fixture session state, never a real sign-in. Force-stop/relaunch resets the interceptor's saved answers.

- `nav:writing-drafts`, or Account → Writing → Drafts: tap **Lanterns Above the Mill** (995001), edit Title, **Save** → form closes, one drafts page read shows the changed local title. New Work (top plus) opens the same native form with no work ID; type a title (or leave everything empty), **Save** → close and current page reload, with new draft **995007** on page one.
- `nav:writing-work-new-demo`: new form, Save draft through **Save**, closes. `nav:writing-work-draft-demo`: 995001, same. `nav:writing-work-posted-demo`: 995006, edit Title, **Save** sends Update, closes. Reopening the draft/posted route shows the saved local fields. Production route equivalents are `nav:writing-work` and `nav:writing-work?workId=995001` / `995006`; posted production entry UI remains outside this brief.
- Any supported form: Title **Refuse this draft**, **Save** → **AO3 could not save the change** / **Title is too long (maximum is 255 characters)** / **OK**; exact input retained. A later explicit tap after correcting the title is a new write. No retry occurs automatically.
- The interceptor handles these POSTs locally, checks the served token/CSRF header and correct Save/Update submit, rejects Post/Preview submissions, and updates later local edit/drafts responses only after success. Missing assets and invalid tokens terminate locally. It never calls `proceed` for these writes.

## Offline tests authored; all need Claude's run

- `WritingWorkSaveTest`: ordered requests for new/draft/posted against a **literal iOS field/value/order oracle**, plus 3bb's independently parsed browser replay (also used for all three actual screen-edited Title tests); all fields, loaded meta versus differing input token, action/referer/CSRF/Cookie, empty new draft allowed, changed title/rating/tags/all four text bindings, no reads on Save, one POST/no duplicate or retry, error/notice/redirect precedence, 200/204 unconfirmed, authored flashes and preview exclusions, fallback verdict, every typed HTTP/network/token failure, thrown transport failure, before/during-write session changes, success/failure recovery files unchanged, untrusted action/signed out no request, multi-chapter title without content.
- `WritingWorkFormScreenTest`: real Title edits saved from all three forms, disabled in-flight Save and ignored second tap, closes only on confirmed success, refusal/unconfirmed exact alert copy and retained form, real-wrapper session change during POST, multi-chapter hidden Work text/no content. Existing Light/Dark/Sepia/OLED accessibility checks now include Save and the refusal alert, using `!didOverflowHeight` and no last-line ellipsis. Tall native-graphics window and patient waits retained.
- `AO3WorkSaveDispatchTest`: actual shared OkHttp/authenticated client with terminal local interceptors; headers, UTF-8 encoded bytes, one POST on 200/429/503 with no retry; generation change inside shared pacing prevents dispatch. No socket can be reached by these interceptors.
- Existing Drafts route/screen tests now assert native destinations. Added confirmed-save revision tests: one current-page reload displays AO3's changed title, and page two remains page two. Added `@GraphicsMode(NATIVE)` to its Compose suite.
- `DemoDraftsTest`: actual local POST responses for all three forms, later form/index state, new draft id, refusal/token/missing assets, fresh interceptor reset. Downstream interceptor throws before any socket.

## Checks performed and handoff

Read real Swift/Kotlin signatures and callers, shared form encoding, HTTP response mapping, parser scoping, session/pacing/write behavior, chrome/alert/toggle/text field and test APIs. `git diff --check` passes. Source checks confirm no edits to TASKS, encoder/model/form repository, backup or Room, and no new raw HTTP implementation. New test assertions are **not executed results**.

Claude must run Android debug compilation and `:app:testDebugUnitTest`, including the suites above, 3bb form/repository, editor/recovery/association, drafts, shell/routes, demo-block and shared write/session regressions, then the full Android gate. Every request count, coroutine/session/failure behavior, compilation, parser, recovery and Compose assertion needs that run. No Gradle, Xcode, Kotlin compiler, emulator, screenshot, live sign-in or AO3 call was run here.

Manual local pass still owed: Account's two native entrances and both Back paths; new/draft/posted Save; refusal with exact text retained; in-flight Save; editor recovery after failures and successes/relaunch; returning to both drafts pages; session transition; all four themes and accessibility text, with screenshots for human review. No visual correctness or live save success is claimed. Post/panel, Delete, Preview on AO3, chapter/tag write refreshes and posted-work entry UI remain excluded.

Work stays uncommitted/unpushed in this worktree on `android/agent-codex-3bo`. No branch switch, TASKS edit, iOS edit, backup-format/Room-schema change, helper script, stub or `.orig` file. Next step: Claude builds, tests, reviews local screenshots and commits.

## Landing note (Claude, 2026-10-08)

Landed on `android/redesign-parity`; the patch applied cleanly. Gate: 2,163 tests.

Changed on landing:

- **The Save button never appeared.** It was registered with the shell as content that
  tested for the form inside itself; the form arrives after the screen, and the shell's row
  stayed empty. Codex's own test (`realWrapperKeepsTypedFieldsWhenTheSessionChangesDuringSave`,
  the only one that loads the form the way the app does) caught it. The button is now
  registered as a value that is absent until there is a form.
- `WritingDraftsScreenTest.confirmedSaveReturnKeepsTheSelectedDraftsPage` waited on a request
  count, which does not let the screen recompose in this harness; it waits for idle first.

Seen on the emulator (demo): a tap on a draft opens the native form with Save in the top
row; the title "Refuse this draft" gives "AO3 could not save the change / Title is too long
(maximum is 255 characters) / OK" and keeps the text; a corrected Save closes the form and
the drafts list is read once and shows the new title.

Not seen: a new work, the posted work's Update, Sepia, OLED, large text, the session change
during a Save (tests cover it), and the open question above (no read on an unsaved Back).
Nothing here has run against AO3.
