# Comments Screen Specification

This document defines the Android implementation specification for the Comments screen, sourced from the iOS implementation as the source of truth.

## 1. Screen tree

The Comments screen is presented either as a pushed view from Work Detail or modally from the reader's action menu. It is backed by `CommentsView.swift` (`kudos-ao3-reader/Features/Comments/CommentsView.swift:25`).

The root element is a `ScrollViewReader` containing a `List` that renders the comments and metadata sections (`CommentsView.swift:133-162`).

- **Header and Scope Section** (`CommentsView.swift:135-149`):
  - **`SubjectHeaderBlock`** (`CommentsView.swift:136`, defined at line 434): Displays the scope kicker (e.g. "Chapter X" or "Comments"), the full work title, and a trailing `AO3AuthorBylineView`.
  - **`SubjectStatStrip`** (`CommentsView.swift:138`): Drawn only when `model.page` is populated. It contains four metrics: "Comments", "Threads", "Yours", and "Latest".
  - **`signalScopeNote`** (`CommentsView.swift:141`): A secondary `Text` block that informs the user the stats count only the current page (shown when `page.totalPages > 1`).
  - **`filterRail`** (`CommentsView.swift:148`): A horizontal rail (`HStack`) containing two `SubjectChip` pills for switching the chapter scope and modifying the local sort order.
- **Content Sections** (`CommentsView.swift:150`, defined at line 642):
  - **Idle / Loading** (`CommentsView.swift:646`): Renders four `CommentSkeletonRow` placeholders without list separators.
  - **Failed** (`CommentsView.swift:660`): Displays a native `ContentUnavailableView` with the error message and a prominent "Try Again" button.
  - **Empty (Loaded)** (`CommentsView.swift:682`): Displays a `ContentUnavailableView` reading "No Comments Yet" and "You can be the first to comment on this work."
  - **Loaded (Populated)** (`CommentsView.swift:692`):
    - A **`SectionRuleHeader`** (`CommentsView.swift:697`) titled "Comments" with the loaded comment count.
    - A flat, lazy `ForEach` over `CommentConversationItem` representing the entire threaded conversation (`CommentsView.swift:705`). To prevent swiping a parent comment from applying to its children, the tree is explicitly flattened so each top-level comment and its deep replies are their own individual rows (`CommentThreadRow.swift:26`).
- **Footer Spacer** (`CommentsView.swift:155`): A transparent 64pt `Color.clear` block appended at the bottom to ensure the last long comment scrolls fully clear of the floating "Write Comment" CTA footprint.

**Select mode and bulk bar:** None. There is no select mode or bulk bar for comments.

## 2. Components

All subject-styled components map to their respective implementations in `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/`.

- **`SubjectHeaderBlock`** (`CommentsView.swift:434`):
  - **Sizes/Styles**: Work title at 32pt. Contains the trailing `AO3AuthorBylineView` rendered with font `.system(size: 15.5)` (`CommentsView.swift:446`) and `expandsHitTarget: false` to allow modal tap-through routing.
  - **Android Mapping**: `io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock`

- **`SubjectStatStrip`** (`CommentsView.swift:138`):
  - **Sizes/Styles**: Standard cell padding defined inside a `subjectPanel()` wash.
  - **Android Mapping**: `io.github.cidy02.kudos.ui.subject.SubjectStatStrip` populated with `SubjectStatCell`.

- **`SubjectChip`** (`CommentsView.swift:573`):
  - **Sizes/Styles**: Uses `.pill(isSelected:)` style. The menu container manually applies `.minimumHitTarget()` to expand the interactive footprint to 44pt (`CommentsView.swift:582` and `626`), correcting for the 30pt visual height of the pill.
  - **Android Mapping**: `io.github.cidy02.kudos.ui.subject.SubjectChip` using `SubjectChipStyle.Pill`.

- **`SectionRuleHeader`** (`CommentsView.swift:697`):
  - **Android Mapping**: `io.github.cidy02.kudos.ui.subject.SectionRuleHeader`.

- **`CommentThreadRow` / `CommentPostRow`** (`CommentThreadRow.swift:1050`):
  - **Sizes/Styles**: Strict geometric rules governed by `CommentThreadGeometry` (`CommentThreadRow.swift:38`):
    - `sideMargin`: 16pt.
    - `conversationGap`: 18pt between distinct top-level threads.
    - `rowTopPadding`: 12pt above every individual reply or control row.
    - `railWidth`: 1pt connecting spine width.
    - `maxInlineDepth`: 5 levels.
    - `avatarSize`: 30pt (depth 0), 26pt (depth 1), 22pt (depth > 1).
    - `avatarContentSpacing`: 11pt (depth 0), 10pt (depth > 0).
    - `elbowRadius`: 21pt (depth <= 1), 18pt (depth > 1).
    - `collapsedBodyLineLimit`: 5 lines maximum for unexpanded comment text.
  - **Android Mapping**: missing: build it.

