# I15 result (iOS): the source URL without a hyphen

*Done.* Branch `claude/agent-ios-i15` from polish `bd533264` (T-439). Nothing committed. One new file and one changed file under `kudos-ao3-reader/`.

## The change

- **New: `UIComponents/URLTextField.swift`** (iOS only). A field for a web address: a `UITextView` whose paragraph style has hyphenation off (`hyphenationFactor = 0`, `usesDefaultHyphenation = false`). A long word such as "archiveofourown.org" still breaks where it must, now without an added hyphen.
  - The project's synchronized source folder picks the file up, so there's no `project.pbxproj` change.
- **The parent work's URL row** uses it on iOS (`Features/Writing/WorkAssociationPickers.swift:696`).
  - macOS keeps the SwiftUI `TextField` exactly as it was before T-439 (`:697-709`). The bar and the shot were iOS's.
  - I14's ineffective `typesettingLanguage("zxx")` line is removed.

## What it keeps from the field it replaces (T-435 / I10)

- **Line breaks dropped:** a typed or pasted line break is never inserted. A paste keeps its other text.
- **Return ends editing:** any line break, typed or pasted, ends editing (`textView(_:shouldChangeTextIn:replacementText:)`), as the old setter's `urlFocused = false` did.
- **1–4 lines:** the field grows a line at a time up to four, then scrolls (`sizeThatFits`). One line when empty.
- **Keyboard and input:** the URL keyboard, no autocapitalisation, no autocorrection, and no smart quotes or dashes.
- **Alignment:** trailing, as `.multilineTextAlignment(.trailing)` (left in a right-to-left layout).
- **Text:** the body text style with Dynamic Type (`adjustsFontForContentSizeCategory`), in the label colour.
- **Placeholder:** "https://archiveofourown.org/works/…" in the system placeholder colour, drawn over the field while it's empty and hidden from VoiceOver.
- **VoiceOver:** reads the field as "URL".
- **The value:** the binding is `parentWork.url` itself. The old setter's newline filter now happens before any newline can reach the text.

## Build and lint

- **iOS:** arm64 simulator, `…/kudos-agent-ios-ios`, BUILD SUCCEEDED. **macOS:** `…/kudos-agent-ios-mac`, BUILD SUCCEEDED.
- **Warnings:** none in either file.
- **SwiftLint:** clean on both files, as at HEAD.
- **Not run:** tests, the simulator. The check is the `parentpicker` re-shoot at AX5, plus a typing pass: type a URL past one line, paste text with a line break, press Return, and grow past four lines.
