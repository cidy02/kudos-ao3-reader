// The switch check (spec 7.11): before a hand-off out of an edited view commits, prove the text survives the trip.
import type { Node as PMNode } from 'prosemirror-model';
import { load, serializeDoc } from '../index.ts';
import type { LoadResult, Variant } from '../index.ts';

export type VerifyResult = { ok: boolean; candidateHtml: string; reason?: string; loaded?: LoadResult };
export type VerifyDeps = {
  serialize?: (doc: PMNode) => string;
  parse?: (html: string, variant: Variant) => LoadResult;
};

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
  const loaded = (deps.parse ?? load)(candidateHtml, variant);
  // S14 follows: the serializer is a function of the document, and the two documents are equal.
  if (!loaded.doc.eq(doc)) return { ok: false, candidateHtml, reason: `parse(serialize(doc)) differs from doc: ${firstDifference(doc, loaded.doc)}` };
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
  const back = parse(canonical, variant).doc;
  if (!back.eq(from.doc)) return { ok: false, candidateHtml: canonical, reason: `parse(serialize(parse(html))) differs: ${firstDifference(from.doc, back)}` };
  const local = serializeDoc(from.doc, { sources: from.sources }).html;
  if (local !== canonical && !parse(local, variant).doc.eq(from.doc)) {
    return { ok: false, candidateHtml: local, reason: `the source-slice serialization does not parse back: ${firstDifference(from.doc, parse(local, variant).doc)}` };
  }
  return { ok: true, candidateHtml: canonical, loaded: from };
}
