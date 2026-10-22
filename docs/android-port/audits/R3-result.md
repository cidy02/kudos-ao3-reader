# R3: What iOS Has in Challenges That Android Lacks (A Reading, for Briefs)

This document is a reading of the Challenges screens and write actions implemented in the iOS codebase (`kudos-ao3-reader/`) that are missing or incomplete in the Android codebase (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`).

---

## 1. Assignments

### 1. Where on iOS
- **View files and lines:**
  - `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:15-535` (main view struct, state properties, body layout, header, segmented control, sections, rows, load pipeline)
  - `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:539-760` (view extension: state cards, pinch-hit rows, `perform(_:)`, floating bottom action bar, candidate pickers, confirmation copy)
  - `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:762-780` (view extension: `WriteKind` and `PendingWrite` data types)
- **Model files and lines:**
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:390-419` (`AO3ChallengeAssignment` struct, `isMatched`, and `badge(dueAt:now:)`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:585-600` (`AO3ChallengeAssignmentPage` struct and `AO3ChallengeAssignmentList` enum cases: `.assignments`, `.unfulfilled`, `.defaults`, `.pinchHits`)
  - `kudos-ao3-reader/Models/AO3ChallengeScreenModels.swift:75-100` (`AO3PinchHitRow` struct, `rows(open:claimed:)`, and `detail(dueText:)`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:755-766` (`AO3ChallengeURL.assignments(slug:list:page:)`, `assignmentDefault(slug:id:)`, `assignmentUpdateMultiple(slug:)`)
- **Service call & parser files and lines:**
  - Fetching assignments: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:57-86` (`allChallengeAssignments(slug:lists:request:)`) and `kudos-ao3-reader/Services/AO3Client+Challenges.swift:104-114` (`challengeAssignments(slug:list:page:request:)`)
  - Parsing assignments HTML: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:466-487` (`parseChallengeAssignmentsPage(_:slug:page:list:)`) and `kudos-ao3-reader/Services/AO3Client+Challenges.swift:808-844` (`parseAssignmentRow(_:details:slug:list:)`)
  - Maintainer write actions:
    - Claim pinch hit: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:120-133` (`claimPinchHit(slug:assignmentID:byline:expectedGeneration:using:)`)
    - Report default: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:140-149` (`markAssignmentDefaulted(slug:assignmentID:expectedGeneration:using:)`)
    - Multi-assignment update helper: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:156-173` (`updateAssignments(slug:field:fallback:expectedGeneration:using:)`)
  - Participant assignment default actions:
    - Participant self-default: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:100-113` (`reportAssignmentDefault(slug:assignmentID:)`)
    - Participant withdraw after sign-up close: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:94-96` (`withdrawSignUpAfterClose(slug:assignmentID:)`)

### 2. How a reader gets there
1. **From Collection Detail:**
   - Screen: `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift`
   - Entry point: `manageRow("Assignments")` at `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:362-370`:
     ```swift
     if show.dashboard.assignmentsURL != nil, show.isMaintainer {
         rows.append(AnyView(manageRow("Assignments") {
             ChallengeAssignmentsView(
                 collectionSlug: slug,
                 collectionTitle: title,
                 viewerIsOwner: show.collection.viewerIsOwner
             )
         }))
     }
     ```
   - Row label: `"Assignments"` with disclosure chevron (rendered via `SubjectFormRow(label: label, showsDisclosure: true)` at line 665).
   - Visibility condition: The collection's dashboard exposes an assignments URL (`show.dashboard.assignmentsURL != nil`) AND the viewer is a maintainer (`show.isMaintainer`).

2. **From Challenge Settings (Read View):**
   - Screen: `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift`
   - Entry point 1: `SubjectFormRow` for `"Assignments"` at `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift:417-423`:
     ```swift
     SubjectFormRow(
         label: "Assignments",
         value: assignmentsSummaryText,
         showsDisclosure: true
     )
     .subjectRowNavigation(accessibilityLabel: "Assignments") { assignmentsView }
     .buttonStyle(.plain)
     ```
     - Row label: `"Assignments"`, value: `assignmentsSummaryText` (e.g. `"<n> matched, <m> unmatched"`, `"None sent yet"`, or `"Couldn't load"`), with disclosure chevron.
   - Entry point 2: `SubjectFormRow` for `"Defaults and pinch hits"` at `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift:428-434`:
     ```swift
     SubjectFormRow(
         label: "Defaults and pinch hits",
         value: defaultsCount.map(String.init) ?? "Couldn't load",
         showsDisclosure: true
     )
     .subjectRowNavigation(accessibilityLabel: "Defaults and pinch hits") { assignmentsView }
     .buttonStyle(.plain)
     ```
     - Row label: `"Defaults and pinch hits"`, value: string count or `"Couldn't load"`, with disclosure chevron.
   - Target view builder: `ChallengeSettingsView.assignmentsView` at `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift:586-592`.

### 3. What is on screen
In order from top to bottom:

1. **Header Block (`SubjectHeaderBlock` at line 155):**
   - Kicker: `effectiveTitle` (`collectionTitle.isEmpty ? collectionSlug : collectionTitle`).
   - Title: `"Assignments"`.
   - Subtitle: `subtitleLine` (line 164) formed by joining with `" · "`:
     - When `phase == .loaded`:
       - If `loadErrors[.matched] == nil`: `"\(matched.count) matched"`
       - If `loadErrors[.unmatched] == nil`: `"\(unmatched.count) unmatched"`
     - If `worksDueAt?.dateText != nil`: `"works due \(due)"`

2. **Segmented Control Strip (`SubjectSegmentedControl` at line 177):**
   - Three segments in order:
     - `"Matched"`
     - `"Unmatched"`
     - `"Pinch hits"`
   - Initial selection: `.unmatched` (`@State private var segment: Segment = .unmatched` at line 43; unmatched leads because it is the actionable list for a maintainer).

3. **Phase-level States (lines 93-99):**
   - **Loading State:** Appears when `phase == .loading`:
     - Loading row (`loadingRow` at line 542): `ProgressView().controlSize(.small)` followed by text `"Loading assignments…"`.
   - **Failure State:** Appears when `phase == .failed(message)`:
     - Failure card (`failureCard(message)` at line 566):
       - Title: `"Couldn't load assignments"`
       - Body: `message` (e.g. `"Sign in to AO3 to view assignments."` when signed out).
       - Button: `"Try Again"` (action: `Task { await load() }`).

4. **Action Error Card (`actionErrorCard` at line 588):**
   - Appears when `actionErrorMessage != nil`:
     - SF Symbol: `"exclamationmark.triangle"` in red.
     - Text: `actionErrorMessage` (e.g. `"Couldn't record the default: <reason>"` or `"Couldn't claim that pinch hit: <reason>"`).
     - Dismiss button: SF Symbol `"xmark"` (clears `actionErrorMessage = nil`).

5. **Segment Content (switched by `segment`):**

   - **When segment is `Segment.matched` (`matchedSection` at line 201):**
     - Section rule header: title `"Matched"`, count `matched.count`.
     - Condition `loadErrors[.matched] != nil`:
       - Failure card: title `"Couldn't load matched assignments"`, body `error`, button `"Try Again"`.
     - Condition `matched.isEmpty` and no error:
       - Empty card: `"No matched assignments yet."`.
     - Condition `!matched.isEmpty` and no error:
       - List panel of assignment rows (`assignmentRow` at line 267):
         - Primary title: `"\(displayName(assignment.requestPseud)) → \(giverDisplay(for: assignment))"`
           - `displayName`: `assignment.requestPseud` or `"An anonymous sign-up"` if blank.
           - `giverDisplay`: `assignment.pinchHitterPseud` if present, else `assignment.offerPseud` if present, else `"Unclaimed"`.
         - Secondary subtitle (if present): `"Assigned \(mediumDate(sentAt)) · due \(due)"` (either half dropped if date is nil).
         - Status badge capsule (`statusBadge` at line 305):
           - If `badge == .delivered`: `"DELIVERED"` in green text and green pill background.
           - If `badge == .late`: `"LATE"` in secondary text and secondary pill background.
           - If `badge == .defaulted`: `"DEFAULTED"` in orange text and orange pill background.
           - If `badge == nil`: `EmptyView()`.

   - **When segment is `Segment.unmatched` (`unmatchedSection` at line 240):**
     - Section rule header: title `"Unmatched sign-ups"`, count `unmatched.count`.
     - Condition `loadErrors[.unmatched] != nil`:
       - Failure card: title `"Couldn't load defaults"`, body `error`, button `"Try Again"`.
     - Condition `unmatched.isEmpty` and no error:
       - Empty card: `"No defaulted assignments are waiting for a pinch hitter."`.
     - Condition `!unmatched.isEmpty` and no error:
       - Cards grouped in pairs (`unmatchedCard` at line 394):
         - Card title: `pair.count == 2 ? "Two sign-ups lost their giver" : "One sign-up lost its giver"`
         - Card prose:
           - Two names: `"The givers for \(pair[0]) and \(pair[1]) defaulted, and no pinch hitter has covered them yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."`
           - One name: `"The giver for \(pair[0]) defaulted, and no pinch hitter has covered it yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."`
         - Button: Label with title `"Open on AO3"` and SF Symbol `"safari"` (opens web URL `AO3ChallengeURL.assignments(slug: collectionSlug, list: .pinchHits)`).

   - **When segment is `Segment.pinchHits` (`pinchHitsSection` at line 219):**
     - Section rule header: title `"Pinch hits"`, count `pinchHitRows.count`.
     - Condition `loadErrors[.pinchHits] != nil || loadErrors[.unmatched] != nil`:
       - Failure card: title `"Couldn't load pinch hits"`, body error, button `"Try Again"`.
     - Condition `pinchHitRows.isEmpty` and no error:
       - Empty card: `"No pinch hits open right now."`.
     - Condition `!pinchHitRows.isEmpty` and no error:
       - List panel of pinch hit rows (`pinchHitRow` at line 612):
         - Row title: `"Pinch hit #\(row.number)"`
         - Pill tag:
           - When `row.isOpen`: `"OPEN"` (accent background)
           - When `!row.isOpen`: `"CLAIMED"` (secondary background)
         - Row detail:
           - When open: `"Requested by \(recipient)"`
           - When claimed: `"Claimed by \(hitter) for \(recipient)"` (+ optional `" · due \(dueText)"`)
         - Claim button (`claimButton` at line 345):
           - Visible condition: `row.isOpen && auth.isLoggedIn && AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner)`.
           - Label: `"Claim"` (accent pill; displays small `ProgressView()` while in flight; disabled when any item is in flight).

6. **Footnote (`footnote` at line 437):**
   - Appears on all loaded/idle segments:
     `"You can view assignments and pinch hits here one page at a time. You can report a default or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3."`

7. **Bottom Action Bar (`bottomActionBar` at line 682):**
   - Appears only when `auth.isLoggedIn && phase == .loaded && AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner)`.
   - Button 1: `"Report a default"`
     - Disabled condition: `reportable.isEmpty || itemInFlight != nil` (`reportable` = `matched.filter { !$0.isFulfilled && !$0.isDefaulted }`).
     - Action: sets `picking = .reportDefault`.
   - Button 2: `"Claim a pinch hit"`
     - Disabled condition: `unmatched.isEmpty || itemInFlight != nil`.
     - Action: sets `picking = .claimPinchHit`.

8. **Confirmation Dialog (`confirmationDialog` at line 124):**
   - Triggered when `picking != nil`.
   - Dialog title: `picking?.title` (`"Report a default"` or `"Claim a pinch hit"`).
   - Candidate buttons (`candidateLabel` at line 745):
     - Displays one button per candidate: `"\(giverDisplay(for: assignment)) → \(displayName(assignment.requestPseud))"`.
     - Action: sets `pendingWrite = PendingWrite(kind: kind, assignment: assignment)`.
   - Cancel button: `"Cancel"` (role `.cancel`).

9. **Confirmation Alert (`alert` at line 137):**
   - Triggered when `pendingWrite != nil`.
   - Alert title:
     - For `.reportDefault`: `"Report this default?"`
     - For `.claimPinchHit`: `"Claim this pinch hit?"`
   - Alert message (`confirmationMessage` at line 749):
     - For `.reportDefault`: `"This marks \(giverDisplay(for: write.assignment))'s assignment for \(recipient) as defaulted on AO3 and adds it to the pinch hits waiting for cover."`
     - For `.claimPinchHit`: `"You'll be the pinch hitter for \(recipient)'s gift\(due)."` (where `due` is `", due <date>"` or empty).
   - Action button:
     - For `.reportDefault`: `"Report default"` (role `.destructive`).
     - For `.claimPinchHit`: `"Claim"` (role `nil`).
   - Cancel button: `"Cancel"` (role `.cancel`).

### 4. What it reads and writes
- **Network Reads:**
  1. Matched assignments:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/assignments?fulfilled=true&page=:page` and `https://archiveofourown.org/collections/:slug/assignments?unfulfilled=true&page=:page` (combined as `AO3ChallengeAssignmentList.sent`).
     - When / how often: On screen load (`.task(id: auth.sessionGeneration)`), pull-to-refresh (`.refreshable`), or after completing a write.
     - What stops a repeat: Session generation tracking (`AO3CollectionSessionReload.nextLoadGeneration` and `AO3CollectionSessionReload.shouldApplyLoad`). Stale load tasks are ignored.
  2. Unmatched defaults:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/assignments?defaulted=true&page=:page` (`AO3ChallengeAssignmentList.defaults`).
     - When / how often: Same as matched assignments.
  3. Pinch hits:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/assignments?pinch_hits=true&page=:page` (`AO3ChallengeAssignmentList.pinchHits`).
     - When / how often: Same as matched assignments.
  4. Challenge works-due date:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/gift_exchange/edit` (`AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)`).
     - When / how often: Best-effort fetch on load to resolve `worksDueAt = form.settings.worksDueAt`.

- **Network Writes:**
  1. Maintainer: Claim Pinch Hit (`auth.claimPinchHit`):
     - Method: HTTP POST with `_method=put` override.
     - Action URL: `https://archiveofourown.org/collections/:slug/assignments/update_multiple` (`AO3ChallengeURL.assignmentUpdateMultiple(slug: slug)`).
     - Referer: `https://archiveofourown.org/collections/:slug/assignments?defaulted=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .defaults, page: 1)`).
     - Headers:
       - `Content-Type: application/x-www-form-urlencoded`
       - `Referer: <referer>`
       - `X-CSRF-Token: <token>`
     - Request body Swift builder:
       ```swift
       let params: [(String, String)] = [("_method", "put"), ("authenticity_token", token), ("cover_\(assignmentID)", pinch)]
       ```
     - Verification & Acceptance logic:
       ```swift
       let (status, body) = try await submitWrite(request, using: client)
       try throwIfChallengeWriteFailed(status: status, body: body, fallback: "AO3 couldn't claim that pinch hit.")
       ```
       Where `throwIfChallengeWriteFailed` calls `AO3AuthService.collectionWriteVerdict(status:body:fallback:)`:
       - Error detection selector: `doc.select("#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution").first()?.text()` -> throws `.rejected(error)`.
       - Success detection selector: `doc.select(".flash.comment_notice, .flash.notice").first()?.text()` -> `nil` (success).
       - Status code `300...399` -> `nil` (success).
       - Status code `200...299` without notice flash -> throws `.unconfirmed`.
       - Other status codes -> throws `.rejected(fallback)`.
  2. Maintainer: Mark Assignment Defaulted (`auth.markAssignmentDefaulted`):
     - Method: HTTP POST with `_method=put` override.
     - Action URL: `https://archiveofourown.org/collections/:slug/assignments/update_multiple`.
     - Referer: `https://archiveofourown.org/collections/:slug/assignments?unfulfilled=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .unfulfilled, page: 1)`).
     - Request body Swift builder:
       ```swift
       let params: [(String, String)] = [("_method", "put"), ("authenticity_token", token), ("default_\(assignmentID)", "1")]
       ```
     - Verification & Acceptance logic:
       Same `throwIfChallengeWriteFailed` evaluation, with fallback `"AO3 couldn't record the default."`.
  3. Participant: Report Self-Default (`auth.reportAssignmentDefault`):
     - Method: HTTP POST with `_method=patch` override.
     - Action URL: `https://archiveofourown.org/collections/:slug/assignments/:id/default` (`AO3ChallengeURL.assignmentDefault(slug: slug, id: assignmentID)`).
     - Referer: `https://archiveofourown.org/collections/:slug/assignments?fulfilled=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .assignments, page: 1)`).
     - Request body Swift builder:
       ```swift
       body: Self.formEncoded([("_method", "patch"), ("authenticity_token", token)])
       ```
     - Verification & Acceptance logic:
       Same `throwIfChallengeWriteFailed` evaluation, with fallback `"AO3 couldn't record the default."`.
  4. Fulfilling an Assignment:
     - On AO3, an assignment is fulfilled when the assigned writer posts a work fulfilling the challenge prompt (`isFulfilled` is parsed from `list == .assignments || status == "complete" || status == "fulfilled"`).
     - In the Kudos iOS reader, the assignment row in `ChallengeAssignmentsView` is read-only regarding delivery: rows display the `"DELIVERED"` badge and are filtered out of the `"Report a default"` candidate list (`matched.filter { !$0.isFulfilled && !$0.isDefaulted }`).

