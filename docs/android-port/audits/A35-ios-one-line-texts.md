# A35: iOS texts that cannot grow (an index for the largest-text pass)

**Read-only.** Change no source file. Do not build, commit, push or switch branches. Write
exactly one file, in this worktree: `docs/android-port/audits/A35-result.md`. No helper
scripts left behind.

The app is in `kudos-ao3-reader/`. At the largest accessibility text size a `Text` held to one
line, or a row held to a fixed height, is cut off. List every place that can happen, so each
can be looked at on a simulator. This is a mechanical index: do not judge, do not fix.

Under `kudos-ao3-reader/Features/` and `kudos-ao3-reader/UIComponents/`, find every:

1. `.lineLimit(1)` (and `lineLimit(1...1)`),
2. `.frame(height: <number>)` and `.frame(minHeight:maxHeight:)` with a fixed maximum, on a
   view that contains a `Text`,
3. `.fixedSize()` on a `Text` inside an `HStack`,
4. `.minimumScaleFactor(` (these are already guarded: list them separately).

For each, one table row: `path:line`; the string or the expression the `Text` shows, quoted
(say "data" when it is a title, a name or another value from AO3 or the reader); what guards
it within the same view, if anything (`ViewThatFits`, `dynamicTypeSize.isAccessibilitySize`,
`@ScaledMetric`, `minimumScaleFactor`, `.truncationMode`), with its `path:line`; and the
screen it belongs to (the enclosing `struct`).

Sort by file. Then a short second table: the twenty rows you think most likely to be cut off
at the largest size (a fixed height, or one line holding data beside other things in an
`HStack`, with no guard), each with one line saying why.

Count the rows of each kind at the end. If you run short of time, finish `Features/` in
alphabetical order and say where you stopped.
