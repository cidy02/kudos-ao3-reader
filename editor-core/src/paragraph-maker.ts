// Derived from otwarchive (Organization for Transformative Works), GPL-2.0-or-later; see editor-core/NOTICE.
// Port of otwarchive's lib/paragraph_maker.rb (452391b6), function for function, on the dom.ts tree.
import { Kind, N } from './dom.ts';
import { parseIn, toHtml } from './html5.ts';
import { POSIX_SPACE, lstrip, rstrip } from './ruby.ts';

const INLINE_INVALID_TAGS = ['button', 'input', 'label', 'map', 'select', 'textarea'];
const BLOCK_INVALID_TAGS = ['fieldset', 'form'];
/** Sanitize::Config::ARCHIVE[:remove_contents] */
export const REMOVE_CONTENTS = ['iframe', 'math', 'noembed', 'noframes', 'noscript', 'plaintext', 'script', 'style', 'svg', 'xmp'];

const TAG_NAMES_TO_SKIP = new Set([
  'a', 'abbr', 'acronym', 'address', 'audio', 'dl', 'embed', 'figure', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'img', 'ol',
  'object', 'p', 'pre', 'source', 'summary', 'table', 'track', 'video', 'ul', ...INLINE_INVALID_TAGS, ...REMOVE_CONTENTS,
]);
const TAG_NAMES_TO_WRAP = new Set([
  'a', 'abbr', 'acronym', 'b', 'big', 'br', 'cite', 'code', 'del', 'dfn', 'em', 'i', 'img', 'ins', 'kbd', 'q', 'rp', 'rt', 'ruby',
  's', 'samp', 'small', 'span', 'strike', 'strong', 'sub', 'sup', 'tt', 'u', 'var', ...INLINE_INVALID_TAGS,
]);
const TAG_NAMES_TO_UNWRAP = new Set([
  'audio', 'details', 'dl', 'figure', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'ol', 'p', 'pre', 'source', 'summary', 'table', 'track', 'ul', 'video',
]);
const TAG_NAMES_STRIP_WHITESPACE = new Set([
  'audio', 'blockquote', 'br', 'center', 'details', 'dl', 'div', 'figure', 'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'ol',
  'p', 'pre', 'source', 'summary', 'table', 'track', 'ul', 'video', ...BLOCK_INVALID_TAGS, ...REMOVE_CONTENTS,
]);

/** What the loss report counts as "normalized": edits ParagraphMaker made that change bytes, not meaning. */
export type PmStats = { stripped: number; splits: number; wraps: number; unwraps: number; emptyDeleted: number };

function traverse(node: N, cb: (n: N) => void): void {
  cb(node);
  if (TAG_NAMES_TO_SKIP.has(node.name)) return;
  for (const c of node.children()) traverse(c, cb);
}

function inParagraph(node: N): boolean {
  if (!node.parent) return false;
  if (node.parent.name === 'p') return true;
  return inParagraph(node.parent);
}

function stripWhitespace(root: N, st: PmStats): void {
  traverse(root, (node) => {
    if (!node.isText) return;
    const before = node.text;
    const prevName = node.prev ? node.prev.name : node.parent?.name;
    if (prevName !== undefined && TAG_NAMES_STRIP_WHITESPACE.has(prevName)) node.text = lstrip(node.text);
    const nextName = node.next ? node.next.name : node.parent?.name;
    if (nextName !== undefined && TAG_NAMES_STRIP_WHITESPACE.has(nextName)) node.text = rstrip(node.text);
    if (node.text !== before) st.stripped++;
    if (node.text === '') node.unlink();
  });
}

const NEWLINE_SPLIT = new RegExp(`([${POSIX_SPACE}]*\\n[${POSIX_SPACE}]*)`);

/** `node.add_previous_sibling("<html string>")`: parsed in the context of node's parent, inserted in order before node. */
function addBeforeHtml(node: N, html: string): void {
  const frag = parseIn(node.parent!.name, html);
  for (const c of frag.children()) node.insertBefore(c);
}

