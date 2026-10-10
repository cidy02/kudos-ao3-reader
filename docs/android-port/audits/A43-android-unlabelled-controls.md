# A43: Android controls a TalkBack reader cannot name

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A43-result.md`. **Leave no other file behind.**

Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
(read-only).

A control is unnamed for TalkBack when it can be tapped and has neither text nor a spoken label.
List every one. Rules, strict, because a row without its quote cannot be used:

1. Search every `.kt` file under that directory for each of: `IconButton(`, `ToolbarCircleButton(`,
   `.clickable(`, `.clickable {`, `.combinedClickable(`, `.toggleable(`, `.selectable(`,
   `FloatingActionButton(`.
2. For each match, look at what it contains or is attached to, up to its closing brace. It is
   **named** if any of these is true (quote the line that makes it so): it contains a `Text(`
   with a non-empty string; it or something inside it has `contentDescription = ` followed by
   anything other than `null`; it has `accessibilityName = `; it has
   `.semantics { contentDescription = ... }`, `spokenAs(`, `spokenFormLabel(`, `onClickLabel = `,
   or `clearAndSetSemantics {` with a description inside.
3. Report **only the ones that are not named**: `path:line` of the match, the three lines
   starting there quoted exactly, and what it shows (the `Icon(` or `Image(` inside, quoted).
   If its only content is an `Icon(..., contentDescription = null)`, say so.
4. A `.clickable` on a whole row that contains text is named: leave it out. A match inside a
   `@Preview` function or a file under a `debug` or `preview` directory: leave it out.
5. Do not judge severity. Do not suggest labels.

Start the file with three numbers: matches examined, named, not named. Then the table of the
not-named ones, grouped by file. If you run out of time, say which files you did not reach.
