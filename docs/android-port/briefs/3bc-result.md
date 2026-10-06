# Brief 3bc result — inventory and implementation record

## Reference discrepancies (iOS code wins)

- §8.3 describes E3/E4 target formats too. The reference implements **E1 only**:
  one JSON file per session. This port keeps E1, with no HTML/meta/journal migration.
- I5 means monotonically newer **accepted** writes, not buffering every checkpoint:
  iOS drops an older sequence after a newer one succeeds. After failure, any next
  call retries the newest received text, even if that call carries older text.
- §8.1 lists mode switches; the reference editor currently has only HTML mode.
  Its concrete forced checkpoints are Done, leaving the editor, restoring a copy,
  inactive/background scene changes, memory warnings, and chapter actions that
  close/checkpoint the editor before acting. Save/Post use the checkpointed form.
- OD4's “Keep as today (included)” matches iOS, but **does not match Android**:
  `AndroidManifest.xml` sets `allowBackup=false`. Backup rules also exclude the
  root domain. No device-backup settings are changed by this brief.
- Exact JSON bytes have no canonical reference fixture: `save` calls the default
  `JSONEncoder()` with no `sortedKeys`, and creates `Date()` internally. Member
  ordering is unspecified and timestamps vary. The JSON values and Foundation date
  epoch are reproducible; universal byte identity to independently generated iOS
  files is not. No iOS test supplies golden JSON bytes. This limitation must not be
  reported as a passing byte-for-byte cross-platform test.

## Inventory read from `/Users/cidy02/kudos-ios-polish/`

### 1. Checkpoints

`Features/Writing/WritingCheckpoint.swift`: idle delay **1,500 ms**, maximum
interval **20,000 ms**. Deadline is the minimum of last edit + idle delay and first
pending edit + maximum interval. Edits record time and start at most one timer;
that timer rereads the deadline on wake. `fireNow` cancels/reset pending timing,
increments the checkpoint count, then calls back even without pending edits.
`cancel` clears timing without checkpointing.

The concrete events above come from `WritingTextEditor.close`, `finish`,
`recoverySheet`, `scenePhase`, and `didReceiveMemoryWarningNotification`.
Explicit close/leave commits composition first; idle, scene and memory checkpoints
do not. Restore is an undoable editor replacement and immediate checkpoint.
The scheduler itself does not fetch text or decide whether text changed.

### 2. Recovery

`Services/WritingTextRecovery.swift`, `WritingRecoveryWriter.swift`, and
`WritingTextEditor.swift`:

| Item | Reference behavior |
|---|---|
| Entry `text` | Exact field string, including empty text, HTML and Unicode |
| Entry `originalDigest` | Lowercase hex SHA-256 of UTF-8 field text at session open |
| Entry `savedAt` | JSON number: seconds since 2001-01-01T00:00:00Z (Foundation default `Date`) |
| Directory | iOS Application Support/WritingTextRecovery; Android filesDir/WritingTextRecovery |
| Field key | SHA-256 UTF-8 of concatenated `n:v` for lowercase account, unchanged target, unchanged field; `n` is each value's UTF-8 byte length |
| Key filename | `<64 lowercase hex digits>.json` (a lookup key, not normally a session copy) |
| Copy filename | `<key>.<sessionUUID>.json`; Swift UUID strings are uppercase |
| Writer | One session writer; newest received sequence starts at 0, last successfully written sequence starts at 0; digest cached once; older/equal successful calls return false |
| Failure | Error propagates; newest pending text retained; next call retries it; no retry timer |
| Install | JSON encoded, then atomic replacement; never delete destination first |
| Prune | After successful save, best effort; retain written file plus four newest other files of this key, by modification date descending, then filename descending; no decoding; unreadable files count; failed deletions ignored |
| List | Matching `<key>.` prefix and `.json` suffix; decode each independently; skip unreadable/missing copies; sort decoded copies by entry savedAt descending |
| Open | Off-thread list/decode; exclude current session filename and text equal to form text; offer all remaining copies (not only copies newer than the form) |
| Offer | Selected copy or first; warn when originalDigest differs from current original's digest; Restore, Keep form text, Delete this copy |
| Successful Save/Post | **Nothing removed**: no recovery cleanup calls in WorkEditView/AddChapterView |
| Other deletion | Explicit Delete this copy and metadata pruning; `allCopyURLs` exposes files, but no caller/Privacy clear action was found in this reference |
| iOS device backup | No isExcludedFromBackup on this directory: normal Application Support backup inclusion |

