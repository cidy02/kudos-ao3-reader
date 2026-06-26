# Kudos Android Port Comprehensive Plan

**Document purpose:** define the plan for porting Kudos to Android while preserving identical core behavior with the Apple app.

**Core rule:** the Android UI should be native Android, but the domain logic, AO3 behavior, saved-work semantics, reader state, settings semantics, and backup format must behave as one shared product.

**Target outcome:** a user should be able to move between iOS/iPadOS/macOS and Android with the same library, same saved work metadata, same reading progress where supported, same user tags, same collections, same reader settings, and the same `.kudosbackup` file.

---

## Revision Notes — Claude Review Integration

This revision incorporates the technical review notes from Claude and tightens the plan in the areas most likely to cause cross-platform drift.

Key changes:

- Replaces any implication of byte-for-byte JSON equality with semantic contract equality, because Swift and Kotlin serialization will differ in key ordering, floating-point formatting, optionals/nulls, and date encodings.
- Adds explicit backup serialization compatibility rules, including support for both ISO-8601 dates and Swift `Date` default numeric encoding where existing v1 manifests require it.
- Clarifies UUID normalization: UUID strings must be compared case-insensitively and serialized canonically to avoid duplicate restored works.
- Clarifies reader progress portability: Readium locators are engine/platform-specific; cross-platform resume must rely on continuously maintained `lastSpineIndex` and `lastScrollFraction` fallback fields.
- Adds Android platform constraints for Readium: minimum SDK decision, core library desugaring if targeting below API 26, Fragment/View navigator interop with Compose, and release-build keep-rule risks.
- Replaces `EncryptedSharedPreferences` as the default session-storage recommendation with an encrypted DataStore/Tink/Android Keystore design and explicit Android Auto Backup exclusions.
- Adds AO3 overload/capacity-page detection as a parser/networking requirement.
- Adds release-risk tracking for Google Play distribution, AO3 policy review, GPL/third-party notices, localization, accessibility, and R8/minification smoke testing.
- Adds a dedicated multi-AI collaboration protocol so Claude and Codex can work safely without overwriting each other or drifting from the contract.
- Incorporates Codex Phase 0 repo-specific corrections: actual source root paths, current Apple v1 backup facts, current search sort enum, current subscription URL, current WorkCollection/SavedSearch field names, and AO3 concurrency parity.
- Resolves the branch-policy conflict: Android port work must happen on the dedicated branch `kudos-ao3-reader-android`; `main` remains protected/reference for this effort unless the human explicitly approves a merge.
- Marks v2 backup fields such as `comments`, `hits`, `knownChapterCount`, `lastUpdateCheck`, `collections`, and `savedSearches` as deliberate v2 additions, not existing v1 parity fields.

## 1. Executive Summary

Kudos currently exists as a native Apple app using SwiftUI and SwiftData. Android should be a sibling native implementation, not a SwiftUI translation.

The Android app should use:

- Kotlin
- Jetpack Compose
- Material 3
- Room
- DataStore
- OkHttp
- Jsoup
- Coroutines / Flow
- Readium Kotlin Toolkit
- Android WebView / CookieManager
- Android BiometricPrompt
- Android Storage Access Framework

The UI can and should follow Android platform conventions. However, the behavioral layer must be treated as a compatibility contract. The Apple app becomes the reference implementation until a formal cross-platform contract is extracted into project docs and fixture tests.

The most important addition to the initial plan is this:

> The Android port must not merely “match features.” It must implement the same state machine, the same backup schema, the same model meanings, the same AO3 URL/query behavior, and the same merge/restore behavior.

---

## 2. Non-Negotiable Compatibility Goals

### 2.1 Same User-Visible Experience

The Android app does not need to look like SwiftUI. It does need to feel like the same product.

Equivalent behavior means:

- A work saved on iOS appears the same on Android.
- User tags have the same meaning.
- Favorites have the same meaning.
- Finished/unread/reading states behave the same.
- Search filters produce the same AO3 requests.
- Work cards show the same important metadata.
- Work Detail exposes the same actions.
- Reader settings map to equivalent reading behavior.
- Backups can be exported on one platform and restored on the other.
- AO3 account actions follow the same safety and retry rules.
- Mature content privacy settings mean the same thing.

### 2.2 Platform-Native UI Is Allowed

Android does not need to imitate:

- SwiftUI navigation chrome
- Apple tab/sidebar behavior
- SF Symbols
- Liquid Glass styling
- iOS inspector panels
- macOS layout idioms

Android should use:

- Compose Material 3
- Android bottom navigation on phones
- navigation rail or adaptive layout on tablets/foldables
- Android system back behavior
- Android share sheet
- Android document picker
- Android biometric/device credential prompt
- Android typography and spacing conventions

### 2.3 Core Logic Must Be Identical

The following must behave the same unless a difference is explicitly documented as a platform limitation:

- AO3 request construction
- Search filter transformation
- Retry and rate-limit behavior
- Work metadata normalization
- Tag grouping and ordering
- Download/import state transitions
- Saved-work persistence semantics
- Reader progress persistence
- Backup export/import
- Merge restore behavior
- Settings defaults and value ranges
- Auth session handling rules
- Authenticated AO3 write safety rules

---

## 3. Source-of-Truth Strategy

### 3.0 Repo-Specific Path Correction

In the current repo, the Apple app source root is:

```text
kudos-ao3-reader/
```

Do not use the older placeholder path `AO3_App_OpenSource/...` inside plan docs, prompts, or task instructions. Phase 0 must correct any stale path references before Android scaffolding begins.

### 3.1 Short-Term Source of Truth

Until shared contract docs exist, the Apple implementation is the reference for behavior.

Claude should inspect these areas before implementing Android equivalents:

```text
README.md
AGENTS.md
TASKS.md
docs/PROJECT_PHILOSOPHY.md
docs/AO3Authentication.md
docs/EPUBParsing.md
docs/Kudos_Layout_Structure.md

kudos-ao3-reader/App/
kudos-ao3-reader/Models/
kudos-ao3-reader/Services/
kudos-ao3-reader/Reading/
kudos-ao3-reader/Features/
kudos-ao3-reader/Settings/
kudos-ao3-reader/UIComponents/
KudosTests/
```

### 3.2 Formalize the Cross-Platform Contract

Add these docs as part of the Android port:

```text
docs/android/ANDROID_PORT_PLAN.md
docs/contracts/CORE_BEHAVIOR_CONTRACT.md
docs/contracts/BACKUP_FORMAT.md
docs/contracts/AO3_BEHAVIOR_CONTRACT.md
docs/contracts/READER_STATE_CONTRACT.md
docs/contracts/SETTINGS_CONTRACT.md
docs/contracts/UI_PARITY_CHECKLIST.md
```

The Android app should be implemented against these docs, and the Apple app should eventually be checked against them too.

### 3.3 Fixture-Driven Equivalence

Create a cross-platform fixture suite:

```text
contracts/
  fixtures/
    ao3/
      search_basic.html
      search_filtered.html
      work_detail_basic.html
      work_detail_series.html
      work_detail_locked.html
      bookmarks.html
      history.html
      subscriptions.html
      comments_chapter.html
    epub/
      sample.epub
      sample_with_series.epub
      sample_unicode_metadata.epub
    backup/
      v1_ios_package/
      v2_zip_basic.kudosbackup
      v2_zip_full.kudosbackup
      unsupported_version.kudosbackup
    expected/
      search_basic.json
      work_detail_basic.json
      backup_manifest_basic.json
      imported_work_basic.json
```

Both platforms should have tests that parse the same fixtures and produce the same expected JSON.

---

## 4. Compatibility Classification

Not everything needs identical implementation. Everything does need clear classification.

| Area | Android Can Differ? | Required Parity |
|---|---:|---|
| Visual styling | Yes | Same information hierarchy and actions |
| Navigation mechanics | Yes | Same reachable destinations and back behavior intent |
| Icons | Yes | Same action meanings |
| Search UI layout | Yes | Same AO3 query output |
| Work cards | Partially | Same metadata content and action availability |
| Work Detail | Partially | Same content and actions |
| SavedWork model | No | Same field meanings and backup serialization |
| Tags/collections | No | Same semantics and merge behavior |
| AO3 networking | No | Same politeness, retries, URL/query semantics |
| AO3 parsing | No | Same normalized output from fixtures |
| EPUB reader engine | Yes | Same progress/settings semantics where supported |
| Backup format | No | Must be cross-platform |
| Settings storage | Yes | Same setting names/values in backups |
| Privacy gate UI | Yes | Same security meaning |
| Auth UI | Yes | Same password/session handling rules |
| Authenticated writes | No | Same safety rules and POST behavior |

---

## 5. Recommended Android Architecture

### 5.1 Repo Layout

Create a sibling Android project under `android/`.

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle/
    libs.versions.toml
  app/
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      java/io/github/cidy02/kudos/
        KudosApplication.kt
        MainActivity.kt

        app/
          AppGraph.kt
          AppNavHost.kt
          AppRouter.kt
          MainScaffold.kt

        core/
          model/
          result/
          time/
          logging/
          dispatchers/
          html/
          files/
          contracts/

        data/
          local/
            KudosDatabase.kt
            entity/
            dao/
            migrations/
            converters/
          repository/
          preferences/

        network/
          ao3/
            AO3Client.kt
            AO3RequestCoordinator.kt
            RequestCoalescer.kt
            AO3Urls.kt
            AO3Parsers.kt
            AO3SearchQueryBuilder.kt
            AO3Errors.kt
            AO3AuthenticatedClient.kt

        auth/
          AO3AuthRepository.kt
          AO3CookieJar.kt
          AO3SessionStore.kt
          AO3WebLoginScreen.kt

        reader/
          ReadiumModule.kt
          ReaderRepository.kt
          ReaderScreen.kt
          ReaderSettingsMapper.kt
          LocatorStore.kt

        backup/
          KudosBackup.kt
          BackupManifest.kt
          BackupExporter.kt
          BackupImporter.kt
          BackupMergeService.kt
          BackupCompatibility.kt

        works/
          WorkRepository.kt
          WorkImporter.kt
          WorkLifecycle.kt
          WorkUpdateChecker.kt
          WorkTags.kt

        search/
        browse/
        library/
        home/
        account/
        bookmarks/
        comments/
        settings/
        privacy/
        ui/
          components/
          theme/
          adaptive/
    src/test/
    src/androidTest/
