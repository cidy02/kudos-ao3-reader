// `npm run perf`: timings for the 510,000-character fixture (spec 9.1, 6.10). Prints a table to paste into PERF.md.
import { EditorState } from 'prosemirror-state';
import { load, serialize, serializeDoc, snapshot, activate } from '../src/index.ts';
import { sanitizeValue } from '../src/clean.ts';
import { makeFixture } from './fixture.ts';

export type Timing = { name: string; ms: number };

export function measure(kind: 'html' | 'plain'): { timings: Timing[]; chars: number; blocks: number } {
  const text = makeFixture(kind);
  const timings: Timing[] = [];
  const time = <T,>(name: string, f: () => T): T => { const t = performance.now(); const r = f(); timings.push({ name, ms: performance.now() - t }); return r; };
  time('clean (AO3 port: ParagraphMaker + sanitizer)', () => sanitizeValue('content', text));
  const loaded = time('load (clean + parse5 + build document)', () => load(text, 'content'));
  time('serialize whole document, canonical', () => serialize(loaded.doc));
  time('serialize, no edit, source slices (first call computes locality)', () => serializeDoc(loaded.doc, { sources: loaded.sources }));
  const st = EditorState.create({ doc: loaded.doc });
  const mid = loaded.doc.child(Math.floor(loaded.doc.childCount / 2));
  let from = 0;
  for (let i = 0; i < Math.floor(loaded.doc.childCount / 2); i++) from += loaded.doc.child(i).nodeSize;
  const edited = st.apply(st.tr.insertText('X', from + 1)).doc;
  time('serialize after one edit (slices for untouched blocks)', () => serializeDoc(edited, { sources: loaded.sources, head: from + 2 }));
  time('snapshot, no edit (R1, original bytes + caret map)', () => snapshot(loaded, loaded.doc, { head: from + 2 }));
  time('activate (HTML offset -> position, builds the caret map once)', () => activate(loaded, Math.floor(text.length / 2)));
  time('activate again (map cached)', () => activate(loaded, Math.floor(text.length / 3)));
  void mid;
  return { timings, chars: text.length, blocks: loaded.doc.childCount };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  for (const kind of ['html', 'plain'] as const) {
    const { timings, chars, blocks } = measure(kind);
    console.log(`\n${kind} fixture: ${chars} chars, ${blocks} top-level blocks (node ${process.version}, ${process.platform}/${process.arch})`);
    for (const t of timings) console.log(`  ${t.ms.toFixed(1).padStart(8)} ms  ${t.name}`);
  }
}
