// Incremental serialization and word counts (spec 9.4, S16, R2). Blocks unchanged since load are written from their
// source slices; edited blocks are serialized once per node object and cached, so a checkpoint after one keystroke
// serializes one block and joins the rest. Output is byte-identical to serializeDoc (roundtrip.test.ts checks).
// It also maps an offset in its own output back to a document position (the caret when HTML mode hands back text
// it got from here), by binary search inside one block, so no switch needs a full reparse.
import type { Node as PMNode } from 'prosemirror-model';
import { serializeBlock, serializeBlockAt } from '../index.ts';
import type { BlockSource, SourceInfo } from '../index.ts';
import { countNode } from './words.ts';

/** Where each top-level block landed in the output; `source` when it was written from its source slice. */
export type Segment = { start: number; end: number; pos: number; source: BlockSource | undefined };
export type Serialized = { html: string; headOffset: number | null; words: number; segments: Segment[] };
export type BlockSerializer = { block: (node: PMNode) => string; blockAt: (node: PMNode, head: number) => { html: string; headOffset: number | null } };
const PART1: BlockSerializer = { block: serializeBlock, blockAt: serializeBlockAt };

export class IncrementalSerializer {
  readonly sources: SourceInfo | undefined;
  private readonly ser: BlockSerializer;
  private html = new WeakMap<PMNode, string>();
  private words = new WeakMap<PMNode, number>();
  private last: { doc: PMNode; out: Serialized } | null = null;

  constructor(sources?: SourceInfo, ser: BlockSerializer = PART1) {
    this.sources = sources;
    this.ser = ser;
  }

  blockWords(node: PMNode): number {
    let n = this.words.get(node);
    if (n === undefined) this.words.set(node, (n = countNode(node)));
    return n;
  }

  wordCount(doc: PMNode): number {
    let n = 0;
    doc.forEach((child) => { n += this.blockWords(child); });
    return n;
  }

  private blockHtml(node: PMNode): string {
    let s = this.html.get(node);
    if (s === undefined) this.html.set(node, (s = this.ser.block(node)));
    return s;
  }

  /** The output offset of a head position inside the block at `seg` (the same rule serializeDoc uses). */
  private headIn(child: PMNode, seg: Segment, head: number): number | null {
    const bs = seg.source;
    if (!bs) {
      const one = this.ser.blockAt(child, head - seg.pos);
      return seg.start + (one.headOffset ?? one.html.length);
    }
    const src = this.sources!;
    // the load's source map works in loaded-document positions: translate through the block's own start
    const off = src.docPosToOffset?.(src.blockStart ? src.blockStart(bs.index) + (head - seg.pos) : head);
    return off !== null && off !== undefined ? seg.start + Math.min(Math.max(off - bs.start, 0), bs.end - bs.start) : head === seg.pos ? seg.start : null;
  }

  serialize(doc: PMNode, head?: number): Serialized {
    const src = this.sources;
    // Same spacer rule as serializeDoc: a blank paragraph between blank lines is only written from source when both
    // of its neighbours are too. shortcut: duplicated from serialize.ts; a block cache in serializeDoc would remove it.
    const eff: (BlockSource | undefined)[] = [];
    doc.forEach((c) => eff.push(src?.blocks.get(c)));
    eff.forEach((e, i) => {
      if (!e?.spacer) return;
      const a = eff[i - 1], z = eff[i + 1];
      if (!(a && z && !a.spacer && !z.spacer && a.index + 1 === e.index && e.index + 1 === z.index)) eff[i] = undefined;
    });
    const parts: string[] = [];
    const segments: Segment[] = [];
    let len = 0;
    let headOffset: number | null = null;
    let words = 0;
    let pos = 0;
    let prev: BlockSource | undefined;
    const push = (s: string) => { parts.push(s); len += s.length; };
    doc.forEach((child, _o, i) => {
      const bs = eff[i];
      if (i > 0) push(prev && bs && prev.index + 1 === bs.index ? src!.text.slice(prev.end, bs.start) : '\n');
      const seg: Segment = { start: len, end: len, pos, source: bs };
      const holdsHead = head !== undefined && headOffset === null && head >= pos && head <= pos + child.nodeSize;
      if (bs) {
        if (holdsHead) headOffset = this.headIn(child, seg, head);
        push(src!.text.slice(bs.start, bs.end));
      } else if (holdsHead) {
        const one = this.ser.blockAt(child, head - pos);
        this.html.set(child, one.html);
        headOffset = seg.start + (one.headOffset ?? one.html.length);
        push(one.html);
      } else push(this.blockHtml(child));
      seg.end = len;
      segments.push(seg);
      words += this.blockWords(child);
      prev = bs;
      pos += child.nodeSize;
      if (head === pos && headOffset === null) headOffset = len;
    });
    if (head !== undefined && headOffset === null) headOffset = len;
    const out = { html: parts.join(''), headOffset, words, segments };
    this.last = { doc, out };
    return out;
  }

  /**
   * The document position for an offset in this serializer's output of `doc` (spec 7.5, the way back): the block
   * holding the offset, then a binary search for the last position whose head offset is at or before it.
   */
  posForOffset(doc: PMNode, offset: number): { pos: number; found: boolean } {
    const out = this.last?.doc === doc ? this.last.out : this.serialize(doc);
    const segs = out.segments;
    if (segs.length === 0) return { pos: 0, found: false };
    const k = Math.min(Math.max(offset, 0), out.html.length);
    let lo = 0, hi = segs.length - 1;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (segs[mid]!.start <= k) lo = mid; else hi = mid - 1; }
    const seg = segs[lo]!;
    const child = doc.child(lo);
    if (k > seg.end) return { pos: seg.pos + child.nodeSize, found: false }; // in the whitespace after the block
    let a = seg.pos, z = seg.pos + child.nodeSize;
    while (a < z) {
      const mid = (a + z + 1) >> 1;
      const at = this.headIn(child, seg, mid);
      if (at !== null && at <= k) a = mid; else z = mid - 1;
    }
    return { pos: a, found: true };
  }
}
