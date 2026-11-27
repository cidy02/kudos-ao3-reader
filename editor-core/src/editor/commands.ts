// The formatting commands (576c's FormatCommand, AO3's own Rich Text toolbar, spec 3.5) and the typing commands the
// keys bar needs. Each is a ProseMirror command, so it can be asked "would you apply?" without dispatching.
import { Fragment } from 'prosemirror-model';
import type { Attrs, Mark, Node as PMNode, NodeType, ResolvedPos } from 'prosemirror-model';
import { Selection, TextSelection } from 'prosemirror-state';
import type { Command, EditorState, Transaction } from 'prosemirror-state';
import { findWrapping, liftTarget } from 'prosemirror-transform';
import { redo, undo } from 'prosemirror-history';
import { liftListItem, wrapInList } from 'prosemirror-schema-list';
import { wrapIn } from 'prosemirror-commands';
import { schema, TOOLBAR_TAG } from '../index.ts';

export type FormatMark = 'bold' | 'italic' | 'underline' | 'strikethrough' | 'superscript' | 'subscript' | 'smaller' | 'code';
export type FormatBlock = 'body' | 'heading' | 'subheading' | 'centred' | 'quote' | 'bulletedList' | 'numberedList' | 'foldOut';
export type FormatAlignment = 'left' | 'centre' | 'right' | 'justify';
export type FormatDirection = 'leftToRight' | 'rightToLeft';
export type SceneBreakStyle = 'asterism' | 'asterisks' | 'line';

const N = schema.nodes;
const M = schema.marks;

/** FormatMark -> schema mark and the tag the toolbar writes (S12). */
export const MARKS: Record<FormatMark, { type: string; tag: string; matches: (m: Mark) => boolean }> = {
  bold: { type: 'strong', tag: TOOLBAR_TAG.strong!, matches: () => true },
  italic: { type: 'em', tag: TOOLBAR_TAG.em!, matches: () => true },
  underline: { type: 'underline', tag: TOOLBAR_TAG.underline!, matches: () => true },
  strikethrough: { type: 'strike', tag: TOOLBAR_TAG.strike!, matches: () => true },
  superscript: { type: 'script', tag: 'sup', matches: (m) => m.attrs.tag === 'sup' },
  subscript: { type: 'script', tag: 'sub', matches: (m) => m.attrs.tag === 'sub' },
  smaller: { type: 'size', tag: TOOLBAR_TAG.size!, matches: (m) => m.attrs.tag === 'small' },
  code: { type: 'code', tag: TOOLBAR_TAG.code!, matches: () => true },
};
export const FORMAT_MARKS = Object.keys(MARKS) as FormatMark[];

/** The attributes a block keeps when its type changes ("G", spec 6.3). */
const keepG = (a: Attrs) => ({ align: a.align ?? null, dir: a.dir ?? null, lang: a.lang ?? null, title: a.title ?? null, class: a.class ?? null });

// ---- marks ---------------------------------------------------------------------------------------------------

/** Active when every text character in the selection carries the mark (or, for a caret, the marks typing would get). */
export function markActive(state: EditorState, fm: FormatMark): boolean {
  const def = MARKS[fm];
  const type = M[def.type]!;
  const has = (marks: readonly Mark[]) => marks.some((m) => m.type === type && def.matches(m));
  const sel = state.selection;
  if (sel.empty) return has(state.storedMarks ?? sel.$from.marks());
  let sawText = false;
  let all = true;
  for (const r of sel.ranges) {
    state.doc.nodesBetween(r.$from.pos, r.$to.pos, (node) => {
      if (!all) return false;
      if (node.isText) { sawText = true; if (!has(node.marks)) all = false; }
      return true;
    });
  }
  return sawText ? all : has(sel.$from.marks());
}

