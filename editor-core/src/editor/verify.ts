// The switch check (spec 7.11): before a hand-off out of an edited view commits, prove the text survives the trip.
//
// Untouched blocks go out as their source slices. Once per load the slice layout itself is proven: the unedited
// serialization is the source text (free, and true for every realistic chapter), or else it reparses to the
// document (one parse, for malformed input). With a sound layout only the blocks rich mode writes itself can change
// the text, and each of those is reparsed together with its neighbours (where the parser and ParagraphMaker can
// carry anything across a block boundary). That is O(edited blocks) per switch instead of a full reparse, which a
// 510,000-character chapter can't afford within B11 (150 ms). Results are cached per block and neighbours. A layout
// that is not sound (the parser moved content, as foster parenting out of a broken table does) falls back to the
// full reparse for that document.
import { Fragment } from 'prosemirror-model';
import type { Node as PMNode } from 'prosemirror-model';
import { load, sanitizeValue, schema } from '../index.ts';
import type { LoadResult, Variant } from '../index.ts';
import { IncrementalSerializer } from './incremental.ts';
import type { BlockSerializer, Serialized } from './incremental.ts';

export type VerifyResult = { ok: boolean; candidateHtml: string; reason?: string };
export type VerifyDeps = {
  /** A stand-in parser (tests: a broken one must be caught). */
  parse?: (html: string, variant: Variant) => LoadResult;
  /** A stand-in block serializer (tests: a broken one must be caught). */
  blocks?: BlockSerializer;
};
/** Blocks already proven, with the neighbours they were proven next to. */
export type Proven = WeakMap<PMNode, [PMNode | null, PMNode | null]>;

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

/**
 * AO3's cleaning is not idempotent on some preserved HTML: saving its own output again changes it once more (an
 * orphan <dd> or <li> gains <p> wrappers, for example), so a preserved source can come back from a reparse with
 * different bytes. Rich Text shows preserved HTML as a locked chip and writes its bytes unchanged, so what AO3 then
 * does to them is what it does to the same text saved from HTML mode. Two preserved sources are therefore the same
 * when AO3's cleaning brings both to the same fixed point.
 */
const fixedPoints = new Map<string, string>();
function fixedPoint(source: string, variant: Variant): string {
  const key = `${variant}\u0000${source}`;
  let out = fixedPoints.get(key);
  if (out === undefined) {
    out = source;
    for (let i = 0; i < 4; i++) {
      let next: string;
      try { next = sanitizeValue(variant, out); } catch { break; }
      if (next === out) break;
      out = next;
    }
    if (fixedPoints.size > 2000) fixedPoints.clear();
    fixedPoints.set(key, out);
  }
  return out;
}

function sameModuloPreserved(a: PMNode, b: PMNode, variant: Variant): boolean {
  if (a === b) return true;
  if (a.type !== b.type) return false;
  if (a.type === schema.nodes.raw_block || a.type === schema.nodes.raw_inline) {
    if (!a.sameMarkup(b)) {
      const sa = String(a.attrs.source ?? ''), sb = String(b.attrs.source ?? '');
      if (!(fixedPoint(sa, variant) === fixedPoint(sb, variant) && a.marks.length === b.marks.length && a.marks.every((m, i) => m.eq(b.marks[i]!)))) return false;
    }
    return true;
  }
  if (a.isText) return a.eq(b);
  if (!a.sameMarkup(b) || a.childCount !== b.childCount) return false;
  for (let i = 0; i < a.childCount; i++) if (!sameModuloPreserved(a.child(i), b.child(i), variant)) return false;
  return true;
}

/** `parsed` is the editor's document `edited`, as AO3 will see it (modulo list-item edge spaces and preserved HTML AO3 re-cleans). */
export function sameDocument(parsed: PMNode, edited: PMNode, variant?: Variant): boolean {
  if (parsed.eq(edited)) return true;
  const trimmed = trimListEdges(edited);
  if (parsed.eq(trimmed)) return true;
  return variant !== undefined && sameModuloPreserved(parsed, trimmed, variant);
}

/** Index and both versions of the first top-level block that differs, for the log that becomes a golden fixture. */
function firstDifference(want: PMNode, got: PMNode, offset = 0): string {
  const n = Math.max(want.childCount, got.childCount);
  for (let i = 0; i < n; i++) {
    const a = i < want.childCount ? want.child(i) : null;
    const b = i < got.childCount ? got.child(i) : null;
    if (!a || !b || !a.eq(b)) return `block ${offset + i}: expected ${a ? a.toString() : 'nothing'}, got ${b ? b.toString() : 'nothing'}`;
  }
  return 'documents differ';
}

