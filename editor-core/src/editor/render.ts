// How the document looks in the page (spec 6.2, 6.3, 10.3 N9, 11): semantic elements for what the writer can edit,
// locked chips for preserved HTML, placeholders for remote images. Everything is built with createElement and
// setAttribute from the clean document; no HTML string ever reaches the live page.
import { DOMParser, DOMSerializer } from 'prosemirror-model';
import type { DOMOutputSpec, Mark, Node as PMNode } from 'prosemirror-model';
import type { MarkViewConstructor, NodeViewConstructor } from 'prosemirror-view';
import { parseFragment } from 'parse5';
import { schema } from '../index.ts';

/** Words the page shows or speaks. The native side may replace any of them (configure `labels`). */
export const DEFAULT_LABELS = {
  editor: 'Chapter text',
  sceneBreak: 'Scene break',
  foldOut: 'Fold-out section',
  spoiler: 'Spoiler',
  image: 'Image',
  editInHTML: 'Edit in HTML view',
  table: 'Table',
  pre: 'Preformatted text',
  dl: 'Definition list',
  figure: 'Figure',
  address: 'Address',
  ruby: 'Ruby text',
  media: 'Embedded media',
  anchor: 'Anchor',
  html: 'HTML',
};
export type Labels = typeof DEFAULT_LABELS;

const ALIGN = new Set(['left', 'center', 'right', 'justify']);
const DIR = new Set(['ltr', 'rtl', 'auto']);
const LANG = /^[A-Za-z0-9-]{1,35}$/;
const LIST_TYPE = /^[A-Za-z0-9]{1,8}$/;

/** align, dir, lang, title. `class` is never rendered: there is no work skin here and it could hit the page's own. */
function g(attrs: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  const { align, dir, lang, title } = attrs;
  if (typeof align === 'string' && ALIGN.has(align)) out.align = align;
  if (typeof dir === 'string' && DIR.has(dir)) out.dir = dir;
  if (typeof lang === 'string' && LANG.test(lang)) out.lang = lang;
  if (typeof title === 'string' && title) out.title = title;
  return out;
}

const SAFE_SCHEME = /^(?:https?|mailto|ftp):/i;
const ANY_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
/** The cleaner already checked the protocol; this is defence in depth (browsers ignore tabs and newlines in a scheme). */
export function safeHref(href: unknown): string | null {
  if (typeof href !== 'string') return null;
  const squeezed = href.replace(/[\u0000- \u007f]/g, '');
  if (ANY_SCHEME.test(squeezed) && !SAFE_SCHEME.test(squeezed)) return null;
  return href;
}

function hostOf(src: unknown): string {
  try { return new URL(String(src)).host || String(src); } catch { return String(src ?? ''); }
}

type RawInfo = { tag: string; label: string; preview: string };
const rawCache = new WeakMap<PMNode, RawInfo>();
const RAW_LABEL: Record<string, keyof Labels> = {
  table: 'table', pre: 'pre', dl: 'dl', figure: 'figure', address: 'address', ruby: 'ruby', a: 'anchor',
  iframe: 'media', embed: 'media', object: 'media', video: 'media', audio: 'media', source: 'media', param: 'media',
};

/** What a preserved slice is, for its chip: the tag of its first element and a short plain-text preview. */
function rawInfo(node: PMNode, labels: Labels): RawInfo {
  let info = rawCache.get(node);
  if (info) return info;
  const source = String(node.attrs.source ?? '');
  let tag = '';
  let text = '';
  const walk = (n: any): void => {
    if (text.length > 200) return;
    if (n.nodeName === '#text') text += n.value;
    else if (n.nodeName !== '#comment') {
      if (!tag && n.tagName) tag = n.tagName;
      for (const c of n.childNodes ?? []) walk(c);
    }
  };
  walk(parseFragment(source));
  const preview = text.replace(/\s+/g, ' ').trim();
  info = { tag, label: labels[RAW_LABEL[tag] ?? 'html'] ?? labels.html, preview: preview.length > 120 ? `${preview.slice(0, 119)}…` : preview };
  rawCache.set(node, info);
  return info;
}

