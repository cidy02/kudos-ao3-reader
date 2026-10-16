# 3fr: iOS's Library tag backfill, in the foreground

**Done by Claude on 2026-10-16** (the agents were away): see DECISIONS 2026-10-16 "Brief 3fr".

**Lane:** a Codex worktree off `android/redesign-parity`. Write code and tests; do not commit,
push, sign in, or contact archiveofourown.org. Claude runs the gate, reviews, and commits.
Binding: `docs/AO3_NETWORKING_POLICY.md` (no background polling but folder sync; no periodic
full-library sweep; pacing never weakened; the demo never reaches AO3).

## Why

On 2026-10-16 Claude removed `WorkTagsRefreshWorker`: a daily background job that read up to
150 works from AO3 and kept nothing (DECISIONS 2026-10-16). So Android now has no tag backfill.
iOS has one, in the foreground: while the Library is open, `LibraryView.backfillFilterMetadata`
walks every work that is not queue-only, in order, and stops when the screen goes away.

## What iOS does (port it exactly)

- `kudos-ao3-reader/Features/Library/LibraryView.swift` `backfillFilterMetadata` (around line
  765): for each work, stop if cancelled; `WorkTags.backfillFromEPUB`; then, if
  `needsAO3Refresh`, `WorkTags.refreshFromAO3`. Sequential.
- `kudos-ao3-reader/Services/WorkTags.swift`:
  - `backfillFromEPUB`: only when `workTags` is empty and the EPUB is on disk; reads the EPUB's
    subjects off the main thread; `normalizedWorkTags(subjects, excludingRating:)`; sets
    `workTags`, and `rating` when empty; marks modified; reindexes search. No network.
  - `refreshFromAO3`: needs an AO3 id (stores a recovered one); `needsAO3Refresh` again; stamps
    `lastTagRefreshAttemptAt` before the read; `workMetadata`; empty tag groups keep the EPUB
    tags; merges each group with `TagMerge.merged`, removes from freeforms what a categorized
    group has, rebuilds the flat `workTags` (fandoms, relationships, characters, freeforms),
    takes language, words, chapters, kudos, comments, bookmarks, hits, verified author
    identities; `workTagsFetched = true`; marks modified; reindexes; records the work present.
    404 records it deleted. **Cancellation puts the previous stamp back.** Other failures keep
    the stamp (the 24-hour cooldown) and the old tags.
- `kudos-ao3-reader/Models/Models.swift` `needsAO3Refresh` (around line 394). Android already
  has it, private, as `BackupMergeService.iosNeedsMetadataRefresh`: make that the one shared
  `SavedWork.needsAO3Refresh` (an `Instant` to compare with, for tests) and use it in both.

## Android

- Run it from the Library screen's lifetime (a `LaunchedEffect`/view-model job that is
  cancelled when the Library leaves), over all non-queue-only works, not the filtered list.
- Reuse what exists: `WorkRepository.refreshMetadata` (it already handles the recovered id, 404
  and part of the fields), `WorkSearchIndex.reindex`, `WorkIdentityIndex.ao3WorkId`, the EPUB
  metadata reader the importer uses. Extend rather than add a second path; say where you did.
- Every read goes through the paced `AO3Client`; nothing in parallel. In the demo
  (`DemoNetwork.isActive`) it reads nothing from the network.
- No Room schema change (every field exists). No WorkManager.

## Tests (JVM; Claude runs them)

The predicate (each clause, the cooldown, `ao3Unavailable`); one refresh that fills every field
and sets `workTagsFetched` so the next pass skips it; cancellation restores the stamp; a failure
keeps the stamp; a 404 marks the work unavailable; the EPUB backfill fills tags only when empty;
the walk is sequential and stops on cancel; demo mode makes no request.

## Report

`docs/android-port/briefs/3fr-result.md`: what you changed (file:line), what you reused, what
you could not match and why.
