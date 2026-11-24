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
| Leading BOM | `EF BB BF` accepted, also when the input's first window holds fewer than three bytes. |
| Whitespace | JSON whitespace only (space, tab, LF, CR) between tokens. |
| Trailing commas | Accepted in objects and arrays (`{"a":1,}`, `[1,]`). A leading or doubled comma is not. |
| Duplicate key | The **first** value wins; later values are validated and ignored. Compared after unescaping (`"version"` is `version`). |
| Escapes | `\" \\ \/ \b \f \n \r \t \uXXXX`. A lone high or low surrogate escape is rejected; a valid pair is accepted. Raw control characters (< 0x20) in a string are rejected; `0x7F` is allowed. |
| Numbers | JSON grammar (no leading `+`, no leading zeros, no `NaN`/`Infinity`, digits required after `.` and `e`). Value range is decided by the typed decode (`99999999999999999999` as `version` is a schema failure, not a syntax one). |
| Not accepted | Comments, single quotes, unquoted tokens, `;`/`=` separators (Android's lenient decoder accepted some; it stops). |
| Top level | An object is a manifest candidate. An array is **schema at its first token**, before depth or budget checks (shared decision 18). A scalar is not JSON (`notJSON`). Empty input is `notJSON`. |
| Trailing content | Anything but whitespace after the top-level value is `notJSON`. |
| Depth | At most **512 containers on any path, the root included** (a 513th is rejected). This differs from today's `JSONSerialization` by one (it allows 513); the shared decision (`briefs/p2-round3-shared.md` 1) follows Android's convention. Scanning goes on past the limit (iteratively, retaining nothing), so a malformed tail still reports syntax first; a depth rejection of a complete file is its own outcome (`invalidDocument(.depth)`), **not** `notJSON`: it never makes a live manifest eligible for `.bak` replacement (§ 3). Real manifests nest about 5 deep. |
| Key equality | Exact sequence of UTF-16 code units after unescaping, **no Unicode normalisation** (`"é"` and `"e"+U+0301` are different keys, as in `NSString`/`JSONSerialization`). **First value wins at every depth**, enforced by the scanner: a later equal key inside a record is cut out of the bytes the typed decoder (and the stored payload) sees, so nothing depends on how Foundation resolves a repeated key. |
| Strings | Raw control characters U+0000–U+001F inside a string and malformed UTF-8 are syntax errors; escape hex digits are ASCII only (`\uFF10` style is rejected); `0x7F` is allowed. |
| Resource limits | Same on both platforms (new, **pending owner approval**; each is one named constant in `ManifestLimits`): object key <= 64 Ki **UTF-16 code units of the decoded key**; number token <= 64 Ki source characters (incremental JSON number grammar: a bare word is a syntax error, not an over-long number); <= 262,144 **source members** per object at every depth, counted before first-wins dedupe and including inside skipped duplicate values; a known root value (`version`, `exportedAt`, `settings`, `pronunciations`, `exportedBy`, or a known section holding the wrong kind of value) <= 16 Mi **source bytes as written** (whitespace included); distinct decoded keys held for dedupe across open objects <= 10 Mi **UTF-16 code units**. Over a limit is **resource exhaustion**, decided at EOF. Record arrays, records and unknown values have no size limit. Tested at the limit and one over. |
| Leading zeros, missing comma | Rejected as syntax (`08`, `{"a":1 "b":2}`): already so on iOS, identical on Android. |
| Evaluation order | Among **observed** failures: **I/O failure > cancellation > syntax > resource exhaustion > schema > unsupported version.** A syntax failure stops reading; an I/O failure in its unread tail is not observed. Resource limits keep scanning to EOF, so malformed syntax still wins. |
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

### Generated defaults and identity

`KudosBackupBookmark`, `KudosBackupWork`, `KudosBackupReadingSession`, `KudosBackupReadingFavorite`,
`KudosBackupFandomReadWatermark`, `KudosBackupFollowedTag` and `KudosBackupTagAlias` mint a default when a field is missing (a
fresh UUID, `Date()`), differently on every decode. The staging pass decodes such a record once and **stores the record
re-encoded from that value**, so the index (`k_id`, `k_work`) and every later reader (reconstruction, apply) see the same
identity. One clock is captured at staging start and passed through date clamping and generated record defaults. SQLite text is bound and read with explicit byte lengths (a NUL inside a key is
part of the key) and composite identities use separate columns (`k_text` + `k_text2` for a favorite's kind and target).

### Consuming a staged run

Root metadata is paged by `memberPage` / `forEachMember` (including unknown-only traversal). Row metadata is read by keyset (`recordPage` / `forEachRecordMeta`, no OFFSET, no whole-section array); P4 validation batches stop at 200 rows or 16 MiB of record source bytes. Payload bytes are read
only through `readPayload(of:seq:range:into:)`, which streams any byte range of a record to a sink from indexed chunk offsets, so
an oversized value is consumed without being assembled. `shape(of:)` gives the presence-aware view an apply decision needs
(`missing` / `null` / `empty` / `nonEmpty` / `wrongKind`). Cross-record semantic validation belongs to
P3/P4 and run over the final metadata before any mutation or sweep. `manifest()` and `forEachPayload` assemble whole records
and exist as the oracle for tests.

File input records device, inode, size, and modification time at open, and verifies them before each range read and before
publishing a staged run. A changed source is I/O failure. The SQLite component is checked against `1.6 × input bytes + 16 MiB`
at each batch and at success, even when free volume space is ample.

### Record sizes

A record or single value up to `typedRecordBudget` (**8 MiB** of source bytes, shared with Android; a single-value member such as `settings` uses the 16 MiB root-value limit instead; real strict records are KBs, and a 22 MiB strict record decoded to a 166 MiB peak on Android) is decoded with the production type while staging. Payloads are stored as rows of at most `chunkSize` (256 KiB)
bytes, never one blob. There is no per-record cap, with these rules above the budget:

- **Lossy** sections (`writingRecovery`, `documents`): the element is syntax-validated and stored in chunks (`status = deferred`,
  no natural keys); whoever reads it decodes it, and a bad one is skipped then, as today. This cannot accept anything today's
  decoder rejects, because today's decoder skips it too.
- **Strict** records and single values (`works`, `settings`, ...): **resource exhaustion**, never accepted, decided when the run reaches EOF (so a malformed or unreadable tail reports its own class first). A record the existing
  decoder would reject must not slip through unchecked, and decoding an oversized strict record field by field is P4 work. Nothing
  real is near the budget (the largest real records are the lossy ones).

## 3. Outcomes and what each route does

The reader reports exactly one of: **ok** (a staged run), **invalid document** (`notJSON`, `schema` or `depth`), **unsupported version(n)**,
**I/O failure**, **cancelled**, **resource exhaustion**. No outcome but ok leaves a staging directory behind, and none is applied
or swept. "Today" is the iOS code path as shipped; "Streaming" is what the same route must do once it uses the reader (the route
code does not change in P2, so the right-hand cells are the rule P4/P5 implement).

| Outcome | Settings preview (`preConfirmManifest`) | Confirmed import (re-open, `init(zipData:)`) | Folder Sync live manifest | Folder Sync `.bak` | Folder Sync conflict versions | Legacy / other |
|---|---|---|---|---|---|---|
| Absent input | ZIP without `manifest.json` → `invalidPackage` | same | decided before the read (first write vs error, `syncDirectoryHoldsNothing`); not a manifest outcome | nil: nothing restored | n/a (versions exist) | legacy directory without `manifest.json` → `invalidPackage` |
| Accepted | typed manifest → preview | typed manifest → restore | restore (`isLive = true`), stamp stored | restore with `isLive = false`, remote stamp withheld | folded through `restore`, version resolved | same as preview |
| Not JSON (`notJSON`) | decode error shown (`DecodingError`) | decode error | **eligible for `.bak`**: the only outcome that is | n/a (read with `try?`: any failure is nil) | error thrown, folding stops, version stays unresolved | decode error |
| Depth rejected (`depth`; > 512 containers, root included) | decode error shown | decode error | **throws; not eligible for `.bak`** (a complete live file beyond the ceiling is protected, not treated as damaged; today it would be `notJSON` and replaceable) | nil | error thrown | decode error |
| Schema rejected (`schema`) | decode error shown | decode error | **throws; not eligible for `.bak`**; a whole document that decodes for another version must not be overwritten | nil (swallowed by `try?`) | error thrown, version unresolved | decode error |
| Unsupported version | `KudosBackupError.unsupportedVersion` | same | throws, as schema | nil | throws | same |
| I/O failure | file error (before decode) | file error | `unreadableSyncFile` / the coordinator's error; **not** a `.bak` trigger (it is thrown before the JSON predicate) | nil | error thrown | file error |
| Cancellation | not cancellable today | not cancellable | not cancellable | not cancellable | not cancellable | not cancellable |
| Resource exhaustion | process killed on a large manifest (P1: 1.7 GiB at 512 MiB) | killed (9.7 GiB) | killed (9.4 GiB) | n/a | n/a | n/a |
| **Streaming rule** | `invalid`/`unsupported`/`io` map to the same user-visible errors as today; `cancelled` ends the preview silently; `resourceExhausted` shows a "not enough free space" error | same | `ManifestStreamError.isBakEligible` is true for `invalid(.notJSON)` only (tested), **every other failure keeps today's protection**: only `notJSON` falls back; `schema`, `unsupportedVersion`, `io`, `resourceExhausted` and `cancelled` throw, leave the stamp alone and never publish | `try?` as today | as today, plus `cancelled` stops without resolving | as today |

Evaluation order per route is preserved: Folder Sync live reads the bytes, applies the whole-document JSON predicate, then the
typed decode and version check; preview and confirmed import go straight to the typed decode. The streaming reader folds the
predicate and the typed decode into one pass and reports I/O, then cancellation, then syntax, then resource, then `schema`, then
`unsupportedVersion`; the first three of today's order are unchanged. A syntax error after an early bad record is still `notJSON`.

## 4. Where the guarantees are tested

All in `KudosTests/ManifestStreaming/ManifestStagingTests.swift` (normal gate unless noted):

- **Differential**: for every manifest in P1's 79-case corpus (both cross-platform fixtures, generated manifests on all three axes,
  field and section variants, byte-level malformed cases) the staged outcome equals `JSONSerialization` + `decodeManifest`, and
  `ManifestStagedRun.manifest()` equals `decodeManifest`'s result, `omittedKeys` and `LossyArray` sections included
  (`stagedOutcomeAndRebuiltManifestEqualTodaysRoute`); again through a file input with 97-byte chunks
  (`fileInputAndTinyChunksAndDeferredRecordsRebuildTheSameManifest`). The depth boundary is the one deliberate difference from today's route.
- **Presence, order, status, keys, indexes**: `presenceOrderStatusAndNaturalKeysAreStaged`.
- **Chunked oversized value**: `oversizedValuesAreStoredInBoundedChunks`.
- **Shared byte fixtures**: `docs/manifest-fixtures/` is Android's set copied byte-identical (`cases.json` + byte files; `wrapper` with
  `BODY` and `gen` recipes), run by `sharedFixtureCasesHoldExactly`. **Pending Android-owned fixture update:** every case is
  asserted exactly on iOS. The current shared wrapper lacks required iOS `bookmarks`, `fonts` and `settings`; the two malformed
  array-root cases still say `syntax` although decision 18 says immediate `schema`. The suite remains red until Android publishes
  the same updated bytes and expectations to both trees.