```

### 5.2 Package Name

Use:

```text
io.github.cidy02.kudos
```

### 5.3 App Module First

Start with one Android app module. Avoid premature multi-module complexity.

Later, split only if useful:

```text
:android:app
:android:core
:android:data
:android:network
:android:reader
:android:backup
```

### 5.4 Dependency Guidance

Pin versions in `libs.versions.toml`.

Recommended dependencies:

- Android Gradle Plugin
- Kotlin
- Kotlin serialization
- Compose BOM
- Material 3
- Navigation Compose
- Lifecycle ViewModel Compose
- Room runtime / KSP compiler
- DataStore Preferences or Proto DataStore
- OkHttp
- Jsoup
- Readium Kotlin Toolkit
- AndroidX Biometric
- WorkManager, if background update checks are eventually introduced
- JUnit
- Truth or AssertJ
- MockWebServer
- Turbine for Flow tests
- Robolectric where helpful

Do not add dependency injection complexity unless needed. A simple manual `AppGraph` is acceptable for the first port. However, make the decision deliberately before Phase 4. If the manual graph starts spreading across many features, consider Hilt before the app has too many hand-wired singletons. Do not retrofit dependency injection in the middle of backup, auth, or reader work unless there is a clear payoff.

### 5.5 Android Platform and Readium Constraints

These constraints must be settled during Phase 0/Phase 1, before the Android implementation grows around assumptions that are expensive to reverse.

#### Minimum SDK

Recommended starting point:

```text
minSdk = 26
targetSdk = current stable Android SDK supported by the toolchain
compileSdk = current stable Android SDK supported by the toolchain
```

Reasoning:

- API 26 simplifies Java time/date handling, biometric/device-credential behavior, and Readium integration.
- If older Android support is important, use `minSdk = 24` or `minSdk = 21`, but explicitly enable core library desugaring in the app module.
- Do not choose a lower minSdk by accident. Make the device-support tradeoff explicit in `docs/android/ANDROID_PORT_PLAN.md`.

If `minSdk < 26`, Gradle must include:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:<pinned-version>")
}
```

#### Readium Integration

Readium Kotlin should be treated as a View/Fragment integration risk, not a pure Compose component.

Plan for:

- Readium navigator hosted through Fragment/View interop.
- A dedicated `ReaderActivity` or a dedicated Compose screen hosting a `FragmentContainerView`.
- Lifecycle-aware publication opening/closing.
- Testing rotations, process death, back navigation, and theme changes.
- Avoiding assumptions that Readium locators are directly compatible with iOS reader positions.

Recommended first pass:

```text
Reader shell: Compose
Navigator: Readium Fragment/View layer
Reader chrome: Compose overlay or sibling UI
Progress bridge: ReaderRepository writes both platform locator and fallback progress fields
```

#### Licensing and Notices

Phase 0 must confirm:

- The current Kudos repo license.
- Readium Kotlin license and notice obligations.
- All Android dependency licenses.
- About/licenses screen requirements.
- Whether GPL distribution obligations require source-distribution links inside the Android app listing or About screen.

#### R8 / Minification

Before release builds are enabled, add smoke tests and keep rules for:

- Readium classes used reflectively or by Android components.
- Kotlin serialization models used by backup import/export.
- Room schema and migrations.
- Jsoup parsing if proguarded method/field access becomes relevant.
- WebView login bridge code, if any bridge is introduced.

#### Distribution Risk

Track but do not overstate these risks:

- Google Play policy review for apps displaying scraped AO3 content.
- AO3/OTW policy and infrastructure-safety expectations.
- Mature/explicit content handling in stores.
- Whether side-loading, F-Droid, GitHub Releases, or Play distribution is the intended first release channel.

---

## 6. Cross-Platform Core Contract

### 6.1 Contract Rule

The app should define a language-neutral contract for core behavior.

Swift and Kotlin do not share code directly, but they can share:

- JSON fixtures
- Expected outputs
- Backup manifests
- Parser HTML fixtures
- EPUB fixtures
- Search query test vectors
- Settings test vectors

### 6.2 Required Contract Test Categories

```text
AO3SearchQueryContractTests
AO3ParserContractTests
AO3UrlContractTests
AO3RetryContractTests
SavedWorkContractTests
WorkImporterContractTests
ReaderStateContractTests
BackupFormatContractTests
BackupMergeContractTests
SettingsContractTests
PrivacyContractTests
```

### 6.3 Golden Test Pattern

For each core behavior:

1. Input is stored as JSON, HTML, EPUB, or backup fixture.
2. iOS test produces a normalized JSON output.
3. Android test produces a normalized JSON output.
4. The outputs must be semantically equivalent according to the contract.
5. Differences must be documented and explicitly accepted.

Do **not** require raw byte-for-byte equality for general Swift/Kotlin JSON output. Byte-for-byte equality is only appropriate for intentionally canonicalized files, such as a v2 manifest after both platforms agree on canonical key ordering, date encoding, null handling, numeric formatting, and path ordering.

Example:

```text
contracts/fixtures/search/advanced_filters_input.json
contracts/expected/search/advanced_filters_url.json
```

Both platforms should assert:

- Same URL path
- Same query item names
- Same query item values
- Same transformed search text
- Same page value
- Same omitted empty fields

Backup and settings tests should assert normalized semantic equality:

- UUIDs canonicalized to lowercase.
- Dates normalized to UTC instants.
- Floating-point values compared within a small tolerance where relevant.
- Missing optional values and explicit `null` treated according to the manifest version contract.
- List ordering preserved only where the contract says order is user-visible or semantically meaningful.

---

## 7. Product Navigation and UI Parity

### 7.1 Product Direction

Target Android sections:

- Home
- Library
- Browse
- Account

Search should be a global action, not merely a content tab. Bookmarks can appear in Library and Account depending on type:

- Local bookmarks/saved links: Library or Account sub-section
- AO3 account bookmarks: Account
- Saved works/favorites: Library

If the current Apple branch still exposes Search and Bookmarks as full tabs, Android should follow the current product direction while preserving all underlying features.

### 7.2 Android Navigation

Phone:

- Bottom navigation for Home / Library / Browse / Account
- Search action in top app bar
- Reader full-screen
- Work Detail as a destination
- Filters as modal bottom sheets or side sheets

Tablet/foldable:

- Navigation rail or permanent navigation drawer
- Search may become a prominent top-level field/action
- Work Detail can use two-pane layouts
- Library list + detail split view where appropriate

### 7.3 Same Information Architecture

Even if layout differs, all major flows must exist:

```text
Home
  Continue Reading
  Recently Added
  Recently Updated
  Favorite works
  Saved searches / quick discovery if implemented

Library
  All saved works
  Favorites
  Finished
  Reading
  Unread
  User Tags
  Collections
  Reading History
  Local Bookmarks
  Filters and sort

Browse
  AO3 native browse/search entry points
  Browse by fandom
  Tag/fandom work lists
  AO3 WebView fallback

Account
  Login/session state
  Marked for Later
  AO3 Bookmarks
  AO3 History
  Subscriptions
  My Works
  Collections where supported
  Account settings/actions
```

### 7.4 Work Detail Consistency

Work Detail must have one canonical implementation shared across entry points:

- Home
- Library
- Browse
- Search
- Bookmarks
- Account lists
- Series lists
- Tag lists

Do not create separate Work Detail implementations for saved works and search results. Use a single screen model that can be hydrated from either local data or AO3 result data.

---

## 8. Domain Model Parity

### 8.1 SavedWork

Android Room entity must preserve the same field meanings as the Apple `SavedWork` model and backup schema.

Required fields:

```text
id: UUID/String
title: String
author: String
summary: String
sourceURL: String
dateAdded: Instant
isFavorite: Boolean
isSaved: Boolean
isFinished: Boolean
hasEPUB: Boolean
isComplete: Boolean
rating: String
language: String
wordCount: Int
chapters: String
kudos: Int
comments: Int? / Int
hits: Int? / Int
workWarnings: List<String>
workCategories: List<String>
seriesTitle: String
seriesPosition: Int
seriesURL: String
lastSpineIndex: Int
lastScrollFraction: Double
lastReadDate: Instant?
knownChapterCount: Int?
lastUpdateCheck: Instant?
workTags: List<String>
workFandoms: List<String>
workCharacters: List<String>
workRelationships: List<String>
workFreeforms: List<String>
workTagsFetched: Boolean
readiumLocator: String?
```

If Apple currently lacks `comments`, `hits`, `knownChapterCount`, or `lastUpdateCheck` in backup v1, Android should support them internally but only write them to a backup version that both platforms understand.

### 8.2 User Tags

User tags are user-created organizational labels.

Rules:

- Trim whitespace.
- Empty tags are invalid.
- Duplicates collapse by exact normalized name.
- Existing restore behavior should preserve names.
- Tag assignment is many-to-many.
- Backup stores assigned user tag names per work.

Recommended Room structure:

```text
TagEntity(
  id: String,
  name: String,
  dateCreated: Instant
)

WorkTagCrossRef(
  workId: String,
  tagId: String
)
```

### 8.3 Collections

If Apple has or adds collections, Android should match.

Recommended semantics:

- Collections are user-created groups of saved works.
- Collections are local app data, not necessarily AO3 collections.
- A work can be in multiple collections.
- Collection names are user-visible and must be included in cross-platform backup.
- Deleting a collection does not delete works.

Backup v2 should include collections explicitly.

### 8.4 Bookmarks

There are two concepts:

1. Local bookmarks / saved links inside Kudos.
2. AO3 account bookmarks.

They should not be conflated.

Local backup v1 contains:

```text
title
urlString
dateAdded
```

Android should preserve this. AO3 account bookmarks should be retrieved from AO3 and can be cached, but must be marked as AO3-derived/account data.

### 8.5 Custom Fonts

Custom fonts must be portable.

Rules:

- Store font file in app-private storage.
- Backup stores metadata plus file bytes.
- `readerFontID = "custom:<fileName>"` must resolve after restore only if the font file exists.
- If missing, fall back to `system`.
- Filenames must be sanitized and treated as untrusted input.

---

## 9. Room Schema Design

### 9.1 Core Entities

```kotlin
@Entity(tableName = "works")
data class WorkEntity(
    @PrimaryKey val id: String,
    val title: String,
    val author: String,
    val summary: String,
    val sourceUrl: String,
    val dateAdded: Instant,
    val isFavorite: Boolean,
    val isSaved: Boolean,
    val isFinished: Boolean,
    val hasEpub: Boolean,
    val isComplete: Boolean,
    val rating: String,
    val language: String,
    val wordCount: Int,
    val chapters: String,
    val kudos: Int,
    val comments: Int?,
    val hits: Int?,
    val seriesTitle: String,
    val seriesPosition: Int,
    val seriesUrl: String,
    val lastSpineIndex: Int,
    val lastScrollFraction: Double,
    val lastReadDate: Instant?,
    val knownChapterCount: Int?,
    val lastUpdateCheck: Instant?,
    val workTagsFetched: Boolean,
    val readiumLocator: String?
)
```

Store lists either as JSON columns or normalized tables. Recommended:

- User tags: normalized.
- Collections: normalized.
- AO3 tag groups: JSON string columns are acceptable in v1 Android if indexed filtering is not needed.
- If Library filters need fast tag filtering, normalize AO3 tags too.

### 9.2 AO3 Tag Tables

Option A: JSON columns:

