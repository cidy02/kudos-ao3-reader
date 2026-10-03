# Brief 3v result: imported EPUB metadata

## Result

Plain EPUB imports now read bounded OPF and HTML/XML entries before creating a
`SavedWork`. They apply the iOS import precedence: OPF title, author, summary,
language, subjects, dates, calibre series/word count and local chapter count;
then AO3-preface source URL, rating, dates, completion, categorized tags and
stats. AO3 work and series IDs are derived from the resulting URLs.

An AO3 source match now updates the existing row fill-only, merges new tags,
keeps its reading/user state and original `downloadedAt`, restores it from
Recently Deleted (including tombstone retraction), and only writes the selected
EPUB when the matched row has no local copy. Converted PDF/HTML/TXT/ZIP imports
and their calibre label path are unchanged.

## Tests and verification

- `WorkLifecycleTest` builds a synthetic EPUB in memory and covers OPF parsing,
  AO3-preface parsing, and duplicate fill-only/restoration behavior.
- `android/Scripts/check-invariants.sh`: passed.
- `EpubImportMetadata.kt` compiled standalone with Android Studio's Kotlin
  compiler against the project's Jsoup and parsing dependencies.
- The bounded parser was run against `/Users/cidy02/Downloads/A_suitor_for_you.epub`.
  It returned `A suitor for you`, `SerasTasha`, work `45053872`, `Not Rated`,
  `English`, the summary and categorized tags, published/updated dates,
  34,546 words, and 7/? chapters.
- `git diff --check`: passed.
- The requested Gradle build/tests could not start in this sandbox. The wrapper
  cannot create its `~/.gradle` lock, and a writable Gradle home then fails before
  configuration because Gradle's `FileLockContentionHandler` cannot open a local
  socket (`java.net.SocketException: Operation not permitted`). The normal
  `:app:assembleDebug :app:testDebugUnitTest` gate remains to be run outside the
  sandbox.