export function nodeSpecs(labels: Labels): Record<string, (node: PMNode) => DOMOutputSpec> {
  return {
    paragraph: (n) => ['p', g(n.attrs), 0],
    heading: (n) => [`h${Math.min(Math.max(Number(n.attrs.level) || 3, 1), 6)}`, g(n.attrs), 0],
    blockquote: (n) => ['blockquote', g(n.attrs), 0],
    bullet_list: (n) => ['ul', { ...g(n.attrs), ...(LIST_TYPE.test(String(n.attrs.type)) ? { type: String(n.attrs.type) } : {}) }, 0],
    ordered_list: (n) => ['ol', {
      ...g(n.attrs),
      ...(LIST_TYPE.test(String(n.attrs.type)) ? { type: String(n.attrs.type) } : {}),
      ...(/^-?\d{1,9}$/.test(String(n.attrs.start)) ? { start: String(n.attrs.start) } : {}),
    }, 0],
    list_item: (n) => ['li', g(n.attrs), 0],
    // Atoms are locked: ProseMirror only adds contenteditable=false itself when there is no custom node view.
    horizontal_rule: (n) => ['hr', { ...g(n.attrs), contenteditable: 'false', 'aria-label': labels.sceneBreak }],
    // Shown open while editing (the writer has to reach the text); `data-open` keeps what AO3 will do.
    details: (n) => ['div', { ...g(n.attrs), class: 'kd-details', 'data-open': n.attrs.open ? 'true' : 'false', role: 'group', 'aria-label': labels.foldOut }, 0],
    summary: (n) => ['div', { ...g(n.attrs), class: 'kd-summary' }, 0],
    container: (n) => ['div', { ...g(n.attrs), class: n.attrs.tag === 'center' ? 'kd-container kd-center' : 'kd-container' }, 0],
    image: (n) => {
      const host = hostOf(n.attrs.src);
      const alt = typeof n.attrs.alt === 'string' ? n.attrs.alt : '';
      return ['span', { class: 'kd-image', contenteditable: 'false', role: 'img', 'aria-label': alt ? `${labels.image}: ${alt} (${host})` : `${labels.image} (${host})` },
        ['span', { class: 'kd-image-label' }, `${labels.image} · ${host}`]];
    },
    hard_break: () => ['br'],
    raw_block: (n) => {
      const info = rawInfo(n, labels);
      return ['div', { class: 'kd-raw', contenteditable: 'false', 'data-tag': info.tag, role: 'group', 'aria-label': `${info.label}. ${labels.editInHTML}` },
        ['span', { class: 'kd-raw-label' }, info.label],
        ['span', { class: 'kd-raw-preview' }, info.preview],
        ['span', { class: 'kd-raw-hint' }, labels.editInHTML]];
    },
    raw_inline: (n) => {
      const info = rawInfo(n, labels);
      return ['span', { class: 'kd-raw-inline', contenteditable: 'false', 'data-tag': info.tag, role: 'img', 'aria-label': info.label }, info.preview || info.label];
    },
  };
}