```text
workWarningsJson
workCategoriesJson
workFandomsJson
workCharactersJson
workRelationshipsJson
workFreeformsJson
workTagsJson
```

Option B: normalized:

```text
ao3_tags
work_ao3_tag_cross_ref
```

For long-term search/filtering, normalized is better.

Recommended compromise:

- Use normalized tables for user tags and collections.
- Use JSON for AO3 metadata initially.
- Add indexes or normalization later if performance requires it.

### 9.3 DAOs

Required DAOs:

```text
WorkDao
TagDao
CollectionDao
BookmarkDao
CustomFontDao
SavedSearchDao
ReadingHistoryDao
DownloadQueueDao
```

### 9.4 Migrations

Never use destructive migrations for user data.

Add migration tests from every schema version.

---

## 10. Settings Contract

### 10.1 Storage

Apple stores settings in `UserDefaults`. Android should store settings in DataStore.

The backup contract, not the platform storage API, defines setting names and values.

### 10.2 Backup Settings Fields

The current backup settings contract includes:

```text
readerFontID: String
readerMode: String
readerTwoPage: Boolean
readerCustomize: Boolean
readerBoldText: Boolean
readerFontPt: Double
readerLineHeight: Double
readerLetterSpacing: Double
readerWordSpacing: Double
readerMargin: Double
readerJustify: Boolean
confirmBeforeDelete: Boolean
hideMatureContent: Boolean
matureContentMode: String
requireBiometricToReveal: Boolean
appTheme: String
readerTheme: String
matchAppReaderTheme: Boolean
accentColorHex: String
```

Android must use the same names in backups.

### 10.3 Defaults

Default values must match Apple behavior:

```text
readerFontID = "system"
readerMode = "scroll"
readerTwoPage = false
readerCustomize = false
readerBoldText = false
readerLetterSpacing = 0
readerWordSpacing = 0
readerJustify = false
confirmBeforeDelete = true
hideMatureContent = true
requireBiometricToReveal = false
matchAppReaderTheme = true
accentColorHex = AO3 red
```

For numeric defaults such as font size, line height, and margin, Android must either:

- match the Apple numeric defaults exactly, or
- define a conversion table if platform units differ.

### 10.4 Reader Unit Mapping

Because iOS points and Android sp may not render identically, use a compatibility mapping.

Store cross-platform values as semantic values:

```text
readerFontPt: backup numeric reference value
androidFontScale: derived value
iosFontPointSize: derived value
```

Do not change backup field names unless introducing backup v2+.

### 10.5 Theme Values

Allowed app/reader theme values:

```text
light
sepia
dark
system
```

If Apple currently only stores `light`, `sepia`, `dark`, Android can support `system` internally but should not write it to a v1 backup unless Apple supports it.

---

## 11. Backup Format Contract

This is the most important cross-platform requirement.

### 11.0 Current Repo Backup Facts

Phase 0 must record these facts from the current Apple implementation before Android models are scaffolded:

| Area | Current Apple v1 fact |
|---|---|
| Container | Directory-backed `.kudosbackup` package |
| Manifest | `manifest.json` |
| Dates | ISO-8601, using the current exporter’s configured date encoding |
| JSON output | Deterministic/sorted keys where current exporter uses that strategy |
| Work files | `Works/<UUID>.epub` |
| Font files | `Fonts/<fileName>` |
| Included top-level arrays | `works`, `bookmarks`, `fonts` |
| Included settings | Existing reader/app settings fields only |
| Not included in v1 | `collections`, `savedSearches`, `comments`, `hits`, `knownChapterCount`, `lastUpdateCheck` |

Do not treat Swift model fields that are absent from the v1 manifest as existing backup parity fields. They may be added deliberately in v2, but only behind explicit compatibility tests.

### 11.1 Current Apple Backup v1

Current backup v1 is a directory-backed `.kudosbackup` package.

Current structure:

```text
<backup>.kudosbackup/
  manifest.json
  Works/
    <workUUID>.epub
  Fonts/
    <fontFileName>
```

Current manifest shape:

```json
{
  "version": 1,
  "exportedAt": "ISO-8601 date string",
  "works": [],
  "bookmarks": [],
  "fonts": [],
  "settings": {}
}
```

Current restore behavior:

- Reject invalid package.
- Reject unsupported version.
- Restore/merge works by UUID.
- Restore/merge bookmarks by URL string.
- Restore/merge fonts by file name.
- Restore user tags by tag name.
- Write EPUB files atomically.
- If an EPUB is not present and no file exists locally, mark `hasEPUB = false`.
- Apply settings after restore.
- If `readerFontID` references a missing custom font, reset to `system`.
- Sanitize font filenames.

Android must be able to read this format where the platform file picker makes it available.

### 11.2 Problem: iOS Packages Are Not Ideal Cross-Platform Files

An Apple document package is directory-backed. It behaves like a file in Apple file pickers, but it is fundamentally a folder. Android’s Storage Access Framework is more reliable with a single archive file.

Therefore, a true cross-platform backup should become:

```text
<backup>.kudosbackup
```

where the file is a ZIP archive containing:

```text
manifest.json
Works/
  <workUUID>.epub
Fonts/
  <fontFileName>
```

### 11.3 Proposed Backup v2

Backup v2 should be a ZIP archive with extension `.kudosbackup`.

It should preserve the same internal paths where possible:

```text
manifest.json
Works/<UUID>.epub
Fonts/<fileName>
```

Add optional future directories:

```text
Covers/
Contracts/
```

But only after both platforms understand them.

### 11.4 Backup Compatibility Matrix

| Format | iOS import | iOS export | Android import | Android export |
|---|---:|---:|---:|---:|
| v1 directory package | Yes | Legacy support | Best effort | No |
| v2 zip package | Yes | Yes | Yes | Yes |

Implementation rule:

- Android should write v2 ZIP.
- iOS should be updated to read v1 directory and v2 ZIP.
- iOS should eventually write v2 ZIP by default.
- Both platforms should keep v1 import for older backups.
- Never silently discard unknown future fields.

### 11.5 Manifest Versioning

Use integer manifest versions.

Rules:

- v1: current Apple package manifest.
- v2: cross-platform ZIP manifest.
- Minor additive fields can be optional.
- Breaking changes require version increment.
- Readers must reject unsupported major versions with a clear message.
- Readers should ignore unknown fields in supported versions.
- Writers should include `platform` and `appVersion` metadata in v2.

Recommended v2 root:

```json
{
  "version": 2,
  "exportedAt": "2026-06-26T12:00:00Z",
  "exportedBy": {
    "app": "Kudos",
    "platform": "android",
    "appVersion": "1.0.0",
    "schemaVersion": 1
  },
  "works": [],
  "bookmarks": [],
  "fonts": [],
  "collections": [],
  "savedSearches": [],
  "settings": {}
}
```

### 11.5.1 Explicit v2 Additions

The following are v2 additions and must not be described as existing v1 parity fields:

| Field/area | v1 status | v2 intent |
|---|---|---|
| `comments` | Not exported in current v1 | Optional work stat |
| `hits` | Not exported in current v1 | Optional work stat |
| `knownChapterCount` | Not exported in current v1 | Update-check support |
| `lastUpdateCheck` | Not exported in current v1 | Update-check support |
| `collections` | Not exported in current v1 | Cross-platform local collections |
| `savedSearches` | Not exported in current v1 | Cross-platform saved AO3 search filters |
| `readiumLocator` metadata | Platform-specific/engine-specific | Preserve same-platform precision; cross-platform resume uses fallback fields |

Android should not write these fields into a v1 manifest. They belong in v2+ only.

### 11.6 Work Manifest v2

Include all current v1 work fields plus explicit v2 additions. Android must not assume these v2 additions are present in older Apple backups.

```json
{
  "id": "UUID",
  "title": "",
  "author": "",
  "summary": "",
  "sourceURL": "",
  "dateAdded": "ISO-8601",
  "isFavorite": false,
  "isSaved": true,
  "isFinished": false,
  "hasEPUB": true,
  "isComplete": false,
  "rating": "",
  "language": "",
  "wordCount": 0,
  "chapters": "",
  "kudos": 0,
  "comments": 0,
  "hits": 0,
  "workWarnings": [],
  "workCategories": [],
  "seriesTitle": "",
  "seriesPosition": 0,
  "seriesURL": "",
  "lastSpineIndex": 0,
  "lastScrollFraction": 0.0,
  "lastReadDate": null,
  "knownChapterCount": null,
  "lastUpdateCheck": null,
  "workTags": [],
  "workFandoms": [],
  "workCharacters": [],
  "workRelationships": [],
  "workFreeforms": [],
  "workTagsFetched": false,
  "userTags": [],
  "collectionIDs": [],
  "readiumLocator": null
}
```

### 11.7 Collection Manifest v2

Current Apple `WorkCollection` parity fields are:

```text
id
name
dateAdded
works
```

v2 should preserve those meanings first. Optional fields such as `description` and `sortOrder` are new v2 additions and must be treated as optional.

```json
{
  "id": "UUID",
  "name": "Favorites",
  "dateAdded": "ISO-8601",
  "workIDs": [],
  "description": "",
  "sortOrder": 0
}
```

### 11.8 Saved Search Manifest v2

Current Apple `SavedSearch` uses `dateAdded`, not `dateCreated`.

```json
{
  "id": "UUID",
  "name": "",
  "dateAdded": "ISO-8601",
  "filters": {}
}
```

### 11.9 Backup Encoding Rules

- JSON must be UTF-8.
- v2 dates should be ISO-8601 strings in UTC.
- v1 date decoding must support the current Apple exporter’s ISO-8601 date strings. Importers may be defensive toward older/experimental numeric Swift `Date` encodings only if such fixtures are found, but current v1 compatibility is ISO-8601.
- UUIDs must be parsed case-insensitively and canonicalized to lowercase for comparisons, file lookup, and merge decisions.
- JSON object keys may be sorted for deterministic v2 output, but importers must not depend on key order.
- Do not rely on byte-for-byte JSON equality across Swift and Kotlin unless a canonicalization step is explicitly defined.
- Floating-point settings and progress values must be parsed leniently and validated against allowed ranges.
- File names inside ZIP must use forward slashes.
- Paths must be validated against traversal.
- Do not allow `../`.
- Do not allow absolute paths.
- Do not write outside the app-private import staging directory.
- Validate ZIP entries before extraction.
- Enforce reasonable per-file and total-backup size limits.
- Stream ZIP import/export entry-by-entry; do not load full backups into memory.
- Detect truncated/incomplete archives and fail before partially merging data when possible.
- Treat backups as untrusted input.

### 11.9.1 Serialization Compatibility Rules

Backup compatibility should be judged by semantic restore results, not by raw JSON bytes.

The importer must normalize:

```text
UUID -> lowercase canonical string
Date -> Instant/Date in UTC
Missing optional field -> contract default or null, depending on manifest version
Numeric progress/settings -> validated number within allowed range
Unknown field -> preserved if practical, ignored if unsupported
```

