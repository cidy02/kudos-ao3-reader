# A60 result — JVM passes, Android fails

## Priority list

1. **P2 · F1 — Collection URL names accept non-ASCII interior characters on Android.** `network/ao3/account/AO3CollectionForm.kt:48`: `^[A-Za-z0-9]\w*[A-Za-z0-9]$`. On API 26+, `aéb`, `a中b`, and `a\u200Cb` pass; the desktop JDK pattern rejects them. This changes both availability checking and the create-collection validation gate. **Smallest fix:** replace `\w*` with `[A-Za-z0-9_]*`.
2. **P2 · F2 — Release selection accepts non-ASCII version digits on Android.** `update/AndroidReleaseMatcher.kt:23` and `update/AppVersion.kt:25`: `^android-v?\d+\.\d+\.\d+` and `v?(\d+)\.(\d+)\.(\d+)`. On API 26+, a non-draft release tagged `android-v٩.٩.٩` with an APK asset qualifies as version **9.9.9**, whereas the desktop JDK patterns reject it. **Smallest fix:** use `[0-9]` in both patterns. Lower practical priority than F1: this requires a publisher-supplied non-ASCII tag; ordinary ASCII releases are unaffected.

**No P1 crash/data-loss finding confirmed. No additional P3 defect confirmed.** Both findings concern wrong validation results, not regex compilation crashes. Neither was reproduced on an Android device in this audit.

## Scope and verification