export const toggleMark = (fm: FormatMark): Command => (state, dispatch) => {
  const def = MARKS[fm];
  const type = M[def.type]!;
  const active = markActive(state, fm);
  const sel = state.selection;
  if (!dispatch) return true;
  const tr = state.tr;
  if (sel.empty) {
    if (active) tr.removeStoredMark(type);
    else tr.addStoredMark(type.create({ tag: def.tag }));
  } else {
    for (const r of sel.ranges) {
      if (active) tr.removeMark(r.$from.pos, r.$to.pos, type);
      else tr.addMark(r.$from.pos, r.$to.pos, type.create({ tag: def.tag }));
    }
    tr.scrollIntoView();
  }
  dispatch(tr);
  return true;
};

const CLEARED = ['strong', 'em', 'underline', 'strike', 'ins', 'size', 'script', 'code', 'phrase'].map((n) => M[n]!);

/** Character formatting off, headings and centring back to body text. Links and classed spans (work skins) stay. */
export const clearFormatting: Command = (state, dispatch) => {
  const tr = state.tr;
  const sel = state.selection;
  if (sel.empty) {
    const marks = (state.storedMarks ?? sel.$from.marks()).filter((m) => !CLEARED.includes(m.type));
    tr.setStoredMarks(marks);
  } else for (const r of sel.ranges) for (const t of CLEARED) tr.removeMark(r.$from.pos, r.$to.pos, t);
  eachTextblock(state, tr, (node) => node.type === N.heading || node.attrs.align
    ? { type: N.paragraph!, attrs: { ...keepG(node.attrs), align: null, implicit: node.attrs.implicit ?? false } }
    : null);
  if (!tr.docChanged && !tr.storedMarksSet) return false;
  if (dispatch) dispatch(tr.scrollIntoView());
  return true;
};

// ---- blocks --------------------------------------------------------------------------------------------------

type Found = { node: PMNode; depth: number; pos: number };
function ancestor($pos: ResolvedPos, pred: (n: PMNode) => boolean): Found | null {
  for (let d = $pos.depth; d > 0; d--) {
    const node = $pos.node(d);
    if (pred(node)) return { node, depth: d, pos: $pos.before(d) };
  }
  return null;
}
const isList = (n: PMNode) => n.type === N.bullet_list || n.type === N.ordered_list;

/** Textblocks the selection touches, with their positions in `state.doc`. */
function textblocks(state: EditorState): { node: PMNode; pos: number }[] {
  const out: { node: PMNode; pos: number }[] = [];
  const { from, to } = state.selection;
  state.doc.nodesBetween(from, to, (node, pos) => {
    if (node.isTextblock) { out.push({ node, pos }); return false; }
    return true;
  });
  return out;
}

/** Re-types or re-attributes each touched textblock where its parent allows the new type. */
function eachTextblock(state: EditorState, tr: Transaction, make: (node: PMNode, $pos: ResolvedPos) => { type: NodeType; attrs: Attrs } | null): void {
  for (const { node, pos } of textblocks(state)) {
    const at = tr.mapping.map(pos);
    const $pos = tr.doc.resolve(at);
    const next = make(node, $pos);
    if (!next) continue;
    if (next.type === node.type && Object.keys(next.attrs).every((k) => next.attrs[k] === node.attrs[k])) continue;
    if (!$pos.parent.canReplaceWith($pos.index(), $pos.index() + 1, next.type)) continue;
    tr.setNodeMarkup(at, next.type, next.attrs);
  }
}

function changeTextblocks(make: (node: PMNode, $pos: ResolvedPos) => { type: NodeType; attrs: Attrs } | null): Command {
  return (state, dispatch) => {
    const tr = state.tr;
    eachTextblock(state, tr, make);
    if (!tr.docChanged) return false;
    if (dispatch) dispatch(tr.scrollIntoView());
    return true;
  };
}

