// What the loader remembers about the HTML it was given: source slices for untouched top-level blocks (S16, R2)
// and the caret maps (spec 7.5). Both are computed on first use, never on the keystroke path.
import type { Node as PMNode } from 'prosemirror-model';
import { Selection } from 'prosemirror-state';
import { load } from './load.ts';
import { Kind } from './dom.ts';
import type { N } from './dom.ts';
import { offsetsFor } from './decode.ts';
import { parseBody } from './html5.ts';
import { fixBadCharacters } from './clean.ts';
import { REMOVE_CONTENTS } from './paragraph-maker.ts';
import { POSIX_SPACE, lstrip, rstrip } from './ruby.ts';
import type { Variant } from './sanitize.ts';
import { serializeBlock } from './serialize.ts';
import type { BlockSource, SourceInfo } from './serialize.ts';

const INLINE = new Set(['a', 'abbr', 'acronym', 'b', 'big', 'br', 'cite', 'code', 'del', 'dfn', 'em', 'i', 'img', 'ins', 'kbd', 'q', 'rp', 'rt', 'ruby', 's', 'samp', 'small', 'span', 'strike', 'strong', 'sub', 'sup', 'tt', 'u', 'var', 'button', 'input', 'label', 'map', 'select', 'textarea']);
const SEPARATOR = new RegExp(`[${POSIX_SPACE}]*\\n[${POSIX_SPACE}]*`, 'g');
const PRESERVED = new Set([...REMOVE_CONTENTS, 'table', 'pre', 'dl', 'figure', 'address', 'ruby', 'rt', 'rp', 'audio', 'video', 'source', 'track', 'embed', 'object', 'param', 'dd', 'dt', 'caption', 'colgroup', 'tbody', 'tfoot', 'thead', 'tr', 'td', 'th']);

/** Offsets between the text HTML mode shows (original) and AO3's fix_bad_characters view of it (the slice source). */
type Segment = { f0: number; f1: number; o0: number; o1: number };

function mapFixed(original: string): { text: string; segs: Segment[]; ok: boolean } {
  const lead = original.length - lstrip(original).length;
  const core = rstrip(lstrip(original));
  const segs: Segment[] = [];
  let out = '';
  let i = 0;
  while (i < core.length) {
    const c = core[i]!;
    if (c === '\r') {
      const n = core[i + 1] === '\n' ? 2 : 1;
      segs.push({ f0: out.length, f1: out.length + 1, o0: lead + i, o1: lead + i + n });
      out += '\n'; i += n;
    } else if (c === '<' && core[i + 1] === '3') {
      segs.push({ f0: out.length, f1: out.length + 4, o0: lead + i, o1: lead + i + 1 });
      out += '&lt;'; i++;
    } else { out += c; i++; }
  }
  const text = fixBadCharacters(rstrip(lstrip(original)));
  // spacer markers and lone surrogates change offsets in ways not modelled here: no caret map for those
  const ok = text === out;
  return { text, segs, ok };
}

function fToO(segs: Segment[], lead: number, f: number): number {
  // segments are sorted; between them the mapping is the identity shifted by what came before
  let lo = 0, hi = segs.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (segs[m]!.f0 <= f) lo = m + 1; else hi = m; }
  if (lo === 0) return lead + f;
  const s = segs[lo - 1]!;
  if (f < s.f1) return s.o0;
  return s.o1 + (f - s.f1);
}
function oToF(segs: Segment[], lead: number, o: number): number {
  let lo = 0, hi = segs.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (segs[m]!.o0 <= o) lo = m + 1; else hi = m; }
  if (lo === 0) return Math.max(o - lead, 0);
  const s = segs[lo - 1]!;
  if (o < s.o1) return s.f0;
  return s.f1 + (o - s.o1);
}

type CaretMap = {
  textPos: Int32Array; textStart: Int32Array; textLen: Int32Array; // per doc text node: PM pos, first char index, length
  d2s: Int32Array; d2e: Int32Array; // per doc char: source start/end in F, or -1
  sStart: Int32Array; sDoc: Int32Array; // aligned chars sorted by source offset -> doc char index
};

export class Sources implements SourceInfo {
  readonly original: string;
  readonly text: string; // AO3's fix_bad_characters view of the (stripped) original: slices are cut from this
  private variant: Variant;
  private doc: PMNode;
  private opts: { appUrl?: string };
  private lead: number;
  private segs: Segment[];
  private mapOk: boolean;
  private _blocks: WeakMap<PMNode, BlockSource> | null = null;
  private _caret: CaretMap | null | undefined;

  constructor(original: string, variant: Variant, doc: PMNode, opts: { appUrl?: string }) {
    this.original = original;
    this.variant = variant;
    this.doc = doc;
    this.opts = opts;
    const m = mapFixed(original);
    this.text = m.text;
    this.segs = m.segs;
    this.mapOk = m.ok;
    this.lead = original.length - lstrip(original).length;
  }

