# Brief 5c result — sync and backup interoperability

Review completed by source inspection, 2026-10-04. Implementation is an unbuilt handoff. No builds/tests run, no sign-in, AO3 traffic, commits,
pushes or branch changes. iOS reference read from `/Users/cidy02/kudos-ios-polish/`;
iOS fixes are only in this worktree for Claude to port. Line references below
describe the reviewed code before edits unless stated otherwise. Findings saved incrementally.

## Findings (most severe first)

Finding IDs stay stable while severity controls their order. **Sure** means a
concrete source path was traced, not that a test ran. Every added/changed regression
requires execution by Claude. Android source paths below use
`android/app/src/main/java/io/github/cidy02/kudos/`; iOS source/test references use
the read-only reference lane unless explicitly described as a patch. Partial fixes explicitly retain their residual risks.

### F1 — iOS can erase remote assets while Android replaces the manifest (high)

**Sure from code; provider timing needs integration testing.** Android
`backup/SyncRepository.kt:538–543`, `writeManifestAtomically`, renames live to
`manifest.json.bak` before installing temp. iOS reference
`Services/FolderSyncService.swift:293–300, 414–425, 939–953`, `performSyncDown`,
`performSyncUp`, `writeSyncDirectoryContents`, knows no `.bak` and treats a nil
modification date as permission to prune. State: shared folder lists work A; a new
iPhone lacks A. Input: Android's rename gap is observed on the iPhone. Outcome:
sync-down imports nothing; sync-up publishes the iPhone's library and deletes A's EPUB,
original and fonts. A provider can prolong this gap by uploading renames separately.
Smallest immediate fix is on iOS: distinguish a genuinely empty folder from an
existing payload whose manifest is temporarily absent, and refuse that write. A nil
date on an existing manifest must never authorize pruning. Implemented below; regression tests await execution.

**Patch status:** iOS refuses upload into an existing nonempty payload with no live manifest, and an existing manifest with no date no longer authorizes pruning. Missing-index regression added; it proves retention of the only EPUB and .bak, not recovery from .bak on iOS. This is the smallest cross-platform fix: Android cannot make SAF renames globally atomic for iOS.

### F2 — stale sync-up overwrites the only index even when pruning is skipped (high)

**Sure from code; concurrent/provider test needed.** iOS
`FolderSyncService.swift:384–438` allows sync-up alone; Android
`SyncRepository.kt:269–282` only disables pruning when the manifest changed during
the run. State: remote adds work B after this device's last read. Input: stale device
uploads A only. Outcome: assets survive this pass, but the live manifest forgets B.
iOS stamps its own write and can skip the next read; a later current prune removes B.
The originating device may repair B if it still exists and syncs again; this is not
a safe backup. Proposed: refuse/retry stale uploads after sync-down, comparing manifest
content rather than trusting a provider date; eventual-consistency concurrency still
requires a storage design decision. No format change proposed or made.

**Patch status:** Android compares the visible live manifest bytes immediately before publication and aborts when changed. iOS standalone syncUp first performs syncDown. Strengthened stale-upload tests check the index, not merely surviving bytes. These guards do not solve changes after the check, stale provider caches, or asset overwrites before the check.

### F3 — iOS deletes and cannot read released Android lowercase EPUB names (high)

**Sure from code.** iOS reference `FolderSyncService.swift:726, 942, 1007` reads/prunes
exact uppercase UUID names. State: Android 0.2.1/0.2.2 folder has a listed work and
`Works/<lowercase UUID>.epub` on case-sensitive storage. Input: iOS sync-now.
Outcome: metadata arrives without EPUB; iOS prune deletes the lowercase copy. Archive
restore already accepts both cases. Fix belongs on iOS because released folders must
remain readable; proposed case-insensitive lookup and pruning, keeping canonical new writes.

**Patch status:** iOS reads uppercase or lowercase UUID EPUBs and folds case while pruning works/fonts. The regression uses the existing case-sensitive APFS harness. Port this change to the iOS lane; older released iOS builds remain unsafe for these folders.

### F4 — Android can prune after recovering only an old backup manifest (high)

**Sure from code.** `SyncRepository.kt:148–159, 269–290`: successful import from `.bak`
sets `folderViewIsCurrent = true`. State: damaged live manifest lists A+B, `.bak` lists A;
B's EPUB exists only in the folder. Input: Android sync with unchanged live modification
date. Outcome: `.bak` restores A, outgoing manifest omits B, and B's assets are pruned.
The fallback repairs availability but proves nothing about current membership. Proposed:
never overwrite/prune an unreadable live manifest or a manifest-less recovery window
without first recovering its authoritative index. At minimum, `.bak` must never permit prune.

**Patch status:** Android may import .bak locally, but returns Error without exporting/pruning when the live index is missing or invalid. Recovery tests now require retention rather than automatic rewrite. Folder repair is intentionally a separate action; no old index is declared authoritative.

### F9 — Android folder assets have unchecked sizes and non-atomic replacements (high)

**Sure from code; crash/provider tests needed.** `SyncRepository.kt:217,330–339,412,443–461,
552–564`: EPUBs are whole-byte reads; a 32 MB batch does not bound one file. Originals
trust provider length then use `readBytes`, so length 0/unknown can admit a multi-GB file.
Case correction deletes the old remote asset before creating/writing the replacement;
other writes truncate live bytes. State: folder's only lowercase original/EPUB is intact.
Input: writer fails after delete or truncate. Outcome: old manifest references absent or
partial content; local copy may repair later, but backup is lost until then. iOS uses
atomic per-file writes (`writeIfChanged`). Proposed: retain existing case-variant names
when safely recognized; fail if create/open fails; enforce actual stream limits for
originals. Full crash-safe SAF replacement requires provider semantics and cannot be
claimed from rename/fsync alone. iOS also has no sync EPUB/original read cap.

**Patch status:** Android retains recognized case/NFC asset names, treats null create/output as failure, bounds manifest reads to 8 MiB and actual original streams to 128 MiB. Actual-byte limit regression added. EPUB reads remain unbounded; asset writes still truncate live files, originals upload uses size only, and SAF manifest rename/fsync semantics remain provider-dependent.

### F10 — conflict copies can be discarded before assets arrive, or ignored entirely (high)

