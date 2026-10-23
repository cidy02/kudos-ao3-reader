> **Checked by Claude-CLI, 2026-10-23 19:20.** Gemini 4 Argon (agy account 2) wrote what follows; these
> claims were checked before anything relies on them:
> - **Against Apple's pages (fetched):** the SDK-dependent behaviour (iOS 26 SDK: centred in a box; 27.0:
>   most of the inner display; 27.1+: the full display with toolbars and tab bars vertical below the status
>   bar), "don't choose a layout by idiom", "the device's orientation doesn't tell you what shape your app
>   is", "on the inner display, your app should look like a natural extension of its iPad layout"
>   (developer.apple.com/iphone-duo/prepare); bars moving to the side except the inner display in portrait,
>   the folding region, poses and "use size classes" (HIG *Designing for iPhone Duo*, read as JSON); Device
>   Hub's Closed / Partially Open / Open buttons and the Option-drag slider, and no command-line pose control
>   on that page; availability on 2026-10-23 and the April 2027 screenshot rule (developer news, 2026-10-05);
>   `ReservedRegion` (iOS 27.1+; `id`, `kind`, `frame`, `margins`, `isActive`; "the fold runs vertically at the
>   center of the display, so your content sits side by side").
> - **Against the iOS 27.1 SDK on this Mac:** `onHingeChange(isEnabled:_:)` reporting `DeviceHingeContext`,
>   `DeviceHinge` (SwiftUICore), `ArrangementView`, `ReservedRegion`, and UIKit's `UIHinge` (`status`:
>   closed, partially open, fully open; `angle`), `UIHingeInteraction`.
> - **On the simulator (Duo1):** the cover is 466×678 pt and the inner 669×951 pt at @3x, and Kudos (built
>   with the 27.1 SDK) fills the cover with a vertical tab bar on the right, as the 27.1 row predicts.
> - **Correction:** the HIG page says nothing about reading, books or two-page layouts. The two-page spread
>   in Apple Books and Quick Look is from secondary reporting only (AppleInsider), not Apple guidance.
> - Everything marked **secondary** (blakecrosley.com, expo.dev, AppleInsider) is unverified beyond the
>   sizes the simulator confirmed.

# iPhone Duo — Developer & Design Research (`Duo2-result.md`)

> **Research note:** All findings below come exclusively from web pages retrieved during this session (2026-10-23). Sources on `developer.apple.com` and `apple.com` (`www.apple.com`, `support.apple.com`) are treated as primary; all other domains are labeled **secondary**. Where a documentation or reference page displays no explicit calendar publication/last-updated date on the page itself, that is noted explicitly alongside its platform availability.

---

## 1. The device

### Form factor and overview
- **Claim:** iPhone Duo is Apple's first foldable iPhone, combining a compact outer display when folded closed with a thin, larger folding inner display connected by a center hinge when opened, each display having its own front-facing camera (with the inner camera hidden under the display until active).
  - **Quote:** "Apple today introduced iPhone Duo, the first foldable iPhone. Opened, it is the thinnest iPhone ever, with a 7.6-inch inner display that provides a large canvas for viewing content, gaming, and multitasking, and a special nano-texture finish that minimizes glare for an unparalleled viewing experience. Closed, the 5.4-inch outer display delivers 90 percent of the screen area of iPhone 18 Pro in a compact, pocketable design."
  - **Page title:** Apple unveils iPhone Duo - Apple Newsroom
  - **URL:** https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/
  - **Date:** September 9, 2026

- **Claim:** Hardware dimensions are 164.6 × 117.8 × 5.2 mm (6.48 × 4.64 × 0.20 in) unfolded and 84.1 × 117.8 × 11.3 mm (3.31 × 4.64 × 0.44 in) folded.
  - **Quote:** "Width: 6.48 inches (164.6 mm)" / "Height: 4.64 inches (117.8 mm)" / "Depth: 0.20 inch (5.2 mm)" (open); "Height: 4.64 inches (117.8 mm)" / "Width: 3.31 inches (84.1 mm)" / "Depth: 0.44 inch (11.3 mm)" (closed).
  - **Page title:** iPhone Duo - Technical Specifications - Apple
  - **URL:** https://www.apple.com/iphone-duo/specs/
  - **Date:** October 23, 2026 (lists "Released October 23, 2026")

- **Claim:** Both displays have front-facing cameras: the outer camera sits permanently visible in the corner aligned with the side control bar, whereas the inner camera sits behind the display and remains hidden until active.
  - **Quote:** "iPhone Duo has two displays, each with its own front-facing camera." "The outer front-facing camera is in the corner and is always visible, vertically aligned with controls on the side." "The inner camera is behind the display and stays hidden until the camera is active."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### Display sizes in pixels, points, and scale
- **Claim:** The inner folding OLED display measures 7.6 inches diagonally with a physical panel resolution of 1878 × 2670 pixels at 430 ppi, and the outer OLED display measures 5.4 inches diagonally with a physical panel resolution of 1398 × 2034 pixels at 460 ppi.
  - **Quote:** "Inner display; Super Retina XDR display; 7.6‑inch (diagonal) all‑screen OLED folding display; 1878‑by‑2670-pixel resolution at 430 ppi" and "Outer display; Super Retina XDR display; 5.4‑inch (diagonal) all‑screen OLED display; 1398‑by‑2034-pixel resolution at 460 ppi"
  - **Page title:** iPhone Duo - Technical Specifications - Apple
  - **URL:** https://www.apple.com/iphone-duo/specs/
  - **Date:** October 23, 2026

- **Claim:** App Store Connect's rendered screenshot resolutions are `1398 × 2034` / `2034 × 1398` pixels for the outer display and `2007 × 2853` / `2853 × 2007` pixels for the inner display (note: **no source found** on `developer.apple.com` or `apple.com` explicitly stating the logical point dimensions or `@3x` scale factor; Apple's HIG *Layout* specifications tables do not list iPhone Duo).
  - **Quote:** "Screenshot size: 1398 × 2034 pixels, 2034 × 1398 pixels (outer display)." "Screenshot size: 2007 × 2853 pixels, 2853 × 2007 pixels (inner display)."
  - **Page title:** Screenshot specifications - App information - Reference - App Store Connect - Help
  - **URL:** https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
  - **Date:** No publication/last-updated date shown on page (updated for iOS 27.1 / iPhone Duo)

- **Claim [secondary]:** Both displays use a `3x` display scale (`@3x`), with an aspect ratio of approximately `1.42`: the outer display is `466 × 678` points (`1398 × 2034` px at `3x` with no hardware downscaling), and the inner display renders at `669 × 951` points (`951 × 669` points in its default landscape-open orientation, equal to `2853 × 2007` px at `3x`) and scales down by ~6.4% per axis onto the `1878 × 2670` physical panel.
  - **Quote:** "TL;DR: App Store Connect's screenshot size for the inner display, published the afternoon of the keynote, is 2007 by 2853 pixels, which is 669 by 951 points at 3x on a 1878 by 2670 panel; my inference is that the display renders at 669 by 951 and scales down by about 6.4 percent in each dimension, as the Plus iPhones did, pending Device Hub. The aspect ratio is 1.42, close to the root-two ratio of A-series paper. The outer display is 1398 by 2034 pixels, 466 by 678 points at 3x with no scaling..."
  - **Page title:** iPhone Duo for Developers: The 1.42 Problem and the SDK Gap (**secondary**)
  - **URL:** https://blakecrosley.com/writing/iphone-duo-for-developers-the-142-problem-and-the-sdk-gap/
  - **Date:** September 9, 2026

