# Brief 6c result

## Scope and presentation

Changed only `backup/PairingSheet.kt`, the `PairingCard` arguments in `backup/BackupScreen.kt` and `settings/SettingsPages2.kt`, and this report. Paths to Kotlin files are relative to `android/app/src/main/java/io/github/cidy02/kudos/`.

Removed `backupChrome` from all four pairing composables and both callers, together with every false presentation branch and the obsolete `outlined` argument. The former true presentation is now unconditional on Backup and Sync Folder. Its displayed strings, action order, callbacks, defaults and conditions remain. No changes to Room, backup format, service implementations, account access, or network behavior. No Gradle, sign-in, AO3 requests, commits, pushes, branch switches, task-board edits, stub files, helper scripts or `.orig` files.

The Deletion signing content column now pads only vertically. “This device”, its selectable public key, the empty-state text, paired-device name/key blocks and status text get horizontal 13 dp explicitly. `SettingsActionRow` supplies its own 13 dp exactly once for the skipped-deletion prompt, Rename, Undo Trust/Revoke, Save and Pair a Device. The retained Material rename field has a 13 dp container inset; its internal input/label padding still belongs to Material, pending a chrome text-input primitive.

Paired-device actions are settings rows, in the original order: identity, Rename, Undo Trust or Revoke, then the conditional name field and Save. They stack instead of competing with the identity and field for horizontal space. Revoke remains destructive. The revoke reasons use `SubjectFormRow` inside `subjectPanel`, with a separator, retaining radio selection and reason order. Its Revoke/Cancel actions use settings rows. Dialog content can scroll at large text sizes. The pairing sheet keeps its header and instruction order; QR, Copy, Advanced, Trust and Done share the same `PairingAction` settings row/panel. The own-device confirmation remains `SubjectFormRow` + `SubjectToggle`, now on a subject panel.

## Callback inventory: before and after

“Before” is the actual `backupChrome = true` presentation at this worktree's HEAD. Statements execute in the order shown. “Same” includes arguments, conditions, local state changes and coroutine placement; no service call is added or removed. Both callers still pass their original settings repository, database and work repository objects.

