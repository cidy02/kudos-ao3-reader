# R8 Audit Result

## Challenge settings, the edit form

### What is on screen
From `Features/Challenges/ChallengeSettingsEditView.swift`:
* `"Challenge Settings"` (`path:119`) - NavigationBar title.
* `"Cancel"` (`path:122`) - NavigationBar button shown if `hasChanges`. Confirms discard or dismisses.
* `"Done"` (`path:125`) - NavigationBar button shown if `!hasChanges`. Dismisses view.
* `"Discard Changes"` (`path:127`) - Destructive button on cancel confirmation sheet.
* `"Keep Editing"` (`path:128`) - Cancel button on cancel confirmation sheet.
* `"Save"` (`path:134`) - NavigationBar button, enabled if `hasChanges` and not saving. Opens confirmation sheet or saves directly.
* `"A Prompt Meme has no matching or assignments. People post prompts and others claim them."` (`path:152`) - Shown if the challenge kind is `.promptMeme`.
* `"AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for a pinch hitter, but you can't run the match."` (`path:155`) - Shown if the challenge kind is `.giftExchange`.
* `"The challenge won't open or close until you hit Save."` (`path:172`) - Shown if signup/assignment dates have changed but not been saved.
* `"Save and Reveal"` (`path:197`, `200`) - Title and action button of the confirmation dialog shown when saving reveals works/authors.
* `"Are you sure you want to save? This will immediately reveal works or authors."` (`path:199`) - Message in the reveal confirmation dialog.
* `"Couldn't load challenge settings"` (`path:208`) - Title on the failure card shown in a `.failed` state.
* `"Try Again"` (`path:213`) - Button on the failure card. Triggers `load()`.

From `Features/Challenges/ChallengeSettingsEditSections.swift`:
* `"Collection settings"` (`path:31`) - Section header.
* `"Couldn't load"` / `"Loading…"` (`path:31`) - Subtitle based on `collectionLoadFailed`.
* `"Name"` (`path:34`) - Row label for collection title.
* `"Tagline"` (`path:35`) - Row label for collection description.
* `"None"` (`path:35`) - Value shown if the tagline/description is empty.
* `"Introduction"` (`path:36`) - Row label for collection introduction.
* `"FAQ"` (`path:37`) - Row label.
* `"Set"` (`path:37`) - Value shown if FAQ is not empty.
* `"None"` (`path:47`) - Text for word count if 0.
* `"word" / "words"` (`path:47`) - Pluralization helper for word counts.
* `"Match on"` (`path:59`) - Row label for match requirements.
* `"Nothing required"` (`path:61`) - Value shown if no specific match constraints exist.
* `"Requests that must match"` (`path:66`) - Row label.
* `"Count optional tags for"` (`path:80`) - Row label for optional tag counting settings.
* `"Anonymous until reveal"` (`path:141`) - Toggle label.
* `"Unrevealed until reveal"` (`path:143`) - Toggle label.
* `"Moderated sign-ups"` (`path:145`) - Toggle label.
* `"Closed to new sign-ups"` (`path:147`) - Toggle label.
* `"Prompts posted anonymously"` (`path:150`) - Toggle label.
* `"Dates use the challenge’s time zone shown on AO3. After a reveal happens, you can't move it to an earlier time in Kudos."` (`path:358`) - Condition: if schedule is editable.
* `"Kudos couldn't read the challenge's time zone. Dates are view-only and won't be saved."` (`path:360`) - Condition: if schedule is not editable.
* `"Prompts have been added so these settings can no longer be changed."` (`path:474`)
* `"Fandoms required per request"` (`path:521`)
* `"Fandoms allowed per request"` (`path:530`)
* `"Allow any fandom"` (`path:541`)
* `"Choosing “any” can match you with anything in the tag set."` (`path:544`)
* `"AO3 does the matching. Save these settings here, then use Open on AO3 to run or rerun the match. If potential matches already exist, your changes take effect after you regenerate them on AO3."` (`path:560`)
* `"Run matching"` (`path:582`), `"Opens AO3"` - Link to AO3 potential matches.
* `"Delete challenge"` (`path:586`), `"Opens AO3"` - Link to delete.
* `"Save changes"` (`path:605`)

### What it reads and writes
**Reads**:
iOS makes 4 requests per opening via `AO3Client.shared`:
1. `challengeSettings(slug: collectionSlug, request: request)` -> `auth.authenticatedRequest(for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug))` or `promptMemeEdit`.
2. `challengeSignUps(...)` -> `auth.authenticatedRequest(for: AO3ChallengeURL.signUps(slug: collectionSlug))` to load total sign-ups count.
3. `collectionTagSets(...)` -> `auth.authenticatedRequest(for: AO3CollectionURL.profile(slug: collectionSlug))` to load tag set links.
4. `auth.collectionEditForm(slug: collectionSlug)` -> `auth.authenticatedRequest(for: AO3CollectionURL.edit(slug: collectionSlug))`.

**Writes**:
`auth.updateChallengeSettings(validated, expectedGeneration: loadedGeneration)` (in `AO3ChallengeActions.swift:277`).
It prepares the POST request to `posted.actionURL` with `body: Self.formEncoded(AO3Client.challengeSettingsParameters(posted))` and `csrf: token`. 
The `isSaving` state boolean stops double submission: `guard !isSaving else { return }`. 
Confirmation logic (`AO3ChallengeActions.swift:298`):
```swift
if let notice = AO3Client.writeSuccessMessage(in: body)
    ?? (body.localizedCaseInsensitiveContains("successfully")
        ? "Challenge was successfully updated." : nil) { ... }
if (300...399).contains(status) { return .saved(message: "Challenge updated.", form: posted) }
```
Refusal logic:
```swift
if let error = AO3Client.writeErrorMessage(in: body) { ... }
if (200...299).contains(status), let parsed = try? AO3Client.parseChallengeSettingsForm(...), !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty { return .invalid(parsed) }
```
Messages shown depend on the parsed HTML notice/error.

