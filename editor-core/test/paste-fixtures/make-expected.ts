// `node test/paste-fixtures/make-expected.ts`: records what the paste cleaner makes of each fixture, for review. The
// expected file is reviewed by hand (every output above was read against the source app's clipboard before freezing).
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { pasteContent } from '../../src/editor/paste.ts';
import { schema, serializeDoc } from '../../src/index.ts';

const dir = new URL('./', import.meta.url);
const expected: Record<string, unknown> = {};
for (const f of readdirSync(dir).filter((f) => f.endsWith('.html')).sort()) {
  const r = pasteContent(readFileSync(new URL(f, dir), 'utf8'), '', 'content')!;
  expected[f] = {
    html: serializeDoc(schema.nodes.doc!.create(null, r.slice.content)).html,
    source: r.source, words: r.words, kept: r.kept, converted: r.converted, styles: r.styles, examples: r.examples,
    dropped: r.loss.dropped,
  };
}
writeFileSync(new URL('expected.json', dir), `${JSON.stringify(expected, null, 2)}\n`);
console.log(`wrote expected.json (${Object.keys(expected).length} fixtures)`);
