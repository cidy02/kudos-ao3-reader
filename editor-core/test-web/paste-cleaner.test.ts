// The paste cleaner (spec 6.8): the P9 fixtures from each source app, the rules one by one, and the property that
// pasting a document's own serialized HTML gives back the same document.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import fc from 'fast-check';
import { pasteContent } from '../src/editor/paste.ts';
import { detectSource, precleanPaste } from '../src/paste/index.ts';
import { load, schema, serializeDoc } from '../src/index.ts';
import type { Variant } from '../src/index.ts';
import { docArb } from '../test/arb.ts';

const fixtures = new URL('../test/paste-fixtures/', import.meta.url);
const expected = JSON.parse(readFileSync(new URL('expected.json', fixtures), 'utf8')) as Record<string, any>;
const paste = (html: string, variant: Variant = 'content') => {
  const r = pasteContent(html, '', variant)!;
  return { ...r, html: serializeDoc(schema.nodes.doc!.create(null, r.slice.content)).html };
};

for (const [file, want] of Object.entries(expected)) {
  test(`P9 fixture ${file}: the expected document and paste report`, () => {
    const r = paste(readFileSync(new URL(file, fixtures), 'utf8'));
    assert.equal(r.html, want.html);
    assert.equal(r.source, want.source);
    assert.equal(r.words, want.words);
    assert.deepEqual(r.kept, want.kept);
    assert.deepEqual(r.converted, want.converted);
    assert.deepEqual(r.styles, want.styles);
    assert.deepEqual(r.examples, want.examples);
    assert.deepEqual(r.loss.dropped, want.dropped);
  });
}

test('the case that matters most: italics and bold from Google Docs survive', () => {
  const r = paste(readFileSync(new URL('google-docs.html', fixtures), 'utf8'));
  assert.match(r.html, /<em>Not once\.<\/em>/);
  assert.match(r.html, /<strong>Chapter Two<\/strong>/);
  assert.match(r.html, /<strong><em>and so did she<\/em><\/strong>/);
  assert.doesNotMatch(r.html, /docs-internal-guid|style=|<b[ >]/, 'the wrapper <b> is gone and makes nothing bold');
});

test('every source app is told apart', () => {
  for (const [file, source] of [['google-docs.html', 'google-docs'], ['word-windows.html', 'word'], ['word-mac.html', 'word'], ['pages.html', 'apple'], ['notes.html', 'apple'], ['ao3-work.html', 'ao3'], ['web-page.html', 'web'], ['scrivener.html', 'web']]) {
    assert.equal(detectSource(readFileSync(new URL(file!, fixtures), 'utf8')), source, file);
  }
});

test('P2: comments, Word conditional comments, style, meta, link, xml, o:p and Office namespaces go', () => {
  const { html, report } = precleanPaste('<!--[if gte mso 9]><xml><w:WordDocument/></xml><![endif]--><style>p{}</style><meta charset="utf-8"><link rel="x" href="y"><p>a<o:p></o:p><w:sdt>b</w:sdt><v:shape>c</v:shape></p><!-- note -->');
  assert.equal(html, '<p>a</p>');
  assert.ok(report.removed['#comment']! >= 1); // the one before <html> isn't in the body at all
  assert.ok(report.removed['o:p'] && report.removed['w:sdt'] && report.removed['v:shape']);
});

test('P3: styles become structure, on the element or its block', () => {
  const cases: [string, string][] = [
    ['<p><span style="font-weight:600">x</span></p>', '<p><strong>x</strong></p>'],
    ['<p><span style="font-weight: bold">x</span></p>', '<p><strong>x</strong></p>'],
    ['<p><span style="font-style:oblique">x</span></p>', '<p><em>x</em></p>'],
    ['<p><span style="text-decoration: underline line-through">x</span></p>', '<p><u><strike>x</strike></u></p>'],
    ['<p>H<span style="vertical-align:sub">2</span>O</p>', '<p>H<sub>2</sub>O</p>'],
    ['<p style="text-align:justify">x</p>', '<p align="justify">x</p>'],
    ['<p><span style="text-align:right">x</span></p>', '<p align="right">x</p>'],
    ['<p style="direction:rtl">x</p>', '<p dir="rtl">x</p>'],
    ['<p style="font-weight:bold">x</p>', '<p><strong>x</strong></p>'],
    ['<h2 style="font-weight:bold">x</h2>', '<h2>x</h2>'],
    ['<p><b style="font-weight:normal">x</b></p>', '<p>x</p>'],
    ['<p><span style="font-weight:400">x</span></p>', '<p>x</p>'],
  ];
  for (const [input, want] of cases) assert.equal(paste(input).html, want, input);
});

test('P4: the Google Docs wrapper is unwrapped without making anything bold', () => {
  assert.equal(paste('<b style="font-weight:normal;" id="docs-internal-guid-1"><p dir="ltr"><span>plain</span></p></b>').html, '<p>plain</p>');
});

test('P5: Word classes, lang spans and lists', () => {
  const word = (body: string) => `<html xmlns:w="urn:schemas-microsoft-com:office:word"><body>${body}</body></html>`;
  assert.equal(paste(word('<p class=MsoNormal><span lang=EN-US>x</span></p>')).html, '<p>x</p>');
  assert.equal(paste(word('<p class="MsoNormal note">x</p>')).html, '<p class="note">x</p>');
  const list = (level: number, marker: string, textValue: string) => `<p class=MsoListParagraph style='mso-list:l0 level${level} lfo1'><![if !supportLists]><span style='mso-list:Ignore'>${marker}<span>&nbsp; </span></span><![endif]>${textValue}</p>`;
  assert.equal(paste(word(list(1, 'a)', 'one') + list(1, 'b)', 'two'))).html, '<ol><li>one</li>\n<li>two</li></ol>');
  assert.equal(paste(word(list(1, '·', 'a') + list(2, 'o', 'b') + list(3, '§', 'c') + list(1, '·', 'd'))).html,
    '<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li>\n<li>d</li></ul>');
  assert.equal(paste(word(`<p>before</p>${list(1, 'i.', 'first')}<p>after</p>`)).html, '<p>before</p>\n<ol><li>first</li></ol>\n<p>after</p>');
});

test('the report counts what AO3 can\'t show, not the layout noise every app adds', () => {
  const r = paste('<p style="margin:0;line-height:1.38;text-indent:2em"><span style="color:#000000;background-color:transparent;font-family:Arial">plain</span> <span style="color:#c00">red</span></p>');
  assert.deepEqual(r.styles, { 'font-family': 1, color: 1 });
  assert.deepEqual(r.examples, ['color ×1', 'font-family ×1']);
});

test('pasting a document\'s own serialized HTML gives back the same document (generated documents, content and notes)', () => {
  for (const variant of ['content', 'notes'] as Variant[]) {
    fc.assert(fc.property(docArb(variant, { maxBlocks: 8 }), (d) => {
      const html = serializeDoc(d).html;
      const pre = precleanPaste(html);
      assert.ok(load(pre.html, variant).doc.eq(d), `${html}\n->\n${pre.html}`);
    }), { seed: Number(process.env.FC_SEED ?? 576003), numRuns: Number(process.env.FC_RUNS ?? 300) });
  }
});

test('paste never fetches anything (P7): the cleaner has no network or DOM access', () => {
  const src = readFileSync(new URL('../src/paste/index.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(src, /\bfetch\(|XMLHttpRequest|document\.|window\.|innerHTML/);
});
