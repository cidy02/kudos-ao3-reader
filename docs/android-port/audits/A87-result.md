# Audit A87 — Adversarial Review of iPhone Batch T-433 / T-434

## Confirmed Findings

### 1. [P2] Accessibility / Behaviour — Bookmark composer toggles lose label hit-testing at accessibility text sizes
- **Location:** `kudos-ao3-reader/Features/WorkDetail/AO3WorkActionsModel.swift:250-259` (called at `:221-222`)
- **Quoted lines:**
  ```swift
  // Features/WorkDetail/AO3WorkActionsModel.swift:221-222
  toggle("Private", isOn: $isPrivate)
  toggle("Recommend", isOn: $isRec)
  ```
  ```swift
  // Features/WorkDetail/AO3WorkActionsModel.swift:250-259
  @ViewBuilder
  private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
      if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 8) {
              Text(title).accessibilityHidden(true)
              Toggle(title, isOn: isOn).labelsHidden().accentFill()
          }
      } else {
          Toggle(title, isOn: isOn).accentFill()
      }
  }
  ```
- **Failing case:** At accessibility Dynamic Type sizes (`AX1`–`AX5`) in `AO3BookmarkSheet`, the visible `"Private"` and `"Recommend"` labels are rendered as standalone `Text(title)` views outside the `Toggle`, while `.labelsHidden()` strips each `Toggle` down to its bare switch control. Tapping the large `"Private"` or `"Recommend"` text (or anywhere in the row outside the switch thumb) does nothing. On macOS, if `dynamicTypeSize.isAccessibilitySize` is active, `.labelsHidden()` also strips the checkbox title while leaving an inert text label above an unlabeled checkbox.

---

### 2. [P2] Behaviour — `CommentsModel.loadFocusedThread` publishes `.loaded` before `page` is set, shows stale-cache notice on a freshly fetched focused thread, and leaks cache flags if reply validation throws
- **Location:** `kudos-ao3-reader/Features/Comments/CommentsModel.swift:441-492`, `:504-508` (with `fetchPage` at `:884-893`)
- **Quoted lines:**
  ```swift
  // Features/Comments/CommentsModel.swift:441, 457-492, 504-508
  var chapterPageWasKept = false
  if pendingInitialFocusesChapter {
      let focusedCount = Self.commentCount(in: focusedPage.comments)
      guard isCurrent(expected, auth) else { return }
      guard let chapterPage = await fetchPage(
          1, auth: auth, forceRefresh: false, expected: expected
      ) else { return }
      guard isCurrent(expected, auth) else { return }
      chapterPageWasKept = isKeptAfterFailure
      presentedPage = Self.chapterPage(
          chapterPage, including: focusedPage, focusedRootID: rootID
      )
      isShowingFocusedThread = true
      focusedThreadShowsFullChapter = true
      focusedCommentCount = focusedCount
  } else {
      ...
  }
  await enrichWorkContextIfNeeded(presentedPage, auth: auth, expected: expected)
  guard isCurrent(expected, auth) else { return }
  if let replyID = pendingInitialReplyCommentID,
     !presentedPage.comments.contains(where: { $0.contains(commentID: replyID) }) {
      throw AO3Error.parse
  }
  page = presentedPage
  ...
  if !chapterPageWasKept {
      isOffline = false
      isFromCache = false
      isKeptAfterFailure = false
  }
  return
  } catch is CancellationError {
      return
  } catch {
      guard isCurrent(expected, auth) else { return }
      isOffline = false
      phase = .failed(Self.userMessage(for: error))
  }
  ```
  ```swift
  // Features/Comments/CommentsModel.swift:884-893 (inside fetchPage)
  if let cached = cache.entry(
      scope: scope, page: requestedPage, authScope: authScope, allowExpired: true
  ) {
      isOffline = Self.isConnectivityFailure(error)
      isFromCache = true
      isKeptAfterFailure = true
      cachedFetchedAt = cached.fetchedAt
      phase = .loaded
      return cached.value
  }
  ```
