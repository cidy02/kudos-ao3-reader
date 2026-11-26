// A deterministic 510,000-character chapter at AO3's limit (spec 9.1): paragraphs of 40-120 words, about 5% formatted
// runs, blockquotes, lists, hr, one table, one work-skin div, non-Latin text. Mirrors Scripts/make-writing-fixture.py's
// description; this copy is for the Node regression guard only.
const LIMIT = 510_000;

export function makeFixture(kind: 'html' | 'plain' = 'html', seed = 510): string {
  let a = seed >>> 0;
  const rnd = () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const latin = 'the lantern swung over quiet water while she counted gulls and boats and the long slow tide that never quite came back'.split(' ');
  const other = ['星', '光', '日本語', 'テキスト', 'привет', 'мир', 'مرحبا', 'עולם', 'café', 'naïve', 'señor', '한국어'];
  const word = () => (rnd() < 0.06 ? other[Math.floor(rnd() * other.length)]! : latin[Math.floor(rnd() * latin.length)]!);
  const words = (n: number) => Array.from({ length: n }, word).join(' ');
  const sentence = () => {
    const n = 40 + Math.floor(rnd() * 81);
    const parts: string[] = [];
    for (let i = 0; i < n; ) {
      const run = Math.min(n - i, 1 + Math.floor(rnd() * 6));
      const w = words(run);
      const r = rnd();
      parts.push(kind === 'html' && r < 0.03 ? `<em>${w}</em>` : kind === 'html' && r < 0.05 ? `<strong>${w}</strong>` : w);
      i += run;
    }
    return parts.join(' ') + '.';
  };
  const out: string[] = [];
  let len = 0;
  const push = (s: string) => { out.push(s); len += s.length + 1; };
  let i = 0;
  while (len < LIMIT - 2000) {
    const r = i % 40;
    if (kind === 'plain') push(sentence());
    else if (r === 7) push(`<blockquote><p>${sentence()}</p></blockquote>`);
    else if (r === 15) push(`<ul>\n<li>${words(8)}</li>\n<li>${words(12)}</li>\n<li>${words(6)}</li>\n</ul>`);
    else if (r === 23) push('<hr>');
    else if (r === 31) push(`<ol><li>${words(10)}</li><li>${words(10)}</li></ol>`);
    else if (r === 39 && i < 100) push('<table border="1"><tr><th>Day</th><th>Light</th></tr><tr><td>Mon</td><td>dusk</td></tr></table>');
    else if (i === 20) push(`<div class="workskin-letter"><p>${sentence()}</p><p>${sentence()}</p></div>`);
    else push(`<p>${sentence()}</p>`);
    i++;
  }
  // pad to exactly the limit with a final paragraph
  const body = out.join(kind === 'plain' ? '\n\n' : '\n');
  const pad = LIMIT - body.length - (kind === 'plain' ? 2 : 8);
  const tail = kind === 'plain' ? '\n\n' + 'x'.repeat(Math.max(pad, 0)) : `\n<p>${'x'.repeat(Math.max(pad, 0))}</p>`;
  return (body + tail).slice(0, LIMIT);
}
