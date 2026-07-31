# Replacing the hand-rolled PDF layout analysis with MuPDF

**Status:** feasibility proven and output verified (2026-07-30). The library is not yet
wired into the app — see "Remaining work".

---

## Why

`PDFPage.string` and `PDFPage.characterBounds` are a **text** API, not a **layout**
API. They do not guarantee reading order, and the glyph boxes are frequently
degenerate. Reconstructing paragraphs from them produced five separate defects in one
day, each found only by a real file:

| # | Defect | Cause |
|---|---|---|
| 1 | Every line became its own paragraph | `page.string` inserts newlines at text *run* boundaries, not line ends |
| 2 | Last letter of every word eaten | `characterBounds` reports zero height for spaces **and** many ordinary letters |
| 3 | Paragraph breaks flipped between fixtures | a threshold derived from glyph ink height lands within a point of normal line spacing |
| 4 | Paragraphs split mid-sentence | a trailing glyph reported `maxX` *below* its own `minX`, collapsing the page measure to 39pt from ~370pt |
| 5 | Prose silently relocated | runs returned **out of reading order**, then merged by baseline into unrelated lines |

Defect 5 is the one that settles it: the converter moved a clause into the wrong
paragraph, and the text looked deleted. Silent relocation of prose is the worst
failure mode a preservation app can have.

## The evidence

`mutool draw -F stext` on page 14 of the owner's calibre-exported PDF — the page that
produced defect 5 — returns:

```
block[3]  "Ye been takin' good care of it." He commented Anna nodded though it wasn't
          a question. He gave a curt nod. "Good, ya know the nice thing about weapons is…"
block[4]  "They never betray you." She finished with him. He laughed again and Anna grinned.
```

Correct reading order, the clause intact, and the paragraph boundary in the right
place. The hand-rolled path produced, from the same page:

```
block[8]   …He gave a curt nod. know the nice thing about weapons is…   ← wrong paragraph
block[10]  ""Good, ya"They never betray you." She finished with him…    ← two lines glued
```

MuPDF gives blocks → lines → spans, each with a bbox — exactly the structure the
converter's heuristics were trying to rebuild.

## What calibre does, and why we are not copying it

Reasonable question, since calibre's conversion quality is the benchmark. calibre's PDF
Input plugin runs **poppler's `pdftohtml`** over each page and builds an EPUB from the
resulting HTML, then applies a large body of Python heuristics on top.

Two things follow:

1. **calibre's reputation is not earned on PDF.** Its strength is
   reflowable→reflowable — EPUB, MOBI/AZW3, DOCX, HTML — handled by its own OEB
   pipeline. PDF is the input its own documentation warns about, and the one users
   complain about, for exactly the reason this document exists: a PDF records glyph
   positions, not paragraphs.
2. **`pdftohtml` would not help us.** It emits absolutely-positioned HTML, which still
   has to be turned back into paragraphs by the same class of heuristics that produced
   all five defects above. MuPDF's `stext` hands over paragraph **blocks** directly, so
   it removes the guesswork rather than relocating it.

So MuPDF is the better choice *for this specific job* than the tool the best-known
converter uses — not despite calibre's approach but because of what that approach has
to work around.

One genuinely useful consequence, if the AGPL terms turn out to be unacceptable:
**poppler is GPL-2/3**, so it is licence-compatible without AGPL's source-offer
obligation. It is the fallback that keeps a real layout engine in the picture, at the
cost of doing more paragraph reconstruction ourselves than MuPDF requires.

Worth noting for the rest of the series: where calibre *is* famously good, we already
chose library-first paths — mammoth.js (BSD-2) for DOCX and libmobi (LGPL-3) for
Kindle formats, both in T-153/T-154. And FanFicFare, which is what fanfic readers
actually rely on, never goes through PDF at all: it scrapes the site's HTML and writes
EPUB directly, which is why its output is clean and why its EPUBs already import here
without conversion.

## Building it

`Scripts/build-mupdf.sh` produces `MuPDF.xcframework` with three slices (iOS device,
iOS simulator, macOS). Verified working: MuPDF cross-compiles for iOS on the first
attempt with `make libs` and an SDK-pointed `CC`; no patches to MuPDF were needed.

Two findings worth keeping, both encoded in the script:

- **Each slice needs a pristine tree.** Building into different `OUT` directories is
  not enough: a HarfBuzz object (`VARC.o`) kept its `MACOS` platform tag inside the
  simulator's `libmupdf-third.a`, because some third-party objects are written outside
  `OUT`. `xcodebuild -create-xcframework` then fails with "binaries with multiple
  platforms are not supported". `git clean -xfd` between slices fixes it.
- **The two archives must be merged per slice** (`libtool -static`), since
  `-create-xcframework` accepts one library per platform.

Sizes: ~64 MB per merged slice, ~190 MB for the xcframework. **Do not commit it** —
build locally or attach it to a release.

## Licence obligations — an owner decision, not a technical one

MuPDF is **AGPL-3.0**. GPL-3 §13 explicitly permits combining GPL-3 and AGPL-3 work,
so this is legal for Kudos (GPL-3.0), but consequences follow:

1. The combined work carries **AGPL** terms, including the obligation to offer
   complete corresponding source. For a local iOS app the network-use clause is moot,
   but the source offer is not.
2. `README.md` and `LICENSE` should say so, since the effective licence of the
   distributed binary changes.
3. `Scripts/check-invariants.sh` rule 9 requires every dependency to have an entry in
   `kudos-ao3-reader/Legal/ThirdPartyNotices.txt`. MuPDF's notice **and** the full
   AGPL-3 text must be added there, or the invariant gate fails — by design.
4. Artifex sells a commercial licence for anyone who cannot accept AGPL. Not relevant
   to a personal GPL-3 app, but worth knowing before this ships anywhere.

If AGPL is unacceptable, the fallback is *not* PDFium — it exposes per-character
positions like PDFKit and would leave every defect above in place. The honest
alternative is to keep PDF conversion best-effort and lean on the archived original
plus the reader's "Original File" viewer.

## Remaining work

1. Add the xcframework to the project (local SPM binary target, or a direct
   `.xcframework` reference) with a module map exposing `mupdf/fitz.h` to Swift.
2. Write `MuPDFStructuredText` — open the document, walk `fz_stext_page`'s blocks and
   lines, return `[[String]]` per page in the shape `PDFWorkConverter` already
   consumes. That keeps the swap surgical: `pageBlocks(of:)` gains a MuPDF path and
   the rest of the converter is untouched.
3. Delete `visualLines`, `runsSharingABaseline`, `blocks(from:)` and `reflowed` once
   the MuPDF path is proven — roughly 250 lines of heuristics, and the source of all
   five defects.
4. Keep PDFKit for `documentAttributes` (title/author/keywords) unless MuPDF's
   metadata proves better; there is no reason to change two things at once.
5. Bump `ImportedDocumentConverter.converterVersion` to 7. Every already-imported PDF
   then offers **Rebuild from Original**, so existing works get the better conversion
   without a re-import — which is the whole point of having versioned the converter.
6. Add the licence entries in point 3 of the previous section *before* the gate is
   expected to pass.
