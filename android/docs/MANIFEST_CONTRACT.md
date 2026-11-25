# `manifest.json` contract (A-567 / T-567, P2)

This is the Android column of the shared manifest contract. It follows the
orchestrator's `p2-round3-shared.md` decisions 1–27,
including 18a, 19a and 25a, and the current `backup/streaming/` code. The
on-disk manifest format is unchanged. The earlier external
`out/a567p2-contract-android.md` is superseded by this file.

Status: `ManifestStager` is built and tested but no production route calls it
yet. The current routes use `BackupValidator.decodeManifestWithRaw`, with an
8 MiB whole-manifest cap. The tables distinguish their present behaviour from
the streaming reader's contract; P4/P5 must wire the latter deliberately.

## 1. Accepted input (document level)

| Case | Streaming contract |
|---|---|
| Encoding | Strict UTF-8. Malformed/overlong sequences, lone surrogates and raw U+0000–U+001F in strings are syntax failures. A leading `EF BB BF` is accepted even across read windows; later BOMs are not. |
| Syntax | JSON whitespace only; one trailing comma in an object or array is allowed. Comments, single quotes, unquoted names, `;`, `=`, leading-zero numbers, missing commas, bare words, and non-ASCII escape hex digits fail syntax. Numbers use JSON grammar; typed range errors are schema failures. |
| Root | Object required. A complete array is root-type `schema`, even when it is 513 containers deep or exceeds a resource limit; a truncated or garbage-tailed array is syntax. Scalar and empty inputs are syntax failures. Trailing non-whitespace is syntax. |
| Duplicate keys | First value wins at every depth; all later values are still syntax-scanned. Equality is exact decoded UTF-16 code units, without Unicode normalisation. A duplicate at the live-key limit costs no new key units. |
| Depth | At most 512 containers on a path, root included. On overflow the scanner stops retaining that subtree but continues to EOF, so a malformed tail wins. Complete overflow is `resource`, never eligible to replace a live file from `.bak`. |
| Limits | Key <= 65,536 decoded UTF-16 units; number <= 65,536 source characters; <= 262,144 source members per object, including duplicates and members of skipped values; <= 10,485,760 UTF-16 units of distinct keys across all open objects. Once the member limit is hit, the object's remaining keys are not retained or staged. A known root value, including `exportedBy`, and wrong-kind `documents`/`writingRecovery`, <= 16 MiB **source bytes** including internal whitespace. Records and unknown roots have no general size cap. |
| Precedence | Among **observed** failures: I/O > cancellation > syntax > root-type schema > resource > other schema > unsupported version. Scanning continues after resource/depth failures to find syntax. Syntax stops input reading, so a later unread I/O failure is not observed. Cancellation is checked at read refills and final boundaries. |
| Order | Top-level keys can appear in any order, including `version` and `exportedAt` after arrays. No mutation or sweep occurs during staging. |

The numeric limits are shared engineering decisions pending owner approval.
`ManifestTokenizer`, `StagingSink`, and `ManifestStager` enforce these rules.
`BackupJson` remains lenient for the typed fields (for example, a quoted Int can
decode), after the tokenizer has enforced document syntax.

## 2. Per top-level key

Every known array element is **strict**: the production kotlinx serializer must
decode it or the whole document is schema-invalid. Android has no lossy typed
sections. A missing or `null` optional array becomes an empty list in
`KudosBackupManifest`; a wrong non-null kind is schema-invalid. Unknown record
fields are ignored by typed decoding and retained as char ranges. Dates are
strings at stage time; `StagedManifest.validate(now)` checks their semantics.

