// Paste, drop, copy and cut (spec 6.8, 11). Pasted HTML never touches the page's DOM: it goes through editor-core's
// paste cleaner (src/paste/: Word, Google Docs, Apple apps, styles to structure) and then the parse5 pipeline (the AO3
// cleaning port) exactly like a loaded document, and the paste report comes back with it.
import { Slice } from 'prosemirror-model';
import type { Node as PMNode } from 'prosemirror-model';
import { TextSelection } from 'prosemirror-state';
import { closeHistory } from 'prosemirror-history';
import type { EditorView } from 'prosemirror-view';
import { load, schema, serializeDoc } from '../index.ts';
import type { LossReport, Variant } from '../index.ts';
import { countNode } from '../words/index.ts';
import { precleanPaste } from '../paste/index.ts';
import type { PasteSource } from '../paste/index.ts';

/**
 * What a paste did (6.8, 6.9): the words pasted, where it came from when that can be told, what was kept (marks as
 * runs of text, blocks by kind), styles turned into structure, styles AO3 can't show, and AO3's own loss report.
 */
export type PasteInfo = {
  loss: LossReport;
  words: number;
  kind: 'html' | 'text';
  source: PasteSource | 'text';
  kept: Record<string, number>;
  converted: Record<string, number>;
  styles: Record<string, number>;
  /** A few of the removed things, most frequent first, as the writer would read them ("<font> ×3", "color ×4"). */
  examples: string[];
};
export type PasteResult = PasteInfo & { slice: Slice };

const KEPT_MARKS: Record<string, (tag: string) => string | null> = {
  strong: () => 'bold', em: () => 'italic', underline: () => 'underline', strike: () => 'strikethrough',
  script: (t) => (t === 'sub' ? 'subscript' : 'superscript'), size: (t) => (t === 'small' ? 'smaller' : null),
  code: () => 'code', link: () => 'link',
};
const KEPT_NODES: Record<string, string> = {
  paragraph: 'paragraph', heading: 'heading', blockquote: 'quote', bullet_list: 'list', ordered_list: 'list',
  horizontal_rule: 'sceneBreak', details: 'foldOut', image: 'image', raw_block: 'preserved', raw_inline: 'preserved',
};

/** What the pasted document holds, by FormatMark and block kind (marks count runs of text). */
export function keptOf(doc: PMNode): Record<string, number> {
  const kept: Record<string, number> = {};
  const bump = (k: string) => { kept[k] = (kept[k] ?? 0) + 1; };
  doc.descendants((node) => {
    const kind = KEPT_NODES[node.type.name];
    if (kind && !(node.type.name === 'paragraph' && node.attrs.implicit)) bump(kind);
    if (node.isBlock && node.attrs.align) bump(node.attrs.align === 'center' ? 'centred' : 'aligned');
    if (node.isText) for (const m of node.marks) { const k = KEPT_MARKS[m.type.name]?.(String(m.attrs.tag)); if (k) bump(k); }
    return true;
  });
  return kept;
}

function examplesOf(loss: LossReport, styles: Record<string, number>): string[] {
  const items: [string, number][] = [
    ...Object.entries(loss.dropped.elements).filter(([k]) => k !== '#comment').map(([k, n]) => [`<${k}>`, n] as [string, number]),
    ...Object.entries(loss.dropped.attributes).map(([k, n]) => [k, n] as [string, number]),
    ...Object.entries(styles),
  ];
  return items.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 5).map(([k, n]) => `${k} ×${n}`);
}

const escapeText = (s: string) => s.replace(/[&<>]/g, (c) => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'));

/** P1: the clipboard's HTML if there is any, else its plain text paragraphed by ParagraphMaker (via the same load). */
export function pasteContent(html: string | null | undefined, text: string | null | undefined, variant: Variant): PasteResult | null {
  const kind = html ? 'html' : text ? 'text' : null;
  if (!kind) return null;
  const pre = kind === 'html' ? precleanPaste(html!) : null;
  const loaded = load(pre ? pre.html : escapeText(text!), variant);
  const styles = pre?.report.styles ?? {};
  return {
    slice: Slice.maxOpen(loaded.doc.content),
    loss: loaded.loss,
    words: countNode(loaded.doc),
    kind,
    source: pre?.report.source ?? 'text',
    kept: keptOf(loaded.doc),
    converted: pre?.report.converted ?? {},
    styles,
    examples: examplesOf(loaded.loss, styles),
  };
}

/** Replaces the selection (or the drop point) with the cleaned content; one undo step. */
export function insertPaste(view: EditorView, result: PasteResult, at?: number, label?: string): void {
  const tr = view.state.tr;
  if (at !== undefined) tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(Math.max(at, 0), tr.doc.content.size))));
  if (label) tr.setMeta('kudosLabel', label);
  const { slice, ...info } = result;
  tr.replaceSelection(slice).scrollIntoView().setMeta('uiEvent', at === undefined ? 'paste' : 'drop').setMeta('kudosPaste', info satisfies PasteInfo);
  view.dispatch(closeHistory(tr)); // a paste is its own undo step (the paste report's Undo Paste)
}

/** The HTML of a slice as rich mode would write it (copy keeps AO3-clean markup). */
export function sliceHtml(slice: Slice): string {
  try {
    return serializeDoc(schema.nodes.doc!.create(null, slice.content)).html;
  } catch {
    return '';
  }
}

export function sliceText(slice: Slice): string {
  return slice.content.textBetween(0, slice.content.size, '\n\n', (leaf: PMNode) =>
    leaf.type.name === 'hard_break' ? '\n' : leaf.type.name === 'image' ? String(leaf.attrs.alt ?? '') : '');
}
