# Native iOS vs hand-rolled code — audit report

| Field | Value |
|---|---|
| **Scope tip** | `hig-review` @ `29cd915` (*Keep the Mac build compiling: the zoom transition is iOS-only*) |
| **Audit root** | `.claude/worktrees/non-epub-pdf-distribution-ab6eba` |
| **App deployment** | **iOS 26.5** (`IPHONEOS_DEPLOYMENT_TARGET` on the app target) |
| **Date** | 2026-07-31 |
| **Question** | Where does hand-rolled code exist when **native Apple APIs** would be cleaner and better? |
| **Method** | 6 exploration agents (nav, UIComponents, lists/search, reader, settings/a11y, services) → 22 candidates → **3 independent evidence reviewers** (R1/R2/R3). Document only findings with **≥2/3 AGREE**. |

### Availability note

Every native recommendation below is available on the app’s **iOS 26.5** floor (often for many major versions). “Available since” is the **first iOS version** that introduced the API (from Apple’s public documentation / platform history), not a suggestion to lower the deployment target.

### Consensus rule

| Votes | Disposition |
|---|---|
| **3/3 AGREE** | Documented finding |
| **2/3 AGREE** | Documented finding (minority DISAGREE noted) |
| **≤1/3 AGREE** | Not a finding — listed under “Rejected candidates” |

---

## Consensus findings (document only if ≥2/3 AGREE)

### F-01 — Dead reader dismiss-peel gesture path after system zoom dismiss

| | |
|---|---|
| **Consensus** | **3/3 AGREE** (R1, R2, R3) |
| **Hand-rolled** | Custom UIKit peel/freeze/snapshot dismiss stack still present; the pan recognizer is **intentionally not installed**, so `handleDismissPan` and related freeze logic never run. |
| **Evidence** | `ReadiumNavigatorContainer.swift` **134–146** (`// No drag-to-dismiss recogniser of our own any more…` `dismissPan` stays nil; peel left “for one build”). `handleDismissPan` still defined from **153+**. `ReaderDismissDrag.swift` **24–206** (`ReaderDismissDragSurface`, `ReaderDismissPeelHost`). `ReadiumReaderView.swift` still wraps content in `ReaderDismissPeelHost` (**~935**). |
| **Native alternative** | Keep system interactive zoom dismiss already wired via `matchedTransitionSource` / `navigationTransition(.zoom)` (`WorkCardZoomTransition.swift`). **Available since: iOS 18.** |
| **Why cleaner** | Deletes unreachable gesture code; one dismiss model (system zoom) instead of dual systems. |
| **Caveat** | T-186 notes the peel **host** may still be required for full-bleed (`safeAreaRegions = []`) and open skeleton geometry — that is separate from the **dead pan handler**. |

**Shape:** hand-rolled peel pan + freeze stack (dead) at `ReadiumNavigatorContainer.swift:134–153` → native zoom interactive dismiss, available since **iOS 18**.

---

### F-02 — Settings font list: Button + checkmark instead of `Picker`

| | |
|---|---|
| **Consensus** | **2/3 AGREE** (R1, R2; R3 DISAGREE — confused Settings with Customize Theme, which already uses `Picker`) |
| **Hand-rolled** | `Section("Font")` builds rows with `Button` + trailing `checkmark` for selection, plus swipe delete for custom fonts. |
| **Evidence** | `SettingsView.swift` **242–261**. Contrast: `CustomizeThemeView.swift` **63** already uses `Picker("Font", selection: $fontID)`. |
| **Native alternative** | SwiftUI `Picker` (`.navigationLink` / list / menu). **Available since: iOS 13** (SwiftUI); continuous refinements through current OS. Swipe-to-delete for custom fonts can stay a separate “Manage fonts” path. |
| **Why cleaner** | One selection idiom app-wide; free selection a11y; matches Customize Theme. |

