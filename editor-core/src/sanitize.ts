// Derived from otwarchive (Organization for Transformative Works), GPL-2.0-or-later; see editor-core/NOTICE.
// Port of Sanitize.clean (sanitize 6.1.0) as configured by otwarchive's sanitizer_config.rb, plus otwarchive's
// transformers: details/open, relative image paths, UserClassSanitizer, EmbedSanitizer and MediaSanitizer (452391b6).
import { Kind, N } from './dom.ts';
import { childrenToHtml, parseIn } from './html5.ts';
import { REMOVE_CONTENTS } from './paragraph-maker.ts';
import { RB_S, isBlank, strip } from './ruby.ts';
import * as uri from './addressable.ts';

/** What the sanitizer removed or changed; feeds the loss report (spec 6.9). */
export type SanitizeReport = {
  elements: Record<string, number>;
  attributes: Record<string, number>;
  normalized: number;
};
export const newReport = (): SanitizeReport => ({ elements: {}, attributes: {}, normalized: 0 });
const bump = (r: Record<string, number>, k: string) => { r[k] = (r[k] ?? 0) + 1; };

export type Variant = 'content' | 'notes' | 'summary';
export type CleanOptions = { appUrl?: string; report?: SanitizeReport };
export const DEFAULT_APP_URL = 'https://archiveofourown.org';

type Protocols = Record<string, Record<string, (string | ':relative')[]>>;
type Config = {
  elements: Set<string>;
  attributes: Record<string, string[]>; // key "all" is the global list
  addAttributes: Record<string, Record<string, string>>;
  protocols: Protocols;
  removeContents?: Set<string>;
};

const ARCHIVE_ELEMENTS = 'a abbr acronym address b big blockquote br caption center cite code col colgroup details figcaption figure dd del dfn div dl dt em h1 h2 h3 h4 h5 h6 hr i img ins kbd li ol p pre q rp rt ruby s samp small span strike strong sub summary sup table tbody td tfoot th thead tr tt u ul var'.split(' ');
const ARCHIVE: Config = {
  elements: new Set(ARCHIVE_ELEMENTS),
  attributes: {
    all: ['align', 'dir', 'lang', 'title'],
    a: ['href', 'name'], blockquote: ['cite'], col: ['span', 'width'], colgroup: ['span', 'width'], details: ['open'],
    hr: ['align', 'width'], img: ['align', 'alt', 'border', 'height', 'src', 'width'], ol: ['start', 'type'], q: ['cite'],
    table: ['border', 'summary', 'width'], td: ['abbr', 'axis', 'colspan', 'height', 'rowspan', 'width'],
    th: ['abbr', 'axis', 'colspan', 'height', 'rowspan', 'scope', 'width'], ul: ['type'],
  },
  addAttributes: { a: { rel: 'nofollow' } },
  protocols: {
    a: { href: ['ftp', 'http', 'https', 'mailto', ':relative'] },
    blockquote: { cite: ['http', 'https', ':relative'] },
    img: { src: ['http', 'https'] },
    q: { cite: ['http', 'https', ':relative'] },
  },
};
const CSS_ALLOWED: Config = { ...ARCHIVE, attributes: { ...ARCHIVE.attributes, all: [...ARCHIVE.attributes.all!, 'class'] } };

// Sanitize::Config::DEFAULT whitespace_elements (before and after are a single space)
const WHITESPACE_ELEMENTS = new Set('address article aside blockquote br dd div dl dt footer h1 h2 h3 h4 h5 h6 header hgroup hr li nav ol p pre section ul'.split(' '));

type Env = { node: N; name: string; isAllowlisted: boolean; allowlist: Set<N>; ctx: Ctx };
type Transformer = (env: Env) => void | { allowlist: N[] };
type Ctx = { appUrl: string; report: SanitizeReport | undefined };

const REGEX_UNSUITABLE_CHARS = new RegExp(
  '[\\u0001-\\u0008\\u000b\\u000e-\\u001f\\u007f-\\u009f]+|[\\ufdd0-\\ufdef\\ufffe\\uffff]+|' +
  '(?:[\\u{1fffe}\\u{1ffff}\\u{2fffe}\\u{2ffff}\\u{3fffe}\\u{3ffff}\\u{4fffe}\\u{4ffff}\\u{5fffe}\\u{5ffff}\\u{6fffe}\\u{6ffff}\\u{7fffe}\\u{7ffff}\\u{8fffe}\\u{8ffff}\\u{9fffe}\\u{9ffff}\\u{afffe}\\u{affff}\\u{bfffe}\\u{bffff}\\u{cfffe}\\u{cffff}\\u{dfffe}\\u{dffff}\\u{efffe}\\u{effff}\\u{ffffe}\\u{fffff}\\u{10fffe}\\u{10ffff}])+', 'gu');

