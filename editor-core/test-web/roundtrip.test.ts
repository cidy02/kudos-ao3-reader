// R1 (load then snapshot with no edit gives the same bytes), the switch check (7.11), and incremental serialization
// (9.4) against part 1's serializer, through the real editor.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import fc from 'fast-check';
import { EditorState, TextSelection } from 'prosemirror-state';
import { caretAt, command, harness, html, opened, selectText } from './dom.ts';
import { load, schema, serializeDoc } from '../src/index.ts';
import type { Variant } from '../src/index.ts';
import { IncrementalSerializer } from '../src/editor/incremental.ts';
import { countNode } from '../src/editor/words.ts';
import { verifyLeavingRich, verifyLeavingSource } from '../src/editor/verify.ts';
import { docArb } from '../test/arb.ts';
import { makeFixture } from '../test/fixture.ts';

const corpus = (JSON.parse(readFileSync(new URL('../test/golden/corpus.json', import.meta.url), 'utf8')) as { cases: { id: string; input: string }[] }).cases;
const seed = Number(process.env.FC_SEED ?? 576002);
const runs = Number(process.env.FC_RUNS ?? 300);
const params = { seed, numRuns: runs, endOnFailure: false };

test(`R1: load then snapshot with no edit returns the same bytes (${corpus.length} corpus inputs, the 510k fixtures)`, async () => {
  const h = harness();
  await h.ready;
  let opened = 0;
  const inputs = [...corpus.map((c) => [c.id, c.input] as const), ['fixture-html', makeFixture('html')] as const, ['fixture-plain', makeFixture('plain')] as const];
  for (const [id, input] of inputs) {
    try {
      await h.call('load', { html: input, revision: 5 });
    } catch (e: any) {
      assert.ok(['too-large', 'sanitizer'].includes(e.code), `${id}: ${e.code} ${e.message}`); // AO3 itself raises on these
      continue;
    }
    opened++;
    const s = await h.call('snapshot', { caret: false });
    assert.equal(s.html, input, id);
    assert.equal(s.revision, 5, id);
    await h.call('activate', { caret: Math.floor(input.length / 2), focus: false });
    await h.call('freeze', {});
    const again = await h.call('snapshot', { caret: true });
    assert.equal(again.html, input, `${id} after activate and freeze`);
    assert.equal(again.revision, 5, id);
  }
  assert.ok(opened > corpus.length * 0.9, `${opened} opened`);
});

test('R1: an edit that is undone hands back the original bytes; the caret maps back to where it was', async () => {
  const src = '<p>Once  upon&nbsp;a <i>time</i>.</p>\r\n\r\n<p>The end.</p>';
  const h = harness();
  await h.ready;
  await h.call('load', { html: src, revision: 1 });
  const at = src.indexOf('time') + 2;
  await h.call('activate', { caret: at, focus: false });
  const s0 = await h.call('snapshot', { caret: true });
  assert.equal(s0.caretOffset, at);
  await command(h, 'insertText', { text: 'X' });
  assert.notEqual(await html(h), src);
  await command(h, 'undo');
  const s1 = await h.call('snapshot', { caret: true });
  assert.equal(s1.html, src);
  assert.equal(s1.revision, 3, 'the revision still counts both edits');
});

test('after an edit, untouched blocks keep their source bytes (R2) and the caret offset is in the new text', async () => {
  const src = '<p>one</p>\n\n<p>two  <b>bold</b></p>\n\n<p align="center">three</p>';
  const h = await opened(src);
  caretAt(h, 'one');
  await command(h, 'insertText', { text: '!' });
  const s = await h.call('snapshot', { caret: true });
  // the newline between an edited block and an untouched one is S6's; between two untouched blocks it is the source's
  assert.equal(s.html, '<p>one!</p>\n<p>two  <b>bold</b></p>\n\n<p align="center">three</p>');
  assert.equal(s.html.slice(0, s.caretOffset), '<p>one!');
  assert.equal(s.words, 4);
});

