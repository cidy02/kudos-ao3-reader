# Brief 3v: imported EPUBs get their title, author and AO3 metadata, as on iOS

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. Leave changes
uncommitted. If you can run Gradle, build and test until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
If not, write carefully (declare before use; check symbols and signatures) and say so.
iOS lane, for reading: `/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.

## The bug (Claude, 2026-10-03)
Importing an AO3 EPUB on Android (`works/WorkImporter.kt` `importLocalEpub`) stores the **file
name** as the title ("A_suitor_for_you"), with no author, summary, source URL, rating, fandoms or
tags. For EPUBs, it only scans the zipped bytes as text for a calibre label block, so it never
reads the OPF. iOS's `importUserEPUB` (`Services/WorkImporter.swift` ~241–400) does read them:
- **OPF metadata:** `Reading/EPUB.swift` `EPUBMetadata` and `Reading/OPFParser.swift`, covering
  `dc:title`, `dc:creator`, `dc:description`, `dc:source`/identifier, `dc:language`, `dc:subject`
  (ratings and tags), the dates, the series, and `calibre:word_count`.
- **AO3 preface scan:** `ExtractedAO3EPUBMetadata.scan` (~line 601–700). It covers rating,
  warnings, categories, fandoms, relationships, characters, additional tags, language, stats,
  summary, source URL, and the published/updated dates.
- **Assignment:** `applyUserImportMetadata` / `applyEPUBMetadata` (fill-only for duplicates), then
  `ao3WorkID` and `ao3SeriesID` derived from the URLs.
- **Duplicate handling:** an import whose source URL matches an existing work updates that work
  (fill-only) instead of creating a second one, and restores it from Recently Deleted.

Test file: `/Users/cidy02/Downloads/A_suitor_for_you.epub` (real AO3 export; read it, don't copy
it into the repo). Make a small synthetic fixture for tests instead.

## Do
Port iOS's EPUB import metadata to Android, behaving identically, field for field, with the same
precedence (OPF first, then preface; fill-only for duplicates). Use Jsoup, already a dependency, as
`works/DownloadDateDetector.kt` does. Bound every read from the untrusted ZIP (see its
`readBounded`).
- Keep the converted-format path (PDF/HTML/TXT/ZIP and the calibre label block) as it is.
- Keep T-353's `downloadedAt` behaviour.
- Add JUnit tests for OPF parsing, the preface scan, and duplicate fill-only, using a synthetic
  EPUB built in the test.

Don't touch `settings/`, `reader/`, `comments/`, `library/` UI, `backup/`, migrations or
`app/MainScaffold.kt`. Write `docs/android-port/briefs/3v-result.md`.