/** Runs steps that each look at the state the previous one left, as one transaction (one undo step). */
type Step = (s: EditorState) => Transaction | null;
function chain(state: EditorState, dispatch: ((tr: Transaction) => void) | undefined, steps: Step[]): boolean {
  let s = state;
  const out = state.tr;
  for (const step of steps) {
    const tr = step(s);
    if (!tr || (!tr.docChanged && !tr.selectionSet)) continue;
    for (const st of tr.steps) out.step(st);
    s = s.apply(tr);
  }
  if (!out.docChanged) return false;
  if (dispatch) dispatch(out.setSelection(Selection.fromJSON(out.doc, s.selection.toJSON())).scrollIntoView());
  return true;
}
const run = (cmd: Command): Step => (s) => {
  let out: Transaction | null = null;
  cmd(s, (tr) => { out = tr; });
  return out;
};
const repeat = (step: Step, times: number): Step[] => Array.from({ length: times }, () => step);

const liftOutOf = (type: NodeType): Step => (s) => {
  const { $from, $to } = s.selection;
  const range = $from.blockRange($to, (n) => n.type === type);
  const target = range && liftTarget(range);
  return range && target !== null && target !== undefined ? s.tr.lift(range, target) : null;
};

const liftOutOfList: Step = (s) => (ancestor(s.selection.$from, isList) ? run(liftListItem(N.list_item!))(s) : null);

/** Replaces the fold-out around the caret by its blocks; a non-empty title becomes a paragraph. */
const unwrapDetails: Step = (s) => {
  const found = ancestor(s.selection.$from, (n) => n.type === N.details);
  if (!found) return null;
  const kids: PMNode[] = [];
  let dropped = 0;
  found.node.forEach((c) => {
    if (c.type !== N.summary) kids.push(c);
    else if (c.content.size) kids.push(N.paragraph!.create(keepG(c.attrs), c.content));
    else dropped = c.nodeSize;
  });
  if (kids.length === 0) kids.push(N.paragraph!.create());
  const $at = s.doc.resolve(found.pos);
  if (!$at.parent.canReplace($at.index(), $at.index() + 1, Fragment.from(kids))) return null;
  const tr = s.tr.replaceWith(found.pos, found.pos + found.node.nodeSize, kids);
  const head = Math.max(found.pos, Math.min(s.selection.head - 1 - dropped, tr.doc.content.size));
  return tr.setSelection(TextSelection.near(tr.doc.resolve(head)));
};

const wrapDetails = (title: string): Step => (s) => {
  const { $from, $to } = s.selection;
  const range = $from.blockRange($to);
  const wrapping = range && findWrapping(range, N.details!);
  if (!range || !wrapping) return null;
  const tr = s.tr.wrap(range, wrapping);
  const at = range.start + wrapping.findIndex((w) => w.type === N.details) + 1;
  tr.insert(at, N.summary!.create(null, title ? schema.text(title) : null));
  return tr.setSelection(TextSelection.create(tr.doc, at + 1, at + 1 + title.length));
};

/** List items the toolbar makes are AO3's own shape, `<li>text</li>`: a plain leading paragraph is implicit. */
const implicitItems = (type: NodeType): Step => (s) => {
  const list = ancestor(s.selection.$from, (n) => n.type === type);
  if (!list) return null;
  const tr = s.tr;
  list.node.forEach((li, offset) => {
    const first = li.firstChild;
    if (!first || first.type !== N.paragraph || first.attrs.implicit) return;
    if (Object.values(keepG(first.attrs)).some((v) => v !== null)) return; // an implicit paragraph can't carry attributes
    tr.setNodeMarkup(list.pos + 1 + offset + 1, null, { ...first.attrs, implicit: true });
  });
  return tr.docChanged ? tr : null;
};

const setList = (type: NodeType): Command => (state, dispatch) => {
  const list = ancestor(state.selection.$from, isList);
  if (list && list.node.type === type) return chain(state, dispatch, [liftOutOfList]);
  if (list) {
    const attrs = type === N.ordered_list ? { ...keepG(list.node.attrs), start: null, type: null } : { ...keepG(list.node.attrs), type: null };
    if (dispatch) dispatch(state.tr.setNodeMarkup(list.pos, type, attrs).scrollIntoView());
    return true;
  }
  return chain(state, dispatch, [run(wrapInList(type)), implicitItems(type)]);
};

