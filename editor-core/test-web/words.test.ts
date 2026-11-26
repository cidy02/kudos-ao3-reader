// AO3's word count (spec 3.6), against the cases KudosTests/AO3WordCounterTests.swift holds for the Swift counter.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countHtml, countNode } from '../src/editor/words.ts';
import { load } from '../src/index.ts';
import { makeFixture } from '../test/fixture.ts';

const SWIFT_CASES: [string, number][] = [
  ["<p>It's a well-known don’t ‘quote’</p>", 5],
  ['left - right', 2],
  ['Stop--now', 2],
  ['wait---no', 2],
  ['日本語', 3],
  ['ひらがな', 4],
  ['カタカナ', 4],
  ['สวัสดี', 6],
  ['한국어 문장', 2],
  ['Hello 世界 world', 4],
  ['東京でcoffee', 4],
  ['<p class="lead" title="three hidden words">One <em>two</em></p><!-- a comment of five words --><p>three</p>', 3],
  ['caf&eacute; &amp; tea', 2],
  ['<b>foo</b>bar', 2],
  ['Ⓐ Ⅷ ０', 3],
  ['² ①', 0],
  ['a‌b', 2],
  ['日‌本', 2],
  ['in 2024, snake_case', 3],
  ['3.5', 2],
  ['', 0],
  ['<p></p><hr><br>', 0],
  ['  \n\t ', 0],
  ['<p>Stop--now 日本語</p>', 5],
];

test('the Swift counter\'s cases give the same counts', () => {
  for (const [input, want] of SWIFT_CASES) assert.equal(countHtml(input), want, JSON.stringify(input));
});

test('counting the document equals counting its HTML for the 510k fixtures and realistic text', () => {
  for (const kind of ['html', 'plain'] as const) {
    const src = makeFixture(kind);
    const doc = load(src, 'content').doc;
    assert.equal(countNode(doc), countHtml(load(src, 'content').cleaned), kind);
  }
  const doc = load('<p>One <b>two</b> three</p><table><tr><td>four five</td></tr></table>', 'content').doc;
  assert.equal(countNode(doc), 5, 'preserved blocks count too');
});
