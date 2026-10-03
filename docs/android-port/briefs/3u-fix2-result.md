# Brief 3u-fix2 Result: Library section filter chips

## iOS behavior verified

- **Reading Now** shows `All <count>` and `WIP <count>`. All is the default. WIP means the AO3 work
  is not complete (`!isComplete`), not that the reader has unfinished reading progress. Counts hold
  every other Library filter constant and replace only the completion filter. The choice is view
  state and is not persisted.
- **Favorites (Works)** shows `All`, `Rereads`, `Offline`, and `WIP`, with no counts. Rereads means
  more than one finishing session, Offline uses `isDownloaded`, and WIP uses `!isComplete`. The
  quick filter is applied after the ordinary Library filters. All is the default and the choice is
  persisted.
- **Saved for Later, Finished, Collections, Downloaded, and Reading History** have no always-visible
  quick-filter choices.

## Android implementation

- Added a horizontally scrolling `SubjectChip` pill rail below the section subtitle. Selected pills
  use the scope accent fill; unselected pills use the existing glass treatment.
- Added the pure `filterLibrarySectionItems` rule and section-to-chip mapping in
  `LibrarySectionQuickFilter.kt`.
- Reading Now uses the existing completion filter, so selecting All or WIP also stays consistent
  with the full filter panel. Its counts are computed from privacy-visible section items after all
  non-completion filters.
- Favorites reads finishing-session counts from the existing `ReadingLogDao` flow and stores its
  selection in the existing `library-dashboard` preferences file.

## Verification

- `LibrarySectionQuickFilterTest`: **7 tests passed** with Android Studio's Kotlin compiler and
  JUnit 4.13.2, covering every `LibrarySectionKind` plus Reading Now counts and all Favorites rules.
- `git diff --check`: passed.
- Full Gradle verification could not run in this sandbox. The default Gradle home is read-only;
  a writable cache still hits the sandbox's forbidden file-lock socket, while the available patched
  cache exhausts the sandbox heap compiling `build.gradle.kts` before project compilation.
- UI was not launched because the Gradle build could not complete; visual verification remains
  manual.
