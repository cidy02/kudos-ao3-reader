// AO3's word count (spec 3.6, OD3), the same five steps as the app's AO3WordCounter.swift, counted per text node.
import type { Node as PMNode } from 'prosemirror-model';
import { parseFragment } from 'parse5';

const SCRIPTS = '\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}\\p{Script=Thai}';
// AO3's `[scripts]|((?!scripts)[[:word:]])+`, with Ruby's [[:word:]] (Alphabetic, marks, decimal digits, connectors).
const WORD = new RegExp(`[${SCRIPTS}]|(?:(?![${SCRIPTS}])[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}])+`, 'gu');

/** Steps 2 to 5 over one text node's text. */
export function countText(text: string): number {
  const normalized = text.replaceAll('--', '—').replace(/['’‘-]/g, '');
  let n = 0;
  WORD.lastIndex = 0;
  while (WORD.exec(normalized)) n++;
  return n;
}

/** Text nodes of an HTML string (a preserved slice); comments, tags and attributes are not words. */
export function countHtml(html: string): number {
  let n = 0;
  const walk = (node: any): void => {
    if (node.nodeName === '#text') n += countText(node.value);
    else if (node.nodeName !== '#comment') for (const c of node.content?.childNodes ?? node.childNodes ?? []) walk(c);
  };
  walk(parseFragment(html));
  return n;
}

/** Words in one node of the document: each ProseMirror text node is one AO3 text node (marks split both alike). */
export function countNode(node: PMNode): number {
  if (node.isText) return countText(node.text!);
  const name = node.type.name;
  if (name === 'raw_block' || name === 'raw_inline') return countHtml(String(node.attrs.source ?? ''));
  let n = 0;
  node.forEach((child) => { n += countNode(child); });
  return n;
}