- **Claim [secondary]:** Runtime probing in the Xcode 27.1 iPhone Duo simulator confirms that an app linked with the iOS 27.1 SDK receives `466 × 678` points when closed and `951 × 669` points when opened in landscape (`669 × 951` points when rotated to portrait).
  - **Quote:** "Stamped 27.1, the probe got the whole screen, 466 by 678 points closed and 951 by 669 open, with vertical bars and reserved regions." "Open, it gets the whole inner display, a landscape-native 951 by 669 points, regular in both size classes, vertical bars again, and an inactive division 40 points wide down the middle that turns active in the Book pose; turned, 669 by 951 with horizontal bars."
  - **Page title:** Prepare Your App for iPhone Duo: A Worked Example (**secondary**)
  - **URL:** https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/
  - **Date:** October 3, 2026

### States and postures (poses)
- **Claim:** Apple refers to the device's physical configurations as **poses**, encompassing closed (outer display), open (inner display), and partially folded states (held like a book, placed on a surface, or standing on its edges).
  - **Quote:** "People hold iPhone Duo and set it down in a number of ways: partially folded like a book, placed down on a surface, or standing on its edges."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

- **Claim:** Apple's user guide defines five named user postures: **Close** (outer display), **Open** (inner display flat), **Book** (partially folded, inner display facing user in landscape), **Tent** (partially folded, outer display facing user in landscape), and **Seated** (partially folded like a laptop, inner display facing user in portrait).
  - **Quote:** "Close: Fold iPhone Duo closed to use the outer display for quick, everyday tasks without unfolding it." "Open : Unfold iPhone Duo to use the larger inner display—for reading, watching, and using two apps at the same time." "Partially fold iPhone Duo like a book so the inner display faces you in landscape." "Partially fold iPhone Duo and place it down like a tent so the outer display faces you in landscape." "Partially fold iPhone Duo and set it down in a seated position so the inner display faces you in portrait."
  - **Page title:** Pose iPhone Duo - Apple Support
  - **URL:** https://support.apple.com/guide/iphone/pose-iphone-duo-iph1d102e3b8/ios
  - **Date:** No publication/last-updated date shown on page (iOS 27 User Guide, October 2026)