const toParagraph = (node: PMNode) => ({ type: N.paragraph!, attrs: { ...keepG(node.attrs), implicit: node.type === N.paragraph ? node.attrs.implicit : false } });

/** Plain body text: out of lists, quotes and fold-outs (work-skin containers stay), headings and centring off. */
const toBody: Command = (state, dispatch) => chain(state, dispatch, [
  ...repeat(liftOutOfList, 6),
  ...repeat(liftOutOf(N.blockquote!), 6),
  ...repeat(unwrapDetails, 6),
  (s) => {
    const tr = s.tr;
    eachTextblock(s, tr, (node) => node.type === N.paragraph && node.attrs.align !== 'center' ? null : { ...toParagraph(node), attrs: { ...toParagraph(node).attrs, align: node.attrs.align === 'center' ? null : node.attrs.align } });
    return tr.docChanged ? tr : null;
  },
]);

const headingClass = (node: PMNode): FormatBlock | null =>
  node.type !== N.heading ? null : Number(node.attrs.level) <= 3 ? 'heading' : 'subheading';

/** What the Format panel shows as the current style (576c FormatBlock). */
export function blockOf(state: EditorState): FormatBlock {
  const $from = state.selection.$from;
  const tb = $from.parent;
  const h = headingClass(tb);
  if (h) return h;
  if (tb.type === N.paragraph && tb.attrs.align === 'center') return 'centred';
  for (let d = $from.depth; d > 0; d--) {
    const n = $from.node(d);
    if (n.type === N.bullet_list) return 'bulletedList';
    if (n.type === N.ordered_list) return 'numberedList';
    if (n.type === N.blockquote) return 'quote';
    if (n.type === N.details) return 'foldOut';
  }
  return 'body';
}

/** Selecting the current style again turns it off, as AO3's toolbar buttons do. */
export const setBlock = (block: FormatBlock, opts: { foldOutTitle?: string } = {}): Command => (state, dispatch) => {
  const current = blockOf(state);
  const all = (pred: (n: PMNode) => boolean) => textblocks(state).every((t) => pred(t.node));
  switch (block) {
    case 'body': return toBody(state, dispatch);
    case 'heading': case 'subheading': {
      if (all((n) => headingClass(n) === block)) return changeTextblocks(toParagraph)(state, dispatch);
      const level = block === 'heading' ? 3 : 4; // AO3MarkupTag.heading is h3
      return changeTextblocks((n) => ({ type: N.heading!, attrs: { ...keepG(n.attrs), level } }))(state, dispatch);
    }
    case 'centred':
      if (current === 'centred' && all((n) => n.attrs.align === 'center')) return changeTextblocks((n) => ({ type: n.type, attrs: { ...n.attrs, align: null } }))(state, dispatch);
      return changeTextblocks((n) => ({ type: N.paragraph!, attrs: { ...toParagraph(n).attrs, align: 'center' } }))(state, dispatch);
    case 'quote':
      if (ancestor(state.selection.$from, (n) => n.type === N.blockquote)) return chain(state, dispatch, [liftOutOf(N.blockquote!)]);
      return wrapIn(N.blockquote!)(state, dispatch);
    case 'bulletedList': return setList(N.bullet_list!)(state, dispatch);
    case 'numberedList': return setList(N.ordered_list!)(state, dispatch);
    case 'foldOut':
      if (ancestor(state.selection.$from, (n) => n.type === N.details)) return chain(state, dispatch, [unwrapDetails]);
      return chain(state, dispatch, [wrapDetails(opts.foldOutTitle ?? 'Spoiler')]);
  }
};