The exporter should prefer deterministic output for human review and reproducible tests:

```text
UTF-8 JSON
Stable key ordering where supported
Stable path ordering in ZIP
ISO-8601 UTC dates for v2+
No platform-specific absolute paths
No session/auth data
```

Add fixtures for both legacy and v2 serialization:

```text
backup_v1_swift_numeric_dates.kudosbackup
backup_v1_iso_dates_if_present.kudosbackup
backup_v2_zip_canonical.kudosbackup
backup_v2_mixed_uuid_case.kudosbackup
backup_v2_path_traversal_rejected.kudosbackup
backup_v2_truncated_archive_rejected.kudosbackup
```

### 11.10 Merge Restore Contract

Restore must be safe and non-destructive.

Works:

- Match by UUID first after case-insensitive parsing and lowercase canonicalization.
- If no UUID match but same canonical AO3 work ID/source URL exists, consider merge only with explicit compatibility logic.
- Existing work should be updated with backup metadata.
- Local EPUB should be overwritten only if backup includes an EPUB for that work.
- If backup lacks EPUB and existing local EPUB exists, keep existing local EPUB.
- If backup lacks EPUB and existing local EPUB is missing, set `hasEPUB = false`.

User tags:

- Merge by trimmed tag name.
- Do not duplicate tags.
- Assign restored tags to works.

Collections:

- Merge by UUID if present.
- If UUID differs but name matches, either merge with confirmation or create separate collection. Recommended: merge by UUID only; if name collision, suffix restored collection.

Bookmarks:

- Merge by URL string.
- Update title/date if existing.

Fonts:

- Merge by safe file name.
- If same file name but different bytes, prefer existing and create a suffixed restored copy, or compare hashes and skip duplicates.

Settings:

- Apply after data restore.
- Validate enum values.
- Validate numeric ranges.
- Reset missing custom font references to `system`.

### 11.11 Backup Tests

Required tests:

```text
BackupV1DirectoryReadTest
BackupV2ZipReadTest
BackupV2ZipWriteTest
BackupRoundTripFullLibraryTest
BackupMergeDoesNotDeleteExistingEpubTest
BackupMissingCustomFontFallsBackToSystemTest
BackupRejectsPathTraversalTest
BackupRejectsUnsupportedVersionTest
BackupPreservesReadiumLocatorTest
BackupSettingsDefaultsTest
```

---

## 12. AO3 Networking Contract

### 12.1 AO3 Philosophy

Kudos uses AO3’s normal HTML pages because AO3 has no public API. The app must remain polite and personal.

Android must preserve:

- Browser-like user agent
- Conservative request rate
- Bounded concurrency
- Request coalescing
- Retry only transient failures
- Respect `Retry-After`
- No aggressive crawling
- No background hammering
- No automated retry of non-idempotent writes

### 12.2 Request Coordinator

Apple currently serializes or coordinates AO3 requests to stay polite. Android should implement the same behavior with Kotlin coroutines.

Current Apple parity note:

The current Apple `AO3RequestCoordinator` defaults to 3 request slots. Android should either match that default or make a deliberately stricter choice after human approval. Do not silently change concurrency policy during Phase 1.

Recommended initial Android default for parity:

```kotlin
class AO3RequestCoordinator(
    private val minDelayMs: Long = 500,
    private val maxConcurrentRequests: Int = 3
)
```

Rules:

- Default to the current Apple request-slot behavior unless the human approves a stricter Android policy.
- Add a delay between AO3 requests.
- Allow internal override only for non-AO3 local work.
- Queue requests FIFO.
- Surface cancellation.

### 12.3 Request Coalescing

Identical concurrent GET requests should share one network result.

Example:

```text
GET https://archiveofourown.org/works/search?...page=1
```

If three screens ask for the same URL at the same time, perform one network request and fan out the result.

Do not coalesce POST requests.

### 12.4 Retry Behavior

Retry only:

- Network timeout
- Network connection lost
- DNS/connectivity transient failures
- HTTP 429
- HTTP 5xx

Do not retry:

- HTTP 400/401/403/404
- Parser errors
- Authentication required
- POST/write actions

Default retry count:

```text
maxRetries = 2
```

Backoff:

```text
attempt 1: 0.5 seconds
attempt 2: 1.0 seconds
attempt 3: 2.0 seconds if maxRetries changes later
```

For HTTP 429, delay must be at least `Retry-After` if present.

### 12.5 HTTP Status Mapping

```text
200...299 -> success
429 -> rateLimited(retryAfter)
404 -> notFound
500...599 -> server(status)
other -> http(status)
```

### 12.6 AO3 Overload and Capacity Pages

AO3 may return overload/capacity pages that are not normal work/search content. These may appear as HTTP 429/5xx or as an HTML page that does not match the expected parser shape.

Android must detect these separately from empty search results or parser failures.

Rules:

- If the response is clearly an AO3 overload/capacity page, surface a retryable `ao3Overloaded` error.
- Respect `Retry-After` if present.
- Otherwise use conservative backoff.
- Do not parse overload pages as empty results.
- Do not immediately repeat requests in a tight loop.

Add fixture tests for:

```text
ao3_overload_200.html
ao3_overload_503.html
ao3_retry_after_429.html
```

### 12.7 User Agent

Use a browser-like User-Agent. Do not invent an obviously bot-like agent.

Keep User-Agent behavior centralized so both platforms can update it consistently.

---

## 13. AO3 Search Contract

### 13.1 URL Path

Search path:

```text
https://archiveofourown.org/works/search
```

### 13.2 Query Parameters

Android must match Apple query behavior.

Known parameters:

```text
work_search[query]
work_search[fandom_names]
work_search[character_names]
work_search[relationship_names]
work_search[freeform_names]
work_search[rating_ids]
work_search[archive_warning_ids][]
work_search[category_ids][]
work_search[crossover]
work_search[complete]
work_search[word_count]
work_search[revised_at]
work_search[language_id]
work_search[sort_column]
page
```

### 13.3 Empty Field Omission

Empty, blank, or whitespace-only values must be omitted.

### 13.4 Search Query Folding

AO3’s structured search does not support every filter directly. Some filters must be folded into `work_search[query]`.

Android must match Apple behavior for:

- multiple ratings
- rating plus
- rating minus
- excluded tags
- excluded warnings/categories where represented in search text
- include/exclude syntax

All search query behavior should be covered by fixture tests.

### 13.5 Word Count Expression

Match Apple logic:

```text
from + to -> "from-to"
from only -> "> from"
to only -> "< to"
neither -> omitted
```

### 13.6 Pagination

`page` is 1-based.

Include:

```text
page=1
```

unless Apple omits it. Match Apple behavior exactly after inspecting current code/tests.

### 13.7 Sorting

Use the same sort mapping as Apple.

Each sort option should match the current Apple search sort enum:

```text
relevance
dateUpdated
datePosted
words
kudos
hits
comments
bookmarks
```

Do not add `title` or `author` as AO3 sort enums unless the Apple implementation and AO3 query mapping are updated first. Map each enum to AO3’s expected `sort_column` string.

### 13.8 Search Results Normalization

Parsed work summaries should normalize:

- title
- authors
- work URL
- work ID
- fandoms
- rating
- warnings
- categories
- relationships
- characters
- freeforms
- summary
- language
- words
- chapters
- kudos
- comments
- hits
- bookmarks where present
- series title/position/url where present
- completion state
- restricted/locked state if visible

---

## 14. AO3 Parser Contract

### 14.1 Parser Library

Swift uses SwiftSoup. Android should use Jsoup.

Selectors must be documented and kept close to parity.

### 14.2 Parser Design

Use small parser functions:

```text
parseSearchPage(html, page)
parseWorkSummary(element)
parseWorkTags(html)
parseBookmarksPage(html, page)
parseCommentsPage(html)
parseCsrfToken(html)
parseSeriesPage(html)
parseAccountUsername(html)
```

### 14.3 Parser Output

Parsers should produce domain DTOs, not UI models.

### 14.4 Tolerance

AO3 HTML can change. Parsers should:

- avoid crashing on optional missing elements
- default to empty values where safe
- throw clear parser errors when required structure is missing
- avoid silently producing misleading data for malformed pages
- be covered by fixtures

### 14.5 Work Tags

Current Apple behavior fetches canonical tags from:

```text
/works/<workID>?view_adult=true
```

Android should match.

Canonical groups:

```text
fandoms
relationships
characters
freeforms
warnings
categories
language
words
chapters
kudos
```

### 14.6 Deduplication

Tag parsing should preserve first-seen order while removing duplicates.

### 14.7 HTML Entity and Summary Normalization

Android must match Apple tests for:

- HTML entity decoding
- summary stripping
- whitespace normalization
- Unicode preservation

---

## 15. Work Lifecycle Contract

### 15.1 Core Work States

A work can be:

```text
unsaved search result
saved metadata only
saved with EPUB
favorite
finished
currently reading
updated since last check
missing EPUB file
```

### 15.2 State Meanings

`isSaved`

- The work belongs to the user’s local library.
- It may or may not have an EPUB.

`hasEPUB`

- The app has an app-private EPUB file for the work.
- Must be verified against file existence during restore or diagnostics.

`isFavorite`

- Local app favorite.
- Independent of AO3 kudos/bookmarks.

`isFinished`

- User marked the work finished or reached end depending on product behavior.
- Must behave the same across platforms.

`isComplete`

- AO3 work completion status.
- Not the same as user finished state.

`lastReadDate`

- Last time user opened or meaningfully progressed in reader.
- Used for Continue Reading and history sorting.

`readiumLocator`

- Raw serialized Readium locator/progress where supported.
- Platform/engine-specific. Android Readium locator data must not be treated as directly readable by the Apple WKWebView reader.
- Must be persisted and included in backups for same-platform restore and future migration tooling.
- Should include or be accompanied by locator metadata such as `locatorPlatform = android` and `locatorEngine = readium-kotlin` once backup v2 is introduced.

`lastSpineIndex` / `lastScrollFraction`

- Required cross-platform fallback progress fields.
- Must be updated whenever reader progress is saved, even if a richer platform locator exists.
- These fields are the portable interchange format for cross-platform resume.
- Exact reader position survives same-platform restore through platform locator fields; approximate chapter-plus-offset progress survives cross-platform restore through these fallback fields.

### 15.3 Import Flow

When user saves/downloads a work:

1. Fetch or already have `AO3WorkSummary`.
2. Download EPUB from AO3.
3. Store file in temp location.
4. Import/parse EPUB metadata.
5. Create or update `SavedWork`.
6. Merge AO3 metadata with EPUB metadata.
7. Move EPUB to app-private permanent path.
8. Set `hasEPUB = true`.
9. Persist tags.
10. Surface success/failure clearly.

### 15.4 EPUB File Naming

Use work UUID for local storage, not title.

