#!/usr/bin/env python3
"""Parse Swift files and report syntax errors, for environments with no Swift.

    Scripts/swift-parse-check.py kudos-ao3-reader KudosTests    # whole tree
    Scripts/swift-parse-check.py path/to/One.swift              # one file
    Scripts/swift-parse-check.py --changed                      # git's dirty + staged

This is not a compiler and cannot replace one. It reports only what a *parser*
can see — an unclosed paren, a malformed declaration, a broken string
interpolation, an edit applied at the wrong anchor. It cannot see a missing
member, a wrong argument label, or a type mismatch, which are the errors that
have actually reddened this branch.

It exists because the compile gate here is a macOS CI runner ten minutes away
(see docs/REDESIGN_PLAN.md §0). Ten minutes is the right price for a type
error and much too high for a stray brace, which is the class this catches in
about a second. Run it before every commit; it is strictly better than the
brace-counting the plan used to recommend, because it knows Swift's grammar
rather than counting characters.

Two known false positives, both gaps in tree-sitter's Swift grammar rather
than in the code: `Services/CalibreMetadataPage.swift` (a `where` clause on an
`if case let`) and `KudosTests/ReaderTimeEstimateTests.swift` (a defaulted
parameter followed by `#function`). Both compile in CI. Prefer `--changed`,
which only looks at what you actually touched, so neither is ever in the way.

Needs `pip install tree-sitter tree-sitter-language-pack`. If that is
unavailable the script says so and exits 0 rather than failing a workflow —
a missing optional check is not a broken build.
"""

import argparse
import os
import subprocess
import sys

try:
    from tree_sitter_language_pack import get_parser
except ImportError:
    print("swift-parse-check: tree-sitter-language-pack not installed; skipping.")
    print("                   pip install tree-sitter tree-sitter-language-pack")
    sys.exit(0)


def swift_files(targets):
    for target in targets:
        if os.path.isfile(target):
            if target.endswith(".swift"):
                yield target
            continue
        for root, _directories, names in os.walk(target):
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(root, name)


def changed_files():
    """Everything git considers modified, staged or untracked."""
    out = subprocess.run(
        ["git", "status", "--porcelain"], capture_output=True, text=True, check=False
    ).stdout
    for line in out.splitlines():
        path = line[3:].strip()
        if " -> " in path:            # a rename reports "old -> new"
            path = path.split(" -> ")[-1]
        if path.endswith(".swift") and os.path.exists(path):
            yield path


def error_nodes(node, found, limit):
    """Depth-first, reporting the *outermost* bad node rather than its children —
    one broken declaration otherwise reports as a dozen nested failures."""
    if len(found) >= limit:
        return
    if node.type == "ERROR" or node.is_missing:
        found.append(node)
        return
    if not node.has_error:
        return
    for child in node.children:
        error_nodes(child, found, limit)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("targets", nargs="*", default=["kudos-ao3-reader"])
    parser.add_argument("--changed", action="store_true",
                        help="check only files git reports as modified/staged/untracked")
    parser.add_argument("--max-per-file", type=int, default=4)
    arguments = parser.parse_args()

    swift = get_parser("swift")
    targets = list(changed_files()) if arguments.changed else list(swift_files(arguments.targets))
    if not targets:
        print("swift-parse-check: nothing to check.")
        return 0

    bad = 0
    for path in targets:
        with open(path, "rb") as handle:
            source = handle.read()
        tree = swift.parse(source)
        if not tree.root_node.has_error:
            continue
        found = []
        error_nodes(tree.root_node, found, arguments.max_per_file)
        bad += 1
        for node in found:
            line = node.start_point[0] + 1
            column = node.start_point[1] + 1
            snippet = source[node.start_byte:node.end_byte][:70].decode("utf-8", "replace")
            snippet = " ".join(snippet.split())
            kind = "missing" if node.is_missing else "unparsed"
            print(f"{path}:{line}:{column}: error: {kind}: {snippet}")

    print(f"swift-parse-check: {len(targets)} file(s), {bad} with syntax errors.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
