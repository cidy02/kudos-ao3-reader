# Brief 6b result

## Scope and guard differences first

Only `BackupScreen.kt`, `PairingSheet.kt`, and this report are in scope. No Gradle, sign-in, AO3 traffic, commits, pushes, branch switches, or task-board edits.

Android's safety-copy failure blocks Replace outright. iOS's second-attempt warning and “I understand the risks” enable an unsafe override after another failure. That override is intentionally excluded: it would remove Android's existing fail-closed guard and change the import callback's conditions. Showing an override that cannot execute would be misleading. Pre-confirm safety-copy creation and automatic retries would change the existing repository-call timing/count; they are excluded. A non-overwriting safety write is added entirely in this screen, without changing repository calls. iOS also checks saved links/searches/collections/custom queues before calling a library empty; Android’s existing preview only exposes work counts. Broadening that check would add repository/database reads and change which restore callback is offered, so that difference is left for a persistence follow-up. Full details follow below.

## Callback inventory (recorded before editing)

Statements within each row execute in the listed order. “None” means no repository call; local state/picker/clipboard/file operations are still listed. `pending` is the same selected byte array and preview throughout the decision.

| Callback / condition | Before | After |
|---|---|---|
| Export row, `!busy` | `exportLauncher.launch(repository.suggestedExportFileName())` | Same |
| CreateDocument result, null URI | Return, no calls | Same |
| CreateDocument result, non-null URI | Set busy, clear status → `repository.exportV2ZipBytes()` → IO `openOutputStream(uri)`, `out.write(bytes)`, `out.flush()` → status; catch error; finally clear busy | Same |
| Import row, `!busy` | `importLauncher.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))` | Same |
| OpenDocument result, null URI | Return, no calls | Same |
| OpenDocument result, non-null URI | Set busy, clear status → IO `openInputStream(uri).readBytes()` → IO `BackupImporter.importV2Zip(bytes)` → `repository.previewImport(pack)` → `settingsRepository.settings.first().sync.isEnabled` → store pending; catch error; finally clear busy | Same; decoded manifest also retained only for display counts |
| Import dismiss / Cancel | `clearPendingImport()` → `pendingImport = null`; no repository call | Same |
| Empty-library Restore, `preview.isLibraryEmpty` | `runImport(BackupImportMode.MERGE, pauseSync = false)` | Same |
| Non-empty Merge | `runImport(BackupImportMode.MERGE, pauseSync = false)` | Same |
| Non-empty Replace, enabled after removal acknowledgement (unless zero removals) + 1.5 s | `onReplace(pending.syncEnabled && pauseSync)` → `runImport(BackupImportMode.REPLACE_LIBRARY, pauseSync = pauseSync)` | Same final repository callback; additional UI review + acknowledgement even for zero removals precede it |
| `runImport`, missing pending | Clear pending then return; no repository call | Same |
| `runImport`, MERGE | Capture and clear pending → busy/status → `repository.importV2ZipBytes(pending.bytes, mode)` → `summary.toUserMessage()` → status; catch; finally clear busy | Same |
| `runImport`, REPLACE_LIBRARY | Capture and clear pending → busy/status → Documents directory fallback/mkdirs → `repository.suggestedSafetyBackupFileName()` → `repository.exportV2ZipBytes()` → IO `file.writeBytes(safetyBytes)` → store safety filename → **if `pauseSync && pending.syncEnabled`**, `settingsRepository.updateSyncIsEnabled(false)` → `repository.importV2ZipBytes(pending.bytes, mode)` → `summary.toUserMessage()` → append safety/sync status; catch; finally clear busy | Same repository calls, arguments, order, and conditions; safety file write now uses `Files.write(file.toPath(), safetyBytes, CREATE_NEW, WRITE)` and refuses an existing undo copy |
| Removal acknowledgement | `acknowledgeRemoval = it`; effect resets armed state, cancels old delay through effect key, waits `delay(1_500)` if zero removals or acknowledged | Review step resets on return/re-entry; acknowledgement is now required for zero removals too (added iOS guard) |
| Pause sync checkbox (only `pending.syncEnabled`) | `pauseSync = it`, initially true | Same |
| Trust-set effect | `trustStore.trustedDevices()` when `trustedHexes` changes | Same |
| Unknown-signer effect | Count `unknownSignerIds.size`; no repository call | Same |
| Unknown-signer badge (count > 0) | `showSheet = true`; does not reset unknown-signers | Same |
| Pair button | `showSheet = true` | Same |
| Trusted-device Rename button | `renaming = true` | Same |
| Rename draft | `nameDraft = it` | Same |
| Rename Save | `onRename(nameDraft)` → coroutine `trustStore.rename(device.publicKeyHex, newLabel)` → `trustStore.trustedDevices()`; close editor | Same |
| Undo Trust (trusted within 24 hours) | Coroutine `trustStore.undoTrust(device.publicKeyHex)`; only if true, `trustStore.trustedDevices()` and success status | Same |
| Revoke (outside 24-hour window) | `revokeTarget = device`; no repository call | Same |
| Revoke dismiss / Cancel | `revokeTarget = null` | Same |
| Revocation reason radio controls | Assign `STOLEN_OR_COMPROMISED` or `RETIRED_OR_SOLD`; first is default | Same |
| Revoke confirmation | `onConfirm(reason)` → coroutine `revocationService.revoke(target.publicKeyHex, reason)` → `trustStore.trustedDevices()` → **only stolen/compromised**, `revocationService.restoreWorksDeletedBy(target.publicKeyHex)` → status; clear revoke target | Same |
| Pairing sheet dismiss | `showSheet = false` | Same |
| Pairing key effect | `TombstoneSigning.publicKeyHex()` | Same |
| Show / Hide QR | `showQr = !showQr`, enabled only for nonblank device key; display uses `PairingKeyCodec.encode(deviceHex)` and remembered `QrCodeGenerator.encode(payload)` | Same |
| Copy key | `clipboard.setText(AnnotatedString(PairingKeyCodec.encode(deviceHex)))`, enabled only for nonblank device key | Same |
| Advanced | `showAdvanced = !showAdvanced` | Same |
| Pasted-key input | `pasteText = it; error = null` | Same |
| Own-device confirmation | `confirmedFromOwnDevice = it` | Same |
| Trust, enabled by `PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice)` | `PairingKeyCodec.decode(pasteText)`; null → error/return; otherwise coroutine `trustStore.trust(hex)`; true → `justTrustedHex = hex`, false → error | Same |
| New trusted-device name input | `trustLabel = it` | Same |
| Done | Get `justTrustedHex`, null → return; coroutine **if `trustLabel.isNotBlank()`**, `trustStore.rename(hex, trustLabel)` → `onTrusted()` → coroutine `trustStore.trustedDevices()`; close pairing sheet | Same |

