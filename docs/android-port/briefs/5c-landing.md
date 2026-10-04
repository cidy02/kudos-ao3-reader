# Brief 5c: what was landed (2026-10-04)

Codex's audit is `5c-result.md`: 29 findings and patches it could not build or run. This file
records what Claude did with them. Where the two differ, this file is what the code does.

## Where it stands

| | |
|---|---|
| Android | `android/redesign-parity`, 8 commits `e533b986`…`0cc50518`. Gate: 1,252 unit tests, all pass. |
| iOS | `91f3930f` on `claude/polish-loop`, `ef120853` on `integrate/cloud-redesign` (T-357). The nine suites that sync a folder: 73 tests pass on the case-sensitive volume. Lint clean. macOS builds. |
| Not pushed | All of it. |
| Not done | A real cloud provider, a real iPhone, two devices at once. See "Not verified". |

## What was changed from Codex's proposal, and why

Codex's patches stopped the sync and wrote nothing in four states: no manifest in a folder that
holds files, a damaged manifest, a listed file that is not in the folder, and a font over a
limit. On both apps. Each of those states is one a folder can be left in for good, so the folder
could never sync again; an interrupted first sync alone leaves "files and no manifest".

Both apps now follow one rule instead: **always write the manifest; delete nothing without a
full view of the folder.** A full view means the live manifest was read, every listed file that
is in the folder was taken, and no conflict copy was left unfolded. The cases:

| The folder | Android | iOS |
|---|---|---|
| Holds nothing | First write. | First write. |
| Files, no manifest | Recovers from `.bak` if there is one; writes; prunes nothing. | Writes; prunes nothing. |
| Manifest cut short (not JSON) | Recovers from `.bak`; writes a whole one; prunes nothing. | The same, from Android's `.bak`. |
| Whole JSON that does not decode | Stops with a message; the file is left as it is. | Stops (it always did). |
| There, and not readable at all | Stops. | Stops (it always did). |
| A listed file is not in the folder | Nothing to fetch. | Nothing to fetch (it always was). |
| A listed file is there and unreadable, or over a limit | Skipped; no prune this run. A font stays in the manifest Android writes. | Skipped; no prune until it is taken. |
| Changed by another device during the sync | Stops; the next sync reads it first. | Reads before every upload. |

Other differences from the proposal:

- **The manifest is written in place** (the proposal kept Android's rename and guarded iOS
  against it). A released iPhone has no guard, and reads the moment without a manifest as an
  empty folder.
- **An old lowercase EPUB is still replaced under iOS's name.** The proposal kept the lowercase
  name. A released iPhone reads no other name than the one in capitals.
- **Fonts are looked up by exact name, then composed form; case is not folded.** The proposal
  folded case, which let one font's bytes be written over another's file.
- **A folded conflict copy is deleted after the manifest is written**, not at the fold.
- **EPUBs from the folder are read with the 128 MB per-entry limit.** The proposal left them
  unbounded.

## Seen on the emulator (Android's own storage provider)

The demo library, a folder under `Documents/`, `Kudos_Verify` in airplane mode.

- A sync over an existing manifest: `manifest.json` and `manifest.json.bak` under exactly those
  names, no "(1)" copy, no temp left; `.bak` holds the manifest that was replaced.
- The manifest cut to 20,000 bytes, and a stray EPUB added: one sync wrote a whole manifest (18
  works), kept the stray file, and left `.bak` alone. The next sync pruned the stray file.
- The manifest removed, a stray EPUB added: one sync wrote a manifest and kept the stray file.
- A manifest saying `"version": 99`: left as it was, nothing pruned, and the page shows "This
  version of Kudos cannot read the sync folder's manifest. Its files were kept."
- A `pronunciations` key added to the manifest: still there, as written, after a sync.
- A `manifest (1).json` beside the manifest: folded, removed, and the page shows "Merged 1
  conflicting copy from another device."

## Not verified

- **Any cloud storage.** The apps were checked against a folder of files. How a storage app
  uploads, lists and renames those files is the part nothing here has seen.