- **Stored Values:**
  - None. All data is transient in-memory state (`@State private var matched`, `@State private var unmatched`, `@State private var pinchHits`). No values are persisted to SwiftData or `UserDefaults`, nothing is saved into the backup archive, and no change is made to the reader's local library.

### 5. Where it would go on Android
- **Nearest existing screen & file:**
  - `account/AO3ChallengeSettingsScreen.kt:179-191` currently hosts the read-only assignments section:
    ```kotlin
    ChallengeSection("Assignments")
    SettingsPanel(Modifier.padding(top = 8.dp)) {
        SubjectFormRow("Sign-ups", value = data.signUpTotal?.toString() ?: "Couldn't load", showsDisclosure = true,
            valueMaxLines = Int.MAX_VALUE, onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeSignUpsView(slug)) })
        SubjectRowSeparator()
        // Corrected brief: no assignment read, count, failed-count label or invented placeholder.
        SubjectFormRow("Assignments", showsDisclosure = true,
            onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeAssignmentsView(slug)) })
        SubjectRowSeparator()
        SubjectFormRow("Defaults and pinch hits", showsDisclosure = true,
            onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeAssignmentsView(slug)) })
    }
    ```
  - And in `account/AO3CollectionDetailScreen.kt:620`:
    ```kotlin
    show.dashboard.assignmentsUrl?.let { add(AO3CollectionManageAction("Assignments", it)) }
    ```
  - Currently on Android, tapping `"Assignments"` or `"Defaults and pinch hits"` opens the AO3 website in an in-app browser or external browser (`onOpenWeb`).
