# Brief I1 (iOS): text that does not grow with Dynamic Type, Library and Work Detail

Rules (binding): work only in this worktree (`~/kudos-agent-ios`, an iOS worktree); change only
Swift files under `kudos-ao3-reader/Features/Library/` and `kudos-ao3-reader/Features/WorkDetail/`;
do not touch `AO3_App_OpenSource.xcodeproj`, `TASKS.md`, tests or anything under `android/`.
Don't commit, push, switch branches or build. No new files. Write
`docs/android-port/audits/I1-result.md` listing every change as `path:line`, old, new.

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
`Features/Library/` and `Features/WorkDetail/`.

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

Files with the most cases (count of fixed sizes): `Features/Library/FavoriteAffinityRow.swift`
15, `ReadingInsightsView.swift` 13, `Features/WorkDetail/WorkDetailSections.swift` 14,
`QueueTagManagerView.swift` 7, `LibraryFilterEmptyState.swift` 7, `QueueTagSheet.swift` 6,
`NewCollectionSheet.swift` 5, `CollectionLedgerRow.swift` 5, `WorkDetailFactsSections.swift` 5.
Do every file in the two folders, not only these.

The result file ends with three lists: changed, left alone (with the reason), needs layout
work. Claude builds, lints, looks at each screen at the largest text size and commits.