const POSIX_EDGES = /^[ \t\n\v\f\r]+|[ \t\n\v\f\r]+$/g;

/** Whether the untouched-block slices of `loaded` reassemble into its document in place (see the top of the file). */
export function layoutIsSound(loaded: LoadResult, variant: Variant, inc: IncrementalSerializer, deps: VerifyDeps = {}): boolean {
  const unedited = inc.serialize(loaded.doc).html;
  if (unedited === loaded.sources.text.replace(POSIX_EDGES, '')) return true;
  try { return sameDocument((deps.parse ?? load)(unedited, variant).doc, loaded.doc, variant); } catch { return false; }
}

/** The whole output, reparsed: for documents whose slice layout is not sound. */
function checkWhole(doc: PMNode, variant: Variant, out: Serialized, deps: VerifyDeps): string | null {
  let back: PMNode;
  try { back = (deps.parse ?? load)(out.html, variant).doc; } catch (e) { return `the reparse failed (${String(e)})`; }
  return sameDocument(back, doc, variant) ? null : firstDifference(trimListEdges(doc), back);
}

/** Reparses every block of `out` that rich mode wrote itself, with its neighbours. Null when all match. */
export function checkWrittenBlocks(doc: PMNode, variant: Variant, out: Serialized, proven: Proven, deps: VerifyDeps = {}): string | null {
  const parse = deps.parse ?? load;
  const segs = out.segments;
  const n = doc.childCount;
  for (let i = 0; i < n; i++) {
    if (segs[i]!.source) continue;
    const block = doc.child(i);
    const before = i > 0 ? doc.child(i - 1) : null;
    const after = i + 1 < n ? doc.child(i + 1) : null;
    const seen = proven.get(block);
    if (seen && seen[0] === before && seen[1] === after) continue;
    const a = Math.max(0, i - 1), z = Math.min(n - 1, i + 1);
    const kids: PMNode[] = [];
    for (let k = a; k <= z; k++) kids.push(doc.child(k));
    const expected = doc.type.create(doc.attrs, kids);
    let back: PMNode;
    try { back = parse(out.html.slice(segs[a]!.start, segs[z]!.end), variant).doc; } catch (e) { return `block ${i}: the reparse failed (${String(e)})`; }
    if (!sameDocument(back, expected, variant)) return firstDifference(trimListEdges(expected), back, a);
    proven.set(block, [before, after]);
  }
  return null;
}

/**
 * Leaving Rich Text: what rich mode writes must parse back to its document (S15, and with it S14). `html`, when
 * given, is what the native side holds from `snapshot`; it must be the current serialization.
 */
export function verifyLeavingRich(doc: PMNode, variant: Variant, inc: IncrementalSerializer, html: string | undefined, proven: Proven, deps: VerifyDeps = {}, soundLayout = true): VerifyResult {
  const out = inc.serialize(doc);
  if (html !== undefined && html !== out.html) return { ok: false, candidateHtml: out.html, reason: 'the snapshot the native side holds is not the current serialization' };
  const lost = soundLayout ? checkWrittenBlocks(doc, variant, out, proven, deps) : checkWhole(doc, variant, out, deps);
  return lost ? { ok: false, candidateHtml: out.html, reason: `parse(serialize(doc)) differs from doc at ${lost}` } : { ok: true, candidateHtml: out.html };
}

/**
 * Leaving HTML: the document load built (the one its loss report described) must be one rich mode can write back.
 * Unedited, it hands back the original bytes (R1); edited, untouched blocks go out as their slices, so what has to
 * hold is that the slice layout is sound and every block with no slice (written canonically) reparses in place.
 * `sound` reports the layout verdict, which the way out of Rich Text reuses.
 */
export function verifyLeavingSource(html: string, variant: Variant, loaded: LoadResult | undefined, proven: Proven, deps: VerifyDeps = {}, inc?: IncrementalSerializer): VerifyResult & { sound: boolean } {
  const from = loaded && loaded.sources.original === html ? loaded : (deps.parse ?? load)(html, variant);
  const ser = inc && from === loaded && !deps.blocks ? inc : new IncrementalSerializer(from.sources, deps.blocks);
  const out = ser.serialize(from.doc);
  const sound = layoutIsSound(from, variant, ser, deps);
  const lost = sound ? checkWrittenBlocks(from.doc, variant, out, proven, deps) : 'the untouched blocks do not reassemble into the document';
  return lost ? { ok: false, candidateHtml: out.html, reason: `rich mode could not write this text back unchanged: ${lost}`, sound } : { ok: true, candidateHtml: out.html, sound };
}
