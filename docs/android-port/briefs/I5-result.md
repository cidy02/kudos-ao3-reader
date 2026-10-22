# I5 result — layouts at the largest text sizes

Owner-approved 2026-10-21. Ordinary text sizes are unchanged: every branch is
`dynamicTypeSize.isAccessibilitySize` (or `AccessibilityChipRail`, which is that
check). Nothing was committed. `xcodebuild` was not run (this worktree cannot
build). No unit test was added. Each rule is which container SwiftUI uses, and
that cannot be pinned without a screen.

## 1. Welcome and sync setup

`kudos-ao3-reader/Features/Onboarding/OnboardingComponents.swift:15`–`:33`
(`scrollingIntro` at `:36`, footer chrome at `:47`).

At accessibility sizes the feature rows and the actions are one scroll, actions
after the rows. Every other size keeps the pinned footer under the scroll view,
with the same padding and `cardSurface` bar.

Labels wrap only at accessibility sizes, and those buttons use a rounded rect so
a second line is not clipped by a capsule:

- `WelcomeView.swift:89`–`:118` — "View on GitHub", "Continue"
- `SyncFolderOnboardingView.swift:116`–`:153` — "Don't remind me again",
  "Choose Sync Folder", "Not Now"
- `OnboardingComponents.swift:86` — `onboardingWrapsButton`

No test. The rule is which container the scaffold uses.

## 2. Comments — "Write a comment"

`kudos-ao3-reader/Features/Comments/CommentsView.swift:24`–`:40`
(`CommentWriteBarPlacement`), applied at `:213`. The bar itself is
`accessibleWriteCommentBar` at `:876`.

At accessibility sizes the control is a full-width bar on `cardSurface`, under
the list (not a safe-area overlay), and the label wraps. It stays on screen.
Every other size keeps the floating capsule in `.safeAreaInset(edge: .bottom)`.

No test. The rule is overlay versus a bar under the list.

## 3. Another reader's Subscribe

`kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:76`–`:111`
(the row), `:133`–`:146` (the button), `:158` (the title).

At accessibility sizes the action row is a `VStack`. Subscribe is a rounded rect
the width of the column, and "Subscribe" / "Unsubscribe" wrap. Mute and Block
stay, without `.controlSize(.small)`, which was the empty pillar. Every other
size keeps the `HStack`, `.controlSize(.small)`, and the one-line label.

No test. The rule is the stack and the button shape.

## 4. Chip labels

`AccessibilityChipRail` in `kudos-ao3-reader/UIComponents/FlowLayout.swift:105`.
At accessibility sizes the chips are a `FlowLayout`. Every other size is the
same horizontal `ScrollView` + `HStack` (indicators off).

Call sites:

- Subscriptions "Authors": `Features/Bookmarks/AO3NamedSubscriptionsList.swift:11`
- Subscriptions "Reset": `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:445`
- Works scopes ("Gifts"): `Features/Authors/WorksScopeAndSort.swift:25`, and the
  row beside the funnel stacks at `:111` so the pills get the width
- Fandom chips ("The Locked Tomb (3)"): `Features/Authors/AuthorProfileContentSections.swift:167`
- Collections "Your items": `Features/Account/AO3CollectionsList.swift:316`

`SubjectChip` already allows three lines at accessibility sizes, so a chip wider
than the phone wraps inside the flow instead of ending in "…".

No test. The rule is scroll row versus `FlowLayout`.

## 5. Bookmark card fandom kicker

`kudos-ao3-reader/Features/Search/AO3WorkRow.swift:289`–`:352`, in
`searchLedgerIdentity` (the bookmark card and the search ledger share this
heading).

At accessibility sizes the kicker is `SubjectKicker` with `lineLimit: 3` on its
own line (`:300`), the same limit a page kicker uses, and Series / Private / Rec
/ expand wrap underneath in a `FlowLayout`. Every other size keeps the one-line
kicker in the `HStack` with those badges.

No test. The line limit is only read by SwiftUI.
