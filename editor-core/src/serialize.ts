// The serializer (spec 6.7, S1 to S16). Canonical output for edited blocks, source slices for untouched ones.
import type { Mark, Node as PMNode } from 'prosemirror-model';
import { GLOBAL_ATTRS, OWN_ATTR_ORDER } from './schema.ts';

/** Where an untouched top-level block came from (spec S16). `start`/`end` index into SourceMap.text. */
export type BlockSource = { start: number; end: number; index: number; spacer?: true };

/** What the loader remembers about the HTML it parsed; keyed by node identity so edits invalidate slices. */
export interface SourceInfo {
  text: string;
  blocks: WeakMap<PMNode, BlockSource>;
  /** UTF-16 offset in `text` of the caret for a document position, or null when unknown (caret.ts). */
  docPosToOffset?(pos: number): number | null;
  /** Document position where top-level block `index` of the loaded document started. */
  blockStart?(index: number): number;
}

export type SerializeOptions = {
  sources?: SourceInfo | undefined;
  /** Document position of the selection head: the result carries the output offset for it (spec 7.5). */
  head?: number | undefined;
};
export type SerializeResult = { html: string; headOffset: number | null };

const escText = (s: string) =>
  s.replace(/[&<> ]/g, (c) => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : '&nbsp;'))
    // AO3's fix_bad_characters deletes this literal; "&#95;" keeps the writer's text intact (departure from S5, see README)
    .replaceAll('____spacer____', '____spacer&#95;___')
    .replace(/\r\n|[\r\n]/g, ' '); // S8