- **Components already there drawing similar UI:**
  - `SubjectHeaderBlock` at `ui/subject/SubjectHeaderBlock.kt:24`
  - `SectionRuleHeader` at `ui/subject/SectionRuleHeader.kt:18` (aliased as `ChallengeSection` in `AO3ChallengeSettingsScreen.kt:207`)
  - `SettingsPanel` at `settings/SettingsPanel.kt:16`
  - `SubjectFormRow` at `ui/subject/SubjectFormRow.kt:25`
  - `SubjectRowSeparator` at `ui/subject/SubjectRowSeparator.kt:12`
  - Segmented control / Tab row: `BrowseScreen.kt:156` and `account/AO3CollectionModerationScreen.kt:105-132`
  - Floating action panel: `account/AO3ChallengeSignUpScreen.kt:189-198` and `account/AO3CollectionModerationScreen.kt:450-480`
  - Dialogs: `AlertDialog` in `account/AO3CollectionFormScreen.kt:85-98`
- **What Android already has:**
  - Android already parses the collection's assignments URL into `AO3CollectionShow.assignmentsUrl` (`network/ao3/account/AO3CollectionParser.kt:120`).
  - Android has URL builder `ChallengeSettingsDestinations.challengeAssignmentsView(slug)` (`network/ao3/account/AO3ChallengeSettings.kt:42`).
  - Android does **not** have assignment models, assignment HTML parsers, assignment state holders, or assignment write endpoints.

### 6. Size
- **Large** (a complete screen with multi-list pagination, 3 segment modes, HTML blurb joining, owner control gating, candidate picker sheets, confirmation alerts, and 2 write mutations).

---

## 2. Challenge Settings, Editing

### 1. Where on iOS
- **View files and lines:**
  - `kudos-ao3-reader/Features/Challenges/ChallengeSettingsEditView.swift:26-849` (main edit view, form state, header, sections, date rows, range steppers, restriction toggles, bottom bar, loading/saving handlers, confirmation dialogs)
  - `kudos-ao3-reader/Features/Challenges/ChallengeSettingsEditSections.swift:10-186` (view extension: Basics collection rows, match settings panels, anonymity and moderation toggles)