**Shape:** hand-rolled font checkmark list at `SettingsView.swift:242–261` → `Picker`, available since **iOS 13**.

---

### F-03 — “Require Face ID” label while auth is full device-owner authentication

| | |
|---|---|
| **Consensus** | **3/3 AGREE** |
| **Hand-rolled / incorrect product string** | Toggle title hardcodes Face ID. Gate uses `LAContext` with **`.deviceOwnerAuthentication`** (biometrics **or** device passcode). |
| **Evidence** | Label: `SettingsView.swift` **382**. Policy: `MatureContent.swift` **89–96** (`canEvaluatePolicy(.deviceOwnerAuthentication)` / `evaluatePolicy(.deviceOwnerAuthentication, …)`). |
| **Native alternative** | `LAContext.biometryType` (`.faceID` / `.touchID` / `.opticID` / `.none`) to pick the title, or generic **“Require device authentication”**. **`LABiometryType` / `biometryType` available since: iOS 11.** `LocalAuthentication` evaluatePolicy since earlier iOS. |
| **Why cleaner** | Honest on Touch ID, Optic ID, and passcode-only devices; matches Apple HIG auth copy guidance. |

**Shape:** hardcoded “Face ID” at `SettingsView.swift:382` while policy is device-owner auth at `MatureContent.swift:89–96` → `LAContext.biometryType`-aware (or generic) copy, available since **iOS 11**.

---

### F-04 — Library Sync “Disconnect” is destructive with no confirmation

| | |
|---|---|
| **Consensus** | **3/3 AGREE** |
| **Hand-rolled / missing system pattern** | Destructive button calls disconnect immediately. |
| **Evidence** | `SettingsView.swift` **1166–1168** (`Button(role: .destructive, action: onDisconnect)`). Action: **856+** `disconnectSyncFolder()`. App already uses `confirmationDialog` / `destructiveConfirmation` elsewhere. |
| **Native alternative** | SwiftUI `confirmationDialog` / `alert` with cancel + destructive roles. **Available since: iOS 15** (`confirmationDialog`). |
| **Why cleaner** | Prevents accidental unlink of the sync folder; matches Clear History / bulk delete patterns in the same app. |

**Shape:** immediate destructive Disconnect at `SettingsView.swift:1166–1168` → `confirmationDialog`, available since **iOS 15**.

---

### F-05 — Mature cover cards use `onTapGesture` where sibling rows use `Button`

| | |
|---|---|
| **Consensus** | **3/3 AGREE** |
| **Hand-rolled** | Blurred cover path uses `.onTapGesture` + manual accessibility; selecting unblurred path already uses real `Button`. |
| **Evidence** | `MatureContent.swift` **289–298** (`.onTapGesture` for select/reveal). Contrast **174–196** / **300–308** (`Button` paths). |
| **Native alternative** | `Button` + `.buttonStyle(.plain)` (same as row wrappers). **Available since: iOS 13** (SwiftUI `Button`). |
| **Why cleaner** | Free button trait / activation; one pattern for privacy wrappers. |

**Shape:** hand-rolled `.onTapGesture` at `MatureContent.swift:289–298` → `Button`, available since **iOS 13**.

---

### F-06 — Background `syncUp` without `beginBackgroundTask`

| | |
|---|---|
| **Consensus** | **3/3 AGREE** |
| **Hand-rolled / missing platform budget** | On `scenePhase` `.inactive` / `.background`, folder sync up is a bare `Task` with no UIApplication background-task assertion. Repo has **no** `beginBackgroundTask` usage. |
| **Evidence** | `ContentView.swift` **126–136** (`case .inactive, .background:` → `Task { await FolderSyncService.syncUp(...) }`). Schedules `FolderSyncBackgroundTask.scheduleNext()` but does not wrap the immediate `syncUp`. |
| **Native alternative** | `UIApplication.beginBackgroundTask(withName:expirationHandler:)` (end in `defer` + cancel on expiration). **Available since: iOS 4** (UIKit). Complementary longer work: BackgroundTasks framework (**iOS 13+**). |
| **Why cleaner** | OS may suspend the process mid-write; an assertion gives a short, documented finish window for the in-flight `syncUp`. |

