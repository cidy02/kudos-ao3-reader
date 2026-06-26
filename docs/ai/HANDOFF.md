# AI Handoff

## Handoff - T-61 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `7b09348`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/app/src/main/java/io/github/cidy02/kudos/KudosApplication.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/MainActivity.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosApp.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/KudosAppContainer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/MainScaffold.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/CollectionDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/TagDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/WorkDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/files/FileWriteResult.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/files/WorkFileStore.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3HttpResponse.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3DownloadUrlBuilder.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3EpubDownloader.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadata.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadataParser.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkMetadataRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailSource.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkMetadataMerger.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkTags.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/files/WorkFileStoreTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/work/AO3WorkNetworkTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/works/WorkLifecycleTest.kt`

Dependencies added:

- None.

Work Detail behavior implemented:

- `WorkDetailSource` now supports `LocalWork`, `RemoteSummary`, `RemoteUrl`,
  and `Ao3WorkId`.
- `AppNavHost` carries the selected source so Search opens remote summaries and
  Library opens local saved-work ids into the same `WorkDetailScreen`.
- `WorkDetailScreen` hydrates from either a remote `AO3WorkSummary` or a local
  `SavedWork` Room record.
- The screen displays title, author, fandoms, rating, warnings, categories,
  relationships, characters, freeforms, summary, language, words, chapters,
  kudos, comments, hits, series metadata, completion state, source URL, saved
  state, downloaded state, favorite state, and finished state where available.
- Read and authenticated AO3 actions are visible but disabled/deferred; no
  reader opening or AO3 write behavior was implemented.

Save/download lifecycle implemented:

- `KudosAppContainer` creates the Room database, app-private file store, AO3
  client, work repository, metadata repository, EPUB downloader, importer, and
  Library repository.
- `WorkImporter.saveMetadataOnly(summary)` creates or updates a saved Room record
  with `isSaved = true` and `hasEpub = false`.
- `WorkImporter.download(summary)` creates/updates the saved Room record, then
  downloads the EPUB and sets `hasEpub = true` only after the file write succeeds.
- Failed downloads leave the metadata record intact but do not mark `hasEpub`
  true.
- Existing saved works are matched by source URL before creating a new UUID,
  avoiding duplicate local records for the same AO3 work in this phase.
- Local actions implemented: favorite toggle, finished toggle, add/remove user
  tags, add/remove collections, delete local EPUB, and remove from Library.

File storage paths:

- EPUB files are written under app-private storage:

```text
files/works/<UUID>.epub
```

- `WorkFileStore` uses the local `SavedWork.id` UUID as the filename.
- Non-UUID/unsafe ids are rejected for EPUB paths.
- Writes go through a temp file in the works directory, then move to the final
  UUID path. Atomic move is attempted first with a normal replace fallback.
- Deleting the local EPUB keeps the Room work record and sets `hasEpub = false`.
- Removing from Library deletes the EPUB file and the Room work record.

Metadata merge policy:

- `WorkMetadataMerger` merges remote search summary, canonical AO3 metadata, and
  any existing local `SavedWork`.
- It preserves local user state: `isFavorite`, `isFinished`, reading progress,
  `lastReadDate`, `lastSpineIndex`, `lastScrollFraction`, `readiumLocator`,
  `knownChapterCount`, and `lastUpdateCheck`.
- Remote metadata fills or updates AO3-derived fields: title, author, summary,
  source URL, rating, language, word count, chapters, kudos, comments, hits,
  warnings, categories, fandoms, characters, relationships, freeforms, series,
  and completion state.
- Blank remote values do not erase existing non-empty local values.

Canonical tag fetch behavior:

- `AO3WorkMetadataRepository` fetches:

```text
/works/<workID>?view_adult=true
```

- `AO3WorkMetadataParser` extracts fandoms, relationships, characters,
  freeforms, warnings, categories, language, words, chapters, kudos, comments,
  and hits using Jsoup selectors matching Apple `parseWorkTags`.
- `workTagsFetched` is set true only when canonical metadata fetch succeeds and
  returns non-empty metadata.
- If canonical fetch fails, save/download proceeds from the search summary and
  `workTagsFetched` remains false.

EPUB download behavior:

- `AO3DownloadUrlBuilder` builds the Apple-matching route:

```text
/downloads/<workID>/work.epub
```

- `AO3Client.getBytes` was added for binary GETs while keeping existing text GETs
  intact.
