# `manifest.json` contract (T-567 / A-567, P2)

What a reader of the v8 manifest accepts, key by key, and what each route does with each outcome. It is the written form of
`docs/MANIFEST_STREAMING_PLAN.md` § Contract and is enforced on iOS by tests (§ Tests). The iOS column is read from the code
(`KudosBackup.swift`, `FolderSyncService.swift`) and from the streaming reader in `Services/ManifestStreaming/`; the Android
column is **see A-567 P2** until that phase lands. The on-disk format is unchanged.

Status: the streaming reader (`ManifestStager`) is built and tested, and **called by no production path yet**. Today every route
still decodes with `JSONSerialization` / `JSONDecoder`; "today" below means those routes, which are the oracle.

## 1. Accepted input (document level)

One contract for both platforms (owner, 2026-11-22, `docs/REDESIGN_DECISIONS.md`): what iOS accepts today.

| Case | Contract |
|---|---|
| Encoding | UTF-8, validated (overlong forms, surrogates, truncated sequences and bytes above `F4 8F` are rejected, also inside keys). |
| Leading BOM | `EF BB BF` accepted. |
| Whitespace | JSON whitespace only (space, tab, LF, CR) between tokens. |
| Trailing commas | Accepted in objects and arrays (`{"a":1,}`, `[1,]`). A leading or doubled comma is not. |
| Duplicate key | The **first** value wins; later values are validated and ignored. Compared after unescaping (`"version"` is `version`). |
| Escapes | `\" \\ \/ \b \f \n \r \t \uXXXX`. A lone high or low surrogate escape is rejected; a valid pair is accepted. Raw control characters (< 0x20) in a string are rejected; `0x7F` is allowed. |
| Numbers | JSON grammar (no leading `+`, no leading zeros, no `NaN`/`Infinity`, digits required after `.` and `e`). Value range is decided by the typed decode (`99999999999999999999` as `version` is a schema failure, not a syntax one). |
| Not accepted | Comments, single quotes, unquoted tokens, `;`/`=` separators (Android's lenient decoder accepted some; it stops). |
| Top level | An object is a manifest candidate. An array is JSON but not a manifest (schema failure). A scalar is not JSON (`notJSON`). Empty input is `notJSON`. |
| Trailing content | Anything but whitespace after the top-level value is `notJSON`. |
| Depth | 512 levels of nesting below the top-level value (a 513th nested container is rejected). Measured against `JSONSerialization` at 508–516 in both object and array roots; they agree. Real manifests nest about 5 deep. |
| Resource limits | Same on both platforms (new, **pending owner approval**; each is one named constant in `ManifestLimits`): object key <= 64 Ki chars; number token <= 64 Ki chars; <= 262,144 distinct keys in the top-level object; a known single root value (`version`, `exportedAt`, `settings`, `pronunciations`) <= 16 Mi chars. Over a limit is **resource exhaustion**, not an invalid document. Record arrays, records and unknown values have no size limit. Keys inside records are not counted (the typed decoder reads them). Tested at the limit and one over. |
| Leading zeros, missing comma | Rejected as syntax (`08`, `{"a":1 "b":2}`): already so on iOS, identical on Android. |
| Evaluation order | Syntax first, through EOF (a bad record early plus a truncated tail is `notJSON`, not `schema`), then record and key checks, then version. |
| Key order | Free. `version` and `exportedAt` may follow the arrays (the exporter writes them last, `sortedKeys`), so nothing is applied or swept before EOF. |

## 2. Per top-level key

"Strict" = every element must decode with the production `Codable` type or the **whole document** is a schema failure.
"Lossy" = `LossyArray` under `try?`: a bad element is skipped, a wrong kind is absent, the document is unaffected.
"nil" and "`[]`" are the values `KudosBackupManifest` ends with. Records are decoded one at a time with
`KudosBackupContents.makeDecoder()` (ISO-8601 dates, fractional or whole seconds, clamped to now + skew), so record defaults
and unknown record fields are exactly the existing code's.

| Key | Required | Missing | `null` | `[]` / empty | Wrong kind | Elements | Staging table (natural keys, all indexed) |
|---|---|---|---|---|---|---|---|
| `version` | yes | schema | schema | n/a | schema | `Int`; must be in 1…8, else **unsupported version** (only after everything else decoded) | `member`/`payload` |
| `exportedAt` | yes | schema | schema | n/a | schema | ISO-8601 date | `member`/`payload` |
| `works` | yes | schema | schema | `[]` | schema | strict | `rec_works`: id, ao3 work id, source URL |
| `bookmarks` | yes | schema | schema | `[]` | schema | strict | `rec_bookmarks`: id, URL |
| `fonts` | yes | schema | schema | `[]` | schema | strict | `rec_fonts`: case-folded name (file name in `k_text`) |
| `collections` | no | `[]` + in `omittedKeys` | `[]` + in `omittedKeys` | `[]` (authorises Replace sweep) | schema | strict | `rec_collections`: id, name |
| `readingQueues` | no | `[]` + in `omittedKeys` | same | `[]` | schema | strict | `rec_readingQueues`: id, name |
| `annotations` | no | `[]` + in `omittedKeys` | same | `[]` | schema | strict | `rec_annotations`: id, work id, passage (locator) |
| `savedSearches` | no | `[]` + in `omittedKeys` | same | `[]` | schema | strict | `rec_savedSearches`: id, name |
| `readingQueueMemberships` | no | `[]` | `[]` | `[]` | schema | strict | `rec_readingQueueMemberships`: id, work id, queue id |
| `readingSessions` | no | **nil** | nil | `[]` | schema | strict | `rec_readingSessions`: id, work id, ao3 id, URL |
| `readingFavorites` | no | nil | nil | `[]` | schema | strict | `rec_readingFavorites`: id, target (`kind␟targetKey`) |
| `fandomReadWatermarks` | no | nil | nil | `[]` | schema | strict | `rec_fandomReadWatermarks`: id, case-folded fandom |
| `followedTags` | no | nil | nil | `[]` (kept as `[]` by the decoder) | schema | strict | `rec_followedTags`: id, ao3 tag id, case-folded name |
| `tagAliases` | no | nil | nil | `[]` | schema | strict | `rec_tagAliases`: id, case-folded name (canonical in `k_text`) |
| `tombstones` | no | `[]` | `[]` | `[]` | schema | strict | `rec_tombstones`: id, record id, ao3 id, URL, type (`k_text`), stamp (`lastModifiedAt`) |
| `settings` | yes | schema | schema | n/a | schema | one `KudosBackupSettings` | `member`/`payload` |
| `pronunciations` | no | `.empty` | `.empty` | n/a | schema | one `KudosBackupPronunciations` | `member`/`payload` |
| `writingRecovery` | no | nil | nil | `[]` | **nil** (absent) | **lossy** | `rec_writingRecovery`: file name |
| `documents` | no | nil | nil | `[]` | **nil** (absent) | **lossy** | `rec_documents`: name, stamp (`modifiedAt`) |
| any other key | n/a | n/a | n/a | n/a | n/a | not decoded; ignored by every consumer today | `member` row (name, kind, length, source order); no payload |

Absent is not empty (T-563): the four `omittedKeys` arrays (`collections`, `readingQueues`, `annotations`, `savedSearches`) are
in `omittedKeys` when the key is **missing or `null`**; Replace Library must not sweep for them. A present `[]` authorises the
sweep. `readingSessions`, `readingFavorites` and `fandomReadWatermarks` are nil (not `[]`) when missing or `null`, which also
leaves local rows alone. The staging database keeps the distinction as `member.presence` (0 missing, 1 `null`, 2 present, 3 wrong
kind) and the rebuilt manifest reproduces `omittedKeys` and each nil.

Record cross-checks (identity uniqueness, tombstone matching, timestamp clamping against a fixed operation clock) are **not** part
of this contract; they belong to P4's resolve step, which reads the indexed key columns. The reader only guarantees that the keys
are there, indexed, in source order (`seq`).

### Record sizes

A record or single value up to `typedRecordBudget` (32 MiB of JSON by default; a supported ~20 MiB recovery copy decodes at about
twice its size) is decoded with the production type while staging. A larger one is syntax-validated and stored as chunks
(`status = deferred`, no natural keys; a known single root value is instead capped, see Resource limits) and its schema is **not** checked while staging; whoever reads it decodes it (P4 streams
oversized supported records field by field). Payloads are stored as rows of at most `chunkSize` (256 KiB) bytes, never one blob.
There is no per-record cap. A strict section's deferred record that would not have decoded is therefore a schema failure found
later, not at staging; this exists only above the budget and is the one place the streaming reader is looser than today.

## 3. Outcomes and what each route does

The reader reports exactly one of: **ok** (a staged run), **invalid document** (`notJSON` or `schema`), **unsupported version(n)**,
**I/O failure**, **cancelled**, **resource exhaustion**. No outcome but ok leaves a staging directory behind, and none is applied
or swept. "Today" is the iOS code path as shipped; "Streaming" is what the same route must do once it uses the reader (the route
code does not change in P2, so the right-hand cells are the rule P4/P5 implement).

| Outcome | Settings preview (`preConfirmManifest`) | Confirmed import (re-open, `init(zipData:)`) | Folder Sync live manifest | Folder Sync `.bak` | Folder Sync conflict versions | Legacy / other |
|---|---|---|---|---|---|---|
| Absent input | ZIP without `manifest.json` → `invalidPackage` | same | decided before the read (first write vs error, `syncDirectoryHoldsNothing`); not a manifest outcome | nil: nothing restored | n/a (versions exist) | legacy directory without `manifest.json` → `invalidPackage` |
| Accepted | typed manifest → preview | typed manifest → restore | restore (`isLive = true`), stamp stored | restore with `isLive = false`, remote stamp withheld | folded through `restore`, version resolved | same as preview |
| Not JSON (`notJSON`) | decode error shown (`DecodingError`) | decode error | **eligible for `.bak`**: the only outcome that is | n/a (read with `try?`: any failure is nil) | error thrown, folding stops, version stays unresolved | decode error |
| Schema rejected (`schema`) | decode error shown | decode error | **throws; not eligible for `.bak`**; a whole document that decodes for another version must not be overwritten | nil (swallowed by `try?`) | error thrown, version unresolved | decode error |
| Unsupported version | `KudosBackupError.unsupportedVersion` | same | throws, as schema | nil | throws | same |
| I/O failure | file error (before decode) | file error | `unreadableSyncFile` / the coordinator's error; **not** a `.bak` trigger (it is thrown before the JSON predicate) | nil | error thrown | file error |
| Cancellation | not cancellable today | not cancellable | not cancellable | not cancellable | not cancellable | not cancellable |
| Resource exhaustion | process killed on a large manifest (P1: 1.7 GiB at 512 MiB) | killed (9.7 GiB) | killed (9.4 GiB) | n/a | n/a | n/a |
| **Streaming rule** | `invalid`/`unsupported`/`io` map to the same user-visible errors as today; `cancelled` ends the preview silently; `resourceExhausted` shows a "not enough free space" error | same | `invalid(.notJSON)` keeps `.bak` eligibility, **every other failure keeps today's protection**: only `notJSON` falls back; `schema`, `unsupportedVersion`, `io`, `resourceExhausted` and `cancelled` throw, leave the stamp alone and never publish | `try?` as today | as today, plus `cancelled` stops without resolving | as today |

Evaluation order per route is preserved: Folder Sync live reads the bytes, applies the whole-document JSON predicate, then the
typed decode and version check; preview and confirmed import go straight to the typed decode. The streaming reader folds the
predicate and the typed decode into one pass and reports `notJSON` before `schema` before `unsupportedVersion`, which is the same
order. A syntax error after an early bad record is still `notJSON`.

## 4. Where the guarantees are tested

All in `KudosTests/ManifestStreaming/ManifestStagingTests.swift` (normal gate unless noted):

- **Differential**: for every manifest in P1's 79-case corpus (both cross-platform fixtures, generated manifests on all three axes,
  field and section variants, byte-level malformed cases) the staged outcome equals `JSONSerialization` + `decodeManifest`, and
  `ManifestStagedRun.manifest()` equals `decodeManifest`'s result, `omittedKeys` and `LossyArray` sections included
  (`stagedOutcomeAndRebuiltManifestEqualTodaysRoute`); again through a file input with 97-byte chunks and a 300-byte typed budget
  so most records are deferred (`fileInputAndTinyChunksAndDeferredRecordsRebuildTheSameManifest`).