- **Failing cases:**
  1. **Premature `phase = .loaded` while `page` is still `nil`:** When `pendingInitialFocusesChapter` is `true` and `fetchPage(1, ...)` falls back to a cached chapter page (`:884-893`), `fetchPage` immediately sets `phase = .loaded` and `isKeptAfterFailure = true` before `loadFocusedThread` runs `await enrichWorkContextIfNeeded(...)` (`:474`) and before `page = presentedPage` (`:481`). While `enrichWorkContextIfNeeded` awaits network I/O (`fetchWorkContext`), `CommentsView` (`:730-742`) observes `phase == .loaded` with `model.page == nil` and `displayThreads.isEmpty`, rendering the `keptCopyNotice` banner above `"No Comments Yet"`.
  2. **Kept-copy banner misdescribes the freshly fetched focused thread:** `loadFocusedThread` only calls `fetchPage(1, ...)` after `fetchStandaloneThread` (`:435`) has just fetched `focusedPage` live from AO3. When `fetchPage(1, ...)` falls back to an expired cache entry, `Self.chapterPage(chapterPage, including: focusedPage, focusedRootID: rootID)` splices the live `focusedPage` root thread into index 0, but keeping `isKeptAfterFailure = true` causes `CommentsView.keptCopyNotice` (`:791-815`) to state that the comments are from `cachedFetchedAt` because the user is offline / AO3 could not be reached.
  3. **Cache flags not cleared on post-`fetchPage` throw:** If `fetchPage(1, ...)` sets `isFromCache = true` and `isKeptAfterFailure = true` (`:888-889`), and lines `478-480` then throw `AO3Error.parse` because `pendingInitialReplyCommentID` is not found in `presentedPage.comments`, the `catch` block (`:504-508`) only resets `isOffline = false` and leaves `isFromCache = true`, `isKeptAfterFailure = true`, and `cachedFetchedAt` dirty on the model.

---

### 3. [P2] Behaviour — `WorkParentWorkPickerView` vertical URL `TextField` breaks Return-to-dismiss and only strips `\n` (not `\r`)
- **Location:** `kudos-ao3-reader/Features/Writing/WorkAssociationPickers.swift:688-695`
- **Quoted lines:**
  ```swift
  // Features/Writing/WorkAssociationPickers.swift:688-695
  TextField("https://archiveofourown.org/works/…", text: Binding(
      get: { parentWork.url },
      set: { parentWork.url = $0.replacingOccurrences(of: "\n", with: "") }
  ), axis: .vertical)
  #if os(iOS)
      .keyboardType(.URL)
      .textInputAutocapitalization(.never)
  #endif
      .autocorrectionDisabled()
  ```
- **Failing cases:**
  1. **Return key no longer dismisses the keyboard:** On iOS, adding `axis: .vertical` switches `TextField` from a single-line control to a multiline text view. Tapping Return on the keyboard now inserts `\n` (which the binding setter silently strips) instead of ending editing / dismissing the keyboard, leaving the user stuck in the field when pressing Return.
  2. **Carriage returns (`\r`) are not stripped:** Pasting a URL copied with `\r\n` or `\r` line breaks strips `\n` via `.replacingOccurrences(of: "\n", with: "")` but leaves `\r` inside `parentWork.url`, whereas the previous single-line `TextField` rejected all line-break characters.

---

### 4. [P3] macOS — Unconditional `.navigationTitle("")` removes the macOS navigation title on Co-creators and Inspired by
- **Location:** `kudos-ao3-reader/Features/Writing/WorkAssociationPickers.swift:565` and `:679`
- **Quoted lines:**
  ```swift
  // Features/Writing/WorkAssociationPickers.swift:563-566 (WorkCocreatorsEditorView)
  // Blank, as WritingTagsEditor's: the header block names the page, and a title
  // set before the wash outranks its blank one, so the bar named it a second time.
  .navigationTitle("")
  .subjectScreenWash(palette: palette)
  ```
  ```swift
  // Features/Writing/WorkAssociationPickers.swift:678-680 (WorkParentWorkPickerView)
  // Blank, as above: the header block already says "Inspired by".
  .navigationTitle("")
  .subjectScreenWash(palette: palette)
  ```
- **Failing case:** In `UIComponents/SubjectScreen.swift:131-139`, `.subjectScreenWash` already blanks the navigation title on iOS via `hidesNavigationBarChrome()`, which is `#if os(iOS)`-guarded so macOS retains its window/split-view toolbar title. Unlike the other two views in the same file (`WorkCollectionsAndGiftsView` at `WorkAssociationPickers.swift:94-97` and `WorkSeriesPickerView` at `:424-427`), which place `#if os(macOS) .navigationTitle("...") #endif` *after* `.subjectScreenWash(palette: palette)`, replacing `.navigationTitle("Co-creators")` and `.navigationTitle("Inspired by")` with an unconditional `.navigationTitle("")` blanks the macOS navigation title when a macOS user opens either screen.

---

