// `node test-web/perf.ts`: editor-side timings on the 510,000-character fixture (Node, no layout; see PERF.md).
import { EditorState } from 'prosemirror-state';
import { load } from '../src/index.ts';
import { IncrementalSerializer } from '../src/editor/incremental.ts';
import { verifyLeavingRich, verifyLeavingSource } from '../src/editor/verify.ts';
import { makeFixture } from '../test/fixture.ts';

const rows: [string, number][] = [];
const time = <T,>(name: string, f: () => T): T => { const t = performance.now(); const r = f(); rows.push([name, performance.now() - t]); return r; };

const src = makeFixture('html');
const loaded = time('load (part 1: clean + parse5 + build)', () => load(src, 'content'));
const inc = new IncrementalSerializer(loaded.sources);
time('word count, first (every block counted once)', () => inc.wordCount(loaded.doc));
time('word count, again (cached per block)', () => inc.wordCount(loaded.doc));
let state = EditorState.create({ doc: loaded.doc });
let pos = 0;
for (let i = 0; i < loaded.doc.childCount / 2; i++) pos += loaded.doc.child(i).nodeSize;
state = state.apply(state.tr.insertText('x', pos + 2));
time('snapshot after one edit, first (computes locality)', () => inc.serialize(state.doc, pos + 3));
state = state.apply(state.tr.insertText('y', pos + 3));
time('snapshot after the next keystroke (one block re-serialized)', () => inc.serialize(state.doc, pos + 4));
time('switch check leaving Rich Text (one edited block)', () => verifyLeavingRich(state.doc, 'content', inc, undefined, new WeakMap()));
const fresh = load(src, 'content');
time('switch check leaving HTML, fresh preload (computes locality)', () => verifyLeavingSource(src, 'content', fresh, new WeakMap()));
time('activate after a switch back (caret through the serializer, no reparse)', () => inc.posForOffset(state.doc, 250_000));

console.log(`fixture: ${src.length} chars, ${loaded.doc.childCount} top-level blocks (node ${process.version}, ${process.platform}/${process.arch})`);
for (const [name, ms] of rows) console.log(`  ${ms.toFixed(1).padStart(8)} ms  ${name}`);
