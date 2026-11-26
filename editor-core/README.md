# editor-core

The shared JavaScript package behind Kudos's Rich Text mode (`docs/WRITING_EDITOR_ARCHITECTURE.md`, D5, E2).
It turns an AO3 field's HTML into a ProseMirror document and back, with AO3's own cleaning rules ported exactly.
Parsing uses parse5 only, never a platform `DOMParser`, so Apple, Android and Node CI parse identically.

**This is part 1 (T-576a).** Done: loading pipeline, AO3 cleaning port, tiers, schema, serializer (S1 to S16), loss report,
caret maps, golden harness, property tests, the 510,000-character fixture. Part 2 (T-576b): the paste cleaner (6.8), the
AO3 word counter (3.6), the editor page and the JS side of the bridge (7.2), and the bundle for the apps. `npm run build`
already bundles `src/index.ts` with esbuild, but nothing consumes it yet.

## Run the tests

```
cd editor-core
npm ci
npm test            # tsc --noEmit, then every test file with node:test (Node 24 or newer; developed on 26)
npm run test:props  # property tests only; FC_SEED=<n> FC_RUNS=<n> to replay or lengthen (seed is printed)
npm run perf        # timings for the 510,000-character fixture (see PERF.md)
```

Tests are TypeScript run directly by Node's type stripping; sources avoid enums and parameter properties for that reason.
Runtime dependencies are exactly `parse5`, `prosemirror-model`, `prosemirror-transform`, `prosemirror-state`, all pinned.
(`prosemirror-transform` is a declared runtime dependency as the brief asks; part 1's own code reaches it through
`prosemirror-state`, which tests use for edits.)

## Regenerate the goldens

The goldens come from otwarchive's own Ruby (`HtmlCleaner#sanitize_value`, ParagraphMaker, the sanitizer transformers)
at commit `452391b648f2fb06b55c36133812449747634504`, vendored unmodified in
`test/golden/generate/upstream/otwarchive/` with its licence (see `NOTICE`). You need Ruby 3.4 (macOS system Ruby 2.6 is
too old for Nokogiri 1.19: `brew install ruby@3.4` and put it first on `PATH`). Gems are pinned in `generate/Gemfile` and
`Gemfile.lock` to otwarchive's `Gemfile.lock` at that commit (otwarchive pins Ruby 3.4.12; the goldens were made with 3.4.13).

```
node test/golden/make-corpus.ts            # writes test/golden/corpus.json (inputs)
cd test/golden/generate && bundle install && bundle exec ruby generate.rb   # writes test/golden/sanitize.golden.json
```

The corpus (1,975 cases): synthetic cases for every rule in spec 3 and 6, realistic chapters, textareas and epub chapter
bodies from `KudosTests/Fixtures/`, 1,200 seeded fuzz inputs, and 300 serializations of generated documents (so Ruby itself
judges S15). A test fails if `corpus.json` is stale. Each case records, for `content`, `notes` (equal to `endnotes`, asserted)
and `summary`, either the HTML Ruby produced or the error class it raised, plus the ParagraphMaker stage on its own.

## Public API (`src/index.ts`)

```ts
type Variant = 'content' | 'notes' | 'summary';            // spec 6.6; FIELD_LIMITS gives 510000 / 5000 / 1250

load(html: string, variant: Variant, opts?: { appUrl?: string }): LoadResult
  // { doc, loss: LossReport, sources, cleaned, timing: { cleanMs, buildMs } }   -- the bridge's `load`
parse(html, variant): Node                                  // S14/S15's "parse"
parseCleaned(cleanHtml): Node                               // build only, no AO3 cleaning (S15's check)

serialize(doc, { sources?, head? }): string
serializeDoc(doc, { sources?, head? }): { html, headOffset: number | null }
serializeBlock(node): string                                // canonical text of one top-level block

snapshot(loaded, doc, { head? }): { html, headOffset }      // the bridge's `snapshot`: R1 if doc is unedited, else R2
activate(loaded, htmlOffsetUtf16): { pos, caretFound }      // the bridge's `activate` caret step (7.5)
lint(html, variant): LossReport                             // the bridge's `lint`

sanitizeValue(variant, html, { appUrl?, report? }): string  // HtmlCleaner#sanitize_value exactly; throws like Ruby does
schema, SCHEMA_VERSION                                      // ProseMirror schema (6.3 to 6.5)
```

* `LossReport` is spec 6.9. `dropped` counts what AO3 removes (elements with their tag name, attributes by name; an element
  that is removed is counted once, its own attributes are not counted again; comments appear as `#comment`).
  `unwrapped` is attribute-less `span` (schema-level). `preserved` counts raw blocks and inlines. `normalized` counts
  edits that change bytes but not meaning: ParagraphMaker restructuring (whitespace strips, splits, wraps, deleted empty
  paragraphs), `rel` on links, relative image URLs made absolute, newline-to-space in text, `<br>` runs split, list-item
  edge whitespace. It is a count of changes, not of characters.