New UI-only callbacks: “Replace Library…” sets `reviewingReplace = true`; “Back” sets it false and clears acknowledgement; “Close” in Backup’s pairing sheet invokes the existing `onDismiss`. None calls a repository. Cancel and swipe/back dismissal still clear the whole pending import; Back is separate so the old Cancel callback keeps its behavior. The new “This device” display reads the existing `TombstoneSigning.publicKeyHex()` once through `remember`; it does not trust a key or persist anything. Manifest counts use the already decoded `pack.manifest`, with no extra parse or repository read.

The added guards are the only intentional changes to execution eligibility: a separate Replace review, explicit acknowledgement at zero removals, restarting/cancelling the full 1.5-second wait on review exit/re-entry, and refusing to overwrite an undo copy. They are authorized by brief item 3. Import modes, selected bytes, repository-call arguments/order, sync conditions, empty-library branching, and trust/revoke conditions stay the same.

## Page and sheet structure

Read-only iOS references: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/{SettingsBackupPage,BackupImportSheet,PairingSheet,SettingsView}.swift`.

The page uses `SettingsPage("Backup")`, so the existing shell supplies floating Back chrome and the SETTINGS header on the subject wash. No Scaffold, TopAppBar, Material Card, or metadata chips render on Backup. The main section follows `BackupSettingsSection`: Export, Import, indeterminate progress, footer. Existing Android compatibility/privacy warnings remain visible as footnotes below it. Existing device actions remain afterward in a `Deletion signing` section; they are not removed merely because current iOS Backup contains only the archive section.

The import sheet follows `BackupImportSheet`: This backup (Library records, Saved links, Reading queues, Collections, Custom fonts), Merge, then Replace Library…. The empty-library Restore confirmation/action is retained. Replace review follows `ReplaceLibraryConfirmationView`: This backup (local count, incoming count, added, removed, in both), smaller-file warning, removal acknowledgement, optional pause-sync toggle/warnings, undo explanation, destructive confirmation, recovery footer. Android still does its safety export at final confirmation, not when review opens.

`PairingCard(backupChrome = true)` opts Backup into settings panels, form actions and accent tokens. The default is false, preserving Sync Folder’s presentation, text, buttons and callbacks. Pairing’s advanced trust gate, rename/undo/revoke controls and revocation dialog remain. Material Card/AssistChip code remains only in the default presentation needed by that other caller.

## Every user-visible string, before and after

Interpolation expressions below represent live counts, filenames, labels, keys or error details; they are not replacement sample data. Concatenated strings are shown as the complete rendered sentence. Repeated uses of a label are grouped. Pure MIME types, empty initial values, and the internal `Documents` directory name are not displayed. “—” means absent. This comparison is for Backup’s opt-in presentation; Sync Folder retains its original strings.

### Changed or removed Android strings

| Before | After |
|---|---|
| `Portable Kudos backups keep Library data, EPUB files, fonts, and settings separate from AO3 session data.` | `Your backup file includes your Library, Reading Queues, downloaded copies, User Tags, saved links, custom fonts, imported original files, and app settings. Importing adds anything you don't have without removing what is already here. Your AO3 sign-in and password are never included.` |
| `Compatibility` | — (information retained in footnote) |
| `Privacy` | — (warnings retained in footnote) |
| `Import and export` | — (Export/Import section in iOS order) |
| `v${BackupVersion.CURRENT} ZIP` | — (version remains in compatibility footnote) |
| `v1–v${BackupVersion.CURRENT} import` | — (range remains in compatibility footnote) |
| `SAF picker` | — (same Android document picker) |
| `merge or replace` | — (choice described in import sheet) |
| `session excluded` | — (explicit session-exclusion warning retained) |
| `Export saves a portable library archive. Import can merge new works or replace this device's library. Unsigned or untrusted tombstones in the file are not applied.` | iOS archive footer above; existing unsigned-deletion and already-trusted-signer warnings below |
| `Import` | `Import Backup…` |
| `Export` | `Export Backup…` |
| `Restore from Backup` (title) | `Import Backup` (title); `Restore from Backup` action unchanged |
| `Import this backup?` | `Import Backup` (choice); `Replace Library` (review) |
| `Library: ${preview.localWorkCount} works. File: ${preview.fileWorkCount} works. Will add ${preview.willAdd}. Will remove ${preview.willRemove}. In both: ${preview.inBoth}.` | Separate rows: `Works in your library` / `${preview.localWorkCount}`; `Works in this backup` / `${preview.fileWorkCount}`; `Will be added` / `${preview.willAdd}`; `Will be removed` / `${preview.willRemove}`; `In both` / `${preview.inBoth}` |
| `This backup is much smaller than your library.` | `This backup has far fewer works than your current library.` (same Android predicate) |
| `Remove ${preview.willRemove} works that are not in this backup.` | `Remove ${preview.willRemove} works that are not in this backup` (iOS punctuation; now also shown for zero) |
| `Sync will put removed works back. Pause sync for this device?` | `If you leave Library Sync on, it will add the removed works back. Pause it on this device?` |
| `Paired devices` | `Deletion signing` |
| `Pair a device` (page and sheet) | `Pair a Device` |
| `Hide my QR code` | `Hide My QR Code` |
| `Show my QR code` | `Show My QR Code` |
| `Copy Key` | `Copy My Key` |
| `Hide advanced` | `Advanced: paste a key manually` (disclosure text stays constant, as iOS) |
| `Trusted. Name this device so you recognize it later.` | `This device is now trusted. Give it a name you will recognize later.` |