```text
files/works/<UUID>.epub
```

This matches backup naming and avoids unsafe filenames.

### 15.5 Missing EPUB Diagnostics

On app start or library load:

- If `hasEPUB = true` but file missing, mark unavailable or repair.
- Do not delete the library record automatically.
- Offer redownload if AO3 source URL exists.

---

## 16. Reader Contract

### 16.1 Reader Engine

Use Readium Kotlin Toolkit.

Do not port the Apple legacy WKWebView reader to Android.

### 16.2 Publication Opening

Reader flow:

1. Resolve `SavedWork`.
2. Verify EPUB exists.
3. Open EPUB with Readium streamer.
4. Build Readium navigator.
5. Apply reader preferences.
6. Restore Android Readium locator only if the locator is present and marked as compatible with the current Android reader engine/version.
7. Fall back to `lastSpineIndex` / `lastScrollFraction` if the locator is missing, incompatible, or came from another platform.
8. Persist both platform locator and fallback progress as user reads.

### 16.3 Progress Storage

Store:

```text
readiumLocator: String?
readiumLocatorPlatform: String?
readiumLocatorEngine: String?
readiumLocatorVersion: String?
lastSpineIndex: Int
lastScrollFraction: Double
lastReadDate: Instant?
```

`readiumLocator` should be raw JSON if feasible. Backup must include the raw string, but it is not the cross-platform source of truth.

Cross-platform progress rule:

- Android should restore `readiumLocator` only when it is compatible with the current Android Readium integration.
- Apple should preserve Android Readium locators during import/export if possible, but it should not attempt to interpret them unless the Apple app also uses a compatible Readium locator format.
- Both platforms must continuously maintain `lastSpineIndex` and `lastScrollFraction`.
- Cross-platform restore resumes from `lastSpineIndex` and `lastScrollFraction`.
- Same-platform restore can use the richer platform locator for more exact positioning.

This means progress portability is:

```text
Same platform: exact/best-effort locator restore
Cross platform: approximate spine index + scroll fraction restore
```

### 16.4 Reader Settings

Must map:

```text
readerFontID
readerMode
readerTwoPage
readerCustomize
readerBoldText
readerFontPt
readerLineHeight
readerLetterSpacing
readerWordSpacing
readerMargin
readerJustify
readerTheme
matchAppReaderTheme
```

### 16.5 Supported Reader Modes

At minimum:

```text
scroll
paged
```

If Readium Kotlin does not support an exact Apple setting, document the fallback.

Example:

```text
readerTwoPage=true
```

On phone: ignored or unavailable.
On tablet/foldable: use if supported.

### 16.6 Link Handling

Links inside reader should be intercepted.

Rules:

- AO3 work links -> native Work Detail if possible.
- AO3 author links -> Browse/WebView or native author page if implemented.
- AO3 tag links -> native Search/Browse tag flow if possible.
- Chapter comments/end-of-work comments -> native comments flow where implemented.
- External links -> browser or in-app confirmation.

### 16.7 End-of-Work Behavior

At end of work, surface:

- finished action
- comments entry point
- open on AO3
- kudos/bookmark/subscription actions if authenticated
- next work in series if available
- return to Library/Home

### 16.8 Reader Performance

Reader must:

- avoid blocking main thread
- load publication on IO dispatcher
- persist progress efficiently
- avoid writing progress too frequently
- debounce locator saves
- release resources when closed

---

## 17. Authentication and Session Contract

### 17.1 Password Handling

Never store AO3 password.

Login must use AO3’s actual form.

### 17.2 Android Login Flow

Use WebView for login.

Steps:

1. Open AO3 login URL in WebView.
2. User completes login.
3. Detect successful session by AO3 cookies and/or redirected account page.
4. Copy AO3 cookies from `CookieManager`.
5. Persist only session cookie data securely/app-privately.
6. Build authenticated OkHttp requests with those cookies.
7. Do not share cookies outside AO3 requests.

### 17.3 Hidden vs Visible Login

Apple uses hidden WebView session capture with visible fallback.

Android can implement:

- visible login first, or
- hidden restore/check and visible fallback.

Behavioral requirement:

- If session is invalid, user is clearly prompted to log in again.
- Do not silently fail.
- Do not loop login.
- Do not store credentials.

### 17.4 Authenticated Page Fetch

Authenticated requests must:

- attach current AO3 cookies explicitly
- detect redirect/bounce to `/users/login`
- return authentication-required error
- allow UI to prompt re-authentication

### 17.5 Session Storage

Use app-private secure storage, but do not make deprecated or fragile storage APIs the default for new Android work.

Recommended design:

- Store session metadata in DataStore Preferences or Proto DataStore.
- Encrypt AO3 cookie values before writing them.
- Use Google Tink or an equivalent maintained crypto layer for authenticated encryption.
- Store/wrap the encryption key with Android Keystore so raw key material is not exportable.
- Prefer hardware-backed Keystore when available, but handle devices without hardware backing gracefully.
- Exclude the encrypted session store and all cookie files from Android Auto Backup/cloud backup rules.
- If Keystore material is lost or restored encrypted blobs cannot be decrypted, delete the stale session and prompt the user to log in again.

Do not include session cookies in `.kudosbackup`.

Do not include session cookies in Android Auto Backup.

Do not log session cookies, CSRF tokens, or authenticated request bodies.

---

## 18. Authenticated AO3 Features

### 18.1 Account Lists

Implement:

- Marked for Later
- AO3 Bookmarks
- AO3 History
- Subscriptions
- My Works
- Collections where supported

Use same AO3 URL patterns as Apple.

Known patterns from Apple logic:

```text
/users/<username>/readings?show=to-read
/users/<username>/readings
/users/<username>/subscriptions?type=works
/users/<username>/bookmarks
```

### 18.2 Authenticated Writes

Supported actions:

- Kudos
- Comment
- Subscribe/unsubscribe
- Mark for Later
- Create/update AO3 bookmark

### 18.3 Write Safety

Non-negotiable rules:

- Fetch page/form first.
- Parse authenticity token / CSRF token.
- Submit exactly one user-initiated POST.
- Do not auto-retry POST.
- Do not perform hidden repeated writes.
- Show clear success/failure.
- If session expired, require re-login.
- If AO3 returns validation errors, show them.

### 18.4 Comments

Product direction: comments by chapter, read/write comments, exposed at the end of the reader/work.

Android should implement architecture for:

```text
CommentThread
Comment
CommentForm
CommentRepository
ChapterCommentTarget
WorkCommentTarget
```

If Apple comment implementation exists on the current branch, match it exactly. If not, Android should scaffold the same behavior behind feature flags and use AO3 real POST only when implemented.

Do not fake comment success.

---

## 19. AO3 Browse Contract

### 19.1 Native Browse

Browse should support:

- browse by fandom
- fandom work lists
- tag work lists
- popular/relevant tag suggestions where existing Apple behavior does this
- native work cards
- tag taps into Search/Browse

### 19.2 WebView Fallback

Keep an AO3 WebView fallback for unsupported pages.

Rules:

- User should understand when they are in AO3 web fallback vs native UI.
- Native-app actions should be offered when recognized.
- Keep AO3 login/session boundaries clear.
- Do not scrape every WebView page aggressively.

---

## 20. Home Screen Contract

Home should prioritize reading.

Required sections:

- Continue Reading
- Recently Added
- Recently Updated, if update checker exists
- Favorites
- Reading History
- Recommended/Discovery sections only if they do not require aggressive AO3 crawling

Home should not become a heavy network screen by default.

---

## 21. Library Contract

Library must support:

- all saved works
- favorites
- finished/unfinished
- downloaded/offline availability
- reading status
- user tags
- AO3 tag filters
- collections
- sorting
- search within library
- bulk actions where practical
- privacy filtering for mature/explicit works

### 21.1 Sorting

Required sort options:

```text
dateAdded
lastReadDate
title
author
wordCount
kudos
updatedDate if available
```

Sorting must be deterministic.

### 21.2 Filtering

Filters should include:

- user tag
- fandom
- character
- relationship
- additional/freeform
- rating
- warning
- category
- completion
- favorite
- finished
- downloaded

### 21.3 Tapping Tags

Tapping a tag from Work Detail should be able to:

- filter local Library by that tag, or
- search/browse AO3 for the tag

The route should match product direction and current Apple behavior.

---

## 22. Work Detail Contract

Work Detail should be canonical and reusable.

### 22.1 Metadata

Show:

- title
- author(s)
- fandoms
- rating
- warnings
- categories
- relationships
- characters
- additional tags/freeforms
- summary
- language
- word count
- chapters
- kudos
- comments
- hits
- series title/position
- completion state
- source URL/open on AO3

### 22.2 Actions

Actions:

- Read
- Download/Save
- Favorite
- Mark Finished/Unfinished
- Add/remove User Tags
- Add/remove Collections
- Open on AO3
- Kudos
- Subscribe/unsubscribe
- Mark for Later
- AO3 Bookmark
- Comments
- Delete local copy
- Remove from Library

### 22.3 Entry Point Independence

The same Work Detail screen should work from:

- a local saved work
- AO3 search result
- AO3 account list result
- series result
- tag result
- bookmark/history/subscription list

Use a screen model such as:

```kotlin
sealed interface WorkDetailSource {
    data class LocalWork(val workId: String)
    data class RemoteWork(val url: String, val summary: AO3WorkSummary)
    data class WorkId(val ao3WorkId: Long)
}
```

---

## 23. Download Queue Contract

### 23.1 Queue Behavior

Support:

- single work downloads
- series downloads where existing Apple supports it
- retry transient download failures
- do not retry permanent errors endlessly
- pause/cancel where practical
- bounded concurrency
- visible progress

### 23.2 Series Downloads

If downloading a series:

- fetch series pages politely
- parse works with same search parser where possible
- queue each work
- preserve series metadata
- do not hammer AO3

### 23.3 Failure Recovery

Failed downloads should remain visible with:

- error message
- retry action
- open on AO3 action

---

## 24. Privacy Contract

### 24.1 Mature Content Gate

Apple supports hiding mature works behind Face ID. Android should use BiometricPrompt/device credentials.

Settings:

```text
hideMatureContent
matureContentMode
requireBiometricToReveal
```

### 24.2 Mature Detection

A work is mature/explicit if rating or metadata indicates it.

Rules should be identical across platforms:

- Rating contains Mature
- Rating contains Explicit
- Possibly AO3 rating IDs if available
- Unknown rating should not be assumed mature unless Apple does

### 24.3 Privacy Modes

Recommended modes:

```text
hide
obscure
show
```

If Apple currently uses `obscure`, Android must match.

### 24.4 Biometric Behavior

If enabled:

- Reveal action prompts biometric/device credential.
- Revealed state can be session-scoped.
- Do not store sensitive reveal state in backup.
- If biometric not available, fall back to device credential where allowed or disable setting with explanation.

---

## 25. Performance Contract