- OkHttp binary GETs use the Phase 4 coordinator/retry policy and map HTTP,
  login redirect, overload, and network errors to `AO3Error`.
- `AO3EpubDownloader` rejects empty bodies, HTML content types/pages, and
  non-ZIP signatures before allowing the file write.

Library behavior implemented:

- `LibraryScreen` observes Room-backed saved works through `LibraryRepository`.
- It shows an empty state, saved work cards, downloaded/offline status, favorite
  status, finished status, rating, words, chapters, summary, and Details action.
- Tapping Details opens canonical Work Detail from the local saved-work id.
- Full filters, sorting controls, bulk actions, privacy filtering, and richer
  Library UX remain Phase 8 work.

Tests added:

- `WorkMetadataMergerTest`
- `WorkLifecycleRepositoryTest`
- `WorkImporterLifecycleTest`
- `WorkFileStoreTest`
- `WorkFileStoreRejectsUnsafePathTest`
- `AO3DownloadUrlBuilderTest`
- `AO3EpubDownloaderTest`
- `AO3WorkMetadataParserTest`
- `AO3WorkMetadataFetchPartialFailureTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.files.*' --tests 'io.github.cidy02.kudos.network.ao3.work.*' --tests 'io.github.cidy02.kudos.works.WorkMetadataMergerTest'`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.works.WorkLifecycleRepositoryTest' --tests 'io.github.cidy02.kudos.works.WorkImporterLifecycleTest'`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- Focused file/network/parser/merger tests passed.
- Focused Room/lifecycle tests passed.
- Full `:app:testDebugUnitTest` passed.
- Non-clean combined assemble/test/lint exposed stale generated Compose output
  (`AO3WorkCardKt 2.class`), matching the stale-output issue seen in prior phases.
- Clean combined verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 99 JVM tests, 0 failures, 0 errors
  - `:app:lintDebug`

Known gaps / intentionally deferred:

- No Readium integration or real reader opening.
- No EPUB metadata parsing/import; Phase 6 persists AO3 metadata and stores EPUB
  bytes, but does not inspect OPF metadata yet.
- No auth/WebView, cookies, authenticated AO3 lists, comments, kudos,
  subscriptions, Mark for Later, AO3 bookmarks, or AO3 writes.
- Direct `RemoteUrl`/`Ao3WorkId` Work Detail hydration is scaffolded but deferred
  until fuller Work Detail page parsing.
- No advanced download queue, cancellation, progress percentages, or series
  download queue.
- Library has a basic saved-work list only; full filters/sorts/bulk/privacy UX is
  still Phase 8.

Apple/contract ambiguity:

- Apple's remote Work Detail `Read` action imports/downloads lazily. Android
  Phase 6 keeps `Read` disabled because the prompt explicitly says not to
  implement reader opening; users can Save or Download instead.
- Apple imports EPUB metadata before creating `SavedWork`. Android Phase 6 does
  not parse EPUB metadata yet; it uses AO3 search/canonical metadata and records
  this as a Phase 7/import follow-up.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 7 Readium Reader. Build on the file-backed `hasEpub` state and
`files/works/<UUID>.epub` storage, open downloaded EPUBs with Readium Kotlin,
and continuously maintain `lastSpineIndex` plus `lastScrollFraction` alongside
any Android Readium locator.

## Handoff - T-60 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `f1ab0fe`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Error.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryPolicy.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchFilters.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchModels.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParser.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/ui/components/AO3WorkCard.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchParserTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepositoryTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilderTest.kt`
- `android/app/src/test/resources/ao3/search_basic.html`
- `android/app/src/test/resources/ao3/search_locked.html`
- `android/app/src/test/resources/ao3/search_no_results.html`
- `android/app/src/test/resources/ao3/search_overload.html`
- `android/app/src/test/resources/ao3/search_series.html`
- `android/app/src/test/resources/ao3/search_unicode.html`

Dependencies added:

- Jsoup `1.22.2` (`org.jsoup:jsoup`) for AO3 HTML parsing.

AO3 filter coverage:

- Ported Android search DTOs for the current Apple filter set:
  query, fandom, characters, relationships, additional tags, excluded fandoms,
  excluded characters, excluded relationships, excluded additional tags, rating,
  rating match, include Not Rated, included/excluded warnings, included/excluded
  categories, crossover, completion, words-from/to, updated window, language,
  and sort.