* `sources` (on `LoadResult`) holds the original text, the slice map (S16) and the caret maps. Both are built on first use,
  not at load. Slices are cut from AO3's `fix_bad_characters` view of the text (CRLF to LF, `<3` to `&lt;3`), so an edited
  document written back through `serialize` normalizes those and nothing else in untouched blocks.
* `appUrl` is the base for relative `img src` (default `https://archiveofourown.org`; otwarchive's own default config says
  `example.org`, production sets its own value, and the goldens use the production one).
* Errors: `ParseLimitError` (Nokogiri's tree depth of 400 and 400 attributes per element, which raise in AO3 too) and
  `SanitizerFailure` (an audio/video `src` Ruby's Addressable cannot parse raises in AO3 too). Callers should treat both as
  "Rich Text can't open this text".
* Top-level blocks come out as `raw_block`/`raw_inline` for the Preserved tier (6.2); their `source` is the cleaned HTML
  slice (what AO3 would keep), so S15 holds for them.

## How a load works (6.1)

`sanitizeValue` (string in, string out, a port of `HtmlCleaner#sanitize_value`: strip, `fix_bad_characters`, ParagraphMaker,
`Sanitize.clean` with the field's transformers, re-serialize with Nokogiri's HTML5 writer rules) then parse5 again with source
locations, then `build.ts` makes the ProseMirror document. The port runs the same parse/serialize round trips AO3 does, because
those round trips are observable (they are why the goldens match on 18,000 further fuzz cases, see below).

Files: `html5.ts` (parse5 to a small DOM; Nokogiri-compatible serializer), `dom.ts` (libxml2-like sibling and text-merge
rules), `paragraph-maker.ts`, `sanitize.ts` (Sanitize 6.1.0 and otwarchive's transformers), `addressable.ts` (the URI
behaviour those transformers use), `clean.ts`, `schema.ts`, `build.ts`, `serialize.ts`, `sources.ts` (S16 and caret maps),
`decode.ts` (character-reference walker), `load.ts`, `index.ts`.

## Departures from the spec, and why

See the "Departures" list in the part 1 report and the commit messages; the ones a reader of the code needs:

1. **S5.** Text also writes `____spacer____` as `____spacer&#95;___`: AO3's `fix_bad_characters` deletes the literal marker, which would silently eat the writer's text.
2. **S6.** No newline between two sibling blocks that are both `address`, `iframe`, `embed` or `object`: AO3 strips whitespace around every other block but not these, and turns the newline into a `<br>` paragraph. Found by the S15 property test against Ruby.
3. **S9 / empty field.** A document that is one empty plain paragraph serializes to the empty string, so an emptied field stays empty.
4. **Empty block containers** (`<div></div>`, `<blockquote></blockquote>`, an empty list, `<details></details>`) become a preserved raw block rather than gaining an invented empty paragraph.
5. **`details`** is `summary? block*` (AO3 accepts a `details` with no `summary`).
6. **Adjacent `<br>` (S10)** inside a paragraph split it exactly as AO3's `merge_br_tags` would (three or more add a spacer paragraph); inside a heading or summary a run collapses to one.
7. **Scope of the Preserved tier:** also orphan `li`, `dd`, `dt`, `summary`, and anything the schema has no home for (a block inside `p` or a heading keeps that whole container).
8. **Locality (S16)** cuts slices only where a one-chunk-one-block alignment is verified by reloading the chunk; anything else falls back to canonical output for that block. A blank paragraph between blank lines is written from source only when both neighbours are too.
9. **Caret mapping (7.5)** aligns decoded text characters (ignoring whitespace) between the original parse and the document, instead of carrying source ranges through the cleaner, because the cleaner re-parses its own output. It is exact for text outside Preserved atoms; whitespace-only positions snap to the nearest text. Documents containing `____spacer____` or lone surrogates get no caret map (offsets are not modelled across those edits).
10. **Gumbo versus parse5.** Nokogiri parses with Gumbo; the port parses with parse5 (scripting disabled to match Gumbo's `noscript`). The corpus shows no difference in cleaned output. One known difference below the cleaner: Gumbo keeps `<![CDATA[..]]>` inside `<svg>` as a node, parse5 as text; the svg is removed with its contents either way.
11. **IDNA** for non-ASCII embed hosts is approximated (`addressable.ts`); allow-list outcomes are unaffected.

## Known limits

* `normalized` is a change count, not a character count.
* A document whose cleaned form still has an `<a>` nested in an `<a>` (an anchor `raw_inline` inside a link mark) cannot round-trip; the editor's commands must not create it (the generators exclude it).
* Whitespace-only text next to a mark boundary in list items is treated as formatting and trimmed at the item's edges.