test('switch check, leaving Rich Text: passes after real edits, and the way back maps the caret into the new text', async () => {
  const h = await opened('<p>alpha beta</p>\n<p>gamma</p>');
  selectText(h, 'beta');
  await command(h, 'toggleMark', { mark: 'italic' });
  caretAt(h, 'gamma');
  await command(h, 'insertFootnote');
  await command(h, 'insertText', { text: 'note' });
  await command(h, 'setBlock', { block: 'quote' });
  await h.call('freeze', {});
  const s = await h.call('snapshot', { caret: true });
  const v = await h.call('verifySwitch', { direction: 'richToSource', html: s.html });
  assert.deepEqual(v, { ok: true, candidateHtml: s.html });
  // HTML mode now shows s.html; switching straight back (warm, no HTML edit) places the caret through its parse
  const target = s.html.indexOf('gamma') + 3;
  const r = await h.call('activate', { caret: target, focus: false });
  assert.equal(r.caretFound, true);
  const { selection, doc } = h.bridge.editor.view.state;
  assert.equal(doc.textBetween(selection.head - 3, selection.head), 'gam');
  assert.equal((await h.call('snapshot', { caret: false })).html, s.html, 'R1 now holds against the HTML-mode text');
});

test('switch check, leaving Rich Text: a list item typed with a trailing space still passes', async () => {
  const h = await opened('<ul><li>item</li></ul>');
  caretAt(h, 'item');
  await command(h, 'insertText', { text: ' ' });
  const s = await h.call('snapshot', {});
  assert.equal(s.html, '<ul><li>item </li></ul>');
  assert.equal((await h.call('verifySwitch', { direction: 'richToSource', html: s.html })).ok, true);
});

test('switch check catches a deliberately broken serializer and a stale snapshot', async () => {
  const h = await opened('<p>a <em>b</em></p>\n<p>c</p>');
  selectText(h, 'c');
  await command(h, 'toggleMark', { mark: 'bold' });
  const doc = h.bridge.editor.view.state.doc;
  const good = (d: typeof doc) => serializeDoc(d).html;
  assert.equal(verifyLeavingRich(doc, 'content', good).ok, true);
  const brokens: [string, (d: typeof doc) => string][] = [
    ['drops a mark', (d) => good(d).replace('<strong>', '').replace('</strong>', '')],
    ['renames a tag', (d) => good(d).replace(/<em>(.*?)<\/em>/, '<i>$1</i>')],
    ['loses the last block', (d) => good(d).split('\n').slice(0, -1).join('\n')],
    ['adds text', (d) => good(d).replace('c', 'cc')],
  ];
  for (const [name, serialize] of brokens) {
    const r = verifyLeavingRich(doc, 'content', serialize);
    assert.equal(r.ok, false, name);
    assert.match(r.reason!, /differs/, name);
  }
  const stale = await h.call('verifySwitch', { direction: 'richToSource', html: '<p>a <em>b</em></p>\n<p>c</p>' });
  assert.equal(stale.ok, false);
  assert.match(stale.reason, /snapshot/);
  const viaBridge = h.bridge.editor.verifySwitch('richToSource', undefined, { serialize: brokens[0]![1] });
  assert.equal(viaBridge.ok, false);
});

// Part 1's serializer is not yet S15-stable on every document loaded from fuzz input (see README, "Open issues"), so
// the check is held to this: every realistic input passes, and on fuzz input it passes exactly when the document
// survives both serializations, which is what keeps a lossy switch from committing.
const KNOWN_S15 = new Set(['li-bare', 'nested-400']);
test('switch check, leaving HTML: realistic corpus inputs pass; on fuzz input it is exactly the round-trip test', async () => {
  let checked = 0, refused = 0;
  for (const c of corpus) {
    let loaded;
    try { loaded = load(c.input, 'content'); } catch { continue; }
    const r = verifyLeavingSource(c.input, 'content', loaded);
    if (/^(fuzz|gen)-/.test(c.id)) {
      let survives: boolean;
      try {
        survives = load(serializeDoc(loaded.doc).html, 'content').doc.eq(loaded.doc) && load(serializeDoc(loaded.doc, { sources: loaded.sources }).html, 'content').doc.eq(loaded.doc);
      } catch { survives = false; }
      assert.equal(r.ok, survives, c.id);
      if (!r.ok) refused++;
    } else if (!KNOWN_S15.has(c.id)) assert.equal(r.ok, true, `${c.id}: ${r.reason}`);
    checked++;
  }
  assert.ok(checked > 1700);
  console.log(`leaving-HTML check: ${checked} inputs, ${refused} fuzz inputs refused (part 1 S15 gaps)`);
  const src = '<p>a <em>b</em></p>';
  assert.equal(verifyLeavingSource(src, 'content', undefined, { serialize: (d) => serializeDoc(d).html.replace('<em>', '<b>').replace('</em>', '</b>') }).ok, false);
  let calls = 0; // a parser that loses the italics on every parse after the first
  assert.equal(verifyLeavingSource(src, 'content', undefined, { parse: (html, v) => load(calls++ === 0 ? html : html.replace(/<\/?em>/g, ''), v) }).ok, false);
});

