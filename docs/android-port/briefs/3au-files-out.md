# Brief 3au: sharing a work's file, and opening an imported original

**Corrected 2026-10-05 (Claude), after Codex read iOS:** iOS's work page shares only a link and
has no way to view an original; only the reader has the file fallback and the Original icon. So
on Android the work page is left as it is and both additions are the reader's only. Where the
text below says "the work page's Share" or "offer it on the work page too", iOS's code wins.

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; if a question
remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3au-result.md` as you go.

## What is missing

You listed these in `briefs/3ao-result.md` ("Capabilities deliberately omitted"):

1. **Share for a work with no link.** iOS's reader Share (and the work page's) falls back to
   the readable EPUB file when there is no AO3 or source address. Android shows no Share at
   all for such an import (it used to share only the title).
2. **Original.** iOS's reader menu has an icon that opens the file an import was converted
   from (Quick Look, `previewingOriginal`), shown only when an archived original exists
   (`WorkReconversion.candidate`). Android keeps the original (`WorkFileStore.originalFile`)
   and offers no way to look at it.

## Build

- One small, shared way for a file of the app's to leave it for reading: a content address
  from a `FileProvider` with a read grant for the receiving app only, the right MIME type, and
  a display name that is the work's title and the file's real extension. The manifest already
  declares a provider for installing an APK: read it and its paths file, and extend the paths
  it serves as narrowly as possible (the EPUB folder and the originals folder, nothing else:
  not the database, not settings, not the cookie store). Say exactly which directories become
  reachable and prove in a test that a path outside them cannot be turned into an address.
- **Share**: when a work has no link, the reader's Share and the work page's Share send the
  EPUB through the system's share sheet (`ACTION_SEND`, the content address, the grant flag).
  With a link, nothing changes: the link is shared as today. Follow iOS's order of preference
  exactly (`shareURL` in `ReadiumReaderView.swift`).
- **Original**: the reader's menu gains iOS's Original icon under iOS's condition, in iOS's
  place in the round row (the pills' width already follows the number of round buttons), and
  opens the original with `ACTION_VIEW` and the same kind of address. If no app can open that
  type, say so in iOS's words if iOS has any, otherwise plainly. Offer it on the work page too
  if iOS does there.
- Nothing is copied to public storage, nothing is left behind after the share, and no file is
  ever served for a work in Recently Deleted unless iOS does so.
- A Mature or hidden work: follow what iOS does about sharing one; say what you found.

## Tests

The address builder (inside and outside the allowed folders, a missing file, a name with
unusual characters); Share's choice between link and file for each kind of work; the Original
icon's condition; the intents built (action, type, grant flag, stream), with a recording
launcher and no real activity. No network.

Say what needs a device: that another app can in fact read the address, and what the share
sheet and the viewer show.