### Hinge and fold region
- **Claim:** A center hinge divides the inner display when folded; the system exposes both the fold (as a `division` reserved region) and cameras/Dynamic Island (as `occlusion` reserved regions) through the `ReservedRegion` / `UIView.ReservedRegion` APIs, including a `frame`, `margins`, `isActive` flag, `kind`, and `id`.
  - **Quote:** "Parts of the display aren't available for your content. For example, a camera or the Dynamic Island covers part of your view, and the fold of iPhone Duo splits it in two. The system describes each of these areas as a reserved region. Framework-provided views, such as split views and sheets, adjust for reserved regions for you. If you build a custom view that places its own content, find out where the reserved regions are and arrange your content around them."
  - **Page title:** ReservedRegion | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/reservedregion
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim [secondary]:** In the Xcode 27.1 simulator (iOS 27.1 SDK), the fold is reported at the exact center of the inner display as a `40`-point-wide `ReservedRegion` (including `20` points of margin on each side), inactive when flat open (`180°`) and active when partially folded (Device Hub's Book pose reports `127°`), without changing the window's point dimensions; on the outer display, the corner camera is reported as an active `37 × 37`-point occlusion. (Note: **no source found** on `developer.apple.com` or `apple.com` giving these exact point measurements.)
  - **Quote:** "It is reported open or folded, at the exact middle, and the frame the API returns is 40 points wide in both states, with 20 points of margin on each side." "Device Hub's Book pose reports the hinge as partly open at 127 degrees. The window does not change size. What changes is the division: same frame, now active." "The system reports that camera to any view that asks, as an active occlusion 37 points square, and its position matches the cutout in Apple's own bezel artwork to within a point and a half."
  - **Page title:** Prepare Your App for iPhone Duo: A Worked Example (**secondary**)
  - **URL:** https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/
  - **Date:** October 3, 2026

### Safe areas
- **Claim:** On the outer display (all orientations) and on the inner display in landscape, system and app bars (Dynamic Island, status bar, navigation bar, toolbar, tab bar) move into a vertical rail on the side of the screen, creating asymmetric horizontal safe areas; in Split View multitasking on the inner display, each app places its vertical controls along its outer edge; only the inner display in portrait retains standard horizontal top/bottom bars.
  - **Quote:** "On iPhone Duo, toolbars, tab bars, and navigation controls that are typically at the top and bottom of the display move to the side, preserving vertical space for content and keeping controls within easy reach. The exception is the inner display in portrait, which has enough vertical space to keep standard horizontal bars. Controls on the side include both system and app elements: the Dynamic Island, the status bar, the toolbar (including navigation buttons), and the tab bar." "Use safe areas to make sure controls don't cover your content, including controls on the opposite edge, like when two apps share the inner display with Split View multitasking."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### Orientations
- **Claim:** iPhone Duo supports rotation across poses on both displays; Apple explicitly warns against using device or interface orientation APIs to infer app layout shape, because orientation does not indicate aspect ratio or size on iPhone Duo.
  - **Quote:** "Avoid using orientation to make layout decisions: On iPhone Duo, the device's orientation doesn't tell you what shape your app is. Search for these properties and remove any layout logic that depends on them: `UIDevice.current.orientation`, `statusBarOrientation`, `interfaceOrientation`, including `windowScene.effectiveGeometry.interfaceOrientation`." "To find out whether your app is wider than it is tall, compare the width and height of the space you have: `view.bounds` in a view controller, `superview.bounds` in a view, or the size from `GeometryReader` in SwiftUI."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

### Shipped iOS version and release date
- **Claim:** iPhone Duo was unveiled on September 9, 2026, became available to customers worldwide on **October 23, 2026**, and shipped running **iOS 27.1**.
  - **Quote:** "iPhone Duo will be available to customers starting October 23, 2026."
  - **Page title:** Prepare and submit your apps for iPhone Duo - Latest News - Apple Developer
  - **URL:** https://developer.apple.com/news/?id=kkphp5qo
  - **Date:** October 5, 2026

- **Claim:** Apple confirmed on October 23, 2026 that iPhone Duo launched in Apple Stores worldwide that day, and Apple's iOS & iPadOS 27 release notes / developer beta news specify that iPhone Duo runs **iOS 27.1** at launch.
  - **Quote:** "On Friday, October 23, the highly anticipated iPhone Duo made its debut at Apple Store locations worldwide."
  - **Page title:** iPhone Duo arrives at Apple Store locations worldwide - Apple Newsroom
  - **URL:** https://www.apple.com/newsroom/2026/10/iphone-duo-arrives-at-apple-store-locations-worldwide/
  - **Date:** October 23, 2026

- **Claim:** Apple's release notes state that iPhone Duo ships with **iOS 27.1**.
  - **Quote:** "When iPhone Duo becomes available on October 23, it will run iOS 27.1."
  - **Page title:** iOS & iPadOS 27 Release Notes | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
  - **Date:** No single header date shown on page (updated September/October 2026 for iOS 27.1)

---

## 2. Human Interface Guidelines

### HIG pages and sections mentioning iPhone Duo
- **Claim:** Within the Human Interface Guidelines, **Designing for iPhone Duo** is the dedicated page covering iPhone Duo and its foldable form factor, organized into four main sections: **Anatomy**, **Device poses**, **Dynamic layouts**, and **Vertical controls**. (Checks of other HIG pages — including *Layout*, *Split views*, *Sidebars*, *Tab bars*, *Toolbars*, *Navigation bars*, *Multitasking*, *Windows*, *Typography*, *App icons*, *Launch screens*, and *Designing for iOS* — found **no source** mentioning "iPhone Duo".)
  - **Quote:** "September 9, 2026 — New page: Introduces the fundamental concepts of designing for iPhone Duo, including device poses, dynamic layouts across dual displays, and vertical controls."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### Layout and size classes
- **Claim:** The HIG advises using size classes, layout margins, and safe area insets rather than fixed widths or pose-specific custom layouts — specifically targeting a **compact width** layout for the outer display and a **regular width** layout for the inner display, expanding existing layouts rather than reinventing the UI.
  - **Quote:** "Use size classes, layout margins, and safe area insets to lay out controls and content. Avoid fixed widths and display-specific dependencies." "Supporting the device's various poses doesn't mean designing a custom layout for each one: instead, use size classes so your app adapts naturally as it changes size. A compact width layout for the outer display and a regular width layout for the inner display give you the fundamentals for every pose. Don't reinvent your app when it resizes; allow the existing layout to expand based on the available space instead."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### Navigation: split views, sidebars, tab bars, and toolbars
- **Claim:** Standard split views (`NavigationSplitView` / `UISplitViewController`) expand to multiple panes on the inner display, collapse to a single pane on the outer display, and automatically adjust pane widths and margins for reserved regions such as the fold.
  - **Quote:** "On iPhone Duo, a split view expands on the inner display and collapses to a single pane on the outer display, the same way it adapts between regular and compact environments on other iPhone devices. When built with standard components, split views adapt to reserved regions automatically, adjusting width and margins to adapt to the fold. For general guidance, see split views. For developer guidance, see NavigationSplitView (SwiftUI) and UISplitViewController (UIKit)."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

- **Claim:** Toolbars, navigation controls, and tab bars move to a vertical rail on the side of the screen (except on the inner display in portrait). Primary navigation controls (`Back`, `Close`) belong at the top of the vertical axis followed by prominent actions (`Done`), items overflow from bottom to top by default, toolbar items should provide both a symbol and a title (text-only labels force a horizontal bar), and apps should use system compression and overflow menus rather than overriding vertical bar placement.
  - **Quote:** "Follow the standard placement order for toolbar items. Reserve the top of the vertical axis for primary navigation controls, like Back or Close, followed by prominent actions, like Done." "Items overflow from bottom to top by default. Assign each item a visibility priority to change that order, starting with whole groups and then individual items within a group if you need finer control." "Include a title even when an item shows a symbol, because the system uses the title in overflow menus and expanded forms." "Keep text-based buttons to a minimum. Labels that include text stay in a horizontal bar, so prefer a symbol wherever one works." "In navigation-focused experiences, move toolbar items into the overflow menu so the tab bar and primary destinations remain accessible. This is the default bar compression behavior. In task-oriented experiences, minimize the tab bar to preserve the toolbar actions that are central to completing the task."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

- **Claim [secondary]:** Secondary coverage of Apple's iPhone Duo design guidance notes three patterns for expanding onto the inner display — a **split view** (preserving identical hierarchy to the outer display), **reflow** (single column to two columns), and **sidebar** (converting a tab bar into a sidebar for information-dense apps) — though explicit **sidebar** component rules were not found verbatim in the HIG text itself.
  - **Quote:** "Apple describes three honest ways to use the extra space on the inner display, rather than simply stretching an existing phone layout: Split view - showing two levels of hierarchy at once (a list and a detail view, for example), with the requirement that the hierarchy itself stays identical to what appears on the outer display. Reflow - a single vertical layout on the outer display becomes a two-column layout on the inner display. Sidebar - a tab bar that becomes a sidebar, best suited to information-dense apps."
  - **Page title:** Designing for iPhone Duo - HIG Guide in 5 Minutes (**secondary**)
  - **URL:** https://sagarunagar.com/blog/designing-for-iphone-duo-hig-guide/
  - **Date:** September 12, 2026

### Windows and multitasking
- **Claim:** *Designing for iPhone Duo* highlights **Split View multitasking** on the inner display — requiring layouts to adapt to variable widths and asymmetric safe areas because each Split View app places its vertical control bar on its outer screen edge (`left` app on the left, `right` app on the right). (For general multi-window design rules in the HIG, **no source found** on *Designing for iPhone Duo*.)
  - **Quote:** "Because the device has two displays and supports a wide range of poses and Split View multitasking, your app can appear at many different sizes." "When two apps share the inner display with Split View multitasking, each one places controls along its outer edge, so the left app has controls on the left."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### The hinge or fold, and continuity when the device changes state
- **Claim:** The HIG stresses continuity across state transitions — keeping functionality, element state, and bar vertical height consistent between outer and inner displays, avoiding abrupt layout jumps while folding, relying on automatic container adaptation where possible, and using `ReservedRegion` to displace important elements away from the center fold.
  - **Quote:** "An app designed for iPhone Duo adapts seamlessly to both displays, providing a continuous experience as the device opens and closes." "Create a consistent experience across displays. Keep functionality and the state of elements the same between displays." "On the inner display, controls remain on the side in landscape to preserve a continuous experience at the same vertical height." "Avoid extreme layout changes as people fold the device." "Prefer a layout container that adapts automatically, like the split view in Notes that adjusts the width of each pane to stay clearly visible as the device folds." "Use the ReservedRegion API to keep important elements clear of the center if the system doesn't move them automatically."
  - **Page title:** Designing for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
  - **Date:** September 9, 2026

### Typography and reading, app icons, and launch screens
- **Claim:** **No source found** in the Human Interface Guidelines for iPhone Duo–specific guidance on typography and reading, app icons, or launch screens.

---

## 3. APIs

### Opting in or out (SDK version vs. `Info.plist`)
- **Claim:** Apps opt in to full-screen iPhone Duo support, vertical bars, and fold/reserved-region reporting by compiling with **Xcode 27.1** (linking against the **iOS 27.1 SDK** or later). (**No source found** for any new iPhone Duo–specific `Info.plist` opt-in or opt-out key.)
  - **Quote:** "Apps built with the iOS 27.1 SDK or later are optimized for iPhone Duo. Apps will extend to use the full display, with toolbars and tab bars appearing vertically below the status bar. This provides people with an optimal and consistent experience as they move across displays. Before shipping an app build with the iOS 27.1 SDK, make sure your app's content adapts to the bars becoming vertical."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

- **Claim [secondary]:** iOS determines an app's compatibility tier on iPhone Duo by inspecting the SDK version stamped in the binary's `LC_BUILD_VERSION` Mach-O load command (`26.0`, `27.0`, or `27.1`); because the iOS 27.0 SDK lacks the new types (`ArrangementView`, etc.), `#available` alone is insufficient when sharing a codebase across Xcode 27.0 and 27.1, requiring a compiler flag or `#if canImport(SwiftUI, _version: 8.0.85)`.
  - **Quote:** "The SDK stamp is the switch. iOS reads the SDK version in the binary's `LC_BUILD_VERSION`." "Until the store takes 27.1, one source tree needs two Xcodes. `#available` does not help; the 27.0 SDK has no `ArrangementView` to compile against. A compilation flag, or `#if canImport(SwiftUI, _version: 8.0.85)`, fences the new calls."
  - **Page title:** Prepare Your App for iPhone Duo: A Worked Example (**secondary**)
  - **URL:** https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/
  - **Date:** October 3, 2026

- **Claim:** The `UIRequiresFullScreen` `Info.plist` key is deprecated and **no longer opts an app out of resizing** in iOS 27+; instead, it switches the scene to discrete resizing, and Apple directs developers to `UISceneSizeRestrictions` and `UIViewController.prefersInterfaceOrientationLocked` for size/orientation constraints.
  - **Quote:** "Starting in iOS 27 and iPadOS 27, UIRequiresFullScreen no longer opts your app out of resizing on either platform. Instead, the system resizes your app's scene discretely." "Opting out of iPad multitasking and dynamic resizing is deprecated. Use a combination of UISceneSizeRestrictions and prefersInterfaceOrientationLocked to replace some of the behaviors of UIRequiresFullScreen."
  - **Page title:** TN3192: Migrating your app from the deprecated UIRequiresFullScreen key | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key
  - **Date:** August 14, 2026

### Size-class, idiom, and trait changes
- **Claim:** iPhone Duo reports `userInterfaceIdiom == .phone` on both displays while changing size classes from compact width (closed) to regular width (open); Apple instructs developers to remove `userInterfaceIdiom` and orientation checks, read display scale from `traitCollection.displayScale` / `@Environment(\.displayScale)`, and treat display transitions as live trait and geometry updates rather than scene disconnects.
  - **Quote:** "On the inner display, your app should look like a natural extension of its iPad layout. For more information, see Prepare your app for iPhone Duo. Don't choose a layout by idiom. Search for userInterfaceIdiom == .phone and == .pad . Base layout choices on size classes or available space instead." "Get scale from the trait collection: Use `traitCollection.displayScale` in UIKit or `@Environment(\.displayScale)` in SwiftUI."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

- **Claim:** Apps can inspect whether the system places bars vertically on a side edge using `@Environment(\.toolbarVerticalEdge)` in SwiftUI or `UITraitCollection.verticalBarEdge` in UIKit, and configure bar compression and item overflow priority via `ToolbarVerticalCompressionBehavior` / `UIVerticalBarCompressionBehavior`, `ToolbarItemVisibilityPriority` / `UIBarButtonItemVisibilityPriority`, and `ToolbarOverflowMenu` / `additionalOverflowItems`.
  - **Quote:** "In a custom view, you may need to know if the system presents bars vertically to adjust your layout. Use the toolbarVerticalEdge environment value in SwiftUI or the verticalBarEdge trait in UIKit to determine if the system presents bars vertically."
  - **Page title:** Preparing your app for iPhone Duo | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** `EnvironmentValues.toolbarVerticalEdge` reports the system's preferred vertical bar edge even when no vertical bar is currently shown.
  - **Quote:** "This value reflects the system's preferred edge for the vertical bar in the current context, regardless of whether a vertical bar is currently visible. Use it to position custom bars or other UI relative to the system's bar placement."
  - **Page title:** toolbarVerticalEdge | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

### Learning the fold's position (`ReservedRegion` and `ArrangementView`)
- **Claim:** In SwiftUI, custom views query hardware reserved regions — including `.division` (the iPhone Duo fold) and `.occlusion` (cameras / Dynamic Island) — via `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)`, returning `[ReservedRegion]`.
  - **Quote:** "A reserved region indicates an area within a view's coordinate space that an entity, such as the device hardware, reserves. Arrange the view's content to account for this region. Each region describes a frame, margins, active state, and an identifier."
  - **Page title:** reservedRegions(kind:options:layoutDirectionBehavior:) | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** In UIKit, custom views query `UIView.ReservedRegion` values (`frame`, `margins`, `isActive`, `kind`, `id`) via `UIView.reservedRegions(kind:options:)` (Objective-C `reservedRegionsOfKind:options:`), passing `.includeInactive` (`UIViewReservedRegionQueryOptionsIncludeInactive`) if they also want inactive regions such as the flat-open fold.
  - **Quote:** "Read reserved regions using the reservedRegionsOfKind:options: method, which returns the reserved regions that overlap your view. By default, the method returns only active regions that affect your view. To also get inactive regions, pass UIViewReservedRegionQueryOptionsIncludeInactive ."
  - **Page title:** UIView.ReservedRegion | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/uikit/uiview/reservedregion
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** For two-pane or primary/secondary content, SwiftUI provides `ArrangementView` (styled with `ArrangementViewStyle`, e.g., split or overlay) and UIKit provides `UIArrangementViewController`, which automatically lay out primary and secondary views across size classes, orientations, and active fold reserved regions.
  - **Quote:** "Use an arrangement view to lay out two related content views differently depending on the current size classes, orientation, and status of reserved regions such as the fold on iPhone Duo."
  - **Page title:** ArrangementView | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/arrangementview
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** UIKit's `UIArrangementViewController` provides the view-controller counterpart to `ArrangementView`.
  - **Quote:** "Use an arrangement view controller to lay out two related content view controllers differently depending on the current size classes, orientation, and status of reserved regions such as the fold on iPhone Duo."
  - **Page title:** UIArrangementViewController | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/uikit/uiarrangementviewcontroller
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

### Learning the device's hinge state and angle (`onHingeChange`, `DeviceHinge`, `UIHingeInteraction`)
- **Claim:** In SwiftUI, `View.onHingeChange(isEnabled:_:)` delivers `(DeviceHingeContext, DeviceHingeContext)` updates, where `DeviceHinge` exposes `angle: Angle` and `status: DeviceHinge.Status` (e.g., `.closed`, `.partiallyOpen`, `.fullyOpen`).
  - **Quote:** "Adds an action to perform when the hinge context of the view hierarchy changes."
  - **Page title:** onHingeChange(isEnabled:_:) | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** `DeviceHinge` encapsulates a single hinge's `angle` and system-computed `status`.
  - **Quote:** "A type encapsulating the state of a single hinge. A hinge provides its angle along with a status determined by the system based on the current angle and device orientation."
  - **Page title:** DeviceHinge | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/devicehinge
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** In UIKit, `UIHingeInteraction` attaches to a `UIView` to deliver `UIHinge` state updates when the hinge changes or the view moves across view hierarchies.
  - **Quote:** "Add a UIHingeInteraction to a view to receive hinge state updates. The interaction's handler is called when the hinge state changes, or when the interaction moves between hierarchies. When the interaction moves out of a hierarchy that provides hinge updates, the update's hinge is nil."
  - **Page title:** UIHingeInteraction | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/uikit/uihingeinteraction
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

### Scene and window behaviour (including dual-display scene accessories)
- **Claim:** Apps must use `UIWindow(windowScene:)` and `view.bounds` / `window.bounds` rather than `UIScreen.main.bounds`, support dynamic window resizing and multi-scene Split View multitasking on the inner display, and can use `sceneAccessory(content:)` (SwiftUI) or `UISceneAccessory` (UIKit) to present supplementary content on the second display simultaneously (such as `CameraCaptureAccessory`).
  - **Quote:** "Replace `UIWindow(frame: UIScreen.main.bounds)` with `UIWindow(windowScene:)`." "Don't store a UIScreen: When screen information is needed, access it dynamically with `view.window?.windowScene?.screen`."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

- **Claim:** `UISceneAccessory` (UIKit) and `sceneAccessory(content:)` (SwiftUI) declare supplementary content that the system presents on a secondary/external display when available.
  - **Quote:** "A scene accessory declares supplementary content that the system presents on your app's behalf when associated functionality becomes available, such as an external display connected by cable or AirPlay."
  - **Page title:** UISceneAccessory | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/uikit/uisceneaccessory
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

### WWDC 2026 sessions vs. September 2026 Tech Talks
- **Claim:** **No WWDC 2026 session specifically covers iPhone Duo** (WWDC 2026 took place in June 2026, three months before iPhone Duo's September 9, 2026 unveiling). However, Apple's `TN3192` cites **WWDC26 Session 278 (*Modernize your UIKit app*)** for prerequisite iOS 27 discrete resizing and UIKit resizability modernization.
  - **Quote:** "Discover the latest updates to UIKit. Learn how to update your iPhone app layouts to work great when resized with iPhone Mirroring and on iPad. Explore new APIs for tab and navigation bars, find out how to prepare your app for new Apple Intelligence capabilities, and get introduced to a skill for your coding agent of choice that helps modernize your codebase."
  - **Page title:** Modernize your UIKit app - WWDC26 - Videos - Apple Developer
  - **URL:** https://developer.apple.com/videos/play/wwdc2026/278/
  - **Date:** June 8, 2026

- **Claim:** Instead of WWDC 2026 sessions, Apple published **six dedicated iPhone Duo Tech Talks** on September 9, 2026 (`111461`–`111466`):
  1. **Tech Talk 111466 — *Design for iPhone Duo***
     - **Quote:** "iPhone Duo is the first folding iPhone and comes with a reimagined iOS. Get to know the design principles behind the updated software, explore how controls move between different poses, and learn where your layout needs to adapt and why."
     - **Page title:** Design for iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111466/
     - **Date:** September 9, 2026
  2. **Tech Talk 111461 — *Prepare your app for iPhone Duo***
     - **Quote:** "Learn how to update and optimize your app for the foldable display of iPhone Duo. Discover how to opt in to the full-screen experience, adopt flexible layout best practices, and simulate poses in Device Hub with Xcode. Find out how to use size classes instead of interface orientation, handle asymmetric safe areas, and test Split View multitasking to ensure your app shines in all the ways people use it."
     - **Page title:** Prepare your app for iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111461/
     - **Date:** September 9, 2026
  3. **Tech Talk 111462 — *Raise the bar with iPhone Duo***
     - **Quote:** "Discover how to adapt your navigation, toolbars, and tab bars for the unique displays of iPhone Duo. Explore the design principles behind the new bar layout, and learn how to configure custom view representations and manage overflow to build powerful, responsive apps."
     - **Page title:** Raise the bar with iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111462/
     - **Date:** September 9, 2026
  4. **Tech Talk 111463 — *Strike a pose with adaptive layouts on iPhone Duo***
     - **Quote:** "Learn how to create responsive, flexible layouts that work great on iPhone Duo. Explore displacement design patterns that keep content visible and reachable as people open and close their iPhone Duo. Discover how to use arrangement views in SwiftUI and UIKit to build split and overlay presentations, and find out how to query reserved regions to tailor layouts around the hinge and cameras."
     - **Page title:** Strike a pose with adaptive layouts on iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111463/
     - **Date:** September 9, 2026
  5. **Tech Talk 111464 — *Leverage multiple displays and scenes on iPhone Duo***
     - **Quote:** "Discover how to build rich multiwindow and multidisplay experiences for iPhone Duo. Explore how to handle dynamic window sizes and request new scenes in side-by-side multitasking. Learn how to observe hinge angle changes in SwiftUI and UIKit to create interactive effects. And find out how to use scene accessories to present supplementary content across both displays simultaneously."
     - **Page title:** Leverage multiple displays and scenes on iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111464/
     - **Date:** September 9, 2026
  6. **Tech Talk 111465 — *Build a great camera experience for iPhone Duo***
     - **Quote:** "Discover how to leverage the outer and inner cameras on iPhone Duo. Explore the Virtual Front Camera, and find out how to use the direction coordinator to switch between cameras and update your UI as people open and close iPhone Duo. Learn best practices for handling preview aspect ratios, positioning, and rotation to deliver a seamless capture experience."
     - **Page title:** Build a great camera experience for iPhone Duo - Tech Talks - Videos - Apple Developer
     - **URL:** https://developer.apple.com/videos/play/tech-talks/111465/
     - **Date:** September 9, 2026

---

## 4. Compatibility and testing

### What an unmodified app gets on iPhone Duo
- **Claim:** All existing iOS apps run on iPhone Duo without recompiling, with behavior determined by the SDK they were built against:
  - **Built with iOS 26 SDK or earlier:** Letterboxed/pillarboxed — centered with surrounding empty space on the open inner display, and inset to the left of the status bar and camera on the closed outer display.
  - **Built with iOS 27.0 SDK:** Dynamically resizes to fill most of the inner display when unfolded, but still stops short of the status bar rail on the right edge and keeps horizontal bars.
  - **Built with iOS 27.1 SDK or later:** Full-screen edge-to-edge on both displays, with toolbars and tab bars placed vertically below the status bar.
  - **Quote:** "iOS 26 SDK: Apps built with the iOS 26 SDK or earlier run on iPhone Duo, but won't adapt to all layouts. When the device is open, your app will appear in the center of the display, with empty space surrounding the window. When the device is closed, the outer display will show your app's content to the left of the status bar and camera." "iOS 27 SDK: Apps built with the iOS 27 SDK resize to fill most of the inner display on iPhone Duo, but still avoid the status bar on the right edge. This provides an improved experience, as empty space is minimized." "iOS 27.1 SDK or later: Apps built with the iOS 27.1 SDK or later are optimized for iPhone Duo. Apps will extend to use the full display, with toolbars and tab bars appearing vertically below the status bar."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

- **Claim [secondary]:** Measured in the Xcode 27.1 simulator, a binary linked against the **iOS 26.0 SDK** renders in a `375 × 667`-point phone box; linked against the **iOS 27.0 SDK**, it resizes dynamically but stops `80` points short of the status rail edge with horizontal bars and receives no fold information; linked against the **iOS 27.1 SDK**, it gets the full `466 × 678` (closed) and `951 × 669` (open) canvas with vertical bars and fold reserved regions.
  - **Quote:** "Stamped 27.1, the probe got the whole screen, 466 by 678 points closed and 951 by 669 open, with vertical bars and reserved regions. Stamped 27.0, it stopped 80 points short of the edge where the status rail is, kept horizontal bars, and was told nothing about the fold. Stamped 26.0, it was a 375 by 667 phone in a box."
  - **Page title:** Prepare Your App for iPhone Duo: A Worked Example (**secondary**)
  - **URL:** https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/
  - **Date:** October 3, 2026

- **Claim:** Regarding **the iPhone vs. the iPad layout**: iPhone Duo runs the iPhone app with `userInterfaceIdiom == .phone`, so an app using adaptive size-class containers (`NavigationSplitView`, `horizontalSizeClass == .regular`) automatically gets its regular-width (iPad-like) multi-column layout on the inner display, whereas an app branching on `userInterfaceIdiom == .pad` stays stuck in its iPhone layout.
  - **Quote:** "On the inner display, your app should look like a natural extension of its iPad layout. For more information, see Prepare your app for iPhone Duo. Don't choose a layout by idiom. Search for userInterfaceIdiom == .phone and == .pad . Base layout choices on size classes or available space instead."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

### App Store requirements and deadlines
- **Claim:** Developers can submit iPhone Duo–optimized apps and screenshots in App Store Connect now; submitting iPhone Duo screenshots adds an "optimized for iPhone Duo" badge on the App Store product page, and **starting April 2027**, submitted apps and games must include iPhone Duo screenshots.
  - **Quote:** "You can submit your iPhone Duo optimized apps and games in App Store Connect today. When you submit iPhone Duo screenshots in App Store Connect, your App Store product page will display a badge to let people know your app is optimized for iPhone Duo. Starting April 2027, any apps or games submitted will need to include screenshots for iPhone Duo."
  - **Page title:** Prepare and submit your apps for iPhone Duo - Latest News - Apple Developer
  - **URL:** https://developer.apple.com/news/?id=kkphp5qo
  - **Date:** October 5, 2026

- **Claim:** App Store Connect Help's screenshot specification reference states the April 2027 screenshot requirement specifically in terms of apps built with the iOS 27.1 SDK or later. (**No source found** for a separate App Store deadline mandating compilation with Xcode 27.1 / iOS 27.1 SDK itself.)
  - **Quote:** "Starting in April 2027, screenshots will be required for any app using the iOS 27.1 SDK or later."
  - **Page title:** Screenshot specifications - App information - Reference - App Store Connect - Help
  - **URL:** https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
  - **Date:** No publication/last-updated date shown on page (updated for iOS 27.1 / iPhone Duo)

### Testing in the Simulator / Device Hub
- **Claim:** In Xcode 27 / 27.1, **Device Hub** hosts the iPhone Duo simulator, which switches between three primary pose buttons below the device bezel — **Closed**, **Partially Open**, and **Open** — and supports continuous arbitrary-angle folding by **holding the `Option` key while dragging the slider** below the bezel. For rotation and bezels, Device Hub provides menu commands **Controls > Rotate Left**, **Controls > Rotate Right** (or Option-clicking the rotate button below the bezel), **Device > Orientation**, and **View > Show Bezels** / **View > Hide Bezels**. (**No source found** for menu-bar commands that switch between Closed, Partially Open, and Open fold states.)
  - **Quote:** "To ensure your iOS app adapts seamlessly to both iPhone Duo displays, simulate folding an iPhone Duo using the controls below the bezel in the canvas: To close the iPhone Duo, click the Closed button on the right of the Rotate Right button. To partially open the iPhone Duo, click the Partially Open button in the middle of the three device pose buttons. To fully open the iPhone Duo, click the Open button on the far right. To fold the device to any angle, hold the Option key while dragging the slider that appears below the bezel."
  - **Page title:** Interacting with your app in Device Hub | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub
  - **Date:** No publication/last-updated date shown on page (Xcode 27 / 27.1 documentation)

- **Claim [secondary]:** Device Hub replaces the standalone `Simulator.app` in Xcode 27 and is launched from Xcode via **Xcode > Open Developer Tool > Device Hub**.
  - **Quote:** "Xcode 27 also replaces Simulator.app with Device Hub (Xcode > Open Developer Tool > Device Hub), which provides a 3D simulator for iPhone Duo where you can open and rotate to various poses as well as freely adjust the hinge angle."
  - **Page title:** Supporting iPhone Duo with Expo: a developer guide (**secondary**)
  - **URL:** https://expo.dev/blog/supporting-iphone-duo-with-expo-a-developer-guide
  - **Date:** October 23, 2026

- **Claim:** Xcode 27.1 also includes an Xcode coding assistant "app resizability skill" invoked by asking the assistant to *"get my app ready for iPhone Duo"*, and Xcode 27.1 Release Notes document simulator limitations (StandBy and debugging most app extensions are unavailable in the iPhone Duo Simulator runtime).
  - **Quote:** "In Xcode, ask the coding assistant to “get my app ready for iPhone Duo.” The skill scans your project for the patterns described in Step 2. For each issue it finds, it explains the problem and suggests a fix."
  - **Page title:** Prepare - iPhone Duo - Apple Developer
  - **URL:** https://developer.apple.com/iphone-duo/prepare/
  - **Date:** No publication/last-updated date shown on page (published September/October 2026 for Xcode 27.1)

- **Claim:** Xcode 27.1 Release Notes note specific runtime limitations in the iPhone Duo simulator.
  - **Quote:** "StandBy is unavailable in the iPhone Duo Simulator runtime. (187708663)" "Running and debugging most app extensions is unavailable in the iPhone Duo Simulator runtime. (187708767)"
  - **Page title:** Xcode 27.1 Release Notes | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes
  - **Date:** October 15, 2026

---

## 5. Reading apps

- **Claim:** Apple's user documentation explicitly positions the open inner display for reading and defines the **Book** pose — partially folding iPhone Duo in landscape like a physical book. (**No source found** on `developer.apple.com` for a dedicated reading-app sample project, typography/line-length guide specific to iPhone Duo, or `UIPageViewController` / TextKit / SwiftUI two-page reader guide for iPhone Duo.)
  - **Quote:** "Open : Unfold iPhone Duo to use the larger inner display—for reading, watching, and using two apps at the same time." "Partially fold iPhone Duo like a book so the inner display faces you in landscape."
  - **Page title:** Pose iPhone Duo - Apple Support
  - **URL:** https://support.apple.com/guide/iphone/pose-iphone-duo-iph1d102e3b8/ios
  - **Date:** No publication/last-updated date shown on page (iOS 27 User Guide, October 2026)

- **Claim:** Apple's `ReservedRegion` documentation specifically uses the book posture as the canonical example of a vertical center fold placing content side by side across the two halves of the inner display.
  - **Quote:** "When you partially fold iPhone Duo like a book, the fold runs vertically at the center of the display, so your content sits side by side."
  - **Page title:** ReservedRegion | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/swiftui/reservedregion
  - **Date:** No publication/last-updated date shown on page (availability: iOS 27.1+)

- **Claim:** On the Apple Developer Forums, an Apple Frameworks Engineer confirmed that `NavigationSplitView` and `UISplitViewController` automatically pad their columns and layout margins around the fold in the `"Book"` pose, whereas custom `UICollectionView` / `UICollectionViewCompositionalLayout` layouts have **no** automatic fold avoidance and must query reserved regions manually if sections do not scroll orthogonally across the fold.
  - **Quote:** "`NavigationSplitView`/`UISplitViewController` have built-in behavior to appropriately pad their columns when the device is in the \"Book\" pose, which they achieve, by adjusting column widths and layout margins within the column." "For a compositional layout, if you need to avoid the area of the fold, you should only do that in sections that aren't scrolling orthogonal to the fold's axis, by reading the reserved regions from the collection view and manually adjusting your compositional layout. There is no automatic fold avoidance to UICollectionView or compositional layout at this time, continuous or otherwise."
  - **Page title:** UICollectionViewCompositionalLayout invalidation context and coordinate space transforms during interactive hinge transitions | Apple Developer Forums
  - **URL:** https://developer.apple.com/forums/thread/774215
  - **Date:** September 23, 2026

- **Claim:** For general single-column vs. multi-column long-text width on regular-width displays, UIKit's `UIView.readableContentGuide` defines optimal line width and column sizing (general platform API, not specific to iPhone Duo).
  - **Quote:** "This layout guide defines an area that can easily be read without forcing users to move their head to track the lines." "Use the readable content guide to lay out a single column of text. If you are laying out multiple columns, you can use the guide's width to determine the optimal width for your columns."
  - **Page title:** readableContentGuide | Apple Developer Documentation
  - **URL:** https://developer.apple.com/documentation/uikit/uiview/readablecontentguide
  - **Date:** No publication/last-updated date shown on page

- **Claim [secondary]:** Secondary reporting on iOS 27 betas notes that both **Apple Books** and system **Quick Look** automatically switch documents/books into a facing **two-page spread** when the user holds iPhone Duo slightly folded like a book.
  - **Quote:** "Specifically, a document being shown in Quick Look will switch to being a double-page spread when the iPhone Duo is held slightly folded. It's not a surprising addition, since the same thing has been shown by Apple over reading in Apple Books. If the user holds the iPhone Duo like a book, the e-reader screen also switches to a spread."
  - **Page title:** iPhone Duo has a book-like two-page Quick Look layout (**secondary**)
  - **URL:** https://www.appleinsider.com/articles/26/10/07/iphone-duo-has-a-book-like-two-page-quick-look-layout
  - **Date:** October 7, 2026

- **Claim [secondary]:** Secondary developer analysis notes that the inner display's `1.42` aspect ratio (`951 × 669` pt open, `669 × 951` pt in portrait) closely approximates the $\sqrt{2}$ (`1.414`) aspect ratio of A-series paper, and demonstrates using SwiftUI's `ArrangementView` + `onHingeChange` so a two-pane layout aligns its divider with the `40`-point fold band in the Book pose.
  - **Quote:** "The aspect ratio is 1.42, close to the root-two ratio of A-series paper."
  - **Page title:** iPhone Duo for Developers: The 1.42 Problem and the SDK Gap (**secondary**)
  - **URL:** https://blakecrosley.com/writing/iphone-duo-for-developers-the-142-problem-and-the-sdk-gap/
  - **Date:** September 9, 2026
  - **Quote:** "One ArrangementView divides the open display between the page and the inspector; in the Book pose it moves its divider onto the fold and leaves the 40-point band empty by itself."
  - **Page title:** Prepare Your App for iPhone Duo: A Worked Example (**secondary**)
  - **URL:** https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/
  - **Date:** October 3, 2026

---

## Not found

- **Question 1 — Logical point sizes, `@3x` scale factor, and numeric fold/safe-area point widths in primary Apple sources:** **no source found** on `developer.apple.com` or `apple.com` stating the exact logical point dimensions (`466 × 678` pt outer, `669 × 951` pt inner), the `@3x` scale factor / ~6.4% inner-display downsampling, or the exact point measurements of the fold `ReservedRegion` (`40` pt with `20` pt margins), camera cutout (`37 × 37` pt), and vertical status rail (`80` pt). Those figures were found only in secondary developer testing (`blakecrosley.com`).
- **Question 2 — Other HIG pages mentioning iPhone Duo:** **no source found** — no HIG page other than *Designing for iPhone Duo* (`https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo`) was found to mention iPhone Duo.
- **Question 2 — HIG guidance on multi-window UI, sidebars (verbatim in HIG), typography and reading, app icons, and launch screens for iPhone Duo:** **no source found** — *Designing for iPhone Duo* covers Split View multitasking, split views, vertical toolbars/tab bars, poses, reserved regions, and display continuity, but contains no guidance on multi-window management, typography/reading, app icons, or launch screens, and no standalone sidebar section in the HIG text itself.
- **Question 3 — iPhone Duo–specific `Info.plist` keys:** **no source found** — opting in is controlled by linking against the iOS 27.1 SDK (`LC_BUILD_VERSION`), and `UIRequiresFullScreen` is deprecated (`TN3192`); no new `Info.plist` key for iPhone Duo was found.
- **Question 3 — WWDC 2026 sessions about iPhone Duo (and full Tech Talk transcripts):** **no source found** — WWDC 2026 occurred in June 2026 prior to the September 9, 2026 announcement, so no WWDC 2026 session covers iPhone Duo (Apple instead released Tech Talks `111461`–`111466` on September 9, 2026; full closed-caption transcripts of those Tech Talks were not accessible via unauthenticated web search).
- **Question 4 — Menu-bar commands in Simulator / Device Hub for switching fold poses:** **no source found** — Apple's *Interacting with your app in Device Hub* documents canvas bezel buttons (`Closed`, `Partially Open`, `Open`) and `Option`-dragging the slider below the bezel for arbitrary fold angles, plus menu-bar commands for rotation and bezels, but no menu-bar commands for switching fold poses.
- **Question 4 — Mandatory App Store SDK deadline for Xcode 27.1 / iOS 27.1 SDK:** **no source found** — only the **April 2027** deadline for iPhone Duo App Store screenshots was found.
- **Question 5 — Official Apple developer documentation, sample code, or HIG guidance specifically for reading apps, books, long text, or two-page layouts on iPhone Duo:** **no source found** on `developer.apple.com` beyond general references to the Book pose, `ReservedRegion` side-by-side content placement across the center fold, and non-Duo-specific `UIView.readableContentGuide` documentation (the Apple Books and Quick Look two-page spread behavior in Book pose was found only in a secondary source, `appleinsider.com`).

---

## Sources

### Primary — `developer.apple.com`
1. https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo — *Designing for iPhone Duo | Apple Developer Documentation*
2. https://developer.apple.com/design/human-interface-guidelines/layout — *Layout | Apple Developer Documentation* (checked; no mention of iPhone Duo)
3. https://developer.apple.com/iphone-duo/ — *Get Ready for iPhone Duo - Apple Developer*
4. https://developer.apple.com/iphone-duo/prepare/ — *Prepare - iPhone Duo - Apple Developer*
5. https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo — *Preparing your app for iPhone Duo | Apple Developer Documentation*
6. https://developer.apple.com/news/?id=kkphp5qo — *Prepare and submit your apps for iPhone Duo - Latest News - Apple Developer*
7. https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications — *Screenshot specifications - App information - Reference - App Store Connect - Help*
8. https://developer.apple.com/documentation/swiftui/arrangementview — *ArrangementView | Apple Developer Documentation*
9. https://developer.apple.com/documentation/swiftui/arrangementviewstyle — *ArrangementViewStyle | Apple Developer Documentation*
10. https://developer.apple.com/documentation/uikit/uiarrangementviewcontroller — *UIArrangementViewController | Apple Developer Documentation*
11. https://developer.apple.com/documentation/swiftui/reservedregion — *ReservedRegion | Apple Developer Documentation*
12. https://developer.apple.com/documentation/swiftui/reservedregion/kind — *ReservedRegion.Kind | Apple Developer Documentation*
13. https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:) — *reservedRegions(kind:options:layoutDirectionBehavior:) | Apple Developer Documentation*
14. https://developer.apple.com/documentation/uikit/uiview/reservedregion — *UIView.ReservedRegion | Apple Developer Documentation*
15. https://developer.apple.com/documentation/uikit/uiview/reservedregion/kind — *UIView.ReservedRegion.Kind | Apple Developer Documentation*
16. https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:) — *reservedRegions(kind:options:) | Apple Developer Documentation*
17. https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:) — *onHingeChange(isEnabled:_:) | Apple Developer Documentation*
18. https://developer.apple.com/documentation/swiftui/devicehingecontext — *DeviceHingeContext | Apple Developer Documentation*
19. https://developer.apple.com/documentation/swiftui/devicehinge — *DeviceHinge | Apple Developer Documentation*
20. https://developer.apple.com/documentation/uikit/uihingeinteraction — *UIHingeInteraction | Apple Developer Documentation*
21. https://developer.apple.com/documentation/uikit/uihinge — *UIHinge | Apple Developer Documentation*
22. https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge — *toolbarVerticalEdge | Apple Developer Documentation*
23. https://developer.apple.com/documentation/uikit/uitraitcollection/verticalbaredge — *verticalBarEdge | Apple Developer Documentation*
24. https://developer.apple.com/documentation/swiftui/toolbarverticalcompressionbehavior — *ToolbarVerticalCompressionBehavior | Apple Developer Documentation*
25. https://developer.apple.com/documentation/uikit/uiverticalbarcompressionbehavior — *UIVerticalBarCompressionBehavior | Apple Developer Documentation*
26. https://developer.apple.com/documentation/swiftui/toolbaritemvisibilitypriority — *ToolbarItemVisibilityPriority | Apple Developer Documentation*
27. https://developer.apple.com/documentation/uikit/uibarbuttonitemvisibilitypriority — *UIBarButtonItemVisibilityPriority | Apple Developer Documentation*
28. https://developer.apple.com/documentation/uikit/uisceneaccessory — *UISceneAccessory | Apple Developer Documentation*
29. https://developer.apple.com/documentation/swiftui/view/sceneaccessory(content:) — *sceneAccessory(content:) | Apple Developer Documentation*
30. https://developer.apple.com/documentation/uikit/uiscenesizerestrictions — *UISceneSizeRestrictions | Apple Developer Documentation*
31. https://developer.apple.com/documentation/uikit/uiview/readablecontentguide — *readableContentGuide | Apple Developer Documentation*
32. https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key — *TN3192: Migrating your app from the deprecated UIRequiresFullScreen key | Apple Developer Documentation*
33. https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub — *Interacting with your app in Device Hub | Apple Developer Documentation*
34. https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes — *Xcode 27.1 Release Notes | Apple Developer Documentation*
35. https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes — *iOS & iPadOS 27 Release Notes | Apple Developer Documentation*
36. https://developer.apple.com/videos/play/tech-talks/111461/ — *Prepare your app for iPhone Duo - Tech Talks - Videos - Apple Developer*
37. https://developer.apple.com/videos/play/tech-talks/111462/ — *Raise the bar with iPhone Duo - Tech Talks - Videos - Apple Developer*
38. https://developer.apple.com/videos/play/tech-talks/111463/ — *Strike a pose with adaptive layouts on iPhone Duo - Tech Talks - Videos - Apple Developer*
39. https://developer.apple.com/videos/play/tech-talks/111464/ — *Leverage multiple displays and scenes on iPhone Duo - Tech Talks - Videos - Apple Developer*
40. https://developer.apple.com/videos/play/tech-talks/111465/ — *Build a great camera experience for iPhone Duo - Tech Talks - Videos - Apple Developer*
41. https://developer.apple.com/videos/play/tech-talks/111466/ — *Design for iPhone Duo - Tech Talks - Videos - Apple Developer*
42. https://developer.apple.com/videos/play/wwdc2026/278/ — *Modernize your UIKit app - WWDC26 - Videos - Apple Developer*
43. https://developer.apple.com/forums/thread/774215 — *UICollectionViewCompositionalLayout invalidation context and coordinate space transforms during interactive hinge transitions | Apple Developer Forums*

