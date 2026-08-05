# iOS issues found while porting to Android

Bugs and inconsistencies noticed in the iOS app (`hig-review`) while porting its
behaviour to Android for the full-parity sweep. **Nothing here has been fixed on
iOS** — this is a to-do list for a later iOS pass.

Each entry records what Android did in the meantime, so the two platforms don't
silently drift while the iOS side is still open.

---

## 1. `Recently Updated` empty-state copy names the wrong source

**iOS:** `Features/Home/HomeSections.swift` — `HomeSectionKind.recentlyUpdated.emptyMessage`

```swift
case .recentlyUpdated:
    "No recent updates from your subscriptions yet."
```

But the section is not built from subscriptions. Its own `works(from:visible:)`
filters saved works by `hasUpdate`:

```swift
case .recentlyUpdated:
    works.filter { $0.hasUpdate && !$0.isQueueOnlyWork && visible($0) }
```

`hasUpdate` is a property of a locally saved work (AO3 has posted chapters since
the user last saw it). A user with no AO3 subscriptions at all still populates
this section from their own library, and a user with many subscriptions sees
nothing here unless their *saved* works updated. The copy sends them to the wrong
place to fix an empty section.

**Severity:** low — copy only, no behavioural impact.

**Android:** kept the accurate wording already in `HomeScreen.kt` ("No recent
updates from your library works yet") rather than porting the incorrect string.
This is a deliberate, documented divergence: propagating wrong copy to a second
platform would just mean fixing it twice. Align iOS to Android here, not the
reverse.

---

## 2. MuPDF is built and verified but never wired in

**iOS:** `docs/PDF_ENGINE_MUPDF.md` — status line, 2026-07-30

> **Status:** feasibility proven and output verified (2026-07-30). The library is
> not yet wired into the app — see "Remaining work".

The document is thorough and the build script (`Scripts/build-mupdf.sh`) produces
a stripped 6.4 MB static library with verified byte-identical structured-text
extraction. But `PDFWorkConverter.swift` still imports PDFKit and Vision, so the
five layout defects the document exists to solve are, as of this branch, still
live in shipping iOS PDF conversion.

**Severity:** medium — PDF import on iOS still uses the path documented as
producing silent prose relocation (defect 5 in that document, called "the worst
failure mode a preservation app can have").

**Android:** not affected yet. Android's PDF path currently refuses to convert
compressed PDFs rather than emitting garbage, and MuPDF is scheduled as the last
item of this sweep. When Android wires MuPDF in, iOS should follow — the build
flags and the two-function wrapper surface port directly.

---

## 3. Sync skips unchanged files by size alone, so a same-size edit never syncs

**iOS:** `Services/FolderSyncService.swift:707-710`

```swift
nonisolated private func writeIfChanged(_ data: Data, to url: URL) throws {
    if let existingSize = fileSize(of: url), existingSize == data.count { return }
    try data.write(to: url, options: .atomic)
}
```

Size equality is not content equality. Any asset whose replacement happens to
have the same byte length is silently never written to the sync folder, and the
other device keeps the stale copy indefinitely — there is no later pass that
would catch it, because the next sync makes the same comparison and skips again.

The blast radius is limited but real: the manifest itself is written
unconditionally (`:687`), so the *index* stays correct while an asset it points
at is stale — arguably worse than both being stale, since nothing looks wrong.

A content hash, or size plus modification time, would close it.

**Severity:** low-probability, high-consequence — this is a sync/preservation
path, and the failure is silent.

**Android:** ported faithfully (`backup/SyncRepository.kt` `writeIfChanged`),
because iOS is the specification for this sweep and diverging unilaterally would
make the two platforms disagree about what "unchanged" means. Fix both together.

---

## 4. `foldedConflicts` has no Android counterpart yet

**iOS:** `FolderSyncService.swift:204-217` increments `result.foldedConflicts`
for every conflict version it folds in.

Android's port merges every conflicting manifest correctly (that is the important
half), but discards the count, so a user whose devices are quietly colliding gets
no signal. Not an iOS bug — an Android gap recorded here so it isn't lost.

---

*Add new entries as they're found. Keep the "Android:" line on every one — it's
what stops an undocumented divergence from looking like an Android defect later.*