const dirAt = ($pos: ResolvedPos): string | null => {
  for (let d = $pos.depth; d >= 0; d--) { const v = $pos.node(d).attrs.dir; if (v) return v as string; }
  return null;
};
const inheritedDir = ($pos: ResolvedPos): string | null => {
  for (let d = $pos.depth; d > 0; d--) { const v = $pos.node(d).attrs.dir; if (v) return v as string; }
  return null;
};

export const setAlignment = (al: FormatAlignment): Command => changeTextblocks((node, $pos) => {
  const rtl = (node.attrs.dir ?? inheritedDir($pos)) === 'rtl';
  const align = al === 'centre' ? 'center' : al === 'left' ? (rtl ? 'left' : null) : al === 'right' && rtl ? null : al;
  return { type: node.type, attrs: { ...node.attrs, align } };
});

export const setDirection = (d: FormatDirection): Command => changeTextblocks((node, $pos) => ({
  type: node.type,
  attrs: { ...node.attrs, dir: d === 'rightToLeft' ? 'rtl' : inheritedDir($pos) === 'rtl' ? 'ltr' : null },
}));

export function alignmentOf(state: EditorState): FormatAlignment {
  const $from = state.selection.$from;
  for (let d = $from.depth; d >= 0; d--) {
    const a = $from.node(d).attrs.align;
    if (a === 'center') return 'centre';
    if (a === 'left' || a === 'right' || a === 'justify') return a;
  }
  return dirAt($from) === 'rtl' ? 'right' : 'left';
}
export const directionOf = (state: EditorState): FormatDirection => (dirAt(state.selection.$from) === 'rtl' ? 'rightToLeft' : 'leftToRight');

// ---- links and images ----------------------------------------------------------------------------------------

/** The link sheet allows http, https and mailto only (spec 6.4). */
export const LINK_URL = /^(?:https?:\/\/[^\s<>"]+|mailto:[^\s<>"]+)$/i;
const IMAGE_URL = /^https?:\/\/[^\s<>"/]+[^\s<>"]*$/i;

/** The extent of the link mark around a caret (a caret just after a link counts as in it). */
export function linkAround($pos: ResolvedPos): { from: number; to: number; mark: Mark } | null {
  const link = M.link!;
  const mark = link.isInSet($pos.nodeBefore?.marks ?? []) ?? link.isInSet($pos.nodeAfter?.marks ?? []);
  if (!mark) return null;
  const start = $pos.start();
  let runStart = -1, runEnd = -1, holds = false;
  let found: { from: number; to: number } | null = null;
  $pos.parent.forEach((child, offset) => {
    if (found) return;
    const cs = start + offset, ce = cs + child.nodeSize;
    if (mark.isInSet(child.marks)) {
      if (runStart < 0) runStart = cs;
      runEnd = ce;
      if (cs <= $pos.pos && $pos.pos <= ce) holds = true;
    } else {
      if (holds) found = { from: runStart, to: runEnd };
      runStart = -1; holds = false;
    }
  });
  if (!found && holds) found = { from: runStart, to: runEnd };
  return found ? { ...(found as { from: number; to: number }), mark } : null;
}

export function linkOf(state: EditorState): Mark | null {
  const sel = state.selection;
  if (sel.empty) return linkAround(sel.$from)?.mark ?? null;
  let found: Mark | null = null;
  state.doc.nodesBetween(sel.from, sel.to, (node) => {
    if (!found && node.isInline) found = M.link!.isInSet(node.marks) ?? null;
    return !found;
  });
  return found;
}

export const setLink = (url: string): Command => (state, dispatch) => {
  const href = url.trim();
  if (!LINK_URL.test(href)) return false;
  const link = M.link!;
  const sel = state.selection;
  const tr = state.tr;
  if (sel.empty) {
    const around = linkAround(sel.$from);
    if (around) {
      tr.removeMark(around.from, around.to, link).addMark(around.from, around.to, link.create({ ...around.mark.attrs, href }));
    } else {
      const marks = link.create({ tag: 'a', href }).addToSet(state.storedMarks ?? sel.$from.marks());
      tr.insert(sel.from, schema.text(href, marks));
      tr.setSelection(TextSelection.create(tr.doc, sel.from + href.length)).setStoredMarks(link.removeFromSet(marks));
    }
  } else for (const r of sel.ranges) tr.addMark(r.$from.pos, r.$to.pos, link.create({ tag: 'a', href }));
  if (dispatch) dispatch(tr.scrollIntoView());
  return true;
};

