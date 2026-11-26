// The paste cleaner (spec 6.8, P1 to P5): what Google Docs, Word, Pages, Notes, Scrivener and web pages put on the
// clipboard, turned into the structure AO3 keeps before part 1's AO3 cleaning runs (P6). The fic-writer case that
// matters most: italics and bold from Google Docs survive, even though they arrive as inline styles AO3 would drop.
// Everything happens on a parse5 tree; nothing touches the page's DOM, and nothing is fetched (P7).
import { parse, serialize } from 'parse5';

export type PasteSource = 'google-docs' | 'word' | 'apple' | 'ao3' | 'web';

/** What the clean-up did before AO3's own cleaning: styles turned into structure, and styles AO3 can't show. */
export type PrecleanReport = {
  source: PasteSource;
  /** Inline or class styles turned into elements or attributes, by what they became (`strong`, `align`, ...). */
  converted: Record<string, number>;
  /** Style properties with no AO3 equivalent, by property (`color`, `font-family`, ...). */
  styles: Record<string, number>;
  /** Elements removed before cleaning (comments, `style`, `meta`, Office namespaces), by name. */
  removed: Record<string, number>;
};

type Attr = { name: string; value: string };
type P5 = {
  nodeName: string;
  tagName?: string;
  attrs?: Attr[];
  childNodes?: P5[];
  parentNode?: P5 | null;
  value?: string;
  content?: P5;
  namespaceURI?: string;
};