- Rating ids match Apple/AO3:
  Not Rated `9`, General `10`, Teen `11`, Mature `12`, Explicit `13`.
- Warning ids match Apple/AO3:
  `16`, `14`, `17`, `18`, `19`, `20`.
- Category ids match Apple/AO3:
  `116`, `22`, `21`, `23`, `2246`, `24`.
- Excluded tag names are folded into `work_search[query]` as `-"tag"` and
  deduped in first-seen order.
- Excluded warnings/categories are folded into search text as
  `-archive_warning_ids:<id>` and `-category_ids:<id>`.
- Multiple-rating, rating-plus, rating-minus, and Not Rated combinations are
  folded into AO3 text-search clauses when the single structured rating field
  cannot express them.

Sort mapping:

- `relevance` -> omitted
- `dateUpdated` -> `revised_at`
- `datePosted` -> `created_at`
- `words` -> `word_count`
- `kudos` -> `kudos_count`
- `hits` -> `hits`
- `comments` -> `comments_count`
- `bookmarks` -> `bookmarks_count`
- No `title` or `author` sort option was added.

URL generation behavior:

- Search path is `https://archiveofourown.org/works/search`.
- Empty/blank fields are omitted.
- `page` is 1-based and always emitted, including `page=1`, matching current
  Apple behavior.
- Included warnings/categories use repeated
  `work_search[archive_warning_ids][]` and `work_search[category_ids][]`.
- Word count expressions are:
  `from-to`, `> from`, `< to`, or omitted.
- Android additionally ignores invalid/non-positive word-count sides safely
  instead of sending malformed expressions.

Parser fixtures added:

- `search_basic.html`
- `search_no_results.html`
- `search_series.html`
- `search_locked.html`
- `search_unicode.html`
- `search_overload.html`

Parser behavior:

- Uses Jsoup and AO3-like CSS selectors to parse `li.work.blurb` search results
  into `AO3WorkSummary`.
- Extracts id, title, authors, work URL, fandoms, rating, warnings, categories,
  relationships, characters, freeforms, summary, language, words, chapters,
  comments, kudos, hits, bookmarks, series title/position/url, completion state,
  restricted marker, and updated date when present.
- Preserves first-seen tag order, dedupes normalized tag text, decodes HTML
  entities, normalizes whitespace, and preserves Unicode.
- Empty/no-result pages return an empty work list and current page fallback.
- AO3 overload/capacity fixture throws a typed parser error and repository maps
  it to `AO3Error.Overloaded`.
- Single malformed work blurbs are skipped at page level, matching Apple; direct
  `parseWorkSummary` calls throw a clear missing-structure error.

Repository behavior:

- `AO3SearchRepository` builds the URL, calls the Phase 4 `AO3Client`, parses
  successful bodies off the main dispatcher, and returns `AO3Result<AO3SearchPage>`.
- Network errors pass through unchanged.
- Parser errors surface as non-retryable `AO3Error.Parse`.
- `AO3RetryPolicy` now explicitly does not retry parse errors.

UI behavior implemented:

- `SearchScreen` is no longer static. It has query input, search action, sort
  menu, disabled advanced-filter entry point, loading/error/empty states, results
  list, retry, and previous/next pagination.
- Results render in `AO3WorkCard` with title, author, fandoms, required tags,
  relationships/characters/freeforms, summary, and stats.
- Tapping Details stores the selected remote summary in `AppNavHost` and opens
  `WorkDetailScreen`.
- `WorkDetailScreen` displays the selected AO3 result metadata and placeholder
  actions for Read, Download, Favorite, User Tags, Collections, Open on AO3,
  Kudos, and Comment. No action performs real save/download/auth/write work.

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- First `:app:testDebugUnitTest` exposed a test fixture helper visibility issue;
  fixed with local helper names.
- Final `:app:testDebugUnitTest` passed.
- Final combined verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 81 JVM tests, 0 failures, 0 errors
  - `:app:lintDebug`

Known gaps / intentionally deferred:

- No advanced filter sheet UI yet; only query and sort are exposed visually.
- No saved-search persistence or local Library search integration.
- No auth/WebView, cookies, authenticated account lists, comments, kudos,
  subscriptions, bookmarks, Mark for Later, or writes.
- No EPUB download/import, save lifecycle, Readium reader, Room work persistence,
  or production Library wiring.
- No full AO3 Work Detail page hydration; Work Detail displays only search-result
  metadata carried from the selected card.
