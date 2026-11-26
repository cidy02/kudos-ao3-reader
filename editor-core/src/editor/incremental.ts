// Incremental serialization and word counts (spec 9.4, S16, R2). Blocks unchanged since load are written from their
// source slices; edited blocks are serialized once per node object and cached, so a checkpoint after one keystroke
// serializes one block and joins the rest. Output is byte-identical to serializeDoc (incremental.test.ts checks).
import type { Node as PMNode } from 'prosemirror-model';
import { serializeBlock, serializeBlockAt } from '../index.ts';
import type { BlockSource, SourceInfo } from '../index.ts';
import { countNode } from './words.ts';

export type Serialized = { html: string; headOffset: number | null; words: number };

export class IncrementalSerializer {
  readonly sources: SourceInfo | undefined;
  private html = new WeakMap<PMNode, string>();
  private words = new WeakMap<PMNode, number>();

  constructor(sources?: SourceInfo) {
    this.sources = sources;
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
    if (s === undefined) this.html.set(node, (s = serializeBlock(node)));
    return s;
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
    let len = 0;
    let headOffset: number | null = null;
    let words = 0;
    let pos = 0;
    let prev: BlockSource | undefined;
    const push = (s: string) => { parts.push(s); len += s.length; };
    doc.forEach((child, _o, i) => {
      const bs = eff[i];
      if (i > 0) push(prev && bs && prev.index + 1 === bs.index ? src!.text.slice(prev.end, bs.start) : '\n');
      const start = len;
      const holdsHead = head !== undefined && headOffset === null && head >= pos && head <= pos + child.nodeSize;
      if (bs) {
        if (holdsHead) {
          // the load's source map works in loaded-document positions: translate through the block's own start
          const off = src!.docPosToOffset?.(src!.blockStart ? src!.blockStart(bs.index) + (head - pos) : head);
          headOffset = off !== null && off !== undefined ? start + Math.min(Math.max(off - bs.start, 0), bs.end - bs.start) : head === pos ? start : null;
        }
        push(src!.text.slice(bs.start, bs.end));
      } else if (holdsHead) {
        const one = serializeBlockAt(child, head - pos);
        this.html.set(child, one.html);
        headOffset = start + one.headOffset!;
        push(one.html);
      } else push(this.blockHtml(child));
      words += this.blockWords(child);
      prev = bs;
      pos += child.nodeSize;
      if (head === pos && headOffset === null) headOffset = len;
    });
    if (head !== undefined && headOffset === null) headOffset = len;
    return { html: parts.join(''), headOffset, words };
  }
}