**Sure from code; exact provider names are device-dependent.** Android
`SyncRepository.kt:134–139,161–170,366,408`: recognizes case-sensitive
`manifest*.json` siblings, but deletes a decoded copy even when `importManifest`
returns false for missing/unreadable fonts; missing EPUBs/fonts do not even mark
the pass incomplete. State: main manifest A; `manifest (1).json` uniquely lists B
whose assets upload later. Input: Android folds it without B's assets and deletes
the conflict; later devices no longer have that conflict as a recovery source.
iOS (`FolderSyncService.swift:314,539`) handles only `NSFileVersion` conflicts,
not sibling `manifest (1).json` or provider-specific names. A current iOS prune can
delete B's assets while its sibling manifest is ignored. Android's prefix rule
recognizes `manifest (user's conflicted copy).json`, but not names prefixed by a
provider, uppercase names, or a second document named exactly `manifest.json`.
Proposed: leave incomplete/unreadable conflicts unresolved, refuse destructive
sync when an unhandled conflict is present, and define supported provider naming
semantics rather than guessing that every prefix match is ours.

**Patch status:** Android keeps incomplete/unreadable recognized conflicts and refuses publication until resolved. iOS sibling conflict support remains open. Complete conflicts are still deleted after local import but before the final manifest commit: a crash or lost local device in between can strand their only remote index. No conflict-copy recovery guarantee.

### F11 — late/missing assets can be stranded by a successful manifest write (high)

**Sure from code.** iOS `FolderSyncService.swift:738–751,375–379,929–953` deliberately
does not count wholly absent referenced EPUBs; only placeholders/read errors do.
Android `SyncRepository.kt:366,408–415` also skips missing files silently. State:
provider delivers manifest before assets, new receiver has no EPUB/font. Input:
receiver syncs now and writes its metadata snapshot. Outcome: iOS stamps that
snapshot and skips subsequent unchanged reads; no placeholder exists on a generic
provider to force a retry. A missing font has no installed row, so receiver's
manifest can omit it; a current prune can delete its late-arriving file. Android
reads again each run, but overwriting the font's only reference prevents recovery.
This is possible even with locally assets-first writes because upload ordering
is external. Proposed: treat every listed but missing asset as pending and avoid
publishing an incomplete snapshot; owner must choose an eventual retry/abandon rule
for genuinely lost remote files. No format change is needed for a conservative guard.

**Patch status:** Android marks listed missing EPUBs/fonts incomplete, imports available records/assets, then returns Error without rewriting the authoritative manifest or pruning. Updated partial-font tests preserve that index and retry. iOS absent-file/pending behavior remains open. Permanently lost/invalid remote assets can now require folder repair; the guard favors preservation.

### F18 — local file-write failure is reported as successful restore on Android (high)

**Sure from code; fault-injection test needed.** `BackupRepository.kt:257–263,284–285`
ignores `FileWriteResult` for EPUB/font writes after merging/upserting their rows.
State: corrected remote EPUB passes validation; local disk cannot write it. Input:
`writeWorkEpub` returns Failure while keeping old bytes. Outcome: restore reports
success, metadata clock/digest claim the new copy, and sync-up can republish old bytes.
New records can be left hasEpub=true with no file. `writeConversionRecord` failures
are similarly ignored. Proposed: throw on failed required asset writes, set hasEpub
only after success, and reconcile snapshot flags on retry; an actual disk-error test
must cover the metadata-first ordering. Left for Claude's fault-injection pass.

**Patch status:** not patched; metadata/file ordering and injected disk failures require a focused follow-up.

### F23 — Android re-import deletes the preserved original before staging a replacement (high)

**Sure from code.** `files/WorkFileStore.kt:75–77`, `writeOriginal`, calls
`deleteOriginalFiles` (also removing its conversion record) before creating/writing
the temp. State: the only local source PDF and sidecar are intact. Input: re-import
attempt cannot create/write/move its replacement. Outcome: Failure is returned but
the original and its provenance have already gone. Backup restore avoids existing
originals, but this shared method also handles user re-import. Fix made: stage and
install first, then remove the old different-extension source and obsolete sidecar.
Regression creates a blocked destination and proves the previous source/record survive.

**Patch status:** implemented with blocked-destination regression; awaits test execution. Cleanup after a successful install can still fail and leave two sources; this is not a multi-file transaction.

### F24 — Android's supposedly disk-based EPUB gate still filters by the flag (high)

**Sure from code.** `BackupRepository.captureLibrarySnapshot`, around line 215,
filters works by `hasEpub` before checking the file. State: a preserved local work
has intact EPUB bytes but a stale false flag. Input: newer incoming EPUB during
Reconcile, or an overlapping File Merge. Outcome: snapshot says there is no local
file, so the gate permits replacement despite the preservation/overlap rule.
The opposite stale-true/missing-file case was tested; this direction was not.
Smallest fix: inspect each known work's actual path regardless of the flag, and
test snapshot capture followed by a preserved-work merge. iOS's launch reconciliation
and `KudosBackupService.mayReplaceEPUB` explain the intended protection; no format
or Room change is needed.

**Patch status:** Android snapshot capture checks the actual file for every known work. Regression captures a stale-false preserved record and proves merge refuses overwrite.

### F5 — batching advances clocks before later EPUBs can replace their files (high)

**Sure from code.** Android `SyncRepository.kt:403–418` merges the entire manifest per
batch, but `BackupMergeService.kt:181–182` requires strictly newer metadata to replace
an existing EPUB. State: local non-preserved A and B both have old bytes and old clocks;
remote A+B have newer clocks and corrected EPUBs; A fills the first batch. Input: two
batches. Outcome: first merge advances B's metadata without B's bytes; next batch sees
equal clocks and refuses B. Sync-up republishes B's old bytes with its new clock and
digest. This contradicts 5a's claim that batching loses nothing. Proposed smallest fix:
use iOS's newer-or-equal EPUB rule (`SyncMerge.shouldApplyIncoming`), with a regression
that replaces two existing files over separate batches. Equal-clock convergence also
requires this parity correction (Part C6).

**Patch status:** Android accepts equal clocks for ordinary eligible EPUB replacements; a two-existing-work multi-batch regression was added. Residual: earlier whole-manifest batches can change preservation/queue state before later assets are evaluated. A newly preserved later work may still have its file refused; full metadata-once/asset-gate batching needs a follow-up test/design.

### F6 — Android tombstone-row replacement can narrow suppression (high)

**Sure from code.** `BackupMergeService.kt:99–105, 2063–2066` compares only type and
record UUID, while the index suppresses also by AO3 id and canonical URL. State: held
deletion is UUID U, AO3 id A, URL A. Input: trusted peer signs a later tombstone with
the same row id/type/UUID but AO3 id B or a blank URL. Outcome: old A suppressors are
lost; another UUID of work A can resurrect. The row id is unsigned and cannot prove
identity. Proposed: require every signed identity dimension to match before replacing
that row; otherwise retain the local row. Does not affect genuine later same-record deletes.