### 25.1 Android Performance Goals

- Smooth scrolling in Library/Search.
- No network or EPUB parsing on main thread.
- Compose lists use stable keys.
- Large summaries/tags should not cause repeated recompositions.
- Images/covers, if added later, should be lazy-loaded and cached.
- Parser and import work on IO dispatcher.
- Room queries should use Flow and paging where needed.

### 25.2 Apple Silicon vs Android Devices

The prior Apple optimization direction does not directly translate. Android should target:

- mid-range Android phones
- tablets
- foldables
- ChromeOS if feasible later

### 25.3 Heavy Operations

Move to IO/default dispatchers:

- EPUB copying/import
- ZIP backup import/export
- HTML parsing
- Room writes
- font registration/copying
- backup checksums
- search parsing

### 25.4 Caching

Cache:

- in-flight GET requests
- recent search result pages only if useful
- autocomplete suggestions
- parsed tag suggestions

Do not create aggressive persistent AO3 caches without a clear invalidation policy.

---

## 26. Testing Plan

### 26.1 Android Unit Tests

Required:

```text
AO3SearchQueryBuilderTest
AO3UrlBuilderTest
AO3ParserSearchTest
AO3ParserWorkDetailTest
AO3ParserWorkTagsTest
AO3ParserBookmarksTest
AO3RetryPolicyTest
RequestCoalescerTest
WorkImporterTest
WorkLifecycleTest
RoomDaoTest
SettingsRepositoryTest
BackupV1ImportTest
BackupV2ImportExportTest
BackupMergeTest
ReaderLocatorStoreTest
PrivacyClassifierTest
```

### 26.2 MockWebServer Tests

Use MockWebServer for:

- 200 success
- 404 not found
- 429 with seconds Retry-After
- 429 with HTTP-date Retry-After
- 500 then success
- network timeout
- redirect to login
- authenticated request cookie attachment

### 26.3 Instrumentation Tests

Use instrumentation for:

- app launch
- navigation
- library list
- Work Detail
- reader opens sample EPUB
- import/export via fake/test document provider if practical
- biometric gate with test hooks
- WebView login manually or with mock AO3 page in non-production build

### 26.4 Cross-Platform Contract Tests

Each behavior should have equivalent Swift and Kotlin tests.

Example fixture:

```json
{
  "name": "advanced rating exclusion",
  "filters": {
    "query": "coffee shop",
    "ratings": ["Teen", "Mature"],
    "excludedTags": ["Major Character Death"],
    "wordsFrom": "10000",
    "wordsTo": "50000"
  },
  "expected": {
    "path": "/works/search",
    "queryItems": {
      "work_search[query]": "...",
      "work_search[word_count]": "10000-50000"
    }
  }
}
```

---

## 27. CI Plan

### 27.1 Existing Apple CI

Do not break existing Swift CI.

### 27.2 Android CI

Add:

```text
.github/workflows/android.yml
```

Initial jobs:

```text
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
```

Optional later:

```text
ktlint
detekt
connectedAndroidTest
```

### 27.3 Artifact Rules

Do not commit:

- APKs
- AABs
- build outputs
- local keystores
- API tokens
- AO3 cookies
- generated backups with personal data

---

## 28. Implementation Phases

### 28.0 Phase 0 Gate — Codex Review Corrections

Phase 1 must not start until Phase 0 records these repo-specific corrections in the repo docs/tasks:

- Approved Android branch: `kudos-ao3-reader-android`.
- Actual Apple source root: `kudos-ao3-reader/...`.
- Current v1 backup facts and v2 additions.
- Current Apple `WorkCollection` and `SavedSearch` field names.
- Current Apple AO3 sort enum.
- Current Apple AO3 request-concurrency default.
- Current subscription URL: `/users/<username>/subscriptions?type=works`.

## Phase 0 — Contract and Repo Preparation

Goal: prepare the repo for a safe Android port.

Tasks:

- Inspect branch strategy.
- Create/use `kudos-ao3-reader-android`.
- Update `TASKS.md`.
- Add `docs/android/ANDROID_PORT_PLAN.md`.
- Add contract doc skeletons.
- Confirm backup v1 schema and actual date encoding.
- Confirm product direction: Home / Library / Browse / Account, global Search.
- Confirm whether Account replaces Bookmarks tab in the current branch.
- Confirm repo license and dependency license obligations.
- Decide Android `minSdk`, `targetSdk`, desugaring policy, and first release channel.
- Add multi-AI collaboration files or sections if they do not already exist.

Deliverables:

- Documentation committed.
- No app code yet.
- Clear task entry.

Done when:

- `TASKS.md` has Android port task.
- Contract docs exist.
- Branch is clean.

## Phase 1 — Android Project Foundation

Goal: create a compileable Android app.

Tasks:

- Create Gradle Android project under `android/`.
- Pin Android Gradle Plugin, Kotlin, Compose BOM, and Java/Kotlin target versions.
- Set `minSdk` deliberately and enable core library desugaring if `minSdk < 26`.
- Add Kotlin, Compose, Material 3.
- Add package `io.github.cidy02.kudos`.
- Add `MainActivity`.
- Add theme system.
- Add basic navigation shell.
- Add placeholder screens:
  - Home
  - Library
  - Browse
  - Account
  - Search
  - Work Detail
  - Reader
  - Settings
- Add app icon placeholder or reuse allowed assets.

Deliverables:

- App builds.
- Screens navigate.
- No AO3/network yet.

Done when:

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

passes.

## Phase 2 — Core Models and Settings

Goal: define the Android domain and persistence model.

Tasks:

- Add Kotlin domain models.
- Add Room entities/DAOs.
- Add type converters.
- Add DataStore settings repository.
- Add settings defaults matching Apple.
- Add initial model tests.

Deliverables:

- Room database works.
- Settings read/write works.
- Backup-compatible settings model exists.

Done when:

- Unit tests verify defaults.
- Room DAO tests pass.
- Models match backup fields.

## Phase 3 — Backup v1/v2 Compatibility

Goal: make data portable before building advanced features.

Tasks:

- Implement v1 manifest decoding.
- Implement v2 ZIP `.kudosbackup` format.
- Implement v2 export.
- Implement restore merge logic.
- Add path traversal protection.
- Add missing custom font fallback.
- Add sample backup fixtures.
- Add tests.

Deliverables:

- Android can import iOS-compatible v1 where possible.
- Android can export v2 ZIP.
- Android can import its own v2 export.
- iOS update plan for v2 exists.

Done when:

- Backup round-trip tests pass.
- Merge tests pass.
- Unsupported version test passes.

## Phase 4 — AO3 Networking Core

Goal: implement polite AO3 client.

Tasks:

- Add OkHttp.
- Add browser-like User-Agent.
- Add request coordinator.
- Add request coalescer.
- Add retry policy.
- Add AO3 errors.
- Add MockWebServer tests.

Deliverables:

- GET requests work.
- Retry behavior matches Apple.
- 429 Retry-After handled.
- POST not retried.

Done when:

- Network policy tests pass.

## Phase 5 — AO3 Search and Parsing

Goal: native AO3 search works.

Tasks:

- Port search filters.
- Port search query builder.
- Port URL builder.
- Implement Jsoup parsers.
- Add fixture tests.
- Build Compose Search UI.
- Build search result cards.
- Route result tap to Work Detail.

Deliverables:

- Search screen returns AO3 works.
- Filters produce Apple-equivalent URLs.
- Parser output matches fixtures.

Done when:

- Contract tests pass.
- Manual search works.

## Phase 6 — Work Detail and Save/Download

Goal: save works to local library.

Tasks:

- Implement WorkRepository.
- Implement WorkImporter.
- Implement AO3 EPUB download.
- Store EPUB in app-private files.
- Create/update WorkEntity.
- Fetch canonical AO3 tags.
- Build Work Detail UI.
- Add save/download/favorite/tag actions.

Deliverables:

- User can search, open detail, save/download, see in Library.
- EPUB file is stored correctly.
- Metadata matches Apple behavior.

Done when:

- Work lifecycle tests pass.
- Manual save/download works.

## Phase 7 — Readium Reader

Goal: offline reading.

Tasks:

- Add Readium Kotlin dependencies.
- Add required desugaring/configuration based on minSdk.
- Open EPUB from saved work.
- Build Reader screen using Fragment/View interop where Readium requires it.
- Apply theme/settings.
- Persist locator.
- Restore progress.
- Implement reader link handling.
- Add end-of-work actions.

Deliverables:

- Saved work opens in reader.
- Progress persists.
- Reader settings apply.
- Backup includes/restores progress.

Done when:

- Sample EPUB opens.
- Progress survives app restart.
- Reader tests pass where feasible.

## Phase 8 — Library UX

Goal: full offline library experience.

Tasks:

- Build Library screen.
- Add filters/sorts.
- Add user tags.
- Add collections.
- Add Continue Reading.
- Add Reading History.
- Add Favorites.
- Add bulk actions if practical.
- Add privacy filtering.

Deliverables:

- Library is useful offline.
- Tag/collection workflows work.
- Home can show library-derived shelves.

Done when:

- Manual library checklist passes.
- DAO/query tests pass.

## Phase 9 — Authentication and Account

Goal: AO3 account support.

Tasks:

- Add WebView login.
- Capture cookies.
- Persist session safely.
- Restore session.
- Add authenticated request builder.
- Add Account screen.
- Add Marked for Later.
- Add History.
- Add AO3 Bookmarks.
- Add Subscriptions.
- Add My Works if feasible.

Deliverables:

- User can log in.
- Account lists load.
- Session expiry handled.

Done when:

- Auth tests pass.
- Manual login checklist passes.

## Phase 10 — Authenticated Writes and Comments

Goal: account actions parity.

Tasks:

- Implement CSRF token parsing.
- Implement kudos.
- Implement subscribe/unsubscribe.
- Implement mark for later.
- Implement AO3 bookmark.
- Implement comments by chapter/work.
- Add end-of-reader comment entry.
- Add write safety tests.

Deliverables:

- User-initiated AO3 writes work.
- No POST auto-retry.
- Comments read/write where supported.

Done when:

- Mock form/write tests pass.
- Manual AO3 write checklist passes.

## Phase 11 — Browse and WebView Fallback

Goal: native browse plus fallback.

Tasks:

- Build Browse screen.
- Browse by fandom.
- Tag/fandom work lists.
- WebView fallback.
- Native link interception.
- Session handling boundaries.

Deliverables:

- Browse is no longer just web-only.
- Unsupported pages still reachable.

Done when:

- Browse manual checklist passes.

## Phase 12 — Polish, Accessibility, Release Prep

Goal: production-ready Android app.

Tasks:

- Accessibility pass.
- Dynamic type/font scale pass.
- Dark/sepia theme pass.
- Tablet/foldable pass.
- Performance profiling.
- Error message review.
- Empty/loading/error states.
- Localization readiness pass, even if English is the only initial language.
- About/licenses.
- AO3/OTW disclaimer.
- GPL and third-party license compliance.
- Distribution policy review for Play/GitHub/F-Droid/side-loading.
- R8/minification keep rules and release-build smoke testing.
- CI hardening.

Deliverables:

- Release candidate Android app.
- Known gaps documented.

Done when:

- Manual parity checklist passes.
- CI green.
- No known data-loss bugs.

---

## 29. Android UI Component Plan

### 29.1 Shared Components

Implement reusable Compose components:

```text
WorkCard
WorkMetadataChips
TagChip
RatingBadge
WarningBadge
ActionRow
LibraryFilterBar
SearchFilterSheet
ReaderTopBar
ReaderBottomBar
EmptyState
ErrorState
LoadingSkeleton
AccountListCard
BackupImportExportCard
PrivacyLockedWorkCard
```

### 29.2 Work Cards

Work cards should contain work info inside the card, matching the product direction.

Show:

- title
- author
- fandom
- rating/warnings/categories
- summary snippet
- words/chapters/kudos/comments
- saved/downloaded/favorite status
- completion status

### 29.3 Loading States

Use skeleton loading for:

- search results
- account lists
- library initial load
- work detail metadata hydration

Do not trigger additional AO3 fetches just to display skeletons.

### 29.4 Error States

Errors should be actionable:

- Retry
- Open on AO3
- Log in again
- Redownload
- Restore from backup
- Dismiss

---

## 30. Security and Privacy

### 30.1 Secrets

Never commit:

- AO3 session cookies
- local backups with real user data
- user EPUBs
- keystores
- API keys
- generated APKs

### 30.2 Backup Import Safety

Backups are untrusted.

Protect against:

- ZIP slip/path traversal
- massive ZIP bombs
- unsafe font filenames
- unsupported versions
- malformed JSON
- bad UUIDs
- invalid dates
- missing manifest
- manifest claiming files that do not exist

### 30.3 WebView Safety

- Restrict login WebView to AO3 domains where practical.
- Do not inject scripts unless necessary.
- Do not log cookies.
- Clear temporary WebView state when logging out if appropriate.
- Keep cookies scoped.

### 30.4 AO3 Disclaimer

About screen must state:

- Kudos is unofficial.
- Kudos is not affiliated with AO3, OTW, or Organization for Transformative Works.
- AO3 HTML is scraped because there is no public official API.
- Use should remain respectful of AO3 infrastructure.

### 30.5 Release, Store, and Policy Review

Before public Android distribution, create a release-risk checklist covering:

- AO3/OTW policy review.
- Google Play policy review if Play distribution is planned.
- Mature/explicit content handling and listing disclosures.
- Whether the first release should be GitHub Releases, side-loading, F-Droid, Play, or some combination.
- Required source-code offer and license notices if the app remains GPL.
- Third-party license notices for Readium, OkHttp, Jsoup, Compose/AndroidX, Room, DataStore, Kotlin serialization, Tink, and any other dependency.

### 30.6 Android Auto Backup Exclusions

Android Auto Backup/cloud backup must not include:

- AO3 session cookies.
- CSRF/auth tokens.
- Encrypted session blobs whose Keystore key cannot be restored.
- Temporary WebView login state.
- Import staging files.

If a backup restore leaves unreadable encrypted state, the app must delete that state and prompt for login rather than crash.

### 30.7 Release Build Hardening

Before enabling minification/shrinking for release builds:

- Add R8 keep rules where required by Readium, Kotlin serialization, Room, WebView integration, and Android components.
- Run backup import/export smoke tests against the release build.
- Run reader-open and progress-save smoke tests against the release build.
- Run login/session smoke tests against the release build where safe.
- Verify parser behavior against fixtures after minification.

---

## 31. Data Migration Strategy

### 31.1 Android Internal Migration

Room migrations start at schema version 1.

Rules:

- Every schema change requires migration.
- No destructive migration in production.
- Test migrations.
- Backup export should work before any risky migration.

### 31.2 Cross-Platform Migration

Cross-platform data migration uses `.kudosbackup`, not direct database copying.

Flow:

```text
iOS/macOS export .kudosbackup
Android import .kudosbackup
Android export .kudosbackup
iOS/macOS import .kudosbackup
```

### 31.3 iOS Update Needed

To guarantee portability, Apple app should be updated to support v2 ZIP `.kudosbackup`.

Short-term options:

1. Android supports v1 import best-effort and writes v2.
2. Apple is updated to import v2 before Android release.
3. Apple switches default export to v2 once both platforms support it.

Recommended:

- Implement Apple v2 import/export in a separate task before Android public release.
- Keep v1 import forever unless impossible.

---

## 32. Manual Parity Checklist

Before considering the Android port done:

### 32.1 Backup

- Export on iOS, import on Android.
- Export on Android, import on iOS.
- EPUBs survive.
- Custom fonts survive.
- User tags survive.
- Collections survive.
- Favorites survive.
- Finished state survives.
- Reader settings survive.
- Mature privacy settings survive.
- Progress survives where supported.

### 32.2 Search

- Basic query matches.
- Fandom search matches.
- Character search matches.
- Relationship search matches.
- Freeform/additional tag search matches.
- Include/exclude tags match.
- Rating exact/rating+/rating- matches.
- Warning/category filters match.
- Completion filters match.
- Word count filters match.
- Sort options match.
- Pagination matches.

### 32.3 Library

- Save work.
- Download EPUB.
- Open offline.
- Favorite.
- Mark finished.
- Add user tag.
- Filter by user tag.
- Filter by AO3 tag.
- Add to collection.
- Delete local copy.
- Remove from library.
- Restore from backup.

### 32.4 Reader

- Open EPUB.
- Resume progress.
- Change theme.
- Change font size.
- Change margin.
- Change line height.
- Switch scroll/paged if supported.
- Open AO3 links.
- End-of-work actions show.
- Comments entry point appears.

### 32.5 Account

- Login.
- Session persists.
- Expired session prompts re-login.
- Marked for Later loads.
- Bookmarks load.
- History loads.
- Subscriptions load.
- Kudos works.
- Subscribe/unsubscribe works.
- Comment works.
- AO3 bookmark works.

### 32.6 Privacy

- Mature work hidden/obscured.
- Reveal prompts biometric/device credential.
- Reveal state does not leak into backup.
- Disabled biometric setting behaves clearly.

---


## 33. Multi-AI Collaboration Protocol

This project is large enough that Claude and Codex can help, but only if they work under an explicit collaboration protocol. The goal is to use each AI where it is strongest while preventing broad, conflicting rewrites.

### 33.0 Approved Android Branch Policy

The human-approved Android port branch is:

```text
kudos-ao3-reader-android
```

This overrides the generic `AGENTS.md` guidance that normal work happens on `main` for this specific Android effort. `main` remains the protected Apple/reference branch unless the human explicitly approves a merge.

Rules:

- Claude and Codex must perform Android-port work on `kudos-ao3-reader-android` or on short-lived branches/worktrees based from it.
- No Android port implementation should be committed directly to `main`.
- If an agent sees that it is on `main`, it must stop before editing and either switch to `kudos-ao3-reader-android` or ask the human.
- Handoffs must include the branch name and base commit.
- Merge back to `main` requires human review.

### 33.1 Collaboration Model

Use this pattern:

```text
Claude: architecture, product reasoning, broad implementation scaffolds, Compose UI structure, documentation, integration planning.
Codex: focused code edits, test generation, parser/backup fixtures, CI/Gradle fixes, small refactors, regression fixes.
Human/user: product decisions, phase approval, risky refactor approval, final merge approval.
```

This is a default, not a hard rule. Either tool can implement any task if the task is scoped tightly and the handoff is clear.

### 33.2 One Owner Per Task

Every active task in `TASKS.md` should include:

```text
Task ID:
Owner: Claude | Codex | Human
Reviewer: Claude | Codex | Human
Branch:
Files/areas touched:
Status:
Commands run:
Known risks:
Next handoff:
```

Only one AI should own a task at a time. The other AI can review, write tests, or fix a clearly scoped issue after the owner has handed off.

### 33.3 Branch and Worktree Rules

Use the approved Android branch and short-lived task branches/worktrees to prevent accidental overwrite.

Approved base branch:

```text
kudos-ao3-reader-android
```

Optional short-lived task branch naming:

```text
ai/claude/<task-id>-<short-name>
ai/codex/<task-id>-<short-name>
review/<task-id>-<short-name>
```

Rules:

- Do not let Claude and Codex edit the same branch at the same time.
- Do not let both tools edit the same file set without an explicit handoff.
- Prefer small PR-style diffs over huge all-in-one changes.
- Before starting, each AI must run `git status` and identify the branch.
- Before finishing, each AI must provide `git diff --stat`, commands run, tests run, and known gaps.
- If a task changes backup schema, auth behavior, AO3 request behavior, or reader progress semantics, it requires human approval before merge.

### 33.4 File Ownership by Phase

Suggested initial split:

```text
Phase 0 docs/contracts: Claude drafts, Codex reviews and tightens fixtures/checklists.
Phase 1 Gradle/app shell: Claude scaffolds, Codex verifies build/CI and fixes Gradle issues.
Phase 2 models/settings: Claude maps semantics, Codex writes Room/DataStore tests.
Phase 3 backup: Claude implements contract shape, Codex writes fixtures, edge tests, path traversal tests.
Phase 4 networking: Claude implements policy, Codex writes MockWebServer tests.
Phase 5 search/parsing: Claude implements parser/query builder, Codex expands fixtures and regression tests.
Phase 6 work import/download: Claude implements flow, Codex tests failure/retry/file-state cases.
Phase 7 reader: Claude handles Readium integration, Codex tests lifecycle/progress persistence and release-build config.
Phase 8 library UI: Claude implements UI, Codex tests DAO/query/filter behavior.
Phase 9 auth/account: Claude implements flow, Codex tests cookie/session/error boundaries.
Phase 10 writes/comments: Claude implements user flows, Codex tests CSRF/body generation and no-POST-retry policy.
Phase 12 polish/release: Claude handles UX/accessibility checklist, Codex handles CI/R8/lint/test stability.
```

### 33.5 Handoff Format

Each AI handoff should be appended to `TASKS.md` or `docs/ai/HANDOFF.md`.

Template:

```md
## Handoff — <Task ID> — <Agent> — <Date>

Branch: 
Base commit: 
Files changed: 
Summary: 
Commands run: 
Tests passing: 
Tests failing/not run: 
Known risks: 
Needs human decision: 
Next recommended agent: Claude | Codex | Human
Next steps: 
```

### 33.6 Review Checklist for AI-Generated Changes

Before accepting Claude or Codex output:

