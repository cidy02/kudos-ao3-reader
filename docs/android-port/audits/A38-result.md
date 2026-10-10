# A38 Audit: Challenge Settings Edit Form

## 1. Requests

**Gift Exchange Opening**
Both platforms make the exact same 4 requests in identical order:
- `GET /collections/:slug/gift_exchange/edit`
- `GET /collections/:slug/signups`
- `GET /collections/:slug/profile`
- `GET /collections/:slug/edit`

**Prompt Meme Opening**
Both platforms make the exact same 5 requests in identical order:
- `GET /collections/:slug/gift_exchange/edit` (404 / Catch `AO3Error.notFound`)
- `GET /collections/:slug/prompt_meme/edit`
- `GET /collections/:slug/signups`
- `GET /collections/:slug/profile`
- `GET /collections/:slug/edit`

There are no requests Android makes that iOS does not, or vice versa.

**Writes (Challenge Save)**
- **Android Address:** `POST actionUrl` (e.g. `/collections/:slug/gift_exchange`) after a `GET` to the edit referer.
- **iOS Address:** `POST posted.actionURL` (e.g. `/collections/:slug/gift_exchange`) after a `GET` to the edit referer.
- **Fields Sent:**
  - **iOS** explicitly constructs and sends only the fields mapped to its `AO3ChallengeSettingsForm` properties: `authenticity_token`, `_method` (if set), `prefix[signup_open]`, `prefix[time_zone]`, all five `prefix[..._at_string]` dates, `prefix[requests_num_required]`, `prefix[requests_num_allowed]`, limits, `signup_instructions_general`, `prefix[request_restriction_attributes]...`, `prefix[potential_match_settings_attributes]...`, and `prefix[requests_summary_visible]`. For a Gift Exchange, it also sends `prefix[offer_restriction_attributes]...`.
  - **Android** parses the HTML and sends the `authenticity_token` along with the `successfulValues()` of *every* `AO3ServedControl` originally present on the form, substituting only the values present in `changes`. This inherently includes all untouched hidden fields, untouched checkboxes, and unmodified "Offer restrictions".

**Writes (Collection Save)**
Both platforms conditionally execute this only if moderation preferences change.
- **Android Address:** `POST` to `actionUrl` (the collection edit form action, `/collections/:slug`) after a `GET /collections/:slug/edit`.
- **iOS Address:** `POST` to `/collections/:slug` after a `GET /collections/:slug/edit`.

## 2. What a row edits

For each row in iOS's order, here is the Swift property edited, the form field it is sent as, and the corresponding Kotlin control name that the Android row alters. The prefix `gift_exchange` or `prompt_meme` is denoted as `[prefix]`.

| iOS Row | Swift Property | Swift Form Field | Kotlin Control Name |
| :--- | :--- | :--- | :--- |
| **Sign-up instructions** | `settings.signupInstructionsGeneral` | `[prefix][signup_instructions_general]` | `[prefix][signup_instructions_general]` |
| **Sign-ups open** | `settings.signupsOpenAt` | `[prefix][signups_open_at_string]` | `[prefix][signups_open_at_string]` (or `_at`) |
| **Sign-ups close** | `settings.signupsCloseAt` | `[prefix][signups_close_at_string]` | `[prefix][signups_close_at_string]` (or `_at`) |
| **Works due** | `settings.assignmentsDueAt` | `[prefix][assignments_due_at_string]` | `[prefix][assignments_due_at_string]` (or `_at`) |
| **Works revealed** | `settings.worksRevealAt` | `[prefix][works_reveal_at_string]` | `[prefix][works_reveal_at_string]` (or `_at`) |
| **Creators revealed** | `settings.authorsRevealAt` | `[prefix][authors_reveal_at_string]` | `[prefix][authors_reveal_at_string]` (or `_at`) |
| **Requests** (required) | `settings.limits.requestsRequired` | `[prefix][requests_num_required]` | `[prefix][requests_num_required]` |
| **Requests** (allowed) | `settings.limits.requestsAllowed` | `[prefix][requests_num_allowed]` | `[prefix][requests_num_allowed]` |
| **Offers** (required)* | `settings.limits.offersRequired` | `[prefix][offers_num_required]` | `[prefix][offers_num_required]` |
| **Offers** (allowed)* | `settings.limits.offersAllowed` | `[prefix][offers_num_allowed]` | `[prefix][offers_num_allowed]` |
| **URL allowed in a request** | `settings.requestRestriction.urlAllowed` | `[prefix][request_restriction_attributes][url_allowed]` | `[prefix][request_restriction_attributes][url_allowed]` |
| **Description required** | `settings.requestRestriction.descriptionRequired` | `[prefix][request_restriction_attributes][description_required]` | `[prefix][request_restriction_attributes][description_required]` |
| **Optional tags allowed** | `settings.requestRestriction.optionalTagsAllowed` | `[prefix][request_restriction_attributes][optional_tags_allowed]` | `[prefix][request_restriction_attributes][optional_tags_allowed]` |
| **Requests that must match** | `settings.matchSettings?.numRequiredPrompts` | `[prefix][potential_match_settings_attributes][num_required_prompts]` | `[prefix][potential_match_settings_attributes][num_required_prompts]` |
| **Fandoms** (Match on limit) | `settings.matchSettings?.numRequired["fandoms"]` | `[prefix][potential_match_settings_attributes][num_required_fandoms]` | `[prefix][potential_match_settings_attributes][num_required_fandoms]` |
| **Count optional tags for** (Fandoms) | `settings.matchSettings?.includeOptional["fandoms"]` | `[prefix][potential_match_settings_attributes][include_optional_fandoms]` | `[prefix][potential_match_settings_attributes][include_optional_fandoms]` |
| **Fandoms required per request** | `settings.requestRestriction.fandomRequired` | `[prefix][request_restriction_attributes][fandom_num_required]` | `[prefix][request_restriction_attributes][fandom_num_required]` |
| **Fandoms allowed per request** | `settings.requestRestriction.fandomAllowed` | `[prefix][request_restriction_attributes][fandom_num_allowed]` | `[prefix][request_restriction_attributes][fandom_num_allowed]` |
| **Allow any fandom** | `settings.requestRestriction.allowAnyFandom` | `[prefix][request_restriction_attributes][allow_any_fandom]` | `[prefix][request_restriction_attributes][allow_any_fandom]` |
| **Anonymous until reveal** | `collectionForm?.isAnonymous` | `collection[preference_attributes][anonymous]` | `collection[preference_attributes][anonymous]` |
| **Unrevealed until reveal** | `collectionForm?.isUnrevealed` | `collection[preference_attributes][unrevealed]` | `collection[preference_attributes][unrevealed]` |
| **Moderated sign-ups** | `collectionForm?.isModerated` | `collection[preference_attributes][moderated]` | `collection[preference_attributes][moderated]` |
| **Closed to new sign-ups** | `collectionForm?.isClosed` | `collection[preference_attributes][closed]` | `collection[preference_attributes][closed]` |
| **Prompts posted anonymously** | `settings.isAnonymous` | `[prefix][anonymous]` | `[prefix][anonymous]` |