### Unchanged screen strings

| Before | After |
|---|---|
| `Backup` (previous shell title) | `Backup` (subject header) |
| `Export writes ZIP packages at manifest v${BackupVersion.CURRENT} (Apple-compatible).` | `Export writes ZIP packages at manifest v${BackupVersion.CURRENT} (Apple-compatible).` |
| `Import accepts Apple/Android .kudosbackup ZIP versions ${BackupVersion.APPLE_V1}–${BackupVersion.CURRENT}.` | `Import accepts Apple/Android .kudosbackup ZIP versions ${BackupVersion.APPLE_V1}–${BackupVersion.CURRENT}.` |
| `Merge adds works that are not already here. Replace Library makes this device match the file.` | `Merge adds works that are not already here. Replace Library makes this device match the file.` |
| `Unsigned deletion claims in a backup or sync folder are ignored. Signed tombstones apply only from devices you already trust.` | `Unsigned deletion claims in a backup or sync folder are ignored. Signed tombstones apply only from devices you already trust.` |
| `AO3 passwords are never stored.` | `AO3 passwords are never stored.` |
| `AO3 cookies, CSRF tokens, and session files are excluded from backups.` | `AO3 cookies, CSRF tokens, and session files are excluded from backups.` |
| `Backup import treats ZIP paths and filenames as untrusted input.` | `Backup import treats ZIP paths and filenames as untrusted input.` |
| `Working…` | `Working…` |
| `Could not open the chosen location for writing.` | `Could not open the chosen location for writing.` |
| `Exported ${bytes.size / 1024} KB as a v${BackupVersion.CURRENT} .kudosbackup ZIP.` | `Exported ${bytes.size / 1024} KB as a v${BackupVersion.CURRENT} .kudosbackup ZIP.` |
| `Export failed` | `Export failed` |
| `Could not read the selected file.` | `Could not read the selected file.` |
| `Import failed` | `Import failed` |
| ` Current library saved as ${safetyName} first.` | ` Current library saved as ${safetyName} first.` |
| ` Sync paused on this device.` | ` Sync paused on this device.` |
| `Unknown error` | `Unknown error` |
| `$prefix: $detail` | `$prefix: $detail` (same Throwable message/class fallback; CREATE_NEW may now report a file-already-exists error) |
| `This library is empty. Restore ${preview.fileWorkCount} work(s) from the selected backup.` | `This library is empty. Restore ${preview.fileWorkCount} work(s) from the selected backup.` |
| `Restore from Backup` (action) | `Restore from Backup` |
| `Cancel` | `Cancel` |
| `Merge` | `Merge` |
| `Replace Library` (final action) | `Replace Library` |
| `Merge adds works that are not already here. It does not delete local works or apply unsigned deletion claims from the file.` | `Merge adds works that are not already here. It does not delete local works or apply unsigned deletion claims from the file.` |
| `Pause sync (recommended). The sync folder is not wiped.` | `Pause sync (recommended). The sync folder is not wiped.` |
| `Deletions only cross devices you've paired. A backup file can never add a trusted device.` | `Deletions only cross devices you've paired. A backup file can never add a trusted device.` |
| `1 deletion skipped from an unpaired device` | `1 deletion skipped from an unpaired device` |
| `$unknownSignerCount deletions skipped from an unpaired device` | `$unknownSignerCount deletions skipped from an unpaired device` |
| `No other devices paired yet.` | `No other devices paired yet.` |
| `Undid trust for that device.` | `Undid trust for that device.` |
| `Revoked. Restored $restored work(s) that device had deleted.` | `Revoked. Restored $restored work(s) that device had deleted.` |
| `Revoked that device.` | `Revoked that device.` |
| `Unnamed device` / custom device label | `Unnamed device` / same custom device label |
| `${device.publicKeyHex.take(8)}…` | `${device.publicKeyHex.take(8)}…` |
| `Rename` | `Rename` |
| `Undo Trust` | `Undo Trust` |
| `Revoke` | `Revoke` |
| `Name this device` | `Name this device` |
| `Save` | `Save` |
| `Scan this device's code from your other device. Kudos on Android never scans a code itself.` | `Scan this device's code from your other device. Kudos on Android never scans a code itself.` |
| `QR code of this device's public key` (accessibility) | `QR code of this device's public key` |
| `Advanced: paste a key manually` | `Advanced: paste a key manually` |
| `Other device's key` | `Other device's key` |
| `kudos-pub-v1:… or 64-char hex` | `kudos-pub-v1:… or 64-char hex` |
| `I got this key from my other device` | `I got this key from my other device` (also toggle accessibility label) |
| `Trust` | `Trust` |
| `Not a recognizable Kudos device key.` | `Not a recognizable Kudos device key.` |
| `That key can't be trusted (it may be revoked).` | `That key can't be trusted (it may be revoked).` |
| `Generating…` / full `deviceHex` | `Generating…` / same full `deviceHex` |
| `Device name` | `Device name` |
| `e.g. Sam's iPhone` | `e.g. Sam's iPhone` |
| `Done` | `Done` |
| `Revoke ${device.label.ifBlank { "this device" }}?` | `Revoke ${device.label.ifBlank { "this device" }}?` |
| `Why are you removing this device?` | `Why are you removing this device?` |
| `Stolen or compromised` | `Stolen or compromised` |
| `Retired or sold` | `Retired or sold` |

