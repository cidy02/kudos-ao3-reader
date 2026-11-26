// Derived from otwarchive (Organization for Transformative Works), GPL-2.0-or-later; see editor-core/NOTICE
// AO3's word count (spec 3.6, OD3): a port of otwarchive's lib/word_counter.rb (452391b6). The text is parsed as a
// whole HTML5 document, as Nokogiri::HTML5.parse does, and only text nodes under <body> count: a leading <title> or
// <style> lands in <head> and is not counted; <script>, <textarea> and <template> text in the body is.
// Each text node is counted on its own: `--` becomes `—`, apostrophes and hyphens are removed, then each Han,
// Hiragana, Katakana or Thai character is a word and each other run of word characters is a word. Goldens from the
// Ruby itself: test/golden/words.golden.json (the Swift counter is tested against the same file).
import type { Node as PMNode } from 'prosemirror-model';
import { parse } from 'parse5';

const SCRIPTS = '\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}\\p{Script=Thai}';
// Ruby's `[[:word:]]` (Onigmo, Unicode strings, as Unicode's \w): Alphabetic, marks, decimal digits, connector
// punctuation and Join_Control. So ZWNJ and ZWJ are word characters: "a\u200Cb" is one word on AO3.
const WORD = new RegExp(`[${SCRIPTS}]|(?:(?![${SCRIPTS}])[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\p{Join_Control}])+`, 'gu');

/** Steps 2 to 5 over one text node's text. */
export function countText(text: string): number {
  const normalized = text.replaceAll('--', '—').replace(/['’‘-]/g, '');
  let n = 0;
  WORD.lastIndex = 0;
  while (WORD.exec(normalized)) n++;
  return n;
}

type P5 = { nodeName: string; value?: string; childNodes?: P5[]; tagName?: string; content?: P5 };

// Gumbo keeps <![CDATA[…]]> in <svg> or <math> as a CDATA node, which is not text; parse5 reads it as text (part 1,
// departure 10). An empty comment in its place behaves as Gumbo's node does. shortcut: also rewrites a CDATA that is
// literal text inside a <textarea> or <script> of the same field; AO3's cleaner removes <svg> and <math> before it
// counts a saved chapter, so this only matters for raw HTML-mode text.
const FOREIGN = /<(?:svg|math)[\s>/]/i;
const CDATA = /<!\[CDATA\[[\s\S]*?(?:\]\]>|$)/g;

/** AO3's count for an HTML string (a whole field, or a preserved slice). */
export function countWords(html: string): number {
  if (!html) return 0;
  const doc = parse(FOREIGN.test(html) ? html.replace(CDATA, '<!---->') : html, { scriptingEnabled: false }) as unknown as P5;
  const root = doc.childNodes?.find((c) => c.tagName === 'html');
  const body = root?.childNodes?.find((c) => c.tagName === 'body');
  let n = 0;
  const walk = (node: P5): void => {
    if (node.nodeName === '#text') n += countText(node.value ?? '');
    else {
      for (const c of node.childNodes ?? []) walk(c);
      if (node.content) walk(node.content); // a <template>'s children live in its content (Nokogiri traverses them)
    }
  };
  if (body) walk(body);
  return n;
}

/** Words in one node of the editor's document: each ProseMirror text node is one AO3 text node. */
export function countNode(node: PMNode): number {
  if (node.isText) return countText(node.text!);
  const name = node.type.name;
  if (name === 'raw_block' || name === 'raw_inline') return countWords(String(node.attrs.source ?? ''));
  let n = 0;
  node.forEach((child) => { n += countNode(child); });
  return n;
}
