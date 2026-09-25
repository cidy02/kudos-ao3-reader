#!/usr/bin/env python3
"""Write the chapter the writing editor's budgets are measured with.

docs/WRITING_EDITOR_ARCHITECTURE.md §9.1: a deterministic chapter of exactly
510,000 characters (AO3's CONTENT_MAX), shaped like real fic HTML: paragraphs
of 40-120 words with about 5% formatted runs, blockquotes, lists, rules, one
table, one work-skin <div>, a spoiler, and Japanese, Chinese and right-to-left
Arabic text. Blocks are separated by single newlines (§6.7 S6).

Same output on every machine and every run (fixed seed), so a budget measured
on the Mac and one measured on Android describe the same text.

    Scripts/make-writing-fixture.py > writing-510k.html
    Scripts/make-writing-fixture.py --characters 100000 --out small.html
"""

import argparse
import random
import sys
from html.parser import HTMLParser

WORDS = (
    "the of and to a in that was he she it with for as his her on at by had "
    "they you not be this from but or have an were which one all their there "
    "been if would when what so out up about into them some could time only "
    "then its like over think also back after use two how our work first well "
    "way even new want because any these give day most us rain window coat "
    "diner quiet letter train morning kitchen river hands laugh whisper door "
    "light remember almost careful storm silver promise tea stairs garden"
).split()

# Non-Latin runs: AO3 counts Han, Hiragana, Katakana and Thai per character
# (§3.6), so these make the word-count differences visible.
JAPANESE = "彼女は窓の外を見て、静かに雨の音を聞いていた。"
CHINESE = "他站在门口，手里拿着那封还没有打开的信。"
ARABIC = "كانت الرسالة لا تزال مغلقة على الطاولة."

FORMATS = ("em", "strong", "u", "strike", "em", "em")

WORK_SKIN = (
    '<div class="phone">\n'
    '<p class="sender">Are you coming tonight?</p>\n'
    '<p class="receiver">Leaving now. Save me a seat &amp; the good tea.</p>\n'
    "</div>"
)

TABLE = (
    "<table>\n"
    "<tr><th>Day</th><th>Place</th></tr>\n"
    "<tr><td>Monday</td><td>The diner</td></tr>\n"
    "<tr><td>Friday</td><td>The river</td></tr>\n"
    "</table>"
)

SPOILER = "<details><summary>Content note</summary><p>Mentions of a storm.</p></details>"


def sentence(rng: random.Random, count: int) -> str:
    words = [rng.choice(WORDS) for _ in range(count)]
    out = []
    i = 0
    while i < len(words):
        # About 5% of words start a formatted run of one to four words.
        if rng.random() < 0.05:
            run = rng.randint(1, 4)
            tag = rng.choice(FORMATS)
            out.append(f"<{tag}>{' '.join(words[i:i + run])}</{tag}>")
            i += run
        else:
            out.append(words[i])
            i += 1
    text = " ".join(out)
    return text[0].upper() + text[1:] + "."


def paragraph(rng: random.Random) -> str:
    return f"<p>{sentence(rng, rng.randint(40, 120))}</p>"


def block(rng: random.Random, index: int) -> str:
    if index == 3:
        return TABLE
    if index == 7:
        return WORK_SKIN
    if index == 11:
        return SPOILER
    if index % 97 == 13:
        return f"<p>{JAPANESE}</p>"
    if index % 89 == 17:
        return f"<p>{CHINESE}</p>"
    if index % 83 == 19:
        return f'<p dir="rtl">{ARABIC}</p>'
    if index % 60 == 29:
        return "<hr>"
    if index % 40 == 23:
        items = "\n".join(f"<li>{sentence(rng, rng.randint(4, 12))}</li>" for _ in range(rng.randint(2, 5)))
        return f"<ul>\n{items}\n</ul>"
    if index % 25 == 5:
        inner = "\n".join(paragraph(rng) for _ in range(rng.randint(1, 2)))
        return f"<blockquote>\n{inner}\n</blockquote>"
    if index % 31 == 2:
        first = sentence(rng, rng.randint(8, 20))
        second = sentence(rng, rng.randint(8, 20))
        return f"<p>{first}<br>{second}</p>"
    return paragraph(rng)


def plain_text(rng: random.Random, length: int) -> str:
    """Exactly `length` characters of plain words: no tags, so it can be cut
    anywhere without breaking the markup."""
    parts: list[str] = []
    total = 0  # len(" ".join(parts)) + 1
    while total <= length:
        word = rng.choice(WORDS)
        parts.append(word)
        total += len(word) + 1
    text = " ".join(parts)[:length]
    return text[:-1] + "x" if text.endswith(" ") else text


def build(characters: int, seed: int) -> str:
    rng = random.Random(seed)
    blocks: list[str] = []
    length = 0  # len("\n".join(blocks)), kept incrementally
    index = 0
    while True:
        candidate = block(rng, index)
        added = len(candidate) + (1 if blocks else 0)
        if length + added > characters:
            break
        blocks.append(candidate)
        length += added
        index += 1
    remaining = characters - length
    text_length = remaining - (1 if blocks else 0) - len("<p></p>")
    if text_length >= 1:
        blocks.append(f"<p>{plain_text(rng, text_length)}</p>")
    elif remaining > 0:
        # No room for one more paragraph: lengthen the last plain one instead.
        last = max(i for i, b in enumerate(blocks) if b.startswith("<p") and b.endswith("</p>"))
        blocks[last] = blocks[last][:-4] + "x" * remaining + "</p>"
    return "\n".join(blocks)


class BalanceCheck(HTMLParser):
    VOID = {"br", "hr", "img", "col"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"unexpected </{tag}> (open: {self.stack[-3:]})")
            return
        self.stack.pop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--characters", type=int, default=510_000,
                        help="exact length in characters (default: AO3's CONTENT_MAX, 510000)")
    parser.add_argument("--seed", type=int, default=262, help="random seed (default 262)")
    parser.add_argument("--out", help="write here instead of standard output")
    args = parser.parse_args()
    if args.characters < 8:
        parser.error("--characters must be at least 8 (room for one <p>…</p>)")

    chapter = build(args.characters, args.seed)
    check = BalanceCheck()
    check.feed(chapter)
    check.close()
    if len(chapter) != args.characters or check.errors or check.stack:
        print(f"make-writing-fixture: bad output: length {len(chapter)}, "
              f"errors {check.errors[:3]}, unclosed {check.stack[-3:]}", file=sys.stderr)
        return 1

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(chapter)
    else:
        sys.stdout.write(chapter)
    print(f"make-writing-fixture: {len(chapter):,} characters, "
          f"{chapter.count('<p'):,} paragraphs, "
          f"{len(chapter.encode('utf-8')):,} UTF-8 bytes", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
