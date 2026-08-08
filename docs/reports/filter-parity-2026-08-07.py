"""Does every filter the app emits actually apply on BOTH endpoints?

Search  -> /works/search?work_search[fandom_names]=<fandom>
Browse  -> /tags/<escaped fandom>/works

Same `work_search[...]` params on both. The crisp test for an ignored parameter
is that the endpoint's own total does not move at all when it is added.

Params mirror AO3Client.workSearchQueryItems exactly.
"""
import re, subprocess, sys, time, urllib.parse

FANDOM = "Naruto (Anime & Manga)"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")
PACE = 5.0          # AO3 answered 525 / timed out at 1.5s; back well off.
RETRIES = 3

def tag_path(name):
    # AO3's own escaping: / -> *s*, & -> *a*, . -> *d*, ? -> *q*, # -> *h*
    out = name.replace("*", "*st*").replace("/", "*s*").replace("&", "*a*")
    out = out.replace(".", "*d*").replace("?", "*q*").replace("#", "*h*")
    return urllib.parse.quote(out, safe="*")

def fetch(url):
    # curl, not urllib: this machine's Python has no usable CA bundle.
    out = subprocess.run(
        ["curl", "-sS", "--fail-with-body", "--max-time", "45", "-A", UA, url],
        capture_output=True)
    if out.returncode != 0:
        raise RuntimeError((out.stderr.decode() or "curl %d" % out.returncode).strip()[:80])
    return out.stdout.decode("utf-8", "replace")

HEADING = re.compile(
    r"<h[23][^>]*class=\"[^\"]*heading[^\"]*\"[^>]*>(.*?)</h[23]>", re.S)

def total(html):
    """The number attached to the Works/Found noun — never 'the first number'."""
    for raw in HEADING.findall(html):
        text = re.sub(r"<[^>]+>", " ", raw)
        text = re.sub(r"\s+", " ", text).strip()
        m = re.search(r"([\d,]+)\s+(?:Works?|Found)\b", text, re.I)
        if m:
            return int(m.group(1).replace(",", ""))
        m = re.search(r"of\s+([\d,]+)\s", text, re.I)
        if m:
            return int(m.group(1).replace(",", ""))
    if "Search Results" in html or "No results found" in html:
        return 0
    return None

def build(base, extra):
    items = list(extra)
    items.append(("page", "1"))
    q = urllib.parse.urlencode(items, quote_via=urllib.parse.quote)
    return base + ("&" if "?" in base else "?") + q

SEARCH = "https://archiveofourown.org/works/search?" + urllib.parse.urlencode(
    [("work_search[fandom_names]", FANDOM)], quote_via=urllib.parse.quote)
TAGS = "https://archiveofourown.org/tags/%s/works" % tag_path(FANDOM)

# (label, [(param, value), ...])
CASES = [
    ("rating_ids (Mature)",          [("work_search[rating_ids]", "12")]),
    ("archive_warning_ids (M.C.D.)", [("work_search[archive_warning_ids][]", "18")]),
    ("category_ids (F/F)",           [("work_search[category_ids][]", "116")]),
    ("crossover (no)",               [("work_search[crossover]", "F")]),
    ("complete (yes)",               [("work_search[complete]", "T")]),
    ("single_chapter",               [("work_search[single_chapter]", "1")]),
    ("word_count 1000-5000",         [("work_search[word_count]", "1000-5000")]),
    ("hits >1000",                   [("work_search[hits]", ">1000")]),
    ("kudos_count >100",             [("work_search[kudos_count]", ">100")]),
    ("comments_count >10",           [("work_search[comments_count]", ">10")]),
    ("bookmarks_count >10",          [("work_search[bookmarks_count]", ">10")]),
    ("revised_at (>1 week)",         [("work_search[revised_at]", "> 1 week ago")]),
    ("date_from",                    [("work_search[date_from]", "2024-01-01")]),
    ("date_to",                      [("work_search[date_to]", "2020-01-01")]),
    ("language_id (fr)",             [("work_search[language_id]", "fr")]),
    ("title",                        [("work_search[title]", "the")]),
    ("creators",                     [("work_search[creators]", "a")]),
    ("character_names",              [("work_search[character_names]", "Uzumaki Naruto")]),
    ("relationship_names",           [("work_search[relationship_names]", "Uchiha Sasuke/Uzumaki Naruto")]),
    ("freeform_names",               [("work_search[freeform_names]", "Fluff")]),
    ("query (free text)",            [("work_search[query]", "ramen")]),
    ("excluded_tag_names",           [("work_search[excluded_tag_names]", "Fluff")]),
    ("sort_column (kudos)",          [("work_search[sort_column]", "kudos_count")]),
    ("sort_direction (asc)",         [("work_search[sort_column]", "kudos_count"),
                                      ("work_search[sort_direction]", "asc")]),
]

def first_work_id(html):
    m = re.search(r'<li id="work_(\d+)"', html)
    return m.group(1) if m else None

def probe(base, extra):
    url = build(base, extra)
    last = ""
    for attempt in range(RETRIES):
        try:
            html = fetch(url)
        except Exception as exc:                   # noqa: BLE001 - reported, not raised
            last = str(exc)
            time.sleep(PACE * (attempt + 2))       # back off, then retry
            continue
        time.sleep(PACE)
        return total(html), first_work_id(html), None
    return None, None, "ERR %s" % last[:60]

def main():
    print("fandom:", FANDOM)
    print("search:", SEARCH)
    print("tags  :", TAGS)
    print()
    s_base, s_first, err = probe(SEARCH, [])
    print("baseline search:", s_base, "first work", s_first, err or "")
    t_base, t_first, err = probe(TAGS, [])
    print("baseline tags  :", t_base, "first work", t_first, err or "")
    print()
    hdr = "%-32s | %-22s | %-22s" % ("filter", "search", "tags")
    print(hdr); print("-" * len(hdr))
    only = sys.argv[1:]                            # resume: pass label substrings
    for label, extra in CASES:
        if only and not any(o in label for o in only):
            continue
        s_tot, s_id, s_err = probe(SEARCH, extra)
        t_tot, t_id, t_err = probe(TAGS, extra)

        def verdict(tot, first, base_tot, base_first, err):
            if err:
                return err
            if tot is None:
                return "no heading"
            # A sort doesn't change the count — it changes which work is first.
            if "sort" in label:
                return "%s reordered=%s" % (tot, first != base_first)
            if tot == base_tot:
                return "%s IGNORED" % tot
            return "%s applied" % tot

        print("%-32s | %-22s | %-22s" % (
            label,
            verdict(s_tot, s_id, s_base, s_first, s_err),
            verdict(t_tot, t_id, t_base, t_first, t_err),
        ))
        sys.stdout.flush()

main()