| Key | Required | Missing / `null` | Present kind / elements | Staging keys |
|---|---|---|---|---|
| `version` | yes | schema | `Int`, supported 1…8 after all other checks | `root` + `root_chunk` |
| `exportedAt` | yes | schema | string; date validated later | `root` + `root_chunk` |
| `works` | no | `[]` | strict `BackupWork` array | `s_works`: `k_id`, `k_ao3`, `k_url` |
| `bookmarks` | no | `[]` | strict `BackupBookmark` array | `s_bookmarks`: `k_id`, `k_url` |
| `fonts` | no | `[]` | strict `BackupFont` array | `s_fonts`: `k_file`, `k_name` |
| `collections` | no | `[]` | strict `BackupCollection` array | `s_collections`: `k_id` |
| `savedSearches` | no | `[]` | strict `BackupSavedSearch` array | `s_savedSearches`: `k_id` |
| `readingQueues` | no | `[]` | strict `BackupReadingQueue` array | `s_readingQueues`: `k_id` |
| `readingQueueMemberships` | no | `[]` | strict membership array | `s_readingQueueMemberships`: `k_id`, `k_queue`, `k_work` |
| `annotations` | no | `[]` | strict annotation array | `s_annotations`: `k_id`, `k_work`, `k_locator` |
| `readingSessions` | no | `[]` | strict session array | `s_readingSessions`: `k_id`, `k_work` |
| `readingFavorites` | no | `[]` | strict favorite array | `s_readingFavorites`: `k_id`, `k_kind`, `k_target` |
| `fandomReadWatermarks` | no | `[]` | strict watermark array | `s_fandomReadWatermarks`: `k_id`, `k_fandom` |
| `tombstones` | no | `[]` | strict tombstone array | `s_tombstones`: `k_id`, `k_rtype`, `k_rid`, `k_stamp` |
| `settings` | no | default / default | `BackupSettingsPayload` object | `root` + `root_chunk` |
| `exportedBy` | no | `null` / `null` | `BackupExportedBy` object | `root` + `root_chunk` |
| `pronunciations` | no | empty / empty | `PronunciationCorrections` object | `root` + `root_chunk` |
| `followedTags`, `tagAliases`, `writingRecovery`, `documents`, any other key | no | ignored | unknown on Android; syntax-scanned, not typed | `root` + `root_chunk`, `known = 0` |

`StagedManifest.presence()` distinguishes missing, `null`, `[]`, and populated
known arrays. `ReplacePolicy` plans to spare local rows for missing or `null`
`collections`, `readingQueues`, `annotations`, and `savedSearches`, while a
present `[]` authorises a sweep. That policy is not wired into today's merge
route. Android does not generate record IDs or dates during decode; validation
uses the caller's fixed `now` and the staged `exportedAt`. Natural-key columns
are indexed; `NULL` means missing, null, non-scalar or >2,048 captured chars,
so consumers must fall back to the payload. Composite identities have separate
indexed columns. SQLite text values and chunk lengths preserve embedded NUL.

### Consuming a staged run

`rootEntries(afterOrd, limit)` and `records(section, afterOrd, limit)` are
keyset-paged (at most 500 metadata rows); `unknownRanges(..., afterStart,
limit)` is similarly bounded. `readRecord` and `readRoot` send a UTF-16 char
range to a sink from indexed 65,536-char chunks; `StagedChunkInputStream`
converts one chunk at a time to UTF-8 for kotlinx `decodeFromStream`.
`reconstructRaw`, `reconstruct`, and `*InMemory` helpers assemble trees/text
and are intended for tests and small inputs. `validate(now,
onValidatedRecord, onBatch)` checks the five sections covered by
`BackupValidator` (`works`, `bookmarks`, `fonts`, `collections`,
`savedSearches`) one record at a time. It flushes batch accounting at 200
records or 16 MiB of source bytes, whichever comes first. Indexed duplicate
checks occur at each record before its other semantic checks. Callbacks expose
canonical typed projections, but callers must wait for validation to return
before mutating the library.

### Record sizes and disk

Every strict record <= 8 MiB **source bytes** is decoded during staging;
records above that are `resource` after EOF. A successful run has no unchecked
strict rows. Small records decode from compact text; spilled records decode
directly from `StagedChunkInputStream`. Each root value has the separate 16 MiB
source-byte limit and stops spilling when it crosses it. Known root fields are
typed-decoded one at a time from staged chunks. `settings.libraryPageArrangement`
is arbitrary JSON already checked by the tokenizer, so its schema check skips
building a `JsonElement`; pronunciation maps are type-checked entry by entry
and discarded. Unknown roots are syntax-checked
and chunked without a size cap.

