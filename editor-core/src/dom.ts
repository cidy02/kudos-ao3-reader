// A small mutable DOM with the sibling and text-merging behaviour of the libxml2 tree that Nokogiri exposes.
// The AO3 cleaning port (paragraph-maker.ts, sanitize.ts) is written against it, one Ruby call at a time.
// parse5 only parses; nothing else here touches a platform DOM.

export const Kind = { Element: 1, Text: 3, Comment: 8, Doctype: 10, Fragment: 11 } as const;
export type Kind = (typeof Kind)[keyof typeof Kind];
export const Ns = { Html: 0, Svg: 1, Math: 2 } as const;
export type Ns = (typeof Ns)[keyof typeof Ns];

export type Attr = { name: string; value: string };

export class N {
  kind: Kind;
  name: string; // lower-case tag name for elements (as Nokogiri's node.name); "text", "comment", ...
  ns: Ns = Ns.Html;
  attrs: Attr[] = [];
  text = ''; // text, comment and doctype content
  parent: N | null = null;
  prev: N | null = null;
  next: N | null = null;
  first: N | null = null;
  last: N | null = null;
  /** Source range in the string handed to parse5 (set by html5.ts when asked). */
  start = -1;
  end = -1;
  startTagEnd = -1;
  endTagStart = -1;

  constructor(kind: Kind, name: string) {
    this.kind = kind;
    this.name = name;
  }

  static element(name: string, ns: Ns = Ns.Html): N { const n = new N(Kind.Element, name); n.ns = ns; return n; }
  static text(value: string): N { const n = new N(Kind.Text, 'text'); n.text = value; return n; }
  static comment(value: string): N { const n = new N(Kind.Comment, 'comment'); n.text = value; return n; }

  get isElement(): boolean { return this.kind === Kind.Element; }
  get isText(): boolean { return this.kind === Kind.Text; }

  children(): N[] {
    const out: N[] = [];
    for (let c = this.first; c; c = c.next) out.push(c);
    return out;
  }

  attr(name: string): string | undefined {
    for (const a of this.attrs) if (a.name === name) return a.value;
    return undefined;
  }
  hasAttr(name: string): boolean { return this.attr(name) !== undefined; }
  setAttr(name: string, value: string): void {
    for (const a of this.attrs) if (a.name === name) { a.value = value; return; }
    this.attrs.push({ name, value });
  }
  removeAttr(name: string): void { this.attrs = this.attrs.filter((a) => a.name !== name); }

  unlink(): void {
    const p = this.parent;
    if (!p) return;
    if (this.prev) this.prev.next = this.next; else p.first = this.next;
    if (this.next) this.next.prev = this.prev; else p.last = this.prev;
    this.parent = this.prev = this.next = null;
  }

  private detachFresh(n: N): void { if (n.parent) n.unlink(); }

  /** xmlAddChild: a text node appended after a text node merges into it. */
  appendChild(n: N): void {
    this.detachFresh(n);
    if (n.kind === Kind.Text && this.last && this.last.kind === Kind.Text) { this.last.text += n.text; return; }
    n.parent = this;
    n.prev = this.last;
    n.next = null;
    if (this.last) this.last.next = n; else this.first = n;
    this.last = n;
  }

  /** xmlAddPrevSibling (as reached through Nokogiri, which never merges into a text pivot). */
  insertBefore(n: N): void {
    const p = this.parent;
    if (!p) throw new Error('no parent');
    this.detachFresh(n);
    if (n.kind === Kind.Text) {
      const pv = this.prev;
      if (pv && pv.kind === Kind.Text) { pv.text += n.text; return; }
    }
    n.parent = p;
    n.prev = this.prev;
    n.next = this;
    if (this.prev) this.prev.next = n; else p.first = n;
    this.prev = n;
  }

  /** xmlAddNextSibling. */
  insertAfter(n: N): void {
    const p = this.parent;
    if (!p) throw new Error('no parent');
    this.detachFresh(n);
    if (n.kind === Kind.Text) {
      const nx = this.next;
      if (nx && nx.kind === Kind.Text) { nx.text = n.text + nx.text; return; }
    }
    n.parent = p;
    n.next = this.next;
    n.prev = this;
    if (this.next) this.next.prev = n; else p.last = n;
    this.next = n;
  }

  /** Document-order list of descendant elements. */
  descendants(pred: (n: N) => boolean): N[] {
    const out: N[] = [];
    const walk = (n: N) => {
      for (let c = n.first; c; c = c.next) {
        if (pred(c)) out.push(c);
        if (c.first) walk(c);
      }
    };
    walk(this);
    return out;
  }
}

export function fragment(): N { return new N(Kind.Fragment, '#document-fragment'); }
