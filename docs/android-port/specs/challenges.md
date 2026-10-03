# Android Port Spec: Challenges

This spec details the implementation requirements for the Challenges feature on Android, mapping the exact behavior, layout, and data flow from the iOS implementation. As per the project guidelines, **iOS code is the absolute source of truth**. Any discrepancies between the original design specification (artboards 1by, 1bz, 1ca, 1cb, 1cc, 1cd, 1ce, 1cf, 1ch) and this document should be resolved in favor of this document, which reflects the shipped iOS state.

---

## 1. Screen tree

The iOS implementation structures the Challenges features across several specialized views, each mapping to a specific administrative or participant function.

### Collection Moderation (`CollectionModerationView.swift` - Artboard 1cd)
*   **Top**: `SubjectHeaderBlock` with the collection title and a "moderator" or "owner" kicker based on permissions.
*   **Awaiting review**: `SectionRuleHeader` followed by a list of `AO3CollectionItem`s. When empty, displays a card: "No works waiting for review" / "All submissions to this collection have been reviewed." (`CollectionModerationView.swift:439`).
*   **Recently decided**: A single `SubjectFormRow` pushing to an approved/rejected list.
*   **Membership requests**: `SectionRuleHeader` followed by `AO3CollectionParticipant` rows. Empty state: "No membership requests" / "Nobody is waiting to join".
*   **Maintainers**: Two `SubjectFormRow`s: "Owners and moderators" (pushes to 1bx) and "Invite a maintainer" (pushes to 1bx).
*   **Reveal and anonymity**: Two `SubjectFormRow`s indicating current status. Conditional "Reveal now" and "Remove anonymity" buttons appear only when the respective flags are true (`CollectionModerationView.swift:611`).

### Collection Maintainers (`CollectionMaintainersView.swift` - Artboard 1bx)
*   **Top**: `SubjectHeaderBlock`.
*   **Owners**: `SectionRuleHeader` followed by owner rows.
*   **Moderators**: `SectionRuleHeader` followed by moderator rows.
*   **Invitations**: `SubjectFormRow` containing an invite text field and role picker.
*   **Leave**: `SubjectFormRow` for stepping down, validating against the "last-owner rule" (`CollectionMaintainersView.swift:6`).

### Challenge Settings Read-Only (`ChallengeSettingsView.swift` - Artboard 1by)
*   **Top**: `SubjectHeaderBlock`.
*   **Type**: Gift Exchange vs Prompt Meme.
*   **Dates**: `SubjectFormRow`s for schedule dates.
*   **Sign-up requirements**: `SubjectFormRow`s detailing the request/offer limits.
*   **Tag sets**: `SubjectFormRow`s linking to `TagSetView` (1ch).
*   **Prompts & Assignments**: Counts and AO3 links.
*   **At AO3**: Actions falling back to the web.

### Challenge Settings Edit (`ChallengeSettingsEditView.swift` - Artboard 1cf)
*   Matches 1by but replaces values with interactive `SubjectFormRow` controls.
*   **Matching**: Opens AO3's matching generator.
*   **Delete**: Open-on-AO3 link, because "deleting a series is irreversible and belongs on AO3's own confirm page" (`ChallengeSettingsEditView.swift:23`).

### Challenge Sign-ups List (`ChallengeSignUpsView.swift` - Artboard 1bz)
*   **Top**: `SubjectHeaderBlock`.
*   **Segmented Control**: `SubjectSegmentedControl` filtering All / Matched / Unmatched.
*   **Sign-ups**: `List` of sign-up cards. Each card shows the user's pseud, request count, and tag summary. If match state is unknown, no chip is shown (`ChallengeSignUpsView.swift:253`).

### Challenge Assignments (`ChallengeAssignmentsView.swift` - Artboard 1cb)
*   **Top**: `SubjectHeaderBlock` with "works due" date in the subtitle.
*   **Segmented Control**: Matched / Unmatched / Pinch hits.
*   **Content**: `assignmentRow`s for matched, grouped pairs for unmatched ("Two sign-ups lost their giver" `ChallengeAssignmentsView.swift:375`), and `pinchHitRow`s.
*   **Bottom Bar**: Floating action bar for "Report a default" and "Claim a pinch hit" (owners only).

### Prompt Meme Prompts (`PromptMemeView.swift` - Artboard 1cc)
*   **Top**: `SubjectHeaderBlock`.
*   **Segmented Control**: All / Claimed / Unclaimed.
*   **Prompts**: List of prompts displaying title, text, tag summary, and poster.

### Tag Set (`TagSetView.swift` - Artboard 1ch)
*   **Ownership**: Read-only `SubjectFormRow`s.
*   **Tags**: Editor for tag lists.
*   **Nominations & Review**: Grouped by `parentTagName`.

