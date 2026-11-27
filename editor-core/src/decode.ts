// Maps source offsets to decoded-text offsets inside one parse5 text node (spec 7.5 step 4): walks the source slice,
// decoding character references the way the HTML tokenizer does. parse5 decodes the rare reference itself.
import { parseFragment } from 'parse5';

const REF = /^&(?:#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[A-Za-z][A-Za-z0-9]*;?)/;
const cache = new Map<string, string>();

function decodeRef(ref: string): string {
  let r = cache.get(ref);
  if (r === undefined) {
    const frag = parseFragment(`<p>${ref}`) as unknown as { childNodes: { childNodes?: { value?: string }[] }[] };
    r = frag.childNodes[0]?.childNodes?.map((c) => c.value ?? '').join('') ?? ref;
    if (cache.size > 5000) cache.clear();
    cache.set(ref, r);
  }
  return r;
}

/**
 * For each UTF-16 unit of `decoded`, the offset in `source` where that unit starts. A reference that decodes to
 * several units maps all of them to the start of the reference. Entries after a mismatch are -1.
 * `ends[i]` is the offset just after the source that produced unit i.
 */
export function offsetsFor(source: string, decoded: string): { starts: Int32Array; ends: Int32Array } {
  const starts = new Int32Array(decoded.length).fill(-1);
  const ends = new Int32Array(decoded.length).fill(-1);
  let si = 0, vi = 0;
  while (vi < decoded.length && si < source.length) {
    const c = source[si]!;
    if (c === '&') {
      const m = REF.exec(source.slice(si, si + 40));
      let used = 0, units = 0;
      if (m) {
        for (let len = m[0].length; len >= 2; len--) {
          const r = decodeRef(source.slice(si, si + len));
          if (r !== source.slice(si, si + len) && decoded.startsWith(r, vi)) { used = len; units = r.length; break; }
        }
      }
      if (used) {
        for (let k = 0; k < units; k++) { starts[vi + k] = si; ends[vi + k] = si + used; }
        si += used; vi += units;
        continue;
      }
    }
    if (decoded[vi] !== c) break; // newline normalization or tokenizer quirk we do not model: stop mapping this node
    starts[vi] = si; ends[vi] = si + 1;
    si++; vi++;
  }
  return { starts, ends };
}

/** `source` (text between tags) with its character references decoded, as the tokenizer would. */
export function decodeText(source: string): string {
  let out = '';
  let si = 0;
  outer: while (si < source.length) {
    if (source[si] === '&') {
      const m = REF.exec(source.slice(si, si + 40));
      for (let len = m ? m[0].length : 0; len >= 2; len--) {
        const ref = source.slice(si, si + len);
        const r = decodeRef(ref);
        if (r !== ref) { out += r; si += len; continue outer; }
      }
    }
    out += source[si];
    si++;
  }
  return out;
}

/**
 * The length of the character reference starting at `at` in `source`, or 0 when there is none (a bare `&`, `D&D`).
 * The longest prefix that decodes to one character: `&copyright` is `&copy` and then text.
 */
export function refLength(source: string, at: number): number {
  if (source[at] !== '&') return 0;
  const m = REF.exec(source.slice(at, at + 40));
  for (let len = m ? m[0].length : 0; len >= 2; len--) {
    const ref = source.slice(at, at + len);
    const r = decodeRef(ref);
    if (r !== ref && r.length <= 2) return len;
  }
  return 0;
}

/** The start of the character reference that covers `offset` in `source`, or null when none does. */
export function refCovering(source: string, offset: number): number | null {
  const amp = source.lastIndexOf('&', offset);
  if (amp < 0 || offset - amp > 40) return null;
  const len = refLength(source, amp);
  return len && amp + len > offset ? amp : null;
}