- **Complete, static audit at lane HEAD:** `android/agent-codex-a60`, `47f468800926ac4b8193c0633545c069afee116f` (2026-10-16). Production scope contains **512 Kotlin files, zero Java files** under `android/app/src/main/java`.
- Paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`, unless prefixed with `android/`.
- Configuration read: `android/app/build.gradle.kts:43–44` (`minSdk = 26`, `targetSdk = 37`), Java/Kotlin target 17 and core-library desugaring enabled; `android/gradle/libs.versions.toml:12` pins `desugar_jdk_libs` **2.1.5**. Availability checks used the installed Android 37 SDK's `data/api-versions.xml`, then source inspection to resolve overloads, receivers and guards.
- Inventoried every `Regex(...)` call, indirect demo route-table pattern, and Jsoup `:matchesOwn(...)` pattern; searched for Java `Pattern`, regex options, pattern-bearing split/replacement calls, newer JDK methods, locale-sensitive conversions/formatting, charset defaults, temp files, absolute paths and process execution.
- **Supplementary host check, not device evidence:** Python `ctypes` called macOS `/usr/lib/libicucore.A.dylib` (ICU **78.1**) in memory. **112/112** non-interpolated literal constructor sites compiled, including their `IGNORE_CASE`/`DOT_MATCHES_ALL` options; **71/71** indirect demo route-table patterns compiled; **10/10** representative dynamic patterns plus the Jsoup pattern compiled. Host matching confirmed the F1/F2 inputs and `\p{InCombiningDiacriticalMarks}`. Older Android ICU versions were assessed from documented syntax, not executed.
- No builds, Gradle/lint/test suites, Android app launches, sign-in, AO3 requests, commits, pushes or branch changes. Only this report is left changed in the worktree; `TASKS.md` and source are untouched. The existing JVM portability test was read, not run.

## Findings

### F1 — P2: shared collection-name validation changes its accepted alphabet

**Code:** `network/ao3/account/AO3CollectionForm.kt:48`:

```kotlin
fun collectionNameFormatIsValid(name: String) = Regex("^[A-Za-z0-9]\\w*[A-Za-z0-9]$").matches(name)
```

The ASCII first/last character checks do not restrict the interior. Android uses Unicode word characters, including letters, combining marks, connector punctuation and join controls. The unflagged desktop JDK `\w` is ASCII. This is an API **26+** difference, independent of locale or desugaring. See [Android Pattern](https://developer.android.com/reference/java/util/regex/Pattern), [ICU regex](https://unicode-org.github.io/icu/userguide/strings/regexp.html), and [JDK 17 Pattern](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/regex/Pattern.html).

**Device consequence, traced in source:** `account/AO3CollectionFormState.kt:96` accepts the input and schedules the availability check; `account/AO3CollectionDetailRepository.kt:250–255` also accepts it and can label a 404 **Available**. `network/ao3/writes/AO3WriteRepository.kt:778` uses the same helper before saving a new collection, so the local invalid-name rejection is bypassed there too. This is a client-side validation inconsistency. No claim is made that AO3 accepted or rejected an actual POST: none was sent.

**Fix:** `^[A-Za-z0-9][A-Za-z0-9_]*[A-Za-z0-9]$` in the shared helper. This preserves the current length/end-character behavior. Add negative cases `aéb`, `a中b`, `a\u0301b`, and `a\u200Cb` to the collection-form tests and an Android-runtime test; verify they make no availability request. `android/app/src/test/java/io/github/cidy02/kudos/account/AO3CollectionFormTest.kt:113` currently checks empty, underscore-prefixed and reserved names, but not these interiors.

### F2 — P2: Unicode decimal digits cross the update release gate

**Code:** `update/AndroidReleaseMatcher.kt:23`:

```kotlin
private val TAG_PATTERN = Regex("""^android-v?\d+\.\d+\.\d+""", RegexOption.IGNORE_CASE)
```

`update/AppVersion.kt:25,29–36`:

```kotlin
private val PATTERN = Regex("""v?(\d+)\.(\d+)\.(\d+)""")
val match = PATTERN.find(text) ?: return null
// Each captured component is converted with toIntOrNull().
```

On API **26+**, ICU `\d` accepts Arabic-Indic decimal digits. `AndroidReleaseMatcher.latest` (`:36–45`) therefore admits `android-v٩.٩.٩`; `AppVersion.parse` converts all three components to 9. Kotlin/JVM's conversion uses `Character.digit`, so conversion does **not** restore an ASCII-only restriction. That conversion chain is visible in the pinned [Kotlin 2.3.21 integer parser](https://raw.githubusercontent.com/JetBrains/kotlin/v2.3.21/libraries/stdlib/src/kotlin/text/StringNumberConversions.kt) and [JVM digit implementation](https://raw.githubusercontent.com/JetBrains/kotlin/v2.3.21/libraries/stdlib/jvm/src/kotlin/text/CharJVM.kt).

**Device consequence:** given that release and an ordinary lower-version release, the non-ASCII tag can win `maxByOrNull { it.version }` and be offered as the newest Android update. The desktop regex excludes it before ranking. This is conditional input validation drift, not an arbitrary-code-execution claim or evidence of an existing malformed published release.

**Fix:** `^android-v?[0-9]+\.[0-9]+\.[0-9]+` and `v?([0-9]+)\.([0-9]+)\.([0-9]+)`. Add Android-runtime negative cases for Arabic-Indic, fullwidth and mixed-script digits, alongside ordinary tags, to `AndroidReleaseMatcherTest` and `AppVersionTest`. Preserve the existing suffix/search behavior; tightening unrelated semver rules is outside this finding.

## Risky-looking code that is compatible

### Regex semantics and unsupported constructs

- `works/WorkSearchIndex.kt:39`: `\p{InCombiningDiacriticalMarks}+` is **supported**, not an Android crash. `browse/FandomListScreen.kt:313` uses supported `\p{Mn}+`; `library/FavoriteAffinityRow.kt:110` uses supported `[^\p{L}\p{N}]+`.
- `reader/ReaderWorkActions.kt:25`: `[/\\\p{Cntrl}]` compiles. On Android its control class also covers C1 controls; removing them from a share filename is appropriate. It is not an unsupported `java…` property.
- Inline `(?i)` and `(?is)`, `RegexOption.IGNORE_CASE`, and `RegexOption.DOT_MATCHES_ALL` are supported on API 26+. The lookahead in `EpubImportMetadata.statValue` is supported. Interpolated regex pieces are constants/enums, or quoted with `Regex.escape` (see inventory), rather than arbitrary user-supplied regex.
- No production `(?U)`, other `U` inline flag, `UNICODE_CHARACTER_CLASS`, `CANON_EQ`, `\p{java…}`, `\p{Is…}`, `\R`, `\X`, `\h`, `\v`, named capture/backreference, possessive quantifier or atomic-group use was found. The brief's list is not a list of unsupported ICU features: several of those constructs are supported, but absent here.
- `\s+` normalization/splitting is Unicode-aware on-device. This generally improves handling of NBSP/em spaces in prose, metadata and search; it is not a compilation failure. `\S+` in spoken URL detection stops at Unicode whitespace. `\d` in counters/IDs is broader on Android; most captures are safely converted with nullable integer conversion. No additional harmful downstream outcome was established for those captures. `AO3SeriesUrls.isSeriesUrl` checks OkHttp's **encoded** path, so a Unicode digit is percent-encoded before its regex sees it.
- `.` is **not ASCII-only on the JDK**. Neither engine's normal dot means only ASCII; DOTALL permits line terminators. Likewise, JDK word-boundary behavior varies by JDK version, so a blanket “desktop `\b` is ASCII” conclusion is unsafe. The prose-heading/yes/no boundary patterns below have no demonstrated Android-only failure. The ICU reference above describes the Android-side semantics.
- Kotlin `String.split("/")`, `split(',')`, and literal `replace("…", "…")` are literal operations; they do not turn their strings into Java regexes. Pattern overloads pass explicit `Regex` objects and are included below. The one Jsoup selector regex is also listed.

### Java/API availability

| Candidate | Evidence and disposition |
|---|---|
| `java.time` | `Instant`, `Clock`, `Duration`, `LocalDate`, `LocalDateTime`, `ZonedDateTime`, `OffsetDateTime`, formatters and temporal helpers used here are present by API 26; configured desugaring also covers the ordinary time APIs. No unguarded later-only time member found. Examples: `auth/AO3Session.kt:71–73`, `network/ao3/AO3RetryAfter.kt:18`, `search/SearchFiltersCodec.kt:36`. |
| `Files`/`Path` | Every used `Files` member is API 26: `createDirectories`, `createTempFile`, `delete`, `deleteIfExists`, `exists`, `getLastModifiedTime`, `isDirectory`, `isRegularFile`, `move`, `newDirectoryStream`, `newInputStream`, `newOutputStream`, `readAllBytes`, `size`, `write`. Existing `Path.resolve/normalize/toFile/toAbsolutePath` and `File.toPath` calls are available. Examples: `files/WorkFileStore.kt:24–40`, `backup/BackupFileUndo.kt:15–27`. This does **not** rely on the separate NIO desugaring artifact. [Android Files reference](https://developer.android.com/reference/java/nio/file/Files). |
| Later JDK string/collection methods | `writing/WritingTextEditorScreen.kt:268` calls Kotlin `String.lines()` (returns a list), not Java `String.lines()` (returns a stream). Production `isBlank`, `toList`, `reversed` calls use Kotlin APIs. No `String.repeat/strip`, `List.of/Set.of/Map.of`, stream terminal call, `java.net.http.HttpClient`, `ProcessHandle`, `java.awt`, or `javax.swing` use found. The pinned desugar library even supports `Stream.toList`, but no production call depends on that. [Desugar 2.1.5 changelog](https://github.com/google/desugar_jdk_libs/blob/master/CHANGELOG.md). |
| `removeFirst/removeLast` | All five sites use **Kotlin `ArrayDeque`**: `comments/CommentComposerSheet.kt:330–335`, `comments/CommentThreadGeometry.kt:70–82`, `network/ao3/writing/AO3WordCounter.kt:14–18`, `network/ao3/AO3PageCache.kt:30–35`, `support/ShakeDetector.kt:152–158`. They invoke the deque's own methods, not API-35 `java.util.List` methods. The [Android 15 List compatibility warning](https://developer.android.com/about/versions/15/behavior-changes-15#openjdk-api-changes) therefore does not apply. |
| Newer Android framework calls | `writing/WritingNativeTextField.kt:62–66` guards API-29 cursor/selection drawable properties; `works/ExternalFileImport.kt:65–78` guards API-33 typed parcelable retrieval; `support/ShakeDetector.kt:257` guards API-31 `VibratorManager`. `reader/ReaderSearch.kt:31` passes a **String** to the old `BreakIterator.setText(String)` overload, not API-29 `setText(CharSequence)`. `account/WritingDraftsScreen.kt:221` uses `ContextCompat.registerReceiver`. No confirmed unguarded newer framework member found in the availability scan. |
| Overload/name false positives | `library/ReadingStatistics.kt:45` calls `ZonedDateTime.ofInstant`, not the later `LocalDate.ofInstant`; `works/EpubImportMetadata.kt:210` calls Kotlin `File.writeBytes`, not API-33 `ByteArrayOutputStream.writeBytes`; `backup/SyncRepository.kt:281` calls `Files.readAllBytes`, not API-33 `InputStream.readAllBytes`. URL encoding/decoding uses the old string-charset-name overloads (e.g. `app/NavArgCodecs.kt:26,37`). |

### Locale, charset, filesystem and process checks

| Candidate | Evidence and disposition |
|---|---|
| Parameterless case conversion | Kotlin `lowercase()`/`uppercase()` uses the invariant locale, unlike deprecated Java `toLowerCase()`/`toUpperCase()` without a locale. Cookie hosts, cache/account keys and URL schemes are therefore not Turkish-default-locale defects. Examples: `auth/AO3Session.kt:31–32`, `auth/AO3PostingPseudStore.kt:60`, `network/ao3/AO3URLResolver.kt:48–51`. No no-argument legacy Java conversion call found. [Kotlin lowercase contract](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.text/lowercase.html). |
| Formatting keys, URLs and stored data | `%02x` in `backup/BackupPaths.kt:187`, `backup/TombstoneSigning.kt:247`, comment-cache/recovery hashes, and `%02X` in `ui/subject/SubjectForm.kt:453` are hexadecimal, not localized decimal digits. Grouped `%,d` calls produce display labels, not URL IDs or persistence keys. Numeric URLs use string interpolation/conversion. Backup filename/time patterns use fixed numeric `DateTimeFormatter` patterns, not locale-grouped integer formatting. No confirmed machine-format locale bug found. |
| Charset defaults | Parameterless Kotlin `readText`, `writeText`, `toByteArray` use UTF-8; examples `auth/AO3SessionStore.kt:114,208`, `network/ao3/comments/CommentCache.kt:46,67`. Java string-from-byte constructors found here supply explicit ASCII/UTF-8/ISO-8859-1 charsets. `files/TextDecoding.kt:24–63` deliberately chooses strict decoders and BOM-gates UTF-16. No default-charset `FileReader/FileWriter/InputStreamReader/OutputStreamWriter` call found. |
| Two default temp-directory overloads | `works/EpubImportMetadata.kt:208` calls `File.createTempFile("incoming", ".epub")`; `backup/BackupImporter.kt:261` calls `Files.createTempFile(prefix, suffix)`. These deserve explicit cache-directory injection for predictable ownership, but **are not a confirmed normal-device failure**: Android's application startup sets `java.io.tmpdir` to the app cache before application code runs, already in [API-26 ActivityThread](https://android.googlesource.com/platform/frameworks/base/+/oreo-release/core/java/android/app/ActivityThread.java). Both callers clean up in `finally` (`works/EpubImportMetadata.kt:223`, `backup/BackupImporter.kt:320–321`). The comment at `works/converters/PDFWorkConverter.kt:105–108` is not sufficient evidence that default temp files always fail. No isolated/direct-boot caller was found for these operations. |
| Other file locations | `app/KudosAppContainer.kt:87–97,298` supplies app `filesDir`/`cacheDir`; update APKs use `update/AppUpdateInstaller.kt:44`; TTS temp downloads pass `applicationContext.cacheDir` at `reader/speech/TTSDownloadWorker.kt:81`. SAF sync uses `DocumentFile`/`ContentResolver`, not a document URI converted to a filesystem path. `backup/BackupScreen.kt:143–144` uses app-specific external Documents with internal fallback. |
| Absolute/system paths | `app/DemoLibrary.kt:287` reads `/system/fonts` inside a guarded fallback to seed a demo font; it does not write there. No production hard-link creation, `File.deleteOnExit`, shell subprocess, `ProcessBuilder`, `Runtime.exec`, home-directory assumption, or hardcoded `/tmp` write found. |
| Native loading | `works/converters/KudosMuPDF.kt:17–19` catches `System.loadLibrary("kudosmupdf")` failure; its wrappers return null when unavailable. Native ABI/page-size correctness is outside the Kotlin source audit and was not tested. This is not evidence that all packaged native libraries work on every device. |
| Blocking network calls | GitHub release/update and TTS synchronous OkHttp calls are inside `withContext(Dispatchers.IO)` (`network/github/GitHubReleaseClient.kt:32–40`, `update/AppUpdateInstaller.kt:57–63`, `reader/speech/TTSDownloadWorker.kt:66`). No main-thread network exception confirmed in these sites. They were inspected without making requests. |

## Follow-up verification to add when implementation is authorized

1. Apply F1/F2 in their existing shared helpers; add both host and **instrumented** Unicode-negative cases. Ordinary JVM tests will accept the fixed ASCII classes but cannot prove ICU behavior.
2. Run the affected cases on API 26 and a current Android runtime, without networking: collection validation/availability fakes, release matcher with constructed releases, and the listed regexes over representative Unicode input.
3. Expand `android/app/src/test/java/io/github/cidy02/kudos/RegexPortabilityTest.kt:13–20` beyond its exact `(?U)`/`UNICODE_CHARACTER_CLASS` source-string ban. At present it neither validates all inline flag combinations nor executes Android's regex engine. Keep the Android-runtime cases even if the source guard is broadened.

No source/test changes were made for these follow-ups. No device/build verification is implied by “complete” above; it describes completion of this read-only audit.

## Regex inventory — quoted patterns and Android behavior
Patterns below are the **evaluated pattern strings** (one backslash layer), with constructor options shown separately. Interpolations in the dynamic table retain the source placeholders. Every row uses supported ICU syntax on API 26+; the behavior codes describe the device result. Host probes support compilation only, not all semantic claims.
| Code | Device behavior / disposition |
|---|---|
| A | Compiles; ordinary literals/classes/groups/anchors. No Android-only defect established. `.` remains Unicode-capable; DOT_MATCHES_ALL includes line terminators. |
| D | Compiles; decimal digit escapes cover Unicode Nd, and `\D` its complement. Broader input than unflagged JDK; F2 identifies the harmful version-gate use. |
| S | Compiles; whitespace escapes cover Unicode whitespace, and `\S` its complement. Normalization/splitting/URL termination differs from desktop ASCII classes; no additional defect established. |
| W | Compiles; Unicode word class. For the history date classifier, ordinary English AO3 dates behave the same; F1 is the URL-name defect. |
| B | Compiles; ICU word boundary, with combining-mark handling. No demonstrated bad heading/metadata/yes-no result. |
| P | Compiles; the named property/block exists. Unicode categories/controls/diacritic removal work. |
| F1 / F2 | Compiles, but the confirmed validation difference is described above. |
### Direct non-interpolated constructors (112 sites)

| Location | Pattern | Constructor option | Device result |
|---|---|---|---|
| `account/AO3ChallengeSettingsEditScreen.kt:349` | `<[^>]+>` | — | A |
| `account/AO3ChallengeSettingsEditScreen.kt:349` | `\s+` | — | S |
| `account/AO3ChallengeSettingsEditScreen.kt:360` | `^(\d{4}-\d{2}-\d{2})(?:([ T])(\d{2}:\d{2})(:\d{2})?(\.\d+)?)?(.*)$` | — | D |
| `app/AppNavHost.kt:541` | `/users/([^/]+)/series` | — | A |
| `app/DemoLibrary.kt:688` | `<navMap>[\s\S]*?</navMap>` | — | S |
| `app/SeriesWorksScreen.kt:119` | `/series/([0-9]+)` | — | A |
| `auth/AO3WebLoginScreen.kt:178` | `"loggedIn"\s*:\s*true` | — | S |
| `auth/AO3WebLoginScreen.kt:179` | `"username"\s*:\s*"([^"]+)` | — | S |
| `backup/BackupPaths.kt:175` | `-restored-([1-9][0-9]*)` | — | A |
| `backup/BackupValidator.kt:23` | `^#[0-9A-Fa-f]{6}$` | — | A |
| `browse/FandomListScreen.kt:313` | `\p{Mn}+` | — | P |
| `comments/CommentsViewModel.kt:412` | `\d+` | — | D |
| `core/HtmlText.kt:5` | `(?i)<br\s*/?>\|</(p\|div\|li\|h[1-6])>` | — | S |
| `core/HtmlText.kt:6` | `<[^>]+>` | — | A |
| `core/HtmlText.kt:7` | `[ \t]+\n` | — | A |
| `core/HtmlText.kt:8` | `\n{3,}` | — | A |
| `library/FavoriteAffinityRow.kt:110` | `[^\p{L}\p{N}]+` | — | P |
| `library/ReadingAffinities.kt:132` | `[A-Za-z0-9_]+` | — | A |
| `network/ao3/AO3OverloadDetector.kt:21` | `\s+` | — | S |
| `network/ao3/DemoNetwork.kt:83` | `^/users/[^/]+(?:/pseuds/[^/]+)?(?:/(?:inbox\|profile\|works(?:/collected)?\|gifts\|series\|bookmarks))?/?$` | — | A |
| `network/ao3/DemoNetwork.kt:84` | `^/series/[0-9]+/?$` | — | A |
| `network/ao3/DemoNetwork.kt:230` | `^/tag_sets/(42\|43\|44)(?:/\|$)` | — | A |
| `network/ao3/DemoNetwork.kt:294` | `^/users/[^/]+/subscriptions/?$` | — | A |
| `network/ao3/DemoNetwork.kt:316` | `^/users/[^/]+/works/drafts/?$` | — | A |
| `network/ao3/DemoNetwork.kt:319` | `^/users/[^/]+/(pseuds/[^/]+/)?(works(/collected)?\|gifts)/?$` | — | A |
| `network/ao3/DemoNetwork.kt:326` | `^/comments/\d+$` | — | D |
| `network/ao3/DemoNetwork.kt:433` | `^/downloads/(99511[0-5]\|995120\|99900000[2-5])/work\.epub$` | — | A |
| `network/ao3/DemoNetwork.kt:445` | `^/works/\d+/bookmarks/?$` | — | D |
| `network/ao3/DemoNetwork.kt:506` | `^/tag_sets/(42\|43\|44)(?:/\|$)` | — | A |
| `network/ao3/DemoNetwork.kt:527` | `^/users/[^/]+/collection_items(?:/update_multiple)?/?$` | — | A |
| `network/ao3/DemoNetwork.kt:534` | `^/users/[^/]+/(blocked\|muted)/users(?:/\d+)?/?$` | — | D |
| `network/ao3/DemoNetwork.kt:575` | `^/users/[^/]+/subscriptions/[^/]+/?$` | — | A |
| `network/ao3/DemoNetwork.kt:594` | `^/works/\d+/mark_as_read/?$` | — | D |
| `network/ao3/DemoNetwork.kt:607` | `^/users/[^/]+/readings/clear/?$` | — | A |
| `network/ao3/DemoNetwork.kt:618` | `^/users/[^/]+/readings/\d+/?$` | — | D |
| `network/ao3/DemoNetwork.kt:647` | `^/tags/([^/]+)/works/?$` | — | A |
| `network/ao3/DemoNetwork.kt:655` | `^/users/[^/]+/subscriptions/?$` | — | A |
| `network/ao3/DemoNetwork.kt:727` | `^/users/AO3_Reader(?:/pseuds/[^/]+)?/works(?:/collected)?$` | — | A |
| `network/ao3/DemoNetwork.kt:753` | `^/users/AO3_Reader/works/(show_multiple\|edit_multiple\|update_multiple\|delete_multiple)$` | — | A |
| `network/ao3/DemoNetwork.kt:813` | `^/users/AO3_Reader(?:/pseuds/[^/]+)?/works(?:/collected\|/show_multiple\|/edit_multiple\|/update_multiple\|/delete_multiple)?$` | — | A |
| `network/ao3/DemoNetwork.kt:814` | `^/works/(995006\|995008\|995009)(?:/edit\|/edit_tags\|/update_tags\|/confirm_delete)?$` | — | A |
| `network/ao3/DemoNetwork.kt:818` | `^/works/(995006\|995008\|995009)/(?:edit_tags\|update_tags)$` | — | A |
| `network/ao3/DemoNetwork.kt:819` | `^/works/(995001\|995006\|995007\|995008\|995009)(?:/.*)?$` | — | A |
| `network/ao3/DemoNetwork.kt:865` | `^/works/(995001\|995006\|995007\|995008\|995009)(?:/edit\|/confirm_delete)?$` | — | A |
| `network/ao3/DemoNetwork.kt:1231` | `^collection_items\[(\d+)]` | — | D |
| `network/ao3/DemoNetwork.kt:1235` | `^/users/[^/]+/collection_items/update_multiple/?$` | — | A |
| `network/ao3/DemoNetwork.kt:1502` | `\[(?:anonymous\|any_fandom\|any_character\|any_relationship\|any_freeform\|_destroy)]$` | — | A |
| `network/ao3/DemoNetwork.kt:1556` | `^/serial_works/321[123]$` | — | A |
| `network/ao3/DemoWritingChapters.kt:18` | `^/works/(995006\|995001)/(chapters(?:/(?:new\|[0-9]+)(?:/(?:edit\|confirm_delete))?)?\|navigate)$` | — | A |
| `network/ao3/account/AO3AccountParser.kt:237` | `\s+` | — | S |
| `network/ao3/account/AO3ChallengeSettings.kt:84` | `/tag_sets/(\d+)(?:/\|$\|[?#])` | — | D |
| `network/ao3/account/AO3ChallengeSettings.kt:95` | `/signups/\d+(?:/\|$\|[?#])` | — | D |
| `network/ao3/account/AO3ChallengeSettings.kt:116` | `\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}(?::\d{2})?)?` | — | D |
| `network/ao3/account/AO3ChallengeSignUp.kt:148` | `/collections/[^/]+/signups(?:/[0-9]+)?/?$` | — | A |
| `network/ao3/account/AO3ChallengeSignUp.kt:189` | `/signups/([0-9]+)(?:/\|$)` | — | A |
| `network/ao3/account/AO3ChallengeSignUp.kt:198` | `\((\d+)(?:\s*-\s*(\d+))?\)` | — | D, S |
| `network/ao3/account/AO3CollectionForm.kt:48` | `^[A-Za-z0-9]\w*[A-Za-z0-9]$` | — | **F1** |
| `network/ao3/account/AO3CollectionItems.kt:178` | `^collection_items\[(\d+)]` | — | D |
| `network/ao3/account/AO3CollectionItems.kt:203` | `/works/(\d+)(?:[/?#]\|$)` | — | D |
| `network/ao3/account/AO3CollectionParser.kt:157` | `\s+` | — | S |
| `network/ao3/account/AO3HistoryVisit.kt:17` | `^\d{1,2} [A-Za-z]{3} \d{4}$` | — | D |
| `network/ao3/account/AO3PromptMeme.kt:81` | `(\d+) anonymous claimant` | — | D |
| `network/ao3/account/AO3ReadingEntry.kt:27` | `^\d{1,2} \w{3} \d{4}$` | — | D, W |
| `network/ao3/account/AO3ReadingEntry.kt:59` | `/readings/(\d+)` | — | D |
| `network/ao3/account/AO3ReadingEntry.kt:92` | `Visited (\d+) times` | IGNORE_CASE | D |
| `network/ao3/author/AO3AuthorModels.kt:44` | `^(.+) \(([A-Za-z0-9_]+)\)$` | — | A |
| `network/ao3/author/AO3AuthorParser.kt:176` | `/series/(\d+)` | — | D |
| `network/ao3/author/AO3AuthorParser.kt:243` | `/works/(\d+)` | — | D |
| `network/ao3/author/AO3AuthorParser.kt:354` | `\byes\b` | — | B |
| `network/ao3/author/AO3AuthorParser.kt:355` | `\bno\b` | — | B |
| `network/ao3/author/AO3AuthorParser.kt:372` | `\((\d[\d,]*)\)\s*$` | — | D, S |
| `network/ao3/browse/AO3BrowseParser.kt:82` | `\s+` | — | S |
| `network/ao3/browse/AO3BrowseParser.kt:115` | `\s+` | — | S |
| `network/ao3/comments/AO3CommentParser.kt:195` | `/chapters/(\d+)` | — | D |
| `network/ao3/comments/AO3CommentParser.kt:296` | `.*/comments/\d+/?$` | — | D |
| `network/ao3/comments/CommentVerification.kt:18` | `<\s*/?\s*[A-Za-z][^>]*>\|&(?:#\d+\|#[xX][0-9A-Fa-f]+\|[A-Za-z][A-Za-z0-9]+);` | — | D, S |
| `network/ao3/inbox/AO3InboxParser.kt:149` | `\s+` | — | S |
| `network/ao3/inbox/AO3InboxParser.kt:335` | `\s+` | — | S |
| `network/ao3/search/AO3FandomUnion.kt:28` | `^/tags/([0-9]+)/feed\.atom$` | — | A |
| `network/ao3/search/AO3FandomUnion.kt:35` | `\s+\([0-9,]+\)$` | — | S |
| `network/ao3/search/AO3FandomUnion.kt:42` | `[0-9]+` | — | A |
| `network/ao3/search/AO3SearchParser.kt:205` | `\s+` | — | S |
| `network/ao3/search/AO3SearchParser.kt:206` | `([\d,]+)\s+(Works\|Work\|Found)\b` | — | D, S, B |
| `network/ao3/search/AO3SearchParser.kt:214` | `([\d,]+)\s*-\s*([\d,]+)\s+of\s+$` | — | D, S |
| `network/ao3/search/AO3SearchParser.kt:254` | `\s+` | — | S |
| `network/ao3/series/AO3SeriesUrls.kt:56` | `/series/\d+/?` | — | D |
| `network/ao3/work/AO3WorkMetadataParser.kt:84` | `\s+` | — | S |
| `network/ao3/writes/AO3WriteFormParser.kt:251` | `\s+` | — | S |
| `network/ao3/writing/AO3ChapterFormParser.kt:55` | `^/works/[1-9][0-9]*/?$` | — | A |
| `network/ao3/writing/AO3ChapterFormParser.kt:99` | `^/works/[1-9][0-9]*/chapters(?:/[1-9][0-9]*)?/?$` | — | A |
| `network/ao3/writing/AO3SeriesFormParser.kt:25` | `^/series(?:/[0-9]+)?/?$` | — | A |
| `network/ao3/writing/AO3SeriesFormParser.kt:62` | `/works/([0-9]+)` | — | A |
| `network/ao3/writing/AO3WordCounter.kt:48` | `['’‘-]` | — | A |
| `network/ao3/writing/AO3WorkFormParser.kt:34` | `^/works(?:/[0-9]+(?:/(?:edit_tags\|update_tags))?)?/?$` | — | A |
| `reader/ReaderContentText.kt:80` | `\s+` | — | S |
| `reader/ReaderContentText.kt:81` | `(?:https?://\|www\.)\S+` | — | S |
| `reader/ReaderContentText.kt:101` | `\s+` | — | S |
| `reader/ReaderWorkActions.kt:25` | `[/\\\p{Cntrl}]` | — | P |
| `reader/ReaderWorkActions.kt:25` | `\s+` | — | S |
| `reader/speech/TextChunker.kt:122` | `\s+` | — | S |
| `update/AndroidReleaseMatcher.kt:23` | `^android-v?\d+\.\d+\.\d+` | IGNORE_CASE | **F2** |
| `update/AppVersion.kt:25` | `v?(\d+)\.(\d+)\.(\d+)` | — | **F2** |
| `works/EpubImportMetadata.kt:465` | `(?i)(?:https?://)?(?:www\.)?archiveofourown\.org/(?:works\|downloads)/(\d+)` | — | D |
| `works/WorkImporter.kt:420` | `/series/(\d+)` | — | D |
| `works/WorkSearchIndex.kt:39` | `\p{InCombiningDiacriticalMarks}+` | — | P |
| `works/WorkSearchIndex.kt:46` | `\s+` | — | S |
| `works/converters/ArchiveWorkConverter.kt:88` | `\d+\|\D+` | — | D |
| `works/converters/PDFWorkConverter.kt:74` | `\((.*?)\)` | DOT_MATCHES_ALL | A |
| `works/converters/PlainTextWorkConverter.kt:58` | `\n[ \t]*\n+` | — | A |
| `works/converters/PlainTextWorkConverter.kt:61` | `\n[ \t]*` | — | A |
| `works/converters/PlainTextWorkConverter.kt:70` | `^(chapter\|part\|prologue\|epilogue)\b.*` | IGNORE_CASE | B |
| `writing/WritingBufferPreview.kt:48` | `[\t\r ]+` | — | A |