### Challenge Sign-up Form (`ChallengeSignUpView.swift` - Artboard 1ca)
*   **Top**: `SubjectHeaderBlock`.
*   **Request 1..N**: Forms for requests.
*   **Offers**: Forms for offers.
*   **Withdraw**: `SubjectFormRow` to withdraw the sign-up.

---

## 2. Components

Android's design system lives in `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/`. Many iOS components have exact equivalents, while others are missing and must be built.

*   **`SubjectHeaderBlock`**: Used at the top of every screen. iOS `SubjectMetrics.accountGutter` is 16pt. The Android equivalent `SubjectHeaderBlock` exists.
*   **`SectionRuleHeader`**: Used to divide forms and lists. Android `SectionRuleHeader` exists.
*   **`SubjectFormRow`**: The primary layout unit for settings and lists. It supports `.value` (right-aligned text), `.control` (embedded pickers/toggles), and `showsDisclosure` (chevron). **Android gap:** `SubjectFormRow` was not ported in brief 1a and must be built.
*   **`SubjectRowSeparator`**: A 0.5pt divider line. Android `SubjectRowSeparator` exists.
*   **`SubjectSegmentedControl`**: Top tabs for filtering (e.g., All/Matched/Unmatched). **Android gap:** Missing in Compose components.
*   **`SubjectFieldLabel`**: Labels for form groups (`SubjectFieldLabel(text: "Prompt", style: .formGroup)`). **Android gap:** Missing in Android.
*   **Cards and Panels**: iOS uses `.subjectPanel()` with a 14pt radius (`SubjectMetrics.panelRadius`). Android provides `Modifier.subjectPanel`.
*   **Status Badges (`ChallengeAssignmentsView.swift:314`)**: Used for assignment states ("Delivered", "Late", "Defaulted").
    *   **Font**: `.system(size: 9, weight: .bold)`, uppercased.
    *   **Tracking**: `0.6`.
    *   **Padding**: `.horizontal, 8`, `.vertical, 4`.
    *   **Background**: `Capsule().fill(color.opacity(0.16))`.
    *   **Border**: `Capsule().strokeBorder(color.opacity(0.34), lineWidth: 0.5)`.
    *   **Android gap:** This specific pill style must be implemented.
*   **Action Buttons**: `moderationPillButton` and `promptActionButton`.
    *   **Font**: `pillLabelSize` (`@ScaledMetric(relativeTo: .caption) private var pillLabelSize: CGFloat = 12`).
    *   **Height**: Minimum 44pt for touch targets in bottom bars.

---

## 3. Data

Data sources map to existing networking infrastructure. Write operations must obey `docs/AO3_NETWORKING_POLICY.md`.

*   **Collection Moderation**: Driven by `AO3Client.shared.collectionModeration`.
*   **Maintainers**: `AO3Client.shared.collectionParticipants`.
*   **Challenge Settings**: `AO3Client.shared.challengeSettings(slug: request:)` fetches the `AO3ChallengeSettingsForm` containing `AO3ChallengeSettings`.
*   **Tag Set**: Fetched by ID using `AO3Client.shared.collectionTagSets`. The ID is parsed from the collection profile page, not the show page (`TagSetView.swift:371`).
*   **Sign-ups**: `AO3ChallengeSignUpList`.
*   **Assignments**: `AO3ChallengeAssignmentList` fetches `.sent`, `.defaults`, and `.pinchHits`. "Works-due is challenge-wide, not per-assignment, so it is read once off the settings form... rather than invented per row" (`ChallengeAssignmentsView.swift:39`).
*   **Prompts**: `AO3ChallengePromptsList`.
*   **Android Layer**: Data fetching should map to corresponding Repositories or ViewModels in `android/app/src/main/java/io/github/cidy02/kudos/library/` and `network/ao3/`.

---

## 4. Interactions

*   **Collection Moderation (`CollectionModerationView.swift`)**:
    *   Approve, reject, accept, decline, invite, reveal, and un-anonymize are native AO3 writes (`AO3CollectionActions.swift`).
    *   **Message creator**: Opens the work's comment composer "for a fix rather than a refusal", rather than opening the work in a browser (`CollectionModerationView.swift:45`).
*   **Collection Maintainers (`CollectionMaintainersView.swift`)**:
    *   Invite by username sends an invitation.
    *   Step-down/leave validates locally: "the last owner cannot remove themselves" (`CollectionMaintainersView.swift:6`).
*   **Tag Set (`TagSetView.swift`)**:
    *   Reject nominations via `reportRejectedTag`.
    *   Approving is not a native client write. "AO3 only approves a nomination by associating it with a fandom, which is the 'Associate nominations' escape hatch" (`TagSetView.swift:20`).