**Shape:** bare background `syncUp` at `ContentView.swift:126–136` → `beginBackgroundTask`, available since **iOS 4**.

---

### F-07 — Folder sync BG path uses only `BGAppRefreshTask` for package I/O

| | |
|---|---|
| **Consensus** | **2/3 AGREE** (R1, R2; R3 DISAGREE — refresh matches “best-effort freshness” design comments) |
| **Hand-rolled / mismatched task class** | Background entry point is exclusively `BGAppRefreshTask` / `BGAppRefreshTaskRequest`, then runs full `FolderSyncService.syncNow` (security-scoped folder, coordination, package I/O). |
| **Evidence** | `FolderSyncBackgroundTask.swift` **15**, **29–34**, **48–49**, **59–73**. |
| **Native alternative** | `BGProcessingTask` / `BGProcessingTaskRequest` for longer network + disk work; keep refresh for cheap “is dirty?” if desired. **Available since: iOS 13** (BackgroundTasks; both refresh and processing). Requires Info.plist permitted identifier (same mechanism already used). |
| **Why cleaner** | Apple’s split: refresh = short opportunistic; processing = sustained I/O. Full library folder sync is the latter class. |
| **Minority DISAGREE** | R3: current comments frame this as best-effort on top of foreground sync; refresh may be intentional under no-entitlement design. |

**Shape:** hand-rolled use of `BGAppRefreshTask` for full `syncNow` at `FolderSyncBackgroundTask.swift:29–73` → `BGProcessingTask` for heavy sync, available since **iOS 13**.

---

### F-08 — iCloud Drive materialization wait is a sleep-poll loop

| | |
|---|---|
| **Consensus** | **2/3 AGREE** (R1, R2; R3 DISAGREE — poll is simple enough for one-shot importer wait) |
| **Hand-rolled** | After `startDownloadingUbiquitousItem`, loop every **0.3s** reading `.ubiquitousItemDownloadingStatus` until `.current` or **120s** timeout via `Task.sleep`. |
| **Evidence** | `WorkImporter.swift` **162–183** (`waitForUbiquitousDownload`). |
| **Native alternative** | Event-driven ubiquity observation, commonly **`NSMetadataQuery`** (download progress / completion notifications) or a coordinated read that surfaces `Progress`. **`NSMetadataQuery` available since: iOS 5** (and earlier on macOS). `startDownloadingUbiquitousItem` itself: **iOS 5**. |
| **Why cleaner** | Avoids busy polling; can surface real progress; less timing fragility. |
| **Minority DISAGREE** | R3: for a bounded one-shot import, poll is simpler than standing up a query. |

**Shape:** poll loop at `WorkImporter.swift:176–183` → `NSMetadataQuery` (or Progress-backed wait), available since **iOS 5**.

---

### F-09 — Multiple independent `.alert` presenters on one screen

| | |
|---|---|
| **Consensus** | **3/3 AGREE** |
| **Hand-rolled / fragile presentation** | Several `.alert` modifiers on one view hierarchy with independent `isPresented` flags (SwiftUI only reliably presents one). |
| **Evidence** | e.g. `AuthorProfileView.swift` **52**, **57**, **97** (multiple `.alert`). Contrast: Settings already funnels through `alert(item:)` (**~500**, enum-driven). Historical T-152: stacked alerts silently dropped presentations. |
| **Native alternative** | Single `alert(item:)` / `alert(_:isPresented:presenting:actions:message:)` driven by one enum. **Modern `alert` builders: iOS 15+**; `alert(item:)` pattern long-standing in SwiftUI. |
| **Why cleaner** | Predictable presentation; same fix class as Settings backup/import. |

