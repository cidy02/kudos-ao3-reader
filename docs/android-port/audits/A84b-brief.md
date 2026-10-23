# Audit A84b: the second 35 of the 70 newly shot screens, compared in code (read only)

**Write nothing but `docs/android-port/audits/A84b-result.md` in `/Users/cidy02/kudos-agent-opus`
(create it FIRST and add to it as you go). Do not edit code, commit, push, switch branches, sign
in, run Gradle or xcodebuild, or contact archiveofourown.org.**

Read the current code, not your worktree's older copy:
- iOS: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (SwiftUI)
- Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (Compose)

`docs/android-port/audits/A82-shots.md` (in this worktree) lists 70 screens, each with its iOS view
and Android composable. **This run covers only these 35:** `inboxfilter`, `authorabout`, `seriesdetail`, `seriesedit`, `seriesreorder`, `seriesremove`, `authorworksfilter`, `colitems`, `colsfilter`, `chsettingsedit`, `chsignupdetail`, `prompttags`, `tagset`, `tagseteditor`, `writingpreview`, `chapters`, `chapterform`, `edittags`, `tagseditor`, `texteditor`, `recovery`, `seriespicker`, `collectionsgifts`, `creatorspicker`, `parentpicker`, `bulkedit`, `bulktagstate`, `bulknames`, `prefhelp`, `privacydata`, `availability`, `pairing`, `revokedevice`, `backupimport`, `aboutkudos`. Gemini is comparing their screenshots; you compare their **code**, which
catches what a screenshot cannot: rows shown only in some states, empty and error states, text that
is cut, labels spoken to a screen reader, and what each control does.

For each screen, read both sides end to end and list every difference in:
1. **Content:** a control, row, section, header, footnote, figure, empty/error/loading state or
   confirmation that one app has and the other lacks; different words for the same thing.
2. **Order:** sections or rows in a different order.
3. **Behaviour:** a control that does something different (opens another screen, saves at another
   moment, asks or does not ask first, different limits or defaults).
4. **States:** signed out, empty list, error, the largest text sizes (iOS `isAccessibilitySize`
   branches, Android `isAccessibilityFontScale`), Blur/Hide of mature works.

Do not report (decided by the owner): Android's navigation and chrome (Material top bar, back
arrow, icon buttons, bottom sheets vs iOS sheets, dialogs, switches, sliders, segmented controls,
dropdowns, overflow menus), fonts, the demo data, Android's own extra information that iOS lacks
when DECISIONS.md (`/Users/cidy02/kudos-android-lane/docs/android-port/DECISIONS.md`) says it is
kept, and a sheet's accent colour.

For each screen: **same**, or the differences, each with `file:line` on both apps and a severity:
**P2** (information or a function missing or wrong on one app) or **P3** (wording, order, minor).
Begin the file with the counts, then a list of every P2, then the per-screen notes. Prefer what
you verified by reading both code paths; mark anything you only suspect as "suspected".
