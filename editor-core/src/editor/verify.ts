// The switch check (spec 7.11): before a hand-off out of an edited view commits, prove the text survives the trip.
import { Fragment } from 'prosemirror-model';
import type { Node as PMNode } from 'prosemirror-model';
import { load, schema, serializeDoc } from '../index.ts';
import type { LoadResult, Variant } from '../index.ts';

export type VerifyResult = { ok: boolean; candidateHtml: string; reason?: string; loaded?: LoadResult };
export type VerifyDeps = {
  serialize?: (doc: PMNode) => string;
  parse?: (html: string, variant: Variant) => LoadResult;
};

/**
 * The builder trims spaces and tabs at the edges of a list item's own text (`<li> x </li>` is `x`: the space collapses
 * in HTML), so a writer who types a trailing space in a list item gets back the same item without it. Equality for the
 * switch check is therefore modulo that trim, applied to the editor's side exactly as build.ts applies it on load.
 */
export function trimListEdges(node: PMNode): PMNode {
  if (node.type === schema.nodes.paragraph && node.attrs.implicit) {
    const kids: PMNode[] = [];
    node.forEach((c) => kids.push(c));
    let changed = false;
    while (kids[0]?.isText) {
      const t = kids[0].text!.replace(/^[ \t]+/, '');
      if (t === kids[0].text) break;
      changed = true;
      if (t) { kids[0] = schema.text(t, kids[0].marks); break; }
      kids.shift();
    }
    for (let l = kids[kids.length - 1]; l?.isText; l = kids[kids.length - 1]) {
      const t = l.text!.replace(/[ \t]+$/, '');
      if (t === l.text) break;
      changed = true;
      if (t) { kids[kids.length - 1] = schema.text(t, l.marks); break; }
      kids.pop();
    }
    return changed ? node.copy(Fragment.from(kids)) : node;
  }
  if (node.isLeaf || node.inlineContent) return node;
  let changed = false;
  const kids: PMNode[] = [];
  node.forEach((c) => { const t = trimListEdges(c); if (t !== c) changed = true; kids.push(t); });
  return changed ? node.copy(Fragment.from(kids)) : node;
}

/** `a` (a parse) is the document `b` (the editor's), as AO3 will see it. */
export const sameDocument = (parsed: PMNode, edited: PMNode): boolean => parsed.eq(edited) || parsed.eq(trimListEdges(edited));

/** Index and both versions of the first top-level block that differs, for the log that becomes a golden fixture. */
function firstDifference(want: PMNode, got: PMNode): string {
  const n = Math.max(want.childCount, got.childCount);
  for (let i = 0; i < n; i++) {
    const a = i < want.childCount ? want.child(i) : null;
    const b = i < got.childCount ? got.child(i) : null;
    if (!a || !b || !a.eq(b)) return `block ${i}: expected ${a ? a.toString() : 'nothing'}, got ${b ? b.toString() : 'nothing'}`;
  }
  return 'documents differ';
}

/**
 * Leaving Rich Text: parse(serialize(doc)) must equal doc (S15, and with it S14).
 * `html`, when given, is what the native side received from `snapshot`; it must be that serialization.
 * On success `loaded` is the parse of the new HTML-mode text, so a later switch back maps carets through it.
 */
export function verifyLeavingRich(doc: PMNode, variant: Variant, serialize: (doc: PMNode) => string, html?: string, deps: VerifyDeps = {}): VerifyResult {
  const candidateHtml = (deps.serialize ?? serialize)(doc);
  if (html !== undefined && html !== candidateHtml) return { ok: false, candidateHtml, reason: 'the snapshot the native side holds is not the current serialization' };
  let loaded: LoadResult;
  try { loaded = (deps.parse ?? load)(candidateHtml, variant); } catch (e) { return { ok: false, candidateHtml, reason: `parse(serialize(doc)) failed: ${String(e)}` }; }
  // S14 follows: the serializer is a function of the document, and the two documents are equal.
  if (!sameDocument(loaded.doc, doc)) return { ok: false, candidateHtml, reason: `parse(serialize(doc)) differs from doc: ${firstDifference(trimListEdges(doc), loaded.doc)}` };
  return { ok: true, candidateHtml, loaded };
}

/**
 * Leaving HTML: the document that load built (the one its loss report described) must survive serialize then parse,
 * both canonically and as rich mode will write it (untouched blocks from their source slices).
 */
export function verifyLeavingSource(html: string, variant: Variant, loaded?: LoadResult, deps: VerifyDeps = {}): VerifyResult {
  const parse = deps.parse ?? load;
  const from = loaded && loaded.sources.original === html ? loaded : parse(html, variant);
  const canonical = deps.serialize ? deps.serialize(from.doc) : serializeDoc(from.doc).html;
  const survives = (out: string): string | null => {
    try {
      const back = parse(out, variant).doc;
      return back.eq(from.doc) ? null : firstDifference(from.doc, back);
    } catch (e) { return `reparse failed: ${String(e)}`; }
  };
  const lost = survives(canonical);
  if (lost) return { ok: false, candidateHtml: canonical, reason: `parse(serialize(parse(html))) differs: ${lost}` };
  const local = serializeDoc(from.doc, { sources: from.sources }).html;
  const lostLocal = local === canonical ? null : survives(local);
  if (lostLocal) return { ok: false, candidateHtml: local, reason: `the source-slice serialization does not parse back: ${lostLocal}` };
  return { ok: true, candidateHtml: canonical, loaded: from };
}