**Shape:** stacked `.alert` at `AuthorProfileView.swift:52–97` → single `alert(item:)` enum, available since **iOS 15** (modern API surface).

---

### F-10 — Comments pagination reinvents a second control (consistency / native-ish chrome)

| | |
|---|---|
| **Consensus** | **2/3 AGREE** (R1, R2; R3 DISAGREE — “not an Apple API, only internal reuse”) |
| **Hand-rolled** | Comments uses a local Prev / “Page x of y” / Next `HStack` instead of the shared `SearchPaginationBar` used by Search, Browse, Account, Inbox. |
| **Evidence** | `CommentsView.swift` **674–707** (`paginationSection`). Shared control: `SearchPaginationBar.swift` (used from Account/Search/Inbox/etc.). |
| **Native / shared alternative** | There is **no** first-class UIKit “page N of M” control. The win is **reuse of the app’s shared bar** (or a single compact prev/next API). Optional quieter style for Comments. Not “Apple API since N” — **consistency finding**. |
| **Why cleaner** | One pagination language, one hit-target/DT story, fewer special cases. |
| **Minority DISAGREE** | R3: internal hygiene, not a native platform API. |

**Shape:** hand-rolled Comments pagination at `CommentsView.swift:674–707` → shared `SearchPaginationBar` (app-native), no separate OS introduction date.

---

## Rejected candidates (≤1/3 AGREE — not documented as findings)

These were proposed by explorers but **failed 2/3 consensus**. Evidence still verified; rejection reasons are product/Readium/design, not “code missing.”

| ID | Topic | Votes | Why rejected |
|---|---|---|---|
| C2 | `EdgeSwipeBack` custom edge pan | 1/3 | Load-bearing: Readium WebKit swallows interactive pop; Search exit is not a stack pop (`EdgeSwipeBack.swift:5–13`) |
| C3 | Floating reader chrome | 0/3 | Intentional Books-style “4a” immersive chrome |
| C4 | Manual safe-area freeze | 0/3 | Page-box geometry must not thrash when status bar hides |
| C5 | Search `exitSearch` tab machine | 1/3 | Search is `Tab(..., role: .search)` with multi-step history, not a push |
| C6 | `GlassFieldBar` vs `.searchable` | 1/3 | Hybrid local/AO3 + filter adjacency; secondary pickers already use `.searchable` (**iOS 15+**) correctly |
| C7 | Custom multi-select bubbles | 1/3 | Deliberate EditMode-free cross-platform select for cards/grids (`LibraryView.swift:50–58`) |
| C9 | Filter multi-select checkmarks | 1/3 | Large searchable option lists; AO3 facets also need non-boolean states |
| C17 | ShakeDetector CoreMotion gate | 1/3 | Intentional anti-false-positive on top of `motionShake` |
| C18 | Permanent WebKit prewarm | 1/3 | Documented cold-start freeze mitigation; no official prewarm API |
| C19 | Window tint walk + segmented appearance | 1/3 | Documented scar tissue for presentation fallbacks / Sepia UIKit chrome |
| C20 | Background `URLSession` for downloads | 1/3 | AO3 politeness + cookies favor paced foreground queue |
| C21 | TTS hold `DragGesture(0)` | 1/3 | Music-like hold-to-seek needs continuous press; not a plain long-press |

---

## API availability reference (checked against platform history / Apple docs)