- **`CommentActionRowLayout`** (`CommentThreadRow.swift:86`):
  - **Sizes/Styles**: The action strip height is 40pt when the "Reply" button is drawn (user is logged in). When signed out, it shrinks to 28pt `overflowOnlyHeight`. A 44pt tap target is maintained, overlapping vertically into the prose space instead of leaving an empty void under short comments.
  - **Android Mapping**: missing: build it.

- **`ExpandableCommentBody`** (`CommentThreadRow.swift:1498`):
  - **Sizes/Styles**: Implements a `lineLimit` clamp to 5 lines. It conditionally shows a "Read more" button based on measuring unclamped vs clamped height via background geometry probes.
  - **Android Mapping**: missing: build it.

- **`CommentParticipantBadge`** (`CommentThreadRow.swift:233`):
  - **Sizes/Styles**: Role chips for "Author" and "Me". "User" roles receive no chip to preserve vertical density and avoid noise.
  - **Android Mapping**: missing: build it.

- **`AO3AuthorBylineView`**, **`CommentSkeletonRow`**, **`ContentUnavailableView`**:
  - **Android Mapping**: missing: build it.

## 3. Data

- **Sources**: The iOS implementation relies on `CommentsModel.swift` to fetch data via `AO3AuthService`. 
  - Comments are fetched iteratively via `model.loadPage` (`CommentsModel.swift:646`). 
  - The chapter navigation index (a small `/navigate` page) is requested exactly once per session if the user selects the "By Chapter" scope via `model.loadChaptersIfNeeded` (`CommentsModel.swift:868`).
  - Inbox navigation triggers a specific sequence where the single comment tree is fetched to satisfy the deep link (`model.loadFocusedThread`, `CommentsModel.swift:385`).
- **Tree Flattening**: AO3 threads can be deeply nested. To optimize layout, `CommentThreadRow.swift:1312` flattens the recursive `AO3Comment` tree into a depth-first `[FlattenedReply]` list. This avoids exponential rendering costs and allows for row-level swipe actions without affecting child elements.
- **Sort Order**: AO3 does not expose a server-side comment sorting parameter. All sorting ("Newest First" / "Oldest First") is performed locally via `model.newestFirst` on the fetched array (`CommentsView.swift:592`).
- **Limits**:
  - `autoExpandedMaxReplies`: Threads containing more than 8 replies are collapsed by default (`CommentThreadRow.swift:86`).
  - `repliesChunkSize`: When expanding, comments load in chunks of 20 (`CommentThreadRow.swift:90`).
  - `maxInlineDepth`: Replies are rendered inline up to a depth of 5. Any deeper nesting displays a "Continue thread" link instead of indenting further (`CommentThreadRow.swift:56`).
- **Filters**: The model restricts its fetching to a specific chapter (`model.selectedChapter`) when `model.scope == .byChapter` (`CommentsView.swift:225`).
- **Closest Android Sources**: The data architecture maps directly to `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt`, fetching from `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt` and `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/chapters/AO3ChapterIndexRepository.kt`.

## 4. Interactions

- **Taps**:
  - **Avatar & Byline**: Tapping the author's avatar or their byline triggers `handlers.onOpenAuthor` (`CommentThreadRow.swift:1298`), routing to the native author profile sheet.
  - **Expandable Text**: Tapping the "Read more" / "Show less" text toggles the `lineLimit` clamp with a 0.2s `easeInOut` animation (`CommentThreadRow.swift:1530`).
  - **Chapter Filter**: Tapping the "By chapter" pill opens the chapter picker modal (`CommentsView.swift:571`).
- **Long-press Menus (Overflow)** (`CommentThreadRow.swift:1437`):
  - "Reply" -> Action: Triggers `handlers.onReply(comment)` to launch the comment composer.
  - "Log in to Reply" -> Action: Triggers `handlers.onRequestLogin()` if the user is unauthenticated.
  - "Edit Comment" -> Action: Triggers `handlers.onEdit(comment)`.
  - "Copy Link" -> Action: Triggers `handlers.onCopyLink(comment)`.
  - "Thread" -> Action: Triggers `handlers.onFocusThread(comment.id)`, pushing the screen focusing entirely on this comment.
  - "Parent Thread" -> Action: Triggers `handlers.onFocusThread(parentID)`.
  - "Delete Comment" (Role: `.destructive`) -> Action: Triggers `handlers.onDelete(comment)` and requests deletion confirmation.
- **Swipe Actions** (`CommentThreadRow.swift:1846`):
  - **Leading edge (Allows full swipe)**: "Reply" (or "Log in to Reply" if signed out).
  - **Trailing edge (No full swipe)**: "Copy Link", "Edit Comment", and "Delete Comment". The `.destructive` delete action is placed at the outer edge to prevent accidental swipes.
- **See All / Expanders** (`CommentThreadRow.swift`):
  - "Show %d replies" or "Show %d more" inserts a chunk of 20 replies into the flat view list.
  - "Continue thread" opens the truncated deep thread on the AO3 website directly via the system browser (`CommentThreadRow.swift:1170`).
