# Backup trust: making deletions consistent and files safe

**Date:** 2026-08-15  
**For:** owner review  
**Participants:** Claude Opus 4.6 (Thinking) · Gemini 3.1 Pro (High) · Grok 4.6  
**Workspace:** `/Users/cidy02/kudos-fix-tombstone`  
**Status:** owner locked Phase 1 short inconsistency; Round 3 on Grok's dissent. Not implemented. Not committed.

This replaces the earlier “trust tombstones only on first empty-device restore” decision. That rule was consistent *or* safe, never both. The owner asked for public/private keys, “gpg maybe.”

---

## The problem in one paragraph

A `.kudosbackup` can carry a `savedWork` tombstone for a work the user never deleted. Importing it plants a standing deletion: later legitimate backups skip that work, folder-sync repeats the lie, and nothing expires. The archive is trying to be two things at once — a **snapshot of a library** and a **standing deletion order**. Those cannot both be trusted when the file can come from anyone.

---

## How this discussion was run

Both models received the same brief (live bug, rejected first-restore rule, signature angle, constraints). They wrote independently (Round 1), then each saw the other’s text and revised (Round 2). Consensus below is only what both locked, plus one moderator tie-break where they *crossed* (each conceded the other’s original position on private-key sync).

---

## Round 1 — Gemini 3.1 Pro

Minimize cryptographic complexity. Do not build a generic secure-messaging protocol.

**Crypto.** Raw Ed25519. iOS `CryptoKit` (`Curve25519.Signing`). Android Google Tink. No OpenPGP, no ObjectivePGP, no Bouncy Castle OpenPGP parser. Optional `gpg --verify` is a nightmare to emit correctly; power users can use a one-liner or `openssl`.

**Keys.** Device (or cluster) identity. iCloud Keychain carries the private key so two iPhones are **zero prompts**. Android Keystore does not sync with iCloud; first Android hit is one “Trust this source? Fingerprint …” prompt. Lost all devices → new key → file is unknown.

**What is signed.** Do not sign re-marshaled JSON (Swift `JSONEncoder` vs Kotlin Moshi will diverge). Put SHA-256 hashes of payload files in `manifest.json`, sign the **exact UTF-8 bytes** of that file, store `signature.bin` + `pubkey.pem` in the ZIP.

**Sync vs file.** First writer to an empty sync folder drops `.kudos_identity`. Readers pin it. File ZIP carries the pubkey; trusted if already pinned, else unknown.

**UX.**
- Merge, unsigned/unknown: add/update works, **silently drop tombstones**.
- Merge, trusted: apply tombstones.
- Replace (any file): wipe-and-load, including tombstones, behind a scary count (“delete 412 works, replace with 14”).

**Residuals.** Sync-folder key swap → hard halt. Clock attacks → reject timestamps >24h in the future. “Curated starter pack + Replace” cannot be fully patched; red confirmation is the bound.

**Phasing.** Ship Merge vs Replace **now** (treat every file as unsigned). Ship Ed25519 immediately after so trusted Merge can apply your own tombstones again.

---

## Round 1 — Opus 4.6

Ed25519, not negotiable. Same libraries. Reject GPG as a **UX template** as well as a runtime: model on **SSH `known_hosts`** (invisible when fine, hard stop when the identity changes). Signal safety numbers only for the cross-device screen.

**Sign each tombstone at delete time, not the backup at export.**

```
payload:    workId || deletionTimestampUTC || signerPublicKey
stored:     { workId, deletedAt, signerPublicKey, signature }
```

Why: transport-independent (file, folder delta, future transfer); incremental sync has no monolithic ZIP to sign; multi-signer libraries don’t force one exporter to vouch for another device’s deletions; cost is ~96 bytes per delete.

Non-tombstone records stay unsigned. Worst case of a hostile file is *adding* works, which the user can see and delete.

**Per-device keys.** Private keys never leave Secure Enclave / StrongBox. iCloud syncs the **trust list**, not the private key. New device is not auto-trusted until TOFU or QR. File import **never** prompts to trust a key (that is the social-engineering hole).

**Prompt budget.** Two iPhones + sync folder: **1** (TOFU). iPhone + Android: **2** (TOFU + QR). Stranger file: **0** blocking prompts; info banner “47 works added, 3 tombstones skipped.”

**Replace** is nuke-and-pave: biometric confirm, signatures not the defense.

**Phasing (round 1).** Ship sign+verify first. No grandfathering of unsigned tombstones.

**Disagreements with the prior sketch.** No GPG-shaped UX. Pin on first *read* by a second device, not on first write. Per-device keys, not one shared pair.

---

## Round 2 — they read each other

### Gemini conceded

- **A.** Per-tombstone signing. Partial sync folders make a single manifest signature constantly break. 96 bytes is trivial.
- **B (as originally stated).** Hardware-bound per-device keys; sync the *trust list* via iCloud, not the private key.
- **D.** A file must never add a key to the trust store. Merge of a stranger’s file adds works and drops tombstones. Trust only via sync-folder TOFU or QR.
- **E.** SSH `known_hosts`, not GPG.

**Held:** Phase 1 must be Merge/Replace with no crypto. Leaving the AirDrop hole open while building Keystore/TOFU is the wrong order.

### Opus conceded

- **B (as Gemini originally stated).** For a reading app the threat is remote file injection, not key extraction. iCloud Keychain may carry a **software-backed** private key so two iPhones are zero-prompt. Do **not** use Secure Enclave keys (they cannot sync). Android stays device-local; QR in Phase 2.
- **C.** Ship Merge/Replace first. Condition: Ed25519 in the **next** release, not someday. Between the two releases, sync users temporarily lose tombstone propagation (Merge drops all tombstones). Acceptable only if short.

**Held:**
- **A.** Per-tombstone. A manifest signature only proves “device C exported this ZIP,” not that tombstones inside were created by a trusted deleter. Relay through an untrusted export would otherwise launder hostile tombstones.
- **D.** No “Trust this source?” on file Merge. Attack: 50 desirable works + 200 kill tombstones; user taps Yes to get the works; attacker’s key is now trusted forever.

**Accepted from Gemini:** reject tombstone timestamps >24h in the future. Manifest-with-hashes as optional **integrity** (corruption), never as **authentication**.

---

## Where they crossed (moderator note)

On **private-key sync** they swapped positions in Round 2: Opus moved toward Gemini’s original “sync the private key,” Gemini moved toward Opus’s original “never leave the device.” Both still want **zero prompts for a second iPhone**.

Those are compatible if we do this:

> Each device keeps its own private key. Same iCloud account **publishes public keys** into a merged trust list. Device B auto-trusts A_pub because A_pub appeared under the same Apple ID — without A’s private key ever leaving A.

That is Gemini’s seamlessness and Opus’s hardware story. It is the locked rule below.

On **phasing**, after Round 2 they actually agree: Merge/Replace first, crypto immediately after. Gemini’s remaining “hold” was against Opus’s *Round 1* order, which Opus had already dropped.

---

## Consensus (locked)

### Phase 1 — ship now, no cryptography

1. **File import defaults to Merge.** Add/update works. **Drop every incoming tombstone.** Info banner: “N works added. K deletions ignored (untrusted source).” Not a blocking dialog.
2. **Replace library from this backup** is a separate, explicit action. Show counts. Require confirmation (biometric if the platform has it). Applies the snapshot including tombstones. This is the only way an unsigned file may delete.
3. **Folder sync in Phase 1** keeps today’s tombstone behavior *or* temporarily drops incoming file-shaped tombstones the same way Merge does — implementers pick the smaller diff, but must not leave **AirDrop/file import** applying hostile tombstones. Preferred: file Merge drops; sync folder unchanged until Phase 2 signs them.
4. **Anti-time-travel** already required on ingest: reject `exportedAt` / tombstone clocks more than 24 hours in the future (iOS already clamps; Android must).

Phase 1 closes the stranger-file attack without keys.

### Phase 2 — immediately following release, not “later”

5. **Primitive: Ed25519 only.** Apple: `CryptoKit.Curve25519.Signing`, software-backed so iCloud can sync *public* material. Android: Tink or `java.security` Ed25519 (API 33+). No GPG, no OpenPGP packets, no libsodium.
6. **Sign the tombstone at delete time.** Payload is a fixed concatenation, not JSON: `workId || deletionTimestampUTC || signerPublicKey`. Store `(signerPublicKey, signature)` on the row. Works/progress/tags stay unsigned.
7. **Optional ZIP integrity** (Gemini): `manifest.json` with SHA-256 of member files. Detects corruption. Does **not** authorize tombstones.
8. **Trust store.** A tombstone applies on Merge/sync only if `signerPublicKey` is already trusted.
   - Own key: auto-trusted at generation.
   - Same Apple ID: peer public keys published via iCloud are auto-trusted (zero extra prompts). Private keys never leave the creating device.
   - Sync folder: first pubkey seen is pinned (TOFU, one confirm if not already in the iCloud set). Later key change = **hard stop** (SSH host-key-changed), not a single dismissible tap.
   - Android / cross-platform: QR (or typed fingerprint) once. Mutual authorize.
   - **A file never adds a key.** No “Trust this source?” on import.
9. **Merge + trusted signer:** apply those tombstones silently (your other phone).
10. **Replace** still nuke-and-pave behind confirmation. Signatures are not the defense.
11. **No grandfathering.** Pre-Phase-2 tombstones are unsigned → dropped on Merge. Document in release notes. That *is* the poison cleanup.
12. **Lost every device.** New key. Old unsigned/unknown tombstones ignored. Additive re-import of works. No recovery phrase, no GPG keyserver.
13. **Format.** `signature` / `signerPublicKey` optional. Old clients ignore them. New clients treat missing sig as untrusted.
14. **Prompt budget.** 0 for same-Apple-ID. ≤1 for sync-folder TOFU if the key is not already in iCloud. ≤2 for first Android pairing. 0 blocking prompts on stranger file import.

### Explicitly rejected

- First-import-is-trusted / empty-library special case.
- Shipping GPG or emitting OpenPGP packets.
- Embedding a pubkey in the file and treating a valid signature under *that* key as trust.
- “Trust this source?” on file Merge.
- Signing only the ZIP/manifest as the authorization layer.
- Recovery seed that lives in the archive.

---

## What a normal user feels

| Setup | Prompts |
|---|---|
| One iPhone | 0 |
| Second iPhone, same Apple ID | 0 (peer pubkeys via iCloud) |
| iPhone + Android, first pair | 1–2 (QR / fingerprint) |
| Import a friend’s backup | 0 dialogs; banner that deletions were ignored |
| “Make this phone look like this file” | 1 scary Replace confirm |
| Sync folder key suddenly changes | 1 hard stop |

Deletions you make on phone A still appear on phone B once Phase 2 is live. A stranger’s AirDrop file cannot ban a work from the rest of your life.

---

## What can still go wrong (both models named these)

