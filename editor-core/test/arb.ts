// fast-check generators for valid, canonical-stable documents (what the editor can produce).
import fc from 'fast-check';
import type { Mark, Node as PMNode } from 'prosemirror-model';
import { MARK_TAGS, schema } from '../src/schema.ts';
import { load } from '../src/load.ts';
import type { Variant } from '../src/sanitize.ts';

const textChars = fc.constantFrom(...Array.from('abcxyz ABC019 .,;:!?-_()"\'&<>é日本語😀 '));
const wordArb = fc.string({ unit: textChars, minLength: 1, maxLength: 12 }).filter((s) => s !== ' ' && !/^ +$/.test(s));
const spacer = fc.constant('a____spacer____b');
export const textArb = fc.oneof({ weight: 12, arbitrary: wordArb }, { weight: 1, arbitrary: spacer });

const valueChars = fc.constantFrom(...Array.from('abcxyz 019&<>"é日本 .-'));
const attrValue = fc.string({ unit: valueChars, minLength: 1, maxLength: 8 });
const urlValue = fc.constantFrom('http://x.org/a?b=1&c=2', 'https://example.org/path/', '/relative/page', '#frag', 'mailto:a@b.co', 'ftp://x.org/f', 'rel/page.html');
const citeValue = fc.constantFrom('http://x.org/q?a=1&b=2', 'https://example.org/quote', '/rel/quote', 'rel-quote');
const classValue = fc.array(fc.constantFrom('dialogue', 'skin-glow', 'a1', 'note_x', 'AB'), { minLength: 1, maxLength: 2 }).map((a) => [...new Set(a)].join(' '));

const globalAttrs = (variant: Variant) => fc.record({
  align: fc.option(fc.constantFrom('left', 'center', 'right', 'justify'), { nil: null, freq: 8 }),
  dir: fc.option(fc.constantFrom('rtl', 'ltr'), { nil: null, freq: 12 }),
  lang: fc.option(fc.constantFrom('en', 'ja', 'ar'), { nil: null, freq: 12 }),
  title: fc.option(attrValue, { nil: null, freq: 10 }),
  class: variant === 'summary' ? fc.constant(null) : fc.option(classValue, { nil: null, freq: 8 }),
});

function markArb(type: string, variant: Variant): fc.Arbitrary<Mark> {
  const tag = fc.constantFrom(...MARK_TAGS[type]!);
  const g = globalAttrs(variant);
  const plain = fc.record({ tag, g }).map(({ tag: t, g: ga }) => schema.marks[type]!.create({ tag: t, ...ga }));
  switch (type) {
    case 'link': return fc.record({ href: fc.option(urlValue, { nil: null, freq: 4 }), name: fc.option(fc.constantFrom('n1', 'top'), { nil: null, freq: 4 }), g }).map(({ href, name, g: ga }) => schema.marks.link!.create({ tag: 'a', href, name, ...ga }));
    case 'span': return fc.record({ g }).map(({ g: ga }) => schema.marks.span!.create({ tag: 'span', ...ga, lang: ga.lang ?? 'en' }));
    case 'phrase': return fc.record({ tag, cite: citeValue, g }).map(({ tag: t, cite, g: ga }) => schema.marks.phrase!.create({ tag: t, cite: t === 'q' ? cite : null, ...ga }));
    default: return plain;
  }
}

const markSetArb = (variant: Variant): fc.Arbitrary<readonly Mark[]> =>
  fc.subarray(Object.keys(MARK_TAGS), { maxLength: 3 }).chain((types) =>
    (types.length === 0 ? fc.constant([] as Mark[]) : fc.tuple(...(types.map((t) => markArb(t, variant)) as [fc.Arbitrary<Mark>]))).map((ms) => ms.reduce<readonly Mark[]>((set, m) => m.addToSet([...set]), [])));

const imageArb = (variant: Variant) => fc.record({ w: fc.option(fc.constantFrom('10', '200'), { nil: null }), alt: fc.option(attrValue, { nil: null }), g: globalAttrs(variant) }).map(({ w, alt, g }) =>
  schema.nodes.image!.create({ src: 'http://x.org/p.png', alt, width: w, ...g }));

/** Raw snippets whose `source` is exactly what the cleaner emits, taken from real loads. */
function rawPool(variant: Variant): { block: PMNode[]; inline: PMNode[] } {
  const nodes: PMNode[] = [];
  const samples = ['<table><tr><td>a</td><td>b &amp; c</td></tr></table>', '<pre>  x\n   y</pre>', '<dl><dt>t</dt><dd>d</dd></dl>', '<figure><img src="http://x.org/a.png"><figcaption>c</figcaption></figure>', '<address>Me<br>Here</address>',
    '<p><a name="ch1"></a>x</p>', '<p>a<span class="skin"></span>b</p>', '<p><ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby></p>'];
  for (const s of samples) load(s, variant).doc.descendants((n) => { if (n.type.name.startsWith('raw_')) nodes.push(n); });
  return { block: nodes.filter((n) => n.type.name === 'raw_block'), inline: nodes.filter((n) => n.type.name === 'raw_inline') };
}