const REGEX_PROTOCOL = new RegExp(`^${RB_S}*([^/#]*?)(?::|&#0*58|&#x0*3a)`, 'i');

function cleanElementFor(cfg: Config): Transformer {
  const attrs = new Map<string, Set<string>>();
  const all = cfg.attributes.all ? new Set(cfg.attributes.all) : undefined;
  for (const [el, list] of Object.entries(cfg.attributes)) if (el !== 'all') attrs.set(el, new Set([...list, ...(all ?? [])]));
  const removeContents = cfg.removeContents ?? new Set(REMOVE_CONTENTS);
  return (env) => {
    const node = env.node;
    if (node.kind !== Kind.Element || env.isAllowlisted) return;
    const name = env.name;
    const rep = env.ctx.report;
    if (!cfg.elements.has(name) && node.parent) {
      if (WHITESPACE_ELEMENTS.has(name)) {
        node.insertBefore(N.text(' '));
        if (node.first) node.insertAfter(N.text(' '));
      }
      if (node.first && !removeContents.has(name)) for (const c of node.children()) node.insertBefore(c);
      if (rep) bump(rep.elements, name);
      node.unlink();
      return;
    }
    const allow = attrs.get(name) ?? all;
    if (!allow) {
      for (const a of node.attrs) if (rep) bump(rep.attributes, a.name);
      node.attrs = [];
    } else {
      for (const attr of [...node.attrs]) {
        const an = attr.name.toLowerCase();
        const drop = () => { node.attrs = node.attrs.filter((x) => x !== attr); if (rep) bump(rep.attributes, an); };
        if (!allow.has(an)) { drop(); continue; }
        const pr = cfg.protocols[name]?.[an];
        if (pr) {
          const m = REGEX_PROTOCOL.exec(attr.value);
          if (m) { if (!pr.includes(m[1]!.toLowerCase())) { drop(); continue; } }
          else if (!pr.includes(':relative')) { drop(); continue; }
          attr.value = strip(attr.value);
        }
        if (an === 'action' || an === 'href' || an === 'src' || (name === 'a' && an === 'name')) {
          attr.value = attr.value.replace(/[ "]/g, (c) => (c === ' ' ? '%20' : '%22'));
        }
      }
    }
    const add = cfg.addAttributes[name];
    if (add) for (const [k, v] of Object.entries(add)) node.setAttr(k, v);
    if (name === 'iframe') for (const c of node.children()) c.unlink();
    else if (name === 'noscript') node.unlink();
  };
}

const cleanComment: Transformer = (env) => {
  if (env.node.kind === Kind.Comment && !env.isAllowlisted) { if (env.ctx.report) bump(env.ctx.report.elements, '#comment'); env.node.unlink(); }
};
const cleanDoctype: Transformer = (env) => { if (!env.isAllowlisted && env.node.kind === Kind.Doctype) env.node.unlink(); };

function traverse(node: N, cb: (n: N) => void): void {
  cb(node);
  let child = node.first;
  while (child) {
    const prev = child.prev;
    traverse(child, cb);
    if (child.parent === node) child = child.next;
    else child = prev ? prev.next : node.first;
  }
}

/** Sanitize#node!: run the transformers over node and its descendants, parents first. */
function sanitizeNode(node: N, transformers: Transformer[], ctx: Ctx): void {
  const allowlist = new Set<N>();
  traverse(node, (n) => {
    for (const t of transformers) {
      const res = t({ node: n, name: n.name.toLowerCase(), isAllowlisted: allowlist.has(n), allowlist, ctx });
      if (res) for (const a of res.allowlist) allowlist.add(a);
    }
  });
}

const baseTransformers = (cfg: Config): Transformer[] => [cleanElementFor(cfg), cleanComment, cleanDoctype];

// ---- otwarchive transformers ------------------------------------------------------------------------------

const openAttribute: Transformer = (env) => {
  if (env.name === 'details' && env.node.hasAttr('open')) env.node.setAttr('open', 'open');
};

const relativeImagePath: Transformer = (env) => {
  const n = env.node;
  if (!(env.name === 'img' && n.kind === Kind.Element)) return;
  const src = n.attr('src');
  if (src === undefined) return;
  try {
    const abs = uri.uriJoin(env.ctx.appUrl, src);
    if (abs !== src && env.ctx.report) env.ctx.report.normalized++;
    n.setAttr('src', abs);
  } catch (e) { if (!(e instanceof uri.UriError)) throw e; }
};

const userClass: Transformer = (env) => {
  const n = env.node;
  const v = n.kind === Kind.Element ? n.attr('class') : undefined;
  if (v === undefined || isBlank(v)) return;
  const names = v.split(new RegExp(`[ \\t\\n\\v\\f\\r]+`)).filter((c) => c !== ''); // Ruby split(" ")
  const ok = names.filter((c) => /^[a-zA-Z][\w-]+$/.test(c));
  if (ok.length !== names.length && env.ctx.report) bump(env.ctx.report.attributes, 'class');
  n.setAttr('class', ok.join(' '));
};

// EmbedSanitizer
const EMBED_HOSTS: Record<string, RegExp> = {
  '4shared': /^4shared\.com\/web\/embed/m, audiocom: /^audio\.com\/embed\/audio\//m, archiveorg: /^archive\.org\/embed\//m,
  bilibili: /^(player\.)?bilibili\.com\//m, criticalcommons: /^criticalcommons\.org\//m, podfic: /^podfic\.com\//m,
  soundcloud: /^(w\.)?soundcloud\.com\//m, spotify: /^(open\.)?spotify\.com\//m, viddersnet: /^vidders\.net\//m,
  viddertube: /^viddertube\.com\//m, vimeo: /^(player\.)?vimeo\.com\//m, youtube: /^youtube(-nocookie)?\.com\//m,
};
const ALLOWS_FLASHVARS = new Set(['criticalcommons', 'eighttracks', 'podfic', 'soundcloud', 'spotify', 'viddersnet']);
const SUPPORTS_HTTPS = new Set(['4shared', 'audiocom', 'archiveorg', 'bilibili', 'eighttracks', 'podfic', 'soundcloud', 'spotify', 'viddersnet', 'viddertube', 'vimeo', 'youtube']);

function standardizeUrl(url: string | undefined): string | null {
  if (url === undefined) return null;
  const stripped = url.replace(new RegExp(`^(?:https?:)?//(?:www\\.)?`, 'i'), '');
  try { return uri.normalize(stripped); } catch (e) { if (e instanceof uri.UriError) return null; throw e; }
}

function nestedClean(node: N, cfg: Config, ctx: Ctx): void {
  sanitizeNode(node, baseTransformers(cfg), ctx);
}

const embedSanitizer: Transformer = (env) => {
  if (env.isAllowlisted) return;
  const node = env.node;
  if (node.kind !== Kind.Element) return;
  const name = node.name.toLowerCase();
  const parentName = node.parent && node.parent.kind === Kind.Element ? node.parent.name.toLowerCase() : undefined;
  const isEmbed = (name === 'param' && parentName === 'object') || name === 'embed' || name === 'iframe';
  if (!isEmbed) return;
  let url: string | undefined;
  if (name === 'param') {
    const movie = node.parent!.descendants((n) => n.kind === Kind.Element && n.name === 'param' && n.attr('name') === 'movie')[0];
    if (!movie) return;
    url = movie.attr('value');
  } else url = node.attr('src');
  const sourceUrl = standardizeUrl(url);
  if (sourceUrl === null) return;
  let source: string | undefined;
  for (const [k, re] of Object.entries(EMBED_HOSTS)) if (re.test(sourceUrl)) { source = k; break; }
  if (!source) return;
  const allowsFlash = ALLOWS_FLASHVARS.has(source);
  if (SUPPORTS_HTTPS.has(source) && node.attr('src')) {
    node.setAttr('src', node.attr('src')!.replaceAll('http:', 'https:'));
    const fv = node.attr('flashvars');
    if (allowsFlash && fv) node.setAttr('flashvars', fv.replaceAll('http:', 'https:').replaceAll('http%3A', 'https%3A'));
  }
  const disableScripts = (e: N) => {
    e.setAttr('allowscriptaccess', 'never');
    e.setAttr('allownetworking', 'internal');
    for (const p of e.descendants((n) => n.kind === Kind.Element && n.name === 'param')) {
      const pn = (p.attr('name') ?? '').toLowerCase();
      if (pn === 'allowscriptaccess' || pn === 'allownetworking') p.unlink();
    }
  };
  if (parentName === 'object') {
    const parent = node.parent!;
    nestedClean(parent, {
      elements: new Set(['embed', 'object', 'param']),
      attributes: { embed: ['allowfullscreen', 'height', 'src', 'type', 'width'], object: ['height', 'width'], param: ['name', 'value'] },
      addAttributes: {}, protocols: {},
    }, env.ctx);
    disableScripts(parent);
    return { allowlist: [node, parent] };
  }
  nestedClean(node, {
    elements: new Set(['embed', 'iframe']),
    attributes: {
      embed: ['allowfullscreen', 'height', 'src', 'type', 'width', ...(allowsFlash ? ['wmode', 'flashvars'] : [])],
      iframe: ['allow', 'allowfullscreen', 'frameborder', 'height', 'src', 'title', 'class', 'type', 'width'],
    },
    addAttributes: {}, protocols: {},
  }, env.ctx);
  if (name === 'embed') {
    disableScripts(node);
    if (!allowsFlash) node.setAttr('flashvars', '');
  }
  if (name === 'iframe') {
    const allow = node.attr('allow');
    if (allow !== undefined && !isBlank(allow)) {
      if (allow.split(/[ \t\r\n\f\v;,]+/).includes('fullscreen')) node.setAttr('allow', 'fullscreen'); else node.removeAttr('allow');
    }
  }
  return { allowlist: [node] };
};

// MediaSanitizer
const MEDIA_CFG: Config = {
  elements: new Set(['audio', 'video', 'source', 'track', ...ARCHIVE_ELEMENTS]),
  attributes: {
    ...ARCHIVE.attributes,
    audio: ['class', 'controls', 'crossorigin', 'dir', 'loop', 'muted', 'preload', 'src', 'title'],
    video: ['class', 'controls', 'crossorigin', 'dir', 'height', 'loop', 'muted', 'playsinline', 'poster', 'preload', 'src', 'title', 'width'],
    source: ['src', 'type'],
    track: ['default', 'kind', 'label', 'src', 'srclang'],
  },
  addAttributes: {
    ...ARCHIVE.addAttributes,
    audio: { controls: 'controls', crossorigin: 'anonymous', preload: 'metadata' },
    video: { controls: 'controls', playsinline: 'playsinline', crossorigin: 'anonymous', preload: 'metadata' },
  },
  protocols: {
    ...ARCHIVE.protocols,
    audio: { src: ['http', 'https'] }, video: { poster: ['http', 'https'], src: ['http', 'https'] },
    source: { src: ['http', 'https'] }, track: { src: ['http', 'https'] },
  },
};

export class SanitizerFailure extends Error {}

const mediaSanitizer: Transformer = (env) => {
  if (env.isAllowlisted) return;
  const node = env.node;
  if (node.kind !== Kind.Element) return;
  const name = node.name.toLowerCase();
  if (!['audio', 'video', 'source', 'track'].includes(name)) return;
  // Ruby computes the source host (and raises on an unparseable URL) even though BANNED_MULTIMEDIA_SRCS is empty.
  const src = node.attr('src') ?? '';
  if (src !== '') {
    try { uri.normalizedHost(/http/.test(src) ? src : 'https://' + src); }
    catch (e) { if (e instanceof uri.UriError) throw new SanitizerFailure('Addressable::URI::InvalidURIError'); throw e; }
  }
  nestedClean(node, MEDIA_CFG, env.ctx);
  for (const k of ['default', 'loop', 'muted']) if (node.hasAttr(k)) node.setAttr(k, k);
  return { allowlist: [node] };
};

/** Sanitize.clean(html, config) with otwarchive's transformers for the variant. Returns the serialized fragment. */
export function sanitizeClean(html: string, variant: Variant, ctx: Ctx): string {
  const cfg = variant === 'summary' ? ARCHIVE : CSS_ALLOWED;
  const transformers: Transformer[] = [openAttribute, relativeImagePath];
  if (variant === 'content') transformers.push(embedSanitizer, mediaSanitizer);
  if (variant !== 'summary') transformers.push(userClass);
  transformers.push(...baseTransformers(cfg));
  const frag = parseIn('body', html.replace(REGEX_UNSUITABLE_CHARS, ''));
  sanitizeNode(frag, transformers, ctx);
  return childrenToHtml(frag, true);
}

export type { Ctx };