- **Replace social engineering** (“use Replace on this starter pack”). Confirmation is the bound, not crypto.
- **Stolen unlocked device** can sign real deletes. Same as deleting in the UI.
- **Write access to the sync folder** can DoS (delete files) and, if the user confirms a key change, can plant a new identity. Hard-stop is the mitigation.
- **Replay of your own old signed tombstones** still verifies. Closing that needs a monotonic chain (Phase 3, not required to ship).
- **Gap between Phase 1 and Phase 2:** your own deletions may not propagate over *file* Merge. Keep that window short.

---

## Grok 4.6 — what I agree with, what I do not

I ran the two-model discussion. I am not a rubber stamp on the locked set. Below is my own position against the current code and the ledger, not a recap.

### I agree

**File Merge must not plant tombstones.** That is the actual bug. Opus and Gemini both landed here. Do this first. Do not wait for keys.

**A file must never add a trusted key.** Gemini’s original “Trust this source?” on Merge is the whole system failing in one tap. Opus is right. I would not ship that prompt even as an advanced setting.

**Ed25519, no GPG.** The GPG *idea* (keypair, fingerprint, pin) is right. GPG-the-program and OpenPGP packets are the wrong dependency in a SwiftUI/Kotlin reader. CryptoKit + Tink (or API 33 `Ed25519`) is the correct primitive. I said this before the discussion and both models independently said it too.

**Sign the tombstone, not the ZIP, as authorization.** Gemini’s concede on this is correct. A manifest signature only proves who exported the bundle. After two devices have deleted different works, the exporter is a *relay*. Relayed deletions need the original deleter’s signature or they are just claims. Fixed-byte concatenation (`workId || timestamp || pubkey`) avoids the JSON encoder war Gemini correctly feared.

**SSH `known_hosts` for the sync folder, not a dismissible warning.** Key change = halt. One “Continue anyway” button is how people get owned.

**No recovery seed in the archive.** That is the private key with extra steps.

**Replace is a different verb.** Merge and Replace must not share a code path that “kind of” applies tombstones.

### I disagree

**1. Replace must not persist standing tombstones from an unsigned file.**

Both models treat Replace as “nuke and pave, apply tombstones exactly.” That reintroduces the original bug behind a confirm button.

Replace should mean: **this snapshot’s work list is now the library.** Works not in the file are gone *because they are not in the library*, not because we inserted poison rows that will suppress every *future* backup. If Replace writes those tombstones into `SyncTombstone` and a later Merge of the user’s real backup runs `suppressesResurrection`, the hostile file still wins after the user has moved on.

Correct unsigned Replace: load the works in the file; do **not** insert unsigned tombstones as future filters. Absence in this snapshot is enough for *this* load. Phase 2 signed tombstones from a trusted key may persist, because they are *your* deletions.

This is the single most important disagreement I have with the locked set.

**2. “Folder sync unchanged in Phase 1” is a hole, not a preference.**

The consensus lets implementers leave live folder sync applying unsigned tombstones. The ledger already treats the sync folder as attacker-controlled (AirDrop a zip into it, or a shared Drive folder). If Phase 1 only fixes the in-app “Import file” button, the same hostile archive dropped as `manifest.json` + tombstones in the folder still plants standing deletions.

Phase 1 rule should be by **ingest path of untrusted bytes**, not by UI label:

- Package / zip / “open this file” → drop incoming tombstones.
- Folder sync of an **unsigned** tombstone that this device did not itself create → drop it too, *or* Phase 1 is incomplete and we should say that in the release notes instead of pretending the AirDrop hole is closed.

I would rather ship a short, honest regression (“deletions do not cross devices until the next version”) than a green “we fixed AirDrop” that is false for anyone using Library Sync.

**3. Do not drop every pre-Phase-2 tombstone on next sync read without a local re-sign.**

“No grandfathering” as written is an availability bug for legitimate users. The day Phase 2 ships, every deletion you made last year is unsigned, gets dropped, and an older backup resurrects those works. That is the font-cap / suffix-loop class of fix: it denial-of-services honest users with no attacker.

Migration on first Phase 2 launch: **sign locally stored tombstones with this device’s new key** (they are already on *this* device; we are attesting “I already believed these”). Incoming unsigned tombstones from files/peers still drop. That is grandfathering *local state*, not grandfathering the network.

**4. The signed payload as specified is the wrong identity.**

Opus signs `workId`. Production matching is `ao3WorkID` → canonical `sourceURL` → `recordID` (`TombstoneIndex` / `suppressesResurrection`). A signature over only a UUID does not bind the fields an attacker actually uses to suppress a *different* work (plant `ao3WorkID` of a popular fic on a random UUID row). Sign the same triple the sink uses, plus `recordType`, plus `deletedAt`, plus `signerPublicKey`. Canonicalize `sourceURL` with the same function iOS already has (`WorkTags.canonicalAO3WorkURL`) before signing; Android must use that rule too or the signature verifies and the index still misses.

**5. Same-Apple-ID auto-trust is fine; do not confuse it with syncing the private key.**

Opus R2 and Gemini R2 crossed. I lock the *moderator* version: private key never leaves the creating device; iCloud publishes **public** keys; peers under the same Apple ID auto-trust those pubs.

I would **not** put the private key in iCloud Keychain. Apple ID compromise plus a new phone running Kudos can already join the ring by publishing a new pubkey — that residual is real and should be named. Syncing the private key makes every iCloud backup of Keychain a signing oracle without even installing Kudos on a new device. Worse, no gain: auto-trust of peer pubs already gives 0 prompts.

Android has no equivalent. QR once. Do not invent a shared secret to paper over that.

**6. The 24-hour clock clamp is necessary and insufficient.**

Agree to keep it (iOS already has it). It does not make timestamp-vs-tombstone a safe resurrection rule. A tombstone dated “now” still beats a work whose `lastModifiedAt` is the AO3 updated date from 2019. Phase 2 authorization is the signature, not the clock. Do not let Phase 2 reintroduce “newer lastModifiedAt wins” as the load-bearing check.

**7. Phase 1 “keep folder sync as today” plus Phase 2 “immediately after” needs a harder gate than a promise.**

I agree with the *order*. I do not agree that Phase 1 is done if sync still honors unsigned incoming tombstones. Write the Phase 1 test against **both** `importPackage` and the folder-sync ingest of a hostile tombstone. If the second test is deferred, the commit message must say “file import only; sync still vulnerable.”

### What I would lock instead (delta only)

| Consensus item | Grok |
|---|---|
| Replace applies unsigned tombstones as stored rows | **No.** Replace loads works. Unsigned tombstones do not become future suppressors. |
| Phase 1 folder sync left as implementer choice | **No.** Either drop unsigned *incoming* tombstones on sync too, or label Phase 1 “file import only.” |
| No grandfathering | **Local re-sign on upgrade.** Incoming unsigned still drops. |
| Sign `workId` | Sign **type + ao3WorkID + canonical sourceURL + recordID + deletedAt + signer pubkey**. |
| iCloud may sync the private key | **No.** Publish pubs only. |
| 24h clamp as anti-time-travel | Keep as defense in depth, not as the authorization rule. |

Everything else in the consensus — Merge drops, no file-TOFU, Ed25519, per-tombstone auth, SSH halt, no GPG, no seed in the archive, Replace as a separate verb — I am with.

### Where I would still ask you (owner)

Only one product call left that is not engineering:

- **Phase 1 sync:** accept a brief window where *your own* deletions do not cross devices (safer, slightly inconsistent), or leave sync applying unsigned tombstones until Phase 2 (consistent, still attackable via the folder). I vote for the short inconsistency.

I do not need another vote on GPG, first-restore, or “Trust this source?” on a file. Those are settled, including by me.

---

## Round 3 — Opus and Gemini on Grok’s dissent

Owner locked G2 (short inconsistency) before this round. Both models were told not to reopen it.

### Scorecard

| Point | Opus | Gemini | Result |
|---|---|---|---|
| G1 Replace must not persist *the file’s* unsigned tombstones | **Concede** | **Amend** | Agree on the core. Gemini wants the device to mint *new* signed tombstones for works dropped by Replace so the wipe propagates. See below. |
| G2 Phase 1 drops unsigned tombstones on file **and** sync | (locked) | (locked) | **Owner locked** |
| G3 Local re-sign on Phase 2 first launch | **Amend** (one-time, flagged; later unsigned arrivals still drop) | **Concede** | **Locked** with Opus’s one-time flag |
| G4 Sign the sink identity tuple, not `workId` | **Amend** (lock serialization now) | **Concede** | **Locked** with Opus’s byte layout |
| G5 Private key never leaves the device; iCloud pubs only | **Concede** | **Concede** | **Locked** |
| G6 Clamp is not authorization | **Concede** | **Concede** | **Locked** |

### The only remaining split: Gemini’s G1 amendment

Gemini agrees not to import the file’s unsigned tombstones, then adds: for every local work *absent from the Replace snapshot*, the executing device should create a **new** tombstone signed with **its own** Phase 2 key, so the wipe crosses the fleet.

Opus: Replace deletes by work-set diff. No suppressor rows. Later Merge of a real backup can bring works back.

**Grok holds with Opus.** Gemini’s amendment turns one confirmed Replace of a hostile empty/tiny file into a *signed* fleet wipe. That is worse than the original bug: the tombstones would verify. Local Replace empties *this* device; it must not authorize standing deletions for every peer. If we ever want “make my other phones look like this snapshot,” that is a separate, even louder verb in Phase 2 — not a side effect of Replace.

### Round 3 locked set (Grok + both models, except Gemini’s fleet-wipe add-on)

1. **Phase 1 (owner):** drop unsigned incoming tombstones on file Merge **and** folder sync. Deletions do not cross devices until Phase 2.
2. **Replace:** load the snapshot’s works. Do **not** persist the file’s unsigned tombstones. Do **not** mint new standing tombstones from an unsigned Replace. Absence in this snapshot is enough for this device. Phase 2: signed tombstones from an already-trusted key may persist.
3. **Phase 2 first launch:** one-time local re-sign of tombstones already in *this* store (`tombstoneMigrationComplete`). Unsigned arrivals after that still drop.
4. **Signature payload:** Ed25519 over UTF-8 fields joined by `\n`, in this order: `recordType`, `ao3WorkID`, `canonicalSourceURL`, `recordID`, `deletedAt` (ISO 8601 UTC, no fractional seconds), `signerPublicKey`. `canonicalSourceURL` is one shared spec on both platforms (must match `WorkTags.canonicalAO3WorkURL` / Android port).
5. **Keys:** per-device Ed25519. Private key stays on the creating device. iCloud publishes public keys; same Apple ID auto-trusts those pubs (0 prompts). Android: QR once.
6. **24h clamp:** keep as a pre-filter. Phase 2 authorization is the signature.

---

## Implementer note

Phase 1 is a small change to `KudosBackup.swift` / `BackupMergeService.kt` import of file packages: do not insert or honor incoming `savedWork` tombstones on Merge. Replace is a separate entry point. Do not start Ed25519 until Phase 1 is gated (production-entry test, Mutation A/B, GREEN last) on both platforms.

Phase 2 is a real feature (key lifecycle, both stores, TOFU, QR). Write it against this consensus, not against first-restore.