### Dynamic constructors (9 sites)

| Location | Pattern template | Inputs / Android result |
|---|---|---|
| `network/ao3/DemoNetwork.kt:554` | `^/users/[^/]+/subscriptions(?:/$DEMO_AUTHOR_SUBSCRIPTION)?/?$` | Constant numeric subscription ID; A. |
| `network/ao3/DemoNetwork.kt:1532` | `^challenge_signup\[${kind}_attributes]\[([0-9]+)]` | `request`/`offer` enum strings; A. |
| `network/ao3/account/AO3ChallengeSignUp.kt:156` | `^${Regex.escape(prefix)}\[([0-9]+)]` | Constant/enum field prefix quoted with `Regex.escape`; A. ICU accepts `\Q…\E` quoting. |
| `network/ao3/account/AO3ChallengeSignUps.kt:61` | `/$resource/(\d+)(?:/\|$\|[?#])` | Constant resource names (`signups`, `assignments`); D. |
| `network/ao3/account/AO3HistoryVisit.kt:43` | `^(?:about\s+)?(\d+)\s+$unit` | Constant `day`/`month`; D, S. |
| `network/ao3/account/AO3PromptMeme.kt:58` | `/$resource/(\d+)(?:/\|$\|[?#])` | Constant `prompts`/`claims`; D. |
| `network/ao3/writing/AO3WorkActions.kt:53` | `(\d[\d,]*)\s+$label` | Constant count labels; IGNORE_CASE; D, S. |
| `network/ao3/writing/AO3WorkFormParser.kt:200` | `(?:^\|/)$kind/([0-9]+)(?:[/?#]\|$)` | Constant `series`/`serial_works`; A. |
| `works/EpubImportMetadata.kt:396` | `(?is)\b$label:\s*(.+?)(?=\s+(?:$nextLabel):\|$)` | Constant stat labels/alternation; supported `(?is)` and lookahead; S, B. |

