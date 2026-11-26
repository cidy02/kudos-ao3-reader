// Parsing (parse5) into the small DOM of dom.ts, and serialization that matches Nokogiri's HTML5 writer
// (ext/nokogiri/xml_node.c, html_standard_serialize) byte for byte, which is what AO3 emits.
import { parse, parseFragment, defaultTreeAdapter, html as p5html } from 'parse5';
import type { DefaultTreeAdapterTypes } from 'parse5';
import { Kind, N, Ns, fragment } from './dom.ts';

/** Nokogiri's Gumbo limits (Nokogiri::Gumbo::DEFAULT_MAX_TREE_DEPTH, DEFAULT_MAX_ATTRIBUTES). */
export const MAX_TREE_DEPTH = 400;
export const MAX_ATTRIBUTES = 400;

/** Thrown where Nokogiri raises (tree too deep, too many attributes). AO3 would answer with an error page. */
export class ParseLimitError extends Error {
  readonly code: 'tree-depth' | 'attributes';
  constructor(code: 'tree-depth' | 'attributes') {
    super(code === 'tree-depth' ? 'Document tree depth limit exceeded' : 'Attributes per element limit exceeded');
    this.code = code;
  }
}

type P5Node = DefaultTreeAdapterTypes.Node;
type P5Parent = DefaultTreeAdapterTypes.ParentNode;
type P5Element = DefaultTreeAdapterTypes.Element;

const nsOf = (uri: string): Ns => (uri === p5html.NS.SVG ? Ns.Svg : uri === p5html.NS.MATHML ? Ns.Math : Ns.Html);

function convertChildren(src: P5Parent, dst: N, depth: number, locations: boolean): void {
  const list = (src as { childNodes: P5Node[] }).childNodes;
  for (const c of list) {
    switch (c.nodeName) {
      case '#text': {
        const t = N.text((c as DefaultTreeAdapterTypes.TextNode).value);
        const loc = (c as DefaultTreeAdapterTypes.TextNode).sourceCodeLocation;
        if (locations && loc) { t.start = loc.startOffset; t.end = loc.endOffset; }
        dst.appendChild(t);
        break;
      }
      case '#comment': {
        const t = N.comment((c as DefaultTreeAdapterTypes.CommentNode).data);
        const loc = (c as DefaultTreeAdapterTypes.CommentNode).sourceCodeLocation;
        if (locations && loc) { t.start = loc.startOffset; t.end = loc.endOffset; }
        dst.appendChild(t);
        break;
      }
      case '#documentType': {
        const t = new N(Kind.Doctype, '#doctype');
        t.text = (c as DefaultTreeAdapterTypes.DocumentType).name;
        dst.appendChild(t);
        break;
      }
      default: {
        const e = c as P5Element;
        if (depth + 1 > MAX_TREE_DEPTH + 1) throw new ParseLimitError('tree-depth');
        if (e.attrs.length > MAX_ATTRIBUTES) throw new ParseLimitError('attributes');
        const n = N.element(e.tagName, nsOf(e.namespaceURI));
        for (const a of e.attrs) n.attrs.push({ name: a.prefix ? `${a.prefix}:${a.name}` : a.name, value: a.value });
        const loc = e.sourceCodeLocation;
        if (locations && loc) {
          n.start = loc.startOffset;
          n.end = loc.endOffset;
          n.startTagEnd = loc.startTag ? loc.startTag.endOffset : -1;
          n.endTagStart = loc.endTag ? loc.endTag.startOffset : -1;
        }
        dst.appendChild(n);
        const content = (e as unknown as { content?: P5Parent }).content;
        convertChildren(content ?? e, n, depth + 1, locations);
      }
    }
  }
}

export type ParseOptions = { locations?: boolean };

/**
 * Nokogiri::HTML5.fragment(html) and node.fragment(html): the HTML fragment algorithm with `contextName` as the
 * context element (Nokogiri uses "body" when there is none). The result is a fragment node.
 */
export function parseIn(contextName: string, html: string, opts: ParseOptions = {}): N {
  const ctx = defaultTreeAdapter.createElement(contextName, p5html.NS.HTML, []);
  const doc = parseFragment(ctx, html, { sourceCodeLocationInfo: !!opts.locations, scriptingEnabled: false });
  const out = fragment();
  convertChildren(doc, out, 1, !!opts.locations); // Gumbo counts the html element too
  return out;
}

/** Same, parsing a whole document and returning the children of its body (what the loader's builder reads). */
export function parseBody(html: string, opts: ParseOptions = {}): N {
  return parseIn('body', html, opts);
}

/** Full-document parse, used only by tests that compare against parse5 directly. */
export function parseDocument(html: string): DefaultTreeAdapterTypes.Document {
  return parse(html, { scriptingEnabled: false });
}

const VOID = new Set(['area', 'base', 'basefont', 'bgsound', 'br', 'col', 'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr']);
const UNESCAPED = new Set(['style', 'script', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext', 'noscript']);

const escText = (s: string) => s.replace(/[&\u00a0<>]/g, (c) => (c === '&' ? '&amp;' : c === '\u00a0' ? '&nbsp;' : c === '<' ? '&lt;' : '&gt;'));
const escAttr = (s: string) => s.replace(/[&\u00a0"]/g, (c) => (c === '&' ? '&amp;' : c === '\u00a0' ? '&nbsp;' : '&quot;'));

function prependsNewline(n: N): boolean {
  return (n.name === 'pre' || n.name === 'textarea' || n.name === 'listing') && !!n.first && n.first.kind === Kind.Text && n.first.text.startsWith('\n');
}

function out(n: N, o: string[], preserveNewline: boolean): void {
  switch (n.kind) {
    case Kind.Element: {
      o.push('<', n.name);
      for (const a of n.attrs) o.push(' ', a.name, '="', escAttr(a.value), '"');
      o.push('>');
      if (n.ns === Ns.Html && VOID.has(n.name)) return;
      if (preserveNewline && prependsNewline(n)) o.push('\n');
      for (let c = n.first; c; c = c.next) out(c, o, preserveNewline);
      o.push('</', n.name, '>');
      return;
    }
    case Kind.Text:
      o.push(n.parent && n.parent.kind === Kind.Element && n.parent.ns === Ns.Html && UNESCAPED.has(n.parent.name) ? n.text : escText(n.text));
      return;
    case Kind.Comment: o.push('<!--', n.text, '-->'); return;
    case Kind.Doctype: o.push('<!DOCTYPE ', n.text, '>'); return;
    default:
      for (let c = n.first; c; c = c.next) out(c, o, preserveNewline);
  }
}

/** Nokogiri's `node.to_html` (a fragment or an element, or one text node) with or without `preserve_newline`. */
export function toHtml(n: N, preserveNewline = false): string {
  const o: string[] = [];
  out(n, o, preserveNewline);
  return o.join('');
}

/** `node.children.to_html`. */
export function childrenToHtml(n: N, preserveNewline = false): string {
  const o: string[] = [];
  for (let c = n.first; c; c = c.next) out(c, o, preserveNewline);
  return o.join('');
}
