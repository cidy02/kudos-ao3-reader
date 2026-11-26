// Derived from otwarchive (Organization for Transformative Works), GPL-2.0-or-later; see editor-core/NOTICE.
// The two things otwarchive's sanitizers ask of Ruby's URI libraries, reproduced for the cases that matter:
//  - Addressable::URI.parse(url).normalize (embed and media sources), addressable 2.9.0;
//  - URI.join(APP_URL, src) (relative image paths), uri 1.1.1.
// shortcut: Addressable's IDNA is approximated by NFKC + lower-casing for non-ASCII hosts; upgrade if an embed
// host ever needs real punycode (none of the allow-listed hosts is non-ASCII, so the allow-list outcome is the same).

import { POSIX_SPACE } from './ruby.ts';

export class UriError extends Error {}

const ALPHA = 'a-zA-Z', DIGIT = '0-9';
const SUB = "!$&'()*+,;=";
const UNRES = `${ALPHA}${DIGIT}\\-._~`;
const esc = (s: string) => s.replace(/[\\\]\[^-]/g, '\\$&');
const PCHAR = `${UNRES}${esc(SUB)}:@`;
const CLASSES = {
  scheme: `${ALPHA}${DIGIT}\\-+.`,
  host: `${UNRES}${esc(SUB)}\\[:\\]`,
  pchar: PCHAR,
  fragment: `${PCHAR}/?`,
  userinfo: `${PCHAR}`,
};

const te = new TextEncoder();
const hex = (b: number) => '%' + b.toString(16).toUpperCase().padStart(2, '0');

function decodePercent(s: string, keep = ''): string {
  // decode %XX to bytes, then to a string; invalid UTF-8 stays as percent escapes
  const bytes: number[] = [];
  let out = '';
  const flush = () => {
    if (!bytes.length) return;
    try { out += new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(bytes)); }
    catch { for (const b of bytes) out += hex(b); }
    bytes.length = 0;
  };
  for (let i = 0; i < s.length; i++) {
    const m = /^%([0-9a-fA-F]{2})/.exec(s.slice(i, i + 3));
    if (m) {
      const b = parseInt(m[1]!, 16);
      if (b < 128 && keep.includes(String.fromCharCode(b))) { flush(); out += s.slice(i, i + 3); }
      else bytes.push(b);
      i += 2;
    } else {
      flush();
      const cp = s.codePointAt(i)!;
      const ch = String.fromCodePoint(cp);
      out += ch;
      if (cp > 0xffff) i++;
    }
  }
  flush();
  return out;
}

function encodeOutside(s: string, allowed: RegExp): string {
  let out = '';
  for (const ch of s) {
    if (allowed.test(ch)) out += ch;
    else for (const b of te.encode(ch)) out += hex(b);
  }
  return out;
}

function normalizeComponent(c: string, cls: string, leave = ''): string {
  const dec = decodePercent(c, leave);
  return encodeOutside(dec.normalize('NFC'), new RegExp(`^[${cls}]$`));
}

function normalizeQueryPair(c: string): string {
  const dec = decodePercent(c, '+');
  let out = '';
  const chars = [...dec];
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i]!;
    if (ch === '%') {
      if (/^2[bB]$/.test(chars.slice(i + 1, i + 3).join(''))) out += '%';
      else out += '%25';
    } else if (/^[a-zA-Z0-9\-._~!$'()*+,=:@/?]$/.test(ch)) out += ch;
    else for (const b of te.encode(ch)) out += hex(b);
  }
  return out;
}

const RULE_2A = /\/\.\/|\/\.$/gm;
const RULE_2B_2C = /\/([^/]*)\/\.\.\/|\/([^/]*)\/\.\.$/m;
const RULE_2D = /^\.\.?\/?/m;
const RULE_PREFIXED_PARENT = /^\/\.\.?\/|^(\/\.\.?)+\/?$/m;
const reEsc = (x: string) => x.replace(/[.*+?^${}()|[\]\\/-]/g, '\\$&');

