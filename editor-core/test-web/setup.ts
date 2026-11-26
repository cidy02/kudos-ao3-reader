// A DOM for the editor tests: jsdom (MIT). Chosen over happy-dom and linkedom because ProseMirror's view needs a
// faithful Selection, Range and MutationObserver, and jsdom implements those to the spec; it has no layout, so
// rectangles are stubbed where a test needs them. Imported first (by dom.ts), before anything loads prosemirror-view.
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>', { pretendToBeVisual: true });
const w = dom.window;
const g = globalThis as Record<string, unknown>;
for (const k of ['window', 'document', 'Node', 'Element', 'HTMLElement', 'Text', 'MutationObserver', 'getComputedStyle', 'DOMParser', 'Event', 'KeyboardEvent', 'CustomEvent', 'MessageEvent']) {
  if (!(k in g) || k === 'Event' || k === 'CustomEvent' || k === 'MessageEvent') g[k] = k === 'window' ? w : k === 'getComputedStyle' ? w.getComputedStyle.bind(w) : (w as unknown as Record<string, unknown>)[k];
}
// jsdom has no layout: give ranges and elements a rectangle so coordsAtPos and posAtCoords work.
const rect = { left: 10, right: 10, top: 20, bottom: 40, width: 0, height: 20, x: 10, y: 20, toJSON() { return this; } };
(w.Range.prototype as unknown as Record<string, unknown>).getClientRects = () => [rect];
(w.Range.prototype as unknown as Record<string, unknown>).getBoundingClientRect = () => rect;
(w.Element.prototype as unknown as Record<string, unknown>).getClientRects = () => [rect];
(w.document as unknown as Record<string, unknown>).elementFromPoint = () => null;

export const jsdomWindow = w;