const HTML_NS = 'http://www.w3.org/1999/xhtml';
const BLOCKS = new Set(['p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'td', 'th', 'center', 'address', 'pre', 'dd', 'dt', 'summary']);
const REMOVE = new Set(['style', 'meta', 'link', 'xml', 'title', 'script', 'head']);
const OFFICE_NS = /^(?:w|o|v|m|st1):/;
const ALIGN = new Set(['left', 'center', 'right', 'justify']);
/** Styles a writer can see that AO3 won't show (reported); the rest is layout noise every app adds (not reported). */
const VISIBLE = new Set(['color', 'background', 'background-color', 'font-family', 'font-size', 'font', 'font-variant', 'text-transform', 'letter-spacing', 'text-shadow']);
const INVISIBLE = /^(?:inherit|initial|normal|none|transparent|black|windowtext|#000(?:000)?|rgba?\(0,\s*0,\s*0(?:,\s*1)?\)|#fff(?:fff)?|white)$/;

const attr = (n: P5, name: string) => n.attrs?.find((a) => a.name === name)?.value;
function setAttr(n: P5, name: string, value: string | null): void {
  n.attrs = (n.attrs ?? []).filter((a) => a.name !== name);
  if (value !== null) n.attrs.push({ name, value });
}
const bump = (r: Record<string, number>, k: string, by = 1) => { r[k] = (r[k] ?? 0) + by; };

function element(tagName: string, children: P5[] = [], attrs: Attr[] = []): P5 {
  const e: P5 = { nodeName: tagName, tagName, attrs, childNodes: [], parentNode: null, namespaceURI: HTML_NS };
  for (const c of children) { c.parentNode = e; e.childNodes!.push(c); }
  return e;
}
/** Replaces `node` in its parent by `replacement` nodes. */
function replace(node: P5, replacement: P5[]): void {
  const parent = node.parentNode;
  if (!parent?.childNodes) return;
  const i = parent.childNodes.indexOf(node);
  for (const r of replacement) r.parentNode = parent;
  parent.childNodes.splice(i, 1, ...replacement);
}
const unwrap = (node: P5) => replace(node, node.childNodes ?? []);

// ---- CSS: inline styles and the class rules Cocoa HTML Writer (Pages, Notes, TextEdit, Scrivener) uses --------

function declarations(style: string): [string, string][] {
  const out: [string, string][] = [];
  for (const part of style.split(';')) {
    const i = part.indexOf(':');
    if (i < 0) continue;
    const prop = part.slice(0, i).trim().toLowerCase();
    const value = part.slice(i + 1).trim().toLowerCase().replace(/\s*!important$/, '');
    if (prop) out.push([prop, value]);
  }
  return out;
}

/** `p.p1, span.s1 { … }` and `.s2 { … }` rules from <style> blocks: class -> declarations, per tag or any tag. */
function classRules(css: string): Map<string, string> {
  const rules = new Map<string, string>();
  const clean = css.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--|-->/g, '');
  for (const m of clean.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    for (const sel of m[1]!.split(',')) {
      const s = sel.trim();
      const k = /^([a-z0-9]*)\.([\w-]+)$/i.exec(s);
      if (k) rules.set(`${k[1]!.toLowerCase()}.${k[2]}`, `${rules.get(`${k[1]!.toLowerCase()}.${k[2]}`) ?? ''};${m[2]}`);
    }
  }
  return rules;
}

const BOLD = (v: string) => /^(?:bold|bolder|[6-9]00)$/.test(v);
/** Wrapping in these would say what the element already says. */
const ALREADY: Record<string, Set<string>> = {
  strong: new Set(['strong', 'b', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'th']), em: new Set(['em', 'i']), u: new Set(['u']),
  strike: new Set(['strike', 's', 'del']), sup: new Set(['sup']), sub: new Set(['sub']),
};
const ITALIC = (v: string) => /^(?:italic|oblique)/.test(v);

/** The structure a set of declarations stands for, and the properties with no AO3 equivalent. */
function interpret(decls: [string, string][], report: PrecleanReport) {
  const wraps: string[] = [];
  let align: string | null = null;
  let dir: string | null = null;
  let unbold = false;
  for (const [prop, value] of decls) {
    if (prop === 'font-weight') { if (BOLD(value)) wraps.push('strong'); else if (/^(?:normal|[1-4]00)$/.test(value)) unbold = true; }
    else if (prop === 'font-style') { if (ITALIC(value)) wraps.push('em'); }
    else if (prop === 'text-decoration' || prop === 'text-decoration-line') {
      if (value.includes('underline')) wraps.push('u');
      if (value.includes('line-through')) wraps.push('strike');
    }
    else if (prop === 'vertical-align') { if (value === 'super') wraps.push('sup'); else if (value === 'sub') wraps.push('sub'); }
    else if (prop === 'text-align') { if (ALIGN.has(value)) align = value; }
    else if (prop === 'direction') { if (value === 'rtl' || value === 'ltr') dir = value; }
    else if (prop === 'font') {
      // the shorthand Cocoa HTML Writer uses: "italic bold 12.0px Helvetica"
      if (/\b(?:bold|[6-9]00)\b/.test(value)) wraps.push('strong');
      if (/\b(?:italic|oblique)\b/.test(value)) wraps.push('em');
      bump(report.styles, 'font-family');
    }
    else if (VISIBLE.has(prop) && !INVISIBLE.test(value)) bump(report.styles, prop);
  }
  return { wraps: [...new Set(wraps)], align, dir, unbold };
}

// ---- Word lists (P5) ---------------------------------------------------------------------------------------------

const MARKER_OL = /^\s*(?:\(?[0-9]+[.)]|\(?[a-z][.)]|\(?[ivxlcdm]+[.)])\s*$/i;

/** Text content of a parse5 subtree. */
function text(n: P5): string {
  if (n.nodeName === '#text') return n.value ?? '';
  return (n.childNodes ?? []).map(text).join('');
}

/** Word's `mso-list` paragraphs (one per item, the bullet a span marked `mso-list:Ignore`) become ul/ol nested by level. */
function wordLists(parent: P5, listStyles: WeakMap<P5, string>, markers: WeakSet<P5>, report: PrecleanReport): void {
  const kids = parent.childNodes ?? [];
  for (let i = 0; i < kids.length; i++) {
    const start = kids[i]!;
    if (!listStyles.has(start)) { if (start.childNodes) wordLists(start, listStyles, markers, report); continue; }
    // a run of list paragraphs, whitespace between them allowed
    const run: P5[] = [];
    let j = i;
    for (; j < kids.length; j++) {
      const k = kids[j]!;
      if (listStyles.has(k)) run.push(k);
      else if (!(k.nodeName === '#text' && !(k.value ?? '').trim())) break;
    }
    const roots: P5[] = [];
    const stack: { level: number; list: P5 }[] = [];
    for (const p of run) {
      const level = Number(/level(\d+)/.exec(listStyles.get(p)!)?.[1] ?? 1);
      let marker = '';
      const strip = (n: P5) => {
        for (const c of [...(n.childNodes ?? [])]) {
          if (markers.has(c)) { marker ||= text(c); replace(c, []); bump(report.converted, 'li'); }
          else if (c.childNodes) strip(c);
        }
      };
      strip(p);
      const tag = MARKER_OL.test(marker.replace(/ /g, ' ')) ? 'ol' : 'ul';
      while (stack.length && stack.at(-1)!.level > level) stack.pop();
      if (!stack.length || stack.at(-1)!.level < level || stack.at(-1)!.list.tagName !== tag) {
        const list = element(tag);
        const top = stack.at(-1);
        if (top && top.level < level) {
          const lastLi = top.list.childNodes!.filter((c) => c.tagName === 'li').at(-1);
          (lastLi ?? top.list).childNodes!.push(list);
          list.parentNode = lastLi ?? top.list;
        } else {
          if (top && top.level === level) stack.pop();
          roots.push(list);
        }
        stack.push({ level, list });
      }
      const li = element('li', p.childNodes ?? []);
      for (const a of p.attrs ?? []) if (a.name === 'align' || a.name === 'dir') li.attrs!.push(a);
      stack.at(-1)!.list.childNodes!.push(li);
      li.parentNode = stack.at(-1)!.list;
    }
    kids.splice(i, j - i, ...roots);
    for (const r of roots) r.parentNode = parent;
    i += roots.length - 1;
  }
}

// ---- detection and the pass ----------------------------------------------------------------------------------------

export function detectSource(html: string): PasteSource {
  if (/id=["']?docs-internal-guid/i.test(html)) return 'google-docs';
  if (/urn:schemas-microsoft-com:office|class=["']?Mso|mso-[a-z-]+\s*:/i.test(html)) return 'word';
  if (/Cocoa HTML Writer|CocoaVersion/i.test(html)) return 'apple';
  if (/class=["']?userstuff\b/i.test(html)) return 'ao3';
  return 'web';
}

/** P2 to P5 over the clipboard's HTML. The result goes through the same pipeline as a loaded document (P6). */
export function precleanPaste(html: string): { html: string; report: PrecleanReport } {
  const source = detectSource(html);
  const report: PrecleanReport = { source, converted: {}, styles: {}, removed: {} };
  const doc = parse(html, { scriptingEnabled: false }) as unknown as P5;
  const root = doc.childNodes?.find((c) => c.tagName === 'html');
  const body = root?.childNodes?.find((c) => c.tagName === 'body');
  if (!body) return { html: '', report };

  // Class rules from every <style> (Cocoa HTML Writer and Word put them in <head>).
  let css = '';
  const collect = (n: P5) => { if (n.tagName === 'style') css += text(n); for (const c of n.childNodes ?? []) collect(c); };
  collect(doc);
  const rules = classRules(css);

  const listStyles = new WeakMap<P5, string>();
  const markers = new WeakSet<P5>(); // Word's bullet or number before each list item (`mso-list:Ignore`)
  const visit = (n: P5): void => {
    for (const c of [...(n.childNodes ?? [])]) visit(c);
    if (n === body) return;
    if (n.nodeName === '#comment') { replace(n, []); bump(report.removed, '#comment'); return; } // P2, Word's [if …] too
    const tag = n.tagName;
    if (!tag) return;
    if (REMOVE.has(tag) || OFFICE_NS.test(tag)) { replace(n, []); bump(report.removed, tag); return; }
    // P4: Google Docs wraps the whole paste in <b id="docs-internal-guid-…" style="font-weight:normal">.
    if (tag === 'b' && /^docs-internal-guid/.test(attr(n, 'id') ?? '')) { unwrap(n); return; }
    const classes = (attr(n, 'class') ?? '').split(/\s+/).filter(Boolean);
    // WebKit's own markers (Safari, Chrome, Pages, Notes): a preserved space, a tab, the selection's trailing newline.
    if (classes.includes('Apple-interchange-newline')) { replace(n, []); return; }
    if (classes.includes('Apple-converted-space') || classes.includes('Apple-tab-span')) {
      for (const c of n.childNodes ?? []) if (c.nodeName === '#text' && c.value === '\u00a0') c.value = ' ';
      unwrap(n);
      return;
    }
    // A copy from an AO3 work page: the page's wrapper and its "Work Text:" landmark aren't the writer's text.
    if (source === 'ao3') {
      if (classes.includes('userstuff')) { unwrap(n); return; }
      if (classes.includes('landmark')) { replace(n, []); bump(report.removed, `${tag}.landmark`); return; }
    }

    let style = attr(n, 'style') ?? '';
    for (const k of classes) {
      const fromRule = rules.get(`${tag}.${k}`) ?? rules.get(`.${k}`);
      if (fromRule) style = `${fromRule};${style}`;
    }
    if (source === 'word') {
      const kept = classes.filter((k) => !/^(?:Mso|SpellE$|GramE$)/i.test(k)); // P5, and Word's spelling marks
      setAttr(n, 'class', kept.length ? kept.join(' ') : null);
      if (/mso-list\s*:\s*l\d/i.test(style) && (tag === 'p' || tag === 'h1' || tag === 'h2' || tag === 'h3')) listStyles.set(n, style.toLowerCase());
      if (/mso-list\s*:\s*ignore/i.test(style)) { markers.add(n); setAttr(n, 'style', null); return; }
    } else if (source === 'apple') {
      setAttr(n, 'class', null); // p1, s1, …: Cocoa's own names, meaningless on AO3
    } else if (source === 'google-docs') {
      setAttr(n, 'class', null);
      if (attr(n, 'dir') === 'ltr') setAttr(n, 'dir', null); // Docs marks every paragraph ltr
    }
    if (style) {
      setAttr(n, 'style', null);
      applyStyle(n, tag, style);
    }
    if (tag === 'span') {
      // nothing left inside: Word's <o:p> holders, or a bare span (a classed empty span is a work-skin hook, kept)
      if (!(n.childNodes ?? []).length && (source === 'word' || !(n.attrs ?? []).length)) { replace(n, []); return; }
      if (!(n.attrs ?? []).length || (source === 'word' && (n.attrs ?? []).every((a) => a.name === 'lang'))) unwrap(n); // P5
    }
  };
  const applyStyle = (n: P5, tag: string, style: string): void => {
    const s = interpret(declarations(style), report);
    if (s.align && BLOCKS.has(tag)) { setAttr(n, 'align', s.align); bump(report.converted, 'align'); }
    else if (s.align) {
      let b = n.parentNode;
      while (b && b !== body && !BLOCKS.has(b.tagName ?? '')) b = b.parentNode;
      if (b && b !== body && !attr(b, 'align')) { setAttr(b, 'align', s.align); bump(report.converted, 'align'); }
    }
    if (s.dir) { setAttr(n, 'dir', s.dir); bump(report.converted, 'dir'); }
    const wraps = s.wraps.filter((w) => !ALREADY[w]?.has(tag));
    if (wraps.length) {
      // wrap the element's children (a block keeps its own tag; an inline span is replaced by the marks)
      let inner: P5[] = n.childNodes ?? [];
      for (const w of [...wraps].reverse()) { inner = [element(w, inner)]; bump(report.converted, w); }
      n.childNodes = [];
      for (const c of inner) { c.parentNode = n; n.childNodes.push(c); }
    }
    // A <b> or <strong> made not-bold by its own style (font-weight:normal) carries no bold.
    if (s.unbold && (tag === 'b' || tag === 'strong')) unwrap(n);
  };
  visit(body);
  if (source === 'word') wordLists(body, listStyles, markers, report);
  // parse5 writes a literal ____spacer____ back out, and AO3's fix_bad_characters would delete it (part 1, S5).
  return { html: serialize(body as never).replaceAll('____spacer____', '____spacer&#95;___'), report };
}
