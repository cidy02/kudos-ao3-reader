# Brief 3fq: A63's action differences

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fq`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema or
backup-format change** (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile: when you add a parameter,
pass it at every call site. **Write your result file early and keep it current**:
`docs/android-port/briefs/3fq-result.md`. Binding: `docs/AO3_NETWORKING_POLICY.md` (a
download is one user-started request per work, paced as any other); owner direction: layout,
content, order and behaviour as iOS, navigation and chrome Android's own. No regex flag or
class beyond what Android's `java.util.regex` documents.

Your A63 (`docs/android-port/audits/A63-result.md`). **Claude is doing F07, F16, F25 and F31**
(comments threads and the Inbox): leave `comments/` and `account/AccountInboxPane.kt` alone.
For the others, in your priority order (F01, F30, F17, F12, F10, F05, F08, F20, F11, then the
rest): confirm against the code at HEAD, fix as iOS does (`/Users/cidy02/kudos-ios-polish/`,
read-only) with a test where the logic can be tested, or say why it isn't worth it. A
confirmation iOS always asks for is asked whatever the delete-confirmation setting. Reuse the
pickers, menus and sheets 3fp made shared (`QueueMembershipDialog`,
`AddSelectionToCollectionDialog`, `LibraryWorkMenu`, `ScopedWorkActions`); don't add a second
version of one. Stop where you run out of time and say where.