Copies never enter Kudos's library backup/sync, and contain no credentials or form
tokens. No Room schema or backup format changes are needed.

### 3. Word counting

`Models/AO3WordCounter.swift`, `WritingWordCount`, `KudosTests/AO3WordCounterTests.swift`:

1. Parse an HTML body fragment (SwiftSoup); visit every text node independently.
   Tags, attributes and comments add nothing. Decode entities through the parser;
   use whole text, without whitespace normalization. If parsing fails, count the
   input as text. Traversal skips Comment nodes, not an invented sanitizer list.
2. Within each text node replace non-overlapping `--` with em dash U+2014.
3. Remove ASCII apostrophe U+0027, right/left single quotes U+2019/U+2018, and
   ASCII hyphen U+002D.
4. Every code point whose Unicode **Script** property is **Han**, **Hiragana**,
   **Katakana** or **Thai** is one word, including Thai combining vowels.
   These are property sets (`\p{Han}`, `\p{Hiragana}`, `\p{Katakana}`, `\p{Thai}`),
   not four manually specified block ranges; supplementary Han characters belong
   too. Common/Inherited characters are not assigned to a script by context.
5. Each maximal remaining run from **Alphabetic ∪ M ∪ Nd ∪ Pc** is one word.
   Hangul runs count once; circled letters and Roman numeral letters count;
   superscript/circled numeric characters do not; ZWNJ/ZWJ split runs. Tags split
   adjacent words because counting is per text node (`<b>foo</b>bar` → 2).
6. `WritingWordCount.count` delegates directly to this function. No whitespace split.

## Implementation

New production files (all under
`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/`):

- `AO3WordCounter.kt`: Jsoup body-fragment parsing and independent text-node counts;
  Unicode Script/Alphabetic/category rules, with a direct `WritingWordCount` facade.
- `recovery/WritingCheckpoint.kt`: pure deadline policy and one-timer scheduler.
  Monotonic millisecond clock and coroutine scope are required inputs; no clock
  reads from the scheduler except its supplied function. The future editor owns
  main-thread confinement, composition and lifecycle calls to `fireNow`.
- `recovery/WritingRecoveryWriter.kt`: newest-received/last-successful sequence
  state and cached original digest, on the shared
  `Dispatchers.IO.limitedParallelism(1)` executor. No suspensions inside the write
  block; failures propagate and retain the newest text for the next call.
- `recovery/WritingTextRecovery.kt`: app-private E1 directory factory, UTF-8
  length-delimited keys, uppercase UUID filenames, strict UTF-8 decoding,
  Foundation-epoch JSON, metadata pruning, list/open filtering and individual
  deletion. Temporary file is flushed/synced then atomically moved into place;
  no non-atomic fallback and no delete-before-replace. Temporary files are removed
  in `finally`; after hard process death any abandoned `.tmp` is ignored by lists
  and pruning. Save/Post install no cleanup, matching iOS.

Opening uses canonical Unicode equality as Swift's String comparison does, while
the actual saved text remains unchanged. Reads and deletion exposed for opening
use the same IO executor. Other synchronous store methods are for IO callers/tests.
Nothing outside these foundations or tests calls the new code. No screen, route,
network request, dependency, Room table, backup format or sync integration was added.

## Tests written (not run)

