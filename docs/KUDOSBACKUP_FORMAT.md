# Portable `.kudosbackup` format

Cross-platform contract for **manual import/export**. Folder sync (iOS and Android) uses a
plain `KudosLibrary/` directory with the same tree; that is a transport detail, not the portable format.

## Container

| Property | Value |
|---|---|
| File extension | `.kudosbackup` |
| Container | **ZIP**, classic or ZIP64 (ZIP64 records only where a value outgrows its classic field) |
| Compression methods | **0 (store)** and/or **8 (deflate)** only |
| Encryption | Not used; encrypted entries are rejected |
| Path encoding | UTF-8; `/` separators; no `..`, absolute, or backslash paths |

iOS writes **store-only** entries (EPUBs are already compressed). Android writes every
entry deflated (`ZipOutputStream` default); readers must accept both.

## Logical layout (ZIP entry names)

```text
manifest.json
Works/<uuid>.epub
Fonts/<safe-filename>
Originals/<safe-filename>
```

- `manifest.json` is required at the archive root.
- Work EPUB paths use the work record UUID from the manifest (`KudosBackupWork.id`).
- Font file names must be basename-only (no path separators).
- `Originals/` holds the file a converted import was made from (`<UPPERCASE-UUID>.<ext>`) and its record (`<UPPERCASE-UUID>.conversion.json`); it has no manifest field.
- Directory-only entries are optional and ignored.

This layout matches the historical directory-package tree so the same payload model
(`KudosBackupContents`) can load either form.

## Manifest

- JSON object; schema version in `version` (currently **8**; decoders accept 1…8).
- Dates: ISO-8601; writers should emit fractional seconds; readers fall back to whole seconds.
- Merge / tombstone / progress rules live in app code (`KudosBackupService.restore`), not in the container.

## Platform notes

| Platform | Create | Extract |
|---|---|---|
| iOS / macOS (this app) | `MiniZip.ArchiveWriter` (store-only), streamed to a file by `KudosBackupService.writeArchive`; `KudosBackupContents.zipData()` builds the same archive in memory | `MiniZip` with `.backup` size limits |
| Android (`android/`) | `java.util.zip.ZipOutputStream` (`BackupExporter`) | `ZipInputStream` (`BackupImporter`) |
| Shared contract | This document + `manifest.json` fields | Same |

Do **not** share a native C ZIP library across apps unless there is a strong reason;
keep the **format** identical and use platform ZIP APIs.

## Legacy directory packages

Older exports, and the pre-2026 iOS **Library Sync Folder** package (`KudosLibrary.kudosbackup`,
now read-only), may still be a **directory** named `*.kudosbackup` with the same internal tree. Importers **must** accept:

1. A regular ZIP file, and  
2. A directory package with `manifest.json` at its root.

Detection is by filesystem type (file vs directory), not by UTI alone.

## Non-goals

- ZIP64 (archives stay under classic size limits; iOS backup limit is ~3.5 GiB uncompressed total).
- Streaming restore (export streams to a file; restore still opens the whole archive in memory; the full archive remains the portable unit).
- Putting derived fields such as `searchText` in the backup (rebuild on restore).