- **Model files and lines:**
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:29-166` (`AO3ChallengeSettingsForm`, `AO3ChallengeSettings`, `AO3ChallengeInstant`, `AO3ChallengeSignUpLimits`, `AO3PromptRestrictionSnapshot`, `AO3PotentialMatchSettings`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:735-748` (`AO3ChallengeURL.giftExchangeEdit`, `AO3ChallengeURL.promptMemeEdit`)
- **Service call & parser files and lines:**
  - Form read & parser: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:9-25` (`challengeSettings(slug:request:)`), `kudos-ao3-reader/Services/AO3Client+Challenges.swift:157-235` (`parseChallengeSettingsForm`), `kudos-ao3-reader/Services/AO3Client+Challenges.swift:243-257` (`submittedHiddenFields`)
  - Parameter serialization: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:259-324` (`challengeSettingsParameters(_:)`) and `kudos-ao3-reader/Services/AO3Client+Challenges.swift:676-710` (`promptRestrictionParameters(_:prefix:)`)
  - Mutating write call: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:261-317` (`updateChallengeSettings(_:expectedGeneration:using:)`)

### 2. How a reader gets there
- Screen: `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift`
- Entry point: `SubjectFormRow` for `"Edit settings"` at `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift:120-131`:
  ```swift
  if AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
      Section {
          SubjectFormRow(label: "Edit settings", showsDisclosure: true) { EmptyView() }
              .subjectRowNavigation(accessibilityLabel: "Edit settings") {
                  ChallengeSettingsEditView(
                      collectionSlug: collectionSlug,
                      collectionTitle: effectiveTitle,
                      viewerIsOwner: viewerIsOwner
                  )
              }
              .subjectPanel()
              .pageBodyRow(top: 14, gutter: gutter)
      }
  }
  ```
- Row label: `"Edit settings"` with disclosure chevron.
- Visibility condition: Only collection owners reach this control (`AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner)`).

### 3. What is on screen
In order from top to bottom:

1. **Header Block (`SubjectHeaderBlock` at line 164):**
   - Kicker: `settings.kind == .giftExchange ? "Gift exchange · moderator" : "Prompt meme · moderator"`.
   - Title: `"Challenge settings"`.
   - Subtitle: `signUpTotal.map { "\(effectiveTitle) · \(AO3ChallengeCountText.plural($0, "sign-up"))" } ?? effectiveTitle`.

2. **Notice Card (`noticeCard` at line 671):**
   - Appears when `saveNotice != nil`:
     - SF Symbol: `"checkmark.circle"` in accent tint.
     - Text: `saveNotice` (e.g. `"Challenge was successfully updated."`).

3. **General Error Cards (`errorCard` at line 684):**
   - Appears for each string in `form?.generalErrors`:
     - SF Symbol: `"exclamationmark.triangle"` in red.
     - Text: `error`.

4. **Phase-level States (lines 111-120):**
   - **Loading State:** Appears when `phase == .loading`:
     - Loading row (`loadingRow` at line 639): `ProgressView().controlSize(.small)` followed by text `"Loading challenge settings…"`.
   - **Failure State:** Appears when `phase == .failed(message)`:
     - Failure card (`failureCard(message)` at line 651):
       - Title: `"Couldn't load challenge settings"`.
       - Body: `message`.
       - Button: `"Try Again"` (action: `Task { await load() }`).

5. **Section 1: Basics (lines 178-186 and `ChallengeSettingsEditSections.swift:16-48`):**
   - SectionRuleHeader: `"Basics"`.
   - Rows (`basicsRows`):
     - If collection form is loading/failed:
       - Row: `"Collection settings"`, value: `collectionLoadFailed ? "Couldn't load" : "Loading…"`.
     - When loaded:
       - Row: `"Name"`, value: `collection.title` (pushes `AO3CollectionFormView(slug: collectionSlug)`).
       - Row: `"Tagline"`, value: `collection.description.isEmpty ? "None" : collection.description` (pushes `AO3CollectionFormView`).
       - Row: `"Introduction"`, value: `Self.wordCountText(collection.introduction)` (e.g. `"<n> words"` or `"None"`; pushes `AO3CollectionFormView`).
       - Row: `"FAQ"`, value: `collection.faq.isEmpty ? "None" : "Set"` (pushes `AO3CollectionFormView`).
   - Instructions card (`instructionsCard` at line 256):
     - Field label: `"Sign-up instructions"`.
     - Placeholder: `"Describe the challenge for people signing up…"`.
     - Multi-line `TextEditor` bound to `form?.settings.signupInstructionsGeneral`.

6. **Section 2: Schedule (lines 188-196 and lines 282-365):**
   - SectionRuleHeader: `"Schedule"`.
   - Field error cards for: `signups_close_at`, `assignments_due_at`, `works_reveal_at`, `authors_reveal_at`.
   - Date rows in order (only rows where `isOnForm == true`):
     - Row: `"Sign-ups open"` (compact date/time picker in UTC or `"Not set"` + button `"Set"`).
     - Row: `"Sign-ups close"` (compact date/time picker in UTC or `"Not set"` + button `"Set"`).
     - Row: `"Assignments sent"` (read-only value: `settings.assignmentsSentAt?.formatted(date: .abbreviated, time: .shortened) ?? "Manual"`).
     - Row: `"Works due"` (compact date/time picker in UTC or `"Not set"` + button `"Set"`).
     - Row: `"Works revealed"` (compact date/time picker in UTC or `"Not set"` + button `"Set"`).
     - Row: `"Creators revealed"` (compact date/time picker in UTC or `"Not set"` + button `"Set"`).
     - Row: `"Time zone"` (value: `settings.scheduleIsEditable ? settings.timeZoneName : "Unavailable"`).
   - Footnote (`scheduleFootnote` at line 356):
     - When editable: `"Dates use the challenge’s time zone shown on AO3. After a reveal happens, you can't move it to an earlier time in Kudos."`
     - When not editable: `"Kudos couldn't read the challenge's time zone. Dates are view-only and won't be saved."`

7. **Section 3: Sign-up limits (lines 198-211 and lines 369-479):**
   - SectionRuleHeader: `"Sign-up limits"`.
   - Field error cards for: `requests_num_required`, `requests_num_allowed`, `offers_num_required`, `offers_num_allowed`.
   - Range rows (`limitsPanel` at line 396):
     - Row: `"Requests"` with menu `"Requests required"` (values 0...20), text `"to"`, and menu `"Requests allowed"` (values 0...20).
     - Row (gift exchange only): `"Offers"` with menu `"Offers required"` (values 0...20), text `"to"`, and menu `"Offers allowed"` (values 0...20).
   - Field group label: `"Request restrictions"`.
   - Toggles (`requestRestrictionTogglesPanel` at line 437):
     - Toggle: `"URL allowed in a request"` (disabled if `!restrictionIsEditable("url_allowed")`).
     - Toggle: `"Description required"` (disabled if `!restrictionIsEditable("description_required")`).
     - Toggle: `"Optional tags allowed"` (disabled if `!restrictionIsEditable("optional_tags_allowed")`).
   - Footnote (when `restrictionControlsLocked`):
     `"Prompts have been added so these settings can no longer be changed."`

8. **Section 4: Tag sets (lines 213-220 and lines 500-511):**
   - Appears only if `!tagSetLinks.isEmpty`.
   - SectionRuleHeader: `tagSetLinks.count == 1 ? "Tag set" : "Tag sets"`.
   - Rows: for each link, row with `link.title` and disclosure chevron, pushing `TagSetView(tagSetID: link.id, tagSetTitle: link.title, isModerator: true)`.

9. **Section 5: Matching (lines 222-230, lines 518-567, and `ChallengeSettingsEditSections.swift:54-98`):**
   - SectionRuleHeader: `"Matching"`.
   - Potential Match panels (if `settings.matchSettings != nil`):
     - Row: `"Match on"`, value: comma-separated labels or `"Nothing required"`.
     - Option row: `"Requests that must match"`, popup menu with values.
     - For each tag type in `AO3PotentialMatchSettings.tagTypes` (`"fandom"`, `"character"`, `"relationship"`, `"freeform"`):
       - Option row: `AO3PotentialMatchSettings.label(type)` (`"Fandoms"`, `"Characters"`, `"Relationships"`, `"Additional tags"`), popup menu with values.
     - Group label: `"Count optional tags for"`.
     - For each tag type:
       - Toggle: `AO3PotentialMatchSettings.label(type)`.
   - Group label: `"Request fandoms"`.
   - Steppers panel (`matchingPanel` at line 518):
     - Stepper row: `"Fandoms required per request"`, range 0...10 (disabled if `!restrictionIsEditable("fandom_num_required")`).
     - Stepper row: `"Fandoms allowed per request"`, range 0...10 (disabled if `!restrictionIsEditable("fandom_num_allowed")`).
     - Toggle: `"Allow any fandom"`, title subtitle: `"Choosing “any” can match you with anything in the tag set."` (disabled if `!restrictionIsEditable("allow_any_fandom")`).
   - Footnote (`matchingFootnote` at line 559):
     `"AO3 does the matching. Save these settings here, then use Open on AO3 to run or rerun the match. If potential matches already exist, your changes take effect after you regenerate them on AO3."`

10. **Section 6: Anonymity and moderation (lines 232-236 and `ChallengeSettingsEditSections.swift:139-161`):**
    - SectionRuleHeader: `"Anonymity and moderation"`.
    - Collection-backed toggles (disabled if `collectionForm == nil`):
      - Toggle: `"Anonymous until reveal"`
      - Toggle: `"Unrevealed until reveal"`
      - Toggle: `"Moderated sign-ups"`
      - Toggle: `"Closed to new sign-ups"`
    - Prompt meme only:
      - Toggle: `"Prompts posted anonymously"` (challenge setting `form?.settings.isAnonymous`).

11. **Section 7: At AO3 (lines 237-241 and lines 580-591):**
    - SectionRuleHeader: `"At AO3"`.
    - Row: `"Run matching"`, value: `"Opens AO3"`, disclosure chevron (opens `settings.matchingOpenOnAO3`).
    - Row: `"Delete challenge"`, value: `"Opens AO3"`, disclosure chevron (opens `deleteChallengeURL`).

12. **Bottom Action Bar (`bottomActionBar` at line 595):**
    - Button: `"Save changes"` (shows small `ProgressView()` in accent text when `isSaving`).
      - Disabled condition: `!AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) || !Self.canStartSave(isSaving: isSaving, hasForm: form != nil)`.
      - Action: `saveTapped()`.

13. **Confirmation Alert (`alert("Reveal now?")` at line 142):**
    - Triggered when saving turns off unrevealed or anonymous (`saveRevealsSomething == true`).
    - Title: `"Reveal now?"`.
    - Message: `"Turning off Unrevealed makes every work visible. Turning off Anonymous shows every creator. You can't reverse either change in Kudos."`.
    - Button 1: `"Save and reveal"` (role `.destructive`, action: `Task { await save() }`).
    - Button 2: `"Cancel"` (role `.cancel`).

### 4. What it reads and writes
- **Network Reads:**
  1. Challenge settings edit form:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/gift_exchange/edit` or `https://archiveofourown.org/collections/:slug/prompt_meme/edit` (`AO3ChallengeURL.giftExchangeEdit` / `promptMemeEdit`).
     - When / how often: On view load (`.task(id: auth.sessionGeneration)`) and pull-to-refresh (`.refreshable`).
     - What stops a repeat: Generation gating via `AO3CollectionSessionReload.nextLoadGeneration`.
  2. Total sign-up count:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/signups` (`AO3ChallengeURL.signUps`).
     - When / how often: Loaded alongside challenge settings to resolve header count.
  3. Collection profile tag sets:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/profile` (`AO3CollectionURL.profile`).
     - When / how often: Loaded alongside challenge settings.
  4. Collection basics and moderation switches:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/edit` (`auth.collectionEditForm(slug: collectionSlug)`).
     - When / how often: Loaded alongside challenge settings.

- **Network Writes:**
  1. Challenge settings update (`auth.updateChallengeSettings` at `AO3ChallengeActions.swift:261`):
     - Method: HTTP POST (with optional `_method` override from form).
     - Action URL: `posted.actionURL` (`/collections/:slug/gift_exchange` or `/collections/:slug/prompt_meme`).
     - Referer: `https://archiveofourown.org/collections/:slug/gift_exchange/edit` or `/prompt_meme/edit`.
     - CSRF: Single-shot `fetchCSRFPage(at: referer)` before submit.
     - Headers:
       - `Content-Type: application/x-www-form-urlencoded`
       - `Referer: <referer>`
       - `X-CSRF-Token: <token>`
     - Request parameters Swift builder (`AO3Client.challengeSettingsParameters` at `AO3Client+Challenges.swift:259`):
       - Ordered key-value pairs:
         ```swift
         ("authenticity_token", form.csrfToken)
         // if method override: ("_method", method)
         ("\(prefix)[signup_open]", settings.signupOpen ? "1" : "0")
         // if scheduleIsEditable: ("\(prefix)[time_zone]", settings.timeZoneName)
         // for dates in [signups_open_at, signups_close_at, assignments_due_at, works_reveal_at, authors_reveal_at] where isOnForm:
         ("\(prefix)[\(key)_string]", instant.postedString)
         ("\(prefix)[requests_num_required]", String(settings.limits.requestsRequired))
         ("\(prefix)[requests_num_allowed]", String(settings.limits.requestsAllowed))
         ("\(prefix)[signup_instructions_general]", settings.signupInstructionsGeneral)
         ("\(prefix)[signup_instructions_requests]", settings.signupInstructionsRequests)
         ("\(prefix)[request_url_label]", settings.requestURLLabel)
         ("\(prefix)[request_description_label]", settings.requestDescriptionLabel)
         // if giftExchange:
         ("\(prefix)[offers_num_required]", String(settings.limits.offersRequired))
         ("\(prefix)[offers_num_allowed]", String(settings.limits.offersAllowed))
         ("\(prefix)[signup_instructions_offers]", settings.signupInstructionsOffers)
         ("\(prefix)[offer_url_label]", settings.offerURLLabel)
         ("\(prefix)[offer_description_label]", settings.offerDescriptionLabel)
         ("\(prefix)[requests_summary_visible]", settings.requestsSummaryVisible ? "1" : "0")
         // if promptMeme:
         ("\(prefix)[anonymous]", settings.isAnonymous ? "1" : "0")
         // Prompt restriction parameters:
         // id, optional_tags_allowed, title_required, title_allowed, description_required, description_allowed, url_required, url_allowed
         // fandom_num_required, fandom_num_allowed, allow_any_fandom, require_unique_fandom
         // character_num_required, character_num_allowed, allow_any_character, require_unique_character
         // relationship_num_required, relationship_num_allowed, allow_any_relationship, require_unique_relationship
         // freeform_num_required, freeform_num_allowed, allow_any_freeform, require_unique_freeform
         // tag_sets_to_add
         // Potential match settings parameters (if matchSettings != nil):
         ("\(base)[id]", match.id)
         ("\(base)[num_required_prompts]", String(match.numRequiredPrompts))
         // for each type in tagTypes:
         ("\(base)[num_required_\(type)]", String(match.numRequired[type] ?? 0))
         ("\(base)[include_optional_\(type)]", match.includeOptional[type] == true ? "1" : "0")
         // Plus enabled hidden inputs preserved from the original page
         ```
     - Verification & Acceptance logic:
       ```swift
       let (status, body) = try await submitWrite(request, using: client)
       if let error = AO3Client.writeErrorMessage(in: body) {
           var invalid = (try? AO3Client.parseChallengeSettingsForm(body, slug: form.collectionSlug, kind: form.kind)) ?? posted
           invalid.generalErrors = [error] + invalid.generalErrors.filter { $0 != error }
           return .invalid(invalid)
       }
       if let notice = AO3Client.writeSuccessMessage(in: body)
           ?? (body.localizedCaseInsensitiveContains("successfully") ? "Challenge was successfully updated." : nil) {
           let parsed = (try? AO3Client.parseChallengeSettingsForm(body, slug: form.collectionSlug, kind: form.kind)) ?? posted
           return .saved(message: notice, form: parsed)
       }
       if (300...399).contains(status) {
           return .saved(message: "Challenge updated.", form: posted)
       }
       if (200...299).contains(status),
          let parsed = try? AO3Client.parseChallengeSettingsForm(body, slug: form.collectionSlug, kind: form.kind),
          !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
           return .invalid(parsed)
       }
       throw AO3ChallengeWriteError.unconfirmed
       ```
  2. Collection moderation switches update (`auth.updateCollection` at line 818):
     - Executed conditionally if `collectionFormChanged == true`.
     - Method: HTTP POST with `_method=put` override.
     - Action URL: `https://archiveofourown.org/collections/:slug` (`AO3CollectionFormUrls.update(slug)`).

