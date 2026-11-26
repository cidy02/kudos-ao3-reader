// Paste, drop, copy and cut (spec 6.8, 11). Pasted HTML never touches the page's DOM: it goes through editor-core's
// parse5 pipeline (the AO3 cleaning port) exactly like a loaded document, and the loss report comes back with it.
// The full paste cleaner (P2 to P5: Word, Google Docs, styles to structure) is part 2a; it slots in at `preclean`.
import { Slice } from 'prosemirror-model';
import type { Node as PMNode } from 'prosemirror-model';
import { TextSelection } from 'prosemirror-state';
import { closeHistory } from 'prosemirror-history';
import type { EditorView } from 'prosemirror-view';
import { load, schema, serializeDoc } from '../index.ts';
import type { LossReport, Variant } from '../index.ts';
import { countNode } from '../words/index.ts';

export type PasteResult = { slice: Slice; loss: LossReport; words: number; kind: 'html' | 'text' };
export type PasteInfo = { loss: LossReport; words: number; kind: 'html' | 'text' };

const escapeText = (s: string) => s.replace(/[&<>]/g, (c) => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'));

/** P1: the clipboard's HTML if there is any, else its plain text paragraphed by ParagraphMaker (via the same load). */
export function pasteContent(html: string | null | undefined, text: string | null | undefined, variant: Variant, preclean: (html: string) => string = (h) => h): PasteResult | null {
  const kind = html ? 'html' : text ? 'text' : null;
  if (!kind) return null;
  const loaded = load(kind === 'html' ? preclean(html!) : escapeText(text!), variant);
  return { slice: Slice.maxOpen(loaded.doc.content), loss: loaded.loss, words: countNode(loaded.doc), kind };
}

/** Replaces the selection (or the drop point) with the cleaned content; one undo step. */
export function insertPaste(view: EditorView, result: PasteResult, at?: number, label?: string): void {
  const tr = view.state.tr;
  if (at !== undefined) tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(Math.max(at, 0), tr.doc.content.size))));
  if (label) tr.setMeta('kudosLabel', label);
  tr.replaceSelection(result.slice).scrollIntoView().setMeta('uiEvent', at === undefined ? 'paste' : 'drop').setMeta('kudosPaste', { loss: result.loss, words: result.words, kind: result.kind } satisfies PasteInfo);
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