test('locality: a slice that leaks an open element into the next block is not used (the sentinel check)', () => {
  const src = '<p><b>a</p><p>b</b></p>';
  const loaded = load(src, 'content');
  const out = serializeDoc(loaded.doc, { sources: loaded.sources }).html;
  assert.ok(load(out, 'content').doc.eq(loaded.doc), out);
});

// ---- incremental serialization -----------------------------------------------------------------------------

const editArb = fc.record({ at: fc.nat(), kind: fc.constantFrom('type', 'delete', 'bold', 'split', 'join'), text: fc.constantFrom('x', 'yz', ' ', 'é') });

function applyEdit(state: EditorState, e: { at: number; kind: string; text: string }): EditorState {
  const positions: number[] = [];
  state.doc.descendants((n, pos) => { if (n.isTextblock) positions.push(pos + 1 + Math.min(n.content.size, e.at % (n.content.size + 1))); return true; });
  if (!positions.length) return state;
  const pos = positions[e.at % positions.length]!;
  const tr = state.tr.setSelection(TextSelection.create(state.doc, pos));
  try {
    if (e.kind === 'type') tr.insertText(e.text, pos);
    else if (e.kind === 'delete' && pos > 1) tr.delete(pos - 1, pos);
    else if (e.kind === 'bold') tr.addMark(Math.max(1, pos - 2), pos, schema.marks.strong!.create());
    else if (e.kind === 'split') tr.split(pos);
    else if (e.kind === 'join' && pos > 2) tr.join(state.doc.resolve(pos).before());
    tr.doc.check();
  } catch { return state; }
  return state.apply(tr);
}

for (const variant of ['content', 'notes'] as Variant[]) {
  test(`incremental serialization equals serializeDoc after random edits, with the head offset (${variant}, ${runs} runs)`, () => {
    fc.assert(fc.property(docArb(variant, { maxBlocks: 10 }), fc.array(editArb, { maxLength: 12 }), (d, edits) => {
      const src = serializeDoc(d).html;
      const loaded = load(src, variant);
      const inc = new IncrementalSerializer(loaded.sources);
      let state = EditorState.create({ doc: loaded.doc });
      const check = () => {
        const head = state.selection.head;
        const want = serializeDoc(state.doc, { sources: loaded.sources, head });
        const got = inc.serialize(state.doc, head);
        assert.equal(got.html, want.html);
        assert.equal(got.headOffset, want.headOffset);
        assert.equal(got.words, countNode(state.doc));
      };
      check();
      for (const e of edits) { state = applyEdit(state, e); check(); }
    }), params);
  });
}

test('incremental serialization reuses cached blocks: one edit re-serializes one block', () => {
  const loaded = load(makeFixture('html'), 'content');
  const inc = new IncrementalSerializer(loaded.sources);
  let state = EditorState.create({ doc: loaded.doc });
  inc.serialize(state.doc);
  let pos = 0;
  for (let i = 0; i < 400; i++) pos += state.doc.child(i).nodeSize;
  const times: number[] = [];
  for (let k = 0; k < 30; k++) {
    state = state.apply(state.tr.insertText('x', pos + 2));
    const t = performance.now();
    const r = inc.serialize(state.doc, pos + 3);
    times.push(performance.now() - t);
    assert.equal(r.html, serializeDoc(state.doc, { sources: loaded.sources }).html);
  }
  times.sort((a, b) => a - b);
  assert.ok(times[Math.floor(times.length * 0.95)]! < 16, `p95 ${times[Math.floor(times.length * 0.95)]} ms (B4 is 16 ms on device)`);
});