- **Depth** (512 containers, root included) and the `.bak` eligibility rule: `nestingLimitIsFiveHundredTwelveContainersIncludingTheRoot`.
  **First wins at every depth, no normalisation**: `firstValueWinsAtEveryDepthBeforeTypedDecode`. **Generated defaults materialised
  once, NUL-safe keys, pair identities**: `generatedDefaultsAreMaterialisedOnceAndKeysSurviveNulAndPairs`.
- **Outcome precedence and split BOM**: `outcomePrecedenceIsIOThenCancellationThenSyntaxThenResourceThenSchema`,
  `syntaxErrorAfterASchemaFailureStillReportsNotJSON`. **Final-boundary disk and cancellation, polls in whitespace and digits**:
  `diskIsRecheckedBeforeSuccess`, `cancellationIsPolledInWhitespaceDigitsAndAtTheFinalBoundary`. **Live key memory**:
  `totalLiveKeyMemoryIsBounded`. **Bounded consumption API and presence shapes**: `keysetPagesAndPayloadRangesAreBounded`,
  `presenceShapesAreExposedForApplyDecisions`. **Sweep**: `staleSweepSparesOpenRunsAndSurfacesFailures`.
- Opt-in (`TEST_RUNNER_KUDOS_T567_P2=1`, `ManifestStagingMeasurementTests`): 8/128/512 MiB on the works, sessions and opaque axes
  against P1's thresholds, a 96 MiB opaque value, cancellation latency.

## 5. Not covered here

- Android: the same table filled from `BackupJson.kt` / `BackupValidator.kt` / `SyncRepository.kt` (**see A-567 P2**).
- **P5 item:** deflated `manifest.json` ZIP entries. `ManifestFileInput` reads a stored entry by byte range, which is what every
  export writes; a deflated entry needs a streaming inflater (and the same limits on output size) and is out of scope for P2.
- A mid-file ENOSPC is mapped (`SQLITE_FULL` → resource exhaustion) but cannot be injected safely on the host disk; the disk
  preflight is tested instead.
- The staging reader is synchronous; callers run it off the main actor inside a `Task` so cancellation reaches it.
