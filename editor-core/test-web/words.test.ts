// AO3's word count (spec 3.6) against goldens from otwarchive's own WordCounter (test/golden/words.golden.json,
// written by test/golden/generate/words.rb). KudosTests/AO3WordCounterGoldenTests.swift reads the same file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { countNode, countWords } from '../src/words/index.ts';
import { load } from '../src/index.ts';
import { makeFixture } from '../test/fixture.ts';

const read = (f: string) => JSON.parse(readFileSync(new URL(`../test/golden/${f}`, import.meta.url), 'utf8'));
const golden = read('words.golden.json').words as Record<string, number | string>;
const sets: { id: string; input: string }[][] = [read('words-cases.json').cases, read('corpus.json').cases];

test('the hand-written cases and the cleaning corpus count as AO3 counts them', () => {
  let checked = 0, raised = 0;
  const wrong: string[] = [];
  for (const set of sets) {
    for (const c of set) {
      const want = golden[c.id];
      assert.ok(want !== undefined, `${c.id} has a golden (run test/golden/generate/words.rb)`);
      if (typeof want === 'string') { raised++; continue; } // Nokogiri raises (tree depth): AO3 can't save it either
      const got = countWords(c.input);
      if (got !== want) wrong.push(`${c.id}: AO3 ${want}, ours ${got}`);
      checked++;
    }
  }
  assert.deepEqual(wrong, []);
  assert.ok(checked > 2000, `${checked} checked, ${raised} where Ruby raises`);
});

test('the 510,000-character fixtures count as AO3 counts them', () => {
  assert.equal(countWords(makeFixture('html')), golden['fixture-html']);
  assert.equal(countWords(makeFixture('plain')), golden['fixture-plain']);
});

test('the editor document counts the same as the HTML it came from, for realistic text', () => {
  for (const kind of ['html', 'plain'] as const) {
    const src = makeFixture(kind);
    const loaded = load(src, 'content');
    assert.equal(countNode(loaded.doc), countWords(loaded.cleaned), kind);
  }
  const doc = load('<p>One <b>two</b> three</p><table><tr><td>four five</td></tr></table>', 'content').doc;
  assert.equal(countNode(doc), 5, 'preserved blocks count too');
});
