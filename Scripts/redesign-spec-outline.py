#!/usr/bin/env python3
"""Read the redesign design canvas without opening 2 MB of inline-styled HTML.

    Scripts/redesign-spec-outline.py --list
    Scripts/redesign-spec-outline.py --board 1k
    Scripts/redesign-spec-outline.py --board 1k --screen 1
    Scripts/redesign-spec-outline.py --notes

The canvas (docs/design/Final_Redesign_Spec.dc.html) is the owner-supplied
source of truth for the redesign. It is unreadable as source and far too large
to page through, so this flattens one artboard into a tree of tags, their
layout-relevant CSS, and their text. Every measured token in
docs/REDESIGN_PLAN.md was read off it this way.

Prefer this over eyeballing the rendered canvas: the numbers you need are in
the inline styles, not in the pixels. A `font: 700 9px/1.2 …; letter-spacing:
.11em` in the output is the exact type spec for that element.

Artboard ids are the canvas's own, `1a` through `1ci`. An artboard can hold
several screens (`--board 1h` has four); `--screen N` picks one, zero-indexed.
`--notes` prints every artboard's prose label and its "Needs building" note,
which is where the spec says what AO3 does and does not allow.
"""

import argparse
import html
import os
import re
import sys
from html.parser import HTMLParser

DEFAULT_CANVAS = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    os.pardir,
    "docs",
    "design",
    "Final_Redesign_Spec.dc.html",
)

# Only the properties that carry design intent. Dropping the rest is what makes
# the output readable — a full style dump is barely smaller than the source.
LAYOUT_PROPERTIES = re.compile(
    r"\b(font|color|background|background-color|border|border-radius|padding|margin"
    r"|gap|width|height|letter-spacing|text-transform|opacity|flex|align-items"
    r"|justify-content|flex-direction|position|inset|top|left|right|bottom|stroke"
    r"|fill|backdrop-filter|box-shadow|grid-template-columns)\b"
)

RENDERED_TAGS = {
    "div", "span", "svg", "path", "circle", "rect", "input", "textarea",
    "button", "p", "a",
}


def strip_markup(fragment):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


class ArtboardOutliner(HTMLParser):
    """Flattens one artboard into `<tag layout-css>` / `· text` lines."""

    def __init__(self):
        super().__init__()
        self.depth = 0
        self.lines = []

    def handle_starttag(self, tag, attributes):
        if tag not in RENDERED_TAGS:
            return
        attribute_map = dict(attributes)
        declarations = [
            declaration.strip()
            for declaration in attribute_map.get("style", "").split(";")
            if declaration.strip() and LAYOUT_PROPERTIES.search(declaration.split(":")[0])
        ]
        screen_label = attribute_map.get("data-screen-label")
        label_suffix = f" label={screen_label}" if screen_label else ""
        self.lines.append(
            "  " * self.depth + f"<{tag}{label_suffix} " + "; ".join(declarations) + ">"
        )
        self.depth += 1

    def handle_endtag(self, tag):
        if tag in RENDERED_TAGS:
            self.depth = max(0, self.depth - 1)

    def handle_data(self, data):
        text = data.strip()
        if text:
            self.lines.append("  " * self.depth + "· " + html.unescape(text))


def read_canvas(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        sys.exit(
            f"redesign-spec-outline: no canvas at {path}\n"
            "                       Pass one with --canvas, or restore "
            "docs/design/Final_Redesign_Spec.dc.html."
        )


def artboard_blocks(source):
    """Yield (artboard_id, start_offset, block_html) in the canvas's own order."""
    starts = [match.start() for match in re.finditer(r'<div class="dv-opt"', source)]
    bounds = starts + [len(source)]
    for index, start in enumerate(starts):
        block = source[start:bounds[index + 1]]
        identifier = re.search(r'id="([^"]+)"', block)
        if identifier:
            yield identifier.group(1), start, block


def turn_titles(source):
    """Position → turn name, so --list can say which turn an artboard came from."""
    return {
        match.start(): strip_markup(match.group(1))
        for match in re.finditer(r'class="dv-tname">(.*?)</div>', source, re.S)
    }


def screen_fragments(block):
    """Yield (screen_label, fragment_html) for each device frame in an artboard."""
    for match in re.finditer(r'<div data-screen-label="([^"]*)"', block):
        start = match.start()
        depth = 0
        end = len(block)
        for token in re.finditer(r"<div\b|</div>", block[start:]):
            depth += -1 if token.group(0) == "</div>" else 1
            if depth == 0:
                end = start + token.end()
                break
        yield match.group(1), block[start:end]


def command_list(source):
    turns = turn_titles(source)
    for identifier, start_offset, block in artboard_blocks(source):
        enclosing = [name for offset, name in sorted(turns.items()) if offset < start_offset]
        labels = [label for label, _ in screen_fragments(block)] or ["(no framed screen)"]
        print(f"{identifier:<5} {' | '.join(labels)}")
        if enclosing:
            print(f"      turn: {enclosing[-1]}")


def command_notes(source):
    for identifier, _start_offset, block in artboard_blocks(source):
        label = re.search(r'<div class="dv-olabel"[^>]*>(.*?)</div>', block, re.S)
        build = re.search(r'<div class="dv-build">(.*?)</div>', block, re.S)
        print(f"\n## {identifier}")
        if label:
            print("LABEL:", strip_markup(label.group(1)))
        if build:
            print("BUILD:", strip_markup(build.group(1)))


def command_board(source, wanted_id, wanted_screen):
    for identifier, _start_offset, block in artboard_blocks(source):
        if identifier != wanted_id:
            continue
        fragments = list(screen_fragments(block))
        if not fragments:
            sys.exit(f"redesign-spec-outline: artboard {wanted_id} has no framed screen.")
        if wanted_screen is not None:
            if not 0 <= wanted_screen < len(fragments):
                sys.exit(
                    f"redesign-spec-outline: artboard {wanted_id} has "
                    f"{len(fragments)} screen(s); --screen is zero-indexed."
                )
            fragments = [fragments[wanted_screen]]
        for label, fragment in fragments:
            print(f"===== {identifier}: {label} =====")
            outliner = ArtboardOutliner()
            outliner.feed(fragment)
            print("\n".join(outliner.lines))
            print()
        return
    sys.exit(f"redesign-spec-outline: no artboard {wanted_id}. Try --list.")


def main():
    parser = argparse.ArgumentParser(
        description="Outline one artboard of the Kudos redesign canvas.",
        epilog="Artboard ids run 1a through 1ci; --list prints them all.",
    )
    parser.add_argument("--canvas", default=DEFAULT_CANVAS, help="Path to the .dc.html canvas.")
    parser.add_argument("--list", action="store_true", help="List every artboard and its screens.")
    parser.add_argument("--notes", action="store_true", help="Print every artboard's prose and build notes.")
    parser.add_argument("--board", help="Artboard id to outline, e.g. 1k.")
    parser.add_argument("--screen", type=int, help="Zero-indexed screen within the artboard.")
    arguments = parser.parse_args()

    source = read_canvas(arguments.canvas)
    if arguments.list:
        command_list(source)
    elif arguments.notes:
        command_notes(source)
    elif arguments.board:
        command_board(source, arguments.board, arguments.screen)
    else:
        parser.print_help()


if __name__ == "__main__":
    # Piping into `head` is the normal way to use this, and without restoring
    # the default SIGPIPE handler Python answers a closed pipe with a traceback
    # instead of exiting quietly.
    try:
        import signal

        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except (ImportError, AttributeError, ValueError):
        pass  # Windows has no SIGPIPE; the tracebacks there are harmless.
    main()
