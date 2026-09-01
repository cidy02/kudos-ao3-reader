#!/usr/bin/env python3
"""Generate the set of RPF umbrella heads whose "RPF" must stay attached.

The display parser strips a trailing "RPF": "Harry Potter RPF" renders as bold
"Harry Potter" with a grey "RPF", which is right — RPF modifies a fandom that
exists on its own. But for umbrella tags whose canonical AO3 name *is*
"<category> RPF", the same strip leaves a meaningless bold stub: "Sports RPF"
became bold "Sports", "Video Blogging RPF" became bold "Video Blogging".
1,477 tags, 1.46M works.

The separating fact is whether the head names a real fandom or only a category,
and that is decided by the corpus rather than by hand:

    strip RPF only if the head is the bold title of non-RPF tags
    totalling more than THRESHOLD works.

"Supernatural" carries 275,355 works of its own, so stripping is safe. "Sports"
carries zero — nobody writes for "Sports", they write for "Sports RPF". Two
leaks have to be closed first or the vocabulary poisons itself: tags containing
"RPF" anywhere (not merely at the end) must be excluded, because otherwise
"Political RPF - US 21st c." contributes "Political" to the vocabulary and
licenses stripping the very tag it came from.

Shipped rather than computed at runtime because FandomCatalog is a cache: it is
empty on first launch and can be cleared, and a tag must not render two ways
depending on cache state.

    python3 gen-rpf-umbrellas.py [--threshold 100] > FandomRPFUmbrellas.swift
"""

import argparse
import collections
import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DB = ROOT / "Scripts/fandom-audit/fandom-audit.sqlite"
EXCEPTIONS = ROOT / "kudos-ao3-reader/Features/Search/FandomDisplayExceptions.swift"

CLOSING = {")", "）"}
SEPARATORS = [" - ", " – ", " — ", " ‐ "]
DASHES = {"-", "–", "—", "‐"}
UMBRELLAS = ["All Media Types", "所有媒体类型", "所有媒體類型", "所有媒體型別",
             "Todos os Tipos de Mídia", "Todos los tipos de medios"]
RELATED = [" & Related Fandoms", " and Related Fandoms"]
DEBRIS = " -–—‐:"
HAS_RPF = re.compile(r"\brpf\b", re.I)


def tidied(text):
    out = text.strip()
    while out and out[-1] in DEBRIS:
        out = out[:-1]
    return out.strip()


def _suffix(text, needles, prefix=""):
    low = text.lower()
    for needle in needles:
        i = low.rfind(needle.lower())
        if i != -1 and i + len(needle) == len(text):
            tail = text[i:]
            return tidied(text[:i]), (prefix + tail).strip() if prefix else tail.strip()
    return None


def take_bracket(text):
    if not text or text[-1] not in CLOSING:
        return None
    open_at = max(text.rfind("("), text.rfind("（"))
    if open_at == -1:
        return None
    return tidied(text[:open_at]), text[open_at:]


def take_separator(text):
    best, sep = -1, None
    for candidate in SEPARATORS:
        i = text.rfind(candidate)
        if i > best:
            best, sep = i, candidate
    if best == -1:
        return None
    tail = text[best + len(sep):].strip()
    if not tail:
        return None
    return tidied(text[:best]), "- " + tail


def take_glued(text):
    i = text.lower().rfind("fandom")
    if i == -1 or i + 6 != len(text):
        return None
    before = text[:i].strip()
    if not before or before[-1] not in DASHES:
        return None
    return tidied(before), "- " + text[i:]


RULES = [
    ("relatedFandoms", lambda t: _suffix(t, RELATED)),
    ("rpf", lambda t: _suffix(t, ["RPF"])),
    ("mediaUmbrella", lambda t: _suffix(t, UMBRELLAS, "- ")),
    ("bracket", take_bracket),
    ("separator", take_separator),
    ("gluedFandom", take_glued),
]


