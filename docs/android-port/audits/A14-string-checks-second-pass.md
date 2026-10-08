# Audit A14: the string checks, second pass (what is really missing on Android)

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A14-result.md`.

Three mechanical checks listed iOS strings that an exact search did not find on Android:
`docs/android-port/audits/A9-result.md` (Search and Browse), `A10-result.md` (Account,
Bookmarks, Authors, Comments) and `A11-result.md` (Onboarding, Auth, Privacy, Support). A
missing string is only a lead: most are the same feature in other words. Your job is the
judgement the search could not make.

## For every "not found" row in the three files

Open the iOS file at the line given (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/…`: the
same tree as this worktree's `kudos-ao3-reader/`) and read enough around it to know what the
control or text does and when it shows. Then find its Android counterpart under
`android/app/src/main/java/io/github/cidy02/kudos/` by reading the matching screen (search by
behaviour and by words in any capitalisation, not by the exact string). Put the row in
exactly one class:

- **M, missing feature**: iOS has a control, a screen, a setting, an action, an alert or a
  state that Android does not have at all. Say what a reader cannot do on Android.
- **B, behaviour differs**: both have it and they do different things (a confirmation one
  side lacks, a different default, a different condition for showing it, an action that
  reads or writes AO3 on one side only). Quote both sides.
- **W, words differ**: the same thing, worded or capitalised differently. Give both strings
  with `path:line`.
- **N, not applicable**: macOS-only or iPad-only code, a preview, a debug screen, a string
  that is not shown to a reader, or something recorded as left out on Android (search
  `docs/android-port/DECISIONS.md` and `docs/android-port/briefs/*-result.md` for it and
  cite the line).

Known already, class them N with "known": anything under Pronunciations, Developer Settings,
the Kokoro engine rows; Writing's edit multiple works, add chapter, edit tags, series edit,
AO3 preview, Post and Delete of a work; Challenges' sign-ups list, assignments, settings
edit, prompt tags editor; Reading History's grouping; Favorites' scopes.

## The result file

1. Counts per class, per source file (A9, A10, A11).
2. **M**, most important first (a setting or an action a reader would look for, before a
   label): the iOS `path:line`, what it is, where on Android it would belong (`path`), and
   every AO3 read or write it makes on iOS (address and when), since that decides how it may
   be built.
3. **B**, with both sides quoted and `path:line` for each.
4. **W** as a table: iOS string, Android string, both `path:line`. No commentary.
5. **N** as a list with the reason in a few words.
6. What you did not read.

Exact files and lines only. A row you could not settle goes under "Unsettled" with what
would settle it; do not guess its class.