- No real AO3 traffic was used in tests. Parser behavior is fixture-driven.

Apple/contract ambiguity:

- Apple currently forwards raw word-count strings. The Phase 5 prompt required
  safe invalid normalization, so Android ignores invalid/non-positive sides while
  preserving Apple-compatible output for valid values. No human approval appears
  needed unless exact malformed-input parity is desired.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 6 Work Detail and Save/Download. Build on `AO3WorkSummary`, fetch canonical
work tags/detail where needed, implement EPUB download/import and local save
lifecycle, and keep auth/writes/reader expansion gated to their approved phases.

## Handoff - T-59 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `c3fe55f`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Constants.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Error.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3HttpResponse.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3NetworkConfig.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3OverloadDetector.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RequestCoalescer.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RequestCoordinator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Result.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryAfter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RetryPolicy.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3UserAgent.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`

Dependencies added:

- OkHttp `5.4.0`
- MockWebServer 3 `5.4.0`
- kotlinx-coroutines-core `1.11.0`
- kotlinx-coroutines-test `1.11.0`

Chosen User-Agent:

```text
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15
```

This matches the Apple browser-like User-Agent and contains no private
user/device-identifying data.

Concurrency configuration:

- `AO3NetworkConfig.maxConcurrentRequests = 3`, matching the current Apple
  `AO3RequestCoordinator` parity note.
- `AO3NetworkConfig.minDelayBetweenRequestsMillis = 500`.
- `AO3RequestCoordinator` uses a coroutine semaphore plus a spacing mutex, is
  cancellation-aware through suspending primitives, and does not block the main
  thread.

Retry/backoff behavior:

- Default `maxRetries = 2`.
- GET retries only for `AO3Error.Network`, `AO3Error.RateLimited`,
  `AO3Error.Server`, and `AO3Error.Overloaded`.
- POST/PUT/PATCH/DELETE are never retryable by policy.
- Bad request, auth required, forbidden, not found, generic non-429/non-5xx HTTP,
  and validation errors are not retryable.
- Backoff is 500 ms for the first retry and 1000 ms for the second retry.

Retry-After behavior:

- `AO3RetryAfter` parses integer seconds and RFC 1123 HTTP-date values.
- For 429 and overload errors, retry delay is at least the parsed
  `Retry-After` value when present.
- Invalid `Retry-After` values fall back to the normal backoff.

Request coalescing behavior:

- Concurrent identical GETs share one in-flight operation.
- Coalescing keys include method, canonical URL, and normalized headers.
- Non-GET retry/coalescing policy is documented through `AO3RetryPolicy`; no
  write client method was added in Phase 4.
- In-flight entries are removed on success or failure, so errors do not poison
  future calls.
- Cancelling one waiter does not automatically cancel the shared operation.

Client behavior:

- `AO3Client.get(url, headers)` returns `AO3Result<AO3HttpResponse>`.
- `AO3HttpResponse` exposes final URL, status code, headers, and raw body.
- OkHttp types are kept inside the network layer.
- Status mapping covers success, 400, 401, 403, 404, 429, 5xx, other HTTP,
  network failures, login redirects, validation errors, and overload/capacity
  pages.
- The conservative overload detector checks obvious AO3/AO3-capacity text so
  later parsers do not treat those pages as empty results.

Tests added:

- `AO3RetryAfterTest`
- `AO3RetryPolicyTest`
- `AO3RequestCoordinatorTest`
- `AO3RequestCoalescerTest`
- `AO3ClientStatusMappingTest`
- `AO3ClientRetryTest`
- `AO3ClientDoesNotRetryPostOrNonRetryableErrorsTest`
- `AO3ClientUserAgentTest`
- `AO3ClientCoalescingTest`
- `AO3OverloadDetectorTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- Focused `:app:testDebugUnitTest` initially exposed a MockWebServer 5 API update
  (`close()` instead of `shutdown()`), then a test ordering assumption for
  concurrent different-URL requests. Both were fixed.
- One combined assemble/test/lint run failed because stale generated build output
  contained duplicate `ComposableSingletons$SearchScreenKt` classes after editing
  the Compose placeholder. A clean Gradle run removed the stale output.
- Final clean verification passed:
  - `:app:assembleDebug`
  - `:app:testDebugUnitTest` with 59 JVM tests
  - `:app:lintDebug`

Known gaps:

- No AO3 search query builder or search UI integration.
- No AO3 HTML parsing/Jsoup.
- No auth/WebView, cookies, authenticated requests, or write actions.
- No EPUB download/import, Readium, comments, account lists, or production Library
  networking.
- No persistent HTTP cache beyond OkHttp defaults.
- No real AO3 traffic was used in tests.

Deliberate deviations from Apple behavior:

- None requiring human approval. Android matches the documented 3-slot default,
  browser-like User-Agent, transient GET retry policy, and Retry-After behavior.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 5 AO3 search/query building and parsing from an approved prompt. Reuse this
network layer; keep auth, writes, reader, EPUB import/download, and production
Library wiring out unless the Phase 5 prompt explicitly expands scope.

## Handoff - T-58 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `02ad56a`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupErrors.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupExporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupJson.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupPaths.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupValidator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupVersion.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`

