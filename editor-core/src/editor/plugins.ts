// Two small plugins: the document invariants edits can break (kept O(edit)), and caret tracking for the native side.
import { Plugin } from 'prosemirror-state';
import type { Transaction } from 'prosemirror-state';
import type { EditorView } from 'prosemirror-view';
import { schema } from '../index.ts';

const N = schema.nodes;

/** The ranges of `doc` the transactions touched, mapped into the final document. */
function changedRanges(trs: readonly Transaction[], size: number): [number, number][] {
  const out: [number, number][] = [];
  for (const tr of trs) {
    for (let i = 0; i < out.length; i++) out[i] = [tr.mapping.map(out[i]![0], -1), tr.mapping.map(out[i]![1], 1)];
    tr.mapping.maps.forEach((map, i) => {
      const rest = tr.mapping.slice(i + 1);
      map.forEach((_a, _b, from, to) => out.push([rest.map(from, -1), rest.map(to, 1)]));
    });
  }
  return out.map(([a, b]) => [Math.max(0, Math.min(a, b) - 1), Math.min(size, Math.max(a, b) + 1)]);
}

/**
 * After an edit, near what changed: an `implicit` paragraph (written without `<p>`) is only valid as the first child of
 * a list item, so one that moved anywhere else becomes explicit (S7); two adjacent `<br>` split the paragraph as
 * AO3's merge_br_tags does, and collapse to one in a heading or fold-out title (S10, part 1 departure 6).
 */
export const invariants = new Plugin({
  appendTransaction(trs, _old, state) {
    if (!trs.some((t) => t.docChanged)) return null;
    const implicit = new Set<number>();
    const pairs = new Set<number>();
    for (const [from, to] of changedRanges(trs, state.doc.content.size)) {
      state.doc.nodesBetween(from, to, (node, pos, parent, index) => {
        if (node.type === N.paragraph && node.attrs.implicit && !(parent?.type === N.list_item && index === 0)) implicit.add(pos);
        if (node.inlineContent) {
          let prevBreak = false;
          node.forEach((child, offset) => {
            const isBreak = child.type === N.hard_break;
            if (isBreak && prevBreak) pairs.add(pos + 1 + offset - 1);
            prevBreak = isBreak;
          });
          return false;
        }
        return true;
      });
    }
    if (!implicit.size && !pairs.size) return null;
    const tr = state.tr;
    for (const pos of implicit) tr.setNodeMarkup(pos, null, { ...state.doc.nodeAt(pos)!.attrs, implicit: false });
    for (const first of [...pairs].sort((a, b) => b - a)) {
      const at = tr.mapping.map(first);
      const $at = tr.doc.resolve(at);
      if ($at.nodeAfter?.type !== N.hard_break || tr.doc.nodeAt(at + 1)?.type !== N.hard_break) continue;
      if ($at.parent.type === N.paragraph && $at.depth > 0) tr.delete(at, at + 2).split(at);
      else tr.delete(at + 1, at + 2);
    }
    return tr.docChanged ? tr : null;
  },
});

export type CaretInfo = { x: number; y: number; height: number; block: number };

/**
 * Reports the caret rectangle (page coordinates, CSS px, which are points at zoom 1) and the top-level block index, at
 * most once per frame and only when the caret's line or block changes: enough for native typewriter scrolling (N4)
 * and the two-view highlight (7.10) without a bridge message per keystroke (D8).
 */
export class CaretTracker {
  private last = '';
  private pending = false;
  private readonly send: (c: CaretInfo) => void;
  private readonly frame: (f: () => void) => void;

  constructor(send: (c: CaretInfo) => void, frame: (f: () => void) => void) {
    this.send = send;
    this.frame = frame;
  }

  plugin(): Plugin {
    return new Plugin({
      view: () => ({
        update: (view, prev) => {
          if (view.state.doc !== prev.doc || !view.state.selection.eq(prev.selection)) this.schedule(view);
        },
      }),
    });
  }

  /** Measure on the next frame even if nothing seems to have moved (activate, rotation, a new text size). */
  force(view: EditorView): void {
    this.last = '';
    this.schedule(view);
  }

  private schedule(view: EditorView): void {
    if (this.pending) return;
    this.pending = true;
    this.frame(() => {
      this.pending = false;
      if (!view.editable || view.isDestroyed) return;
      const head = view.state.selection.head;
      let rect: { left: number; top: number; bottom: number };
      try { rect = view.coordsAtPos(head); } catch { return; }
      const win = view.dom.ownerDocument.defaultView;
      const info: CaretInfo = {
        x: Math.round(rect.left + (win?.scrollX ?? 0)),
        y: Math.round(rect.top + (win?.scrollY ?? 0)),
        height: Math.round(rect.bottom - rect.top),
        block: view.state.doc.resolve(head).index(0),
      };
      const key = `${info.y}|${info.height}|${info.block}`;
      if (key === this.last) return;
      this.last = key;
      this.send(info);
    });
  }
}
