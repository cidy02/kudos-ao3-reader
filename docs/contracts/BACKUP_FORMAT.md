# Backup Format Contract

Status: Phase 0 skeleton. This records the current Apple v1 facts and the
intended v2 additions before Android implementation begins.

## Current Apple v1 Facts

Reference implementation: `kudos-ao3-reader/Services/KudosBackup.swift`.

| Area | Current Apple v1 fact |
|---|---|
| Container | Directory-backed `.kudosbackup` package |
| Manifest | `manifest.json` |
| Dates | ISO-8601 date strings |
| JSON output | Pretty printed with sorted keys |
| Work files | `Works/<UUID>.epub` |
| Font files | `Fonts/<fileName>` |
| Top-level arrays | `works`, `bookmarks`, `fonts` |
| Settings | Current reader/app settings fields only |
| Not included | `collections`, `savedSearches`, `comments`, `hits`, `knownChapterCount`, `lastUpdateCheck` |

Current v1 manifest shape:

```json
{
  "version": 1,
  "exportedAt": "ISO-8601 date string",
  "works": [],
  "bookmarks": [],
  "fonts": [],
  "settings": {}
}
```

## Current v1 Work Fields

Current Apple v1 work manifests include:

- `id`
- `title`
- `author`
- `summary`
- `sourceURL`
- `dateAdded`
- `isFavorite`
- `isSaved`
- `isFinished`
- `hasEPUB`
- `isComplete`
- `rating`
- `language`
- `wordCount`
- `chapters`
- `kudos`
- `workWarnings`
- `workCategories`
- `seriesTitle`
- `seriesPosition`
- `seriesURL`
- `lastSpineIndex`
- `lastScrollFraction`
- `lastReadDate`
- `workTags`
- `workFandoms`
- `workCharacters`
- `workRelationships`
- `workFreeforms`
- `workTagsFetched`
- `userTags`
- `readiumLocator`

The current Swift model has `comments`, `hits`, `knownChapterCount`, and
`lastUpdateCheck`, but v1 backups do not export them.

## Current v1 Merge Semantics

Restore is merge-only and non-destructive:

- Works merge by UUID.
- Bookmarks merge by `urlString`.
- Fonts merge by safe file name.
- User tags merge by trimmed tag name.
- EPUB files are written atomically when present.
- If the backup lacks an EPUB and no local EPUB exists, `hasEPUB` becomes false.
- If `readerFontID` points to a missing custom font, it resets to `system`.
- Unsupported versions are rejected.
- Invalid packages are rejected.

## v2 Direction

Backup v2 should be a single ZIP file with `.kudosbackup` extension:

```text
manifest.json
Works/<UUID>.epub
Fonts/<fileName>
```

Android should write v2. Apple should be updated to read v1 directory packages
and v2 ZIP packages before public Android release.

## Explicit v2 Additions

These are deliberate v2 additions, not existing v1 parity fields:

| Field/area | v1 status | v2 intent |
|---|---|---|
| `comments` | Not exported in current v1 | Optional work stat |
| `hits` | Not exported in current v1 | Optional work stat |
| `knownChapterCount` | Not exported in current v1 | Update-check support |
| `lastUpdateCheck` | Not exported in current v1 | Update-check support |
| `collections` | Not exported in current v1 | Cross-platform local collections |
| `savedSearches` | Not exported in current v1 | Cross-platform saved AO3 searches |
| Readium locator metadata | Not exported in current v1 | Same-platform precision and engine safety |

Android must not write these fields into a v1 manifest.

## Encoding Rules

- JSON is UTF-8.
- v1 compatibility is ISO-8601 date strings.
- v2 dates should be ISO-8601 UTC strings.
- UUIDs are parsed case-insensitively and canonicalized for comparisons.
- Importers must not depend on JSON key order.
- Backup files are untrusted input.
- ZIP paths must reject absolute paths, `../`, and traversal.
- Import/export should stream entries rather than loading full backups into memory.
- Session cookies, CSRF tokens, passwords, personal credentials, and platform
  absolute paths must never appear in `.kudosbackup`.

## Required Future Tests

- v1 directory import
- v2 ZIP import/export
- unsupported version rejection
- path traversal rejection
- merge does not delete existing EPUBs
- missing custom font falls back to `system`
- v2 additions round-trip once both platforms support them