---

## Merge vs Replace as explicit import options (owner proposal)

**Owner asked:** add Merge (add works not already present; delete nothing) and Replace (library becomes the snapshot), with an extra step on Replace (checkbox or similar). Discussed by Gemini 3.1 Pro, Opus 4.6, and Grok 4.6.

Today’s iOS Settings import is a single path: confirm, then `KudosBackupService.restore` always merges (including tombstones). Copy already says “Merged into your library.” Folder sync is a separate always-merge path.

### Where all three of us agree

- **Two verbs is enough.** Preview is a *step*, not a third button. “Add only EPUBs” is a niche filter.
- **Call the dangerous one “Replace Library,”** not just Replace.
- **Merge is the default** (primary button). Replace is secondary / destructive styling.
- **Empty library:** skip the fork. Merge and Replace are the same; one “Restore from Backup” button.
- **Folder sync stays implicit Merge forever.** No Replace-via-sync. A stale file in the folder must not nuke a live library.
- **This UX ships in Phase 1.** It does not need keys. Unsigned tombstones stay dropped.
- **Show the math before either action:** works in library, works in file, will add, will remove (Replace only).
- **Replace must not persist the file’s unsigned tombstones** and must not mint fleet-wide signed tombstones (already locked).
- **Keep device prefs / login / (Phase 2) keys** across Replace. Do not wipe AO3 session or themes as a side effect of replacing the *library*.
- **Replace + Library Sync is a trap.** Next sync will put wiped works back unless we pause or warn.

### Where they split

| Topic | Opus | Gemini | Grok |
|---|---|---|---|
| Merge on overlap | Never touch an existing work. Local wins everything. | Union tags/collections; furthest progress | **Phase 1: Opus.** One sentence users can read. Furthest-progress is a later opt-in, not the default. New *collections that only hold newly added works* can still be created. |
| Replace extra step | Two screens + **2s delay** on the red button. Biometric is the wrong signal (identity ≠ intent). Checkbox is too easy. | FaceID / hold-to-confirm. Counts. No type-REPLACE. | **Checkbox that *enables* the red button**, plus counts, plus a short delay. See below. |
| Undo | Silent auto-backup of the current library before Replace | Not specified | **With Opus.** This project has already hurt users with security fixes. |
| Sync after Replace | Prompt to **pause** sync | Prompt to **clear the sync folder** as well | **Pause, do not clear.** Clearing the replica is a second nuke. |

### Grok — I would ship this

Your proposal is the right product. It is also the Phase 1 security control: Merge cannot delete; Replace can, but only locally, and only after an extra step.

**Merge:** union of works by identity. Add anything not already here. Do not delete. Do not overwrite an existing work’s progress, tags, or notes. Create a collection/queue from the file only if it introduces new works (so those works are not orphaned). Drop unsigned tombstones.

**Replace Library:** this device’s works / progress / collections / annotations / queues become the snapshot. Fonts, appearance, AO3 login, trusted keys stay. File’s unsigned tombstones are not stored. Works missing from the file leave *this* library because they are not in the snapshot, not because we planted suppressors. Other devices are untouched.

**Replace extra step (what you asked for):** not a lone checkbox, and not “type REPLACE.”

1. Sheet shows the delta (add / remove / in both).
2. If removals ≫ additions, amber line: “This backup is much smaller than your library.”
3. Disabled red **Replace Library** until the user checks: “Remove N works that are not in this backup.”
4. Button enables after the check **and** ~1–2 seconds (iOS Erase All pattern).
5. If Library Sync is on: “Sync will put removed works back. Pause sync for this device?” Default **Pause**. Do not offer “wipe the sync folder” in Phase 1.
6. Before execute: write a timestamped `.kudosbackup` of the current library (Documents or the sync folder). Confirmation copy names that file.

**Surfaces:** file import from Settings and from opening a `.kudosbackup`. Not on the folder-sync settings page.

**First run / zero works:** one Restore button, no Merge/Replace choice.

### Recommendation I would lock (if you say yes)

1. Two verbs: Merge (default) and Replace Library.
2. Merge = add missing works only; local overlap unchanged; no deletes.
3. Replace Library = this device’s library becomes the snapshot; prefs/login/keys/fonts stay.
4. Replace extra step = checkbox enabling a delayed red button + removal counts. Not biometric-only, not type-to-confirm.
5. Auto-save current library before Replace.
6. If sync is on, default to pausing it; never clear the sync folder from this flow.
7. Empty library: single Restore.
8. Folder sync remains Merge-only.
9. Ship in Phase 1 with tombstones dropped.
10. Result alert states counts in past tense.

---

## Appendix — Merge vs Replace full transcripts

See the end of this file.

---

## Appendix — full model text

Round 1 Gemini, Round 1 Opus, Round 2 Gemini, and Round 2 Opus are archived next to this file’s sources:

- Gemini R1: `~/.antigravity-jobs/20260815-112045-78062-8685/out`
- Opus R1: `/tmp/opus-r1-out.md`
- Gemini R2: `~/.antigravity-jobs/20260815-114434-79720-18488/out`
- Opus R2: `/tmp/opus-r2-out.md`

The body above is the discussion plus the locked set. The owner reviews this file, not the job logs.

---

## Full transcript: Gemini 3.1 Pro — Round 1

### Gemini 3.1 Pro

I am taking the position that we must aggressively minimize cryptographic complexity. The goal is data safety, not building a generic secure messaging protocol. If we pull in an OpenPGP parser, we are inviting memory exhaustion, canonicalization bugs, and library bloat. We split the problem: UI semantics govern intent, and cryptography governs identity.

Here is my argument for how we build this.

#### 1. Crypto Primitive: Raw Ed25519 (No GPG, No OpenPGP)
I strongly disagree with the sketch’s suggestion of an "optional detached sig for `gpg --verify`." Generating valid RFC 4880 OpenPGP signature packets natively in Swift and Kotlin is an absolute nightmare without pulling in massive, brittle dependencies like ObjectivePGP or the depths of Bouncy Castle. 
Instead, we use raw Ed25519. 
- **iOS:** Native `CryptoKit` (`Curve25519.Signing`). It is built-in, fast, and safe.
- **Android:** Google's `Tink` library. It provides safe Ed25519 primitives without the sharp edges of `java.security`.
We output a raw 64-byte signature. If a power user wants to verify it externally, they can use a one-line Python script or `openssl`, not `gpg`. The keys are stored in the iOS Secure Enclave / Android Keystore.

#### 2. Trust Bootstrap & Seamlessness
Keys identify *devices* (or a cluster of devices), not humans. 
- **Two iPhones:** Seamless (0 prompts). We store the Ed25519 private key in iCloud Keychain. When a user installs Kudos on their iPad, it silently inherits the identity. They sync, it matches, zero friction.
- **First-time Android / Cross-platform:** Android Keystore doesn't sync with iCloud. When an Android device connects to a sync folder populated by iOS (or imports an iOS file), the pubkey won't match its local keystore. It prompts *once*: "Trust this source? Fingerprint: `a1b2-c3d4...`". 
- **Lost all devices:** The user has a `.kudosbackup` file but no keychain. Their new phone generates a new key. The file is treated as **Unknown Key**. 

#### 3. What is Signed and Canonicalization
Do not attempt to sign JSON by unmarshaling and re-marshaling it. Key ordering differences between Swift's `JSONEncoder` and Kotlin's `Moshi/Kotlinx` will break signatures constantly.
Instead, we sign the raw bytes. 
The `.kudosbackup` is a ZIP. Inside the ZIP, we place a `manifest.json` that contains the SHA-256 hashes of all other files in the archive (like `tombstones.json` and `works.sqlite`), plus an `exportedAt` timestamp. 
We sign the exact UTF-8 bytes of `manifest.json` as they are written to disk. We store the 64-byte signature in `signature.bin` and the public key in `pubkey.pem`. To verify: hash the files, assert they match the manifest, then verify the manifest's bytes against the signature. 

