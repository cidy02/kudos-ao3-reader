# Brief 3fl: A58's reader, Browse and work-detail faults

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fl`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile (`SavedWork` needs an
`author`; give test works a fixed millisecond `dateAdded`, since Room keeps milliseconds).
**Write your result file early and keep it current**, so a usage limit cannot leave it empty:
`docs/android-port/briefs/3fl-result.md`. Binding: `docs/AO3_NETWORKING_POLICY.md`.

Your A58 (`docs/android-port/audits/A58-result.md`, the priority list). Claude confirmed #1 in
the code (`browse/FandomListChrome.kt:275–280` opens `first.fandom` under "All N tags"). For
each below: confirm it against the code first, fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion, or say
why it isn't real. In this order; stop where you run out of time and say where.

1. **(#1)** "All N tags" opens the sibling union, as iOS's `AO3FandomUnion` and
   `FandomWorksView(includedFandoms:)`; one search, paced as any other.
2. **(#2)** "Last Copy" only when a local EPUB exists (`WorkOriginTests`).
3. **(#3)** Work detail prefers fresh remote figures over stale local ones (`BrowseAndWorkDetailRulesTests`).
4. **(#4)** A TOC child sharing its parent's href keeps the outer title; chapter totals not
   inflated by an Afterword (`ReadiumReaderTests`).
5. **(#5)** Blank or tiny page samples never publish a page count (`ReaderPageSampleTests`).
6. **(#6)** Non-AO3 imports with no declared status show Unknown, not In Progress (`WorkStatLabelTests`).
7. **(#8)** Comments' chapter fallbacks for empty sections and out-of-range positions (`ReaderSectionTests`).
8. **(#9)** Removing a source-less work dismisses its detail (`WorkDetailPresentationTests`).
9. **(#10)** The comment length budget counts Unicode code points (`BrowseAndWorkDetailRulesTests`).
10. **(#15)** Queue and collection action labels name their memberships ("In 2 Queues").
11. **(#17)** A malformed chapter section falls back to chapter 1 (`ReaderTimeEstimateTests`).
12. **(#18)** Creator identity matching: whitespace normalization and orphan exclusion (`SeriesCreatorTests`).
13. **(#14)** Recognized AO3 dates on detail go through the display-date formatter.

Leave A58's #7 (media-control time estimates), #11 (note markup), #12 (sentence chunking for
speech), #13, #16, #19 and #20 (colours, skeletons, italics); note any you find cheap and safe.
