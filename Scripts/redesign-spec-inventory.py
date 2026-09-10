#!/usr/bin/env python3
"""Find the redesign spec's *shared* elements, by counting how many artboards
each element shape appears in.

    Scripts/redesign-spec-inventory.py                 # the shared set, ranked
    Scripts/redesign-spec-inventory.py --min-boards 8  # only the very common
    Scripts/redesign-spec-inventory.py --signature 12  # every use of shape #12
    Scripts/redesign-spec-inventory.py --board 1a      # one artboard's shapes

Why this exists: the canvas is 87 artboards drawn from a much smaller set of
parts, and building it screen by screen means discovering those parts one at a
time, in whatever order the screens happen to need them. This reads the whole
canvas at once and ranks every element shape by how many *artboards* use it, so
the parts worth building first are the ones the spec actually repeats.

The ranking is by artboard spread, deliberately not by raw count. A chip drawn
forty times inside one screen is that screen's list; a chip drawn once each in
forty screens is the design system.

Shapes are compared after normalising away everything that varies with the
subject rather than with the component — every colour, gradient and percentage
becomes a placeholder, so the same chip in a purple artboard and a gold one is
one shape. What survives is the part worth naming in Swift: radius, padding,
type, border, gap.
"""

import argparse
import collections
import html
import os
import re
import sys
from html.parser import HTMLParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from redesign_spec_outline_support import DEFAULT_CANVAS, artboard_blocks, read_canvas

# Properties that describe the *component*. Position and flow describe where a
# use of it happens to sit, which is the screen's business, not the part's.
SHAPE_PROPERTIES = re.compile(
    r"^\s*(font|font-size|font-weight|color|background|background-color|border"
    r"|border-radius|border-top|padding|gap|width|height|letter-spacing"
    r"|text-transform|flex-direction|align-items|justify-content|backdrop-filter"
    r"|box-shadow|flex-wrap|font-variant-numeric)\s*$"
)

RENDERED_TAGS = {"div", "span", "svg", "input", "textarea", "button", "p", "a"}

COLOUR = re.compile(
    r"(#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|\b(?:white|black|currentColor)\b)"
)
GRADIENT = re.compile(r"linear-gradient\([^)]*\)")
PERCENT = re.compile(r"\b\d+(?:\.\d+)?%")


def normalise(declaration):
    """Strip everything that varies with the subject rather than the part."""
    value = GRADIENT.sub("<gradient>", declaration)
    value = COLOUR.sub("<c>", value)
    value = PERCENT.sub("<pct>", value)
    return re.sub(r"\s+", " ", value).strip()


class ShapeCollector(HTMLParser):
    """Every rendered element in one artboard, as a normalised shape signature."""

    def __init__(self):
        super().__init__()
        self.shapes = []          # (signature, tag)
        self.pending = []         # stack of indices awaiting their text
        self.texts = {}           # index -> first text seen inside it

    def handle_starttag(self, tag, attributes):
        if tag not in RENDERED_TAGS:
            return
        style = dict(attributes).get("style", "")
        declarations = sorted(
            normalise(declaration)
            for declaration in style.split(";")
            if declaration.strip() and SHAPE_PROPERTIES.match(declaration.split(":")[0])
        )
        if not declarations:
            self.pending.append(None)
            return
        self.pending.append(len(self.shapes))
        self.shapes.append(("; ".join(declarations), tag))

    def handle_endtag(self, tag):
        if tag in RENDERED_TAGS and self.pending:
            self.pending.pop()

    def handle_data(self, data):
        text = html.unescape(data).strip()
        if not text:
            return
        for index in reversed(self.pending):
            if index is not None and index not in self.texts:
                self.texts[index] = text[:40]
                return


def collect(source):
    """signature -> {boards: set, uses: int, tag: str, samples: set}."""
    table = collections.defaultdict(
        lambda: {"boards": set(), "uses": 0, "tag": "", "samples": set()}
    )
    per_board = collections.defaultdict(list)
    for board_id, _offset, block in artboard_blocks(source):
        collector = ShapeCollector()
        collector.feed(block)
        for index, (signature, tag) in enumerate(collector.shapes):
            entry = table[signature]
            entry["boards"].add(board_id)
            entry["uses"] += 1
            entry["tag"] = tag
            sample = collector.texts.get(index)
            if sample and len(entry["samples"]) < 4:
                entry["samples"].add(sample)
            per_board[board_id].append(signature)
    return table, per_board


def wrap(signature, width, indent):
    """Signatures are long; break them on the declaration separator."""
    lines, current = [], ""
    for part in signature.split("; "):
        candidate = part if not current else current + "; " + part
        if len(candidate) > width and current:
            lines.append(current)
            current = part
        else:
            current = candidate
    if current:
        lines.append(current)
    return ("\n" + " " * indent).join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--canvas", default=DEFAULT_CANVAS)
    parser.add_argument("--min-boards", type=int, default=5,
                        help="only shapes appearing in at least this many artboards")
    parser.add_argument("--limit", type=int, default=60)
    parser.add_argument("--signature", type=int,
                        help="list every artboard using the ranked shape with this number")
    parser.add_argument("--board", help="rank one artboard's own shapes by how shared they are")
    arguments = parser.parse_args()

    table, per_board = collect(read_canvas(arguments.canvas))
    ranked = sorted(
        table.items(),
        key=lambda item: (len(item[1]["boards"]), item[1]["uses"]),
        reverse=True,
    )

    if arguments.signature is not None:
        signature, entry = ranked[arguments.signature - 1]
        print(f"#{arguments.signature}  {entry['tag']}  "
              f"{len(entry['boards'])} artboards, {entry['uses']} uses")
        print("  " + wrap(signature, 96, 2))
        print("  artboards: " + " ".join(sorted(entry["boards"])))
        if entry["samples"]:
            print("  text: " + " | ".join(sorted(entry["samples"])))
        return

    if arguments.board:
        signatures = per_board.get(arguments.board)
        if not signatures:
            sys.exit(f"redesign-spec-inventory: no artboard {arguments.board}")
        rank_of = {signature: index + 1 for index, (signature, _) in enumerate(ranked)}
        seen = []
        for signature in signatures:
            if signature not in seen:
                seen.append(signature)
        print(f"{arguments.board}: {len(signatures)} elements, {len(seen)} distinct shapes\n")
        for signature in sorted(seen, key=lambda s: rank_of[s]):
            entry = table[signature]
            print(f"#{rank_of[signature]:<4} {len(entry['boards']):>3} boards  "
                  f"{wrap(signature, 88, 21)}")
        return

    total_uses = sum(entry["uses"] for entry in table.values())
    shared = [item for item in ranked if len(item[1]["boards"]) >= arguments.min_boards]
    covered = sum(entry["uses"] for _signature, entry in shared)
    print(f"{len(table)} distinct shapes across {total_uses} elements.")
    print(f"{len(shared)} of them appear in {arguments.min_boards}+ artboards "
          f"and account for {covered * 100 // total_uses}% of every element drawn.\n")

    for rank, (signature, entry) in enumerate(shared[:arguments.limit], start=1):
        samples = " | ".join(sorted(entry["samples"])[:3])
        print(f"#{rank:<3} {len(entry['boards']):>3} boards {entry['uses']:>5} uses  {entry['tag']}")
        print(f"      {wrap(signature, 92, 6)}")
        if samples:
            print(f"      text: {samples}")
        print()


if __name__ == "__main__":
    main()