  get blocks(): WeakMap<PMNode, BlockSource> {
    if (!this._blocks) this._blocks = this.computeBlocks();
    return this._blocks;
  }

  // ---- locality (S16) ------------------------------------------------------------------------------------

  private computeBlocks(): WeakMap<PMNode, BlockSource> {
    const out = new WeakMap<PMNode, BlockSource>();
    const F = this.text;
    if (F === '' || !this.mapOk) return out;
    const doc = this.doc;
    type Chunk = { start: number; end: number; spacer?: boolean };
    const chunks: Chunk[] = [];
    const top = parseBody(F, { locations: true }).children();
    let run: { start: number; end: number; nodes: N[] } | null = null;
    const flushRun = () => {
      if (!run) return;
      this.splitRun(F, run.nodes, chunks);
      run = null;
    };
    for (const n of top) {
      if (n.kind === Kind.Element && !INLINE.has(n.name)) {
        flushRun();
        chunks.push({ start: n.start, end: n.end });
      } else if (n.start >= 0) {
        if (!run) run = { start: n.start, end: n.end, nodes: [] };
        run.end = n.end;
        run.nodes.push(n);
      }
    }
    flushRun();

    let j = 0;
    for (const c of chunks) {
      if (j >= doc.childCount) break;
      if (c.spacer) {
        const b = doc.child(j);
        if (!(b.type.name === 'paragraph' && b.childCount === 0)) break;
        out.set(b, { start: c.start, end: c.end, index: j, spacer: true });
        j++;
        continue;
      }
      const text = F.slice(c.start, c.end);
      const b = doc.child(j);
      if (text === serializeBlock(b)) { out.set(b, { start: c.start, end: c.end, index: j }); j++; continue; }
      let res: PMNode[];
      try { res = load(text, this.variant, this.opts).doc.content.content.slice(); } catch { break; }
      let ok = j + res.length <= doc.childCount;
      for (let k = 0; ok && k < res.length; k++) ok = res[k]!.eq(doc.child(j + k));
      if (!ok) break; // positions no longer line up: stop rather than guess
      if (res.length === 1) out.set(doc.child(j), { start: c.start, end: c.end, index: j });
      j += res.length;
    }
    return out;
  }