/** Addressable::URI.normalize_path (not RFC 5.2.4: it keeps ".." in relative paths such as "youtube.com/../x"). */
function removeDotSegments(path: string): string {
  let p = path;
  for (;;) {
    let mod = false;
    // Ruby: `mod ||= path.gsub!(re, rep)`; gsub! is truthy exactly when the pattern matched
    const sub = (re: RegExp, rep: string) => { if (!mod) { re.lastIndex = 0; if (re.test(p)) { re.lastIndex = 0; p = p.replace(re, rep); mod = true; } } };
    sub(RULE_2A, '/');
    const pair = RULE_2B_2C.exec(p);
    const parent = pair ? pair[1] : undefined, current = pair ? pair[2] : undefined;
    if (pair && ((parent !== '.' && parent !== '..') || (current !== '.' && current !== '..'))) {
      sub(new RegExp(`/${reEsc(parent ?? '')}/\\.\\./|(/${reEsc(current ?? '')}/\\.\\.$)`, 'gm'), '/');
    }
    sub(RULE_2D, '');
    sub(RULE_PREFIXED_PARENT, '/');
    if (!mod) return p;
  }
}

const PORTS: Record<string, number> = { http: 80, https: 443, ftp: 21, tftp: 69, ssh: 22, svn: 3690, 'svn+ssh': 22, telnet: 23, nntp: 119, gopher: 70, wais: 210, ldap: 389, prospero: 1525 };

type Parsed = { scheme: string | null; authority: string | null; user: string | null; password: string | null; host: string | null; port: number | null; path: string; query: string | null; fragment: string | null };