| Callback / condition | Before | After |
|---|---|---|
| This-device key display, remembered once | `runCatching { TombstoneSigning.publicKeyHex() }.getOrDefault("")`, then `ifBlank { "Unavailable" }` | Same |
| Trust-set effect, keyed by `trustedHexes` | `trustedDevices = trustStore.trustedDevices()` | Same |
| Unknown-signer effect, keyed by `unknownSignerIds` | `unknownSignerCount = unknownSignerIds.size` | Same |
| Skipped-deletion row, only `unknownSignerCount > 0` | `showSheet = true`; count-only, no reset or trust call | Same |
| Pair a Device | `showSheet = true` | Same |
| Rename | `renaming = true` | Same |
| Rename draft, field only while `renaming` | `nameDraft = it`; initial value `device.label`, remembered by public key | Same |
| Rename Save | `onRename(nameDraft)` → caller launches coroutine `trustStore.rename(device.publicKeyHex, newLabel)` → `trustedDevices = trustStore.trustedDevices()`; `renaming = false` after invoking `onRename` | Same |
| Undo Trust, only `Duration.between(device.trustedAt, Instant.now()) <= Duration.ofHours(24)` | `onUndo` → coroutine `trustStore.undoTrust(device.publicKeyHex)`; **only if true**, reload `trustStore.trustedDevices()` and set `status = "Undid trust for that device."` | Same |
| Revoke row, only outside that undo window | `onRevoke` → `revokeTarget = device` | Same |
| Revoke dialog dismiss / Cancel | `onDismiss` → `revokeTarget = null` | Same |
| Stolen or compromised radio | `reason = KeyRevocationReason.STOLEN_OR_COMPROMISED`; selected iff equal; this remains the initial reason | Same |
| Retired or sold radio | `reason = KeyRevocationReason.RETIRED_OR_SOLD`; selected iff equal | Same |
| Revoke confirmation | `onConfirm(reason)` → coroutine `revocationService.revoke(target.publicKeyHex, reason)` → reload `trustStore.trustedDevices()` → **only if stolen/compromised**, `revocationService.restoreWorksDeletedBy(target.publicKeyHex)` and set restored-count status if `restored > 0`, otherwise revoked status; retired/sold sets revoked status without restoration. `revokeTarget = null` after launching coroutine | Same |
| Pairing sheet dismiss / Close | `onDismiss` → `showSheet = false` | Same |
| Pairing key effect, `LaunchedEffect(Unit)` | `deviceHex = TombstoneSigning.publicKeyHex()` | Same |
| Show/Hide My QR Code, enabled only `deviceHex.isNotBlank()` | `showQr = !showQr` | Same |
| QR display, only `showQr && deviceHex.isNotBlank()` | `payload = PairingKeyCodec.encode(deviceHex)`; `remember(deviceHex) { QrCodeGenerator.encode(payload) }` | Same |
| Copy My Key, enabled only `deviceHex.isNotBlank()` | `clipboard.setText(AnnotatedString(PairingKeyCodec.encode(deviceHex)))` | Same |
| Advanced: paste a key manually | `showAdvanced = !showAdvanced`; label constant even while expanded | Same |
| Paste field, only `showAdvanced` in the not-yet-trusted branch | `pasteText = it; error = null` | Same |
| Own-device confirmation | `confirmedFromOwnDevice = it`, initially false | Same |
| Trust, only advanced and not yet trusted; enabled by `PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice)` | `hex = PairingKeyCodec.decode(pasteText)`; null → recognizable-key error and `return@PairingAction`; otherwise coroutine `trustStore.trust(hex)`; true → `justTrustedHex = hex`, false → can't-trust error | Same |
| Newly trusted device name, only `justTrustedHex != null` | `trustLabel = it`; initially blank, never supplied by QR/key | Same |
| Done, in newly trusted branch | `hex = justTrustedHex ?: return@PairingAction`; coroutine **if `trustLabel.isNotBlank()`**, `trustStore.rename(hex, trustLabel)` → `onTrusted()` | Same |
| Pairing `onTrusted` | Launch coroutine `trustedDevices = trustStore.trustedDevices()`; then `showSheet = false` | Same |
| `PairingAction` dispatch | Pass `onClick` and `enabled` unchanged to `SettingsActionRow` | Same; dead Material button dispatches deleted |

No new behavior callbacks. Switching Material buttons to action rows changes their drawing/layout, while the supplied lambdas remain identical. Reason labels still do not call a callback; the radio controls do. The trust gate, undo time window, revoked-key rejection and conditional restoration stay intact.

## Every user-visible string

No live string changes. These cover all pairing labels, placeholders, messages, dynamic text and accessibility descriptions. Empty initial buffers are omitted. Other Backup/Sync Folder strings are untouched because only the removed named argument changed there. Repeated labels are grouped; expressions describe real runtime values.

