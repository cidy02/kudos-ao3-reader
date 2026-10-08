# Audit A13: Android controls a screen reader cannot name

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A13-result.md`.

This is a mechanical check, and its value is exactness. Report only what you found by
searching and then reading the lines around each hit; never infer, never describe a file you
did not open, never invent a line number.

## The check

In every Kotlin file under `android/app/src/main/java/io/github/cidy02/kudos/` find each
control a reader can tap that TalkBack would announce with no name:

1. An `Icon(` or `Image(` with `contentDescription = null` that is the **only** content of
   something tappable: an `IconButton`, a `ToolbarCircleButton`, a `Box`/`Row`/`Surface` with
   `.clickable`, `.combinedClickable`, `.toggleable` or `.selectable`, when neither that
   container nor a parent merges in a text or sets
   `semantics { contentDescription = … }` / `clearAndSetSemantics`.
2. A `.clickable` container whose content is only colour or shape (a swatch, a dot, a
   handle, a cover image) with no `contentDescription` and no text.
3. A custom switch, checkbox, radio row or slider with no `role`, no `stateDescription` and
   no `toggleable`/`selectable` (so its state is not announced).
4. An `IconButton` whose `Icon` has a `contentDescription` that is the icon's name or an
   empty string rather than what the button does.

Not findings: an icon beside a visible text inside the same clickable row (the text names
it); a decorative icon in a row that is not tappable by itself; anything under a `@Preview`;
debug-only screens (files or routes with "Demo" or "Debug" in the name).

## The result file

1. Counts: files read, hits examined, findings by kind (1 to 4).
2. A table, grouped by file, most-used screens first (reader, Library, Home, Work Detail,
   Search, Browse, Account, then the rest): `path:line` (open the file and copy the real
   line), the kind, the code of the control in one line, what it does (read the `onClick`),
   and the label you would give it (if iOS has the same control, its label: search
   `kudos-ao3-reader/` for the matching `accessibilityLabel` and quote it with its
   `path:line`; otherwise say "no iOS counterpart found").
3. What you did not read.