export const unlink: Command = (state, dispatch) => {
  const sel = state.selection;
  const range = sel.empty ? linkAround(sel.$from) : linkOf(state) ? { from: sel.from, to: sel.to } : null;
  if (!range) return false;
  if (dispatch) dispatch(state.tr.removeMark(range.from, range.to, M.link!).scrollIntoView());
  return true;
};

export type ImageSpec = { address: string; description?: string | null; width?: number | null; height?: number | null };
const dimension = (v: unknown): string | null => (typeof v === 'number' && Number.isInteger(v) && v > 0 && v < 100_000 ? String(v) : null);

export const insertImage = (img: ImageSpec): Command => (state, dispatch) => {
  const src = img.address.trim();
  if (!IMAGE_URL.test(src)) return false;
  const node = N.image!.create({ src, alt: img.description?.trim() || null, width: dimension(img.width), height: dimension(img.height) });
  if (dispatch) dispatch(state.tr.replaceSelectionWith(node, false).scrollIntoView());
  return true;
};

// ---- inserted blocks -----------------------------------------------------------------------------------------

/** Puts a block after the caret's textblock (splitting it when the caret is inside) and the caret after the block. */
export const insertBlock = (node: PMNode): Command => (state, dispatch) => {
  const tr = state.tr;
  if (!state.selection.empty) tr.deleteSelection();
  const $p = tr.selection.$from;
  let at: number | null = null;
  if ($p.parent.isTextblock) {
    const size = $p.parent.content.size;
    if ($p.parentOffset === 0) at = $p.before();
    else if ($p.parentOffset === size) at = $p.after();
    else if ($p.depth > 0) { tr.split($p.pos); at = $p.pos + 1; }
    if (at !== null) {
      const $at = tr.doc.resolve(at);
      if (!$at.parent.canReplaceWith($at.index(), $at.index(), node.type)) at = null;
    }
  }
  if (at === null) {
    tr.replaceSelectionWith(node, false);
    at = tr.selection.from - node.nodeSize;
    if (at < 0 || tr.doc.nodeAt(at) !== node) at = null;
  } else tr.insert(at, node);
  let after = at === null ? tr.selection.to : at + node.nodeSize;
  const next = tr.doc.resolve(after).nodeAfter;
  if (!next || !next.isTextblock) {
    const $after = tr.doc.resolve(after);
    if ($after.parent.canReplaceWith($after.index(), $after.index(), N.paragraph!)) tr.insert(after, N.paragraph!.create());
    else after = tr.selection.to;
  }
  tr.setSelection(Selection.near(tr.doc.resolve(Math.min(after + 1, tr.doc.content.size))));
  if (dispatch) dispatch(tr.scrollIntoView());
  return true;
};

export const insertSceneBreak = (style: SceneBreakStyle): Command =>
  style === 'line'
    ? insertBlock(N.horizontal_rule!.create())
    : insertBlock(N.paragraph!.create({ align: 'center' }, schema.text(style === 'asterism' ? '⁂' : '* * *')));

/**
 * Footnotes don't exist on AO3, so Kudos writes the usual pair of anchors, which AO3 keeps: a numbered superscript
 * link down to the note, and the note at the end with its number linking back up. The caret goes to the note.
 */