- **Stored Values:**
  - None. State is held in `@State var form` and `@State var collectionForm`. No persistence to SwiftData or backup archive. No change to local library.

### 5. Where it would go on Android
- **Nearest existing screen & file:**
  - `account/AO3ChallengeSettingsScreen.kt:105-110` currently has an `"Edit settings"` row when `viewerIsOwner == true`:
    ```kotlin
    if (viewerIsOwner) item {
        SettingsPanel(Modifier.padding(top = 14.dp)) {
            SubjectFormRow("Edit settings", showsDisclosure = true,
                onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeSettingsEditView(slug, kind)) })
        }
    }
    ```
    This currently delegates to `onOpenWeb(...)` rather than opening a native edit screen.
- **Components already there drawing similar UI:**
  - Form panels: `settings/SettingsPanel.kt:16`
  - Rows with disclosure: `ui/subject/SubjectFormRow.kt:25`
  - Multiline input fields: `settings/SubjectTextFieldRow.kt:22` (used for prompt/collection description)
  - Toggles: `ui/subject/SubjectToggle.kt:20`
  - Buttons: `settings/SettingsActionRow.kt:15`
  - Section headers: `ui/subject/SectionRuleHeader.kt:18`
- **What Android already has:**
  - Android already parses the collection form and writes collection settings (`network/ao3/account/AO3CollectionForm.kt`, `account/AO3CollectionFormScreen.kt`, and `network/ao3/writes/AO3WriteRepository.kt:324` `saveCollection`).
  - Android currently has a strictly read-only representation of challenge settings (`network/ao3/account/AO3ChallengeSettings.kt:50` notes: `/** Only the fields 1by displays. No form serializer, assignment parser or write path. */`).
  - Android lacks `AO3ChallengeSettingsForm`, serializer, validation logic, and the `updateChallengeSettings` write method in `AO3WriteRepository.kt`.

