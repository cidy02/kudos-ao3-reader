# A47: iOS controls a VoiceOver reader cannot name

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A47-result.md`. **Leave no other file behind.**

iOS, and **not the copy in this worktree**: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`
(read-only).

A control is unnamed for VoiceOver when it can be tapped and has neither text nor a spoken
label. List every one. Rules, strict, because a row without its quote cannot be used:

1. Search every `.swift` file under `Features/` and `UIComponents/` for each of: `Button {`,
   `Button(action:`, `Button(role:`, `.onTapGesture`, `NavigationLink {`, `NavigationLink(value:`,
   `Menu {`, `ToolbarCircleButton(`.
2. For each match, look at its label (for a `Button { } label: { }`, the `label:` closure; for
   `.onTapGesture`, the view it is attached to) up to the closing brace. It is **named** if any
   of these is true (quote the line that makes it so): the label contains a `Text(` or a
   `Label(` with a non-empty string, or a string passed as the title (`Button("Save")`); the
   control or its label has `.accessibilityLabel(`; it has `.accessibilityElement(children: .combine)`
   over a view that contains text; it is `.accessibilityHidden(true)` (then it is not a control
   for VoiceOver at all: leave it out).
3. Report **only the ones that are not named**: `path:line` of the match, the four lines
   starting there quoted exactly, and what it shows (the `Image(systemName:` inside, quoted).
4. A match inside a `#Preview` or `#if DEBUG` block: leave it out.
5. Do not judge severity. Do not suggest labels.

Start the file with three numbers: matches examined, named, not named. Say for each of the eight
search strings in rule 1 how many matches it had. Then the table of the not-named ones, grouped
by file. If you run out of time, say which directories you did not reach.
