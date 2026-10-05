# Brief 3aq: three screens at the largest text size

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference for what happens at accessibility text sizes: read it at
`/Users/cidy02/kudos-ios-polish/` (search for `dynamicTypeSize.isAccessibilitySize` and
`ViewThatFits` in the matching iOS files), change nothing there. Write
`docs/android-port/briefs/3aq-result.md` as you go.

## What is wrong

At the system's largest text size (font scale 2.0) three screens cut or crowd their text. The
shared components were done in an earlier brief (4a: read `briefs/4a-result.md` if it exists,
and `isAccessibilityFontScale()` in `ui/subject/SubjectComponents.kt`, which is Android's
`isAccessibilitySize`: above 1.3). These three were left:

1. **The Inbox rows** (`account/AccountInboxPane.kt`): the commenter's name, their badge, the
   status chip and the date share one line.
2. **The AO3 collection cards** on the Collections list (`account/` , the list at
   `Routes.AO3Collections`): the kicker, the two state chips and the title share the card's
   head; the stats line runs long.
3. **The local collection covers** (`library/CollectionsScreen.kt`): a cover's four tiles hold
   a title and an author each in a fixed square.

## Build

For each, do what iOS does at accessibility sizes (it stacks a row that no longer fits, lets a
title wrap, and drops nothing): read the matching iOS view first and say what it does. On
Android that is the same pattern the done screens use: branch on `isAccessibilityFontScale()`
to stack what was side by side; let text wrap with a line height; never shrink text, never
ellipsize a title that iOS wraps, never give a fixed height to something that holds text. At
ordinary sizes nothing may change: the layout at scale 1.0 must be what it is today.

Tokens only, no literal colours; the page's existing components only (pills are `SubjectChip`):
no stock Material chips or default Material colours.

## Tests

For each screen a Compose test at font scale 2.0 in a 411dp-wide window (Robolectric
qualifiers) that the texts named above are all displayed and that none is clipped by its
parent (compare each text node's bounds with its parent's), and one at scale 1.0 pinning
today's arrangement (the row is still a row). The pages are lazy lists: give the test window
the height it needs.
