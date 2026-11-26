// S15 over loaded documents, not just generated ones (T-576g): for every corpus input, in every field variant, the
// canonical serialization of the loaded document parses back to it, modulo what AO3's own cleaning does to preserved
// HTML on its next save (verify.ts, sameDocument). What is left is listed by name: inputs whose reparse changes
// visible structure (orphan <li>/<dd> content, nested anchors, the parser's depth limit). The switch check refuses
// those, so Rich Text can't open them, and nothing is lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { load, schema, serializeDoc } from '../src/index.ts';
import type { Variant } from '../src/index.ts';
import { sameDocument } from '../src/editor/verify.ts';

const corpus = (JSON.parse(readFileSync(new URL('../test/golden/corpus.json', import.meta.url), 'utf8')) as { cases: { id: string; input: string }[] }).cases;

/** Inputs whose reparse changes structure (all fuzz or synthetic): refused by the switch check, on purpose. */
const STRUCTURAL = new Set([
  'li-bare', 'nested-400', 'fuzz-576-74', 'fuzz-576-181', 'fuzz-576-182', 'fuzz-576-383', 'fuzz-576-411', 'fuzz-576-491',
  'fuzz-576-498', 'fuzz-576-569', 'fuzz-576-602', 'fuzz-576-611', 'fuzz-576-640', 'fuzz-576-695', 'fuzz-576-771',
  'fuzz-576-801', 'fuzz-576-832', 'fuzz-576-836', 'fuzz-576-883', 'fuzz-576-909', 'fuzz-576-931', 'fuzz-576-945',
  'fuzz-576-1007', 'fuzz-576-1010', 'fuzz-576-1106', 'fuzz-576-1193',
]);

for (const variant of ['content', 'notes', 'summary'] as Variant[]) {
  test(`S15 on every loaded corpus document (${variant}), modulo AO3's own re-cleaning of preserved HTML`, () => {
    const wrong: string[] = [];
    const stillStructural = new Set<string>();
    let checked = 0;
    for (const c of corpus) {
      let loaded;
      try { loaded = load(c.input, variant); } catch { continue; }
      checked++;
      let ok: boolean;
      try { ok = sameDocument(load(serializeDoc(loaded.doc).html, variant).doc, loaded.doc, variant); } catch { ok = false; }
      if (ok) continue;
      if (STRUCTURAL.has(c.id)) stillStructural.add(c.id);
      else wrong.push(c.id);
    }
    assert.deepEqual(wrong, [], 'new S15 failures');
    assert.ok(checked > 1900);
    // keep the list honest: an entry that now passes should come off it
    assert.ok(stillStructural.size >= STRUCTURAL.size - 2, `listed but passing: ${[...STRUCTURAL].filter((x) => !stillStructural.has(x)).join(' ')}`);
  });
}

test('the fixed-point equality is not lenient about content: different text in preserved HTML still differs', () => {
  const a = load('<p>x</p>\n<table><tr><td>one</td></tr></table>', 'content').doc;
  const b = load('<p>x</p>\n<table><tr><td>two</td></tr></table>', 'content').doc;
  assert.equal(sameDocument(a, b, 'content'), false);
  const c = load('<dd>it’s</dd>', 'content').doc;
  const d = schema.nodes.doc!.create(null, c.content);
  assert.equal(sameDocument(c, d, 'content'), true);
});