export function docArb(variant: Variant = 'content', opts: { maxBlocks?: number } = {}): fc.Arbitrary<PMNode> {
  const pool = rawPool(variant);
  const g = globalAttrs(variant);
  const inlineNode = (): fc.Arbitrary<PMNode> => fc.oneof(
    { weight: 10, arbitrary: fc.tuple(textArb, markSetArb(variant)).map(([t, m]) => schema.text(t, m)) },
    { weight: 1, arbitrary: fc.tuple(imageArb(variant), markSetArb(variant)).map(([i, m]) => i.mark(m)) },
    { weight: 1, arbitrary: fc.tuple(fc.constantFrom(...pool.inline), markSetArb(variant)).map(([r, m]) => r.mark(m.filter((x) => x.type.name !== 'link'))) },  // (an anchor cannot nest in an anchor)
    { weight: 2, arbitrary: markSetArb(variant).map((m) => schema.nodes.hard_break!.create(null, null, m)) },
  );
  // inline content: no two hard breaks in a row (S10)
  const inlineContent = (min: number, max: number): fc.Arbitrary<PMNode[]> => fc.array(inlineNode(), { minLength: min, maxLength: max }).map((ns) => ns.filter((n, i) => !(n.type.name === 'hard_break' && i > 0 && ns[i - 1]!.type.name === 'hard_break')));
  const paragraph = (implicit = false) => fc.record({ c: inlineContent(0, 5), g }).map(({ c, g: ga }) => schema.nodes.paragraph!.create({ implicit, ...ga }, c));
  const leaf = (): fc.Arbitrary<PMNode> => fc.oneof(
    { weight: 8, arbitrary: paragraph() },
    { weight: 2, arbitrary: fc.record({ level: fc.integer({ min: 1, max: 6 }), c: inlineContent(0, 3), g }).map(({ level, c, g: ga }) => schema.nodes.heading!.create({ level, ...ga }, c)) },
    { weight: 1, arbitrary: fc.record({ width: fc.option(fc.constantFrom('50%', '100'), { nil: null }), g }).map(({ width, g: ga }) => schema.nodes.horizontal_rule!.create({ width, ...ga })) },
    { weight: 1, arbitrary: fc.constantFrom(...pool.block) },
  );
  const { tree } = fc.letrec((tie) => ({
    tree: fc.oneof({ depthSize: 'small', withCrossShrink: true }, leaf(), tie('quote'), tie('list'), tie('details'), tie('container')),
    blocks: fc.array(tie('tree') as fc.Arbitrary<PMNode>, { minLength: 1, maxLength: 3 }),
    quote: fc.record({ cite: fc.option(citeValue, { nil: null, freq: 4 }), g, kids: tie('blocks') as fc.Arbitrary<PMNode[]> }).map(({ cite, g: ga, kids }) => schema.nodes.blockquote!.create({ cite, ...ga }, kids)),
    container: fc.record({ tag: fc.constantFrom('div', 'center'), g, kids: tie('blocks') as fc.Arbitrary<PMNode[]> }).map(({ tag, g: ga, kids }) => schema.nodes.container!.create({ tag, ...ga }, kids)),
    details: fc.record({ open: fc.boolean(), sum: fc.option(inlineContent(0, 3), { nil: null }), g, kids: fc.array(tie('tree') as fc.Arbitrary<PMNode>, { minLength: 0, maxLength: 2 }) })
      .filter(({ sum, kids }) => sum !== null || kids.length > 0)
      .map(({ open, sum, g: ga, kids }) => schema.nodes.details!.create({ open, ...ga }, [...(sum ? [schema.nodes.summary!.create(null, sum)] : []), ...kids])),
    list: fc.record({
      ordered: fc.boolean(), start: fc.option(fc.constantFrom('3', '10'), { nil: null }), type: fc.option(fc.constantFrom('a', 'I'), { nil: null }), g,
      items: fc.array(fc.record({ first: fc.tuple(fc.boolean(), inlineContent(0, 3)), rest: fc.array(tie('tree') as fc.Arbitrary<PMNode>, { maxLength: 1 }), g }), { minLength: 1, maxLength: 3 }),
    }).map(({ ordered, start, type, g: ga, items }) => {
      // an empty implicit paragraph in front of a paragraph is the same list item as one that starts with that paragraph
      const trim = (ns: PMNode[]): PMNode[] => {
        const o = ns.slice();
        while (o[0]?.isText) { const t = o[0].text!.replace(/^ +/, ''); if (t === o[0].text) break; if (t) { o[0] = schema.text(t, o[0].marks); break; } o.shift(); }
        for (let l = o[o.length - 1]; l?.isText; l = o[o.length - 1]) { const t = l.text!.replace(/ +$/, ''); if (t === l.text) break; if (t) { o[o.length - 1] = schema.text(t, l.marks); break; } o.pop(); }
        return o;
      };
      const lis = items.map(({ first: [implicit, c0], rest, g: lg }) => { const c = implicit ? trim(c0) : c0; return schema.nodes.list_item!.create(lg, [schema.nodes.paragraph!.create({ implicit: implicit && !(c.length === 0 && rest[0]?.type.name === 'paragraph') && !(c.length > 0 && c.every((x) => x.isText && /^[ ]*$/.test(x.text!))) }, c), ...rest]); });
      return ordered ? schema.nodes.ordered_list!.create({ start, type, ...ga }, lis) : schema.nodes.bullet_list!.create({ type, ...ga }, lis);
    }),
  }));
  return fc.array(tree as fc.Arbitrary<PMNode>, { minLength: 1, maxLength: opts.maxBlocks ?? 6 }).map((kids) => schema.nodes.doc!.create(null, kids));
}