const URIREGEX = /^(([^:/?#]+):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#([^\n]*))?$/m;

export function parse(uri: string): Parsed {
  const m = URIREGEX.exec(uri)!;
  const scheme = m[2] ?? null, authority = m[4] ?? null;
  let user: string | null = null, password: string | null = null, host: string | null = null, portS: string | null = null;
  if (authority !== null) {
    const ui = /^([^[\]]*)@/.exec(authority)?.[1];
    if (ui !== undefined) { const t = ui.trim(); user = /^([^:]*):?/.exec(t)![1]!; password = /:([^\n]*)$/.exec(t)?.[1] ?? null; }
    host = authority.replace(/^([^[\]]*)@/, '').replace(/:([^:@[\]]*?)$/, '');
    portS = /:([^:@[\]]*?)$/.exec(authority)?.[1] ?? null;
    if (portS === '') portS = null;
  }
  const p: Parsed = { scheme, authority, user, password, host, port: null, path: m[5] ?? '', query: m[7] ?? null, fragment: m[9] ?? null };
  if (scheme !== null && !/^[a-z][a-z0-9.+-]*$/i.test(scheme)) throw new UriError('Invalid scheme format');
  if (scheme !== null && scheme.trim() === '') p.scheme = null;
  if (portS !== null) {
    const d = decodePercent(portS);
    if (!/^\d+$/m.test(d)) throw new UriError('Invalid port number');
    p.port = parseInt(d, 10) || null;
  }
  if (p.path !== '' && p.path[0] !== '/' && host !== null) p.path = '/' + p.path;
  validate(p);
  return p;
}

function validate(p: Parsed): void {
  if (p.host === null && (p.port !== null || p.user !== null || p.password !== null)) throw new UriError('Hostname not supplied');
  const hasAuthority = p.host !== null;
  if (p.path !== '' && p.path[0] !== '/' && hasAuthority) throw new UriError('relative path with authority');
  if (p.path.startsWith('//') && !hasAuthority) throw new UriError('two leading slashes without authority');
  if (p.host !== null) {
    if (new RegExp(`[<>{}/\\\\?#@"${POSIX_SPACE}]`).test(p.host)) throw new UriError('Invalid character in host');
    const ip = /^\[(.*)\]$/.exec(p.host)?.[1];
    if (ip !== undefined && !new RegExp(`^[${UNRES}${esc(SUB)}:]*$`).test(ip)) throw new UriError('Invalid character in host');
  }
}

function normHost(host: string): string {
  const h = host.trim();
  if (h === '') return '';
  let r = decodePercent(h.toLowerCase());
  if (/[^\x00-\x7f]/.test(r)) r = r.normalize('NFKC').toLowerCase();
  if (/[^.]\.$/.test(r)) r = r.slice(0, -1);
  return normalizeComponent(r, CLASSES.host);
}

/** Addressable::URI.parse(url).normalize.to_s. Throws UriError where Addressable raises. */
export function normalize(url: string): string {
  const p = parse(url);
  const scheme = p.scheme === null ? null : /^\s*ssh\+svn\s*$/i.test(p.scheme) ? 'svn+ssh' : normalizeComponent(p.scheme.trim().toLowerCase(), CLASSES.scheme);
  let authority: string | null = null;
  let host: string | null = null;
  if (p.host !== null) {
    let a = '';
    const ui = p.user !== null ? (p.password !== null ? `${p.user}:${p.password}` : p.user) : null;
    if (ui !== null) a += normalizeComponent(ui, CLASSES.userinfo) + '@';
    host = normHost(p.host);
    a += host;
    if (p.port !== null && !(scheme !== null && PORTS[scheme] === p.port)) a += ':' + p.port;
    authority = a;
  }
  let path = p.path;
  if (p.scheme === null && /^(?!\/)[^/:]*:[^\n]*$/m.test(path)) path = path.replace(':', '%2F');
  path = path.trim().split('/').map((s) => normalizeComponent(s, CLASSES.pchar)).join('/');
  path = removeDotSegments(path);
  if (path === '' && scheme !== null && ['http', 'https', 'ftp', 'tftp'].includes(scheme)) path = '/';
  let query: string | null = null;
  if (p.query !== null) { const q = p.query.split('&').map(normalizeQueryPair).join('&'); query = q === '' ? null : q; }
  let fragment: string | null = null;
  if (p.fragment !== null) { const f = normalizeComponent(p.fragment, CLASSES.fragment); fragment = f === '' ? null : f; }
  const n: Parsed = { scheme, authority, user: null, password: null, host: authority === null ? null : host, port: null, path, query, fragment };
  if (authority !== null && path !== '' && path[0] !== '/') throw new UriError('relative path with authority');
  if (scheme === null && path !== '' && /^(?!\/)[^/:]*:[^\n]*$/m.test(path)) throw new UriError('ambiguous path');
  let s = '';
  if (n.scheme !== null) s += n.scheme + ':';
  if (authority !== null) s += '//' + authority;
  s += path;
  if (query !== null) s += '?' + query;
  if (fragment !== null) s += '#' + fragment;
  return s;
}

/** `Addressable::URI.parse(url).normalize.host` */
export function normalizedHost(url: string): string | null {
  const s = normalize(url);
  const p = parse(s);
  return p.host;
}

// ---- URI.join -------------------------------------------------------------------------------------------------

const SEG = "(?:%[0-9a-fA-F]{2}|[!$&-.0-9:;=@A-Z_a-z~/])";
const SEG_NC = "(?:%[0-9a-fA-F]{2}|[!$&-.0-9;=@A-Z_a-z~])";
const FRAG = "(?:%[0-9a-fA-F]{2}|[!$&-.0-9:;=@A-Z_a-z~/?])*";
const HOST = "(?:\\[[0-9A-Fa-f:.vV]+\\]|(?:%[0-9a-fA-F]{2}|[!$&-.0-9;=A-Z_a-z~])*)";
const USERINFO = "(?:%[0-9a-fA-F]{2}|[!$&-.0-9:;=A-Z_a-z~])*";
const AUTH = `(?:(${USERINFO})@)?(${HOST})(?::(\\d*))?`;
const RFC_URI = new RegExp(`^([A-Za-z][+\\-.0-9A-Za-z]*):(?:\\/\\/${AUTH}((?:\\/${SEG}*)?)|(\\/(?:(?!\\/)${SEG}+)?)|((?!\\/)${SEG}+)|())(?:\\?([^#]*))?(?:#(${FRAG}))?$`);
const RFC_REL = new RegExp(`^(?:\\/\\/${AUTH}((?:\\/${SEG}*)?)|(\\/${SEG}*)|(${SEG_NC}+(?:\\/${SEG}*)?)|())(?:\\?([^#]*))?(?:#(${FRAG}))?$`);

function splitPath(p: string): string[] { return p === '' ? [] : p.split('/'); }
function mergePath(base: string, rel: string): string {
  const basePath = splitPath(base), relPath = splitPath(rel);
  if (basePath[basePath.length - 1] === '..') basePath.push('');
  for (let i = basePath.indexOf('..'); i >= 0; i = basePath.indexOf('..')) basePath.splice(i - 1, 2);
  if (relPath.length && relPath[0] === '') { basePath.length = 0; relPath.shift(); }
  const last = relPath[relPath.length - 1];
  if (last === '.' || last === '..') relPath.push('');
  const rp = relPath.filter((x) => x !== '.');
  const tmp: string[] = [];
  for (const x of rp) { if (x === '..' && !(tmp.length === 0 || tmp[tmp.length - 1] === '..')) tmp.pop(); else tmp.push(x); }
  let addTrailer = tmp.length > 0;
  let bp = basePath;
  if (bp.length === 0) bp = ['']; else if (addTrailer) bp.pop();
  while (tmp.length) {
    const x = tmp.shift()!;
    if (x === '..') { if (bp.length > 1) bp.pop(); }
    else { bp.push(x, ...tmp); addTrailer = false; break; }
  }
  if (addTrailer) bp.push('');
  return bp.join('/');
}

/** URI.join(base, src).to_s for an absolute http(s) base without a path. Throws UriError (Ruby's InvalidURIError). */
export function uriJoin(base: string, src: string): string {
  if (/[^\x00-\x7f]/.test(src)) throw new UriError('URI must be ascii only');
  if (RFC_URI.test(src)) return absoluteToS(src);
  const m = RFC_REL.exec(src);
  if (!m) throw new UriError('bad URI');
  const [, ui, host, port, abempty, absolute, noscheme, , query, fragment] = m;
  const b = /^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)(.*)$/i.exec(base)!;
  const hasAuthority = host !== undefined || ui !== undefined || port !== undefined;
  const relPath = abempty ?? absolute ?? noscheme ?? '';
  let out = `${b[1]}://${b[2]}`;
  if (relPath === '' && !hasAuthority && query === undefined) return out + b[3] + (fragment !== undefined ? '#' + fragment : '');
  if (hasAuthority) {
    out = `${b[1]}://${ui !== undefined ? ui + '@' : ''}${host ?? ''}${port !== undefined && port !== '' ? ':' + port : ''}${relPath}`;
  } else out += mergePath(b[3]!, relPath);
  if (query !== undefined) out += '?' + query;
  if (fragment !== undefined) out += '#' + fragment;
  return out;
}

const DEFAULT_PORTS: Record<string, string> = { http: '80', https: '443', ftp: '21', ws: '80', wss: '443', ldap: '389', ldaps: '636' };
/** URI::Generic#to_s of a parsed absolute URI: lower-case scheme, default port omitted for known schemes. */
function absoluteToS(src: string): string {
  const m = /^([^:]*):(.*)$/s.exec(src)!;
  const scheme = m[1]!.toLowerCase();
  let rest = m[2]!;
  const dp = DEFAULT_PORTS[scheme];
  if (dp !== undefined) rest = rest.replace(/^(\/\/[^/?#]*?):(\d*)(?=[/?#]|$)/, (all, h, port) => (port === dp || port === '' ? h : all));
  return `${scheme}:${rest}`;
}