*   **Challenge Assignments (`ChallengeAssignmentsView.swift`)**:
    *   "Report a default" and "Claim a pinch hit" are native writes presented via floating bottom bar pickers.
    *   Matching actions fallback to Safari: "matching is AO3's own algorithm... so both actions on an unmatched card open AO3's own assignments page" (`ChallengeAssignmentsView.swift:9`).
*   **Prompt Meme (`PromptMemeView.swift`)**:
    *   Claim and release are native writes (`AO3ChallengeActions.claimPrompt`).
    *   "Fill it" opens AO3 in Safari because it requires posting a whole new work (`PromptMemeView.swift:14`).
    *   "New prompt" opens the sign-up form.
*   **Global Gestures**:
    *   **Pull-to-refresh**: Implemented on all scrollable list views, resetting the `sessionGeneration`.
    *   No long-press or swipe actions are used on these screens to prevent accidental destructive writes.

---

## 5. Strings

Verbatim strings used across the UI, including alerts and empty states:

*   "Owners and moderators", "Invite a maintainer"
*   "Recently decided: Approved and rejected"
*   "Awaiting review", "Membership requests", "Reveal and anonymity"
*   "No works waiting for review", "All submissions to this collection have been reviewed."
*   "No membership requests", "Nobody is waiting to join"
*   "Reject", "Decline", "Reveal", "Remove Anonymity"
*   "This rejects “...” from the collection. The work stays on AO3, and its creators will be notified."
*   "This removes ...'s membership request. They will need to apply again."
*   "Unrevealed works and their creators become visible to everyone. This cannot be undone."
*   "Creators become visible to everyone instead of only maintainers. This cannot be undone."
*   "You can view assignments and pinch hits here one page at a time. You can report a default or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3."
*   "A Prompt Meme has no matching or assignments. You can claim a prompt here and release it or use Open on AO3 to fill it."
*   "Two sign-ups lost their giver", "One sign-up lost its giver"
*   "The giver for ... defaulted, and no pinch hitter has covered it yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."
*   "AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for..."
*   "Before you approve a nominated character or relationship, it must be linked to a fandom."
*   "Enter each tag type as its own comma-separated list, as on AO3. If AO3 rejects a tag..."
*   "AO3 does the matching. Save these settings here, then use Open on AO3 to run or rerun..."
*   "Match state unavailable"

---

## 6. Owner decisions

Specific rationale documented in the iOS codebase that must be preserved:

*   **Moderated Items Condensation**: "The old Moderated Items screen's 3 switches were condensed to 'Recently decided: Approved and rejected' linking to those." (`CollectionModerationView.swift:222`).
*   **Tag Set Network Load**: "`TagSetView` is addressed by a numeric id that AO3 publishes on the collection profile page... The fetch lives here rather than on `AO3CollectionDetailView` deliberately... `docs/AO3_NETWORKING_POLICY.md` treats request politeness as a product requirement, so the cost sits on the two screens that use it." (`ChallengeSettingsView.swift:371`).
*   **Unmatched Grouping**: "AO3's defaults queue lists one stuck request per row, not a pairing. The spec draws two names per card, so consecutive rows are grouped two at a time for layout only; an odd one out gets the singular copy." (`ChallengeAssignmentsView.swift:374`).
*   **Tag Set Review Grouping**: "The review queue groups by `parentTagName` per the model's own note that a nominated character or relationship needs its fandom association finished before AO3 will approve it — grouping is how the queue keeps that dependency visible." (`TagSetView.swift:32`).
*   **Assignment Due Dates**: "Works-due is challenge-wide, not per-assignment, so it is read once off the settings form... rather than invented per row." (`ChallengeAssignmentsView.swift:39`).
*   **Fill It Behavior**: "'Fill it' means posting a whole new work, which this screen doesn't attempt, so it opens the meme on AO3 instead." (`PromptMemeView.swift:14`).

---

## 7. Android gaps

The following components and behaviors are missing from Android's `ui/subject/` package and must be built to support Challenges:

1.  **`SubjectFormRow`**: Essential for settings panels. Needs to support text values (`.value`), embedded controls (`.control`), and disclosure indicators (`showsDisclosure`).
2.  **`SubjectSegmentedControl`**: Required for top-level navigation on Assignments, Sign-ups, and Prompt Meme views.
3.  **`SubjectFieldLabel`**: Text styling for field group headers.
4.  **Custom Status Badges**: The specific `.system(size: 9, weight: .bold)` pill design with 0.6 tracking, 0.16 fill opacity, and 0.34 stroke opacity is absent.
5.  **Bottom Action Bar**: The floating, gradient-backed dual-button bar used in Assignments needs a Compose implementation matching iOS (`ChallengeAssignmentsView.swift:682`).