const PHRASE = new Set(['abbr', 'dfn', 'cite', 'q']);
const CODE = new Set(['kbd', 'samp', 'var']);
export const markSpecs: Record<string, (mark: Mark, inline: boolean) => DOMOutputSpec> = {
  link: (m) => {
    const href = safeHref(m.attrs.href);
    return ['a', { ...g(m.attrs), ...(href === null ? {} : { href }) }, 0];
  },
  span: (m) => ['span', g(m.attrs), 0],
  phrase: (m) => [m.attrs.tag === 'acronym' ? 'abbr' : PHRASE.has(m.attrs.tag) ? m.attrs.tag : 'span', g(m.attrs), 0],
  strong: (m) => ['strong', g(m.attrs), 0],
  em: (m) => ['em', g(m.attrs), 0],
  underline: (m) => ['u', g(m.attrs), 0],
  strike: (m) => [m.attrs.tag === 'del' ? 'del' : 's', g(m.attrs), 0],
  ins: (m) => ['ins', g(m.attrs), 0],
  size: (m) => [m.attrs.tag === 'big' ? 'big' : 'small', g(m.attrs), 0],
  script: (m) => [m.attrs.tag === 'sub' ? 'sub' : 'sup', g(m.attrs), 0],
  code: (m) => [CODE.has(m.attrs.tag) ? m.attrs.tag : 'code', { ...g(m.attrs), ...(m.attrs.tag === 'tt' ? { class: 'kd-tt' } : {}) }, 0],
};

/** Node views for every node type: the schema has no toDOM, so this is how the page draws the document. */
export function nodeViews(labels: Labels): Record<string, NodeViewConstructor> {
  const specs = nodeSpecs(labels);
  const views: Record<string, NodeViewConstructor> = {};
  for (const [name, spec] of Object.entries(specs)) {
    views[name] = (node) => {
      const { dom, contentDOM } = DOMSerializer.renderSpec(document, spec(node));
      return contentDOM ? { dom, contentDOM } : { dom };
    };
  }
  return views;
}

export const markViews: Record<string, MarkViewConstructor> = Object.fromEntries(
  Object.entries(markSpecs).map(([name, spec]) => [name, ((mark: Mark, _view: unknown, inline: boolean) => {
    const { dom, contentDOM } = DOMSerializer.renderSpec(document, spec(mark, inline));
    return { dom, contentDOM: contentDOM ?? undefined };
  }) as MarkViewConstructor]),
);

/** Used by ProseMirror for drag images and as a fallback; copy and cut write our own serializer's HTML (paste.ts). */
export const clipboardSerializer = (labels: Labels): DOMSerializer => new DOMSerializer(nodeSpecs(labels), markSpecs);

/**
 * Reads DOM the browser itself changed (autocorrect, dictation, spell-check replacements). Existing nodes are
 * recognised by their views; these rules only cover elements WebKit may create on its own. Paste and drop never
 * come here (paste.ts runs them through editor-core's parse5 pipeline instead).
 */
export const domParser = new DOMParser(schema, [
  { tag: 'p', node: 'paragraph' },
  ...[1, 2, 3, 4, 5, 6].map((level) => ({ tag: `h${level}`, node: 'heading', attrs: { level } })),
  { tag: 'blockquote', node: 'blockquote' },
  { tag: 'ul', node: 'bullet_list' },
  { tag: 'ol', node: 'ordered_list' },
  { tag: 'li', node: 'list_item' },
  { tag: 'hr', node: 'horizontal_rule' },
  { tag: 'br', node: 'hard_break' },
  { tag: 'strong', mark: 'strong', attrs: { tag: 'strong' } },
  { tag: 'b', mark: 'strong', attrs: { tag: 'b' } },
  { tag: 'em', mark: 'em', attrs: { tag: 'em' } },
  { tag: 'i', mark: 'em', attrs: { tag: 'i' } },
  { tag: 'u', mark: 'underline', attrs: { tag: 'u' } },
  { tag: 's', mark: 'strike', attrs: { tag: 's' } },
  { tag: 'strike', mark: 'strike', attrs: { tag: 'strike' } },
  { tag: 'sup', mark: 'script', attrs: { tag: 'sup' } },
  { tag: 'sub', mark: 'script', attrs: { tag: 'sub' } },
  { tag: 'small', mark: 'size', attrs: { tag: 'small' } },
  { tag: 'code', mark: 'code', attrs: { tag: 'code' } },
  { tag: 'a[href]', mark: 'link', getAttrs: (dom: HTMLElement) => { const href = safeHref(dom.getAttribute('href')); return href === null ? false : { tag: 'a', href }; } },
]);