| API | First available | Notes |
|---|---|---|
| `navigationTransition(.zoom)` / `matchedTransitionSource` | **iOS 18** | Used for work-card → reader zoom |
| SwiftUI `Picker` | **iOS 13** | Continuous refinements later |
| `LAContext.biometryType` | **iOS 11** | Face ID / Touch ID / Optic ID |
| `confirmationDialog` | **iOS 15** | Prefer over destructive-without-confirm |
| SwiftUI `Button` | **iOS 13** | |
| `UIApplication.beginBackgroundTask` | **iOS 4** | Short finish window on backgrounding |
| `BGAppRefreshTask` / `BGProcessingTask` | **iOS 13** | BackgroundTasks framework |
| `NSMetadataQuery` | **iOS 5** | Ubiquity query / download observation |
| Modern `alert` / `alert(item:)` builders | **iOS 15+** | Prefer over stacked `isPresented` alerts |
| `.searchable` | **iOS 15** | Already used on secondary filter pickers |
| `List(selection:)` multi-select | **iOS 13+** (major selection polish **iOS 16**) | Rejected as global multi-select replacement |
| `URLSessionConfiguration.background` | **iOS 7** | Rejected for AO3 paced queue |
| `UIScreenEdgePanGestureRecognizer` | **iOS 7** | What EdgeSwipeBack already uses |

All of the above are available on the app’s **iOS 26.5** deployment floor.

---

## Suggested priority (only consensus findings)

| Priority | Finding | Effort | Risk |
|---|---|---|---|
| P0 | **F-03** Face ID copy honesty | Trivial | None |
| P0 | **F-04** Disconnect confirmation | Small | None |
| P1 | **F-05** Mature cover `Button` | Small | a11y-only upside |
| P1 | **F-09** Unify alerts (`alert(item:)`) | Medium | Presentation races |
| P1 | **F-06** `beginBackgroundTask` on syncUp | Small–medium | Must end task correctly |
| P2 | **F-01** Delete dead peel gesture code | Medium | Keep full-bleed host if still needed |
| P2 | **F-02** Font `Picker` in Settings | Small | Keep custom-font delete UX |
| P2 | **F-07** `BGProcessingTask` for heavy sync | Medium | Info.plist + scheduling policy |
| P2 | **F-08** Event-driven ubiquity wait | Medium | More infrastructure |
| P3 | **F-10** Comments → shared pagination bar | Small | Visual density choice |

---

## Process appendix

### Exploration (phase 1)

| Agent | Area |
|---|---|
| explore | Navigation / gestures / chrome |
| explore | UIComponents |
| explore | Lists / forms / search / selection |
| explore | Reader chrome / TTS / dismiss |
| explore | Settings / onboarding / privacy / a11y |
| explore | Services / App lifecycle / background |

### Review (phase 2)

| Reviewer | Role |
|---|---|
| R1 | Strict evidence vote on C1–C22 |
| R2 | Independent evidence vote (Books chrome → DISAGREE unless cleanup) |
| R3 | Independent evidence vote (native must be *clearly* cleaner for this app) |

### Tallies for documented IDs

| Finding | R1 | R2 | R3 | Result |
|---|---|---|---|---|
| F-01 dead peel | A | A | A | **3/3** |
| F-02 font Picker | A | A | D | **2/3** |
| F-03 Face ID wording | A | A | A | **3/3** |
| F-04 Disconnect confirm | A | A | A | **3/3** |
| F-05 mature cover Button | A | A | A | **3/3** |
| F-06 beginBackgroundTask | A | A | A | **3/3** |
| F-07 BGProcessingTask | A | A | D | **2/3** |
| F-08 ubiquity poll | A | A | D | **2/3** |
| F-09 stacked alerts | A | A | A | **3/3** |
| F-10 Comments pagination | A | A | D | **2/3** |

---

## Out of scope / intentionally not “native replacements”

- AO3 HTML scraping, request pacing, coalescing (`AO3Client`, coordinators)
- MiniZip / hostile-archive validation (no Apple EPUB/ZIP import API that replaces threat model)
- Readium navigator embedding (UIKit-only toolkit)
- Sepia/OLED semantic surfaces (`AppThemeSurface`) — system has no Sepia scheme
- Three-state AO3 include/exclude filter model
- Immersive Books-like reader fan menu / position card (product chrome)

---

*End of report. Re-run exploration if tip moves far past `29cd915`.*