### Primary — `apple.com`
44. https://www.apple.com/newsroom/2026/09/apple-unveils-iphone-duo/ — *Apple unveils iPhone Duo - Apple Newsroom*
45. https://www.apple.com/newsroom/2026/10/iphone-duo-arrives-at-apple-store-locations-worldwide/ — *iPhone Duo arrives at Apple Store locations worldwide - Apple Newsroom*
46. https://www.apple.com/iphone-duo/specs/ — *iPhone Duo - Technical Specifications - Apple*
47. https://support.apple.com/guide/iphone/pose-iphone-duo-iph1d102e3b8/ios — *Pose iPhone Duo - Apple Support*

### Secondary
48. https://blakecrosley.com/writing/iphone-duo-for-developers-the-142-problem-and-the-sdk-gap/ — *iPhone Duo for Developers: The 1.42 Problem and the SDK Gap* (**secondary**)
49. https://blakecrosley.com/writing/prepare-your-app-for-iphone-duo-a-worked-example/ — *Prepare Your App for iPhone Duo: A Worked Example* (**secondary**)
50. https://expo.dev/blog/supporting-iphone-duo-with-expo-a-developer-guide — *Supporting iPhone Duo with Expo: a developer guide* (**secondary**)
51. https://sagarunagar.com/blog/designing-for-iphone-duo-hig-guide/ — *Designing for iPhone Duo - HIG Guide in 5 Minutes* (**secondary**)
52. https://www.appleinsider.com/articles/26/10/07/iphone-duo-has-a-book-like-two-page-quick-look-layout — *iPhone Duo has a book-like two-page Quick Look layout* (**secondary**)