**Patch status:** Android additionally requires AO3 ID and trimmed case-insensitive URL identity before replacement; signed-identity-swap test added. iOS reference still replaces signed identity on the matching type/record key, and NewestTombstoneWinsTests explicitly permits this. This residual reference behavior needs review: preserve both valid suppressors or retain the old row when identity changes. The Android guard is conservative and can reject a legitimate URL spelling change; it is not a shared canonical-identity policy.

### F7 — a saved search created during Android import is hard-deleted (high)

**Sure from code.** `BackupRepository.kt:305–315`, `applyMergeResult`, compares a new DAO
listing against an earlier snapshot. `search/SavedSearchRepository.kt:33–44`, `save`,
does not acquire `PersistenceGate`. State: merge snapshot contains S. Input: save T
while import reads files/merges. Outcome: T is absent from merged set and is deleted
without a tombstone. Reading-log sweeps use the same pattern (`BackupRepository.kt:385+`).
Proposed: delete only rows explicitly removed from the captured snapshot and still
unchanged at apply time, rather than all rows absent from a stale merged set. A transaction
alone is insufficient if ordinary writes happen between capture and transaction start.

**Patch status:** Android records explicitly removed captured searches and deletes only unchanged captured rows inside a Room transaction. A deterministic capture/save-T/apply regression was added. Replace's separate omission sweep, reading-session/favorite/watermark sweeps and stale upserts still have analogous concurrency gaps; no broad persistence rewrite made.

### F13 — Android's EPUB gate both rejects good packages and accepts non-EPUB ZIPs (high)

**Sure from code; real ZIP64/device reader cases need tests.**
`works/EpubImportMetadata.kt:194–215`: picks the first `.opf` among 4,096 entries,
caps it at 2 MB, looks for itemref/id membership, and only searches for an EOCD
signature. iOS `Reading/EPUB.swift:261–291`, `inspectPackage`, reads the package path
from `META-INF/container.xml` and parses that document. A package document named
`package.xml` or appearing after the scan limit is accepted by iOS and silently
refused by Android. Conversely, ZIP containing a plausible stray OPF but no container
passes Android and can replace good local bytes. EOCD presence alone does not prove
a complete/consistent ZIP central directory or later-entry CRCs. ZIP64 still has a
classic EOCD signature; that alone is not evidence of ZIP64 rejection. Proposed:
validate the container-selected package, never the first suffix match, and validate
the complete ZIP before replacement. Fix requires extending the actual EPUB validator
outside the brief's permitted backup/files patch scope; left explicitly for Claude.

**Patch status:** not patched; validator follow-up outside the authorized backup/files patch scope.

### F14 — Android's real 32 MB font aggregate still cannot converge (high)

**Sure from code.** `SyncRepository.kt:383–391` does not count settled fonts toward
its pass budget but still adds all their bytes to `fontFiles`. Then
`BackupRepository.importPackage:104` / `BackupFontValidator.validate` enforce the
32 MB aggregate on that entire map. State: remote 40 MB fonts, first pass installs
32 MB. Input: second pass includes those 32 MB plus 8 MB new. Outcome: validator
rejects 40 MB; the rest never install. Test uses a small injected pass limit, not
the real validator threshold, and misses this. iOS excludes byte-identical settled
fonts from the incoming set (`FolderSyncService.swift:790–794`). Proposed: skip
settled bytes entirely; retain incomplete manifests until all fonts arrive.

**Patch status:** Android excludes settled font bytes from the incoming map, matching iOS. Existing multi-pass test now retries without simulating another device republishing the original index. It still uses a small injected cap; Claude should add/run a real 32 MiB validator-boundary case.

### F17 — nil/unstable modification dates are not a concurrency token (high)

**Sure from code; provider-specific reproduction needs tests.** iOS
`FolderSyncService.swift:307–316,418` treats missing date as current (F1) and equal
dates as unchanged. Android `SyncRepository.kt:142,269` sees unknown dates as 0 on
both reads, so a changed manifest can pass the prune guard. Constant/coarse dates
hide edits; dates changing on download cause needless reads/stale checks. A missing
EPUB size causes extra reads, not safe bounded reads; originals with size 0 still
pass the precheck (F9). Proposed: manifest byte/digest comparison for local staleness
and an explicit provider concurrency contract. Neither NSFileCoordinator nor Android's
mutex coordinates the other device or its server. A hash detects visible changes,
but cannot stop a later concurrent upload by itself.

**Patch status:** Android uses content rather than dates for the pre-publication guard; the fake provider reports date 0 in the race regression. iOS nil-date prune permission removed, but its equal-date skip/read cache still needs a content/revision policy. A local hash is not a remote conditional commit.

### F25 — record clocks are bounded differently and can dominate valid edits (high)

**Sure from code; cross-device sequence needs tests.** Android
`BackupMergeService.kt:1808–1848`, `sanitizeArchivedLastModifiedAt`, clamps work
metadata/progress to exportedAt and rejects far-future clocks. iOS
`KudosBackupService.restore/apply` and `PersistenceSync.swift:640–675` use record
metadata/progress dates directly; only adopted tombstones are clamped to exportedAt.
State: a stale snapshot exported January 1 carries a work/progress clock of January 20.
Input: both apps reconcile it, then another device publishes a genuine January 10 edit.
Outcome: Android can accept the later genuine edit; iOS's January 20 clock rejects it
and republishes the poisoned clock. Comparing identical manifests therefore does not
prove convergence. Proposed: share the incoming-clock policy on iOS, with existing
progress/metadata separation and tests; not patched. The iOS reference is the side to
change for defensive clock handling, without changing date keys or the format.

**Patch status:** not patched; use one clamp policy across both apps after targeted metadata/progress tests.

### F27 — Android archive limits and whole-memory import break large-backup parity (high)

**Sure from code; memory behavior needs a stress run.** Android
`BackupImporter.kt:17–110`, `BackupVersion.kt:37–41`, and the backup-screen byte read
keep the compressed ZIP and all expanded EPUB/font/original byte arrays in memory.
The compressed cap is 1 GiB and each normal entry 128 MiB; there is no aggregate
expanded EPUB/original cap or entry-count cap. iOS `MiniZip.swift:Limits.backup`
allows 1,000,000,000 bytes per entry, 64,000,000,000 bytes total and 250,000 entries, and lazily inflates assets
while restoring. State: valid iOS backup contains a 129 MiB EPUB. Input: Android
restore. Outcome: whole restore fails; a 129 MiB original is instead silently skipped.
Many highly compressible entries below 128 MiB can exhaust Android memory despite
its compressed cap. Folder EPUBs remain unbounded on both (F9); Android's new
actual-stream cap covers originals only. Proposed: streaming/lazy Android restore
and a deliberate common resource policy; no limit values or format changed here.

**Patch status:** not patched; resource-policy and streaming restore work remain open.

