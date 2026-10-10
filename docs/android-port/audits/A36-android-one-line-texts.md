# A36: Android texts that cannot grow (an index for the largest-text pass)

**Read-only.** Change no source file. Do not build, commit, push or switch branches. Write
exactly one file: `/Users/cidy02/kudos-agent-ios/docs/android-port/audits/A36-result.md`. No
helper scripts left behind.

The Android app is at
`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (read it
there; change nothing). At twice the text size a `Text` held to one line, or a row held to a
fixed height, is cut off. List every place that can happen, so each can be looked at on an
emulator. This is a mechanical index: do not judge, do not fix.

In the packages `account/`, `author/`, `comments/`, `writing/`, `settings/`, `library/`,
`search/`, `browse/`, `home/` and `ui/subject/`, find every:

1. `maxLines = 1` on a `Text` (and `singleLine = true` on a text field),
2. `Modifier.height(<number>.dp)` or `.size(` on a `Row`, `Box` or `Column` that contains a
   `Text` (a fixed height; `heightIn(min = …)` is fine and is not listed),
3. `softWrap = false`,
4. a `Row` holding two or more `Text` with no `weight(` on any of them.

For each, one table row: `path:line`; the string or expression the `Text` shows, quoted (say
"data" when it is a title, a name or another value from AO3 or the reader); what guards it in
the same composable, if anything (`isAccessibilityFontScale()`, `FlowRow`,
`overflow = TextOverflow.Ellipsis`, `weight(1f)`), with its `path:line`; and the composable
function it is in.

Sort by file. Then a short second table: the twenty rows you think most likely to be cut off
at twice the text size (a fixed height, or one line holding data beside other things in a
`Row`, with no guard), each with one line saying why.

Count the rows of each kind at the end. If you run short of time, finish the packages in the
order listed and say where you stopped.
