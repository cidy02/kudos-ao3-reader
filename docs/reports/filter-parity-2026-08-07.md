# Filter parity: `/works/search` vs `/tags/<t>/works`

**Measured live against AO3 on 2026-08-07.** Fandom: `Naruto (Anime & Manga)`.
Baseline **142,362 works** — the same number from both endpoints, which is the
first result worth stating: Search and Browse are looking at the same set.

    Search : /works/search?work_search[fandom_names]=Naruto (Anime & Manga)
    Browse : /tags/Naruto (Anime *a* Manga)/works

Both then take the identical `work_search[...]` parameters, exactly as
`AO3Client.workSearchQueryItems` emits them.

## Method

The crisp test for a parameter an endpoint *ignores* is that the endpoint's own
total does not move when it is added. So: baseline each endpoint, then add one
parameter at a time and compare. A sort parameter is checked differently — it
changes which work is first, not how many there are — so those rows compare the
first `work_id` in the returned page instead.

Script: `filter_matrix.py` (session scratchpad). It shells out to `curl`
because this machine's Python has no usable CA bundle.

**Pacing matters and I got it wrong first.** At 1.5 s between requests AO3
started answering `525` and timing out about eleven filters in. Re-run at 5 s
with exponential backoff, and the last one re-probed alone. Anyone repeating
this should start at 5 s.

## Result: every parameter applies, on both, identically

Not "similar" — the same integer.

| Parameter | `/works/search` | `/tags/…/works` |
|---|---|---|
| `rating_ids` (Mature) | 27,338 | 27,338 |
| `archive_warning_ids[]` (Major Character Death) | 10,693 | 10,693 |
| `category_ids[]` (F/F) | 7,889 | 7,889 |
| `crossover` (no) | 125,066 | 125,066 |
| `complete` (yes) | 106,005 | 106,005 |
| `single_chapter` | 85,984 | 85,984 |
| `word_count` (1000-5000) | 61,913 | 61,913 |
| `hits` (>1000) | 78,570 | 78,570 |
| `kudos_count` (>100) | 55,392 | 55,392 |
| `comments_count` (>10) | 44,036 | 44,036 |
| `bookmarks_count` (>10) | 58,446 | 58,446 |
| `revised_at` (> 1 week ago) | 141,029 | 141,029 |
| `date_from` (2024-01-01) | 50,330 | 50,330 |
| `date_to` (2020-01-01) | 36,222 | 36,222 |
| `language_id` (fr) | 1,631 | 1,631 |
| `title` ("the") | 23,291 | 23,291 |
| `creators` ("a") | 83 | 83 |
| `character_names` | 55,506 | 55,506 |
| `relationship_names` | 20,428 | 20,428 |
| `freeform_names` | 24,075 | 24,075 |
| `query` (free text, "ramen") | 980 | 980 |
| `excluded_tag_names` ("Fluff") | 118,288 | 118,288 |
| `sort_column` (kudos_count) | reordered | reordered |
| `sort_direction` (asc) | reordered | reordered |

`fandom_names` is not a row because it *is* the difference between the two URLs
— Search sends it as a parameter, Browse puts it in the path. The matching
baselines are the evidence that both resolve to the same tag.

`query` covers more than it looks. AO3 has no structured field for excluded
warnings, excluded categories, "rating and up", or "include not rated" —
`AO3SearchFilters.searchQuery` folds all four into AO3's text-search syntax and
sends them here. That row passing is what says those four work on Browse too.

### Conclusion

**No filter is incompatible with either endpoint.** The Browse migration to
`/tags/` costs nothing in filtering power.

## What *is* restricted — and it is the app, not AO3

`AO3FilterPanel.Mode.refine` hides Sort, Crossovers, Hits, Kudos, Comments,
Bookmarks, Updated, and Title & creator. Two screens use it:

| Screen | Mode | Filters offered |
|---|---|---|
| Search tab | `.search` | all |
| Browse → category → fandom (`FandomWorksView`) | `.search` | all |
| Tag drill-down (`TagWorksView`) | `.refine` | reduced |
| Account works / bookmarks (`AO3AccountWorksList`) | `.refine` | reduced |

For `TagWorksView` the restriction is *correct given how it works* and
*expensive because of it*: it narrows the page already fetched, in memory
(`filters.apply(to: results)`), rather than re-querying. It can therefore only
filter the 20 blurbs on screen, and the hidden facets are ones a blurb does not
carry — a hit count is on the blurb, but "crossover" is not, and re-sorting 20
of 142,362 works is not a sort.

The table above proves AO3 would honour every one of those on that very URL if
that screen re-queried the way `FandomWorksView` does. So this is a capability
gap with a known fix, not a defect:

> ~~**Open question for the owner:** should the tag drill-down re-query AO3 like
> Browse does, instead of refining the loaded page?~~ **Answered: yes.** Done —
> `TagWorksView` now sends the filters with the request. Measured on the
> simulator against `Wednesday (TV 2022)`: adding the F/F category took the card
> from 19,219 works / 961 pages to **12,292 / 615**, which is AO3's own count for
> the filtered question. Under the old code the header would have gone on saying
> 19,219 and 961 while the list showed whichever of the fetched 20 were F/F.

### A pre-existing bug this surfaced

Driving that screen to check the change is what found it: **the tag drill-down
had never loaded anything at all.** AO3's own markup links a tag as
`/tags/<name>` — its *info* page — and every route into this screen comes from
such a link (an EPUB preface's "Fandom:", a tag link on a work page). That page
carries no work blurbs: measured 0 on `/tags/Frozen (Disney Movies)` against 20
on the same path plus `/works`. So the screen fetched it, parsed nothing, and
said "No works found" for tags with hundreds of thousands of works.

`AO3TagWorksRequest` now appends the `/works` segment when it is missing,
rebuilding from the *original* percent-encoded path so AO3's `*a*`-style escapes
survive. Pinned by `TagWorksRequestTests`.

Worth noting how close this came to being missed: the unit tests passed, the
URL builder was correct, and the first live check looked like AO3 rate-limiting
(a real 525, which it also was). Only re-running curl after a cooldown separated
"AO3 is throttling me" from "this URL has no works on it, ever".

`AO3AccountWorksList` is a separate case — `/users/<n>/works` and
`/users/<n>/bookmarks` were not measured here and should not be assumed to
behave like the two endpoints above.

## Not covered

- One fandom, one value per parameter. A filter that works on `Naruto` at these
  magnitudes is not proven for every tag shape (a tag with a `/` in its name
  takes a different path escape, which `tagPathSegment` handles and
  `FandomWorksURLTests` pins separately).
- Combinations. Each parameter was added to a bare baseline, so this says
  nothing about AO3's AND semantics across several at once.
- The account endpoints, as noted.
