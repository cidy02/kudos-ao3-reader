#!/usr/bin/env python3
"""Fandom display-name audit: a database of every AO3 fandom tag, the split the
app produces for it, and what the review agents decided about the ambiguous ones.

Why this exists
---------------
`FandomDisplayName.split` demotes the text after a spaced dash to grey. That is
right for "Harry Potter - J. K. Rowling" and wrong for "InuYasha - A Feudal Fairy
Tale". No syntactic rule separates the two — it needs knowledge of the work, and
three attempts at a general rule were measured and rejected (see
discussions/fandom-name-disambiguation.md).

So the ambiguous names are classified offline by several AI agents, which CAN
search the web, and the confirmed "this is really part of the title" cases ship
as a static exception list. Nothing here runs in the app and nothing here talks
to AO3 — the input is the app's own catalog cache.

The app has two users, so waiting for bug reports will not surface these before
release. This finds them first.

Usage
-----
  audit.py build   <catalog.json>       load/refresh the catalog into the db
  audit.py batch   [--size N] [--from-rank R]  emit the next unclassified batch
  audit.py ingest  <agent> <file>       record one agent's verdicts for a batch
  audit.py status                       coverage, agreement, what is left
  audit.py export  <out.swift>          write the agreed exception list
  audit.py save    [file]               dump verdicts to TSV (this is what git keeps)
  audit.py load    [file]               restore verdicts from that TSV

The sqlite file is ~20 MB and rebuildable from the catalog cache, so it is
gitignored. The verdicts are not rebuildable — they cost real agent time — so
they live in verdicts.tsv, which is committed. After a fresh `build`, run `load`.
"""

import argparse
import json
import os
import re
import sqlite3
import sys

DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fandom-audit.sqlite")

SEPARATORS = [" - ", " – ", " — ", " ‐ "]