function splitTextAtNewlines(root: N, st: PmStats): void {
  traverse(root, (node) => {
    if (!node.isText) return;
    // Ruby: node.to_s is the escaped serialization, and each piece is re-parsed as HTML.
    const pieces = toHtml(node).split(NEWLINE_SPLIT);
    if (pieces.length <= 1) return;
    for (const piece of pieces) {
      if (piece === '') continue;
      const newlines = piece.split('\n').length - 1;
      if (newlines === 0) addBeforeHtml(node, piece);
      else if (newlines === 1) addBeforeHtml(node, '<br>\n');
      else if (newlines === 2) addBeforeHtml(node, '<split>');
      else addBeforeHtml(node, '<split long>');
    }
    st.splits++;
    node.unlink();
  });
}

function replaceWithHtml(node: N, html: string): void {
  const frag = parseIn(node.parent!.name, html);
  for (const c of frag.children()) node.insertBefore(c);
  node.unlink();
}

function mergeBrTags(root: N, st: PmStats): void {
  traverse(root, (node) => {
    if (!(node.name === 'br' && node.next?.name !== 'br' && node.prev?.name === 'br')) return;
    let breakCount = 1;
    while (node.prev && node.prev.name === 'br') { node.prev.unlink(); breakCount++; }
    st.splits++;
    replaceWithHtml(node, breakCount === 2 ? '<split>' : '<split long>');
  });
}

function wrapAll(root: N, st: PmStats): void {
  if (TAG_NAMES_TO_SKIP.has(root.name) || inParagraph(root) || root.name === 'p') return;
  const chunks: { wrap: boolean; nodes: N[] }[] = [];
  for (const node of root.children()) {
    const wrap = node.isText || TAG_NAMES_TO_WRAP.has(node.name);
    const last = chunks[chunks.length - 1];
    if (last && last.wrap === wrap) last.nodes.push(node); else chunks.push({ wrap, nodes: [node] });
  }
  for (const { wrap, nodes } of chunks) {
    if (wrap) {
      const p = N.element('p');
      nodes[0]!.insertBefore(p);
      for (const n of nodes) p.appendChild(n);
      st.wraps++;
    } else {
      for (const n of nodes) wrapAll(n, st);
    }
  }
}

function splitParent(node: N): void {
  const parent = node.parent!;
  if (!node.prev) { parent.insertBefore(node); return; }
  if (!node.next) { parent.insertAfter(node); return; }
  const np = N.element(parent.name, parent.ns);
  for (const a of parent.attrs) np.setAttr(a.name, a.value);
  parent.insertAfter(np);
  while (node.next) np.appendChild(node.next);
  parent.insertAfter(node);
}

function extractFromParagraph(node: N): void {
  while (inParagraph(node)) splitParent(node);
}

function unwrapAll(root: N, st: PmStats): void {
  traverse(root, (node) => {
    if (TAG_NAMES_TO_UNWRAP.has(node.name) && inParagraph(node)) { extractFromParagraph(node); st.unwraps++; }
  });
}

function replaceSplits(root: N): void {
  for (const node of root.descendants((n) => n.kind === Kind.Element && n.name === 'split')) {
    extractFromParagraph(node);
    replaceWithHtml(node, node.hasAttr('long') ? '\n<p>&nbsp;</p>\n' : '\n');
  }
}

function deleteEmptyParagraphs(root: N, st: PmStats): void {
  traverse(root, (node) => {
    if (node.name === 'p' && !node.first) { node.unlink(); st.emptyDeleted++; }
  });
}

export function process(root: N): PmStats {
  const st: PmStats = { stripped: 0, splits: 0, wraps: 0, unwraps: 0, emptyDeleted: 0 };
  stripWhitespace(root, st);
  splitTextAtNewlines(root, st);
  mergeBrTags(root, st);
  wrapAll(root, st);
  unwrapAll(root, st);
  replaceSplits(root);
  deleteEmptyParagraphs(root, st);
  return st;
}

/** HtmlCleaner#add_paragraphs_to_text */
export function addParagraphsToText(text: string, stats?: PmStats[]): string {
  const doc = parseIn('body', `<myroot>${text}</myroot>`);
  const myroot = doc.first;
  if (!myroot) return '';
  const st = process(myroot);
  stats?.push(st);
  let out = '';
  for (let c = myroot.first; c; c = c.next) out += toHtml(c);
  return out;
}