- **A real iPhone and a real Android phone on one folder.** The two apps read each other's
  folders in tests (`CrossPlatformFolderSyncTests` on iOS, the golden folder tests on Android),
  one direction at a time. A folder both have written to in turn has not been tested.
- **iOS on a device.** Unit tests, lint and a macOS build only.
- **A disk that fails in the middle of a write**, beyond the one test of a read-only directory.

## The 29 findings

| | Finding | Now |
|---|---|---|
| F1 | iOS prunes while Android's manifest is renamed away | **Fixed both sides.** Android writes in place; iOS prunes nothing without a manifest. |
| F2 | A stale upload writes over the only index | **Fixed.** Android stops if the manifest changed; iOS reads before every upload. Two devices in the same instant: owner question 6. |
| F3 | iOS cannot read, and prunes, lowercase EPUB names | **Fixed.** iOS reads either case; Android still renames its old files. |
| F4 | Android prunes after reading only `.bak` | **Fixed.** |
| F5 | Batches refuse later EPUBs | **Fixed** (equal clock replaces). Open: a work newly marked preserved by an earlier batch can still have its file refused. |
| F6 | A later tombstone can narrow what is suppressed | **Fixed on Android**, stricter than iOS: owner question 8. |
| F7 | A saved search made during an import is deleted | **Fixed** for saved searches. Open: the same pattern for reading sessions, favorites and watermarks. |
| F8 | A colliding font is copied once per batch | **Fixed** per sync. Open: repeated restores still add suffixed copies, on both apps. |
| F9 | Unbounded reads; delete before write | **Partly.** Reads are bounded. Writes still truncate the file they replace. |
| F10 | Conflict copies discarded early, or ignored | **Partly.** Android deletes after the commit and keeps what it cannot fold. Open: iOS does not read a `manifest (1).json` at all. |
| F11 | Late files stranded | **Partly.** Fonts not taken stay listed. A font whose file has not arrived at all is not listed again until its owner syncs. |
| F12 | An original and its record can be split across batches | Open. |
| F13 | The EPUB check takes the first `.opf` | **Fixed.** |
| F14 | More than 32 MB of fonts never finishes | **Fixed.** Open: a test at the real 32 MB limit. |
| F15 | File names: Unicode, duplicates, length | **Partly.** Composed form compared. Open: two files of one name on a provider; names over 128 characters. |
| F16 | Fields lost through Android | **Fixed for the folder** (unknown top-level keys are written back). Open: a backup made on Android holds no pronunciations; unknown keys inside a record are still dropped. |
| F17 | Dates are not a safe "has it changed" signal | **Fixed on Android** (bytes compared). Open on iOS: it still skips a read when the date is unchanged. |
| F18 | A failed write reported as success | **Fixed.** |
| F19 | Deleted saved links and highlights stay on the peer | Open, both apps: owner question 7. |
| F20 | Recently Deleted's countdown restarts on sync | **Fixed.** |
| F21 | "Kept" and "queued" flags can never go back to off | Open. |
| F22 | A stranger's file pruned as an original | **Fixed.** |
| F23 | A failed re-import deletes the original | **Fixed.** |
| F24 | The EPUB gate trusts the flag, not the file | **Fixed.** |
| F25 | Clocks from the future are bounded differently | Open, iOS side: owner question 8. |
| F26 | Each app ignores the other's old single-file sync | Open. Only matters for a folder last written by a very old build of the other app. |
| F27 | Android's limits and whole-memory restore | Open: owner question 8. |
| F28 | Android promised Apple-account trust | **Fixed** (text). iOS's text: owner question 7. |
| F29 | Replace Library deletes collections and queues for good on Android | Open. iOS keeps them 90 days. |

Found while landing, not in the audit:

- **Android has no `remoteEPUBPending`.** iOS remembers that a work was promised an EPUB it has
  not received, and goes on saying so in its manifest. Android says "no EPUB", and an iPhone
  that reads that stops looking for the file. Needs a Room column and a migration test.
- **A sync that fails in the background leaves no message on Android.** iOS stores its last
  error; Android shows one only after a tap on Sync Now.
- **Android fetches an EPUB from the folder whatever the manifest's flag says**; iOS fetches only
  when the flag is set. A download removed on Android comes back at the next sync.
