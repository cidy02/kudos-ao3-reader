# Audit A21: what the two apps write to their logs

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A21-result.md`. No helper scripts or scratch files left behind (work
in memory or under `/tmp`).

## Why

Kudos is a reader for a fan-fiction archive: what a person reads, searches for and writes is
private, and so is their account name. A failed "Open With" on iOS logged the file's name as
public text (fixed). This audit finds every other place where either app writes something
about the reader into a log.

## What to read

- iOS: every `Log.<category>.<level>(…)`, `os_log`, `Logger`, `print(` and `NSLog(` under
  `kudos-ao3-reader/` in this worktree.
- Android: every `Log.d/i/w/e/v(`, `println(`, `Timber.` and `printStackTrace(` under
  `/Users/cidy02/kudos-android-lane/android/app/src/main/` (read-only; not in this worktree).

## What to report

A table, one row per log statement that includes **any value that is not a constant**:

| app | `path:line` | the statement, quoted | each interpolated value and what it holds | its privacy marker (iOS: `.public`, `.private`, none; Android: none exists) | class |

Class is one of:

- **P** personal: a work's title, author, summary, tags or URL; a file name or path; a search
  query or filter; a username, pseud or email; a comment's or draft's text; a cookie, token
  or header; a collection, bookmark or series name; an AO3 work, comment or user id.
- **E** an error's `localizedDescription` / `message` or a whole exception (these often
  repeat a file name, URL or server text: say which it can contain here, from the call that
  throws).
- **C** a count, a duration, a status code, a boolean, an enum case, a page number.

For iOS, a **P** or **E** value marked `.public` is a finding. A **P** value with no marker
inside a `Logger` call is private by default: say so, it is not a finding. For Android,
every **P** value is a finding (logcat has no private marker), and so is an **E** that can
carry a URL or file name.

Then, under "Findings", list only the findings, most serious first (credentials and tokens,
then usernames, then what is read or searched, then file names), each with the smallest fix:
on iOS `privacy: .private` (or `.private(mask: .hash)` where a stable id helps debugging);
on Android, drop the value or log a count or an id's hash.

Finish with "Counted": how many statements you read in each app, and the list of files you
did **not** read.

Exact files and lines only. Quote the statement as it is written. Do not guess what a value
holds: open the declaration and say.
