# EPUB Parsing and Import Assumptions

Kudos is optimized for unprotected EPUBs downloaded from Archive of Our Own.
This document records what the app actually accepts, which metadata it uses, and
where the legacy parser intentionally falls short of a general-purpose EPUB
implementation.

## Platform behavior (single `main` branch)

| Platform | Import metadata | Reader |
|---|---|---|
| iOS / iPadOS | Readium `Publication` | Readium EPUB navigator |
| macOS | Legacy `MiniZip` + `OPFParser` | Legacy `EPUBDocument` + `WKWebView` (`#if os(macOS)`) |

The legacy stack therefore remains production code even after the iOS Readium
migration. Changes to its format assumptions must still be tested on both
branches.

## Legacy pipeline

The legacy path is deliberately small:

1. `MiniZip` reads the ZIP central directory.
2. `META-INF/container.xml` supplies the first `rootfile` `full-path`.
3. `OPFParser` reads metadata, manifest items, and spine order.
4. `NavTOCParser` or `NCXParser` builds a flat chapter list.
5. For reading, every archive entry is extracted into the work's cache
   directory and each spine resource is loaded as a local file in `WKWebView`.

`EPUBDocument.metadata(ofEPUBAt:)` reads only the container and OPF directly
from the ZIP. `EPUBDocument.open(epubURL:into:)` extracts the complete archive
before parsing and rendering it.

## ZIP assumptions

`MiniZip` is not a complete ZIP implementation. It assumes:

- A single-disk archive with a conventional central directory and End of Central
  Directory record.
- The EOCD is within the final 65,558 bytes, allowing the standard maximum ZIP
  comment.
- Entry counts, sizes, and local-header offsets fit in 16/32-bit ZIP fields.
  ZIP64 is unsupported.
- File names are UTF-8. Legacy ZIP filename encodings are not decoded.
- Entries are either stored (`method 0`) or DEFLATE-compressed (`method 8`).
  Other nonzero methods are currently attempted as DEFLATE and will fail.
- Entries are not encrypted. DRM-protected EPUBs are unsupported.
- Central-directory sizes are accurate. CRC values are not checked.

The parser does not require or validate the EPUB `mimetype` entry, its position,
or whether it is stored uncompressed. A ZIP is treated as an EPUB only when the
expected container and package files can subsequently be found and parsed.

Extraction skips entries whose payload cannot be decoded. As a result, a
corrupt required file may later surface as `missingContainer`,
`missingPackage`, or `noReadableContent` rather than `extractionFailed`.
`extractionFailed` is primarily reserved for filesystem write failures.

## Container, OPF, and spine assumptions

- The container is found at the exact, case-sensitive path
  `META-INF/container.xml`.
- The first XML element named `rootfile` with a `full-path` wins. Multiple
  renditions are not selected by media type or other criteria.
- The OPF path and manifest hrefs are treated as paths relative to their
  containing directory.
- XML must be well formed enough for Foundation's `XMLParser`.
- Namespace prefixes are ignored by taking each element's local name.
- Every readable spine `itemref` must have an `idref` matching a manifest item.
  Missing manifest references are dropped.
- At least one matched spine item is required.
- Spine media types are not validated, and `linear="no"` is ignored. The app
  assumes spine entries point to resources that `WKWebView` can render.
- All archive resources are extracted up front so relative CSS, image, and font
  references can resolve beneath the extracted root.

Manifest paths are not normalized or validated against the extraction root.
Archive entry names are appended directly to the cache directory. Imported
EPUBs must therefore be treated as trusted input; before expanding arbitrary
third-party import, add canonical-path containment checks to prevent `../` path
traversal.

The legacy reader also renders publisher XHTML directly. It does not sanitize
markup or strip publisher scripts; it relies on WebKit's local-file isolation
and limits file read access to the extracted work directory.

## Table-of-contents behavior

The app prefers an EPUB 3 navigation document identified by a manifest
`properties` value containing `nav`. It falls back to:

1. the OPF spine's `toc` manifest id; or
2. the first manifest item with media type `application/x-dtbncx+xml`.

