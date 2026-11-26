// Builds the ProseMirror document from the cleaned HTML tree (spec 6.1 step 3, 6.2 tiers, 6.3 nodes, 6.4 marks).
// Input is the output of sanitizeValue, parsed with parse5, so only allow-listed markup arrives here.
import { Fragment, Mark } from 'prosemirror-model';
import type { Node as PMNode } from 'prosemirror-model';
import { Kind } from './dom.ts';
import type { N } from './dom.ts';
import { GLOBAL_ATTRS, MARK_TAGS, schema } from './schema.ts';

export type BuildReport = { unwrapped: Record<string, number>; normalized: number; preserved: number };

const TAG_TO_MARK = new Map<string, string>();
for (const [mark, tags] of Object.entries(MARK_TAGS)) for (const t of tags) TAG_TO_MARK.set(t, mark);

const RAW_BLOCK_ONLY = new Set(['table', 'pre', 'dl', 'figure', 'address', 'audio', 'video', 'source', 'track', 'dd', 'dt', 'caption', 'col', 'colgroup', 'tbody', 'tfoot', 'thead', 'tr', 'td', 'th', 'li', 'summary']);
const RAW_EITHER = new Set(['iframe', 'embed', 'object', 'param']);
const RAW_INLINE_ONLY = new Set(['ruby', 'rt', 'rp']);
const BLOCK_TAGS = new Set(['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'hr', 'details', 'div', 'center', ...RAW_BLOCK_ONLY]);
const WS = /^[ \t\r\n\f]*$/;

function gAttrs(n: N): Record<string, string | null> {
  const o: Record<string, string | null> = {};
  for (const a of GLOBAL_ATTRS) o[a] = n.attr(a) ?? null;
  if (o.class === '') o.class = null;
  return o;
}
const pick = (n: N, names: string[]): Record<string, string | null> => Object.fromEntries(names.map((k) => [k, n.attr(k) ?? null]));

class Builder {
  src: string;
  rep: BuildReport;
  constructor(src: string, rep: BuildReport) { this.src = src; this.rep = rep; }

  slice(n: N): string { return this.src.slice(n.start, n.end); }

  markFor(n: N): Mark | null {
    const type = TAG_TO_MARK.get(n.name);
    if (!type) return null;
    const extra = type === 'link' ? pick(n, ['href', 'name']) : type === 'phrase' && n.name === 'q' ? pick(n, ['cite']) : {};
    return schema.marks[type]!.create({ tag: n.name, ...extra, ...gAttrs(n) });
  }

  /** Children of a block container (doc, blockquote, div, details body, li) into blocks. */
  blocks(children: N[], marks: readonly Mark[], liMode = false): PMNode[] {
    const w = new Walker(this, false, liMode);
    w.walk(children, marks);
    return w.finish();
  }

  /** Children of a p, heading or summary: inline content only. null when a block element is inside (then preserved). */
  inline(children: N[], marks: readonly Mark[], collapseBreaks = false): PMNode[] | null {
    const w = new Walker(this, true, false);
    w.walk(children, marks);
    if (w.failed) return null;
    const out = w.cur ?? [];
    if (!collapseBreaks) return out;
    // headings and summaries cannot split: a run of <br> becomes one
    const kept = out.filter((n, i) => !(n.type.name === 'hard_break' && i > 0 && out[i - 1]!.type.name === 'hard_break'));
    if (kept.length !== out.length) this.rep.normalized++;
    return kept;
  }

  raw(n: N, inline: boolean, marks: readonly Mark[] = []): PMNode {
    this.rep.preserved++;
    return schema.nodes[inline ? 'raw_inline' : 'raw_block']!.create({ source: this.slice(n) }, null, inline ? marks : []);
  }
}

class Walker {
  b: Builder;
  inlineOnly: boolean;
  liMode: boolean;
  out: PMNode[] = [];
  cur: PMNode[] | null = null;
  failed = false;
  constructor(b: Builder, inlineOnly: boolean, liMode: boolean) { this.b = b; this.inlineOnly = inlineOnly; this.liMode = liMode; }

  private addInline(n: PMNode) { (this.cur ??= []).push(n); }

  private flush(): void {
    const cur = this.cur;
    this.cur = null;
    if (cur && cur.length) for (const part of this.splitBreaks(cur)) this.pushParagraph(part);
  }

  /** S10: no two adjacent <br>. A run splits the paragraph as AO3's merge_br_tags does (three or more add a spacer). */
  splitBreaks(cur: PMNode[]): PMNode[][] {
    const parts: PMNode[][] = [];
    let part: PMNode[] = [];
    let i = 0;
    while (i < cur.length) {
      const n = cur[i]!;
      if (n.type.name !== 'hard_break') { part.push(n); i++; continue; }
      let j = i;
      while (j < cur.length && cur[j]!.type.name === 'hard_break') j++;
      if (j - i === 1) part.push(n);
      else {
        this.b.rep.normalized++;
        if (part.length) parts.push(part);
        if (j - i >= 3) parts.push([]);
        part = [];
      }
      i = j;
    }
    if (part.length) parts.push(part);
    return parts;
  }

  private pushParagraph(nodes: PMNode[], explicit?: Record<string, string | null>): void {
    const implicit = this.liMode && this.out.length === 0 && !explicit;
    if (this.liMode && this.out.length > 0 && !explicit) this.b.rep.normalized++;
    const empty = nodes.length === 0 || (!implicit && nodes.length === 1 && nodes[0]!.isText && nodes[0]!.text === '\u00a0');
    if (implicit) nodes = this.trimEdges(nodes);
    this.out.push(schema.nodes.paragraph!.create({ implicit, ...explicit }, empty ? null : Fragment.from(nodes)));
  }

  /** Whitespace at the edges of a list item's own text is formatting, not content (it collapses in HTML). */
  private trimEdges(nodes: PMNode[]): PMNode[] {
    const out = nodes.slice();
    let changed = false;
    while (out[0]?.isText) {
      const t = out[0].text!.replace(/^[ \t]+/, '');
      if (t === out[0].text) break;
      changed = true;
      if (t) { out[0] = schema.text(t, out[0].marks); break; }
      out.shift();
    }
    for (let l = out[out.length - 1]; l?.isText; l = out[out.length - 1]) {
      const t = l.text!.replace(/[ \t]+$/, '');
      if (t === l.text) break;
      changed = true;
      if (t) { out[out.length - 1] = schema.text(t, l.marks); break; }
      out.pop();
    }
    if (changed) this.b.rep.normalized++;
    return out;
  }

  private pushBlock(n: PMNode): void { this.flush(); this.out.push(n); }

  walk(children: N[], marks: readonly Mark[]): void {
    for (const n of children) {
      if (this.failed) return;
      if (n.kind === Kind.Text) { this.text(n.text, marks); continue; }
      if (n.kind !== Kind.Element) continue; // comments never survive the cleaner
      this.element(n, marks);
    }
  }

  private text(raw: string, marks: readonly Mark[]): void {
    if (this.cur === null && !this.inlineOnly && WS.test(raw)) return; // whitespace between blocks
    let s = raw;
    const last = this.cur?.[this.cur.length - 1];
    if (last && last.type.name === 'hard_break' && /^[ \t]*[\r\n]/.test(s)) { s = s.replace(/^[ \t]*[\r\n]+[ \t]*/, ''); this.b.rep.normalized++; } // AO3 writes "<br>" + newline
    if (/[\r\n]/.test(s)) { s = s.replace(/\r\n|[\r\n]/g, ' '); this.b.rep.normalized++; } // S8
    if (s === '') return;
    this.addInline(schema.text(s, marks));
  }

  private element(n: N, marks: readonly Mark[]): void {
    const name = n.name;
    const b = this.b;
    const markType = TAG_TO_MARK.get(name);
    if (markType) { this.markElement(n, marks); return; }
    if (name === 'br') { this.addInline(schema.nodes.hard_break!.create(null, null, marks)); return; }
    if (name === 'img') {
      this.addInline(schema.nodes.image!.create({ ...pick(n, ['src', 'alt', 'width', 'height', 'border']), ...gAttrs(n) }, null, marks));
      return;
    }
    if (RAW_INLINE_ONLY.has(name)) { this.addInline(b.raw(n, true, marks)); return; }
    if (RAW_EITHER.has(name)) {
      if (this.cur !== null || this.inlineOnly) this.addInline(b.raw(n, true, marks)); else this.pushBlock(b.raw(n, false));
      return;
    }
    if (this.inlineOnly) {
      // a block element inside p, a heading or a summary: keep the whole container as an atom
      if (BLOCK_TAGS.has(name)) this.failed = true; else this.addInline(b.raw(n, true, marks));
      return;
    }
    if (RAW_BLOCK_ONLY.has(name)) { this.pushBlock(b.raw(n, false)); return; }
    switch (name) {
      case 'p': {
        const inl = b.inline(n.children(), marks);
        if (!inl) { this.pushBlock(b.raw(n, false)); return; }
        this.flush();
        const parts = this.splitBreaks(inl);
        if (parts.length === 0) this.pushParagraph([], gAttrs(n));
        for (const part of parts) this.pushParagraph(part, gAttrs(n));
        return;
      }
      case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': {
        const inl = b.inline(n.children(), marks, true);
        if (!inl) { this.pushBlock(b.raw(n, false)); return; }
        this.pushBlock(schema.nodes.heading!.create({ level: Number(name[1]), ...gAttrs(n) }, Fragment.from(inl)));
        return;
      }
      case 'blockquote': case 'div': case 'center': {
        const kids = b.blocks(n.children(), marks);
        if (kids.length === 0) { this.pushBlock(b.raw(n, false)); return; }
        this.pushBlock(name === 'blockquote'
          ? schema.nodes.blockquote!.create({ cite: n.attr('cite') ?? null, ...gAttrs(n) }, kids)
          : schema.nodes.container!.create({ tag: name, ...gAttrs(n) }, kids));
        return;
      }
      case 'ul': case 'ol': {
        const items: PMNode[] = [];
        for (const c of n.children()) {
          if (c.kind === Kind.Text && WS.test(c.text)) continue;
          if (c.kind === Kind.Element && c.name === 'li') {
            const kids = b.blocks(c.children(), marks, true);
            // list_item needs a leading paragraph; an empty implicit one is written as nothing
            if (kids.length === 0 || kids[0]!.type.name !== 'paragraph') kids.unshift(schema.nodes.paragraph!.create({ implicit: true }));
            items.push(schema.nodes.list_item!.create(gAttrs(c), kids));
          } else { items.length = 0; break; }
        }
        if (items.length === 0) { this.pushBlock(b.raw(n, false)); return; }
        this.pushBlock(name === 'ul'
          ? schema.nodes.bullet_list!.create({ type: n.attr('type') ?? null, ...gAttrs(n) }, items)
          : schema.nodes.ordered_list!.create({ start: n.attr('start') ?? null, type: n.attr('type') ?? null, ...gAttrs(n) }, items));
        return;
      }
      case 'hr':
        this.pushBlock(schema.nodes.horizontal_rule!.create({ width: n.attr('width') ?? null, ...gAttrs(n) }));
        return;
      case 'details': {
        const kids = n.children().filter((c) => !(c.kind === Kind.Text && WS.test(c.text)));
        const parts: PMNode[] = [];
        let rest = kids;
        const first = kids[0];
        if (first && first.kind === Kind.Element && first.name === 'summary') {
          const inl = b.inline(first.children(), marks, true);
          if (!inl) { this.pushBlock(b.raw(n, false)); return; }
          parts.push(schema.nodes.summary!.create(gAttrs(first), Fragment.from(inl)));
          rest = kids.slice(1);
        }
        parts.push(...b.blocks(rest, marks));
        if (parts.length === 0) { this.pushBlock(b.raw(n, false)); return; }
        this.pushBlock(schema.nodes.details!.create({ open: n.hasAttr('open'), ...gAttrs(n) }, parts));
        return;
      }
      default:
        this.pushBlock(b.raw(n, false)); // anything the schema has no home for is preserved, never dropped
    }
  }

  private markElement(n: N, marks: readonly Mark[]): void {
    const b = this.b;
    const mark = b.markFor(n)!;
    const isPlainSpan = n.name === 'span' && GLOBAL_ATTRS.every((a) => mark.attrs[a] === null);
    if (isPlainSpan) b.rep.unwrapped.span = (b.rep.unwrapped.span ?? 0) + 1;
    if (n.name === 'a') b.rep.normalized++; // AO3 adds rel="nofollow" itself
    const before = (this.cur?.length ?? 0) + this.out.length;
    const inner = isPlainSpan ? marks : mark.addToSet([...marks]);
    this.walk(n.children(), inner);
    const after = (this.cur?.length ?? 0) + this.out.length;
    if (after === before && !this.failed) {
      // a mark cannot cover zero characters (spec 6.4): keep the empty element verbatim
      if (isPlainSpan) { b.rep.unwrapped.span!--; if (b.rep.unwrapped.span === 0) delete b.rep.unwrapped.span; }
      this.addInline(b.raw(n, true, marks));
    }
  }

  finish(): PMNode[] {
    this.flush();
    return this.out;
  }
}

export function buildDoc(root: N, cleaned: string, rep: BuildReport): PMNode {
  const b = new Builder(cleaned, rep);
  const kids = b.blocks(root.children(), []);
  return schema.nodes.doc!.create(null, kids.length ? kids : [schema.nodes.paragraph!.create()]);
}
