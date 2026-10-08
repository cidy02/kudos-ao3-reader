# Brief I3 (iOS): text that does not grow with Dynamic Type, Challenges and Writing

Rules (binding): work only in this worktree (`~/kudos-agent-ios`, an iOS worktree); change only
Swift files under `kudos-ao3-reader/Features/Challenges/` and `kudos-ao3-reader/Features/Writing/`;
do not touch `AO3_App_OpenSource.xcodeproj`, `TASKS.md`, tests or anything under `android/`.
Don't commit, push, switch branches or build. No new files. Write
`docs/android-port/audits/I3-result.md` listing every change as `path:line`, old, new.

## The fault

These screens draw some text with a fixed point size, `.font(.system(size: 15, ...))`, so it
does not grow when the reader sets a larger text size in iOS Settings. The app's rule, already
followed in most places, is a scaled size:

```swift
@ScaledMetric(relativeTo: .headline) private var rowTitleSize: CGFloat = 15
...
Text(title).font(.system(size: rowTitleSize, weight: .semibold))
```

See how it was done before: `git show 7160e9a1` (the same change for the challenge and
collection cards), and the existing `@ScaledMetric` declarations in
`Features/Challenges/` and `Features/Writing/`.

## The change, mechanically

For each `.font(.system(size: <number literal>` in a `View` under those two folders:

1. If the text is a **row title, a card title, a body line, a caption or a value a reader
   reads**, replace the literal with a `@ScaledMetric` property on the enclosing `View` struct:
   same number as its default; `relativeTo:` chosen by size (17 and up `.body`, 15 to 16
   `.headline` if the weight is semibold or bold, otherwise `.subheadline`, 13 to 14
   `.footnote`, 12 and under `.caption`). Reuse a property the struct already has for the same
   size and style; name new ones after what they size (`rowTitleSize`, `captionSize`).
2. **Leave alone** and list as left alone: SF Symbol images (`Image(systemName:)` with a font),
   text inside a fixed-size control (a ring, a badge of fixed diameter, a cover), small-caps
   kickers that the design fixes, and anything in a `static` or non-`View` context where a
   `@ScaledMetric` cannot live.
3. Change nothing else: no layout, no weights, no colours, no wording, no line limits. If a
   scaled text would now clip because its container has a fixed height, do **not** fix the
   container: list it under "Needs layout work" with the `path:line`.

About 118 call sites: Challenges 63, Writing 55. Some of Challenges was already done (T-334): leave what already scales.

The result file ends with three lists: changed, left alone (with the reason), needs layout
work. Claude builds, lints, looks at each screen at the largest text size and commits.

## Learned from I1

- I1 found two such containers (a button label in a `.frame(height: 42)`). The rule above
  stands: list them, do not fix them.
- Declare each `@ScaledMetric` in the view struct that uses it (not in an extension, a static
  function or a non-View type): the build is run afterwards and one misplaced property fails it.
- A view struct near SwiftLint's limit (a struct body may span 900 code lines) fails the lint
  with one more property: when two metrics in one struct have the same size and the same
  text style, declare one and use it twice (I2 broke the lint this way in
  `AO3AccountWorksList.swift`).
- The text editor's own text (`WritingNativeTextView`, a UIKit view) is not SwiftUI: leave it.
