# Audit A87 (read-only): adversarial review of the iPhone batch T-433/T-434

**Read only. Do not edit any file except the result file. Do not build, do not run git or shell
commands that change anything, do not sign in, do not contact archiveofourown.org.**

Write your result to `/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A87-result.md`
(create it first, then fill it as you go).

## What to review

The diff is saved at `/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A87-ios-diff.patch`
(41 Swift files, uncommitted in `/Users/cidy02/kudos-ios-polish`; read the full files there too).
It is two batches:
- T-434 (another Claude session's I9, I9b, I10): Sepia theming (`.appThemedScroll()`,
  `.appThemedRows()` moved from a List/Form to its sections or a `Group`), layouts at the largest
  text sizes (`wrappingInlineTitle(_:isActive:)` in `UIComponents/SubjectScreen.swift`, `AnyLayout`
  reflows, line limits lifted at accessibility sizes), navigation titles set before
  `.subjectScreenWash`, and small fixes. Its notes: `/Users/cidy02/kudos-android-lane/docs/android-port/briefs/I9-result.md`
  and `I10-result.md`.
- T-433 (Claude): `Features/Comments/CommentsModel.swift` (`chapterPageWasKept`),
  `Features/Writing/WritingTextEditor.swift` ("Copy text"), `Features/ReaderReadium/ReadiumReaderView.swift`
  and `App/DemoLibrary.swift` (DEBUG routes), `Features/Authors/AuthorProfileView.swift`.

Look for real faults only, each with `file:line`, a severity (P1 data loss or crash, P2 wrong
behaviour a user meets, P3 minor) and a concrete failing case:
1. **macOS:** the app also builds for macOS. Anything iOS-only used outside `#if os(iOS)`, or a
   macOS layout the change breaks (for example a toolbar placement or `navigationBarTitleDisplayMode`).
2. **Accessibility:** a VoiceOver label lost (for example a picker whose label is hidden), a
   title VoiceOver no longer reads, a button with no name (the editor's Done turned into a
   checkmark at accessibility sizes must still say "Done").
3. **Theming:** a modifier placed where it does nothing (`.appThemedRows()` only reaches rows
   from a row, a ForEach, a Section or a `Group` inside a List), or Light changed when it should
   not be.
4. **Behaviour:** anything a change alters beyond its layout (bindings, what a button does, the
   URL field dropping newlines, the select-mode titles, the kept-copy notice's state).
5. **DEBUG-only code** that could run in a release build.

Quote the lines for every finding. If unsure, put it under "Unconfirmed" with what would confirm
it. End with one line: P1 / P2 / P3 / unconfirmed counts.
