# Brief 3fp: A62's remaining action differences

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fp`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema or
backup-format change** (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile. **Write your result file
early and keep it current**: `docs/android-port/briefs/3fp-result.md`. Binding:
`docs/AO3_NETWORKING_POLICY.md`; owner direction: layout, content, order and behaviour as
iOS, navigation and chrome Android's own. Write no regex flag or class beyond what Android's
`java.util.regex` documents.

Your A62 (`docs/android-port/audits/A62-result.md`). Claude fixed **F01, F02, F26, F03**
(`b67cf686`). **Leave F21 and F22** (reader theme customisation and Read Aloud's controls:
the reader's controls wait on owner question 12). For the others, in your priority order
(F04, F05, F06, F07, F08, F09, then F10 to F20, F23 to F25, F27 to F33): confirm against the
code at HEAD, fix as iOS does (`/Users/cidy02/kudos-ios-polish/`, read-only) with a test where
the logic can be tested, or say why it isn't worth it. A confirmation iOS always asks for is
asked on Android whatever the delete-confirmation setting (F04). Reuse Android's existing
pickers, sheets and menus; don't add a second version of one. Stop where you run out of time
and say where.
