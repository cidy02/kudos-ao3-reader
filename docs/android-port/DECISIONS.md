# Decisions log (Claude, under the owner's grant of 2026-10-02)

Newest first. Each entry: decision · why · evidence · how to reverse · backup (if lossy).

- **2026-10-02 · T-353 stores `downloadedAt` as a work field, not inside the EPUB or by editing Date Added.**
  Why: writing into the EPUB alters the preserved copy and `epubDigest`, and an AO3 refresh replaces the
  file. Editing Date Added would have needed a new sync rule, because both apps merge Date Added as the
  earlier of two copies. Evidence: the owner's own AO3 EPUB carries only `calibre:timestamp`
  (generation) and `dc:date` (last update). Reverse: drop the field; nothing else depends on it.
- **2026-10-02 · Library shelves follow iOS's rules, not iOS simulator counts.** The simulator's demo
  store was stale, so Finished counts 2 on a fresh seed. Evidence: `LibrarySectionKind.swift:127-129`.
  Reverse: n/a (iOS parity).
- **2026-10-02 · Android backup dates use three fractional digits** (`2023-11-14T22:13:20.000Z`), the
  iOS format, so archives round-trip byte-for-byte. Reverse: `BackupValidator.formatInstant`.
- **2026-10-03 · T-354 landed on iOS alone, before the full cross-platform suite was green.** Why: it is
  a data-loss fix (every EPUB in an Android backup was dropped on iOS restore), it's small and
  additive, and iOS's existing backup suites show only the two known pre-existing failures. Reverse:
  revert b02bf8ec.
- **2026-10-03 · The Android demo must never reach AO3 (brief 1e).** Agents ran Browse against live AO3.
  Until the demo network block lands, agents may not open Browse or Search on the emulator.