def split(name, keep_whole):
    """Mirror of FandomDisplayName.split, for offline analysis only.

    Also reports the head the RPF rule saw. That is not always the final title:
    takeRPF fires before takeBracket gets its turn, so "Super Sketch Show (TV)
    RPF" reaches the rule as "Super Sketch Show (TV)" and only later becomes
    "Super Sketch Show". The shipped set has to be keyed on what the rule
    actually tests, or the lookup misses and the tag strips anyway.
    """
    title = name.strip()
    if not title:
        return name, set(), None
    rules = [r for r in RULES if not (r[0] == "separator" and title in keep_whole)]
    taken, rpf_head = set(), None
    for _ in range(len(rules)):
        before = title
        for rule_name, cut in rules:
            if rule_name in taken:
                continue
            peel = cut(title)
            if not peel or not peel[0]:
                continue
            if rule_name == "rpf":
                rpf_head = peel[0]
            title = peel[0]
            taken.add(rule_name)
        if title == before:
            break
    return title, taken, rpf_head


def swift_quote(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=int, default=100,
                    help="minimum non-RPF works for a head to count as a real fandom")
    args = ap.parse_args()

    keep_whole = set()
    if EXCEPTIONS.exists():
        keep_whole = {
            s.replace('\\"', '"').replace("\\\\", "\\")
            for s in re.findall(r'^\s*"((?:[^"\\]|\\.)*)",\s*$', EXCEPTIONS.read_text(), re.M)
        }

    db = sqlite3.connect(DB)
    rows = db.execute("SELECT primary_name, work_count FROM fandom").fetchall()

    vocabulary = collections.Counter()
    for name, works in rows:
        if HAS_RPF.search(name):
            continue
        title, _, _ = split(name, keep_whole)
        if title:
            vocabulary[title] += works

    # Judge on the final title — that is the string the reader would be left
    # looking at — but key the set on the head the rule tests.
    #
    # A head still carrying its bracket is a work, not a category: AO3 only adds
    # "(TV)", "(2002)", "(Podcast)" to disambiguate an actual title, and no
    # category tag has one. Without this the work-count proxy misfires on shows
    # whose fandom is ENTIRELY RPF — "RuPaul's Drag Race" has no non-RPF works
    # because drag queens are real people, and "8 Mile (2002)" would have gone
    # bold in full. The proxy answers "does this head have works of its own",
    # which is not the same question as "is this head a real title".
    heads, tags, bracketed = set(), 0, 0
    for name, works in rows:
        title, taken, rpf_head = split(name, keep_whole)
        if "rpf" not in taken or not rpf_head:
            continue
        if vocabulary.get(title, 0) > args.threshold:
            continue
        if rpf_head.endswith(")") or rpf_head.endswith("）"):
            bracketed += 1
            continue
        heads.add(rpf_head)
        tags += 1
    print(f"excluded {bracketed} bracket-carrying heads as real works", file=sys.stderr)

    print(f"generated from {len(rows)} tags, threshold {args.threshold}: "
          f"{len(heads)} heads across {tags} tags", file=sys.stderr)

    out = [
        "// Generated by Scripts/fandom-audit/gen-rpf-umbrellas.py — do not edit by hand.",
        "//",
        "// Heads whose trailing \"RPF\" is part of the fandom's own name rather than a",
        "// suffix on a fandom that exists without it. \"Sports RPF\" is the canonical tag;",
        "// nobody writes for a fandom called \"Sports\", so stripping the RPF left a bold",
        "// \"Sports\" that named nothing. \"Harry Potter RPF\" is the opposite: Harry Potter",
        "// is a fandom in its own right, so the RPF is a genuine qualifier.",
        "//",
        "// Membership is decided by the corpus, not by hand: a head qualifies as a real",
        f"// fandom only if non-RPF tags carrying that same head hold more than {args.threshold} works",
        "// between them. Regenerate whenever the catalog is refreshed.",
        "",
        "// A generated wall of string literals; the size rules are not meaningful here.",
        "// swiftlint:disable file_length type_body_length",
        "enum FandomRPFUmbrellas {",
        "    static let keepAttached: Set<String> = [",
    ]
    out += [f'        "{swift_quote(h)}",' for h in sorted(heads)]
    out += ["    ]", "}", "// swiftlint:enable file_length type_body_length"]
    print("\n".join(out))


if __name__ == "__main__":
    main()
