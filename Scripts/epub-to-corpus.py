#!/usr/bin/env python3
"""Turn an EPUB into a `tag<TAB>text` corpus for KokoroCorpusDiagnosticTests.

    Scripts/epub-to-corpus.py ~/Downloads/Some_Work.epub corpus/

Emits one `.tsv` per EPUB, blocks in spine order. Then:

    TEST_RUNNER_KOKORO_CORPUS_DIR=$PWD/corpus xcodebuild test \
      -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
      -destination 'id=<sim-udid>' \
      -only-testing:KudosTests/KokoroCorpusDiagnosticTests

The report lands at `corpus/REPORT.txt`.

**Collect works from different fandoms and authors.** Prose style varies
enormously and each style stresses a different part of the pipeline: quirk
typing, romaji and honorifics, texting/chat formats, epistolary works with
URLs, heavy ALL-CAPS emphasis, `<hr>` scene breaks. A single work characterises
its own author and nothing more — a finding that a feature "isn't a problem"
is only ever a statement about the works measured so far.

Stdlib only; no EPUB library needed. Nothing here is committed to the repo but
the script itself — corpora are third-party fiction and stay local.
"""
import html
import os
import re
import sys
import zipfile

BLOCK_RE = re.compile(
    r"<(p|h[1-6]|blockquote|hr)\b[^>]*(?:/>|>(.*?)</\1>)", re.S | re.I
)


def spine_documents(zf):
    """Content documents in reading order, per the OPF spine."""
    opf_name = next(
        (n for n in zf.namelist() if n.endswith(".opf")), None
    )
    if not opf_name:
        return [n for n in zf.namelist() if n.endswith((".xhtml", ".html"))]
    opf = zf.read(opf_name).decode("utf-8", "replace")
    base = os.path.dirname(opf_name)
    ids = dict(
        re.findall(r'<item[^>]*id="([^"]+)"[^>]*href="([^"]+)"', opf)
    ) | dict(
        (i, h) for h, i in re.findall(
            r'<item[^>]*href="([^"]+)"[^>]*id="([^"]+)"', opf
        )
    )
    order = re.findall(r'<itemref[^>]*idref="([^"]+)"', opf)
    out = []
    for ref in order:
        href = ids.get(ref)
        if not href or not href.endswith((".xhtml", ".html")):
            continue
        path = os.path.normpath(os.path.join(base, html.unescape(href)))
        if path in zf.namelist():
            out.append(path)
    return out


def blocks(zf, name):
    raw = zf.read(name).decode("utf-8", "replace")
    body = re.search(r"<body[^>]*>(.*)</body>", raw, re.S | re.I)
    if not body:
        return
    for m in BLOCK_RE.finditer(body.group(1)):
        tag = m.group(1).lower()
        inner = m.group(2) or ""
        # Keep it dumb: strip tags, unescape, collapse whitespace. Readium's
        # own extraction differs in detail, which is fine — this measures the
        # packer, not the EPUB reader.
        text = html.unescape(re.sub(r"<[^>]+>", "", inner))
        text = " ".join(text.split())
        if tag == "hr":
            yield tag, "***"
        elif text:
            yield tag, text


def convert(epub_path, out_dir):
    stem = os.path.splitext(os.path.basename(epub_path))[0]
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-").lower()
    out_path = os.path.join(out_dir, f"{stem}.tsv")
    count = 0
    with zipfile.ZipFile(epub_path) as zf, open(
        out_path, "w", encoding="utf-8"
    ) as out:
        for name in spine_documents(zf):
            for tag, text in blocks(zf, name):
                out.write(f"{tag}\t{text}\n")
                count += 1
    print(f"{out_path}: {count} blocks")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    *epubs, out_dir = argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    for path in epubs:
        convert(path, out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