Dependencies added:

- Kotlin serialization compiler Gradle plugin
  `org.jetbrains.kotlin.plugin.serialization` using the existing Kotlin/Compose
  compiler version `2.3.21`.
- No new runtime JSON dependency; Phase 3 uses the existing
  `kotlinx-serialization-json` runtime added in Phase 2.

Backup format implemented:

- Current Apple v1 directory-backed `.kudosbackup` manifest decoding and
  best-effort directory import where Android can access the package path.
- Android v2 ZIP `.kudosbackup` export/import with internal paths:
  `manifest.json`, `Works/<UUID>.epub`, and `Fonts/<fileName>`.
- v2 manifest includes `exportedBy`, optional collections, saved searches,
  v2 work stats/update fields, and Readium locator metadata. v2-only fields stay
  optional and are not treated as Apple v1 parity.

Import/export behavior:

- JSON is UTF-8 and decoded with unknown-field tolerance.
- UUIDs normalize to canonical lowercase for work, collection, and saved-search
  identity.
- Dates validate as ISO-8601 instants.
- ZIP import rejects missing manifests, unsupported versions, invalid JSON,
  invalid dates, invalid UUIDs, unsafe paths, absolute paths, traversal, malformed
  `Works/` or `Fonts/` entries, duplicate entries, truncated archives, and entries
  over the configured size limits.
- v2 ZIP output is deterministic where practical: manifest first, then sorted
  work/font entries with stable ZIP timestamps.

Merge behavior:

- Works merge by UUID without deleting local-only works.
- Local EPUB state is preserved when the backup lacks the EPUB file; a new work
  whose manifest claims `hasEPUB = true` is restored with `hasEpub = false` when
  the file is missing.
- Backup EPUB bytes are returned as files-to-write by work UUID for later
  app-private atomic persistence.
- User tags are trimmed, deduplicated, and unioned with local assignments.
- Bookmarks merge by URL and update title/date to match Apple restore behavior.
- Collections merge by UUID; name collisions with different UUIDs create a
  separate suffixed restored collection.
- Fonts merge by safe filename. Colliding different/unknown bytes are suffixed,
  and a restored `readerFontID` is retargeted to the suffixed file when needed.
- Settings are applied after data merge with enum/range validation. Missing or
  unsafe custom font references fall back to `system`.
- `readiumLocator` is preserved for same-platform precision; portable resume
  fields `lastSpineIndex` and `lastScrollFraction` are preserved as the
  cross-platform fallback.

Tests added:

