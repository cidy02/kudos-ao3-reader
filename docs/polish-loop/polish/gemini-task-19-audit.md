READ-ONLY AUDIT. Do not edit, create or delete any file. Repo root is the current directory.
Search ONLY these folders: kudos-ao3-reader/Features/Home, kudos-ao3-reader/Features/Library, kudos-ao3-reader/Features/WorkDetail (all files).

Report every occurrence of these five bug patterns, with exact file:line and the offending line of code:
A. `SubjectFormRow(` called WITH `value:` AND followed by a trailing closure whose body is EMPTY or only `EmptyView()`
   (that closure binds to `action:` and swallows a navigation link on the same row). Closures that do real work are fine.
B. `accentOnFill` used as a foreground/label colour on a view whose background is a SOLID `palette.accent` or
   `palette.tint` fill (not `.opacity(...)`).
C. `Color.accentColor` or `.tint(.accentColor)` anywhere.
D. `.cardList()` NOT followed within 3 lines by `.environment(\.defaultMinListRowHeight, 0)` in a List whose rows are
   form rows (`SubjectFormRow`, text fields, toggles).
E. `.font(.system(size: <number>` on body text inside those folders that is NOT backed by `@ScaledMetric` (list at
   most 15, prioritising titles and row labels).

Output ONE markdown table only: | Pattern | file:line | code | note |. If a pattern has no hits, write one row saying
"none". Do not speculate beyond what the code shows.
