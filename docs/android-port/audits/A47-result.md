# A47: iOS Controls a VoiceOver Reader Cannot Name

## Summary Numbers

- **Matches examined**: 569
- **Named**: 564 (563 excluding the macOS-only reader button under `#if os(macOS)`)
- **Not named**: 5 (6 including the macOS-only reader button under `#if os(macOS)`)

All 268 `.swift` files across all directories under `Features/` and `UIComponents/` in `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` were fully reached and examined. None were skipped.

---

## Matches per Search String (Rule 1)

| Search String | Matches Examined |
|---|---|
| `Button {` | 345 |
| `Button(action:` | 71 |
| `Button(role:` | 43 |
| `.onTapGesture` | 9 |
| `NavigationLink {` | 11 |
| `NavigationLink(value:` | 38 |
| `Menu {` | 52 |
| `ToolbarCircleButton(` | 0 |
| **Total** | **569** |

### Context on Examined Matches

- **Comments (4)**: 4 occurrences occurred inside comments (`NavigationLink {` in `Features/Comments/CommentsView.swift:8`, `NavigationLink(value:` in `Features/Library/ReadingQueues.swift:174`, `.onTapGesture` in `Features/Privacy/MatureContent.swift:183`, `Menu {` in `Features/Writing/WritingFormFields.swift:3`).
- **Identifier Substrings (2)**: 1 occurrence was a boolean expression (`showsExpandButton {` in `Features/Library/WorkRow.swift:214`), and 1 was a type extension (`extension ReaderFanMenu {` in `Features/ReaderReadium/ReaderFanMenu.swift:362`).
- **`#Preview` / `#if DEBUG` Blocks (0)**: None of the matches appeared inside `#Preview` or `#if DEBUG` blocks.
- **Accessibility-Hidden Controls**: Controls with `.accessibilityHidden(true)` (e.g., `ReaderFanMenu.swift:377`, `MinimumHitTarget.swift:48`) are omitted from the not-named report per Rule 2.

---

## Not-Named Controls (Grouped by File)

### `kudos-ao3-reader/Features/Browse/BrowseView.swift`

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Browse/BrowseView.swift:102` | <pre>            Button {<br>                model.reload()<br>            } label: {<br>                Image(systemName: "arrow.clockwise").font(.caption)</pre> | `Image(systemName: "arrow.clockwise")` |

---

### `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift`

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:597` | <pre>            Button {<br>                actionErrorMessage = nil<br>            } label: {<br>                Image(systemName: "xmark")</pre> | `Image(systemName: "xmark")` |

---

### `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift`

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift:734` | <pre>            Button {<br>                actionErrorMessage = nil<br>            } label: {<br>                Image(systemName: "xmark")</pre> | `Image(systemName: "xmark")` |

---

### `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift`

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:501` | <pre>            Button {<br>                actionErrorMessage = nil<br>            } label: {<br>                Image(systemName: "xmark")</pre> | `Image(systemName: "xmark")` |

---

### `kudos-ao3-reader/Features/Search/SearchView.swift`

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Search/SearchView.swift:605` | <pre>                Button(action: clearQuery) {<br>                    Image(systemName: "xmark.circle.fill").font(.caption)<br>                }<br>                .buttonStyle(.plain)</pre> | `Image(systemName: "xmark.circle.fill")` |

---

### `kudos-ao3-reader/Features/Reader/ReaderView.swift` (macOS-only legacy reader)

*Note: `ReaderView.swift` is guarded by `#if os(macOS)` and excluded from iOS builds.*

| `path:line` | Four lines starting at match | What it shows |
|---|---|---|
| `kudos-ao3-reader/Features/Reader/ReaderView.swift:319` | <pre>        Button(action: action) {<br>            Image(systemName: systemName)<br>                .font(.body.weight(.medium))<br>                .frame(width: 44, height: 44)</pre> | `Image(systemName: systemName)` |

## Triage (Claude, 2026-10-10)

569 controls examined, six unnamed (one of them macOS only). All six read in the Swift and
labelled as iOS **T-380** (polish and integrate, pushed): "Reload", "Dismiss error" (three),
"Clear search", and "Previous" / "Next" on the macOS reader. Not heard with VoiceOver. The count
of the other 563 as named was not checked.