- `BackupV1ManifestDecodeTest`
- `BackupV2ZipDecodeTest`
- `BackupV2ZipExportTest`
- `BackupRoundTripBasicTest`
- `BackupMergeDoesNotDeleteExistingWorkTest`
- `BackupMergeDoesNotDeleteExistingEpubTest`
- `BackupMissingEpubMarksHasEpubFalseTest`
- `BackupUserTagMergeTest`
- `BackupCollectionMergeTest`
- `BackupBookmarkMergeByUrlTest`
- `BackupFontMissingReaderFontFallbackTest`
- `BackupRejectsUnsupportedVersionTest`
- `BackupRejectsMissingManifestTest`
- `BackupRejectsPathTraversalTest`
- `BackupRejectsAbsolutePathTest`
- `BackupRejectsInvalidJsonTest`
- `BackupRejectsTruncatedZipTest`
- `BackupRejectsDuplicateEntryTest`
- `BackupPreservesLegacyProgressFieldsTest`
- `BackupPreservesReadiumLocatorAsPlatformSpecificDataTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- First focused `:app:testDebugUnitTest` run found a test-fixture issue: Java
  `ZipOutputStream` refuses duplicate entries before the importer can inspect
  them. Fixed by hand-writing the duplicate-entry ZIP fixture.
- Final `:app:testDebugUnitTest` passed: 35 tests, 0 failures.
- Final `:app:assembleDebug` passed.
- Final `:app:lintDebug` passed and wrote
  `android/app/build/reports/lint-results-debug.html`.

Known gaps:

- Storage Access Framework picker/share-sheet wiring remains placeholder-only.
- Backup services return file bytes/maps for later app-private staging and atomic
  writes; production Room/DataStore persistence and file commit orchestration are
  not wired yet.
- Apple v2 ZIP import/export support is not implemented in this branch.
- No AO3 networking, parsing, search requests, auth, Readium, EPUB download/import
  from AO3, account lists, comments, or production Library browsing/filtering.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 4 AO3 networking core from an approved prompt. Keep it limited to request
policy/client foundations and tests; do not start search parsing, auth, reader,
or production Library UI unless the phase prompt explicitly allows it.

## Handoff - T-57 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `c1a7475`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/schemas/io.github.cidy02.kudos.data.local.KudosDatabase/1.json`
- `android/app/src/main/java/io/github/cidy02/kudos/core/model/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/**`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/**`

Dependencies added:

- KSP Gradle plugin `2.3.9`
- Room runtime/ktx/compiler/testing `2.8.4`
- DataStore Preferences `1.2.1`
- Kotlinx serialization JSON `1.11.0`
- AndroidX Test core `1.7.0`
- JUnit `4.13.2`
- Robolectric `4.16.1`

Database schema summary:

- Room database: `KudosDatabase`, name `kudos.db`, schema version `1`, schema
  export enabled and committed.
- Tables: `works`, `user_tags`, `work_tag_cross_refs`, `collections`,
  `collection_work_cross_refs`, `bookmarks`, `custom_fonts`, `saved_searches`.
- User tags and collections are normalized with cross-reference tables.
- AO3 tag groups are stored as JSON-encoded string-list columns for Phase 2.
- Date/time values use `java.time.Instant` converted to epoch milliseconds.
- `comments`, `hits`, `knownChapterCount`, and `lastUpdateCheck` are nullable
  Android/local/future-compatible fields, not current Apple v1 backup parity
  fields.
- Production destructive migrations were not enabled.

Settings defaults implemented:

- `readerFontID = "system"`
- `readerMode = "scroll"`
- `readerTwoPage = false`
- `readerCustomize = false`
- `readerBoldText = false`
- `readerFontPt = 18`
- `readerLineHeight = 1.65`
- `readerLetterSpacing = 0`
- `readerWordSpacing = 0`
- `readerMargin = 28`
- `readerJustify = false`
- `confirmBeforeDelete = true`
- `hideMatureContent = true`
- `matureContentMode = "obscure"`
- `requireBiometricToReveal = false`
- `appTheme = "light"`
- `readerTheme = "light"`
- `matchAppReaderTheme = true`
- `accentColorHex = "#990000"`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed: 11 tests, 0 failures, 0 errors.
- `:app:lintDebug` passed with `0 errors, 6 warnings`; the warnings are the same
  version-availability notices carried from Phase 1.

Known gaps:

- No AO3 networking, parsing, search requests, auth, backups, Readium, EPUB
  import/download, account lists, comments, or production Library queries.
- DataStore repository exists and is tested, but app-wide runtime settings wiring
  remains minimal; Settings screen only displays default values.
- Backup import/export is not implemented; `BackupSettings` only preserves the
  contract field names for future Phase 3 work.
- Robolectric is included because Room DAO tests run under local JVM unit tests,
  not instrumentation.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 3 backup v1/v2 compatibility from an approved prompt. Keep it limited to
manifest decoding/encoding, ZIP safety, merge semantics, fixtures, and tests.

## Handoff - T-56 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `00a25b6`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/.gitignore`
- `android/gradle/libs.versions.toml`
- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/drawable/ic_kudos_mark.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/xml/backup_rules.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `android/app/src/main/java/io/github/cidy02/kudos/**`

Summary:

Phase 1 scaffold only. Added a native Android project under `android/` with
Gradle Kotlin DSL, a Gradle 9.4.1 wrapper, AGP 9.2.0, Kotlin/Compose compiler
2.3.21, Compose BOM 2026.06.00, Material 3, and placeholder Compose navigation.
The app shell has Home, Library, Browse, Account, global Search, Work Detail,
Reader placeholder, Settings, and Backup placeholder routes. It intentionally
does not implement AO3 networking, parsing, auth, backup import/export, Readium,
Room, DataStore, EPUB handling, account data, comments, or production Library
behavior.

Verification:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed with no unit tests defined yet.
- `:app:lintDebug` passed and wrote `android/app/build/reports/lint-results-debug.html`.
- Lint report has `0 errors, 6 warnings`, all version-availability notices for
  Gradle, AGP, Activity Compose, Lifecycle, Navigation Compose, and the Compose
  compiler plugin.
- First assemble without `ANDROID_HOME` failed because Gradle could not locate
  the Android SDK. Re-running with `ANDROID_HOME=$HOME/Library/Android/sdk`
  succeeded; Gradle installed the licensed Android SDK Platform 37.0 package
  into the local SDK.

Version decisions:

- `minSdk = 26`
- `compileSdk = 37`
- `targetSdk = 37`
- Gradle wrapper `9.4.1`
- Android Gradle Plugin `9.2.0`
- Compose BOM `2026.06.00`
- Compose compiler plugin `2.3.21`

Known risks:

- UI has not been emulator/screenshot verified; verification was build/lint only.
- Placeholder copy and layout are intentionally temporary and should be replaced
  as each contract-backed implementation phase lands.
- Version catalog choices are pinned to the official AGP/Compose baseline used
  for this scaffold; review whether to bump the six lint-reported newer
  versions before Phase 2.
- `ANDROID_HOME` must be set to `$HOME/Library/Android/sdk` in this local
  environment unless Android Studio or shell configuration exports it.

Next recommended agent: Claude or Codex

Next steps:

1. Review the Phase 1 scaffold against the Phase 0 contracts and prompt scope.
2. If accepted, start Phase 2 only from the approved next-phase prompt.
3. Keep AO3 networking/parsing/auth, backups, Room/DataStore, Readium, EPUB import,
   and account/comment behavior out of the scaffold until their phases are approved.

## Handoff - T-55 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `69e92a6`

Files changed:

- `TASKS.md`
- `AGENTS.md`
- `docs/android/ANDROID_PORT_PLAN.md`
- `docs/contracts/CORE_BEHAVIOR_CONTRACT.md`
- `docs/contracts/BACKUP_FORMAT.md`
- `docs/contracts/AO3_BEHAVIOR_CONTRACT.md`
- `docs/contracts/READER_STATE_CONTRACT.md`
- `docs/contracts/SETTINGS_CONTRACT.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`
- `docs/ai/HANDOFF.md`

Summary:

Phase 0 docs only. Added the approved Android port plan from
`Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md`, contract skeletons,
Android branch policy notes, current Apple v1 backup facts, explicit v2 backup
additions, AO3 sort/concurrency notes, and this handoff. No Android Gradle,
Compose, Room, DataStore, networking, backup, reader, auth, or parser
implementation was added.

Commands run:

- `git branch --show-current`
- `git status --short`
- `git branch -a --list '*kudos-ao3-reader-android*'`
- `git switch -c kudos-ao3-reader-android`
- `mkdir -p docs/android docs/contracts docs/ai`
- `cp /Users/cidy02/Downloads/Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md docs/android/ANDROID_PORT_PLAN.md`
- `git rev-parse --short HEAD`

Tests passing:

- Not run; documentation-only Phase 0 change.

Tests failing/not run:

- Swift tests not run.
- Android tests unavailable because no Android scaffold exists yet.

Known risks:

- `docs/android/ANDROID_PORT_PLAN.md` is copied from the external plan and should
  be reviewed for any remaining wording drift before Phase 1.
- Contract docs are skeletons, not complete executable specs.
- Phase 1 remains blocked until Codex/Claude review accepts these docs.

Needs human decision:

- Confirm Android `minSdk`, `targetSdk`, desugaring policy, and first release
  channel during Phase 0/Phase 1 planning.

Next recommended agent: Codex

Next steps:

1. Review the Phase 0 docs for consistency with the current repo.
2. If accepted, hand to Claude for Phase 1 scaffold on `kudos-ao3-reader-android`.
3. Keep Phase 1 limited to Gradle/app shell/navigation/theme placeholders only.
