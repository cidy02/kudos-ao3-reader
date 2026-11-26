import { test } from 'node:test';
import assert from 'node:assert/strict';
import fc from 'fast-check';
import { EditorState } from 'prosemirror-state';
import type { Node as PMNode } from 'prosemirror-model';
import { sanitizeValue } from '../src/clean.ts';
import { load, parse, parseCleaned } from '../src/load.ts';
import { schema } from '../src/schema.ts';
import { serializeBlock, serializeDoc } from '../src/serialize.ts';
import { snapshotHtml } from '../src/index.ts';
import { docArb } from './arb.ts';
import type { Variant } from '../src/sanitize.ts';

// Seeded and reproducible: FC_SEED=<n> replays a failure (fast-check prints the seed and path with the counterexample).
const seed = Number(process.env.FC_SEED ?? 576576);
const runs = Number(process.env.FC_RUNS ?? 1000);
console.log(`property tests: seed=${seed} runs=${runs} (set FC_SEED / FC_RUNS to change)`);
const params = { seed, numRuns: runs, endOnFailure: false };

for (const variant of ['content', 'notes', 'summary'] as Variant[]) {
  test(`S14 idempotence (${variant}): serialize(parse(serialize(d))) == serialize(d)`, () => {
    fc.assert(fc.property(docArb(variant), (d) => {
      const s1 = serializeDoc(d).html;
      const loaded = load(s1, variant);
      assert.equal(serializeDoc(loaded.doc).html, s1, 'without source slices');
      assert.equal(serializeDoc(loaded.doc, { sources: loaded.sources }).html, s1, 'with source slices');
    }), params);
  });

  test(`S15 AO3 stability (${variant}): cleaning serialize(d) and parsing gives d`, () => {
    fc.assert(fc.property(docArb(variant), (d) => {
      const s = serializeDoc(d).html;
      assert.ok(parse(s, variant).eq(d), `parse(clean(serialize(d))) differs from d\n${s}\n${JSON.stringify(d.toJSON())}\n${parse(s, variant).toString()}`);
      assert.ok(parseCleaned(sanitizeValue(variant, s)).eq(d), 'build of the cleaned HTML differs from d');
    }), params);
  });
}

test('S16 locality: untouched blocks are written from their source slices', () => {
  fc.assert(fc.property(docArb('content', { maxBlocks: 8 }), fc.nat(), fc.string({ unit: fc.constantFrom(...'abcdef xyz'.split('')), minLength: 1, maxLength: 10 }).filter((s) => s.trim() === s), (d, pick, word) => {
    const blocks: string[] = [];
    d.forEach((c) => blocks.push(serializeBlock(c)));
    const s = blocks.join('\n');
    const loaded = load(s, 'content');
    const j = pick % loaded.doc.childCount;
    let from = 0;
    for (let i = 0; i < j; i++) from += loaded.doc.child(i).nodeSize;
    const old = loaded.doc.child(j);
    const state = EditorState.create({ doc: loaded.doc });
    const replacement = schema.nodes.paragraph!.create(null, schema.text(word));
    const edited = state.apply(state.tr.replaceWith(from, from + old.nodeSize, replacement)).doc;
    const want = blocks.slice();
    want[j] = serializeBlock(replacement);
    assert.equal(serializeDoc(edited, { sources: loaded.sources }).html, want.join('\n'));
    // and with no edit nothing is rewritten
    assert.equal(serializeDoc(loaded.doc, { sources: loaded.sources }).html, s);
  }), params);
});

test('R2 on non-canonical text: edits rewrite only the blocks they touch', () => {
  const src = 'First plain paragraph with <b>bold</b>.\n\nSecond plain paragraph\nwith a soft break.\n\n\nAfter a long gap.\n<P ALIGN=center>Shouting   tag</P>\n<blockquote>Quoted\n\nstuff</blockquote>\n<table><tr><td>cell</td></tr></table>\nTail text';
  const loaded = load(src, 'content');
  assert.equal(loaded.doc.childCount, 8);
  const p = loaded.doc.child(1);
  assert.equal(p.textContent, 'Second plain paragraphwith a soft break.');
  const state = EditorState.create({ doc: loaded.doc });
  let from = loaded.doc.child(0).nodeSize;
  const tr = state.tr.insertText('EDIT ', from + 1);
  const out = serializeDoc(state.apply(tr).doc, { sources: loaded.sources }).html;
  assert.ok(out.startsWith('First plain paragraph with <b>bold</b>.\n\n<p>EDIT Second plain paragraph<br>with a soft break.</p>\n<p>&nbsp;</p>\n'), out);
  assert.ok(out.includes('<P ALIGN=center>Shouting   tag</P>\n<blockquote>Quoted\n\nstuff</blockquote>\n<table><tr><td>cell</td></tr></table>\nTail text'), out);
});

test('R1 no-op round trip: an unchanged document hands back the exact input text', () => {
  const inputs = ['', 'plain', 'a\r\nb\r\n\r\nc', '<p>x</p>\n\n\n<p>y</p>  ', '  <B>x</B> <font color=red>y</font><script>1</script>  ', 'x &amp; <3 ____spacer____'];
  fc.assert(fc.property(fc.oneof(fc.constantFrom(...inputs), fc.string({ maxLength: 60 }), docArb('content').map((d) => serializeDoc(d).html)), (x) => {
    const loaded = load(x, 'content');
    assert.equal(snapshotHtml(loaded, loaded.doc), x);
    const again = load(x, 'content');
    assert.equal(snapshotHtml(loaded, again.doc), x, 'an equal document is "no edit" too');
  }), params);
});

test('every generated document is valid for the schema', () => {
  fc.assert(fc.property(docArb('content'), (d: PMNode) => { d.check(); }), { ...params, numRuns: 200 });
});
