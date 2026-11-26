# editor-core performance (regression guard)

Spec 6.10 and 9.1: timings for a 510,000-character chapter, recorded so a future change that makes parsing or serializing
much slower is noticed. These are Node numbers on a laptop, **not device budgets** (B4, B8, B10, B11 are measured on
devices in E3). `test/perf.test.ts` fails if load exceeds 15 s or a canonical serialize exceeds 3 s, which is far above
these numbers on purpose: it catches an accidental quadratic, not a few percent.

The fixture (`test/fixture.ts`, seeded, exactly 510,000 characters) follows 9.1: paragraphs of 40 to 120 words, about 5%
formatted runs, blockquotes, lists, `hr`, one table, one work-skin `div`, non-Latin text. `html` is `<p>`-wrapped, `plain`
is blank-line-separated text that AO3 paragraphs itself.

Run `npm run perf`. Recorded on Node v26.13.1, darwin/arm64 (Apple silicon laptop), one run, cold JIT:

| Step | html fixture | plain fixture |
|---|---:|---:|
| clean: the AO3 port (ParagraphMaker + sanitizer) | 62 ms | 72 ms |
| load: clean + parse5 + build document | 95 ms | 94 ms |
| serialize the whole document, canonical | 4.5 ms | 1.5 ms |
| serialize, no edit, with source slices (first call computes locality) | 31 ms | 108 ms |
| serialize after one edit (slices for untouched blocks) | 0.2 ms | 0.3 ms |
| snapshot with no edit (original bytes, caret map built on first use) | 50 ms | 46 ms |
| activate / caret offset to position (map cached) | <0.1 ms | <0.1 ms |

Top-level blocks: 1,190 (html), 1,179 (plain). Locality (slices) and the caret map are computed on first use and cached
per load, so they are off the load path and off the keystroke path.

## The editor page (part 2b)

`npm run bundle`: `editor.js` 462 KB minified, 140 KB gzip (parse5 140 KB, prosemirror-view 99 KB, prosemirror-model 45 KB,
entities 33 KB, prosemirror-transform 32 KB, editor-core 85 KB); `editor.css` 5.8 KB; `editor.html` 0.7 KB. It ships inside
the app and is never downloaded.

`node test-web/perf.ts`, Node v26.13.1, darwin/arm64, html fixture (510,000 characters, 1,190 blocks), one run:

| Step | Time |
|---|---:|
| word count, first (every block once) / again (cached per block) | 8 ms / 0.1 ms |
| snapshot after one edit, first (part 1's locality computed) | 31 ms |
| snapshot after the next keystroke (one block re-serialized) | 0.4 ms |
| switch check leaving Rich Text, one edited block | 0.6 ms |
| switch check leaving HTML, fresh preload (computes locality) | 33 ms |
| caret through the serializer after a switch back (first use builds part 1's caret map) | 45 ms |

`test-web/roundtrip.test.ts` fails if a checkpoint after a keystroke exceeds 16 ms (B4) at p95 or the switch check after
one edit exceeds 150 ms (B11). These are Node numbers, not device budgets.