The EPUB 3 nav document must be XML-compatible XHTML and contain a `nav` whose
`epub:type`/`type` contains `toc`, or whose `id` is `toc`. If nav parsing yields
no entries, the app tries NCX.

TOC output is intentionally simplified:

- Nested navigation is flattened into document order.
- Targets are matched to the spine by URL-decoded, lowercased basename after
  removing fragments.
- This assumes spine resources have unique basenames. Two files such as
  `part1/chapter.xhtml` and `part2/chapter.xhtml` are ambiguous.
- Multiple anchors into one spine resource collapse to the first matching
  chapter because entries are deduplicated by spine index.
- TOC targets outside the spine are ignored.
- Titles receive one additional HTML-entity decode to handle double-encoded
  calibre/AO3 exports.
- If no usable TOC remains, the reader creates `Section 1`, `Section 2`, and so
  on for every spine item.

## Metadata used by the Library

The legacy parser reads:

- the first `dc:title`
- the first `dc:creator`
- the first `dc:description`
- the first `dc:language`
- every `dc:subject`
- calibre's legacy `calibre:series` and `calibre:series_index` meta fields

It does not interpret creator roles, EPUB 3 metadata refinements, alternate
titles, multiple authors, or general collection metadata. A calibre series
position is parsed as `Double` and truncated to `Int`.

AO3 rating is inferred only when a subject exactly matches one of:

- `General Audiences`
- `Teen And Up Audiences`
- `Mature`
- `Explicit`
- `Not Rated`

All other subjects become initial work tags after removing the selected rating.
The AO3 work-page refresh may later replace or enrich language and tag metadata.

`WorkImporter.importEPUB` currently uses the legacy `EPUBMetadata`/`OPFParser` rules
above on **both** iOS and macOS at import time. A `ReadiumMetadataMapper`
(`Features/ReaderReadium/ReadiumMetadataMapper.swift`) exists that maps a Readium
`Publication`'s richer metadata (joined multi-author, calibre series/index, same
exact AO3-rating subject matching) onto the shared `ImportedWorkMetadata` shape,
but nothing currently calls it — it is unused dead code today, not exercised by
either the import path or the Readium reader itself. Wiring it into import is
tracked as follow-up work, not shipped behavior.

## Import and failure behavior

Metadata extraction is best effort. If it fails, `importEPUB` still moves the
file into permanent storage and creates a Library record using the filename as
the title. This allows a readable publication with unusual metadata to import,
but it also means final structural validation occurs when the reader opens it.

Moving the file into permanent storage is the import operation that throws.
Most model-save and AO3 metadata-refresh failures are nonfatal.

The legacy reader reports these typed errors:

| Error | Meaning |
|---|---|
| `unreadableFile` | The source file could not be read. |
| `notAnEPUB` | No usable ZIP central directory was found. |
| `missingContainer` | The container is absent or has no usable rootfile path. |
| `missingPackage` | The referenced OPF cannot be read. |
| `malformedPackage` | Foundation could not parse the OPF XML. |
| `noReadableContent` | No spine entries resolved through the manifest. |
| `extractionFailed` | Extracted files could not be written to the cache. |

Readium surfaces its own parser/opening errors on iOS. Protected publications
are opened with `allowUserInteraction: false`, so the app never prompts for DRM
credentials.

## Tests and change checklist

`KudosTests/Fixtures/sample.epub` is a minimal EPUB 2 fixture covering stored and
DEFLATE ZIP access, OPF metadata, calibre series fields, AO3 rating extraction,
spine order, and NCX chapter mapping. Existing tests also cover non-ZIP and
missing-file errors.

When changing EPUB handling:

1. Add a focused fixture for each newly supported structure or regression.
2. Test metadata-only parsing and full extraction/opening separately.
3. Include EPUB 2 NCX and EPUB 3 nav cases when changing TOC logic.
4. Check nested resource paths, duplicate basenames, percent-encoded hrefs, and
   malformed/missing manifest references.
5. Verify on **macOS** for legacy parser/reader changes.
6. Verify on **iOS** for Readium metadata or navigator changes.
7. Do not silently broaden trusted-input assumptions; add path containment,
   compression validation, and active-content policy first.
