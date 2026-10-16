# Brief 3fo: A61's missing rows

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fo`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema or
backup-format change** (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile (`SavedWork` needs an
`author`; fixed millisecond `dateAdded`). **Write your result file early and keep it
current**: `docs/android-port/briefs/3fo-result.md`. Binding: `docs/AO3_NETWORKING_POLICY.md`.
Write no regex flag or class beyond what Android's `java.util.regex` documents; spell ASCII
classes out (`[0-9]`, `[A-Za-z0-9_]`) where ASCII is meant.

Your A61 (`docs/android-port/audits/A61-result.md`, its priority list). Claude has fixed **#1
and #3** (`d513e61e`). **Leave #2 and #5** (reader web view isolation and script-driven
navigation: Readium gives the app only a URL, so telling a tap from a script needs a device
experiment first), **#11 and #12** (reader typography and page-box insets: visual, to be
measured on a device first) and **#22** (backup ZIP structure checks: a backup-format area).

For each of the others, in A61's order: confirm it against the code at HEAD, then fix it as
iOS does (`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion,
or say why it isn't worth it. Stop where you run out of time and say where. Most harmful
first: **#4** (collection staging kept across leaving and returning; a cancelled load
restarts without dropping same-session drafts), **#8**, **#10**, **#6**, **#7**, then the rest
(#9, #13 to #21, #23 to #31).