### F29 — Android Replace permanently removes collections/queues that iOS retains (high)

**Sure from code; restore-then-sync regression needed.** Android
`BackupRepository.kt:450–468`, `removeRecordsAbsentFromReplaceSnapshot`, deletes
omitted collections and queues outright (annotations are also DAO-deleted). iOS
`KudosBackup.swift:3387–3412` soft-deletes omitted collections/ordinary queues for
90-day recovery and marks omitted annotations pending deletion. State: owner has a
collection/queue absent from an older archive. Input: Replace restore. Outcome:
iOS retains a recoverable row; Android loses the row, name/order/membership and
cannot recover it from Recently Deleted. A peer may later reintroduce it because
omission is not a deletion signal, but that is not local recovery parity.
Proposed: use existing soft-deletion fields and reference recovery semantics for
collections/queues, retaining the system queue. Not patched; no Room/format change
made. Annotation lifecycle differences need review before copying that behavior.

### F19 — some signed deletions never remove a peer's already-existing copy (medium)

**Sure for bookmarks/annotations from code; full lifecycle test required.** Android
`BackupMergeService.mergeBookmarks` (around 700) and `mergeAnnotations` (around 1730)
filter incoming records but do not sweep existing ones; their apply path also only
upserts outside Replace. iOS `KudosBackup.swift:3124–3153,3780–3810` behaves the same
for these classes. State: both have bookmark/highlight H. Input: one hard-deletes H
and publishes only its trusted tombstone. Outcome: the peer retains and reexports H;
origin refuses stale resurrection but the peer never removes it. A hard-deleted work
with a tombstone only similarly meets existing-row behavior, whereas soft-deletion
records carry isDeleted/deletedAt and normally reach Recently Deleted by LWW. Proposed:
extend the captured-target tombstone sweep used for saved searches/reading logs to
each immediate-delete class, preserving genuinely later edits and Replace semantics.
Cross-platform key compatibility alone does not establish full deletion parity.

**Patch status:** not patched; full existing-row deletion parity remains open despite interoperable signatures.

### F20 — Android restarts Recently Deleted's countdown on repeated sync (medium)

**Sure from code.** `BackupMappers.kt:97–106`, `restoredDeletionState`, always returns
now+90 days for a deleted record. `BackupMergeService.mergeWork` restores that value
on every equal/newer-clock merge; collection/queue merge calls the same function.
State: local deleted work is on day 89. Input: same deleted snapshot is synced again.
Outcome: its deadline returns to day 0; regular sync can prevent expiry forever.
iOS `KudosBackupService.archivedDeletionState` (`KudosBackup.swift:4373–4385`) retains
a local countdown. Proposed: pass existing deleted state/schedule to the helper and
keep it on repeated deletion, using the same helper for works/collections/queues.
No Room schema or backup field change required. Not patched in this pass.

**Patch status:** not patched; countdown-preserving merge helper and regressions remain open.

### F21 — keep/remove-download flags cannot converge to false on Android (medium)

**Sure from code.** `BackupMergeService.mergeWork` (around 515–519) ORs `isSaved`
and `isQueuedForLater` with the local flags even when incoming metadata wins.
iOS `KudosBackupService.apply` uses incomingWins-gated flags. State: both devices
have a kept work; iPhone clears its keep flag without deleting its EPUB (owner's
current rule). Input: later iPhone snapshot reaches Android. Outcome: Android keeps
isSaved=true and republishes it; the newer export does not represent the user's
choice. Queue membership normalization should derive queue flags, not preserve a
removed flag forever. Proposed: use iOS's winning snapshot flag rule while retaining
the EPUB independently. A regression must distinguish kept copies from reading copies.
Not patched in this pass.

**Patch status:** not patched; incoming-wins flags need tests alongside current kept/reading-copy behavior.

### F8 — a conflicting font is duplicated once per EPUB/original batch (medium)

**Sure from code.** `SyncRepository.kt:417,454` supplies the same fonts each time;
`BackupMergeService.kt:762–777,877` chooses a fresh `-restored-N` name whenever local
`f.ttf` has different bytes. It never checks whether the prior suffixed copy already
contains the incoming bytes. State: local f=A, remote f=B. Input: three batches (or
three syncs). Outcome: B appears as f-restored-1, -2, -3; manifest/font selector drift,
unbounded copies and aggregate-limit pressure. Metadata name collisions for queues
and collections instead look up stable ids and do not recreate per batch. Proposed:
reuse a previously restored suffix with identical bytes, and read its bytes during
snapshot capture; stop resubmitting already merged fonts per batch where possible.
The same suffix-without-reuse logic exists on iOS (`KudosBackup.swift:3242–3301`),
so repeated manual restores or remote rewrites can duplicate fonts there too. iOS
usually skips a stable manifest, masking this; Android batching amplifies it.

**Patch status:** Android submits incoming fonts once per importManifest call, then clears the batch map; the combined multi-batch regression checks one collision suffix. Repeated independent imports on either app can still generate more suffixes. No suffix-dedup claim is made.

### F12 — original/conversion pairing can be broken across batches (medium)

**Sure from code.** Android `SyncRepository.kt:443–446` applies the provider-size
filter to each sibling independently; `BackupRepository.kt:145–149` takes a record
only when that import wrote its original. State: oversized/temporarily missing
original but available conversion JSON. Input: sidecar is fetched alone and dropped;
original arrives on the next run without sidecar, or the sidecar arrives after the
original. Outcome: future `originalExists` skips the entire group, so its conversion
record never arrives. Original/file pairing avoids attaching a record to unrelated
local bytes, but lacks deferred recovery. iOS now independently fetches absent
sidecars (`FolderSyncService.swift:839–842`); it can attach a peer's record to a
different local original, so that parity is unsafe to copy blindly. Proposed:
only consume a delayed sidecar after establishing that the existing original
matches the remote original. The existing record has format, converterVersion,
convertedAt and originalFileName, but no original digest; verifying a digest from
that record is impossible. A byte/digest comparison with the remote source can work
without a schema change; adding provenance fields requires an owner decision.

**Patch status:** not patched; original/sidecar delayed-arrival parity remains open.

### F15 — filename equality differs for Unicode, duplicate names and length (medium)