### 6. Size
- **Large** (a complete edit screen with 7 sections, date pickers, range menus, match settings toggles, collection preference sync, and dedicated form POST).

---

## 3. The Sign-Ups List for a Challenge, and Withdrawing or Deleting a Sign-Up

### 1. Where on iOS
- **View files and lines:**
  - Moderator's sign-ups list: `kudos-ao3-reader/Features/Challenges/ChallengeSignUpsView.swift:9-524` (`ChallengeSignUpsView`)
  - Moderator's read of individual participant sign-up: `kudos-ao3-reader/Features/Challenges/ChallengeSignUpsView.swift:530-622` (`ChallengeSignUpDetailView`)
  - Participant's sign-up editor & withdraw action: `kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:9-150`, lines 227-233 (withdraw section), lines 442-471 (withdraw panel), and lines 683-697 (`performWithdraw()`)
- **Model files and lines:**
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:421-440` (`AO3ChallengeSignUp`, `AO3ChallengePrompt`, `requestTagSummary`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:574-583` (`AO3ChallengeSignUpPage`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:814-878` (`AO3ChallengeSignUpMatching`: `joining(_:assignments:)`, `state(of:assignments:)`, `ownSignUpID(in:login:)`)
  - `kudos-ao3-reader/Models/AO3ChallengeModels.swift:750-753` (`AO3ChallengeURL.signUps(slug:page:)`, `AO3ChallengeURL.signUp(slug:id:)`, `AO3ChallengeURL.confirmDeleteSignUp(slug:id:)`)
- **Service call & parser files and lines:**
  - Sign-ups index reader: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:27-37` (`challengeSignUps`) and lines 332-360 (`parseChallengeSignUpsPage`)
  - Sign-up total count: `kudos-ao3-reader/Services/AO3Client+Challenges.swift:39-55` (`challengeSignUpTotal`)
  - Withdraw mutation service call: `kudos-ao3-reader/Services/AO3ChallengeActions.swift:74-87` (`withdrawSignUp(slug:signUpID:)`)
  - Self-default mutation (post-close withdrawal): `kudos-ao3-reader/Services/AO3ChallengeActions.swift:94-113` (`withdrawSignUpAfterClose(slug:assignmentID:)` / `reportAssignmentDefault(slug:assignmentID:)`)

### 2. How a reader gets there
1. **To the Sign-ups List (`ChallengeSignUpsView`):**
   - **From Collection Detail:**
     - Screen: `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift`
     - Entry point: `manageRow("Sign-ups")` at `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:357-361`:
       ```swift
       if show.dashboard.signUpsURL != nil, show.isMaintainer {
           rows.append(AnyView(manageRow("Sign-ups") {
               ChallengeSignUpsView(collectionSlug: slug, collectionTitle: title)
           }))
       }
       ```
     - Row label: `"Sign-ups"` with disclosure chevron.
     - Visibility condition: Collection dashboard has `signUpsURL` AND user is maintainer (`show.isMaintainer`).
   - **From Challenge Settings:**
     - Screen: `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift`
     - Entry point: `SubjectFormRow` for `"Sign-ups"` at `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift:402-413`:
       ```swift
       SubjectFormRow(
           label: "Sign-ups",
           value: signUpTotal.map(String.init) ?? "Couldn't load",
           showsDisclosure: true
       )
       .subjectRowNavigation(accessibilityLabel: "Sign-ups") {
           ChallengeSignUpsView(
               collectionSlug: collectionSlug,
               collectionTitle: effectiveTitle
           )
       }
       .buttonStyle(.plain)
       ```
     - Row label: `"Sign-ups"`, value: string count or `"Couldn't load"`, with disclosure chevron.

2. **To the Participant's Sign-up (`ChallengeSignUpView`) and Withdraw Action:**
   - **From Collection Detail:**
     - Screen: `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:382-386`:
       ```swift
       if show.dashboard.signUpsURL != nil, auth.isLoggedIn {
           rows.append(AnyView(manageRow("Your Sign-up") {
               ChallengeSignUpView(collectionSlug: slug, collectionTitle: title)
           }))
       }
       ```
     - Row label: `"Your Sign-up"` with disclosure chevron.
     - Visibility condition: `show.dashboard.signUpsURL != nil && auth.isLoggedIn`.
   - **From the Sign-ups List Bottom Bar:**
     - Screen: `kudos-ao3-reader/Features/Challenges/ChallengeSignUpsView.swift:348-356` (`"Your sign-up"` button) and lines 374-388 (`"Create sign-up"` button).

### 3. What is on screen
#### Part A: Moderator's Sign-ups List (`ChallengeSignUpsView`)
In order from top to bottom:

1. **Header Block (`SubjectHeaderBlock` at line 149):**
   - Kicker: `effectiveTitle`.
   - Title: `"Sign-ups"`.
   - Subtitle: `subtitleText` (line 137): `"<n> sign-ups · open until <date>"` (or `"open"`, or `"closed"`).

2. **Filter Segment Strip (`SubjectSegmentedControl` at line 158):**
   - Three segments: `"All"`, `"Matched"`, `"Unmatched"`.

3. **Loading / Failure States (lines 100-108):**
   - Loading row (`loadingRow` at line 408): `ProgressView().controlSize(.small)` followed by text `"Loading sign-ups…"`.
   - Failure card (`failureCard` at line 421): title `"Couldn't load sign-ups"`, body error message, button `"Try Again"`.

4. **Section Content (line 170):**
   - SectionRuleHeader: title `"Sign-ups"`, count `filteredSignUps.count`.
   - Top error note (if page failed while rows exist): SF Symbol `"exclamationmark.triangle"`, text `"Couldn't load sign-ups: \(message)"`.
   - Match note (if match state unavailable): SF Symbol `"exclamationmark.triangle"`, text:
     - If error: `"Kudos can't tell which sign-ups are matched. AO3 shows assignments to maintainers after sign-ups close. \(matchError)"`.
     - If no assignments sent yet: `"No assignments have been sent yet, so no sign-up is matched or unmatched."`.
   - Empty filtered card (`emptyFilteredCard` at line 289):
     - Title:
       - Unknown match state: `"Match state unavailable"`.
       - All filter: `"No sign-ups yet"`.
       - Filtered: `"No \(filterSelection.rawValue.lowercased()) sign-ups"`.
     - Body:
       - Unknown match state: `"No sign-up can be shown as matched or unmatched without assignments."`.
       - All filter: `"Sign-ups will appear here as people join the challenge."`.
       - Filtered: `"No sign-ups in this page match the \"\(filterSelection.rawValue)\" filter."`.
   - Sign-up rows (`signUpRow` at line 214):
     - Primary line: `signUp.pseud`.
     - Status chip capsule:
       - When matched: `"MATCHED"` (accent background).
       - When unmatched: `"UNMATCHED"` (subtle background).
       - When unknown: no chip shown.
     - Secondary count line: `"<n> requests · <m> offers"` (or singular).
     - Tertiary tag summary line: `signUp.requestTagSummary` (first line of prompt request tags).
     - Disclosure chevron (`"chevron.right"`).
     - Tapping row pushes `ChallengeSignUpDetailView`.
   - Footnote (`footnoteText` at line 313):
     `"AO3 shows 20 sign-ups per page, so these filters apply only to the pages you have loaded. Each tag summary shows one line from that person's sign-up requests."`
   - Load more button (`loadMoreRow` at line 322; visible if `pages.hasMore`):
     Button with optional small `ProgressView()` and text `"Load page \(pages.loadedPages + 1) of \(pages.totalPages)"`.

5. **Bottom Action Bar (`bottomActionBar` at line 346):**
   - Button 1: NavigationLink `"Your sign-up"` (passes `existingSignUpID` if found in list for logged-in user).
   - Button 2: NavigationLink `"Create sign-up"`.

#### Part B: Individual Sign-up Read (`ChallengeSignUpDetailView` inside `ChallengeSignUpsView.swift:530-622`)
- Header: kicker `collectionTitle`, title `signUp.pseud`, subtitle `"<n> requests · <m> offers"`.
- For each request: SectionRuleHeader `"Request \(index + 1)"`:
  - Panel rows for `"Fandoms"`, `"Relationships"`, `"Characters"`, `"Additional tags"`, `"Optional tags"`.
  - Body text in serif (`prompt.promptText`).
- For each offer: SectionRuleHeader `"Offer \(index + 1)"` with same panel rows.

#### Part C: Participant's Sign-Up Editor & Withdraw Section (`ChallengeSignUpView`)
- Withdraw section (`withdrawPanel` at `ChallengeSignUpView.swift:442-471`):
  - Visible condition: `form?.signUpID != nil` (only rendered for an existing, persisted sign-up).
  - SectionRuleHeader: `"Withdraw"`.
  - Panel contents:
    - Button:
      - Icon: SF Symbol `"xmark.circle"` in red.
      - Label: `"Withdraw sign-up"` in red text.
      - Trailing: small `ProgressView()` while `isWithdrawing == true`.
      - Disabled when `isWithdrawing == true`.
      - Tapping sets `confirmWithdraw = true`.
- Confirmation Dialog (`confirmationDialog("Withdraw this sign-up?")` at lines 133-146):
  - Dialog title: `"Withdraw this sign-up?"`.
  - Message: `"Withdrawing removes your requests and offers from \(effectiveTitle)."`.
  - Button 1: `"Withdraw Sign-up"` (role `.destructive`, action: `Task { await performWithdraw() }`).
  - Button 2: `"Cancel"` (role `.cancel`).

### 4. What it reads and writes
- **Network Reads:**
  1. Sign-ups index:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/signups?page=:page` (`AO3ChallengeURL.signUps`).
     - When / how often: On load and when clicking `"Load page <n> of <m>"`.
     - What stops a repeat: `AO3LoadMorePages` tracks `loadedPages` and ignores duplicates.
  2. Sign-ups total count:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/signups` (reads pagination total on page 1).
  3. Schedule (open/close state):
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/gift_exchange/edit`.
  4. Challenge assignments (for match join):
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/assignments?fulfilled=true` and `?defaulted=true`.
  5. Participant's existing sign-up form:
     - Method: `GET`
     - URL: `https://archiveofourown.org/collections/:slug/signups/:id/edit` (`AO3ChallengeURL.editSignUp`) or `/signups/new` (`AO3ChallengeURL.newSignUp`).

- **Network Writes:**
  1. Withdraw Sign-Up (`auth.withdrawSignUp(slug:signUpID:)` at `AO3ChallengeActions.swift:74-87`):
     - Method: HTTP POST with `_method=delete` override.
     - Action URL: `https://archiveofourown.org/collections/:slug/signups/:id` (`AO3ChallengeURL.signUp(slug: slug, id: signUpID)`).
     - Referer: `https://archiveofourown.org/collections/:slug/signups/:id/confirm_delete` (`AO3ChallengeURL.confirmDeleteSignUp(slug: slug, id: signUpID)`).
     - Headers:
       - `Content-Type: application/x-www-form-urlencoded`
       - `Referer: <referer>`
       - `X-CSRF-Token: <token>`
     - Request parameters Swift builder:
       ```swift
       let request = try writeRequest(
           to: AO3ChallengeURL.signUp(slug: slug, id: signUpID),
           body: Self.formEncoded([("_method", "delete"), ("authenticity_token", token)]),
           csrf: token, referer: referer, ajax: false
       )
       ```
     - Verification & Acceptance logic:
       ```swift
       let (status, body) = try await submitWrite(request)
       try throwIfChallengeWriteFailed(
           status: status, body: body, fallback: "AO3 couldn't withdraw that sign-up."
       )
       ```
       Where `throwIfChallengeWriteFailed` calls `AO3AuthService.collectionWriteVerdict`:
       - Error detection: `doc.select("#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution").first()?.text()`.
       - Success detection: `doc.select(".flash.comment_notice, .flash.notice").first()?.text()` != nil or status in `300...399`.
       - Status 200...299 without notice flash throws `.unconfirmed`.
       - On success, view dismisses with `dismiss()` and posts status `"Sign-up withdrawn."`.

- **Stored Values:**
  - None. All participant rows and form states are held in memory. No SwiftData entities or local files are written. The reader's library is untouched.

### 5. Where it would go on Android
- **Nearest existing screen & file:**
  1. For the Sign-ups list:
     - `account/AO3ChallengeSettingsScreen.kt:181-182` currently links to web:
       `SubjectFormRow("Sign-ups", value = data.signUpTotal?.toString() ?: "Couldn't load", showsDisclosure = true, valueMaxLines = Int.MAX_VALUE, onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeSignUpsView(slug)) })`
     - And in `account/AO3CollectionDetailScreen.kt:619`:
       `show.dashboard.signUpsUrl?.let { add(AO3CollectionManageAction("Sign-ups", it)) }`
     - Android has no native sign-ups list screen. The nearest existing list patterns are `account/AO3CollectionItemsScreen.kt` and `account/AO3CollectionMaintainersScreen.kt`.
  2. For Withdrawing a Sign-Up:
     - Nearest file: `account/AO3ChallengeSignUpScreen.kt:1-276`.
     - In `account/AO3ChallengeSignUpScreen.kt`, the sign-up form and tag editor are fully implemented, but it **completely lacks** the `"Withdraw"` section and action!
     - Android already has the form state (`AO3ChallengeSignUpState.kt`), the form parser (`network/ao3/account/AO3ChallengeSignUpParser.kt`), and `saveChallengeSignUp` in `network/ao3/writes/AO3WriteRepository.kt:103`.
     - Android is missing:
       - The `"Withdraw"` section and button in `AO3ChallengeSignUpScreen.kt` (lines 103-174).
       - The confirmation dialog (`"Withdraw this sign-up?"`).
       - The repository method `withdrawSignUp(slug, signUpID)` in `AO3WriteRepository.kt`.
- **Components already there drawing similar UI:**
  - Red destructive action row: `account/AO3CollectionFormScreen.kt:125-132` (delete collection row)
  - Confirmation alert dialog: `account/AO3CollectionFormScreen.kt:85-98` (`AlertDialog`)
  - Status messages: `SignUpMessage` at `account/AO3ChallengeSignUpScreen.kt:209`

### 6. Size
- **Sign-ups List (`ChallengeSignUpsView`):** **Large** (a complete list screen with pagination, segment filtering, assignment matching join, and detail navigation).
- **Withdrawing a Sign-up (`ChallengeSignUpView`):** **Small** (a single section, destructive action button, confirmation dialog, and DELETE write added to the existing `AO3ChallengeSignUpScreen.kt` and `AO3WriteRepository.kt`).

---

## 4. The Prompt Tags Editor (`PromptTagsEditorView.swift`)

### Counterpart on Android
**This screen already exists on Android.**

- **Location on Android:**
  - File and lines: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSignUpScreen.kt:218-247`
  - Composable name: `SignUpTagsEditor(prompt: SignUpPrompt, position: Int, onDone: (Map<SignUpTagType, List<String>>) -> Unit, onBack: () -> Unit)`
- **Invocation / Entry point on Android:**
  - Screen: `account/AO3ChallengeSignUpScreen.kt:50-57`:
    ```kotlin
    val edit = editing
    val prompt = if (edit == null) null else form?.live(edit.first)?.firstOrNull { it.id == edit.second }
    if (prompt != null && form != null) {
        val position = form.live(prompt.kind).indexOf(prompt)
        SignUpTagsEditor(prompt, position, onDone = { tags -> model.update(prompt.copy(tags = tags)); editing = null },
            onBack = { editing = null })
        return
    }
    ```
  - When the user taps any tag row in `AO3ChallengeSignUpScreen` (`Fandom`, `Relationship`, `Character`, or `Freeform` at lines 117-122), `editing` is set to `prompt.kind to prompt.id`, which presents `SignUpTagsEditor`.
  - It renders header kicker `"${prompt.kind.label} ${position + 1}"`, title `"Tags"`, subtitle `"Comma-separated tag names"`, top bar Done check icon, and four input rows for Fandom, Relationship, Character, and Freeform using `SubjectTextFieldRow`.

*(Per audit instructions: because this screen exists on Android, reporting stops here for this screen.)*

---

## 5. Additional Challenge Write Functions Lacking Android Counterparts

The following mutating functions in `kudos-ao3-reader/Services/AO3ChallengeActions.swift` and `kudos-ao3-reader/Features/Challenges/` write to AO3 and currently have **no counterpart** in Android's `account/AO3Challenge*`, `AO3PromptMeme*`, `AO3TagSet*`, or `network/ao3/writes/AO3WriteRepository.kt`:

### 1. `AO3AuthService.withdrawSignUp(slug:signUpID:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:74-87`
- **Called from:** `kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift:688`
- **What it does:** Withdraws the participant's sign-up while sign-ups are still open.
- **HTTP Request:**
  - Method: `POST` with `_method: delete` parameter.
  - Action URL: `https://archiveofourown.org/collections/:slug/signups/:id` (`AO3ChallengeURL.signUp(slug: slug, id: signUpID)`).
  - Referer: `https://archiveofourown.org/collections/:slug/signups/:id/confirm_delete` (`AO3ChallengeURL.confirmDeleteSignUp(slug: slug, id: signUpID)`).
  - CSRF Page: Fetched from the confirm-delete referer page.
  - Form parameters: `[("_method", "delete"), ("authenticity_token", token)]`.
- **Status & Acceptance Check:**
  `throwIfChallengeWriteFailed(status: status, body: body, fallback: "AO3 couldn't withdraw that sign-up.")` checking flash notice and status 300...399.
- **Android Status:** No method in `AO3WriteRepository.kt`.

### 2. `AO3AuthService.withdrawSignUpAfterClose(slug:assignmentID:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:94-96`
- **What it does:** Forwards to `reportAssignmentDefault(slug: slug, assignmentID: assignmentID)`. Used when sign-ups are closed, since AO3's `signups#destroy` route refuses withdrawal after close and participants must default on their assignment instead.
- **Android Status:** No method in `AO3WriteRepository.kt`.

### 3. `AO3AuthService.reportAssignmentDefault(slug:assignmentID:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:100-113`
- **What it does:** Participant defaults on their own assignment.
- **HTTP Request:**
  - Method: `POST` with `_method: patch` parameter.
  - Action URL: `https://archiveofourown.org/collections/:slug/assignments/:id/default` (`AO3ChallengeURL.assignmentDefault(slug: slug, id: assignmentID)`).
  - Referer: `https://archiveofourown.org/collections/:slug/assignments?fulfilled=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .assignments, page: 1)`).
  - Form parameters: `[("_method", "patch"), ("authenticity_token", token)]`.
- **Status & Acceptance Check:**
  `throwIfChallengeWriteFailed(status: status, body: body, fallback: "AO3 couldn't record the default.")`.
- **Android Status:** No method in `AO3WriteRepository.kt`.

### 4. `AO3AuthService.claimPinchHit(slug:assignmentID:byline:expectedGeneration:using:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:120-133`
- **Called from:** `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:658`
- **What it does:** Assigns a pinch hitter to cover a defaulted assignment from the maintainer's Defaulted list.
- **HTTP Request:**
  - Method: `POST` with `_method: put` parameter.
  - Action URL: `https://archiveofourown.org/collections/:slug/assignments/update_multiple` (`AO3ChallengeURL.assignmentUpdateMultiple(slug: slug)`).
  - Referer: `https://archiveofourown.org/collections/:slug/assignments?defaulted=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .defaults, page: 1)`).
  - Form parameters: `[("_method", "put"), ("authenticity_token", token), ("cover_\(assignmentID)", pinch)]`.