### Added strings

| Before | After |
|---|---|
| — | `SETTINGS` (existing `SettingsPage` kicker) |
| — | `This backup` |
| — | `Library records` / `${pending.manifest.works.size}` |
| — | `Saved links` / `${pending.manifest.bookmarks.size}` |
| — | `Reading queues` / `${pending.manifest.readingQueues.size}` |
| — | `Collections` / `${pending.manifest.collections.size}` |
| — | `Custom fonts` / `${pending.manifest.fonts.size}` |
| — | `Merge keeps everything already on this device and adds anything you don't have from the backup. It removes nothing.` |
| — | `Replace Library…` (opens review only) |
| — | `Replace makes this device match the backup. Your works, reading positions, notes, collections, and queues change to match it, and anything missing from the backup is removed. You will confirm before it starts, and Kudos saves a copy of your current library first.` |
| — | `Pause Library Sync on this device` (also toggle accessibility label) |
| — | `Replace only changes this device. Removed works go to Recently Deleted and can return through Merge; saved links, saved searches, reading history, stars, and fandom visits are deleted completely and remembered as deleted, so Merge will not bring them back. To restore everything, import the saved copy and choose Replace.` |
| — | `Kudos saves a copy of your current library before replacing it. If the copy cannot be saved, your library will not be replaced.` (Android-specific fail-closed explanation) |
| — | `Back` (returns to choice, no import) |
| — | `This device` / same local public key |
| — | `Close` (pairing dismissal) |