### 5. [P3] Accessibility / macOS — `.labelsHidden()` on `RevokeDeviceSheet`'s inline `Picker` removes its VoiceOver control label
- **Location:** `kudos-ao3-reader/Settings/PairingSheet.swift:229-238`
- **Quoted lines:**
  ```swift
  // Settings/PairingSheet.swift:229-238
  Section("Why are you removing this device?") {
      // Hidden label: the section already asks, and an inline picker
      // drew "Reason" as a row of its own inside the card.
      Picker("Reason", selection: $reason) {
          Text("Stolen or compromised").tag(TombstoneRevokeReason.stolenOrCompromised)
          Text("Retired or sold").tag(TombstoneRevokeReason.retiredOrSold)
      }
      .pickerStyle(.inline)
      .labelsHidden()
  }
  ```
- **Failing case:** Adding `.labelsHidden()` without `.accessibilityLabel("Reason")` (or `"Why are you removing this device?"`) strips the picker's label for VoiceOver users navigating by form controls, and on macOS (where `RevokeDeviceSheet`'s `Form` does not set `.formStyle(.grouped)` and `.pickerStyle(.inline)` renders a radio group) leaves the radio group unlabeled.

---

## Unconfirmed

### U1. Theming — `BackupImportSheet` step 2 (`ReplaceLibraryConfirmationView`) remains unthemed in Sepia
- **Location:** `kudos-ao3-reader/Settings/BackupImportSheet.swift:32-39` and `:54-60` (presenting `ReplaceLibraryConfirmationView` from `kudos-ao3-reader/Settings/SettingsView.swift:445-507`)
- **Quoted lines:**
  ```swift
  // Settings/BackupImportSheet.swift:32-39
  Group {
      if let preview = replacePreview {
          ReplaceLibraryConfirmationView(preview: preview) {
              await runImport(mode: .replaceAll)
          }
      } else {
          chooseStep
      }
  }
  ```
  ```swift
  // Settings/BackupImportSheet.swift:54-60
  private var chooseStep: some View {
      Form {
          Group {
              ...
          }
          .appThemedRows()
      }
      .formStyle(.grouped)
      .appThemedScroll()
  }
  ```
- **What would confirm it:** In Sepia theme, open `BackupImportSheet` (which is now themed on `chooseStep`) and tap `"Replace Entire Library"` to transition to `ReplaceLibraryConfirmationView`: `ReplaceLibraryConfirmationView`'s `Form` (`SettingsView.swift:445`) has neither `.appThemedScroll()` nor `.appThemedRows()`, so the sheet reverts to system light grouped surfaces on its confirmation step.

---

P1: 0 / P2: 3 / P3: 2 / unconfirmed: 1

---

## Triage (Claude, 2026-10-23)

Gemini 4 Argon (account 2) on the iPhone batch T-433/T-434 before it was committed (it landed as
polish `315ef41a`, `7a905485` while this ran; the fixes below are T-435). Each finding was checked
in the code. **Finding 2's quote is partly invented** (`isShowingFocusedThread`,
`focusedThreadShowsFullChapter`, `focusedCount` and `allowExpired:` are not in `CommentsModel.swift`).

| Finding | Verdict | Fix |
|---|---|---|
| 1 P2 bookmark toggles at AX sizes: the label above no longer toggles | **Not a fault.** In an iOS form only the switch toggles; tapping a Toggle's label never did. `labelsHidden()` keeps the label for VoiceOver (Apple: "the label is still used for accessibility"), and macOS has no accessibility text sizes | — |
| 2 P2 focused thread: `.loaded` before the page, the kept notice, flags after a throw | **First part real, P3, older than T-433:** a kept or cached chapter page sets `phase = .loaded` inside `fetchPage`, and the thread is only published after the work-details request, so "No Comments Yet" could show for that long. Second part is the intended A83 fix (the page is mostly the kept copy). Third: flags stay set only on the failure screen, which does not show them; a later load clears them | The spinner stays until the page is set (`if page == nil { phase = .loading }`) |
| 3 P2 URL field: Return no longer ends editing; `\r` survives | **Real, P3** (I10 made the field vertical) | Every line break dropped (`isNewline`); a typed or pasted line break ends editing (`@FocusState`) |
| 4 P3 macOS: Co-creators and Inspired by lost their title | **Real** | No iOS title; a macOS-only title after the wash, as the file's other two pickers do |
| 5 P3 revoke reason picker's label hidden from VoiceOver | **Not a fault:** `labelsHidden()` keeps the accessibility label | — |
| U1 Replace Library's confirmation white under Sepia | **Real, P3, older than T-434** (the import sheet before it is themed since I9) | `.appThemedScroll()` on its Form, `.appThemedRows()` on a `Group` of its sections |