The private SQLite component is checked against **2.5 × input bytes + 32 MiB**
at commits, index creation and success, even when the disk reports ample free
space. With unknown input length the budget follows bytes read. Up-front
reservation uses an expected length when supplied. Database initialization
failure closes it; a failed run deletes its directory and surfaces cleanup
failure. `sweepStaleRuns` removes marked, old `manifest-*` directories;
`close()` deletes a successful run. The input is one-pass `InputStream`; Android
does not reread a source file, so decision 24's file-identity recheck is not
applicable here. Staged compact JSON is re-escaped without byte inflation for
short control escapes.

## 3. Outcomes and route effects

The staging reader returns a run or throws `Invalid(syntactic = true)`
(`notJSON`), `Invalid(syntactic = false)` (schema), `UnsupportedVersion`,
`Io`, `Cancelled`, or `ResourceExhausted`. Depth is a resource failure. Every
failure closes and deletes the private run; no staging result applies data.

| Outcome | Backup ZIP / legacy directory | Folder Sync live | `.bak` / conflicts | Streaming recovery rule |
|---|---|---|---|---|
| Absent manifest | `MissingManifest` | handled before decode | absent is ignored | no staged outcome |
| Accepted | import after validation | merge; stamp/update only after success | merge valid copies | publish only after validation |
| Syntax (`notJSON`) | decode error | today's sync may try `.bak` | failed copy ignored today | sole live-file failure eligible for `.bak` (`MALFORMED`) |
| Root/typed schema, unsupported version | decode/version error | today's nullable decode can fall back | failed copy ignored today | protect live file (`PROTECT`); never overwrite it |
| Depth / other resource | today's whole-file path can fail its 8 MiB cap or allocation | same | failed copy ignored today | protect live file |
| I/O | read error | `readLiveManifest` throws, protecting files | failed optional copy ignored today | protect live file |
| Cancellation | current routes are not cancellable in the reader | same | same | protect live file; abandon without mutation |

Today `SyncRepository` treats any unreadable/undecodable live manifest as
unusable for its `.bak` fallback. P4 must narrow fallback to the streaming
reader's `MALFORMED` syntax verdict; complete schema/resource failures and I/O
must protect the live document. `recoveryVerdict()` is the P2 predicate and
returns `MALFORMED` only for syntax; it does not run typed validation. ZIP and
legacy imports still use the old whole-file decoder until wired.

## 4. Where the guarantees are tested

- `ManifestFixtureCasesTest`: the Android-owned, byte-identical 51-case shared
  `manifest-fixtures/` set; exact outcome per case, reconstruction separately.
- `ManifestStagingDifferentialTest`: production decoder comparison, values and
  first-wins behaviour on small supported inputs.
- `ManifestStagingTest`, `ManifestRound2Test`, `ManifestRound4Test`,
  `ManifestRound5Test`: syntax/limits/precedence, presence and Replace policy,
  indexed metadata, cleanup, disk budget, duplicate precedence and root spill.
- `ManifestRound6Test`: direct staged-chunk decode with Unicode and escapes at
  the 65,536-char boundary, compared with string decode and reconstruction.
- Opt-in `ManifestStagingLargeTest` (`A567_P2_OUT=<report path>`,
  `A567_TEST_HEAP=256m`): large inputs, three real near-8 MiB records and
  a 15 MiB structured settings root. The former reports sampled/forced-GC live JVM heap peaks. Prior round-6 three-record live peaks
  were 8.4 and 16.7 MiB; sampled peaks were 60.6 and 62.4 MiB. Native SQLite
  memory is outside these JVM heap measurements.

## 5. Not covered here

- Wiring the staging reader, semantic validation and presence-aware Replace
  into ZIP import and Folder Sync is P4/P5 work. The current 8 MiB whole-file
  decoder and its route effects remain in service until then.
- Android has no typed lossy `writingRecovery` or `documents` section; those
  remain unknown roots. Its model does not know iOS `followedTags`/`tagAliases`.
- End-to-end merge checks for queues, annotations, sessions, favorites,
  watermarks and tombstones belong to the later merge phase. JVM heap excludes
  native SQLite/Room memory; physical-device memory verification remains.