- Does it compile?
- Did it update `TASKS.md`?
- Did it avoid unrelated refactors?
- Did it preserve the Apple implementation unless the task explicitly allowed changes?
- Did it preserve cross-platform backup compatibility?
- Did it add or update tests for contract behavior?
- Did it avoid storing passwords, cookies, tokens, personal EPUBs, generated APKs, or real backups?
- Did it avoid aggressive AO3 requests?
- Did it document known gaps instead of pretending work is complete?
- Did the other AI review the highest-risk part?

### 33.7 Stop-and-Ask Rules

Claude and Codex must stop and ask before:

- Changing backup manifest versions or field meanings.
- Changing AO3 request cadence, retry policy, or write behavior.
- Changing auth/session storage design.
- Changing reader progress semantics.
- Performing broad refactors outside the current phase.
- Deleting or rewriting the Xcode project.
- Removing existing iOS functionality.
- Adding large dependencies not already approved in the plan.
- Changing licensing/distribution assumptions.

### 33.8 Codex-Focused Prompt Template

Use Codex for narrow, testable edits.

```md
You are working in `cidy02/kudos-ao3-reader` on branch `<branch>`.

Task: <specific task only>.

Scope:
- Files/areas allowed: <list>
- Files/areas off-limits: <list>
- Do not perform broad refactors.
- Do not change backup/auth/AO3/reader semantics unless explicitly requested.

Before editing:
- Run `git status`.
- Read `TASKS.md` and the relevant contract doc.
- Identify any existing uncommitted changes and do not overwrite them.

Implementation requirements:
- Add or update tests for this behavior.
- Keep the diff small.
- Run the relevant Gradle/Xcode test command if available.
- Update `TASKS.md` with commands run and known gaps.

Handoff:
- Provide `git diff --stat`.
- List files changed.
- List tests run and results.
- List any follow-up needed.
```

### 33.9 Claude-Focused Prompt Template

Use Claude for broader implementation chunks, but still phase-limited.

```md
You are working in `cidy02/kudos-ao3-reader` on branch `<branch>`.

Task: Implement <phase/task> only.

Read first:
- `TASKS.md`
- `docs/android/ANDROID_PORT_PLAN.md`
- relevant `docs/contracts/*.md`
- current implementation files in the Apple app that define reference behavior

Rules:
- Preserve core behavior parity.
- Keep Android UI native, but match model/AO3/backup/reader semantics.
- Do not modify unrelated iOS files.
- Do not make large unapproved refactors.
- Ask before schema, backup, auth, AO3 cadence, or reader-progress changes.
- Leave a handoff suitable for Codex to review or test.

Definition of done:
- Build/test commands run where possible.
- `TASKS.md` updated.
- Known gaps documented.
- Diff is phase-scoped.
```

---

## 34. Claude Implementation Prompt

Use this as the implementation prompt after adding this plan to the repo.

```md
You are working in `cidy02/kudos-ao3-reader`.

Task: begin the native Android port while preserving identical core logic and cross-platform backup compatibility.

Important product rule:
The Android UI should be native Android, not a SwiftUI clone. However, the core behavior must match the Apple app: same model semantics, same AO3 search behavior, same AO3 networking safety, same restore/merge behavior, same reader settings meaning, same portable progress fallback fields, and cross-platform `.kudosbackup` support.

Multi-AI rule:
This repo may also be edited by Codex. Before editing, identify the current branch, inspect uncommitted changes, and do not overwrite work from another AI. Own only the task assigned to you, leave a handoff, and mark whether Codex should review/test the result.

Before editing:
1. Read:
   - `README.md`
   - `AGENTS.md`
   - `TASKS.md`
   - `docs/PROJECT_PHILOSOPHY.md`
   - `docs/AO3Authentication.md`
   - `docs/EPUBParsing.md`
   - `docs/Kudos_Layout_Structure.md`
   - `kudos-ao3-reader/Services/KudosBackup.swift`
   - `kudos-ao3-reader/Services/AO3Client.swift`
   - `kudos-ao3-reader/Services/AO3RequestCoordinator.swift`
   - `kudos-ao3-reader/Services/RequestCoalescer.swift`
   - `kudos-ao3-reader/Models/`
   - `KudosTests/`
   - `docs/ai/HANDOFF.md` if it exists
2. Run:
   - `git status`
   - `git branch --show-current`
   - `git branch -a`
3. Create or use the approved Android branch:
   - `kudos-ao3-reader-android`
4. If currently on `main`, stop before editing source and switch to `kudos-ao3-reader-android`.
5. Update `TASKS.md` with an Android port task and keep it current.

Implementation principles:
- Do not modify the Xcode project unless necessary.
- Do not break existing Apple CI/tests.
- Add Android under `android/`.
- Use Kotlin, Jetpack Compose, Material 3, Room, DataStore, OkHttp, Jsoup, Coroutines/Flow, Readium Kotlin Toolkit, Android WebView/CookieManager, BiometricPrompt, and Storage Access Framework.
- Keep commits small and logical.
- Do not bulk-reformat unrelated files.
- Do not commit generated APKs, personal backups, EPUBs, AO3 cookies, or secrets.

Phase 0:
- Confirm repo license, dependency license obligations, Android minSdk/desugaring decision, and distribution risk assumptions.
- Record the approved branch policy: Android work happens on `kudos-ao3-reader-android`, not directly on `main`.
- Correct stale source-path references to `kudos-ao3-reader/...`.
- Record current Apple v1 backup facts before scaffolding Android models.
- Record the current Apple AO3 sort enum and request-concurrency default.
- Add/confirm docs:
  - `docs/android/ANDROID_PORT_PLAN.md`
  - `docs/contracts/CORE_BEHAVIOR_CONTRACT.md`
  - `docs/contracts/BACKUP_FORMAT.md`
  - `docs/contracts/AO3_BEHAVIOR_CONTRACT.md`
  - `docs/contracts/READER_STATE_CONTRACT.md`
  - `docs/contracts/SETTINGS_CONTRACT.md`
  - `docs/contracts/UI_PARITY_CHECKLIST.md`
- Document that iOS/macOS is the reference implementation until contract tests are complete.
- Document that backup v1 is the current iOS directory package and backup v2 should be a ZIP `.kudosbackup` for true cross-platform portability.

Phase 1:
- Create a compileable Android project under `android/`.
- Package name: `io.github.cidy02.kudos`.
- Pin minSdk deliberately; if below API 26, enable core library desugaring.
- Add Compose Material 3 app shell.
- Add Home / Library / Browse / Account navigation.
- Add global Search action.
- Add placeholder Work Detail, Reader, Settings, Backup screens.
- Add theme foundation: light, sepia, dark, AO3 red accent.
- Confirm `./gradlew :app:assembleDebug` works.

Phase 2:
- Add Kotlin domain models matching Apple/backup semantics.
- Add Room database and DAOs.
- Add DataStore settings repository.
- Match setting defaults from the Apple backup contract.
- Add tests for settings defaults and Room persistence.

Phase 3:
- Implement backup support early:
  - read current v1 manifest/package where Android can access it
  - write/read v2 ZIP `.kudosbackup`
  - preserve internal paths: `manifest.json`, `Works/<UUID>.epub`, `Fonts/<fileName>`
  - safe merge restore
  - path traversal protection
  - missing custom font fallback to `system`
- Add backup round-trip and merge tests.

Phase 4:
- Implement AO3 networking:
  - browser-like User-Agent
  - request coordinator
  - bounded concurrency
  - request coalescing for GET
  - retry only transient GET failures
  - respect `Retry-After`
  - never auto-retry POST/write actions
- Add MockWebServer tests.

Phase 5:
- Implement AO3 search:
  - exact Apple-equivalent URL/query generation
  - same filter semantics
  - same word count expression behavior
  - Jsoup parsing fixture tests
  - Compose Search UI and result cards
  - Work Detail route

Phase 6:
- Implement saving/downloading:
  - WorkRepository
  - WorkImporter
  - EPUB download
  - app-private file storage
  - canonical AO3 tag fetch
  - Work Detail actions
  - Library appears with saved works

Phase 7:
- Integrate Readium Kotlin:
  - EPUB opening
  - Fragment/View navigator interop inside the Compose app
  - reader UI
  - progress persistence via serialized platform locator
  - continuously updated fallback legacy progress fields for cross-platform resume
  - reader settings mapping
  - end-of-work actions and comments entry point

Phase 8:
- Build Library:
  - filters
  - sorts
  - user tags
  - collections
  - favorites
  - finished/unfinished
  - Continue Reading
  - Reading History
  - privacy filtering

Phase 9:
- Build Account/Auth:
  - WebView login
  - CookieManager bridge
  - secure session persistence
  - authenticated page fetch
  - account lists: Marked for Later, AO3 Bookmarks, History, Subscriptions, My Works where feasible

Phase 10:
- Implement authenticated writes:
  - CSRF parsing
  - kudos
  - subscribe/unsubscribe
  - mark for later
  - AO3 bookmark
  - comments by chapter/work
  - no fake successes
  - no POST retry

Definition of done for every phase:
- Code compiles.
- Tests added where practical.
- `TASKS.md` updated.
- Known gaps documented.
- `git status` is clean except intentional changes.
```

---

## 35. Recommended Immediate Next Steps

1. Commit this plan into the repo as:

```text
docs/android/ANDROID_PORT_PLAN.md
```

2. Add a compact cross-platform backup spec as:

```text
docs/contracts/BACKUP_FORMAT.md
```

3. Add a multi-AI handoff file as:

```text
docs/ai/HANDOFF.md
```

4. Ask Claude to implement Phase 0 and Phase 1 only first, then ask Codex to review/build-test the Android scaffold and tighten CI/Gradle issues.

Do not ask Claude to implement the whole Android port in one pass. The risk of architectural drift is too high.

Recommended first implementation prompt after Codex's Phase 0 review:

```text
Implement Phase 0 docs only first on branch kudos-ao3-reader-android. Do not scaffold Android yet. Correct source paths to kudos-ao3-reader/..., record current Apple v1 backup facts, record v2 additions, reconcile AGENTS.md with the approved Android branch policy, record the current AO3 sort enum, record AO3RequestCoordinator's current 3-slot default, add the Android task to TASKS.md, and leave a handoff for Codex review.
```

After that is reviewed, use:

```text
Implement Phase 1 only on branch kudos-ao3-reader-android. Do not implement AO3 networking, backups, reader, auth, Room, DataStore, or parsing yet. Create the Android project foundation, navigation shell, theme foundation, and placeholders. Make sure it builds and update TASKS.md.
```

---

## 36. Final Success Definition

The Android port is successful when:

- Android is a first-class native Android app.
- The Apple app remains a first-class native Apple app.
- Both apps implement the same core behavior contract.
- Both apps can read/write the same `.kudosbackup` format.
- AO3 search/filter behavior matches between platforms.
- Saved works, EPUBs, tags, collections, settings, and progress survive cross-platform restore.
- Reader experience is equivalent even when UI conventions differ.
- AO3 infrastructure is treated respectfully.
- No user data is lost during import, restore, update, or migration.