- **Presence, order, status, keys, indexes**: `presenceOrderStatusAndNaturalKeysAreStaged`.
- **Chunked oversized value**: `oversizedValuesAreStoredInBoundedChunks`.
- **Depth boundary vs today's route**: `nestingLimitMatchesTodaysRouteAtTheBoundary`. **Evaluation order**: `syntaxErrorAfterASchemaFailureStillReportsNotJSON`.
- **Cancellation** (inside a record and inside one huge string) / **I/O failure** (read error, missing file, file shrunk) / **low disk**
  (before anything is created) / **stale-directory sweep**: each also asserts no staging directory is left.
- Opt-in (`TEST_RUNNER_KUDOS_T567_P2=1`, `ManifestStagingMeasurementTests`): 8/128/512 MiB on the works, sessions and opaque axes
  against P1's thresholds, a 96 MiB opaque value, cancellation latency.

## 5. Not covered here

- Android: the same table filled from `BackupJson.kt` / `BackupValidator.kt` / `SyncRepository.kt` (**see A-567 P2**).
- Deflated `manifest.json` ZIP entries (the prototype and `ManifestFileInput` read stored entries by byte range; every export
  writes stored). A streaming inflater is P5 work.
- A mid-file ENOSPC is mapped (`SQLITE_FULL` → resource exhaustion) but cannot be injected safely on the host disk; the disk
  preflight is tested instead.
- The staging reader is synchronous; callers run it off the main actor inside a `Task` so cancellation reaches it.
