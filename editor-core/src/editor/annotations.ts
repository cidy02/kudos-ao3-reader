// Private notes anchored in the text, and TK markers (T-576d, canvas v156): highlights drawn over the document, never
// part of it. Nothing here is ever serialized: notes and TKs live in the native documents store (574a), anchored by
// quote in the chapter's HTML, and come to the page as offset ranges of the HTML-mode text.
import { Plugin, PluginKey } from 'prosemirror-state';
import type { EditorState, Transaction } from 'prosemirror-state';
import { Decoration, DecorationSet } from 'prosemirror-view';

export type AnnotationKind = 'note' | 'tk';
export type PlacedAnnotation = { id: string; kind: AnnotationKind; from: number; to: number };

const key = new PluginKey<DecorationSet>('kudosAnnotations');

/** Highlights follow every edit (DecorationSet.map); setting a new list replaces them all. */
export const annotationsPlugin = new Plugin<DecorationSet>({
  key,
  state: {
    init: () => DecorationSet.empty,
    apply(tr, set) {
      const next = tr.getMeta(key) as DecorationSet | undefined;
      return next ?? set.map(tr.mapping, tr.doc);
    },
  },
  props: { decorations: (state) => key.getState(state) },
});

export function setAnnotations(state: EditorState, items: PlacedAnnotation[]): Transaction {
  const decorations = items
    .filter((a) => a.from < a.to)
    .map((a) => Decoration.inline(a.from, a.to, {
      class: `kd-annotation kd-${a.kind}`,
      'data-annotation': a.id,
    }, { id: a.id, kind: a.kind, inclusiveStart: false, inclusiveEnd: false }));
  return state.tr.setMeta(key, DecorationSet.create(state.doc, decorations)).setMeta('addToHistory', false);
}

/** The annotations covering a document position (a tap). */
export function annotationsAt(state: EditorState, pos: number): string[] {
  const set = key.getState(state) ?? DecorationSet.empty;
  return set.find(pos, pos).map((d) => String((d.spec as { id: string }).id));
}

/** Every highlight with where it now is (after edits), for tests and for re-reporting. */
export function currentAnnotations(state: EditorState): PlacedAnnotation[] {
  const set = key.getState(state) ?? DecorationSet.empty;
  return set.find().map((d) => ({ id: String((d.spec as { id: string }).id), kind: (d.spec as { kind: AnnotationKind }).kind, from: d.from, to: d.to }));
}

/** A "TK" the writer just finished typing: the token, followed by a space or punctuation, at the caret. */
export function typedTK(state: EditorState): { from: number; to: number } | null {
  const { $head, empty } = state.selection;
  if (!empty || !$head.parent.inlineContent) return null;
  const before = $head.parent.textBetween(Math.max(0, $head.parentOffset - 4), $head.parentOffset, undefined, '￼');
  const m = /(?:^|[^\p{L}\p{N}])TK[\s.,;:!?)\]—–-]$/u.exec(before);
  if (!m) return null;
  const end = $head.pos - 1; // just before the space or punctuation
  return { from: end - 2, to: end };
}

/** The letters of the word before the caret, for name suggestions on the keys bar; null when there are fewer than two. */
export function wordAtCaret(state: EditorState): string | null {
  const { $head, empty } = state.selection;
  if (!empty || !$head.parent.inlineContent) return null;
  const before = $head.parent.textBetween(Math.max(0, $head.parentOffset - 40), $head.parentOffset, undefined, '￼');
  const m = /[\p{L}\p{M}'’-]{2,40}$/u.exec(before);
  const after = $head.parent.textBetween($head.parentOffset, Math.min($head.parent.content.size, $head.parentOffset + 1), undefined, '￼');
  if (!m || /^[\p{L}\p{M}'’-]/u.test(after)) return null; // only at the end of a word, a hyphenated one included
  return m[0];
}
