import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fixBadCharacters, paragraphStage, sanitizeValue } from '../src/clean.ts';
import { buildCorpus } from './golden/corpus.ts';
import type { Variant } from '../src/sanitize.ts';

const here = dirname(fileURLToPath(import.meta.url));
const golden = JSON.parse(readFileSync(join(here, 'golden/sanitize.golden.json'), 'utf8'));
const corpus = JSON.parse(readFileSync(join(here, 'golden/corpus.json'), 'utf8'));
const inputs = new Map<string, string>(corpus.cases.map((c: any) => [c.id, c.input]));

test('corpus.json is what corpus.ts generates (regenerate with: node test/golden/make-corpus.ts)', () => {
  assert.deepEqual(JSON.parse(JSON.stringify(buildCorpus(resolve(here, '../..')))), corpus);
});

test('golden file covers the corpus', () => {
  assert.deepEqual(golden.cases.map((c: any) => c.id), corpus.cases.map((c: any) => c.id));
});

const attempt = (f: () => string): { html: string } | { error: string } => {
  try { return { html: f() }; } catch (e) { return { error: (e as Error).constructor.name }; }
};

// Gumbo keeps <![CDATA[...]]> inside <svg> as a node; parse5 turns it into text. The svg is removed with its contents by
// the sanitizer either way, so the full pipeline matches (the sanitize_value tests below cover it).
const KNOWN_STAGE_DIFFERENCES = new Set(['cdata-svg']);

test('ParagraphMaker stage reproduces every golden', () => {
  const bad: string[] = [];
  for (const g of golden.cases) {
    const input = inputs.get(g.id)!;
    if (input.trim() === '') continue;
    let got: string;
    try { got = paragraphStage(input); } catch (e) { got = `!${(e as Error).constructor.name}`; }
    if (KNOWN_STAGE_DIFFERENCES.has(g.id)) continue;
    if (g.paragraphs.startsWith('!')) continue; // Ruby raised: covered by the full-pipeline error comparison
    if (got !== g.paragraphs) bad.push(`${g.id}\n  input:    ${JSON.stringify(input).slice(0, 300)}\n  expected: ${JSON.stringify(g.paragraphs).slice(0, 300)}\n  got:      ${JSON.stringify(got).slice(0, 300)}`);
  }
  assert.equal(bad.length, 0, `${bad.length} mismatches\n` + bad.slice(0, 8).join('\n'));
});

for (const variant of ['content', 'notes', 'summary'] as Variant[]) {
  test(`sanitize_value(${variant}) reproduces every golden`, () => {
    const bad: string[] = [];
    for (const g of golden.cases) {
      const input = inputs.get(g.id)!;
      const want = g[variant];
      const got = attempt(() => sanitizeValue(variant, input));
      const same = 'error' in want ? 'error' in got : 'html' in got && got.html === want.html;
      if (!same) bad.push(`${g.id}\n  input:    ${JSON.stringify(input).slice(0, 300)}\n  expected: ${JSON.stringify(want.html ?? 'ERR ' + want.error).slice(0, 400)}\n  got:      ${JSON.stringify('html' in got ? got.html : 'ERR ' + got.error).slice(0, 400)}`);
    }
    assert.equal(bad.length, 0, `${bad.length} of ${golden.cases.length} mismatches\n` + bad.slice(0, 10).join('\n'));
  });
}

test('fixBadCharacters drops lone surrogates (not representable in the JSON corpus)', () => {
  assert.equal(fixBadCharacters('a\ud800b\udc00c\u{1f600}'), 'abc\u{1f600}');
});