*\* Only shown for Gift Exchanges.*

*(No row is completely absent on one side while present on the other. Both platforms entirely omit "Offer restrictions" editing from the UI).*

## 3. Validation before sending

Both platforms execute these checks before POSTing:
- **Deadline order:**
  - Android: `"This date is before the previous deadline."`
  - iOS: `"This date is before the previous deadline."`
- **Request/Offer minimums:**
  - Android: `"At least one request is required."` / `"At least one offer is required."`
  - iOS: `"At least one request is required."` / `"At least one offer is required."`
- **Allowed >= Required limits:**
  - Android: `"Allowed requests cannot be fewer than required requests."` / `"Allowed offers cannot be fewer than required offers."`
  - iOS: `"Allowed requests cannot be fewer than required requests."` / `"Allowed offers cannot be fewer than required offers."`

Additionally, because Android allows manual string input for dates rather than enforcing a native `DatePicker`, Android includes one extra validation check iOS does not need: `"Enter the date in the format shown on AO3."`

## 4. Verdicts

**Android:**
- **Saved:** "Challenge was successfully updated." (or "Collection was successfully updated.") when `notice != null` or `statusCode in 300..399`.
- **Refused (Invalid):** When `error != null` or when `statusCode in 200..299` and `!parsed.isValid`.
- **Not Confirmed:** "Couldn't prepare the request. Try again, or open the collection on AO3." (token parse failure) or `AO3CollectionFields.UNCONFIRMED`.

**iOS:**
- **Saved:** "Challenge was successfully updated." when `notice != null` or `body.localizedCaseInsensitiveContains("successfully")`; "Challenge updated." when `(300...399).contains(status)`.
- **Refused (Invalid):** When `error != null` or when `(200...299).contains(status)` and `!parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty`.
- **Not Confirmed:** `AO3ChallengeWriteError.unconfirmed` fallback.

## 5. Words on screen

The screen strings between `AO3ChallengeSettingsEditScreen.kt` and iOS's `ChallengeSettingsEditView.swift` are nearly identical. 

Differences found:
- **Android:** `"Saving…"` (when POST is in-flight)
- **iOS:** Does not have the `"Saving…"` text (renders a spinner next to "Save changes" instead).

## 6. Second taps, stale answers, the reveal question

- **What stops a second Save while one is out:**
  - **Android:** `if (!ownsSession() || !owner || state.value.loading || state.value.saving || state.value.terminal) return`
  - **iOS:** `guard !isSaving else { return }`
- **What stops an answer that arrives after a session change being shown:**
  - **Android:** `movedOnAfterWrite(expectedGeneration, response)?.let { return it }` cancels the flow if the auth session changed. `if (active)` drops UI updates if the user closed the screen.
  - **iOS:** `try auth.requireSessionGeneration(loadedGeneration)` throws before the view updates if the session rolled over.
- **Exactly when "Reveal now?" is asked:**
  - **Android:** `listOf("unrevealed", "anonymous").any { flag -> val key = AO3CollectionFields.preference(flag); form.copy(changes = emptyMap())[key] == "1" && form[key] == "0" }`
  - **iOS:** `(before.isUnrevealed && !after.isUnrevealed) || (before.isAnonymous && !after.isAnonymous)`

## Table

| Number | Severity | Android | iOS | Description |
| :--- | :--- | :--- | :--- | :--- |
| 1 | P3 | `AO3ChallengeSettingsEditState.kt:93` | `ChallengeSettingsEditView.swift:341` | Android drops UI updates with `if (active)` when the screen closes, whereas the comment states "Once the POST is sent, show its verdict even if the preparing session moved on." |