### What Android has today
Android has the read-only `account/AO3ChallengeSettingsScreen.kt`. It shows the values without any local edit capabilities. "Edit settings" simply opens the gift form or meme form in the in-app browser (`/collections/SLUG/gift_exchange/edit` or `/prompt_meme/edit`). It does not load the assignment/tag-set pages if they aren't part of the single challenge settings probe.

### What `docs/AO3_NETWORKING_POLICY.md` says
- "No parallel request fan-out outside `AO3RequestCoordinator.withSlot`; no bypassing `AO3Client` with raw `URLSession` calls to AO3"
- "No retry loops around writes"
- "No background or bulk scraping of logged-in pages. Authenticated reads are limited to the user's own account lists, pages opened through explicit profile/work navigation..."
- "No queued write continues after its preparing auth service or `sessionGeneration` is observed stale."

---

## A challenge's matching and its moderator actions

### What is on screen
None of these actions (generate matches, send assignments, purge, potential matches list, single match edit) exist on iOS. 

### What it reads and writes
0 requests per opening. iOS does not make any requests for matching/assignments generation.

### What Android has today
Like iOS, Android does not have these. "Run matching" (`runMatching`) only opens the OS browser in live mode (`/collections/SLUG/potential_matches`).

### What `docs/AO3_NETWORKING_POLICY.md` says
Not applicable since no network calls are built for this.

---

## Support

### What is on screen
From `Features/Support/BugReportView.swift`:
* `"Found a bug? Describe what happened and Kudos will open a prefilled GitHub issue you can review and post. Nothing is sent automatically."` (`path:23`) - Under header.
* `"What went wrong?"` (`path:31`) - Section title.
* `"What happened, and what did you expect instead?"` (`path:33`) - TextField placeholder.
* `"Included with your report"` (`path:42`) - Section title.
* `"App version"` (`path:43`) - Displays current app version.
* `"System"` (`path:44`) - Displays system architecture/device.
* `"Only these app and system details are sent with your report. Nothing personal is included, and never your AO3 account."` (`path:45`)
* `"Continue on GitHub"` (`path:59`) - Opens the prefilled new-issue URL. Disabled if summary is empty.
* `"Browse existing issues"` (`path:66`) - Opens the GitHub issues page.
* `"The AO3 team can't help with Kudos, so please don't contact them about it."` (`path:71`) - Section footer.
* `"Report a Bug"` (`path:78`) - Navigation bar title.
* `"Cancel"` (`path:83`) - Toolbar dismissal button.
* `"Screenshot"` (`path:101`) - Section header (iOS only, condition: `screenshot` exists).
* `"Include a screenshot"` (`path:103`) - Toggle label (iOS only).
* `"Attached screenshot preview"` (`path:114`) - Accessibility label for image (iOS only, condition: `includeScreenshot` is true).
* `"Save or Share Screenshot"` (`path:119`) - Share link (iOS only).
* `"GitHub can't add the screenshot for you. Save it, then drag or paste it into the issue."` (`path:127`) - Section footer.

From `Features/Support/WhatsNew.swift`:
* `"What's New"` (`path:83`) - Navigation bar title.
* `"Done"` (`path:91`) - Dismissal button.
* `"Version \(entry.version)"` (`path:72`) - Section header for each unread changelog entry.

### What it reads and writes
0 requests per opening. It reads nothing from the network or the store; everything is locally bundled.

### What Android has today
Android has `account/BugReportScreen.kt` which implements the same strings (minus the iOS-only screenshot attachment section) and links out to GitHub. Android also has `support/WhatsNew.kt` displaying the bundled changelog entries.

### What `docs/AO3_NETWORKING_POLICY.md` says
Not applicable (no network traffic).

---

## Onboarding beyond the first run

### What is on screen
There are no additional screens or sheets in `Features/Onboarding/` that are not already described in `briefs/3ax-result.md`. The directory solely contains `WelcomeView.swift`, `SyncFolderOnboardingView.swift`, and `OnboardingComponents.swift`.

### What it reads and writes
N/A

### What Android has today
Android has implemented the exact routes and setup screens outlined in `briefs/3ax-result.md`.

### What `docs/AO3_NETWORKING_POLICY.md` says
N/A

---

## Summary

| Screen | iOS file | Lines of Swift | Requests per opening | Writes | Android today |
|---|---|---|---|---|---|
| Challenge Settings, Edit Form | `ChallengeSettingsEditView.swift`, `ChallengeSettingsEditSections.swift`, `AO3ChallengeActions.swift` | ~1300 | 4 | `auth.updateChallengeSettings` | Read-only screen `AO3ChallengeSettingsScreen.kt`, links to in-app browser |
| Matching & Moderator Actions | N/A | 0 | 0 | None | Links to external browser |
| Support | `BugReportView.swift`, `WhatsNew.swift` | ~270 | 0 | None | Native `BugReportScreen.kt` and `WhatsNew.kt` |
| Onboarding (post-first run) | N/A (all described in 3ax) | 0 | 0 | None | Implemented (described in 3ax) |