export const insertFootnote: Command = (state, dispatch) => {
  let max = 0;
  state.doc.descendants((node) => {
    for (const m of node.marks) {
      const k = m.type === M.link ? /^fnref(\d+)$/.exec(String(m.attrs.name ?? '')) : null;
      if (k) max = Math.max(max, Number(k[1]));
    }
    return true;
  });
  const n = max + 1;
  const tr = state.tr;
  const at = state.selection.to;
  const ref = schema.text(String(n), [M.link!.create({ tag: 'a', href: `#fn${n}`, name: `fnref${n}` }), M.script!.create({ tag: 'sup' })]);
  tr.insert(at, ref);
  const note = N.paragraph!.create(null, [schema.text(`${n}.`, [M.link!.create({ tag: 'a', href: `#fnref${n}`, name: `fn${n}` })]), schema.text(' ')]);
  const end = tr.doc.content.size;
  tr.insert(end, note);
  tr.setSelection(TextSelection.create(tr.doc, end + note.nodeSize - 1)).setStoredMarks([]);
  if (dispatch) dispatch(tr.scrollIntoView());
  return true;
};

// ---- typing (the keys bar) -----------------------------------------------------------------------------------

export const insertText = (text: string): Command => (state, dispatch) => {
  if (!text || !state.selection.$from.parent.inlineContent) return false;
  if (dispatch) dispatch(state.tr.insertText(text).scrollIntoView());
  return true;
};

/** Wraps the selection in a pair of quotation marks, or puts the caret between a new pair. */
export const insertQuotes = (open: string, close: string): Command => (state, dispatch) => {
  const { from, to, $from } = state.selection;
  if (!$from.parent.inlineContent || !open || !close) return false;
  if (dispatch) {
    const tr = state.tr.insertText(close, to).insertText(open, from);
    tr.setSelection(from === to ? TextSelection.create(tr.doc, from + open.length) : TextSelection.create(tr.doc, from, to + open.length + close.length));
    dispatch(tr.scrollIntoView());
  }
  return true;
};