const escAttr = (s: string) => s.replace(/[&" ]/g, (c) => (c === '&' ? '&amp;' : c === '"' ? '&quot;' : '&nbsp;'));

/**
 * S6 says one newline between sibling blocks. AO3 keeps (and turns into a line break) the newline between two
 * elements it does not strip whitespace around: address, iframe, embed, object (ParagraphMaker's
 * TAG_NAMES_STRIP_WHITESPACE). Between two of those the separator is empty, which the S15 property test found.
 */
const NO_STRIP = /^<(?:address|iframe|embed|object)[\s>/]/i;
const unstripped = (n: PMNode) => n.type.name === 'raw_block' && NO_STRIP.test(n.attrs.source as string);
const sep = (a: PMNode, b: PMNode, nl = '\n') => (unstripped(a) && unstripped(b) ? '' : nl);

class Writer {
  parts: string[] = [];
  len = 0;
  head: number | undefined;
  headOffset: number | null = null;
  push(s: string): void { this.parts.push(s); this.len += s.length; }
  at(pos: number): void { if (this.head === pos && this.headOffset === null) this.headOffset = this.len; }
}

function attrString(tag: string, own: string, attrs: Record<string, unknown>): string {
  const names = [...(OWN_ATTR_ORDER[own] ?? [])];
  for (const g of GLOBAL_ATTRS) if (!names.includes(g)) names.push(g);
  let s = '';
  for (const k of names) {
    if (k === 'open') { if (attrs.open) s += ' open="open"'; continue; }
    const v = attrs[k];
    if (v === null || v === undefined || v === false) continue;
    s += ` ${k}="${escAttr(String(v))}"`;
  }
  void tag;
  return s;
}

function markAttrs(m: Mark): string {
  const type = m.type.name;
  const attrs = { ...m.attrs } as Record<string, unknown>;
  if (type === 'phrase' && m.attrs.tag !== 'q') attrs.cite = null;
  return attrString(m.attrs.tag as string, type, attrs);
}

function inline(node: PMNode, pos: number, w: Writer, allowBreakRuns: boolean): void {
  // `pos` is the document position of the first child. Marks stay open across adjacent children that share them (S11).
  let open: Mark[] = [];
  let p = pos;
  let prevBreak = false;
  w.at(p);
  node.forEach((child) => {
    const marks = child.marks;
    let k = 0;
    while (k < open.length && k < marks.length && open[k]!.eq(marks[k]!)) k++;
    for (let i = open.length - 1; i >= k; i--) w.push(`</${open[i]!.attrs.tag as string}>`);
    for (let i = k; i < marks.length; i++) w.push(`<${marks[i]!.attrs.tag as string}${markAttrs(marks[i]!)}>`);
    open = [...marks];
    const name = child.type.name;
    if (child.isText) {
      const t = child.text!;
      const head = w.head;
      if (head !== undefined && head > p && head < p + t.length) {
        // Escape the text whole: escaping the halves separately misses a ____spacer____ the head cuts. The only escape
        // that isn't prefix-stable is that marker's `_` -> `&#95;` (4 longer), so a head past it moves on by 4.
        const full = escText(t);
        const before = escText(t.slice(0, head - p));
        const start = w.len;
        w.push(full);
        w.headOffset ??= start + (full.startsWith(before) ? before.length : before.length + 4);
      } else w.push(escText(t));
      prevBreak = false;
    } else if (name === 'hard_break') {
      if (!(prevBreak && !allowBreakRuns)) w.push('<br>'); // S10 (a valid document never has two in a row)
      prevBreak = true;
    } else if (name === 'image') {
      w.push(`<img${attrString('img', 'image', child.attrs)}>`);
      prevBreak = false;
    } else if (name === 'raw_inline') {
      w.push(child.attrs.source as string);
      prevBreak = false;
    }
    p += child.nodeSize;
    w.at(p);
  });
  for (let i = open.length - 1; i >= 0; i--) w.push(`</${open[i]!.attrs.tag as string}>`);
}

function blocks(node: PMNode, pos: number, w: Writer): void {
  let p = pos;
  let prev: PMNode | null = null;
  node.forEach((child) => {
    if (prev) w.push(sep(prev, child));
    prev = child;
    block(child, p, w);
    p += child.nodeSize;
    w.at(p);
  });
}

function block(node: PMNode, pos: number, w: Writer): void {
  w.at(pos);
  const a = node.attrs;
  switch (node.type.name) {
    case 'paragraph':
      if (a.implicit) { inline(node, pos + 1, w, false); return; }
      w.push(`<p${attrString('p', 'paragraph', a)}>`);
      if (node.childCount === 0) { w.push('&nbsp;'); w.at(pos + 1); } else inline(node, pos + 1, w, false);
      w.push('</p>');
      return;
    case 'heading': {
      const t = `h${a.level as number}`;
      w.push(`<${t}${attrString(t, 'heading', a)}>`);
      inline(node, pos + 1, w, false);
      w.push(`</${t}>`);
      return;
    }
    case 'blockquote':
      w.push(`<blockquote${attrString('blockquote', 'blockquote', a)}>`);
      w.at(pos + 1);
      blocks(node, pos + 1, w);
      w.push('</blockquote>');
      return;
    case 'container': {
      const t = a.tag as string;
      w.push(`<${t}${attrString(t, 'container', a)}>`);
      w.at(pos + 1);
      blocks(node, pos + 1, w);
      w.push(`</${t}>`);
      return;
    }
    case 'bullet_list': case 'ordered_list': {
      const t = node.type.name === 'bullet_list' ? 'ul' : 'ol';
      w.push(`<${t}${attrString(t, node.type.name, a)}>`);
      w.at(pos + 1);
      let p = pos + 1;
      let first = true;
      node.forEach((li) => {
        if (!first) w.push('\n');
        first = false;
        w.at(p);
        w.push(`<li${attrString('li', 'list_item', li.attrs)}>`);
        let q = p + 1;
        li.forEach((child, _o, i) => {
          if (i === 0 && child.type.name === 'paragraph' && child.attrs.implicit) inline(child, q + 1, w, false);
          else block(child, q, w);
          q += child.nodeSize;
          w.at(q);
        });
        w.push('</li>');
        p += li.nodeSize;
        w.at(p);
      });
      w.push(`</${t}>`);
      return;
    }
    case 'horizontal_rule':
      w.push(`<hr${attrString('hr', 'horizontal_rule', a)}>`);
      return;
    case 'details': {
      w.push(`<details${attrString('details', 'details', a)}>`);
      w.at(pos + 1);
      let p = pos + 1;
      let prev: PMNode | null = null;
      node.forEach((child) => {
        if (prev) w.push(sep(prev, child));
        prev = child;
        if (child.type.name === 'summary') {
          w.at(p);
          w.push(`<summary${attrString('summary', 'summary', child.attrs)}>`);
          inline(child, p + 1, w, false);
          w.push('</summary>');
        } else block(child, p, w);
        p += child.nodeSize;
        w.at(p);
      });
      w.push('</details>');
      return;
    }
    case 'raw_block':
      w.push(a.source as string);
      return;
    default:
      throw new Error(`cannot serialize ${node.type.name} as a block`);
  }
}

/** The canonical serialization of one top-level block (S1 to S13). */
export function serializeBlock(node: PMNode): string {
  const w = new Writer();
  block(node, 0, w);
  return w.parts.join('');
}

/** One top-level block with the output offset of a head position inside it (`head` is relative to the block's start). */
export function serializeBlockAt(node: PMNode, head: number): SerializeResult {
  const w = new Writer();
  w.head = head;
  block(node, 0, w);
  w.at(node.nodeSize);
  return { html: w.parts.join(''), headOffset: w.headOffset ?? w.len };
}

/** Serializes a document: S6 separators, source slices for untouched blocks (S16), and the head offset (spec 7.5). */
export function serializeDoc(doc: PMNode, opts: SerializeOptions = {}): SerializeResult {
  // an empty field: a document that is one empty plain paragraph
  const only = doc.childCount === 1 ? doc.child(0) : null;
  if (only && only.type.name === 'paragraph' && only.childCount === 0 && Object.values(only.attrs).every((v) => v === null || v === false)) return { html: '', headOffset: opts.head === undefined ? null : 0 };
  const w = new Writer();
  w.head = opts.head;
  const src = opts.sources;
  // A spacer (blank paragraph between blank lines) is only written from source when both neighbours are too.
  const eff: (BlockSource | undefined)[] = [];
  doc.forEach((c) => eff.push(src?.blocks.get(c)));
  eff.forEach((e, i) => {
    if (!e?.spacer) return;
    const a = eff[i - 1], z = eff[i + 1];
    if (!(a && z && !a.spacer && !z.spacer && a.index + 1 === e.index && e.index + 1 === z.index)) eff[i] = undefined;
  });
  let pos = 0;
  let prev: BlockSource | undefined;
  doc.forEach((child, _o, i) => {
    const bs = eff[i];
    if (i > 0) {
      if (prev && bs && prev.index + 1 === bs.index) w.push(src!.text.slice(prev.end, bs.start)); // S16: the text between untouched blocks
      else w.push(sep(doc.child(i - 1), child));
    }
    const startLen = w.len;
    if (bs) {
      if (w.head !== undefined && w.head >= pos && w.head <= pos + child.nodeSize && w.headOffset === null) {
        // the caret sits in an untouched block: the load's source map knows where it is in the slice
        const off = src!.docPosToOffset?.(src!.blockStart ? src!.blockStart(bs.index) + (w.head - pos) : w.head);
        w.headOffset = off !== null && off !== undefined ? startLen + Math.min(Math.max(off - bs.start, 0), bs.end - bs.start) : w.head === pos ? startLen : null;
      }
      w.push(src!.text.slice(bs.start, bs.end));
    } else block(child, pos, w);
    prev = bs;
    pos += child.nodeSize;
    w.at(pos);
  });
  if (w.head !== undefined && w.headOffset === null) w.headOffset = w.len;
  return { html: w.parts.join(''), headOffset: w.headOffset };
}

/** Convenience: the HTML string only. */
export const serialize = (doc: PMNode, opts?: SerializeOptions): string => serializeDoc(doc, opts).html;