The main footer, import counts/labels, Merge/Replace descriptions, Replace recovery footer, warning, pause-sync label/copy, and shared pairing labels use iOS strings verbatim. Android-specific compatibility, privacy, QR-only instructions, empty-library Restore, safety-failure explanation and outcome/error notices stay truthful to its existing behavior.

### Repository-generated outcome strings (unchanged)

`BackupRestoreSummary.toUserMessage()` is unedited. The screen still displays its full result, followed by the unchanged safety filename and sync suffixes above. Conditional fragments are preserved exactly:

| Before | After |
|---|---|
| `$worksCreated work(s) added` | `$worksCreated work(s) added` |
| `$worksUpdated work(s) updated` | `$worksUpdated work(s) updated` |
| `$worksRemoved work(s) removed from this library` | `$worksRemoved work(s) removed from this library` |
| `$worksSuppressed previously deleted work(s) skipped` | `$worksSuppressed previously deleted work(s) skipped` |
| `${bookmarksCreated + bookmarksUpdated} bookmark(s)` | `${bookmarksCreated + bookmarksUpdated} bookmark(s)` |
| `${fontsCreated + fontsUpdated} font(s)` | `${fontsCreated + fontsUpdated} font(s)` |
| `${collectionsCreated + collectionsUpdated} collection(s)` | `${collectionsCreated + collectionsUpdated} collection(s)` |
| `${savedSearchesCreated + savedSearchesUpdated} saved search(es)` | `${savedSearchesCreated + savedSearchesUpdated} saved search(es)` |
| `${queuesCreated + queuesUpdated} queue(s)` | `${queuesCreated + queuesUpdated} queue(s)` |
| `${membershipsCreated + membershipsUpdated} queue membership(s)` | `${membershipsCreated + membershipsUpdated} queue membership(s)` |
| `${annotationsCreated + annotationsUpdated} annotation(s)` | `${annotationsCreated + annotationsUpdated} annotation(s)` |
| `$annotationsSuppressed deleted annotation(s) skipped` | `$annotationsSuppressed deleted annotation(s) skipped` |
| `Import finished — nothing new to merge.` | `Import finished — nothing new to merge.` |
| `Import finished: ${parts.joinToString(", ")}.` | `Import finished: ${parts.joinToString(", ")}.` |

## iOS guards compared individually