  /** Splits a run of loose top-level nodes at blank lines and <br><br> the way ParagraphMaker would. */
  private splitRun(F: string, nodes: N[], chunks: { start: number; end: number; spacer?: boolean }[]): void {
    let segStart = -1, segEnd = -1;
    const closeSeg = () => {
      if (segStart >= 0) {
        const raw = F.slice(segStart, segEnd);
        const trimmedStart = segStart + (raw.length - raw.replace(/^[ \t\r\n\f]+/, '').length);
        const trimmedEnd = segEnd - (raw.length - raw.replace(/[ \t\r\n\f]+$/, '').length);
        if (trimmedEnd > trimmedStart) chunks.push({ start: trimmedStart, end: trimmedEnd });
      }
      segStart = segEnd = -1;
    };
    const touch = (a: number, b: number) => { if (segStart < 0) segStart = a; segEnd = b; };
    const separate = (newlinesOrBreaks: number, at: number) => {
      closeSeg();
      if (newlinesOrBreaks >= 3) chunks.push({ start: at, end: at, spacer: true });
    };
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]!;
      if (n.kind === Kind.Text) {
        const src = F.slice(n.start, n.end);
        let last = 0;
        for (const m of src.matchAll(SEPARATOR)) {
          const newlines = (m[0].match(/\n/g) ?? []).length;
          if (newlines < 2) continue;
          if (m.index! > last) touch(n.start + last, n.start + m.index!);
          separate(newlines, n.start + m.index! + m[0].length);
          last = m.index! + m[0].length;
        }
        if (last < src.length) touch(n.start + last, n.end);
      } else if (n.kind === Kind.Element && n.name === 'br') {
        let j = i, count = 0, end = n.end;
        while (j < nodes.length) {
          const x = nodes[j]!;
          if (x.kind === Kind.Element && x.name === 'br') { count++; end = x.end; j++; }
          else if (x.kind === Kind.Text && /^[ \t\r\n\f]*$/.test(F.slice(x.start, x.end)) && j + 1 < nodes.length && nodes[j + 1]!.name === 'br') j++;
          else break;
        }
        if (count >= 2) { separate(count, end); i = j - 1; } else touch(n.start, n.end);
      } else touch(n.start, n.end);
    }
    closeSeg();
  }

  // ---- caret maps (spec 7.5) -----------------------------------------------------------------------------

  private caret(): CaretMap | null {
    if (this._caret !== undefined) return this._caret;
    this._caret = this.mapOk ? this.buildCaret() : null;
    return this._caret;
  }

  private buildCaret(): CaretMap | null {
    const F = this.text;
    // doc side
    const tp: number[] = [], ts: number[] = [], tl: number[] = [];
    let chars = 0;
    const docText: string[] = [];
    this.doc.descendants((node, pos) => {
      if (node.isText) { tp.push(pos); ts.push(chars); tl.push(node.text!.length); chars += node.text!.length; docText.push(node.text!); }
      return true;
    });
    const dtext = docText.join('');
    // source side: text nodes of the original parse, outside everything the cleaner drops or the schema preserves
    const root = parseBody(F, { locations: true });
    const oStart: number[] = [], oEnd: number[] = [];
    const oChars: number[] = [];
    const visit = (n: N, skip: boolean) => {
      for (let c = n.first; c; c = c.next) {
        if (c.kind === Kind.Text) {
          if (skip || c.start < 0) continue;
          const { starts, ends } = offsetsFor(F.slice(c.start, c.end), c.text);
          for (let k = 0; k < c.text.length; k++) {
            if (starts[k]! < 0) break;
            oChars.push(c.text.charCodeAt(k));
            oStart.push(c.start + starts[k]!);
            oEnd.push(c.start + ends[k]!);
          }
        } else if (c.kind === Kind.Element) {
          const orphan = (c.name === 'summary' && n.name !== 'details') || (c.name === 'li' && n.name !== 'ul' && n.name !== 'ol');
          visit(c, skip || PRESERVED.has(c.name) || orphan);
        }
      }
    };
    visit(root, false);
    const isSkip = (u: number) => u === 0xa0 || u === 0x20 || (u >= 9 && u <= 13) || u === 0x85 || u === 0x1680 || (u >= 0x2000 && u <= 0x200a) || u === 0x2028 || u === 0x2029 || u === 0x202f || u === 0x205f || u === 0x3000;
    const d2s = new Int32Array(chars).fill(-1), d2e = new Int32Array(chars).fill(-1);
    const sStart: number[] = [], sDoc: number[] = [];
    let o = 0;
    for (let k = 0; k < chars; k++) {
      const u = dtext.charCodeAt(k);
      if (isSkip(u)) continue;
      while (o < oChars.length && (oChars[o] !== u)) o++;
      if (o >= oChars.length) break;
      d2s[k] = oStart[o]!; d2e[k] = oEnd[o]!;
      sStart.push(oStart[o]!); sDoc.push(k);
      o++;
    }
    return { textPos: Int32Array.from(tp), textStart: Int32Array.from(ts), textLen: Int32Array.from(tl), d2s, d2e, sStart: Int32Array.from(sStart), sDoc: Int32Array.from(sDoc) };
  }

  private charToPos(m: CaretMap, k: number): number {
    let lo = 0, hi = m.textStart.length - 1;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (m.textStart[mid]! <= k) lo = mid; else hi = mid - 1; }
    return m.textPos[lo]! + (k - m.textStart[lo]!);
  }

  /** Document position -> offset in `text` (the slice source), or null when the map has nothing near it. */
  docPosToOffset(pos: number): number | null {
    const m = this.caret();
    if (!m || m.textPos.length === 0) return null;
    // first doc char at or after pos
    let lo = 0, hi = m.textPos.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (m.textPos[mid]! + m.textLen[mid]! <= pos) lo = mid + 1; else hi = mid; }
    let k: number;
    if (lo >= m.textPos.length) k = m.d2s.length; // after the last text
    else k = m.textStart[lo]! + Math.max(0, pos - m.textPos[lo]!);
    for (let a = k; a < m.d2s.length && a < k + 64; a++) if (m.d2s[a]! >= 0) return m.d2s[a]!;
    for (let a = k - 1; a >= 0 && a > k - 64; a--) if (m.d2e[a]! >= 0) return m.d2e[a]!;
    return null;
  }

  /** HTML-mode offset (UTF-16, in the original text) -> document position. `found` says whether a text node was near. */
  activate(offset: number): { pos: number; caretFound: boolean } {
    const m = this.caret();
    const end = Selection.atEnd(this.doc).from;
    if (!m) return { pos: end, caretFound: false };
    const f = oToF(this.segs, this.lead, Math.min(Math.max(offset, 0), this.original.length));
    let lo = 0, hi = m.sStart.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (m.sStart[mid]! < f) lo = mid + 1; else hi = mid; }
    if (lo >= m.sStart.length) return { pos: end, caretFound: false };
    return { pos: this.charToPos(m, m.sDoc[lo]!), caretFound: true };
  }

  /** Document position -> offset in the original text (R1: no edit since load), or null. */
  offsetForPos(pos: number): number | null {
    const f = this.docPosToOffset(pos);
    return f === null ? null : Math.min(fToO(this.segs, this.lead, f), this.original.length);
  }
}