Four new test files under the matching `src/test/java` package contain **40 tests**:
**27** required iOS pure-case names/vectors and **13** supplemental cases. A static
name comparison found no missing names from WritingCheckpointTests,
AO3WordCounterTests, the recovery-only WritingTextEditorTests case, and the two
WritingTextRecoveryBoundsTests cases. Native editor/markup/preview tests belong to
later UI briefs and were not ported here.

- Policy and scheduler names retained; Android virtual time replaces Swift's real
  clock polling. Added sequence-before-callback and moved-deadline checks.
- All nine `AO3WordCounterTests` cases and both `WritingWordCountTests` cases retain
  every vector and expectation. Added supplementary Han, combining mark and ZWJ
  checks. No whitespace-splitting substitute.
- All six writer/list/prune cases from WritingCheckpointTests retain their names,
  including `aCorruptCopyIsSkippedNotFatal`, newest-write retry, unreadable files
  counted during pruning, and preserving an old-dated file currently being written.
- Recovery markup/account/field/session and bounds cases keep their iOS names.
- Added independently calculated ASCII/accented/emoji UTF-8 key vectors,
  whole/fractional/negative Foundation dates, a representative JSON-byte assertion,
  open filtering including malformed JSON/UTF-8, delete/missing-store behavior,
  Swift canonical equality and deterministic metadata-tie pruning.
- A hundred shuffled checkpoint calls are queued. The next save observes the prior
  completed disk copy; the history must be strictly increasing and end at 100.
  Older calls can be skipped, **as in iOS**; this does not claim all 100 snapshots
  must be written.
- Cancellation blocks an active save at its injected clock, queues the remaining
  98 calls before cancellation, verifies the prior JSON is still complete, releases
  the write, joins all jobs, and reopens the store. Disk must contain either the
  previous full text or the full active checkpoint, with no partial JSON/temp file.
  A failed atomic replacement also checks destination preservation and temp cleanup.

### JSON-byte limitation

The representative byte assertion is derived from E1's encoder settings, not an
iOS-generated golden fixture. It verifies compact UTF-8, escaped slash/quotes/newline,
literal Unicode, SHA-256 and the 2001 epoch. Android uses fixed member order
`text, originalDigest, savedAt`, whereas iOS's default encoder does not promise
member order. Arbitrary floating-point lexical rendering can also differ between
Foundation and the JVM even when decoded numbers agree. A captured iOS file at a
known `savedAt` is needed for a true byte comparison; universal byte identity
cannot be guaranteed by the reference as written. No iOS change or invented
“captured” fixture was made.

### Verification and handoff

- Read reference implementations, editor call sites, relevant tests and Android
  dependencies/backup settings. Inspected the cached Jsoup 1.22.2, coroutines 1.11.0
  and serialization-json 1.11.0 APIs with `javap` for the external symbols used.
- Independently checked key SHA-256 vectors and the date epoch using Python.
- Static comparison: 27 required iOS pure-case names, zero missing; 40 written tests.
- `git diff --check` and a whitespace scan covering new/untracked files passed.
- **No Gradle, Xcode or Kotlin compilation/test execution.** Claude must compile
  Android and run these tests (including actual IO ordering/cancellation tests)
  before claiming behavioral parity. The full Android suite remains necessary.
- Actual SIGKILL/relaunch on app-private Android storage and OS suspension are
  untested; coroutine cancellation coverage is written, not an executed device
  process-death result. Atomic-move support should be confirmed on device.
- Unicode property data comes from the runtime, just as iOS's regex comes from ICU.
  Newly added characters outside these golden vectors can vary with OS/JDK Unicode
  versions; no universal Unicode-version parity claim is made without a broader
  cross-platform run.

Open product questions: **none**. Outstanding evidence: compile/test runs, captured
iOS bytes and device process-death/atomic-replacement verification described above.
No commits, pushes, branch changes, TASKS.md edits, iOS edits, helper scripts or
`.orig` files. Device backup remains disabled in Android's manifest; OD4's inclusion
proposal was documented, not applied.