| iOS guard / warning | Android before | Android after / disposition |
|---|---|---|
| Both archive actions disabled while busy | `!busy` for both | Preserved |
| Review selected file before any restore | Preview then confirmation | Preserved, now grouped sheet with incoming record counts |
| Offer Replace only when there is something to remove, counting links/searches/collections/custom queues too | `isLibraryEmpty` checks active work count alone | Existing condition preserved. Non-work-only libraries still get Restore/MERGE. Full parity needs broader preview data/new reads and a deliberate callback-condition change; not silently repaired here |
| Separate choice and destructive Replace review | One dialog had both final actions | Added with no repository calls |
| Explain Merge removes nothing | Existing add-only/unsigned-claims explanation | iOS footer added; old warning retained |
| Explain all classes Replace affects before confirmation | Works delta only | iOS Replace description added |
| Five local/file/add/remove/in-both counts | All five in sentence, from shared identity preview | Same five values in iOS order; incoming records counts also displayed |
| Far-smaller backup warning | `willRemove > 0 && fileWorkCount * 2 < localWorkCount` | Same predicate retained with iOS wording, in both choice and review before either action. iOS uses `willRemove >= 20 && willRemove >= willAdd * 10`; changing the predicate could suppress an Android warning, so it is not changed |
| Explicit removal acknowledgement, including zero | Only when `willRemove > 0` | Added for zero too; original acknowledgement retained for positive count |
| Full 1.5-second delay; uncheck/recheck cannot reuse an old sleep | `LaunchedEffect(acknowledgeRemoval, preview.willRemove)` cancellation | Preserved plus review-step key: Back/re-entry also cancels/restarts; no arming without acknowledgement |
| Destructive visual emphasis | Error-colored disabled/enabled Replace | Preserved on review entry and final confirmation |
| Cancel/back out without deleting | Dismiss clears pending | Cancel/swipe still clear pending. Separate Back returns to choice; neither executes calls |
| Undo/recovery explanation: works can return through Merge; fully deleted record classes need Replace | None | Exact iOS recovery footer added; real Android soft-deletion and immediate-type tombstones checked in `BackupRepository.removeRecordsAbsentFromReplaceSnapshot` and `BackupMergeService` |
| Current-library safety export before removal | Saved in `runImport`, before sync pause/import | Same repository export call and order |
| Create and show successful undo filename **during review** | Only after success, appended to status | Filename still reported after success. Moving safety export to review would change callback timing and create copies even on Cancel; excluded |
| Failed undo-copy creation blocks first attempt | Exception exits try before sync pause/import | Preserved and explained before confirmation; no unsafe fallback |
| Safety creation tries three times per presentation | One export/write per confirmation | One remains. Three tries would repeat `exportV2ZipBytes()` and alter callback count; excluded |
| Undo filename time precision + refusal to overwrite | Seconds precision, but `file.writeBytes` overwrote same-name files | Added atomic **exclusive creation** with `CREATE_NEW` (not atomic full-content writing). Existing filename function/argument stays the same; collision blocks Replace instead of destroying the earlier copy |
| Stage complete safety archive, then atomically install without overwrite | Direct write | Still direct write with exclusive creation. Full staging/cleanup is a persistence-write change beyond callback-preserving restyle. A failed/partial write aborts before import; no unsafe Replace follows |
| First-failure copy: `Could not save an undo copy`; `You can't replace your library until a copy can be saved. Free some space and try again.` | Existing `Import failed: <detail>` after abort | Existing error unchanged; advance fail-closed explanation added. Not pretending a copy was attempted when merely opening review |
| Persist failure across presentations before permitting escalation | None | Not added; Android never permits proceeding without a successful copy. Adding stored retry state or an override would change existing behavior |
| Second-attempt warning: `This is the second attempt. Replacing now will delete works without an undo because no copy of your current library was saved.` | None; failure always aborts | Deliberately excluded: unsafe branch cannot execute on Android, and exposing it would contradict the preserved stronger guard |
| `I understand the risks` explicitly gates iOS’s repeat-failure override | None; no override | Deliberately excluded with the override. It is not a substitute for Android’s mandatory successful copy |
| Successful undo copy resets escalation | No escalation state | Not applicable; mandatory copy on every Replace remains |
| Pause Library Sync offer, default on; warn it can add removed works back | Offered iff captured `sync.isEnabled`, checkbox true | Same condition/default/Boolean argument; iOS wording added, Android “sync folder is not wiped” retained |
| Replace changes only this device | Implicit execution of local repository import | Explicit iOS footer added; no folder wipe or remote action added |
| Guard import against background sync/persistence operations | Repository `PersistenceGate.withLock` | Same locked repository functions; UI busy condition unchanged |
| Hold scoped source + identity; reject source swapped after confirmation | Android reads the selected URI to its pending byte array once | Same immutable selected bytes passed to preview/import; later URI changes cannot replace them. iOS’s manifest-only/constant-memory pending representation needs importer/repository redesign, excluded |
| Trust only a valid pasted key explicitly confirmed from own device | `PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice)` | Identical gate/arguments; no automatic trust from a backup |
| Refuse revoked key, show trust errors | `trustStore.trust(hex)` and two explicit error messages | Preserved |
| Name trusted device locally, never take name from QR | Initially blank `trustLabel`, local rename only if nonblank | Preserved |
| Undo Trust only within 24 hours | Duration check + store undo guard | Preserved |
| Revoke requires choosing reason; stolen/compromised default | Revoke dialog/radios; safe default | Preserved; stolen path still restores works deleted by that device |
| Unknown signer prompt is count-only; opening it never automatically trusts | Count badge → sheet | Preserved. iOS also resets prompt tracking; Android does not, and no reset call is added |
| Apple-account peers automatically trusted; QR scanning on iOS | Android neither does Apple-account trust nor scans | Truthful Android instructions retained. No scanning, sign-in, account service or new trust behavior added |