#### 4. Folder Sync vs One-Shot File
- **Folder Sync:** The sync folder is a continuous state. The first device to write to an empty folder places a `.kudos_identity` file containing its public key. Other devices reading this folder pin this key on first read (prompting the user if the key isn't in their keychain).
- **One-Shot File:** The ZIP contains the pubkey. We verify the signature inside the ZIP. If the pubkey is in our trusted list, it's a Trusted File. If not, it's an Unknown File.

#### 5. Unsigned and Unknown-Key UX (Merge vs Replace)
This is where we actually defeat the AirDrop attack. Cryptography only tells us *who* wrote it; the UI dictates what they are *allowed* to do.
- **Merge (Unknown/Unsigned File):** Adds new works, updates existing metadata. **Silently drops all tombstones.** A malicious file cannot delete your library.
- **Merge (Trusted File):** Adds works AND applies tombstones silently.
- **Replace Library (Any File):** Wipes the current device database and loads the backup exactly. This includes tombstones. Because it's an explicit snapshot overwrite, we show a scary prompt: *"This will delete your current library of 412 works and replace it with the 14 works in this backup."* Since the user explicitly consents to the snapshot, applying tombstones here is safe, even if the file is unsigned.

#### 6. What Can Still Go Wrong
- **Sync Folder Key Swap:** An attacker with write access to the sync folder replaces `.kudos_identity` with their own key and signs a malicious sync state. 
  *Mitigation:* When a device sees a pinned key change, sync halts hard. UI: "The identity of this sync folder has changed. Did you set up a new device?" The user has to click "Yes" to get owned.
- **Clock Attacks:** An attacker with a stolen trusted device signs a tombstone with a `lastModifiedAt` of the year 2099. That work is permanently un-downloadable. 
  *Mitigation:* The importer must reject any timestamps in the manifest or tombstones that are more than 24 hours in the future relative to the device clock.
- **Social Engineering "Replace":** Someone posts a "curated starter pack" and tells users to use "Replace". 
  *Mitigation:* The UI explicitly warns them that their current library will be deleted. We can't patch human gullibility further than a red confirmation button.

#### 7. Phasing
We do not need to ship the cryptography to solve the immediate bug. We can ship the UX semantic split first.
**Phase 1:** Ship "Merge vs Replace". Treat all files as unsigned. "Merge" ignores tombstones. "Replace" honors them. This immediately closes the AirDrop vulnerability without painting us into a corner.
**Phase 2:** Ship Ed25519 identity. Now "Merge" can safely process tombstones from your own devices.

***

### DECISION SET

1. **Crypto Primitive:** Use raw Ed25519 signatures (iOS `CryptoKit`, Android `Tink`). Do not support OpenPGP/GPG formats.
2. **Key Storage:** Store the private key in iCloud Keychain (iOS) and Android Keystore (Android).
3. **Payload Construction:** The `.kudosbackup` ZIP contains a `manifest.json` with SHA-256 hashes of all data files and an `exportedAt` timestamp.
4. **Signature Target:** Sign the exact byte representation of `manifest.json`. Include `signature.bin` and `pubkey.pem` in the ZIP.
5. **Anti-Time-Travel:** Reject imports where the manifest's `exportedAt` or any tombstone timestamp is >24 hours in the future.
6. **Sync Pinning:** The first write to a sync folder drops `.kudos_identity`. Subsequent readers pin this key. If the key changes, halt sync and prompt the user.
7. **Merge UX (Untrusted/Unsigned):** Add/update works, but **ignore all tombstones**. 
8. **Merge UX (Trusted):** Add/update works, and apply tombstones.
9. **Replace UX (Any):** Show a destructive warning ("This will delete your current library"). Apply works and tombstones exactly as they exist in the file.
10. **Cross-Platform Bootstrap:** Show a one-time "Trust this source?" prompt displaying a short key fingerprint when an unknown key is encountered on an explicit Merge or Sync setup.
11. **Execution Phasing:** Ship the Merge vs Replace semantics immediately to fix the live vulnerability. Ship Ed25519 in a fast-follow release.

---

## Full transcript: Opus 4.6 — Round 1

# Kudos Tombstone Signing: Full Design Argument

## Crypto Primitive

**Ed25519. Not negotiable, but the "how" matters.**

Ed25519 gives you 32-byte keys, 64-byte signatures, constant-time operations, and no parameter choices to get wrong. It's available natively: `CryptoKit.Curve25519.Signing` on Apple platforms (backed by Secure Enclave where available), `java.security.KeyPairGenerator("Ed25519")` on Android (API 33+, Tink library below that). Same wire format, cross-platform verification without dependency alignment.

Reject ECDSA (malleable without normalization), RSA (key size, speed), HMAC (symmetric = shared secret = can't distinguish devices). Reject X25519 — that's Diffie-Hellman key agreement, not signing. Reject NaCl `crypto_sign` wrappers like libsodium: they're Ed25519 underneath, but adding a C dependency to a SwiftUI/Kotlin app for something the platform already provides is unjustifiable.

**Do not ship GPG, do not model UX on GPG.** GPG's UX is a cautionary tale, not a template. The prior sketch says "GPG-shaped UX" — I'd push back. Model on **SSH `known_hosts`**: invisible when it works, one hard stop when something changes, no key servers, no expiry dialogs, no web of trust. Signal's safety numbers are a secondary reference for the cross-device verification screen.

## What Gets Signed (and When)

**Sign each tombstone at creation time, not the backup file at export time.**

When the user deletes a work, the tombstone record is created and immediately signed with the device's private key. The tombstone becomes a self-authenticating record:

```
Signed payload:  workId || deletionTimestampUTC || signerPublicKey
Stored fields:   { workId, deletedAt, signerPublicKey, signature }
```

Why per-tombstone, not per-file:

1. **Transport-independent.** The same signed tombstone is valid whether it arrives in a `.kudosbackup`, a sync-folder delta, or a future Kudos-to-Kudos transfer. You never need to re-sign on export.
2. **Incremental sync.** Sync folders don't always contain monolithic backups. If you write per-work or per-change files, per-tombstone signatures Just Work. A file-level signature breaks when the folder contains partial state.
3. **No mixing ambiguity.** A backup file could contain tombstones from multiple signers (if you've restored from two devices). Per-file signing forces you to pick *one* signer or nest signatures. Per-tombstone avoids this entirely.
4. **Cost is negligible.** Users delete works rarely. 64 bytes of signature + 32 bytes of pubkey per tombstone is noise against EPUB storage.

Non-tombstone records (work metadata, reading progress, bookmarks, tags) are **not signed.** They're additive and non-destructive — the worst a hostile file can do with them is add unwanted works, which the user can see and delete.

## Trust Bootstrap

This is the real design problem. The crypto is easy; the trust model is where you can brick the UX or leave a gap.

### Per-device keys, not shared keys

**Each device generates its own Ed25519 keypair.** Private keys never leave the platform keychain/keystore. This is non-negotiable because:

- Secure Enclave / StrongBox can protect key material at the hardware level — but only if the key was born there.
- Transmitting a private key (even via QR) means it exists in memory on two devices during transfer. That's a downgrade from "never extracted."
- Per-device keys give you meaningful revocation: "this device was compromised, revoke its pubkey" without rotating every device.

### The trust store

Each Kudos installation maintains a **local trust store**: a list of `(publicKey, fingerprint, label, authorizedAt, authorizedBy)` tuples. A tombstone is applied only if `signerPublicKey` is present in the local trust store.

### Scenario walkthrough

| Scenario | What happens |
|---|---|
| **First device ever** | Keypair generated. Own pubkey auto-trusted. Trust store = `[self]`. |
| **Second iPhone (same Apple ID)** | New keypair generated. **Not** auto-trusted. User must cross-authorize (below). iCloud Keychain syncs *trust store entries*, not private keys. |
| **First Android (user has iPhone)** | New keypair generated. Cross-authorize via QR. |
| **Sync-folder TOFU** | First write to a sync folder embeds the writer's pubkey in a `sync_identity.json`. Second device reads, sees an unknown pubkey, prompts once: "Trust this sync identity? Fingerprint: `b7a3 92f1 …`". User confirms → pubkey added to local trust store. |
| **Lost device** | User opens Settings → Trusted Devices → revokes the lost device's pubkey. A signed revocation record propagates via the sync folder. Tombstones from the revoked key are **kept** (they were legitimate when created) but no *new* tombstones from that key are accepted. |
| **Total loss (all devices gone)** | Fresh start. New keypair. Old sync folder's tombstones are from an untrusted key → they're ignored (treated as unsigned). User effectively gets a clean merge from the sync folder. This is *correct behavior*: you've lost your identity, so you shouldn't inherit someone else's deletions. |
| **Stranger's `.kudosbackup` imported** | Signer pubkey not in trust store → tombstones silently ignored. Works/progress merged. No prompt about trust — the absence of trust is the default. |

### Cross-authorization protocol

Adding a new device to your trust ring:

1. New device generates keypair, displays its pubkey fingerprint as a QR code + human-readable hex.
2. Existing trusted device scans QR → shows fingerprint for visual confirmation → user taps "Authorize."
3. Existing device signs `("authorize" || newPubkey || timestamp)` and writes this authorization record to the sync folder (and its local trust store).
4. New device picks up the authorization and adds the existing device's pubkey to *its* trust store (mutual trust from the authorization record's signer).

This is **one QR scan, one tap**. No passphrase. No seed phrase. No account creation.

## Sync Folder vs. File Import

These are fundamentally different trust contexts and must have different defaults:

### Sync folder (continuous, bidirectional)

- **TOFU on first contact.** Pin the first pubkey seen in `sync_identity.json`. This is safe because the sync folder itself is access-controlled (iCloud Drive, Google Drive, Dropbox — all require account auth).
- **Verify on every read.** Every tombstone from the sync folder must verify against a trusted pubkey. Unsigned or untrusted tombstones are dropped silently.
- **Pubkey change = hard stop.** If `sync_identity.json` contains a pubkey not in the trust store (and TOFU has already occurred), **halt sync and prompt.** This is the SSH `@@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED @@@@` moment. It means either the user rotated keys (legitimate) or someone else wrote to the folder (attack).

### File import (one-shot, unidirectional)

- **No TOFU.** The file's signer pubkey is checked against the existing trust store. If not trusted, tombstones are dropped.
- **Never prompt to trust a file's pubkey.** This is the critical defense against the social engineering vector ("hey, import my backup!"). A file cannot bootstrap trust.
- **The only way to get a file's tombstones applied** is to first add the file's signer to your trust store via the cross-authorization protocol (QR scan from a device you control).

### Import modes

| Mode | Source | Tombstones applied? | Prompt? |
|---|---|---|---|
| **Merge** (default for file import) | `.kudosbackup` file | Only if signer is trusted | "N works added. K tombstones skipped (unsigned)." — info banner, not a blocking dialog |
| **Sync read** | Sync folder | Only if signer is trusted | None (happy path) or hard stop (pubkey mismatch) |
| **Replace** (destructive) | Any | Yes, regardless of trust | "This will replace your entire library with this backup. You will lose [N] works not in this file. Are you sure?" — blocking dialog, biometric confirm |

**Replace** bypasses tombstone signing because it's semantically a "nuke and pave." The user is explicitly choosing to overwrite *everything.* The threat model for Replace is different: you're trusting the file's *entirety*, not its individual claims. The confirmation dialog is the defense, not the signature.

## Unsigned UX and Prompt Counts

Prompt count is a proxy for UX quality. Every dialog is a point where the user can be confused, make the wrong choice, or learn to reflexively tap "OK." Minimize.

### Happy path: two iPhones with iCloud sync folder

| Event | Prompts |
|---|---|
| First launch (device A) | 0 — keypair generated silently |
| Enable sync folder (device A) | 0 — pubkey written to sync folder automatically |
| First launch (device B) | 0 — keypair generated silently |
| Enable sync folder (device B) | **1** — TOFU: "Trust this sync identity?" (shows fingerprint) |
| Ongoing sync (both directions) | 0 — everything verified in background |
| Delete a work on device A | 0 — tombstone signed and synced automatically |
| Work disappears on device B | 0 — tombstone verified and applied |

**Total: 1 prompt** for the entire lifetime of a two-device setup (same platform).

### Cross-platform: iPhone + Android

Same as above, plus **1 prompt** for the QR cross-authorization.

**Total: 2 prompts.**

### Importing a stranger's file

| Event | Prompts |
|---|---|
| User taps "Import" on a `.kudosbackup` | 0 — merge starts |
| Merge completes | 0 — info banner: "47 works added. 3 tombstones skipped (unsigned)." |

**Total: 0 blocking prompts.** The banner is dismissible and informational. The user never needs to understand cryptography.

### Edge cases that prompt

- **Pubkey mismatch on sync folder:** 1 hard-stop dialog. "The sync folder's identity has changed. This could mean you rotated keys on another device, or someone else is writing to your folder." Two buttons: "I rotated keys" (re-TOFU) / "Something is wrong" (disable sync, show details).
- **Replace import:** 1 blocking dialog with biometric.

## Residuals (What This Doesn't Solve)

Be honest about the remaining attack surface:

1. **Replay of legitimately signed tombstones.** If an attacker obtains a copy of your sync folder from last month and replays it, all those tombstones verify. This is **by design** — they're your own deletions. Protecting against rollback would require a monotonic counter or Merkle chain, which is Phase 3+ complexity.

2. **Compromise of the sync folder itself.** If an attacker gets write access to your iCloud Drive, they can't inject signed tombstones (no private key), but they *can* delete your backup files (DoS). Signing doesn't help with deletion-at-the-transport-layer. Mitigation: versioned backups (keep last N).

3. **Compromised device.** If malware on your phone has Keychain access, it can sign tombstones. But at that point, it can also just delete the SwiftData store directly. Signing protects against *remote* injection via files, not local compromise.

4. **Replace-mode social engineering.** "Import this file using Replace!" bypasses signing. The biometric confirmation is the only defense. Consider: should Replace require *two-step* confirmation (dialog → wait 5 seconds → confirm again)?

5. **Pre-signing-era tombstones.** Existing tombstones in the wild have no signatures. After the migration, these must be treated as unsigned (no grandfathering). Users who already have a poisoned sync folder will see poisoned tombstones get dropped — which is the desired behavior, but might surprise users who had legitimate unsigned tombstones.

## Phasing

### Phase 1: Sign + Verify (ship first)

- Ed25519 keypair generation on first launch
- Tombstones signed at creation time
- Sync folder TOFU
- Unsigned tombstones silently dropped on merge-import and sync-read
- Info banner for skipped tombstones
- Settings screen: shows own fingerprint, list of trusted keys
- **No cross-device authorization yet** — Phase 1 only supports same-iCloud-account devices via Keychain trust store sync

### Phase 2: Cross-Device + Cross-Platform

- QR-based cross-authorization protocol
- Android key generation (Tink or API 33+ native)
- Key revocation (from Settings → Trusted Devices)
- Revocation propagation via sync folder

### Phase 3: Hardening

- Signed revocation records
- Audit log (which tombstones were applied/rejected, when, from whom)
- Optional: tombstone chain (each tombstone references the hash of the previous, making replay detectable)
- Replace-mode two-step confirmation

---

## Decision Set

> **D1. Primitive: Ed25519, platform-native only.** `CryptoKit.Curve25519.Signing` on Apple, `java.security` Ed25519 (API 33+) / Tink (below 33) on Android. No libsodium, no BoringSSL, no GPG.

> **D2. Per-device keypairs; private keys never leave the keychain/keystore.** No shared secrets, no key export, no passphrase-derived keys. Secure Enclave / StrongBox where available.

> **D3. Sign tombstones at creation time, not backups at export time.** Each tombstone carries `(signerPublicKey, signature)` over `(workId, deletionTimestamp, signerPublicKey)`. Non-tombstone records are unsigned.

> **D4. Trust model: local trust store, not file-based trust.** A file cannot introduce a trusted pubkey. Trust is established only via: (a) self-trust at keygen, (b) TOFU on first sync-folder read, or (c) QR cross-authorization from an already-trusted device.

> **D5. Unsigned/untrusted tombstones are silently dropped on merge and sync-read.** No prompt, no dialog, no "do you want to trust this?" for file imports. An info banner ("N tombstones skipped") is shown post-merge, dismissible, non-blocking.

> **D6. Sync-folder TOFU with hard stop on pubkey change.** First pubkey seen in `sync_identity.json` is pinned automatically with one confirmation prompt. Subsequent pubkey mismatch halts sync and requires explicit user resolution (SSH `known_hosts` model).

> **D7. Replace mode bypasses tombstone signing but requires biometric-gated destructive confirmation.** Replace is "nuke and pave" — the user is trusting the file wholesale. The signature system is not the defense here; the confirmation dialog is.

> **D8. Prompt budget: ≤1 for same-platform sync setup, ≤2 for cross-platform, 0 for file import.** Any design that adds prompts beyond this budget is wrong and must be reworked.

> **D9. Pre-signing-era tombstones are treated as unsigned after migration.** No grandfathering. Existing unsigned tombstones in sync folders will be dropped on next read. This is the desired behavior (it's the fix for the poisoning bug) but must be documented in release notes.

> **D10. Phase 1 ships sign+verify, TOFU, and the info banner.** Cross-device QR authorization is Phase 2. Key revocation is Phase 2. Audit log and tombstone chaining are Phase 3. Phase 1 alone fully closes the hostile-`.kudosbackup` attack vector.

> **D11. Backup format is backward-compatible.** `signature` and `signerPublicKey` are optional fields on tombstone records. Old clients ignore them (and thus ignore the tombstones on compliant new clients — safe). New clients reading old backups see unsigned tombstones → drop them.

> **D12. No key-rotation-via-passphrase, no recovery phrase, no account.** If all trusted devices are lost, the user starts fresh. Old sync-folder tombstones are ignored (untrusted key). This is correct: cryptographic identity was lost, so deletions from that identity should not propagate to a new identity. The user re-imports works from the sync folder additively.

---

### Where I Disagree With the Prior Sketch

**"GPG-shaped UX"** — No. SSH-shaped. GPG's UX teaches users to click through warnings. SSH's UX is invisible until something is actually wrong, and then it's a hard stop that can't be dismissed with a single tap.

**"Pin pubkey on first sync-folder write"** — Mostly right, but it must be "pin on first sync-folder *read by a second device*," and it must be a device that has already been set up (has its own keypair). The writing device doesn't need to pin — it trusts itself. The reading device pins. This distinction matters for the prompt flow.

**Per-device vs. shared keypair** — The prior sketch implies a single shared keypair. I argue per-device is strictly better: no private key transmission, meaningful revocation per device, Secure Enclave compatibility. The cost is the cross-authorization protocol in Phase 2, which is one QR scan.

### Opus 4.6

---

## Full transcript: Gemini 3.1 Pro — Round 2

### Gemini 3.1 Pro — Round 2

Opus, your analysis of the trust model and per-tombstone signing is excellent. You’ve successfully convinced me on the cryptography and trust architecture. However, I am holding the line on execution phasing. A live vulnerability requires an immediate, foolproof mitigation, not a multi-week cryptography project.

Here is where we stand on the disagreements.

#### A. Sign per-tombstone (Opus) vs. Sign the manifest (Gemini)
**CONCEDE to Opus.** 
Your point about the sync folder containing partial state completely invalidates my file-level manifest idea. If the sync folder isn't monolithic, a single manifest signature will constantly break as files sync at different speeds. Per-tombstone signing is transport-agnostic, survives partial syncs, and eliminates the need to canonicalize an entire ZIP file. The storage cost (96 bytes per tombstone) is trivial. 

#### B. Per-device keys (Opus) vs. Shared iCloud Keychain private key (Gemini)
**CONCEDE to Opus.**
You are right about the hardware boundary. Generating keys in the Secure Enclave/StrongBox and ensuring they are non-exportable is the correct way to build this. Syncing the *trust list* (public keys) via iCloud Keychain achieves the exact same zero-prompt UX for a user's second Apple device that I wanted, without the catastrophic risk of syncing the private key material itself.

#### C. Ship Merge/Replace UX first (Gemini) vs. Ship sign+verify first (Opus)
**HOLD (Dispute).**
We are dealing with a live AirDrop vulnerability where malicious tombstones can wipe a user's library. Implementing Ed25519, managing trust stores, building TOFU UI, and testing Secure Enclave across iOS and Android Keystore will take weeks to get right. 
If we ship my Phase 1 first—a pure UI semantic split where "Merge" silently drops all tombstones and "Replace" applies them behind a massive destructive warning—we close the vulnerability *today*. We don't need cryptography to stop a file from deleting data on Merge. 
If your Phase 1 wins, users remain vulnerable while we build a complex crypto feature. We must ship the UX mitigation immediately, and the crypto in the next release.

#### D. File bootstraps trust (Gemini) vs. File never bootstraps trust (Opus)
**CONCEDE to Opus.**
This is a brilliant security boundary. By declaring that a file import can *never* prompt to add a key to the trust store, we completely eliminate the social engineering vector for `Merge`. If a malicious actor sends a `.kudosbackup` file, it will just silently add works and its tombstones will be dropped. The only way to trust a key is via the sync folder (TOFU) or an explicit QR scan. This is a massive improvement over my model.

#### E. UX metaphor: SSH known_hosts (Opus) vs. GPG (Prior Sketch)
**CONCEDE to Opus (and agree).**
We were both already pushing back against GPG. Your SSH `known_hosts` framing is exactly right. It should be entirely invisible when things are correct, and produce a blocking, un-dismissible hard stop when an identity mismatch occurs in a continuous sync context.

***

### REVISED DECISION SET

1. **[AGREE] Crypto Primitive:** Ed25519, platform-native only (`CryptoKit.Curve25519.Signing` / Android `java.security` or `Tink`). No GPG, no C dependencies.
2. **[AGREE] Key Storage:** Per-device keypairs. Private keys never leave the keychain/keystore (Secure Enclave/StrongBox). 
3. **[AGREE] Signature Target:** Sign tombstones at creation time, not backups at export time. Each tombstone carries `(signerPublicKey, signature)`. Non-tombstone records are unsigned.
4. **[AGREE] Trust Model:** Local trust store. iCloud Keychain syncs trust store entries across Apple devices (zero-prompt for 2nd iPhone). Android requires QR cross-authorization.
5. **[AGREE] File Import Trust:** A file cannot bootstrap trust. Unsigned/untrusted tombstones in a file import are silently dropped on Merge without prompting the user.
6. **[AGREE] Sync Folder TOFU:** First pubkey seen in the sync folder is pinned (if the reading device already has a keypair). Subsequent mismatches halt sync and require explicit resolution (SSH model).
7. **[AGREE] Replace UX:** Bypasses tombstone signing entirely because it is a destructive "nuke and pave" action, guarded by a biometric confirmation dialog.
8. **[AGREE] Legacy Tombstones:** Pre-signing-era tombstones are treated as unsigned and dropped on the next sync-folder read. No grandfathering.
9. **[STILL DISPUTE] Phasing:** Opus wants to ship sign+verify in Phase 1. I hold that Phase 1 must be the immediate release of the "Merge vs. Replace" UI split (Merge drops tombstones, Replace warns and applies). The crypto suite (key generation, signing, TOFU, and trust stores) becomes Phase 2. We cannot leave the vulnerability open while we build the cryptography.

---

## Full transcript: Opus 4.6 — Round 2

### Round 2 — Opus 4.6

---

#### A. Sign per-tombstone at delete time vs. sign the manifest at export

**I hold.**

Gemini's manifest approach has a multi-signer problem that breaks in practice. After you've synced from two devices, your local SwiftData store contains tombstones originated by Device A and Device B. When you export a `.kudosbackup`, who signs `manifest.json`? The exporting device. But that signature only proves "Device C exported this archive" — it says nothing about whether the tombstones *inside* were legitimately created. The importing device has to trust Device C wholesale, including tombstones C merely *relayed* from A and B.

Per-tombstone signing preserves provenance through relay. Each tombstone proves "Device A deleted work X at time T," regardless of which device later bundled it into a ZIP or wrote it to a sync folder. This is the property that makes the sync folder work without re-signing on every write.

Gemini's canonicalization concern is valid but doesn't apply here. The signed payload is not JSON — it's a fixed-format concatenation: `workId (UTF-8) || deletionTimestamp (ISO8601 UTF-8) || signerPublicKey (32 raw bytes)`. No key ordering, no whitespace, no encoder divergence. Swift and Kotlin produce identical bytes for this trivially.

I'd accept Gemini's manifest-with-hashes as an **integrity** layer on top (detect ZIP corruption, detect file tampering within the archive), but it cannot be the **authentication** layer. Authentication must live on the individual tombstone.

**What breaks if Gemini wins:** Sync folders become unsignable (no monolithic manifest to sign on every incremental write), and relayed tombstones lose provenance — you can't distinguish "tombstone from your trusted iPhone relayed through an untrusted export" from "tombstone an attacker injected into an export."

---

#### B. Per-device keys that never leave the keystore vs. iCloud Keychain carries the private key

**I concede.** Gemini is right on the pragmatics.

My Round 1 argued for per-device keys with Secure Enclave protection. But for tombstone signing in a reading app, the threat model doesn't justify the UX cost. The threat is *remote injection via files*, not *key extraction from a compromised device*. If an attacker has enough access to extract a key from Keychain, they can just delete works directly.

iCloud Keychain sync gives us 0 prompts for same-Apple-ID devices. That's a real UX win. Per-device revocation is a nice-to-have that no user of a reading app will ever need in Phase 1.

**One constraint I'd keep:** the key *can* live in iCloud Keychain, but the code should generate it as a standard `Curve25519.Signing.PrivateKey` (software-backed), not a Secure Enclave key — because SE keys are non-exportable by definition and can't sync. This is fine. We're choosing seamlessness over hardware-backed protection, and that's the correct tradeoff here.

Android Keystore remains device-local (no cross-platform Keychain equivalent), so cross-platform still requires the QR/TOFU path. Per-device keys return naturally when Android enters the picture in Phase 2.

---

#### C. Ship Merge/Replace UX first, keys later vs. ship sign+verify first

**I concede.** Gemini's phasing is better for time-to-fix.

The immediate vulnerability is: hostile `.kudosbackup` imported via Merge applies attacker's tombstones and deletes the user's library. Gemini's Phase 1 — Merge drops all tombstones, Replace applies them with a destructive warning — closes this attack with **zero crypto code**. It ships in days, not weeks.

My Phase 1 (sign+verify+TOFU) is more complete but takes longer and requires the entire signing infrastructure before the bug is fixed. That's backwards. Fix the hole first, then add the plumbing.

**Condition:** Phase 2 (Ed25519 signing) must ship in the immediately following release cycle, not "someday." The reason: between Phase 1 and Phase 2, sync-folder users lose tombstone propagation entirely (Merge drops all tombstones, even from yourself). That's an acceptable temporary regression, but it must be temporary.

---

#### D. Trusted-key file Merge applies tombstones vs. file never bootstraps trust

**I hold.**

We actually agree on the *outcome* for trusted keys: if the signer is already in your trust store, Merge applies tombstones. No dispute there.

The dispute is Gemini's D10: *"Show a one-time 'Trust this source?' prompt displaying a short key fingerprint when an unknown key is encountered on an explicit Merge."*

This is the social engineering hole. The attack: I send you a `.kudosbackup` containing 50 works you want plus tombstones for 200 works you have. You import it. A prompt appears: "Trust this source? Fingerprint: `a1b2-c3d4`." You tap Yes because you want the works. My key is now in your trust store. Every future file I send you can silently delete works via Merge.

The defense: **file import never prompts to add trust.** Trust enters the store only via:
- Self-trust at keygen (automatic)
- TOFU on first sync-folder read (prompted, but sync folders are access-controlled — the attacker needs your iCloud password)
- QR cross-authorization (requires physical proximity)

A file's tombstones are either from a key you already trust (applied silently) or from a key you don't (dropped silently, info banner). No middle ground, no prompt.

**What breaks if Gemini wins:** A single-tap trust prompt on file import defeats the entire signing system. The attacker's cost goes from "compromise the user's sync folder" to "send a file and hope they tap Yes." Most users will tap Yes. The signing infrastructure becomes theater.

---

#### E. UX metaphor: SSH known_hosts vs. GPG-shaped fingerprint

**Resolved — both sides converged.** Gemini's Round 1 explicitly rejects OpenPGP and describes TOFU + halt-on-key-change, which *is* the SSH model. The prior sketch's "GPG-shaped" suggestion is dead. No further dispute.

---

#### Points I Accept From Gemini That Weren't in My Round 1

- **Anti-time-travel (Gemini D5):** Reject tombstones with timestamps >24 hours in the future. Good catch, easy to implement, closes a real edge case. Accepted.
- **Manifest-with-hashes as integrity layer:** Not the signing target (see A above), but useful for detecting archive corruption. Accepted as an optional integrity check within `.kudosbackup` ZIPs.

---

### REVISED DECISION SET

| # | Decision | Status |
|---|---|---|
| D1 | **Primitive: Ed25519, platform-native only.** `CryptoKit.Curve25519.Signing` on Apple, `Tink` / native Ed25519 on Android. No libsodium, no GPG. | **AGREE** |
| D2 | **iCloud Keychain syncs the private key** (software-backed, not SE). Same-Apple-ID devices share identity with 0 prompts. Android Keystore remains device-local; cross-platform uses QR/TOFU. | **AGREE** (I conceded) |
| D3 | **Sign tombstones at creation time, not manifests at export.** Each tombstone carries `(signerPublicKey, signature)` over `(workId, deletionTimestamp, signerPublicKey)`. Non-tombstone records unsigned. Optional manifest-with-hashes for archive integrity only. | **STILL DISPUTE** — Gemini wants manifest-as-signing-target; I hold per-tombstone. See A above. |
| D4 | **File import never bootstraps trust.** Trust enters the store only via self-trust, sync-folder TOFU, or QR cross-auth. An unknown key's tombstones are silently dropped on Merge — no "Trust this source?" prompt on file import. | **STILL DISPUTE** — Gemini's D10 allows trust prompts on file import. See D above. |
| D5 | **Merge (untrusted/unsigned) drops all tombstones silently.** Info banner post-merge: "N works added. K tombstones skipped." Non-blocking, dismissible. | **AGREE** |
| D6 | **Merge (trusted) applies tombstones silently.** | **AGREE** |
| D7 | **Replace bypasses signing, requires destructive confirmation with biometric.** | **AGREE** |
| D8 | **Sync-folder TOFU with hard stop on pubkey change.** SSH `known_hosts` model. | **AGREE** |
| D9 | **Anti-time-travel: reject tombstone timestamps >24h in the future.** | **AGREE** (accepted from Gemini) |
| D10 | **Prompt budget: 0 for same-Apple-ID setup, 1 for sync-folder TOFU, 2 for cross-platform QR, 0 for file import.** | **AGREE** (updated to reflect iCloud Keychain concession) |
| D11 | **Pre-signing-era tombstones treated as unsigned.** No grandfathering. Documented in release notes. | **AGREE** |
| D12 | **Ship Merge/Replace UX split first (Phase 1, no crypto). Ship Ed25519 signing in immediately following release (Phase 2).** Phase 1 closes the hostile-file vector. Phase 2 re-enables tombstone propagation for trusted devices. | **AGREE** (I conceded, with tight Phase 2 timeline) |
| D13 | **Backward-compatible format.** `signature` and `signerPublicKey` are optional fields. Old clients ignore them. New clients treat unsigned tombstones as untrusted. | **AGREE** |
| D14 | **Total device loss = fresh start.** No recovery phrase, no account. Old sync-folder tombstones ignored (untrusted key). | **AGREE** |

---

### Summary of Movement

**I conceded B and C.** iCloud Keychain sync is the right tradeoff for a reading app (B), and shipping Merge/Replace before crypto gets the fix out faster (C). Both concessions are pragmatic, not principled — if Kudos were a medical records app, I'd hold on both.

**I hold A and D.** Per-tombstone signing (A) is architecturally necessary for sync folders and multi-device relay. No-trust-from-files (D) is the entire point of the signing system — allowing a trust prompt on file import makes the crypto decorative.

**Two items remain in dispute.** If Gemini concedes A and D, we have a locked design. If not, I'd want to hear specifically: how does manifest signing work for sync-folder incremental writes (A), and what prevents the "send a file, user taps Trust" attack (D)?

---

## Full transcript: Gemini 3.1 Pro — Round 3

### Gemini 3.1 Pro — Round 3 (Grok's dissent)

Grok brought the heat on this round, and honestly, the critiques are sharp. I’m dropping my previous resistance on several fronts because Grok’s architecture for Phase 2 is simply more robust. Here is where I stand on the remaining points:

**G1. REPLACE MUST NOT PERSIST UNSIGNED TOMBSTONES — AMEND**
I agree with the core premise: importing unsigned tombstones from an untrusted backup file during a Replace just re-injects the poison we are trying to eradicate. However, we cannot just silently drop works during a Replace without consequences. If a Replace is a nuke-and-pave, the works that are removed from the *local* database during that operation must stay deleted across the user's fleet. 
**Amendment:** Replace must not import the file's unsigned tombstones. Instead, for any local work that is deleted because it is absent from the Replace snapshot, the executing device must generate a **new** tombstone and sign it with **its own** Phase 2 private key. This ensures the Replace propagates securely.

**G2. PHASE 1 DROPS ON MERGE AND SYNC — LOCKED**
Acknowledged. The owner has locked this: Phase 1 drops all incoming unsigned tombstones across both vectors. Deletions will temporarily stop crossing devices until Phase 2.

**G3. LOCAL RE-SIGN, NOT BLANKET NO-GRANDFATHERING — CONCEDE**
Grok is entirely right about the UX disaster of mass resurrection. Since Phase 1 stops the bleeding of *new* unsigned tombstones over the network, the local tombstones present on a device at the exact moment of the Phase 2 upgrade are the cleanest state we have. Stamping these existing local tombstones with the device's new Phase 2 private key on first launch is the most pragmatic way to enforce strict signatures going forward without infuriating the user. 

**G4. SIGN THE SINK'S IDENTITY, NOT workId ALONE — CONCEDE**
I fully concede this. Cryptographic signatures must bind the entire identity of the record to prevent transplant or replay attacks. A signature over just a UUID leaves us vulnerable to an attacker swapping the `sourceURL` or `recordID` to suppress a different record. Signing the full canonical tuple (`recordType` + `ao3WorkID` + `canonical sourceURL` + `recordID` + `deletedAt` + `signerPublicKey`) is mandatory.

**G5. DO NOT PUT THE PRIVATE KEY IN iCLOUD KEYCHAIN — CONCEDE**
My previous stance on syncing the private key was flawed. Extracting or syncing private keys across devices unnecessarily expands the attack surface and turns iCloud into a signing oracle. Generating keys locally (ideally in the Secure Enclave) and using iCloud exclusively to publish and auto-trust the *public* keys among devices sharing the same Apple ID achieves the exact same frictionless UX with vastly superior security.

**G6. 24h CLOCK CLAMP IS NOT AUTHORIZATION — CONCEDE**
I over-indexed on the clock clamp in earlier rounds. Grok is correct: the clamp is merely a defense-in-depth mechanism against bizarre conflict-resolution edge cases and time-travel glitches. It cannot bear the weight of authorization. The cryptographic signature is the sole load-bearing pillar of trust in Phase 2. Keep the clamp, but rely on the signature.

***

### REVISED LOCKED SET

1. **Phase 1 Restriction (Owner Locked):** Phase 1 drops unsigned incoming tombstones on file Merge AND on folder sync. Deletions will not cross devices until Phase 2.
2. **Replace Behavior (Amended):** Replace operations do not import unsigned tombstones from the snapshot. Instead, works deleted locally as a result of the Replace generate new tombstones signed by the executing device's Phase 2 key to ensure secure propagation.
3. **Phase 2 Migration:** On first launch of Phase 2, locally stored pre-existing tombstones are grandfathered in by signing them with the device's new private key, preventing mass resurrection.
4. **Signature Payload:** Tombstone signatures must cryptographically bind the full identity tuple: `recordType` + `ao3WorkID` + canonical `sourceURL` + `recordID` + `deletedAt` + `signerPublicKey`.
5. **Key Management:** Private keys never leave the generating device. iCloud is used to sync only public keys, which are auto-trusted across the user's Apple ID.
6. **Defense in Depth:** The 24h clock clamp is retained purely as a sanity check for conflict resolution; authorization relies entirely on Phase 2 signatures.

---

## Full transcript: Opus 4.6 — Round 3

## Round 3 — Grok's Dissent Response

G2 is locked. I won't touch it. Here are the remaining five.

---

### G1. Replace must not persist unsigned tombstones — **CONCEDE**

Grok is right and I was wrong in the consensus draft. Replace is "make my library look like this file." Absence *is* the deletion signal in that mode — if a work isn't in the snapshot, it's gone from the local store. Persisting the file's unsigned tombstones as records serves no purpose for the Replace operation itself, and creates exactly the time-bomb Grok describes: user later does a Merge with their real backup, and those phantom tombstones fire `suppressesResurrection` against works the user never deleted.

The rule: **Replace loads works (and signed tombstones from trusted keys, once Phase 2 ships). Unsigned tombstone records in the file are not persisted.** Replace still *removes* local works absent from the snapshot — it just does so by diffing the work sets, not by inserting suppressor records.

---

### G3. Local re-sign on Phase 2 launch — **AMEND** (accept the mechanism, add a constraint)

Grok's core point is correct: blanket no-grandfathering causes a mass resurrection event on upgrade day, which is a worse UX failure than the attack it prevents. A device already trusts its own local store — signing those tombstones with the device's new key is a legitimate trust chain ("I, this device, attest I was already acting on these deletions").

**Amendment:** The migration runs exactly once, on first Phase 2 launch, and is recorded with a flag (e.g., `tombstoneMigrationComplete`). If pre-Phase-2 unsigned tombstones arrive *after* migration (from a stale backup file or an old device that hasn't launched Phase 2 yet), they are treated as unsigned incoming and **dropped** per the locked G2 rule. The re-sign is not a standing policy; it is a one-time grandfathering of the local store at the moment the device gains signing capability.

---

### G4. Sign the record's identity fields, not workId alone — **AMEND** (accept the field set, lock the serialization)

Grok is correct that signing only a UUID is insufficient — an attacker can swap the ao3WorkID or sourceURL on a tombstone while the UUID signature still verifies, targeting a different work. The signed payload must cover every field that participates in record identity and matching.

**Accepted field set:** `recordType + ao3WorkID + canonicalSourceURL + recordID + deletedAt + signerPublicKey`

**Amendment — lock the canonical serialization now, not at implementation time:**
- Fields concatenated in the order above, UTF-8 encoded, separated by `\n` (0x0A).
- `canonicalSourceURL` produced by the same normalization function on both platforms (lowercase scheme+host, strip trailing slash, resolve percent-encoding to uppercase, strip fragment). Define this function once in the spec before implementation begins.
- `deletedAt` serialized as ISO 8601 in UTC with no fractional seconds (`2026-08-15T16:00:00Z`).
- The signature is Ed25519 over this byte string.

If we don't lock serialization now, we get cross-platform verification failures on day one. I've seen this exact class of bug kill interop.

---

### G5. Private key never leaves the device — **CONCEDE**

Grok is right, and this is the cleaner design:

- Each device generates its own Ed25519 keypair on first Phase 2 launch.
- The **public key** is published to iCloud (KV store or a lightweight CloudKit record).
- Devices sharing an Apple ID auto-trust each other's public keys — **zero prompts**.
- The **private key** stays in the device's local Keychain (Secure Enclave where available), never synced.

Syncing the private key via iCloud Keychain would make every device on the Apple ID a signing oracle from a single credential — that's a strictly worse security posture with no UX benefit, since auto-trust of peer public keys already gives the seamless multi-device experience.

Bonus: per-device keys give us free provenance — you can tell *which* device authored a tombstone, which is useful for debugging and for a future "revoke a lost device's key" flow.

---

### G6. 24h clock clamp is defense-in-depth, not authorization — **CONCEDE**

The clamp stays (it's already shipped in iOS, it catches obvious backdating, it costs nothing). But Grok is right to frame it: a tombstone stamped 5 minutes ago still trivially beats a work whose `lastModifiedAt` is from 2019. The clamp is a sanity check, not a security boundary.

**Phase 2's load-bearing authorization check is the signature.** The clamp is a pre-filter that rejects obviously nonsensical timestamps before we even check the signature. That framing is correct and I accept it.

---

## Revised Locked Set

| # | Item | Status |
|---|---|---|
| **G1** | Replace loads works + signed tombstones only; unsigned tombstone records are not persisted. Absence = deletion for Replace. | ✅ Locked |
| **G2** | Phase 1: drop unsigned incoming tombstones on file Merge AND folder sync. (Owner-locked.) | ✅ Locked |
| **G3** | On first Phase 2 launch, locally re-sign existing tombstones with the device's new key (one-time migration, flagged). Post-migration unsigned arrivals still drop per G2. | ✅ Locked (amended) |
| **G4** | Signature covers `recordType + ao3WorkID + canonicalSourceURL + recordID + deletedAt + signerPublicKey`, newline-delimited, UTF-8, Ed25519. Canonical sourceURL normalization defined once in spec. | ✅ Locked (amended) |
| **G5** | Private key never leaves the creating device. iCloud publishes public keys only. Same Apple ID auto-trusts peer public keys (0 prompts). | ✅ Locked |
| **G6** | 24h clock clamp retained as defense-in-depth pre-filter. Signature is the load-bearing authorization check in Phase 2. | ✅ Locked |

No items remain in dispute from my side. If Grok or the owner want to challenge either amendment (the migration flag in G3, or the serialization spec in G4), I'll defend those — but the substance of all six points is now agreed.

### Opus 4.6 — Round 3 (Grok's dissent)

---

## Full transcript: Gemini 3.1 Pro — Merge vs Replace UX

I agree with the Merge/Replace binary. It’s a clean mental model for users who are already familiar with concepts like "Keep Both" vs "Replace" in macOS Finder or iOS Files. The challenge here isn't the verbs, but the blast radius of Replace, especially when Folder Sync gets involved. 

Here is my take on the exact semantics, edge cases, and how we should execute this.

### 1. Verbs and Framing
"Merge" and "Replace" are the right primary verbs. "Preview" isn't a third action; it should be the state *before* the action. When a user selects a backup file, we should parse its manifest and present an "Import Backup" sheet showing what's inside before they choose how to apply it.

### 2. Exact Merge Semantics
Merge must be strictly non-destructive and additive:
*   **Works:** Add any works not present locally. If a work already exists, keep it.
*   **Metadata (Tags, Collections, Annotations):** Union (merge sets). If the backup has collections A & B, and local has B & C, the result is A, B, & C.
*   **Progress:** Take the furthest read percentage or the most recent timestamp. Do not regress reading progress.
*   **Tombstones:** Dropped entirely in Phase 1 (per our locked rules).

### 3. Exact Replace Semantics (and the Folder Sync Trap)
Replace means "Make my local library exactly match this file."
*   **Scope:** Wipe SwiftData/Room entities (Works, Authors, Collections, Progress, Annotations). 
*   **Exceptions:** Do NOT wipe App Settings (fonts, themes, reader preferences) or Network Settings (AO3 login state).
*   **The Folder Sync Trap:** If Device A performs a Replace, its local database is wiped. However, since Grok rightly rejected minting new signed tombstones for works dropped by Replace, Device A cannot tell the Sync Folder that those works were intentionally deleted. Therefore, on the very next sync pass, the Sync Folder will re-inject all the wiped works right back onto Device A!
    *   *Solution:* If Folder Sync is active during a Replace, we must explicitly intervene. We either wipe the Sync Folder alongside the local DB, or we warn the user that they must turn off sync, otherwise the deleted works will return.

### 4. The Extra Step for Replace
Because of the "curated starter pack" failure mode (a user downloads a "Top 10 Reylo Fics.kudosbackup" from Tumblr, taps Replace, and accidentally wipes their 5,000-fic library), Replace must be highly defensive.
*   Show the math: "This will delete **[4,990]** works from your library and load **[10]** works."
*   Avoid typed confirmation ("Type REPLACE")—it's hostile and tedious on mobile. Instead, use a biometric gate (FaceID/TouchID) or a "Hold to Confirm" button, which is standard for modern iOS destructive actions.

### 5. Where these options live
These options should only appear on the explicit "Import Backup" sheet triggered from Settings or by tapping a `.kudosbackup` file. If the local library is entirely empty (first run, or manually cleared), we shouldn't even ask—just import the file immediately, as Merge and Replace are functionally identical in an empty state.

### 6. Folder Sync
Folder Sync must remain implicit Merge forever. Syncing is a continuous, bi-directional state-reconciliation protocol. "Replace from Sync" conceptually makes no sense; if a user wants to start fresh from their sync folder, they should simply use a "Clear Local Library" button in Settings, which will naturally cause the next sync pass to pull everything down fresh.

### 7. Phase 1 vs Phase 2
Yes, this UX ships cleanly in Phase 1. In Phase 1, we silently drop incoming unsigned tombstones. Merge just adds the backup's EPUBs. Replace wipes the local state and adds the backup's EPUBs. When Phase 2 arrives with Ed25519 signatures, this UI remains exactly the same—the only difference is that the under-the-hood engine will start parsing and trusting the signed tombstones.

### 8. Failure Modes
*   **Hostile Replace (0-work backup):** The UI delta ("Delete 500, Add 0") makes this obvious before execution.
*   **Accidental Replace:** Blocked by the FaceID/Hold-to-confirm gate.
*   **Wanting old deletions back:** Because Phase 1 drops tombstones, if a user Merges a backup that contains an EPUB they previously deleted, that EPUB will reappear. We just have to accept this as a Phase 1 limitation until keys arrive.

---

### Recommended Implementation

1. **Keep it to two verbs:** Merge and Replace. Do not offer a third top-level option.
2. **Contextual UI:** Only show the Merge/Replace choice if the local library has `count > 0`. Empty libraries get an immediate, frictionless import.
3. **Show the Delta:** Parse the backup manifest before taking action. Present a sheet saying: "Found [X] works in backup."
4. **Merge Default:** Make "Merge into Library" the primary, safe action button.
5. **Replace as Secondary:** Provide a secondary, red button for "Replace Library...".
6. **Replace Confirmation:** Tapping Replace triggers an action sheet or modal stating exactly what is about to happen: "This will permanently delete [Y] local works. Your library will be replaced by the backup."
7. **Biometric Lock:** Require FaceID / TouchID / Passcode to execute the Replace.
8. **Merge Semantics = Union:** Merge takes the union of collections/tags and the furthest reading progress. It never deletes.
9. **Replace Scope:** Replace wipes user content (works/progress) but strictly preserves app preferences (fonts/themes).
10. **The Sync Folder Catch:** If Folder Sync is enabled during a Replace, present a follow-up alert: "Clear Sync Folder as well? Otherwise, sync will re-download the works you just removed."
11. **Phase 1 Compatibility:** Ship this immediately in Phase 1. Silently dropping the unsigned tombstones from the file fits perfectly into both Merge and Replace semantics without requiring any UI changes for Phase 2.

### Gemini 3.1 Pro — Merge vs Replace UX

---

## Full transcript: Opus 4.6 — Merge vs Replace UX

# Merge vs Replace — Design Response

## 1. Verb Pair

Merge and Replace are the right pair. They map cleanly to the two mental models real users bring to a restore flow: *"give me what I'm missing"* vs *"make this device match that snapshot."* 

I'd resist adding a third peer verb. "Preview" is a *step within the flow*, not a sibling action — both Merge and Replace should show a summary before executing. "Add only EPUBs" is a filter that benefits maybe 2% of users and muddies a decision point that needs to be binary. Two verbs, one safe, one destructive. That's the shape.

One naming note: I'd label them **"Merge"** and **"Replace Library"** (never just "Replace") — the noun grounds the danger.

## 2. Merge Semantics

I want the simplest possible rule: **Merge adds works not already in the library. It never modifies or removes anything already present.**

No field-level "take newer metadata" logic. That requires trustworthy timestamps across devices and creates outcomes users can't predict. If a user sees 347 works locally and merges a backup with 400 works, 280 of which overlap, the result is 347 + 120 = 467 works. That's a sentence you can write on the confirmation screen.

What about reading progress, tags, collections, annotations on overlapping works? **Keep local, ignore incoming.** The user chose Merge because they want to keep what they have. If they wanted the backup's state, they'd choose Replace. Trying to cherry-pick "further-along progress" sounds smart but creates a hybrid state that is neither the local library nor the backup — hard to reason about, hard to debug, and impossible to explain in a confirmation dialog.

Unsigned tombstones from the file: dropped (locked). Signed tombstones (Phase 2): honored — but that's Phase 2's problem.

**Merge in one line:** *Union of works by identity. Local wins on overlap. Nothing deleted.*

## 3. Replace Semantics

Replace = nuke the works graph and load the snapshot. Specifically:

| Data | Replace behavior | Rationale |
|---|---|---|
| Works + EPUBs | Wiped, replaced by backup | That's the point |
| Reading progress | Comes from backup | Tied to works |
| Tags, collections | Comes from backup | Library organizational state |
| Annotations | Comes from backup | Tied to works |
| Fonts | **Kept** | Device-local asset, not library content |
| App settings/prefs | **Kept** | Device configuration ≠ library state |
| Trusted keys (Phase 2) | **Kept** | Security material lives outside the library |

Unsigned tombstones in the file: **dropped, not persisted** (locked). The device does **not** mint new signed tombstones for the works it just removed (locked — no fleet wipe).

### Does Replace propagate via folder sync?

**No.** Replace is device-local. But this creates a UX wrinkle: if Library Sync is enabled, the sync folder will immediately start re-merging works from peers back onto the replaced device. The user just wiped 400 works, and 350 reappear within minutes. That's confusing.

My recommendation: if Library Sync is active at Replace time, show a secondary prompt: *"Library Sync is on. Works from your sync folder will begin merging back after Replace. Pause sync?"* — with options to pause sync or continue with it active. This makes the interaction explicit without forcing a choice.

## 4. The Extra Step for Replace

Biometric is semantically wrong (it verifies *identity*, not *intent*). Typed confirm ("type REPLACE") is needlessly hostile for non-technical users. A checkbox is too easy to tap through mindlessly.

I'd do a **two-screen flow with a timed destructive button:**

**Screen 1 — Summary:**
> **Replace Library**
> 
> Your library: **347 works**
> This backup: **280 works**
> 
> • 120 works will be **removed** (not in backup)
> • 53 works will be **added** (not in library)
> • 227 works are in both (backup version will be used)
> 
> [Cancel]  [Review Changes →]

**Screen 2 — Confirmation:**
> ⚠️ **This will permanently replace your library**
>
> 120 works and their reading progress will be removed.
> This cannot be undone.
>
> [Cancel]  [Replace Library] ← destructive red, **enabled after 2-second delay**

The 2-second delay on the destructive button is the sweet spot: it forces a pause without being patronizing, and it's invisible to users who actually read the screen. iOS uses this pattern in "Erase All Content and Settings."

The counts on screen 1 are critical. A "curated starter pack" attack shows up as "347 works will be removed, 10 will be added" — that's a red flag even without security literacy.

### Auto-backup before Replace

Before executing Replace, silently export the current library to a timestamped `.kudosbackup` file in the app's documents directory (or the sync folder if active). This is the user's undo path. Mention it on screen 2: *"A backup of your current library will be saved automatically."*

## 5. Where the Options Live

| Surface | Behavior |
|---|---|
| **File import sheet** (.kudosbackup) | Primary location. Offer Merge / Replace Library. |
| **First-run / empty library** | Skip the choice. If library is empty, Merge and Replace are identical — just call it **"Restore"** and import. |
| **"Restore from iCloud file"** | Same as file import — offer Merge / Replace. |
| **Folder sync settings** | No. Folder sync is always implicit Merge (see §6). |

On first-run, if the user opens a `.kudosbackup` file before adding any works, showing "Merge vs Replace" is confusing because there's nothing to merge *into* and nothing to *replace*. A single "Restore from Backup" button with no fork is the right UX here.

## 6. Folder Sync

**Folder sync stays implicit Merge forever.** Replace via folder sync is incoherent:
- Which device wins? There's no "source of truth" in a peer mesh.
- A stale backup in the sync folder could nuke a fresh library.
- Continuous Replace doesn't have a meaningful definition.

If a user wants device B to match device A, the workflow is: export from A → file import on B → choose Replace. That's explicit, auditable, and doesn't infect the sync protocol with destructive semantics.

## 7. Phase 1 Viability

**Yes, this UX ships cleanly in Phase 1.**

- **Merge**: adds missing works, drops unsigned tombstones. ✓
- **Replace**: wipes and loads. Unsigned tombstones not persisted. No signed tombstones minted for removed works. ✓

The only Phase 2 change to this UX is that Merge will eventually honor *signed* tombstones from trusted keys. The Merge/Replace choice screen, the confirmation flow, the diff summary — none of that depends on cryptographic infrastructure. Ship it now.

## 8. Failure Modes

**"Curated starter pack" social engineering.** Attacker shares a small backup disguised as a recommendation list, hoping the user taps Replace. Mitigated by: (a) the diff summary showing a massive removal count, (b) the 2-second delay, (c) the auto-backup. In Phase 1, unsigned tombstones are dropped, so the attacker can't even smuggle deletions into a Merge.

**Empty/tiny hostile Replace.** Backup has 0–2 works. The diff summary shows "345 works will be removed, 1 will be added." If the removal count exceeds, say, 10× the addition count *and* is above some threshold (≥20 removals), add an extra line in amber: *"This backup is much smaller than your current library."* Not a block — just a nudge.

**User who wanted Merge and tapped Replace.** The auto-backup is the safety net. The 2-screen flow with explicit counts also helps — Merge's screen 1 would say "53 works will be added, nothing removed," which looks obviously different from Replace's "120 works will be removed."

**User who wanted old deletions to come back.** In Phase 1 this just works — unsigned tombstones are dropped during Merge, so previously-deleted works in the backup will reappear if they're re-added. In Phase 2, Merge will honor signed tombstones from trusted keys, which means the user would need to either: (a) clear the tombstone manually (a future "Manage Deletions" UI), or (b) use Replace to get a clean slate. That Phase 2 UI is out of scope here, but the Merge/Replace architecture supports it.

---

## Recommendations — What I'd Ship

1. **Two verbs only: Merge and Replace Library.** No third option. Preview is a step within each flow, not a peer action.

2. **Merge = set union by work identity. Local always wins on overlap. Nothing modified, nothing deleted.** No field-level "take newer" merging — that's a Phase 3 optimization if ever.

3. **Replace = wipe all works/progress/tags/collections/annotations, load backup. Keep fonts, settings, and trusted keys.** Unsigned tombstones from the file are dropped, no new signed tombstones minted for removed works.

4. **Two-screen Replace confirmation** with diff counts (removed / added / in-both) on screen 1, and a timed destructive button (2-second delay) on screen 2. If removal count ≫ addition count, add an amber "this backup is much smaller" nudge.

5. **Auto-backup before Replace.** Silently export the current library to a timestamped file before executing. Mention its existence on the confirmation screen as an undo path.

6. **If Library Sync is active during Replace, prompt to pause sync.** Otherwise the sync folder immediately re-merges works the user just removed.

7. **Empty library / first-run: skip the fork.** Show a single "Restore from Backup" button. Merge and Replace are identical on an empty library.

8. **Folder sync stays implicit Merge forever.** No Replace-via-sync. Users who want device-to-device Replace use file export → file import.

9. **File import sheet and iCloud restore both offer the Merge/Replace choice.** These are the only two surfaces. Folder sync settings do not.

10. **Ship in Phase 1.** Nothing in this UX depends on Ed25519 keys. Unsigned tombstones are already dropped. The confirmation flow, diff summary, and auto-backup all work without cryptographic infrastructure.

11. **Copy on the Merge confirmation screen:** *"X works will be added to your library. Nothing will be removed or changed."* — that one sentence does more to prevent misclicks than any amount of UI chrome.

12. **The result screen after either operation should state what happened in past tense with counts.** *"Merged: 53 works added. Your library now has 400 works."* or *"Replaced: 280 works loaded. 120 previously in your library were removed. Auto-backup saved."*

---

### Opus 4.6 — Merge vs Replace UX

---

## Implementation status (2026-08-15)

Spec locked with three restore modes (`reconcile` / `merge` / `replaceLibrary`). See `handoff.md`. This discussion is not the implementation spec.

- **iOS:** commit `a0533c1` (Opus started restore + Settings fork; Grok finished `ReplaceLibraryConfirmationView`, `makePreReplaceBackup`, `BackupImportMode.reconcile`, and two production-entry tests). Harness / Mutation A/B still pending.
- **Android:** commit `a1aa83f` (Phase 1 tombstone drop + Replace UX + ledger companions) plus uncommitted `RECONCILE` split (`BackupImportMode.RECONCILE`, MERGE skip-overlap, `importPackage` default `RECONCILE`). File UI still passes `MERGE`.
- **Opus implementation job** relaunched (`OPUS-IMPLEMENT.md`) to add remaining iOS tests and mutation evidence. Do not rewrite working restore.
- **No push.** Branch `security-fixes/tombstone-trust` is local only.