| Before (true presentation) | After |
|---|---|
| `Deletion signing` | `Deletion signing` |
| `This device` | `This device` |
| `deviceKey` (local full public key) | Same key |
| `Unavailable` | `Unavailable` |
| `Kudos checks that deletions came from one of your devices. Pair each of your other devices here, and pair this one on each of them: scan its QR code or share its pairing code. Deletions from a device that is not paired are ignored. A backup file can never mark a device as trusted.` | Same complete footnote |
| `1 deletion skipped from an unpaired device` | `1 deletion skipped from an unpaired device` |
| `$unknownSignerCount deletions skipped from an unpaired device` | `$unknownSignerCount deletions skipped from an unpaired device` |
| `No other devices paired yet.` | `No other devices paired yet.` |
| `device.label` | Same local label |
| `Unnamed device` (blank-label fallback) | `Unnamed device` |
| `device.publicKeyHex.take(8) + "…"` | Same eight-character fingerprint and ellipsis |
| `Rename` | `Rename` |
| `Undo Trust` | `Undo Trust` |
| `Revoke` (row and dialog confirmation) | `Revoke` |
| `Name this device` | `Name this device` |
| `nameDraft` (editable paired-device label) | Same draft |
| `Save` | `Save` |
| `Undid trust for that device.` | `Undid trust for that device.` |
| `Revoked. Restored $restored work(s) that device had deleted.` | `Revoked. Restored $restored work(s) that device had deleted.` |
| `Revoked that device.` | `Revoked that device.` |
| `Pair a Device` (section action and sheet title) | `Pair a Device` |
| `Close` | `Close` |
| `Scan this device's code from your other device. Kudos on Android never scans a code itself.` | Same complete instruction |
| `Show My QR Code` | `Show My QR Code` |
| `Hide My QR Code` | `Hide My QR Code` |
| `QR code of this device's public key` (image description) | `QR code of this device's public key` |
| `Copy My Key` | `Copy My Key` |
| `Advanced: paste a key manually` | `Advanced: paste a key manually` |
| `Other device's key` | `Other device's key` |
| `kudos-pub-v1:… or 64-char hex` | `kudos-pub-v1:… or 64-char hex` |
| `pasteText` (editable key) | Same input |
| `I got this key from my other device` (label and toggle description) | `I got this key from my other device` |
| `Trust` | `Trust` |
| `Not a recognizable Kudos device key.` | `Not a recognizable Kudos device key.` |
| `That key can't be trusted (it may be revoked).` | `That key can't be trusted (it may be revoked).` |
| `deviceHex` (sheet's selectable full key) | Same key |
| `Generating…` | `Generating…` |
| `This device is now trusted. Give it a name you will recognize later.` | Same complete instruction |
| `Device name` | `Device name` |
| `e.g. Sam's iPhone` | `e.g. Sam's iPhone` |
| `trustLabel` (editable new-device name) | Same draft |
| `Done` | `Done` |
| `Revoke ${device.label.ifBlank { "this device" }}?` | Same title, including `this device` fallback |
| `Why are you removing this device?` | `Why are you removing this device?` |
| `Stolen or compromised` | `Stolen or compromised` |
| `Retired or sold` | `Retired or sold` |
| `Cancel` | `Cancel` |

Deleted strings existed only in the unreachable false presentation, so no current caller loses visible copy:

| Dead before | After |
|---|---|
| `Paired devices` | Removed |
| `Deletions only cross devices you've paired. A backup file can never add a trusted device.` | Removed; live Deletion signing footnote preserved |
| `Pair a device` | Removed; live `Pair a Device` preserved |
| `Show my QR code` | Removed; live `Show My QR Code` preserved |
| `Hide my QR code` | Removed; live `Hide My QR Code` preserved |
| `Copy Key` | Removed; live `Copy My Key` preserved |
| `Hide advanced` | Removed; live constant Advanced label preserved |
| `Trusted. Name this device so you recognize it later.` | Removed; live naming instruction preserved |

## Material left, and missing chrome

Inspected `settings/SettingsChrome.kt` and all of `ui/subject/`. No new chrome primitives were invented.

| Remaining Material component | Reason |
|---|---|
| Three `OutlinedTextField`s: paired-device rename, pasted key, newly trusted device name | Neither settings nor subject chrome has a text-input component. Existing single-line labels, placeholders, buffers and change callbacks remain. The existing token-mapped `MaterialTheme` still supplies accent and text colors. A chrome input primitive is needed for a complete field restyle. |
| `AlertDialog` revoke container | No generic subject/settings dialog container exists. `HsvColorDialog` is color-specific and itself uses Material `AlertDialog`; it cannot host this content. The retained dialog contains subject reason rows/panel/separator and settings Revoke/Cancel actions. A generic chrome dialog is missing. |
| Two `RadioButton`s | No subject/settings radio or single-choice primitive exists. A toggle would change the meaning of mutually exclusive reasons. Radios keep their original selection predicates/callbacks within the subject form rows. |
| `ModalBottomSheet` and its remembered state | No subject/settings sheet presenter exists. Keep the original modal dismissal and `skipPartiallyExpanded = true`, with settings content inside. |
| Header `TextButton("Close")` | Preserved compact title/Close header from the true presentation. Settings actions are full-width form rows; no compact header action exists in the supplied chrome. Close still invokes the original dismissal callback. |
| `Text`, `MaterialTheme`, typography | Shared chrome itself uses Material text/theme APIs. The original token-to-color-scheme mapping remains; these are text infrastructure, not a second presentation. |

No Material Card, AssistChip, Checkbox, Button, OutlinedButton or ButtonDefaults remains in the pairing file. No Material action buttons remain for Rename, Undo Trust, row Revoke, Save, dialog Revoke/Cancel, Advanced, QR, Copy, Trust or Done. Full input/dialog/radio replacement awaits the missing chrome components; this report does not claim those have been redesigned.

## Verification and emulator handoff

Source verification only; no build/test or emulator success is claimed. Read actual signatures/implementations in `SettingsChrome.kt`, `SubjectForm.kt`, `SubjectComponents.kt`, `SubjectToggle.kt`, `PairingKeyCodec.kt` (also defines `PairingTrustGate`), `TombstoneTrustStore.kt`, `KeyRevocationService.kt`, and both call sites. No new project symbols or dependencies.

A one-off in-memory comparison against `git show HEAD:…/PairingSheet.kt` confirmed all 23 surviving braced callback bodies match baseline after whitespace normalization; the sets of callback bodies match even after deleting dead duplicate controls. Service, codec, clipboard and callback-call expressions retain their source order and arguments. Named callback pass-throughs and live display/trust/undo guards were checked separately. Checked every nonempty baseline/edited literal fragment against this string inventory. A source search confirms no `backupChrome` remains under `android/app/src`, and exactly the definition plus two `PairingCard` calls remain. `git diff --check` passes. Caller diffs contain only removal of the argument and preceding comma.

Claude should compile Android and run the existing pairing/security suites afterward, particularly `PairingKeyCodecTest`, `TombstoneTrustStorePairingTest`, `KeyRevocationServiceTest`, `BackupTrustPhase1Test` and `BackupTrustPhase2Test`.

Offline emulator review must see these states on **both Backup and Sync Folder**, then repeat in **Dark** and at the **largest system text size**, including Dark plus largest text:

- Deletion signing: empty paired list, populated list, one skipped deletion and multiple skipped deletions. Confirm This device, key, device identity, action labels, empty/status text share the intended 13 dp text line; Pair a Device and skipped-deletion prompts have no second inset. Check the remaining Material field's separate internal padding explicitly.
- Pairing sheet from both page actions and the skipped-deletion prompt: original title/Close and instructions; Show/Hide QR, readable full QR, Copy's exact prefixed payload, Advanced expanded/collapsed with its constant label, selectable full key. Closing/swiping/back dismisses without trust.
- Keyboard-open Advanced: blank/malformed/valid key; confirmation off/on; Trust disabled unless valid and confirmed; edits clear errors; own/revoked key failures; successful trust enters the original naming state. Confirm the toggle label wraps without displacing the switch, and Trust/error/Done remain reachable while scrolling.
- Newly trusted name: blank and nonblank Done, local name field/placeholder, refresh after dismissal. Nothing takes a name from the pasted key.
- Paired-device row: long and blank names, short fingerprint, Rename field and Save reachable without horizontal collisions; saved name refreshes. Within 24 hours see Undo Trust; outside see destructive Revoke. Verify Undo success/status and that the actions remain in the original order.
- Revoke dialog: long/blank-name title, both reason labels fully visible, stolen/compromised initially selected, each radio changes only its original reason, Cancel/back/outside-dismiss does not revoke. Confirm actions wrap/stack properly inside the retained Material dialog, reason content scrolls at largest text, destructive Revoke is readable. Exercise both reasons and the restored-count/zero-restoration statuses using local test data.
- Check Dark contrast for accent, disabled rows, errors, radios, fields, key text, panels and separators, and largest-text clipping/overlap in the header, grouped rows, sheet and dialog. No AO3 access or sign-in is needed.