- **Status & Acceptance Check:**
  `throwIfChallengeWriteFailed(status: status, body: body, fallback: "AO3 couldn't claim that pinch hit.")`.
- **Android Status:** No method in `AO3WriteRepository.kt`.

### 5. `AO3AuthService.markAssignmentDefaulted(slug:assignmentID:expectedGeneration:using:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:140-149`
- **Called from:** `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:663`
- **What it does:** Collection owner marks an open assignment defaulted from the maintainer's Open (unfulfilled) list.
- **HTTP Request:**
  - Method: `POST` with `_method: put` parameter.
  - Action URL: `https://archiveofourown.org/collections/:slug/assignments/update_multiple`.
  - Referer: `https://archiveofourown.org/collections/:slug/assignments?unfulfilled=true&page=1` (`AO3ChallengeURL.assignments(slug: slug, list: .unfulfilled, page: 1)`).
  - Form parameters: `[("_method", "put"), ("authenticity_token", token), ("default_\(assignmentID)", "1")]`.
- **Status & Acceptance Check:**
  `throwIfChallengeWriteFailed(status: status, body: body, fallback: "AO3 couldn't record the default.")`.
- **Android Status:** No method in `AO3WriteRepository.kt`.

### 6. `AO3AuthService.updateAssignments(slug:field:fallback:expectedGeneration:using:)` (private helper)
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:156-173`
- **What it does:** Core handler for otwarchive's `challenge_assignments#update_multiple` endpoint (`PUT /collections/:slug/assignments/update_multiple`), posting dynamic `<action>_<id>` fields (`cover_<id>` or `default_<id>`) with session generation checks and CSRF token extraction.
- **Android Status:** No counterpart in `AO3WriteRepository.kt`.