**Sure for the string operations; exact provider behavior needs tests.** Android
`BackupPaths.kt:119–123,134–143,169`, `SyncRepository.kt:366,594`: Kotlin compares
UTF-16 strings and folds case without Unicode normalization. Swift String equality
and Set membership equate canonical Unicode forms. State: manifest font `Café.ttf`
is NFC; provider enumerates decomposed `Café.ttf`. Input: Android `findFile` cannot
find it, outgoing manifest omits the font, and prune can remove it. Case-folding
providers also alias f.ttf/F.ttf; neither app can keep two distinct byte versions at
one path. Android's `childrenByLowercaseName().toMap()` arbitrarily chooses the last
duplicate EPUB; `findFile` chooses one manifest/font. iOS's URL API names only one
entry. Same-name Drive duplicates therefore have no agreed identity. Duplicated EPUB
`UUID (1).epub` or font `f (1).ttf` is unlisted and pruned on either platform; original
conflict suffix is not a UUID and is left alone. Android rejects safe font names over
128 UTF-16 units; iOS `isSafeFileName` has no corresponding cap. Android's restored-collision-name sanitizer replaces combining marks/punctuation
with `_`; iOS collision suffixes retain them. Normal Android font imports generate
UUID filenames, so this discrepancy concerns restored collisions, not every import. Proposed: normalize only lookup/comparison keys, retain actual
file names, and reject ambiguous duplicate remote documents before mutation. Long
name compatibility needs a limit policy decision, not a wire-name migration.

**Patch status:** Android normalizes comparison keys to NFC and folds case for font listing/lookup/reuse/prune; key-equivalence test added. No filenames changed. Actual SAF Unicode behavior, same-name ambiguity and long-name compatibility need separate tests/policy. iOS font reads still use the manifest spelling as a URL; canonical Swift equality alone does not guarantee filesystem lookup on every provider.

### F16 — manifests still lose fields; golden comparisons hide some losses (medium)

**Sure from code.** iOS `KudosBackup.swift:633,3435` carries pronunciation corrections.
Android `BackupManifest.kt:18–39` has no `pronunciations`; `BackupJson.kt:8` ignores
unknown keys. Passing a backup/shared manifest through Android removes that data from
the transport. The iOS golden canonicalizer explicitly removes pronunciations
(`CrossPlatformBackupTests.swift:568`), so it cannot detect this loss. Android also
drops Readium locator platform/engine/version on entity mapping/export
(`BackupMappers.kt:153–154,263+`); both canonicalizers remove them. Current iOS reference does not emit those three provenance keys either. Thus
Android can lose them from an older/future producer, but this is not evidence of
a current iOS export losing an active field. Locator JSON itself survives. Both omit
export metadata, recovery deadlines, collectionIDs and local font selection; deadlines
are intentionally reconstructed for safety, collections carry membership separately,
and local font selection is deliberately kept by `SettingsRepository.replaceAll` /
iOS settings.apply. Android's test also canonicalizes the Saved-for-Later UUID.
Known v8 fields now carried soundly: queue/collection colorHex, reading logs, annotations,
legacyReaderProgress and hiddenFromHistoryAt tri-state. Unknown future additive keys
still get stripped by both typed codecs. Proposed: explicit existing-key passthrough
with durable local storage; if Room fields are needed, stop for owner per this brief.

**Patch status:** not patched. Durable pronunciation passthrough/storage needs an owner-approved implementation; a Room schema change is prohibited here. Current fields and golden exclusions audited below.

### F22 — Android can prune a stranger's original whose name uses a short UUID (medium)

**Sure from code.** `BackupPaths.parseOriginalFileName` accepts Java's permissive
`UUID.fromString("1-1-1-1-1")`, which expands the components. iOS `UUID(uuidString:)`
requires the full UUID form. State: `Originals/1-1-1-1-1.pdf` was left by the owner,
not written by Kudos. Input: current Android prune with no matching work. Outcome:
the file is classified as ours and deleted, violating 5b's stranger-file guarantee.
Fix made: require the parsed UUID's full spelling (case-insensitive) to equal the
name's UUID text. JVM regression added to `BackupPathsTest`.

**Patch status:** implemented with a JVM parser regression; awaits test execution.

### F26 — automatic legacy migration only reads each platform's own filename (medium)

**Sure from code.** Android `SyncRepository.kt:188` opens only root
`Kudos.kudosbackup` as ZIP; iOS `FolderSyncService.swift:102,462–501` folds only
`KudosLibrary.kudosbackup` (also supporting the old directory package). State: shared
root contains only the other platform's legacy backup. Input: first folder sync.
Outcome: that library is not imported; an empty/new current layout is published.
Legacy files are not themselves deleted, so manual recovery remains possible, but
automatic interoperability is absent and subsequent current-layout sync can hide it.
Proposed: read both existing names/shapes before initializing a new folder. No rename,
new filename, or version is needed; not patched.

**Patch status:** not patched; read both existing legacy shapes/names, retaining originals. This is migration compatibility, not permission to change the format.

### F28 — Android pairing text promises Apple-account trust it cannot provide (medium)

**Sure from code; UI wording only.** `settings/SettingsPages2.kt:767–776`
says devices using the same Apple account are trusted automatically. Android's
`TombstoneTrustStore` reads its local settings, not Apple's ubiquitous key-value
store. State: owner chooses one folder on an iPhone and Android and expects that
message to apply. Input: owner deletes a work without pairing in both directions.
Outcome: Android ignores the iPhone's signed deletion and can reexport its stale
copy. Pairing formats are compatible, but choosing the folder does not pair devices.
Proposed: describe cross-platform manual QR/code pairing explicitly; settings UI is
outside the authorized patch scope, so wording remains unchanged.

## Can one cloud folder serve both apps today?

**Not safely or with full parity today.** The common v8 manifest layout is usable,
and cross-platform pairing is compatible, but the code does not provide a safe
multi-device commit protocol on an arbitrary cloud provider. The patches reduce
specific data-loss paths; they do not certify Google Drive, Dropbox, Box or even
concurrent iCloud/SAF propagation as safe.

The obstacles, in order:

1. **An access route on both devices.** Android needs an installed DocumentsProvider
   exposing a selectable writable directory tree through `OpenDocumentTree`, a
   persistable read/write URI grant, listing/creation/deletion/rename support, and
   working file streams. iOS needs a folder supplied by `.fileImporter([.folder])`,
   a usable recursive security-scoped bookmark, URL enumeration/read/write and
   FileCoordinator support. Both settings and onboarding use these mechanisms;
   neither has a direct Drive API fallback.
2. **Manifest/asset commit and staleness.** Assets upload separately from the index;
   rename steps are not a remote transaction. Android's content check and iOS's
   missing-index guard cannot stop a cloud server exposing stale caches or a write
   after the check. Both can alter the shared asset path before publishing an index.
3. **Conflict and duplicate identity.** iOS understands NSFileVersion conflicts,
   Android some sibling filenames; neither reconciles arbitrary provider names or
   duplicate same-name Drive documents. No universal remote file identity is stored.
4. **Incomplete content and provider metadata.** Late files, placeholders,
   nullable/coarse dates and sizes need retries based on content availability.
   iOS's iCloud-specific download helper does not request a generic provider's
   download or make a partial stream safe; Android trusts streams supplied by SAF.