- **Select mode and bulk bar**: None.
- **Toolbar Buttons (Top Right)** (`CommentsView.swift:308`):
  - A "Close" (`xmark`) `.cancellationAction` is provided when the view is presented modally (`isModal`).
  - An "Expand to full screen" (`arrow.up.left.and.arrow.down.right`) `.primaryAction` is provided if the `onRequestExpand` binding is present.
- **Pull-to-refresh**: Configured on the primary List via `.refreshable` (`CommentsView.swift:190`), which executes `model.load(auth: auth, forceRefresh: true)`.

## 5. Strings

Every user-visible string provided by the Comments module, verbatim:

- "Comments"
- "Chapter %@"
- "Threads"
- "Yours"
- "Latest"
- "Threads, Yours and Latest count only this page. The comment total covers the whole work."
- "By chapter"
- "All comments"
- "Oldest First"
- "Newest First"
- "Newest"
- "Oldest"
- "Couldn't Load Comments"
- "Try Again"
- "No Comments Yet"
- "You can be the first to comment on this work."
- "(Previous comment deleted.)"
- "Reply"
- "Log in to Reply"
- "Edit Comment"
- "Copy Link"
- "Thread"
- "Parent Thread"
- "Delete Comment"
- "Delete this comment?"
- "Delete"
- "Cancel"
- "This removes the comment on AO3. It cannot be undone."
- "AO3"
- "OK"
- "Show %d replies"
- "Show %d reply"
- "Show %d more"
- "Hide"
- "Hide replies"
- "1 deeper reply"
- "%d deeper replies"
- "Continue thread"
- "·"
- "Your comment"
- "Work author"
- "Close" (accessibility label)
- "Expand to full screen" (accessibility label)
- "Browse comments by chapter" (accessibility label)
- "Sort comments" (accessibility label)
- "Opens the rest of this thread on the AO3 website" (accessibility hint)

## 6. Owner decisions

- **`CommentsModel.swift` (T-86)**: The data layer is structured so views can nest cards strictly under the immediate parent to maintain threading contexts.
- **`CommentMarkup.swift` (T-273)**: Comment text elements are forced to grow into the room provided by their columns to prevent clipping.
- **`CommentThreadRow.swift` (T-151/T-183)**: The inline list was historically bounded in depth. It now allows rendering all comment connections up to AO3's hard 5-depth limit before rendering a strict "Continue thread" row.
- **`CommentThreadRow.swift` (T-247)**: When signed out, the 44pt bounding box for the action row overlaps the prose instead of stacking under it to prevent a tall, glaring empty gap under short comments.
- **`CommentThreadRow.swift` (T-292 regression, owner 2026-09-29)**: The swiped comment ID is shared dynamically via `CommentSwipeTracker` so its descendants can instantly drop the vertical rail line joining them to it. This fixes a visual bug where the swiped comment faded but its connecting rails improperly remained on screen.
- **`CommentThreadRow.swift` (owner, 2026-09-29)**: The vertical rail drawing animations are manually delayed (0.4s / 0.55s) to allow the rest of the list to settle first, set by eye on physical devices.
- **`CommentThreadRow.swift` (owner, 2026-09-29)**: The control button text alignment is manually verified to align seamlessly with the text in surrounding data rows.
- **`CommentThreadRow.swift` (owner, 2026-09-28)**: The author's name is strictly aligned with the top of the avatar in every row. The byline view is bounded precisely to the avatar's height so that external badges (like chapter tags) cannot push the text vertically off-axis (`CommentThreadRow.swift:1143`).
- **`CommentsView.swift` (T-139)**: Modal view routing relies on `AO3AuthorNavigationModifier` to correctly overlay the profile sheet above the comments modal.

## 7. Android gaps

- **Flattened Thread Topology**: The complete algorithmic layout for DFS flattened threads, including stepped avatar constraints (`CommentThreadGeometry`), recursive indentation logic, vertical rail connectors (`railWidth`, `conversationGap`), and visual elbows is missing.
- **Action Bar Overlap (`CommentActionRowLayout`)**: The specific 40pt / 28pt layout shifting behavior that maintains a 44pt hit target by overlapping into the prose requires custom Compose `Modifier.offset` or `Layout` equivalents.
- **Rail Sync during Swipes (`CommentSwipeTracker`)**: Compose `SwipeToDismissBox` native components need to be paired with a shared ViewModel/State mechanism to signal the removal of connection rails dynamically during a swipe.
- **Intrinsic Truncation Measurement (`ExpandableCommentBody`)**: Compose requires building an equivalent to iOS `ZStack` background geometry probes (likely using `SubcomposeLayout` or `TextLayoutResult`) to silently measure unclamped text height and trigger the "Read more" toggle at exactly 5 lines.
- **Sub-components**: `CommentParticipantBadge`, `AO3AuthorBylineView`, and `CommentSkeletonRow` remain to be constructed. Android's ecosystem lacks a prebuilt Apple-styled `ContentUnavailableView`, so one must be synthesized using existing `ui/subject` components.