### Jsoup selector regex

| Location | Embedded pattern | Device result |
|---|---|---|
| `network/ao3/account/AO3CollectionParser.kt:34` | `(?i)^Maintainers?:$` inside `:matchesOwn(...)` | A; inline case flag is supported. |

### Indirect demo route table (71 patterns)

These strings feed `Regex(pattern)` at `network/ao3/DemoNetwork.kt:227`. They are fixed offline-demo routing rules; all compiled in the host probe. D retains the Unicode-digit caveat; no production validation conclusion is inferred from a demo route.

| Location in `network/ao3/DemoNetwork.kt` | Pattern | Device result |
|---|---|---|
| `:155` | `^/works/995006/chapters/new/?$` | A |
| `:156` | `^/works/995006/chapters/12302/edit/?$` | A |
| `:157` | `^/works/995006/chapters/12302/confirm_delete/?$` | A |
| `:158` | `^/works/995001/chapters/new/?$` | A |
| `:159` | `^/works/995001/chapters/12311/edit/?$` | A |
| `:160` | `^/works/995001/chapters/12311/confirm_delete/?$` | A |
| `:161` | `^/works/new` | A |
| `:162` | `^/works/995001/edit/?$` | A |
| `:163` | `^/works/995006/edit/?$` | A |
| `:164` | `^/works/995006/edit_tags/?$` | A |
| `:165` | `^/works/\d+/edit` | D |
| `:166` | `^/works/995006/navigate/?$` | A |
| `:167` | `^/works/\d+/navigate` | D |
| `:168` | `comments` | A |
| `:169` | `^/works/45678901/?$` | A |
| `:170` | `^/works/12345/?$` | A |
| `:171` | `^/works/999000002/?$` | A |
| `:172` | `^/works/999000003/?$` | A |
| `:173` | `^/works/\d+` | D |
| `:174` | `edit_multiple` | A |
| `:175` | `^/series/321/edit/?$` | A |
| `:176` | `^/series/321/manage/?$` | A |
| `:177` | `^/series/321/?$` | A |
| `:178` | `^/series/\d+/edit` | D |
| `:179` | `^/series/999/?$` | A |
| `:180` | `^/collections/new/?$` | A |
| `:181` | `^/collections/winter_exchange/edit/?$` | A |
| `:182` | `^/collections/winter_exchange/confirm_delete/?$` | A |
| `:183` | `^/collections/winter_exchange/signups/new/?$` | A |
| `:184` | `^/collections/winter_exchange/signups/4/edit/?$` | A |
| `:185` | `^/collections/summer_meme/signups/new/?$` | A |
| `:186` | `^/collections/[^/]+/signups/\d+` | D |
| `:187` | `^/collections/[^/]+/signups` | A |
| `:188` | `^/collections/[^/]+/assignments` | A |
| `:189` | `^/collections/[^/]+/(gift_exchange\|prompt_meme)` | A |
| `:190` | `^/collections/winter_exchange/items` | A |
| `:191` | `^/collections/[^/]+/items` | A |
| `:192` | `^/collections/[^/]+/participants` | A |
| `:193` | `^/collections/[^/]+/profile` | A |
| `:194` | `^/collections/[^/]+/edit` | A |
| `:195` | `^/collections/[^/]+/requests` | A |
| `:196` | `^/collections/[^/]+/works` | A |
| `:197` | `^/collections/winter_exchange/bookmarks/?$` | A |
| `:198` | `^/collections/winter_exchange/people/?$` | A |
| `:199` | `^/collections/[^/]+/?$` | A |
| `:200` | `^/users/[^/]+/collections` | A |
| `:201` | `^/users/[^/]+/collection_items` | A |
| `:202` | `^/tag_sets/\d+` | D |
| `:203` | `^/media/[^/]+/fandoms` | A |
| `:204` | `^/media/?$` | A |
| `:205` | `^/tags/[^/]+/works` | A |
| `:206` | `^/works/search` | A |
| `:207` | `^/users/[^/]+/works/drafts/?$` | A |
| `:208` | `^/users/[^/]+/(pseuds/[^/]+/)?works` | A |
| `:209` | `^/users/[^/]+/(pseuds/[^/]+/)?gifts` | A |
| `:210` | `^/users/[^/]+/(pseuds/[^/]+/)?series` | A |
| `:211` | `^/users/AO3_Reader/bookmarks/?$` | A |
| `:212` | `^/users/[^/]+/(pseuds/[^/]+/)?bookmarks` | A |
| `:213` | `^/users/[^/]+/readings/confirm_clear` | A |
| `:214` | `^/users/[^/]+/readings` | A |
| `:215` | `^/users/[^/]+/subscriptions` | A |
| `:217` | `^/users/[^/]+/blocked/confirm` | A |
| `:218` | `^/users/[^/]+/muted/confirm` | A |
| `:219` | `^/users/[^/]+/inbox` | A |
| `:220` | `^/users/[^/]+/preferences` | A |
| `:221` | `^/users/[^/]+/stats` | A |
| `:222` | `^/users/[^/]+/profile` | A |
| `:223` | `^/users/[^/]+/pseuds/[^/]+/?$` | A |
| `:224` | `^/users/[^/]+/?$` | A |
| `:225` | `^/help/preferences_privacy` | A |
| `:226` | `^/?$` | A |