/** Replaces the word before the caret with `text` (a name suggestion from the keys bar, T-576d). */
export const completeWord = (text: string): Command => (state, dispatch) => {
  const { $head, empty } = state.selection;
  if (!empty || !text || !$head.parent.inlineContent) return false;
  const before = $head.parent.textBetween(Math.max(0, $head.parentOffset - 40), $head.parentOffset, undefined, '\ufffc');
  const m = /[\p{L}\p{M}'’-]{1,40}$/u.exec(before);
  if (!m) return false;
  if (dispatch) dispatch(state.tr.insertText(text, $head.pos - m[0].length, $head.pos).scrollIntoView());
  return true;
};

export const moveCaret = (by: number): Command => (state, dispatch) => {
  const sel = state.selection;
  if (!Number.isInteger(by) || by === 0) return false;
  const target = Math.min(Math.max((by < 0 ? sel.from : sel.to) + (sel.empty ? by : 0), 0), state.doc.content.size);
  const next = Selection.near(state.doc.resolve(target), by < 0 ? -1 : 1);
  if (dispatch) dispatch(state.tr.setSelection(next).scrollIntoView());
  return true;
};

const wordSegmenter = new Intl.Segmenter(undefined, { granularity: 'word' });

/** Word spans in a textblock, as parent offsets (leaves count as one character, as positions do). */
const wordsIn = (block: PMNode): { from: number; to: number }[] => {
  const text = block.textBetween(0, block.content.size, undefined, '￼');
  const out: { from: number; to: number }[] = [];
  for (const s of wordSegmenter.segment(text)) if (s.isWordLike) out.push({ from: s.index, to: s.index + s.segment.length });
  return out;
};

/** One word from `pos`, the way Option-arrow moves on a Mac: forward to a word's end, back to its start. */
const wordStep = (doc: PMNode, pos: number, forward: boolean): number | null => {
  const $pos = doc.resolve(pos);
  if ($pos.parent.inlineContent) {
    const start = $pos.start();
    const words = wordsIn($pos.parent);
    const off = $pos.parentOffset;
    const hit = forward ? words.find((w) => w.to > off) : words.findLast((w) => w.from < off);
    if (hit) return start + (forward ? hit.to : hit.from);
  }
  // On to the nearest textblock after (or before) this one that has a word in it; else to this block's edge.
  const hit = { pos: null as number | null };
  const inBlock = $pos.parent.inlineContent;
  const [from, to] = forward ? [inBlock ? $pos.after() : pos, doc.content.size] : [0, inBlock ? $pos.before() : pos];
  doc.nodesBetween(from, to, (node, at) => {
    if (forward && hit.pos !== null) return false;
    if (!node.isTextblock) return true;
    const w = forward ? wordsIn(node)[0] : wordsIn(node).at(-1);
    if (w) hit.pos = at + 1 + (forward ? w.to : w.from); // backward keeps the last (nearest) one
    return false;
  });
  if (hit.pos !== null) return hit.pos;
  const edge = inBlock ? (forward ? $pos.end() : $pos.start()) : pos;
  return edge !== pos ? edge : null;
};

/** Moves the caret by `by` words (T-576e, the keys bar's slide); `extend` keeps the anchor. False if nothing moved. */
export const moveWord = (by: number, extend: boolean): Command => (state, dispatch) => {
  if (!Number.isInteger(by) || by === 0 || Math.abs(by) > 1000) return false;
  const sel = state.selection;
  let head = extend ? sel.head : by > 0 ? sel.to : sel.from;
  for (let i = 0; i < Math.abs(by); i++) {
    const next = wordStep(state.doc, head, by > 0);
    if (next === null || next === head) break;
    head = next;
  }
  // between/near keep the selection inside text even from a selected scene break or Select All
  const $head = state.doc.resolve(head);
  const next = extend ? TextSelection.between(state.doc.resolve(sel.anchor), $head) : Selection.near($head, by > 0 ? 1 : -1);
  if (next.eq(sel)) return false;
  if (dispatch) dispatch(state.tr.setSelection(next).scrollIntoView());
  return true;
};

/**
 * One dictated phrase at the caret (T-576e), replacing any selection, with a space before it unless the caret is at
 * the start of a paragraph or line, after a space or an opening bracket or quote, or the phrase starts with
 * punctuation. Its own undo step comes from the caller's label.
 */
export const insertPhrase = (text: string): Command => (state, dispatch) => {
  const { from, to, $from } = state.selection;
  if (!text.trim() || !$from.parent.inlineContent) return false;
  const before = $from.parentOffset > 0 ? $from.parent.textBetween($from.parentOffset - 1, $from.parentOffset, undefined, '￼') : '';
  const glue = before && !/[\s (\[{“‘"'￼]/u.test(before) && !/^[\s.,;:!?)\]}”’…]/u.test(text) ? ' ' : '';
  if (dispatch) dispatch(state.tr.insertText(glue + text, from, to).scrollIntoView());
  return true;
};

// ---- keys ----------------------------------------------------------------------------------------------------

/** Shift+Return. S10: a break right after another splits the paragraph instead, as AO3's merge_br_tags would. */
export const hardBreak: Command = (state, dispatch) => {
  const { $from } = state.selection;
  if (!$from.parent.inlineContent) return false;
  const br = N.hard_break!;
  const tr = state.tr;
  if (!state.selection.empty) tr.deleteSelection();
  const $c = tr.selection.$from;
  const twin = $c.nodeBefore?.type === br ? $c.pos - 1 : $c.nodeAfter?.type === br ? $c.pos : -1;
  if (twin >= 0) {
    tr.delete(twin, twin + 1);
    const at = Math.min(twin, tr.doc.content.size);
    if ($c.depth === 0 || !tr.doc.resolve(at).parent.isTextblock) return false;
    tr.split(at).setSelection(TextSelection.create(tr.doc, at + 2));
  } else tr.replaceSelectionWith(br.create(), true);
  if (dispatch) dispatch(tr.scrollIntoView());
  return true;
};

export { undo, redo };
