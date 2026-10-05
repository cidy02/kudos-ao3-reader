# Brief 3at — collection form and Your items

**Landing note (Claude, 2026-10-05).** Codex ran out of usage before it finished this file: the
form (new, edit, delete), its demo answers and its tests were written; **"Your items" was not
started** and goes to the next brief; the sections below stop where Codex stopped. Where this
file says the owner answered, it was Claude (the decisions are in `DECISIONS.md`).

It compiled and passed first time. Gate green (1,555 tests). The three writes were read line by
line against iOS (`createCollection`, `updateCollection`, `deleteCollection`,
`submitCollectionForm`, `collectionFormParameters`, `collectionNameAvailable`) and against
`docs/AO3_NETWORKING_POLICY.md`: the same fields in the same cases, a fresh token fetched at
Save, the session checked on entry and after that fetch, one POST, never retried, success
recognised as iOS recognises it; the name check is one anonymous read per settled name and
never for an empty, malformed or reserved name. **Never run against AO3.**

Changed on landing:
- The form had a Cancel and a Save button in the top row (my brief's wording). iOS has neither:
  Back leaves and the one Save is at the end of the form. Removed.
- AO3's refusal was shown twice when its page carried the message in two places. Said once.
- "Name is available" stayed beside AO3's "Name has already been taken". AO3's answer now
  clears the earlier check. (iOS keeps its green mark there.)
- The new text field row: a typed value sat at the left of its box while the hint sat at the
  right, and then lost its last character; the value now sits at the end like the hint, with
  its width measured from the text. A stacked form (label above) was added for the delete
  dialog, where label and hint wrapped.

How to reach it in the demo (airplane mode, never signed in): Account › Collections › "+" for
the new form: `lantern_archive` is free and is created; `taken_name` is taken; `refused_name`
passes the check and is refused by the form ("Name has already been taken"). Account ›
Collections › Winter Exchange 2026 › Manage › Collection Settings for the edit form: Save
Changes succeeds; Delete Collection asks for the collection's name and then succeeds (the
demo's list still shows it; restart to reset).

Seen on the emulator against those answers, in Light and Dark and at double text size: all of
the above, with the typed entries kept after a refusal.

Three things on iOS that Android copies and the owner may want changed on both: the form shows
"Header image alt text", which is never sent; after creating, the form stays open as "New
collection", so a second tap tries to create it again; and nothing but AO3's own refusal stops
a name that was free a moment ago.

## iOS reference inventory (read-only)

Reference root: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Read `Features/Account/AO3CollectionFormView.swift`, `AO3CollectionItemsView.swift`, `AO3CollectionItemStaging.swift`, `AO3CollectionScreenDecisions.swift`, `Models/AO3CollectionDetailModels.swift`, `Services/AO3Client+Collections.swift`, and `Services/AO3CollectionActions.swift`. Read 3as's landing note first: its confirmation and refresh-after-refusal deviations came from Claude, not owner approval; the shared toolbar disappearance was corrected on landing.

### Form, in screen order

Header: “AO3 Account › Collections”; “New collection” / “Edit collection”; “Your changes are saved to AO3”. Success notice then general errors appear above the groups.

All initial values come from the fetched HTML, including account defaults. The model's `blank` fallback has empty strings, false toggles and no challenge options; it is not a substitute for fetching the form. iOS imposes no text-length maximum and does not read HTML maxlength attributes. Single-line rows show one line; multiline rows use a vertical text field with 2–6 visible lines. All text rows except Collection name remain editable in the view, regardless of HTML disabled attributes.

| Group | Label | Kind / placeholder | Default and limits |
|---|---|---|---|
| Header | Display title | Single-line text / Required | Served title; trimmed nonempty required for Save |
| Header | Collection name | Single-line text / Required | Served name; locked on edit; autocorrection/capitalization disabled; validation below |
| Header | Parent collection | Single-line text / None | Served parent_name; no client validation |
| Header | Contact email | Single-line text / Optional | Served email; no client email validation |
| Header | Tagline | Single-line text / Optional | Served description textarea; no client length validation |
| Images | Header image URL | Single-line text / Optional | Served header_image_url; no client URL validation |
| Images | Header image alt text | Single-line text / Optional | Served header_image_alt; no error key; **not encoded in the iOS POST** |
| Images | Icon alt text | Single-line text / Optional | Served icon_alt_text |
| Images | Icon comment | Single-line text / Optional | Served icon_comment_text |
| Preferences | Closed to new items | Toggle | Served checked state; otherwise false |
| Preferences | Moderated | Toggle | Served checked state; otherwise false |
| Preferences | Unrevealed | Toggle | Served checked state; otherwise false |
| Preferences | Anonymous | Toggle | Served checked state; otherwise false |
| Preferences | Email new items | Toggle | Served checked state; otherwise false; encoded only if the served control exists |
| Challenge | Set up a challenge | Menu picker | Served selected value/options; blank option displays None; entire group absent without options |
| Profile | Introduction | Multiline text / Optional | Served intro textarea |
| Profile | FAQ | Multiline text / Optional | Served faq textarea |
| Profile | Rules | Multiline text / Optional | Served rules textarea |

Header footnote: “The collection name is part of its web address. Use letters, numbers and underscores. You can't change it after creating the collection.”

Preferences footnote: “You can turn on any combination of these settings. Unrevealed shows each work as Mystery Work, Anonymous hides its creators, and new-item emails go to the contact email.” No other group footnotes. No sliders appear in this reference.

No field row is exclusive to edit. Collection name becomes locked on edit. Edit alone adds “Collection actions”, its footnote “Open AO3 to close this collection. Deleting the collection leaves its works on AO3.”, “Open Collection Settings on AO3”, and owner-only “Delete Collection” when the fetched page offers `confirm_delete` or `form.simple.destroy`.

Buttons: “Create Collection” / “Save Changes” below Profile, disabled while saving or when title/name is trimmed empty or name availability is taken/invalid. The form view defines no Save confirmation and no explicit Cancel toolbar button. Initial loading is a spinner; initial failure says “Couldn't open the form”, error description, “Try Again”.

Deletion alert: `Delete “{display title, else name}”?`; text field placeholder is that name; “Cancel” and “Delete on AO3”. Delete enables only on a nonempty trimmed exact match. Message: “This removes the collection, its challenge settings and any gift assignments from AO3. The works stay with their creators. Unrevealed works become visible, and anonymous works show their creators. Type the collection name to confirm.” Deletion reads the owner confirmation page, then one `_method=delete` POST; success dismisses the form. It is an additional write action beyond Save.

### Validation, reads and encoding

`canSave` requires trimmed nonempty title/name and no taken/invalid availability. New-name edits cancel the prior task, clear availability, trim, and validate locally against `^[A-Za-z0-9]\w*[A-Za-z0-9]$` (thus at least two characters; first and last alphanumeric). Invalid names do not trigger a read. For a valid nonempty new name, `scheduleNameCheck` waits 600 ms and calls `collectionNameAvailable`: an **anonymous GET of `/collections/{typedName}`**, not a name-check API. 404 means available, 2xx taken, other results unknown; reserved slugs new/edit/list_challenges/list_ge_challenges/list_pm_challenges are taken without a read. Marks announce “Name is available”, “Name is taken”, or “Name is not a valid collection name”. Unknown does not disable Save.

`createCollection` checks the **untrimmed** name's format before sending. Field message: “That URL name isn't valid on AO3. Use letters, numbers, and underscores, and don't start or end with an underscore.” Update does not perform that format validation; it forces the existing slug into the locked name.

`collectionNewForm` / `collectionEditForm` reads the corresponding page on opening. **Create and Save then fetch that page again for a fresh CSRF token**, retain the loaded action/values/method override, and send one POST. The expected generation is checked before and after this second GET and at shared write dispatch. iOS's form permits save under a newer session of the same username; another account cannot send it.

`collectionFormParameters` sends these `collection[...]` fields even unchanged: name, title, email, header_image_url, description, parent_name, icon_alt_text, icon_comment_text, tag_string, multifandom, delete_icon; preference attributes moderated/closed/unrevealed/anonymous/show_random; profile attributes intro/faq/rules/gift_notification/assignment_notification. Boolean values are 1/0. It also sends authenticity_token, the served `_method` when present, nonempty preference/profile IDs, selected `owner_pseuds[]` (repeated), challenge_type only with served options, and email_notify only with a served control. Non-UI values remain those parsed from AO3. The parser captures hidden fields but the encoder **does not replay arbitrary hidden fields**. It does not filter disabled form fields; the locked collection name is still sent. Header image alt text is displayed/parsed but omitted from encoding. **iOS code wins over the brief's suggestion of carrying every served field; these differences must be preserved unless clarified.**

Form-specific success handling (`submitCollectionForm`): error flash takes priority and returns invalid; success flash or text containing successfully created/updated returns saved; bare 3xx returns “Collection created.” / “Collection updated.”; a 2xx parsed form with general/field errors returns invalid; otherwise unconfirmed. Success keeps the form open and shows the notice. Invalid responses replace the model with AO3's returned form; if parsing fails on an error flash, the submitted form is kept. Transport/unconfirmed/session errors appear inline above the existing fields. No retry occurs. Important distinction: form saves additionally recognize the successfully-created/updated text; `collectionWriteVerdict` for item writes recognizes error flash → success flash → 3xx → non-2xx refusal / plain-2xx unconfirmed.

Shared messages: “Log in to AO3 first.”; “Couldn't prepare the request. Try again, or open the collection on AO3.”; “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.” Save's session cancellation message retains edits and asks the loaded account to sign in again or reopen for another account. The brief's stronger requirement to ignore a response after a session change must be covered in Android tests.

### Your items

The Collections chip opens `AO3CollectionItemsDestination(slug: nil, title: "Your items")`, the **same item screen** in account scope. Header remains “AO3 Account › Collections”, “Collection items”; subtitle begins “Your works in AO3 collections” with decision count or item count and page suffix.

Filters, in order: “Awaiting collection”, “Awaiting you”, “Rejected”, “Approved”, “Reset”. Account default/reset is Awaiting you, whose GET omits status. Awaiting collection explicitly uses `status=unreviewed_by_collection`; Rejected/Approved use rejected_by_collection/approved. Reads are `/users/{login}/collection_items`, only requested pages/tabs; no crawling/prefetch. Initial field values/defaults come from those rows.

Each card: collection eyebrow, role, unsent marker, work title; “Approved by creator” then “Approved by moderators” with Awaiting/Approved/Rejected choices; Unrevealed then Anonymous toggles; creator byline, “Remove from collection” / “Keep”, date. Disabled served controls become facts, excluded from pending drafts and POSTs. No character limits/text-entry fields or work-navigation tap. Removal hides controls, strikes/dims the title and shows “This work will leave the collection when you submit your changes. It stays on AO3.” All changes are local until Submit; returning to server values stops counting a draft; removal replaces other changes. Off-page drafts survive, but only current-page changes count/send. Discard clears every draft.

Toolbar: “N staged”, “Submit”, “Discard”. Submit disabled with no changes or while submitting. **iOS has no Submit/Remove/Discard confirmation.** Complete success clears only sent drafts and refreshes the current page. Failure retains drafts and displays the error without rereading the list. Initial empty: “Nothing in this tab.” Initial failure: “Couldn't load collection items”, description, “Try Again”. Signed out: “Log in to AO3 to manage collection items.” Session change clears/hides previous private rows, drafts, errors and paging. Page failures keep prior rows/page number; tab changes replace rows and return to page one.

`updateUserCollectionItems` captures generation once; reads account Awaiting-you page 1 for CSRF/action/method; parsed action falls back to `/users/{login}/collection_items/update_multiple`, method to patch. Then **one POST per draft**, ascending item ID from staging, strictly sequential with a coordinator slot each, never retried/coalesced; first failure stops the loop. Account AO3 permits creator approval and removal, stripping maintainer fields; served disabled controls govern submittable drafts. Fields are `collection_items[id][user_approval_status]`, `[collection_approval_status]`, `[unrevealed]`, `[anonymous]`, `[remove]` as present in the filtered draft, plus token/method. The collectionWriteVerdict fallback is “AO3 couldn't update that collection item.” The misleading one-POST comments in the view are contradicted by the actual action code; **the action code wins**. 3as's landing note records two Android deviations still awaiting owner question 13: confirmation before Submit and refresh on failure. Do not silently treat them as owner-approved parity.

## Blocker — clarification requested before implementation

The brief permits reads of the new/edit page when the form opens and says “Nothing in the background”, while iOS schedules availability GETs after typing and refetches new/edit on Save. The general iOS-wins rule points to preserving those reads, but the explicit network restriction leaves a material question about permitted request scope. Asked immediately whether Android should include both iOS extra reads or read only on opening; implementation stopped pending the answer, as requested. The first question mistakenly named a check_name endpoint; the replacement question above correctly identifies `/collections/{typedName}`. No such check_name endpoint was found in iOS.

## Networking policy

`docs/AO3_NETWORKING_POLICY.md` allows explicitly opened own-account/collection pages under “No background or bulk scraping”. Opening form and Your items reads fit that scope. Shared contact User-Agent, trusted-host allow-list, ≥0.6 s pacing, coordinator cap, typed 403/404/429, transient-only GET retries and authentication/session fencing apply. Writes are authenticated, explicit-cookie, paced, generation-fenced before/after pacing, single-shot, never retried/coalesced; batch items are sequential and cancellable between requests. No policy rule forbids the requested form/item writes themselves. The policy does not expressly address typed-name anonymous probes; the brief's narrower read rule is the unresolved issue, not a claimed policy prohibition.

## Worktree / handoff

Initial tree clean, branch `android/agent-gemini-3at`. Only this result document added. No Android implementation, demo fixture, or test changes yet; no compile/runtime claims. No builds or test suite run. Once the read-scope question is answered, continue the requested Android implementation and offline parser/body/single-dispatch/Cancel/validation/session tests, then record concrete demo routes and Claude's compile/test/visual gates here.

No AO3 contact, sign-in, commits, pushes, branch switches, TASKS.md edits, iOS edits, backup-format or Room-schema changes. No helper scripts, stubs or .orig files created.