### 7. `AO3AuthService.updateChallengeSettings(_:expectedGeneration:using:)`
- **Location:** `kudos-ao3-reader/Services/AO3ChallengeActions.swift:261-317`
- **Called from:** `kudos-ao3-reader/Features/Challenges/ChallengeSettingsEditView.swift:780`
- **What it does:** Validates and submits the complete challenge settings form for a Gift Exchange or Prompt Meme, persisting dates, limits, prompt restrictions, potential match attributes, and instructions.
- **HTTP Request:**
  - Method: HTTP POST (with optional `_method` override).
  - Action URL: `posted.actionURL` (`/collections/:slug/gift_exchange` or `/collections/:slug/prompt_meme`).
  - Referer: `AO3ChallengeURL.giftExchangeEdit` or `AO3ChallengeURL.promptMemeEdit`.
  - Form parameters: Serialized via `AO3Client.challengeSettingsParameters(posted)` (including all 15 potential match fields, request/offer prompt restrictions, and preserved hidden fields).
- **Status & Acceptance Check:**
  - Error check: `AO3Client.writeErrorMessage(in: body)` -> returns `.invalid(invalid)`.
  - Success check: `AO3Client.writeSuccessMessage(in: body) ?? (body.localizedCaseInsensitiveContains("successfully") ? "Challenge was successfully updated." : nil)` or status in `300...399` -> returns `.saved(...)`.
  - Unconfirmed check: Final 200 without parsed notice or errors throws `AO3ChallengeWriteError.unconfirmed`.
- **Android Status:** No counterpart in `AO3WriteRepository.kt` (Android only supports read-only challenge settings in `AO3ChallengeSettings.kt` and `AO3ChallengeSettingsScreen.kt`).

---

### Functions in `AO3ChallengeActions.swift` that DO Have Android Counterparts (for reference)
- `saveChallengeSignUp`: Counterpart at `AO3WriteRepository.kt:103` (`suspend fun saveChallengeSignUp(...)`).
- `claimPrompt`: Counterpart at `AO3WriteRepository.kt:150` (`suspend fun claimPrompt(...)`).
- `releasePrompt`: Counterpart at `AO3WriteRepository.kt:155` (`suspend fun releasePrompt(...)`).
- `saveTagSetFields`: Counterpart at `AO3WriteRepository.kt:182` (`suspend fun saveTagSetFields(...)`).
- `reportRejectedTag`: Counterpart at `AO3WriteRepository.kt:206` (`suspend fun reportRejectedTag(...)`).