5. **Remaining semantic parity.** Pronunciations, clock clamping, deletion sweeps,
   recovery countdowns, Replace recovery and large archives remain different.
   Pairing must happen in both directions; one shared folder is not a trust grant.

### Can the folder actually be chosen?

Claude's reported Google Drive Android picker limitation is **not device-verified
here**. If its installed provider does not expose selectable trees, Drive cannot
be chosen by this code. SAF supports provider trees, but providers can block tree
selection or omit required capabilities; registering a Drive app does not prove
that its tree is usable. Nullable date/size metadata is explicitly allowed by the
platform. See [Android SAF documentation](https://developer.android.com/training/data-storage/shared/documents-files)
and [DocumentsContract.Document](https://developer.android.com/reference/android/provider/DocumentsContract.Document).

The claim that **all** third-party iOS providers must be greyed out for folder
selection is not a general platform rule. Apple's directory-access documentation
says the folder picker can access folders from available File Providers. That does
not prove that an installed Drive/Dropbox/Box version implements the required folder
capabilities. Those actual apps' picker availability must be checked on devices;
none was opened or signed into in this review. See
[Apple's directory-access documentation](https://developer.apple.com/documentation/uikit/providing-access-to-directories).

| Location/access route | Can both use the same storage? |
|---|---|
| On My iPhone / Android local app storage | Each is device-local; not one shared folder. |
| iCloud Drive | iOS route exists; Android needs an additional provider/bridge. No built-in Android route in Kudos. |
| One SMB/network share | Potentially: iOS Files network location plus an Android SAF provider exposing that share. Provider operations and concurrent behavior still need tests. |
| Removable USB/filesystem | Potentially usable sequentially on compatible devices/providers. It does not provide unattended cloud sync. |
| A third-party cloud folder provider on both | Conditional on both pickers exposing the same writable tree and on verified operation/consistency semantics. No provider is certified here. |
| Cloud folder mirrored to a real filesystem/share | A bridge may provide access, but cloud propagation still needs a safe commit/conflict design. |
| Direct Google Drive integration | Requires implementation on both apps; the current generic folder picker is insufficient when the provider hides folders. |

For Drive itself: either use a verified provider/bridge exposing folders on both
platforms, or implement owner-selected Drive API access, authentication, stable
folder/file IDs, duplicate-name disambiguation, revisions/retry and a concurrency
strategy. Drive explicitly permits non-unique names within one folder and not all
file types expose size. Matching paths/names alone cannot identify its objects.
See [Drive Files resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
and [folder/file queries](https://developers.google.com/workspace/drive/api/guides/search-files).
No authentication, provider installation or new sync protocol was attempted.

Android's current writer additionally calls `FileDescriptor.sync()` on a provider
file descriptor and ignores null `renameDocument` results. A provider backed by
pipes/virtual files may not support fsync/rename as a local filesystem does. It
also deletes all matching stale temp names, which can remove another device's
in-flight temp if both are visible. These are code-level concurrency/capability
risks needing a real provider harness, not claims that fsync makes cloud writes
atomic. iOS FileCoordinator and Android PersistenceGate/Mutex serialize their own
process/coordination participants, not a phone running the other app.

### Shared-folder walkthrough (Part B)

These traces distinguish the reviewed baseline from the safety patches. Both use
`KudosLibrary/manifest.json`, `Works/`, `Fonts/`, `Originals/`; new UUID asset names
are uppercase in current code. Neither treats a manifest's absence of a work as
proof that the work was deleted during ordinary Reconcile.

| Scenario | What iOS reads/writes/deletes | What Android reads/writes/deletes | Can the peer misread or lose data? |
|---|---|---|---|
| First iPhone sync, then first Android sync (and reverse) | Reads current manifest/assets or its legacy package; restores metadata/assets; writes local union, atomic local files/index; prunes unlisted work/font assets and UUID-owned originals when view is current. | Reads live index or recovery .bak, recognized conflicts or its legacy ZIP; batch restores, writes assets, temp→live/bak index, then prunes. | Ordinary current complete folders mostly interoperate. Released lowercase EPUBs need the iOS patch. With patches, an existing nonempty folder without a valid live index refuses publication. Legacy cross-platform files still need manual restore. |
| An edit on each side | Metadata/progress have separate LWW clocks; tags/memberships merge under their existing rules; up publishes merged library. Standalone up now first reads remote. | Same clock split, digest-based EPUB checks, union/dedup rules; equal clocks now permit eligible asset replacement. | Keep flags can remain true on Android (F21), future clocks differ (F25), pronunciation transport is lost (F16). Same-path asset changes are not associated atomically with competing manifest revisions. |
| One deletes the same work while the other edits | Publishes deleted row/retained EPUB during recovery plus signed tombstone; trusted tombstone suppresses stale incoming identities, newer edits can revive. Existing deleted flag follows LWW. | Same broad protocol; unknown signer is recorded, not adopted; existing/new records follow tombstone and clock gates. | Manual pairing both ways is essential. Deleted-vs-newer-edit outcome depends on clocks, not a conflict dialog. Tombstone-only removal of existing peer rows is incomplete (F19), changed signed identities can lose suppressors (F6), Android restarts deadlines (F20). |
| Both sync at once | FileCoordinator plus local gate; date-based current check; NSFileVersion conflicts folded; local atomic writes can still arrive out of order remotely. | Local mutex/gate; content check before commit; recognized sibling copies folded, assets written before check. | Baseline could overwrite the only index or prune in rename gap. Patches close those visible cases, but no server conditional commit; unrecognized siblings, same-name duplicates, late uploads and overwritten shared asset paths remain unsafe. |
| One device offline for a month | Re-reads if manifest date differs or pending/conflict state requires; merges union and trusted deletion/progress state. | Reads each pass; imports union, trusted deletion/progress, actual content; retains local originals. | Thirty days is within the nominal 90-day recovery period, so normal soft-deleted rows should travel. Untrusted deletion/old clocks, date caching and hard-deleted tombstone-only cases remain. A longer absence past hard deletion increases existing-row resurrection/staleness risk. |
| App updated on only one device | Supports current v8 and older supported backup versions; typed decoding/export can drop unknown additions. Old released iOS still has exact-uppercase sync lookup. | Supports v1–v8 shapes as applicable; newer format versions are rejected rather than guessed; old Android wrote lowercase. | Version acceptance is not field preservation. An old app can strip newer additive keys, and an old iOS build can prune lowercase EPUBs. A minimum safe app-version policy is required; this brief does not drop old support or bump version. |
| Backup restore on one device, then sync | File Merge keeps active overlap/fills gaps; Reconcile LWW; Replace restores snapshot and soft-deletes omitted works/collections/ordinary queues without work tombstones; immediate-delete classes have their own rules. Next upload publishes resulting state. | File Merge/Reconcile similar; Replace soft-deletes omitted works but DAO-deletes omitted collections/queues/annotations. Next sync merges restored state with the folder again. | Replace is a local snapshot action, not an instruction to erase the shared folder. Its soft-deletion flags can still travel; hard-omitted collections/queues may reappear from a peer while local recovery was lost. Fonts/settings have deliberate local exceptions; archive size/write failures and countdown parity remain open. |

On a generic cloud provider the same sequence adds three independent orderings:
this app's local operations, the provider's uploads, and the other device's downloads.
Assets-first locally does not imply assets-first remotely. An uploaded index with
missing assets can be cached as complete on iOS; Android now withholds publication
for missing listed EPUBs/fonts, but not all original/sidecar omissions. A provider
placeholder that exists yet fails to open triggers read failure/pending handling;
one that returns partial bytes can be rejected by the EPUB gate or mishandled by
weaker font/original/sidecar checks. iCloud `.icloud` discovery is not a generic
cloud placeholder protocol. Date changes on download cause extra reads; constant
or rounded dates can hide real changes on iOS. A size of zero is not proof of empty
or bounded content; new Android original reads enforce the actual stream limit.

## What changed

All changes are **uncommitted, unbuilt and untested**, as requested. No manifest
version/key/file/directory names, Room schema, project file, signing settings or
bundle identifiers changed. Existing old-case assets are retained; canonical names
for new writes remain unchanged. Added `BackupMergeResult.removedSavedSearches` is
an internal merge result, not a serialized manifest field.

### Android production

| File (relative to `android/app/src/main/java/io/github/cidy02/kudos/`) | Change |
|---|---|
| `backup/SyncRepository.kt` | Refuse unsafe/incomplete publication; compare live manifest bytes; retain incomplete conflicts and case/NFC asset names; skip settled font bytes; submit fonts once per asset batch sequence; bound manifest/original reads; reject failed create/open. |
| `backup/BackupMergeService.kt` | Equal-clock eligible EPUB replacement; stricter signed tombstone identity replacement; capture searches explicitly swept by merge. |
| `backup/BackupRepository.kt` | Delete only unchanged captured removed searches in a transaction; inspect actual EPUB paths regardless of stale hasEpub flags. |
| `backup/KudosBackup.kt` | Internal captured-search removal list in the merge result. |
| `backup/BackupPaths.kt` | NFC comparison keys; strict full UUID spelling for owned original filenames. |
| `files/WorkFileStore.kt` | Install a replacement original before removing its prior source/provenance. |

Each fix has a nearby iOS file/function citation explaining the reference behavior
or, for safer identity replacement, the remaining reference discrepancy.

### Android regressions

Paths relative to `android/app/src/test/java/io/github/cidy02/kudos/backup/`:

- `SyncRepositoryTest.kt`: recovery refuses destructive publication; zero-date
  concurrent index change; incomplete/unreadable conflicts/fonts; preserved stale-false
  flags; later-existing-EPUB batches plus colliding font; actual original stream cap;
  retry without rewriting the authoritative index; old-case assets retained.
- `IncomingEpubGateTest.kt`: equal clock after earlier metadata-only batch.
- `BackupTrustPhase2Test.kt`: changed signed identity cannot replace held deletion;
  a search created after capture survives apply while the captured tombstoned search is removed.
- `BackupPathsTest.kt`: NFC/NFD keys and short-UUID stranger originals.
- `OriginalsRoundTripTest.kt`: failed re-import retains source and sidecar.
- `FakeTempDocumentsProvider.kt`: optional reported modification date for regression;
  remains the existing fake provider, not a new stub file or real-cloud test.

### iOS production and regressions

- `kudos-ao3-reader/Services/FolderSyncService.swift`: standalone upload reads remote
  first; missing live manifest in nonempty payload refuses publication; no-date
  manifest cannot authorize prune; uppercase/lowercase EPUB read and folded pruning.
  iOS is the correct side for old Android filename compatibility and recognizing
  Android's existing rename window; these are minimal interoperability corrections
  to the reference, not an Android-only workaround or a format change.
- `KudosTests/FolderSyncTests.swift`: rename-gap preservation and lowercase asset
  read/prune. The latter reuses `CaseSensitiveFontTestVolume` so host case folding
  cannot mask lookup failure; Claude must use the existing APFS harness.
- `KudosTests/StaleSyncUpKeepsRemoteAssetsTests.swift`: asserts remote work membership
  survives upload, extending the previous asset-only assertion.

### Documentation

- `docs/android-port/briefs/5c-result.md`: this incremental review/result.
- `TASKS.md`: one Brief-5c claim/handoff, no other task ownership changes.
- `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: brief safety-guard handoff note.
- `docs/REGRESSION_TEST_MATRIX.md`: added regression locations and pending verification.

## For the owner to decide

1. Choose the supported shared-storage route and arrange real iPhone/Android provider
   testing. Direct Drive integration/authentication is a product decision; no sign-in
   or provider implementation has been done here.
2. Define safe concurrent publication and conflict recovery. A journal/per-device
   publication protocol or other wire-layout change would violate this brief; stop
   and design it separately if simple conditional operations cannot meet the goal.
3. Define minimum safe released app versions and upgrade behavior. Old iOS exact-case
   pruning and old additive-field exporters cannot be made safe by patching one Android
   device. No released-build support was removed here.
4. Define common archive/resource limits, oversized-asset reporting and incomplete-folder
   repair/abandon behavior. Current guards intentionally return errors rather than
   replacing an index they cannot reconstruct. Do not automatically promote .bak.
5. Decide durable pronunciation/unknown-key passthrough and conversion provenance.
   If storage requires a Room migration or new backup field, stop for a separate task.
6. Reconcile changed signed identity, existing-row deletion, countdown/Replace recovery
   and kept flags on both platforms. The report distinguishes definite bugs from policy
   choices; no UI wording or deletion lifecycle overhaul was attempted.

## What was checked and found sound

### Part A — all eleven commits and the six review checks

The prescribed baseline diff `git diff f29dd32e..HEAD --` was reviewed for the backup,
WorkFileStore and EpubImportMetadata scope. Unrelated UI changes in the range were
excluded. The verdicts below cover the named eleven commits, not just their tests.

| Commits | Verified intention / gaps |
|---|---|
| `d60ff5a4`, `94f1e444` | New uppercase names and case-insensitive Android listing/prune protect listed works/fonts. Delete/recreate recasing was unsafe (F9); iOS old-case lookup missing (F3); .bak/unreadable-index publication could still lose membership (F1/F4). |
| `932d1e93` | Preserved present-file protection and missing-file refill are structurally sound when actual file set is correct. Snapshot ignored stale-false flags (F24); equal-clock batching differed (F5); actual EPUB validator is weaker/different (F13). |
| `f4da80c3` | Size+digest detects equal-size EPUB edits; exported digest is real local content. Fresh-work batching does not prove later-existing-work replacement (F5) or font idempotence (F8/F14). Batch count is not a per-file bound (F9). |
| `de066460` | Date movement suppresses immediate prune, but overwrites index (F2); unknown dates bypass detection (F17). Content guard now refuses publication for visible change. |
| `0c7db7b0` | Trusted search tombstones sweep matching captured rows with newer-edit escape. DAO sweep raced new ordinary writes (F7); narrow captured removal patched. |
| `0370ebad` | Carries later signed date/signature together, so legitimate later same-identity deletions still verify. Type/UUID alone did not preserve other suppressors (F6); iOS has a related open case. |
| `d8f0d17e` | Mac legacy percent follows progress clock; stale metadata cannot advance it, absent locator is not a reset, moved locator can clear obsolete percent. This is sound from code/tests reviewed, not newly test-run. |
| `b799dda8` | Actual per-font bound/loadability validation exists; incomplete font pass disables prune. Aggregate re-submission (F14), repeated suffix collision (F8) and loss of index reference on publication (F11) remained. |
| `28231dac`, `9cb02ad4` | Originals and sidecars use existing folder shape, map archived work ID to restored/matched ID and skip suppressed works; local originals are preserved. Delayed pairing, stream/size limits, same-size upload and failed re-import remain/materially differed (F9/F12/F23). |

Review checklist coverage: all three prune paths and every current-view transition;
recase failure; captured/apply search race; tombstone identity/signature; actual-file
gate in both flag directions; remapped/skipped originals; repeated-batch fonts,
queue/collection IDs, tombstone adoption and unknown-signers; validator false rejects;
parity; weak tests; and shared-folder filename/size trust boundaries.

Repeated queue/collection name collisions consult stable restored IDs, so they do
not manufacture one new record per batch like fonts. Unknown signer IDs are a set;
adoption clears matching pending IDs. Repeated batches can inflate restore counts
and repeat reconstructed deletion deadlines; summary counts are not evidence of
unique assets successfully installed. Whole-manifest reapplication still deserves
coverage for preservation transitions (F5) and ordinary concurrent writes (F7).

### Part C — the eight known parity questions

| Question | Confirmed/refuted and remaining behavior |
|---|---|
| 1. iOS exact-case sync assets | Confirmed and iOS patch made (F3). Archive restore already checked lowercase; sync did not. |
| 2. Pairing and signed deletion | Compatible QR/code/raw key and payload, so not a format blocker. Both accept `kudos-pub-v1:` plus a full 64-hex key. Payload is UTF-8 newline-separated recordType, AO3 ID or empty, canonical AO3 URL or empty, lowercase record UUID, UTC whole-second deletedAt, lowercase signer key, with no trailing newline. Both use raw Ed25519 64-byte signatures. Manual trust both directions is necessary; Android has no Apple KVS trust channel. Existing-row/lifecycle gaps remain (F6/F19/F28). |
| 3. Each old sync filename ignored by the other | Confirmed (F26), including Android ZIP-only legacy path vs iOS directory package. |
| 4. Limits/memory | Confirmed (F9/F27). Android 128 MiB per entry vs iOS decimal 1 GB; Android compressed cap does not bound all expanded memory. Both folder EPUBs unbounded; Android originals now bound actual stream bytes. |
| 5. Snapshot clock clamp | Confirmed (F25): Android metadata/progress clamp; iOS tombstones clamp only. |
| 6. Equal-clock EPUB replacement | Confirmed baseline difference, Android patch made (F5), preserving existing preserved-file and File Merge overlap rules. |
| 7. Conversion records | Confirmed: Android passes existing iOS records through and creates none for its own conversions. Android originals can therefore lack provenance; delayed source/sidecar pairing differs (F12). |
| 8. Dropped/unwatched fields | Current pronunciation loss confirmed. Both typed codecs drop unknown additions. Golden exclusions listed below; current iOS does not emit locator provenance keys, so their exclusion is an unmonitored compatibility surface rather than a current emitted-field mismatch. |

The golden comparisons strip: exportedAt/exportedBy; all permanent deletion deadlines
(works/collections/queues); work collectionIDs; Readium platform/engine/version; local
reader font selection. iOS additionally removes pronunciations; Android cannot compare
that missing DTO field at all. Both canonicalize UUID case/order and the system queue
identity as applicable. These intentional exclusions are **not full field parity**.
Deadline reconstruction and collection membership representation explain some exclusions;
pronunciation stripping is an actual transport loss. Golden asset/round-trip assertions
must be supplemented by raw-key/digest, lifecycle and behavior assertions.

Other checked protections: archive traversal names and duplicate font names are
validated; trusted signer verification precedes adoption; backup contents never enroll
a key; clamping adopted tombstone lastModified does not change the signed createdAt;
originals are rehomed only for mapped works and not overwritten when a local source
exists; normal sync unions records rather than treating omissions as deletions; fonts
have real signature/table/loadability validation, 4 MiB individual/32 MiB incoming caps;
metadata and progress clocks are separated; annotation/reading-log/color/hidden-history
fields exist on both current DTOs. These observations do not certify the remaining
failure paths listed above.

### Verification and handoff

**Performed:** source/diff review, real-symbol/call-site checks and `git diff --check`.
**Not performed:** Gradle/Kotlin compilation, JVM/Robolectric tests, Swift compilation,
Xcode/iOS/macOS suites, APFS harness, screenshots, real QR exchange, offline/cloud
propagation, crash/disk-full/provider-failure or large-memory stress tests.

Claude should first compile Android and port only the three explicit iOS files to
`kudos-ios-polish`, then run changed JVM tests and the existing full suites, including
`Scripts/verify.sh` with the case-sensitive harness. Add real-threshold 32 MiB fonts,
late/conflicted assets, equal-clock preservation transitions, disk failures and the
unfixed deletion/countdown/Replace/clock cases before claiming parity. The fake SAF
provider's local rename/fsync and one-file-per-name model cannot prove remote atomicity,
duplicate-document handling, nullable-size streams or provider-picker availability.

No commits, pushes, branch changes, builds, sign-in, AO3 contact, stub files, helper
scripts or `.orig` artifacts were made. The working diff is the authorized handoff;
29 findings include partial fixes and explicit unresolved blockers. This task is
ready for Claude verification, not a declaration that the owner's full parity/cloud
goal has been achieved.