# Tails the parser is already certain about — no agent time is spent on these.
SETTLED_TAIL = re.compile(r"^(All Media Types|Fandom|Ambiguous Fandom|RPF|Works)$", re.I)
SETTLED_MEDIUM = re.compile(
    r"\((Song|TV|Anime|Manga|Movies?|Band|Video Games?|Webcomic|Musician|Music Video"
    r"|Album|Comics|Webnovel|Visual Novel|Cartoon|Podcast|Radio|Play|Musical|Film"
    r"|Novel|Book|Manhwa|Manhua|Light Novel|Web Series|Roleplaying Game|\d{4})\)$",
    re.I,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS fandom (
    name          TEXT PRIMARY KEY,   -- the raw AO3 tag; the identity, never derived from
    primary_name  TEXT NOT NULL,      -- last '|' segment, what the row actually parses
    head          TEXT NOT NULL,      -- text before the last spaced dash
    tail          TEXT NOT NULL,      -- text after it: the thing being judged
    work_count    INTEGER NOT NULL DEFAULT 0,
    categories    TEXT NOT NULL DEFAULT '',
    ambiguous     INTEGER NOT NULL DEFAULT 0  -- 1 = needs a human/agent call
);
CREATE INDEX IF NOT EXISTS fandom_rank ON fandom (ambiguous, work_count DESC);

CREATE TABLE IF NOT EXISTS verdict (
    name     TEXT NOT NULL,
    agent    TEXT NOT NULL,
    decision TEXT NOT NULL CHECK (decision IN ('DEMOTE', 'KEEP', 'UNSURE')),
    reason   TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (name, agent)
);

CREATE TABLE IF NOT EXISTS batch (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    created TEXT NOT NULL DEFAULT (datetime('now')),
    note    TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS batch_item (
    batch_id INTEGER NOT NULL,
    ordinal  INTEGER NOT NULL,
    name     TEXT NOT NULL,
    PRIMARY KEY (batch_id, ordinal)
);
"""


def connect():
    db = sqlite3.connect(DB)
    db.executescript(SCHEMA)
    return db


def primary_of(name):
    parts = [p.strip() for p in name.split("|") if p.strip()]
    return parts[-1] if parts else name.strip()


def split_tail(primary):
    """Where the last spaced dash falls, or None if there is none."""
    best = max(((primary.rfind(s), s) for s in SEPARATORS), key=lambda x: x[0])
    index, sep = best
    if index <= 0:
        return None
    head, tail = primary[:index].strip(), primary[index + len(sep):].strip()
    return (head, tail) if head and tail else None


def is_ambiguous(tail):
    """True when the parser cannot know whether this tail is a suffix or a title."""
    return not (SETTLED_TAIL.match(tail) or SETTLED_MEDIUM.search(tail))


def cmd_build(args):
    with open(args.catalog, encoding="utf-8") as handle:
        catalog = json.load(handle)

    rows, cats = {}, {}
    for category, value in catalog.items():
        for fandom in value.get("fandoms", []):
            name = fandom.get("name")
            if not name:
                continue
            rows[name] = max(rows.get(name, 0), fandom.get("workCount") or 0)
            cats.setdefault(name, set()).add(category)

    db = connect()
    added = ambiguous = 0
    for name, works in rows.items():
        primary = primary_of(name)
        pieces = split_tail(primary)
        head, tail = pieces if pieces else ("", "")
        amb = 1 if pieces and is_ambiguous(tail) else 0
        ambiguous += amb
        db.execute(
            "INSERT INTO fandom (name, primary_name, head, tail, work_count, categories, ambiguous) "
            "VALUES (?,?,?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET "
            "primary_name=excluded.primary_name, head=excluded.head, tail=excluded.tail, "
            "work_count=max(fandom.work_count, excluded.work_count), "
            "categories=excluded.categories, ambiguous=excluded.ambiguous",
            (name, primary, head, tail, works, ",".join(sorted(cats[name])), amb),
        )
        added += 1
    db.commit()
    print(f"catalog: {added} unique tags   ambiguous (need a call): {ambiguous}")


def cmd_batch(args):
    db = connect()
    # Highest exposure first: a fandom with 300k works is seen constantly, one
    # with 1 work may never be scrolled to. Coverage is measured in works, not rows.
    rows = db.execute(
        "SELECT f.name FROM fandom f "
        "WHERE f.ambiguous = 1 "
        "  AND NOT EXISTS (SELECT 1 FROM verdict v WHERE v.name = f.name) "
        "ORDER BY f.work_count DESC LIMIT ? OFFSET ?",
        (args.size, args.from_rank),
    ).fetchall()
    if not rows:
        print("nothing left to classify", file=sys.stderr)
        return
    cur = db.execute("INSERT INTO batch (note) VALUES (?)", (args.note,))
    batch_id = cur.lastrowid
    for i, (name,) in enumerate(rows, 1):
        db.execute("INSERT INTO batch_item (batch_id, ordinal, name) VALUES (?,?,?)",
                   (batch_id, i, name))
        print(f"{i}\t{name}")
    db.commit()
    print(f"# batch {batch_id}: {len(rows)} names", file=sys.stderr)


def cmd_ingest(args):
    db = connect()
    batch_id = args.batch or db.execute("SELECT max(id) FROM batch").fetchone()[0]
    order = dict(db.execute(
        "SELECT ordinal, name FROM batch_item WHERE batch_id = ?", (batch_id,)).fetchall())

    line_re = re.compile(r"^\s*(\d+)[\s|]+\**(DEMOTE|KEEP|UNSURE)\**[\s|]*(.*)$")
    kept = skipped = 0
    with open(args.file, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = line_re.match(line.strip())
            if not match:
                continue
            ordinal, decision, reason = int(match.group(1)), match.group(2), match.group(3)
            name = order.get(ordinal)
            if not name:
                skipped += 1
                continue
            db.execute(
                "INSERT INTO verdict (name, agent, decision, reason) VALUES (?,?,?,?) "
                "ON CONFLICT(name, agent) DO UPDATE SET decision=excluded.decision, "
                "reason=excluded.reason",
                (name, args.agent, decision, reason.strip()[:120]))
            kept += 1
    db.commit()
    print(f"{args.agent}: {kept} verdicts into batch {batch_id}"
          + (f" ({skipped} unmatched)" if skipped else ""))


def consensus(db):
    """Names where every agent that voted agrees, and the ones they split on."""
    rows = db.execute(
        "SELECT name, group_concat(decision) FROM verdict GROUP BY name").fetchall()
    agreed, split = {}, {}
    for name, decisions in rows:
        values = set(decisions.split(","))
        if len(values) == 1:
            agreed[name] = values.pop()
        else:
            split[name] = sorted(values)
    return agreed, split


def cmd_status(args):
    db = connect()
    total, amb = db.execute(
        "SELECT count(*), sum(ambiguous) FROM fandom").fetchone()
    voted = db.execute("SELECT count(DISTINCT name) FROM verdict").fetchone()[0]
    agreed, split = consensus(db)
    keeps = sorted((n for n, d in agreed.items() if d == "KEEP"))
    works_amb, works_done = db.execute(
        "SELECT sum(work_count), sum(CASE WHEN EXISTS "
        "(SELECT 1 FROM verdict v WHERE v.name=f.name) THEN work_count ELSE 0 END) "
        "FROM fandom f WHERE ambiguous = 1").fetchone()

    print(f"tags in catalog          {total}")
    print(f"ambiguous (need a call)  {amb}")
    print(f"classified               {voted}")
    if works_amb:
        print(f"exposure covered         {100 * (works_done or 0) / works_amb:.1f}% of works behind ambiguous tags")
    print(f"  unanimous              {len(agreed)}")
    print(f"  split (human queue)    {len(split)}")
    print(f"  agreed KEEP            {len(keeps)}   <-- these become exceptions")
    for name in keeps[:20]:
        print(f"      {name}")
    if split:
        print("\nsplit decisions:")
        for name, values in list(split.items())[:20]:
            print(f"      {name}   {'/'.join(values)}")


VERDICTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verdicts.tsv")


def cmd_save(args):
    db = connect()
    rows = db.execute(
        "SELECT name, agent, decision, reason FROM verdict ORDER BY name, agent").fetchall()
    path = args.file or VERDICTS
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("name\tagent\tdecision\treason\n")
        for row in rows:
            handle.write("\t".join(str(c).replace("\t", " ") for c in row) + "\n")
    print(f"saved {len(rows)} verdicts to {path}")


def cmd_load(args):
    db = connect()
    path = args.file or VERDICTS
    if not os.path.exists(path):
        print(f"no verdict file at {path}", file=sys.stderr)
        return
    count = 0
    with open(path, encoding="utf-8") as handle:
        next(handle, None)
        for line in handle:
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 3:
                continue
            db.execute(
                "INSERT INTO verdict (name, agent, decision, reason) VALUES (?,?,?,?) "
                "ON CONFLICT(name, agent) DO UPDATE SET decision=excluded.decision, "
                "reason=excluded.reason",
                (cols[0], cols[1], cols[2], cols[3] if len(cols) > 3 else ""))
            count += 1
    db.commit()
    print(f"loaded {count} verdicts from {path}")


def cmd_export(args):
    db = connect()
    agreed, _ = consensus(db)
    keep_names = {n for n, d in agreed.items() if d == "KEEP"}
    # Key on primary_name, NOT the raw tag. `split` is handed the last '|'
    # segment, so an exception stored as the full multilingual tag would never
    # match — 11 of the first 28 differ, and the list would have silently done
    # nothing for those while looking correct.
    keeps = sorted({
        row[0] for row in db.execute("SELECT primary_name FROM fandom WHERE name IN (%s)"
                                     % ",".join("?" * len(keep_names)), tuple(keep_names))
    }) if keep_names else []
    lines = [
        "// Generated by Scripts/fandom-audit/audit.py — do not hand-edit.",
        "//",
        "// Fandom tags whose text after the dash is part of the real title, not a",
        "// disambiguator. No syntactic rule can tell the two apart (see",
        "// discussions/fandom-name-disambiguation.md), so these were classified",
        "// offline by several AI agents with web search and are shipped as data.",
        "//",
        f"// {len(keeps)} entries, matched against the name `split` actually receives:",
        "// the last '|' segment of the tag, not the whole multilingual tag.",
        "",
        "enum FandomDisplayExceptions {",
        "    /// Tags to render whole, with no part of the name demoted.",
        "    static let keepWhole: Set<String> = [",
    ]
    for name in keeps:
        lines.append(f'        {json.dumps(name, ensure_ascii=False)},')
    lines += ["    ]", "}", ""]
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {len(keeps)} exceptions to {args.out}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("build"); p.add_argument("catalog"); p.set_defaults(fn=cmd_build)
    p = sub.add_parser("batch")
    p.add_argument("--size", type=int, default=50)
    p.add_argument("--from-rank", type=int, default=0)
    p.add_argument("--note", default="")
    p.set_defaults(fn=cmd_batch)
    p = sub.add_parser("ingest")
    p.add_argument("agent"); p.add_argument("file"); p.add_argument("--batch", type=int)
    p.set_defaults(fn=cmd_ingest)
    p = sub.add_parser("status"); p.set_defaults(fn=cmd_status)
    p = sub.add_parser("export"); p.add_argument("out"); p.set_defaults(fn=cmd_export)
    p = sub.add_parser("save"); p.add_argument("file", nargs="?"); p.set_defaults(fn=cmd_save)
    p = sub.add_parser("load"); p.add_argument("file", nargs="?"); p.set_defaults(fn=cmd_load)

    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
