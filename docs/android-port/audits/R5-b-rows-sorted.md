# R5: the 49 differences in behaviour, sorted and made ready (a reading)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R5-result.md`. No helper scripts or scratch files left behind.

iOS is in this worktree under `kudos-ao3-reader/`. Android is at
`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (read-only;
not in this worktree). The audit to work from is
`/Users/cidy02/kudos-android-lane/docs/android-port/audits/A14-result.md`, section
"3. B — both have it, and they differ": about 49 rows in paragraphs, each naming an iOS
`path:line` and an Android `path:line`. That audit is several days old and much has changed
on Android since: **open both files for every row and describe what is there now.**

For each row, in the audit's order, write:

1. **The row**: its bold title, as the audit has it.
2. **iOS now**: the code, quoted, with `path:line`.
3. **Android now**: the code, quoted, with `path:line`. If the Android line has moved, find
   it. If Android now does what iOS does, say **"already the same"** and stop there for the
   row.
4. **Class**, one of:
   - **L** a label or words only: a `contentDescription`, an accessibility hint or value, a
     visible string, a placeholder. Nothing else about the control differs.
   - **S** a small difference in what a control does, contained in one function or one
     composable (an empty state that appears in the wrong case, a button missing from an
     existing dialog, a default).
   - **F** a feature: a screen, a sheet, a new read of AO3, or a change across several files.
   - **A** deliberately Android: the row is about a platform control (a swipe that Android
     draws as a menu, a slider where iOS has a field, a share sheet, haptics), or
     `docs/android-port/DECISIONS.md` records it (quote the entry's heading).
5. **For L rows only, the exact edit**: the Android `path:line`, the old text and the new
   text, ready to apply. Use iOS's words exactly. Where iOS's string is a VoiceOver label,
   hint, value or action name, it goes into the matching Android semantics property
   (`contentDescription`, `stateDescription`, `onClickLabel`, a custom action's label), **not
   into visible text**: say which property.
6. **For S rows**, two or three lines on the smallest change, naming the function.

End with a table of every row: title, class, and for L the one-line edit. Then counts per
class.

Exact files and lines only. Quote code as it is written. Do not guess what a line does: open
it.