## Left out and why

First-class gaps are listed at the top and in the guard table: non-work-only Replace eligibility, safety export/filename during review, automatic backup retries, atomic full-content staging, and iOS’s persistent repeat-failure/unsafe override branch. Existing external Documents versus internal fallback locations, filename format, archive bytes, success/error details, busy semantics, merge modes, preview predicates, pause-sync conditions, trust defaults and revocation behavior remain.

No change to Room, migrations, archive format, repository code, settings pages, navigation or any other screen. No new dependencies, stub files, helper scripts, `.orig` files, or tests outside the allowed files. No edits in the iOS worktree. No task-board edits or git mutations.

## Verification and handoff

Source-level verification only; Gradle and device UI not run per brief. New project symbols were read in `SettingsChrome.kt`, `SubjectForm.kt`, `SubjectToggle.kt`, `SubjectComponents.kt`, `KudosTokens.kt`, `BackupManifest.kt`, `KudosBackup.kt`, `BackupRepository.kt`, `TombstoneSigning.kt`, `TombstoneTrustStore.kt`, `KeyRevocationService.kt`, and the real call sites in `SettingsPages2.kt` / the app shell. `Files.write` / `StandardOpenOption` use Android’s existing Java NIO API path (`minSdk = 26`).

Compared baseline picker callbacks byte-for-byte after removing the display-only manifest assignment. Compared `runImport` byte-for-byte after replacing just the exclusive-create safety-write block with the baseline `file.writeBytes` expression. Compared all repository call expressions in both edited Kotlin files. Checked absence of old Backup cards/chips/bars, preserved mode/Boolean arguments and warning predicates, full-delay gating, opt-in pairing defaults, allowed-file scope, and whitespace with `git diff --check`. These checks do not establish a compiled or visually verified UI. An optional tree-sitter Kotlin parse was attempted but could not start because its grammar-cache lock is outside the writable sandbox; no syntax-parse success is claimed. An exhaustive literal-fragment comparison found no before/after screen string missing from the inventory.

Claude: build and run the Android suite afterward, especially `BackupCompatibilityTest`, `BackupRestoreSecurityTest`, `BackupTrustPhase2Test`, `TombstoneTrustStorePairingTest`, and `PairingKeyCodecTest`. Offline/device review should cover empty library; nonempty Merge; Replace Cancel and Back; zero and positive removal acknowledgement; rapid uncheck/recheck; smaller-file warning; sync on/off and pause default; successful undo copy; unwritable/failed copy; existing same-name safety file; document-picker cancellation and malformed ZIP errors; unknown signer prompt; key paste validation + own-device toggle; rename, 24-hour Undo Trust and both revocation reasons; and unchanged Sync Folder presentation. Inspect narrow width, large font, keyboard-open pairing, all four themes and floating chrome. No AO3 access or sign-in is needed.

