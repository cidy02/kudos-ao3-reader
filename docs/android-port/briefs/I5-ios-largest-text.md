# Brief I5 (owner-approved U2): the iPhone's layouts at the largest text sizes

**Edit code in this worktree (`/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i5`); do
not commit, push, switch branches, sign in, run xcodebuild or contact archiveofourown.org.** This
worktree cannot build (no Packages/Vendor); Claude ports the change, builds, tests and looks at it
on the simulator at the largest size. Create `docs/android-port/briefs/I5-result.md` FIRST; write
each item into it as you finish it: what changed (`path:line`), why, and the test added if the rule
can be pinned without a screen.

The owner approved this on 2026-10-21. **At the ordinary text sizes nothing may change.** Use what
the code already has: `dynamicTypeSize.isAccessibilitySize`, `FlowLayout` (`UIComponents/FlowLayout.swift`;
T-422 used it for the AO3 collection card's badges), `ViewThatFits`, `AnyLayout`. Nothing a reader
can see or do may be lost. Match the surrounding style (hand-wrapped; SwiftLint line length 120).

At the largest accessibility size (AX5) these cover or cut off content:
1. **Welcome and sync setup** (`kudos-ao3-reader/Features/Onboarding/WelcomeView.swift`,
   `SyncFolderOnboardingView.swift`, shared `OnboardingComponents.swift`): the scaled header and the
   pinned buttons fill the screen, so every feature row is hidden and "Don't remind me again" and
   "Choose Sync Folder" are cut to "Don't remin…" and "Choose S…". At accessibility sizes the
   buttons scroll with the content after the rows instead of staying pinned; labels wrap.
2. **Comments** (`Features/Comments/CommentsView.swift:192`, `.safeAreaInset(edge: .bottom) {
   writeCommentBar }`): the floating "Write a comment" covers the "All comments" filter row at AX5.
   At accessibility sizes it must not cover controls or text (for example a full-width bar with its
   own ground, or in the content after the filters); keep it reachable. (Hiding it while scrolling
   was not approved.)
3. **Another reader's page** (`Features/Authors/AuthorProfileComponents.swift`, the action row
   with Subscribe near `:59`): at AX5 Subscribe becomes a tall empty pillar with no label. Its label
   stays readable (the row stacks or wraps at accessibility sizes).
4. **Chip labels cut with "…"**: Subscriptions' filter chips "Authors" and "Reset"
   (`Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift` or the shared filter row it uses), your
   Works' scope and fandom chips ("Gifts", "The Locked Tomb (3)": `Features/Authors/WorksScopeAndSort.swift`,
   `AuthorProfileContentSections.swift:172`–`:200`), AO3 collections' "Your items"
   (`Features/Account/AO3CollectionsList.swift`). No chip label truncates at accessibility sizes:
   wrap the row (`FlowLayout`) there.
5. **A bookmark card's fandom kicker** ("THE LOCKED T…" at AX5; `Features/Search/AO3WorkRow.swift`,
   the ledger heading): wraps at accessibility sizes, as the kicker does elsewhere.
