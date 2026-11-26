// The Rich Text canvas: a ProseMirror EditorView on part 1's schema, and the operations the bridge exposes (spec 7).
import { EditorState, Selection, TextSelection } from 'prosemirror-state';
import type { Command, Transaction } from 'prosemirror-state';
import { EditorView } from 'prosemirror-view';
import { closeHistory, history, isHistoryTransaction, redoDepth, undoDepth } from 'prosemirror-history';
import { keymap } from 'prosemirror-keymap';
import { baseKeymap } from 'prosemirror-commands';
import { liftListItem, sinkListItem, splitListItem } from 'prosemirror-schema-list';
import { activate as mapCaret, lint, load, schema } from '../index.ts';
import type { LoadResult, LossReport, Variant } from '../index.ts';
import * as cmd from './commands.ts';
import type { FormatAlignment, FormatBlock, FormatDirection, FormatMark, SceneBreakStyle } from './commands.ts';
import { IncrementalSerializer } from './incremental.ts';
import { insertPaste, pasteContent, sliceHtml, sliceText } from './paste.ts';
import type { PasteInfo } from './paste.ts';
import { CaretTracker, invariants } from './plugins.ts';
import type { CaretInfo } from './plugins.ts';
import { clipboardSerializer, DEFAULT_LABELS, domParser, markViews, nodeViews } from './render.ts';
import type { Labels } from './render.ts';
import { formatState } from './state.ts';
import type { FormatState } from './state.ts';
import { layoutIsSound, verifyLeavingRich, verifyLeavingSource } from './verify.ts';
import type { Proven, VerifyDeps } from './verify.ts';

export type EditorHooks = {
  /** A doc-changing transaction raised the revision. No text: the native side fetches text at checkpoints (I3). */
  edited(revision: number): void;
  /** Selection, stored marks or document changed: the toolbar state may have too. */
  changed(): void;
  caret(info: CaretInfo): void;
  pasted(info: PasteInfo): void;
  /** Changed top-level blocks for the native HTML mirror (7.10); only while the mirror is shown. */
  mirror(event: MirrorEvent): void;
  error(code: string, message: string): void;
};

/**
 * One update of the native HTML mirror (7.10): replace its blocks [from, to) with `blocks`, or all of them when
 * `reset`. Every block carries the text that follows it up to the next block, so the blocks joined are the HTML a
 * snapshot would return now. `activeBlockIndex` is the block holding the caret.
 */
export type MirrorEvent = {
  revision: number;
  totalBlocks: number;
  activeBlockIndex: number;
  reset: boolean;
  from: number;
  to: number;
  blocks: { html: string; separatorAfter: string }[];
};

export type EditorOptions = {
  hooks: EditorHooks;
  /** One animation frame (tests pass a synchronous or manual one). */
  frame?: (f: () => void) => void;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  /** Timers for the mirror's debounce (the bridge passes its clock). */
  timer?: { set(f: () => void, ms: number): unknown; clear(t: unknown): void };
};

/** The mirror is refreshed this long after typing stops (7.10). */
export const MIRROR_DEBOUNCE_MS = 300;

export type BridgeErrorShape = { code: string; message: string };
export const bridgeError = (code: string, message: string): BridgeErrorShape => ({ code, message });

export const COMPOSITION_CAP_MS = 500;

export class Editor {
  readonly view: EditorView;
  variant: Variant = 'content';
  revision = 0;
  private labels: Labels = { ...DEFAULT_LABELS };
  // Built once per label set: ProseMirror redraws the whole document when node view constructors change identity.
  private views = nodeViews(this.labels);
  private clipboard = clipboardSerializer(this.labels);
  private autocorrect = true;
  private locale: string | null = null;
  private loaded: LoadResult | null = null;
  private loadRevision = 0;
  private serializer = new IncrementalSerializer();
  private frozen = true;
  /** The last text handed to HTML mode; `original` when it was the loaded text itself (R1). */
  private lastSnapshot: { revision: number; html: string; original: boolean } | null = null;
  /** Blocks the switch check has proven, per load (verify.ts). */
  private proven: Proven = new WeakMap();
  private sourceVerdict: { loaded: LoadResult; html: string; result: { ok: boolean; candidateHtml: string; reason?: string } } | null = null;
  /** Whether this load's slice layout reassembles in place (verify.ts); computed once, on the first check. */
  private sound: boolean | null = null;
  private readonly hooks: EditorHooks;
  private readonly caret: CaretTracker;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly timer: NonNullable<EditorOptions['timer']>;
  /** Names of the steps on prosemirror-history's undo and redo stacks, kept in step with their depths (N6). */
  private undoLabels: string[] = [];
  private redoLabels: string[] = [];
  private mirror: { enabled: boolean; sent: EditorState['doc'][]; reset: boolean; timer: unknown; active: number } =
    { enabled: false, sent: [], reset: true, timer: null, active: -1 };

  constructor(mount: HTMLElement, opts: EditorOptions) {
    this.hooks = opts.hooks;
    this.timer = opts.timer ?? { set: (f, ms) => setTimeout(f, ms), clear: (t) => clearTimeout(t as ReturnType<typeof setTimeout>) };
    this.now = opts.now ?? (() => performance.now());
    this.sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    // WebKit suspends animation frames for a hidden page; a timer keeps caret reports flowing there too.
    const frame = (f: () => void) => (document.visibilityState === 'hidden' ? setTimeout(f, 16) : requestAnimationFrame(() => f()));
    this.caret = new CaretTracker((c) => this.hooks.caret(c), opts.frame ?? frame);
    this.view = new EditorView(mount, {
      state: this.newState(schema.nodes.doc!.create(null, schema.nodes.paragraph!.create())),
      dispatchTransaction: (tr) => this.dispatch(tr),
      ...this.props(),
    });
  }

  // ---- view setup ----------------------------------------------------------------------------------------------

  private props() {
    return {
      editable: () => !this.frozen,
      nodeViews: this.views,
      markViews,
      domParser,
      clipboardParser: domParser,
      clipboardSerializer: this.clipboard,
      clipboardTextSerializer: sliceText,
      attributes: (): Record<string, string> => ({
        class: 'kd-editor',
        role: 'textbox',
        'aria-multiline': 'true',
        'aria-label': this.labels.editor,
        'aria-readonly': this.frozen ? 'true' : 'false',
        spellcheck: 'true',
        autocorrect: this.autocorrect ? 'on' : 'off',
        autocapitalize: 'sentences',
        translate: 'no',
        ...(this.locale ? { lang: this.locale } : {}),
      }),
      handleDOMEvents: {
        paste: (_v: EditorView, e: ClipboardEvent) => this.onPaste(e),
        drop: (v: EditorView, e: DragEvent) => this.onDrop(v, e),
        copy: (_v: EditorView, e: ClipboardEvent) => this.onCopy(e, false),
        cut: (_v: EditorView, e: ClipboardEvent) => this.onCopy(e, true),
        // N12, 11: a link never navigates; the caret lands in it and the native side offers the link sheet.
        click: (_v: EditorView, e: MouseEvent) => { if ((e.target as Element | null)?.closest?.('a')) e.preventDefault(); return false; },
      },
    };
  }

  private refreshProps(): void {
    this.view.setProps(this.props());
  }

  /** A command whose transaction is its own undo step, named `label` (typing is the only thing that groups). */
  private labelled(label: string, command: Command): Command {
    return (state, dispatch, view) => command(state, dispatch && ((tr) => dispatch(closeHistory(tr.setMeta('kudosLabel', label)))), view);
  }

  private newState(doc: EditorState['doc'], selection?: Selection): EditorState {
    const c = cmd;
    const L = this.labels;
    this.undoLabels = [];
    this.redoLabels = [];
    return EditorState.create({
      doc,
      selection,
      plugins: [
        invariants,
        history(),
        keymap({
          'Mod-b': this.labelled(L.stepBold, c.toggleMark('bold')),
          'Mod-i': this.labelled(L.stepItalic, c.toggleMark('italic')),
          'Mod-u': this.labelled(L.stepUnderline, c.toggleMark('underline')),
          'Mod-z': c.undo,
          'Shift-Mod-z': c.redo,
          'Mod-y': c.redo,
          Enter: splitListItem(schema.nodes.list_item!),
          'Shift-Enter': this.labelled(L.stepLineBreak, c.hardBreak),
          Tab: sinkListItem(schema.nodes.list_item!),
          'Shift-Tab': liftListItem(schema.nodes.list_item!),
        }),
        keymap(baseKeymap),
        this.caret.plugin(),
      ],
    });
  }

  private dispatch(tr: Transaction): void {
    const before = this.view.state;
    const state = before.apply(tr);
    this.view.updateState(state);
    this.trackUndoLabels(tr, before, state);
    if (state.doc !== before.doc) {
      this.revision++;
      this.hooks.edited(this.revision);
      this.scheduleMirror(MIRROR_DEBOUNCE_MS);
    } else if (this.mirror.enabled && state.doc.resolve(state.selection.head).index(0) !== this.mirror.active) {
      this.scheduleMirror(100); // only the highlight moves
    }
    const paste = tr.getMeta('kudosPaste') as PasteInfo | undefined;
    if (paste) this.hooks.pasted(paste);
    if (state.doc !== before.doc || !state.selection.eq(before.selection) || state.storedMarks !== before.storedMarks) this.hooks.changed();
  }

  private trackUndoLabels(tr: Transaction, before: EditorState, after: EditorState): void {
    const u0 = undoDepth(before), u1 = undoDepth(after), r0 = redoDepth(before), r1 = redoDepth(after);
    if (isHistoryTransaction(tr)) {
      if (u1 < u0) this.redoLabels.push(this.undoLabels.pop() ?? this.labels.stepTyping);
      else if (r1 < r0) this.undoLabels.push(this.redoLabels.pop() ?? this.labels.stepTyping);
    } else if (u1 > u0) {
      const ui = tr.getMeta('uiEvent') as string | undefined;
      this.undoLabels.push((tr.getMeta('kudosLabel') as string | undefined)
        ?? (ui === 'paste' ? this.labels.stepPaste : ui === 'cut' ? this.labels.stepCut : ui === 'drop' ? this.labels.stepDrop : this.labels.stepTyping));
    }
    if (r1 === 0) this.redoLabels = [];
    // history may merge or drop events on its own: the depths are the truth
    while (this.undoLabels.length > u1) this.undoLabels.shift();
    while (this.undoLabels.length < u1) this.undoLabels.unshift(this.labels.stepTyping);
    while (this.redoLabels.length > r1) this.redoLabels.shift();
    while (this.redoLabels.length < r1) this.redoLabels.unshift(this.labels.stepTyping);
  }

  // ---- the HTML mirror (7.10) -----------------------------------------------------------------------------------

  /** Shows or hides the native HTML mirror; showing it sends every block once, then only what changes. */
  setMirror(enabled: boolean): void {
    this.mirror.enabled = enabled;
    this.mirror.reset = true;
    this.mirror.sent = [];
    if (this.mirror.timer !== null) this.timer.clear(this.mirror.timer);
    this.mirror.timer = null;
    if (enabled) this.scheduleMirror(0);
  }

  private scheduleMirror(ms: number): void {
    if (!this.mirror.enabled || !this.loaded) return;
    if (this.mirror.timer !== null) {
      if (ms > 0) this.timer.clear(this.mirror.timer); // debounce: wait for typing to stop
      else return;
    }
    this.mirror.timer = this.timer.set(() => { this.mirror.timer = null; this.emitMirror(); }, ms);
  }

  private emitMirror(): void {
    if (!this.mirror.enabled || !this.loaded) return;
    const doc = this.view.state.doc;
    const out = this.serializer.serialize(doc);
    const cur: EditorState['doc'][] = [];
    doc.forEach((b) => cur.push(b));
    const prev = this.mirror.sent;
    const reset = this.mirror.reset;
    let from = 0, toOld = prev.length, toNew = cur.length;
    if (!reset) {
      let prefix = 0;
      const max = Math.min(prev.length, cur.length);
      while (prefix < max && prev[prefix] === cur[prefix]) prefix++;
      let suffix = 0;
      while (suffix < max - prefix && prev[prev.length - 1 - suffix] === cur[cur.length - 1 - suffix]) suffix++;
      // and the block before: its separatorAfter depends on whether the next block is written from source
      from = Math.max(0, prefix - 1);
      toOld = prev.length - suffix;
      toNew = cur.length - suffix;
      if (prefix === prev.length && prefix === cur.length) { from = toOld = toNew = cur.length; }
    }
    const segs = out.segments;
    const blocks: MirrorEvent['blocks'] = [];
    for (let i = from; i < toNew; i++) {
      blocks.push({ html: out.html.slice(segs[i]!.start, segs[i]!.end), separatorAfter: i + 1 < segs.length ? out.html.slice(segs[i]!.end, segs[i + 1]!.start) : '' });
    }
    const active = doc.resolve(this.view.state.selection.head).index(0);
    if (!reset && blocks.length === 0 && from === toOld && active === this.mirror.active) return;
    this.mirror.sent = cur;
    this.mirror.reset = false;
    this.mirror.active = active;
    this.hooks.mirror({ revision: this.revision, totalBlocks: cur.length, activeBlockIndex: active, reset, from: reset ? 0 : from, to: reset ? 0 : toOld, blocks });
  }

  // ---- clipboard -----------------------------------------------------------------------------------------------

  private onPaste(e: ClipboardEvent): boolean {
    if (this.frozen || !e.clipboardData) return true;
    const result = pasteContent(e.clipboardData.getData('text/html'), e.clipboardData.getData('text/plain'), this.variant);
    e.preventDefault();
    if (result) this.guard(() => insertPaste(this.view, result));
    return true;
  }

  private onDrop(view: EditorView, e: DragEvent): boolean {
    if (view.dragging) return false; // a move inside the editor: ProseMirror's own slice, already clean
    e.preventDefault();
    if (this.frozen || !e.dataTransfer) return true;
    const result = pasteContent(e.dataTransfer.getData('text/html'), e.dataTransfer.getData('text/plain'), this.variant);
    const at = view.posAtCoords({ left: e.clientX, top: e.clientY })?.pos;
    if (result) this.guard(() => insertPaste(view, result, at));
    return true;
  }

  private onCopy(e: ClipboardEvent, cut: boolean): boolean {
    const sel = this.view.state.selection;
    if (sel.empty || !e.clipboardData) return false;
    const slice = sel.content();
    e.clipboardData.clearData();
    e.clipboardData.setData('text/html', sliceHtml(slice));
    e.clipboardData.setData('text/plain', sliceText(slice));
    e.preventDefault();
    if (cut && !this.frozen) this.view.dispatch(closeHistory(this.view.state.tr.deleteSelection().scrollIntoView().setMeta('uiEvent', 'cut')));
    return true;
  }

  private guard(f: () => void): void {
    try { f(); } catch (err) { this.hooks.error('paste-failed', err instanceof Error ? err.message : String(err)); }
  }

  // ---- bridge operations (spec 7.2) ----------------------------------------------------------------------------

  configure(o: { variant: Variant; locale?: string | null; labels?: Partial<Labels>; autocorrect?: boolean }): void {
    this.variant = o.variant;
    if (o.locale !== undefined) this.locale = o.locale;
    if (o.labels) {
      this.labels = { ...DEFAULT_LABELS, ...o.labels };
      this.views = nodeViews(this.labels);
      this.clipboard = clipboardSerializer(this.labels);
    }
    if (o.autocorrect !== undefined) this.autocorrect = o.autocorrect;
    this.refreshProps();
  }

  /** Replaces the document, read-only and not focused, with fresh history. */
  load(html: string, revision: number): { revision: number; loss: LossReport; timing: { parseMs: number; buildMs: number; renderMs: number } } {
    const loaded = load(html, this.variant);
    const t0 = this.now();
    this.frozen = true;
    this.view.dom.blur();
    this.view.updateState(this.newState(loaded.doc));
    this.refreshProps();
    const renderMs = this.now() - t0;
    this.loaded = loaded;
    this.revision = this.loadRevision = revision;
    this.serializer = new IncrementalSerializer(loaded.sources);
    this.lastSnapshot = null;
    this.proven = new WeakMap();
    this.sourceVerdict = null;
    this.sound = null;
    this.mirror.reset = true;
    this.mirror.sent = [];
    this.scheduleMirror(0);
    this.hooks.changed();
    return { revision, loss: loaded.loss, timing: { parseMs: loaded.timing.cleanMs, buildMs: loaded.timing.buildMs, renderMs } };
  }

  /**
   * Makes the editor editable, puts the caret at the HTML-mode offset (7.5), optionally focuses. The offset is in the
   * text HTML mode holds: the loaded text, or, after a switch out of an edited Rich Text, the snapshot it was given.
   */
  activate(caret: number | null, focus: boolean): { caretFound: boolean } {
    if (!this.loaded) throw bridgeError('not-loaded', 'activate before load');
    const doc = this.view.state.doc;
    let pos: number | null = null;
    let caretFound = false;
    if (caret !== null) {
      const snap = this.lastSnapshot;
      if (snap && !snap.original && snap.revision === this.revision) ({ pos, found: caretFound } = this.serializer.posForOffset(doc, caret));
      else if (doc === this.loaded.doc || doc.eq(this.loaded.doc)) ({ pos, caretFound } = mapCaret(this.loaded, caret));
    }
    let state = this.view.state;
    const selection = pos === null ? state.selection : TextSelection.near(state.doc.resolve(Math.min(Math.max(pos, 0), state.doc.content.size)));
    // U2: a hand-off into Rich Text (it brings the HTML-mode caret) starts with empty history. Without a caret the
    // native side is resuming Rich Text after a switch out that did not happen (a failed check), so history stays.
    state = this.frozen && caret !== null ? this.newState(state.doc, selection) : state.apply(state.tr.setSelection(selection));
    this.frozen = false;
    this.view.updateState(state);
    this.refreshProps();
    if (caret !== null) { // a hand-off in: the native mirror starts again from the text HTML mode had
      this.mirror.reset = true;
      this.mirror.sent = [];
      this.scheduleMirror(0);
    }
    if (focus) this.view.focus();
    this.caret.force(this.view);
    this.hooks.changed();
    return { caretFound };
  }

  /** Blur, read-only, and wait for IME composition to end (7.6). */
  async freeze(): Promise<{ revision: number }> {
    this.view.dom.blur();
    this.frozen = true;
    this.refreshProps();
    const start = this.now();
    await this.sleep(0);
    while (this.view.composing) {
      if (this.now() - start >= COMPOSITION_CAP_MS) {
        this.view.dom.blur();
        this.hooks.error('composition-timeout', `IME composition still open after ${COMPOSITION_CAP_MS} ms`);
        break;
      }
      await this.sleep(10);
    }
    return { revision: this.revision };
  }

  /** R1 when the document is the loaded one (the original bytes), R2 otherwise (untouched blocks from source). */
  snapshot(withCaret: boolean): { revision: number; html: string; caretOffset: number | null; words: number } {
    if (!this.loaded) throw bridgeError('not-loaded', 'snapshot before load');
    const { doc, selection } = this.view.state;
    const head = withCaret ? selection.head : undefined;
    let html: string;
    let caretOffset: number | null;
    let words: number;
    const original = doc === this.loaded.doc || doc.eq(this.loaded.doc);
    if (original) {
      html = this.loaded.sources.original;
      caretOffset = head === undefined ? null : this.loaded.sources.offsetForPos(head);
      words = this.serializer.wordCount(doc);
    } else {
      ({ html, headOffset: caretOffset, words } = this.serializer.serialize(doc, head));
    }
    this.lastSnapshot = { revision: this.revision, html, original };
    return { revision: this.revision, html, caretOffset: withCaret ? caretOffset : null, words };
  }

  /** Runs one formatting or typing command. Nothing applies while frozen (I1). */
  command(name: string, attrs: Record<string, unknown>): { applied: boolean; state: FormatState; paste?: PasteInfo } {
    if (this.frozen || !this.loaded) return { applied: false, state: this.formatState() };
    if (name === 'paste') {
      const html = typeof attrs.html === 'string' ? attrs.html : null;
      const text = typeof attrs.text === 'string' ? attrs.text : null;
      const result = pasteContent(html, text, this.variant);
      if (!result) return { applied: false, state: this.formatState() };
      insertPaste(this.view, result, undefined, this.labels.stepPaste);
      const { slice: _slice, ...paste } = result;
      return { applied: true, state: this.formatState(), paste };
    }
    const command = this.resolve(name, attrs);
    const label = this.stepLabel(name, attrs);
    const step = command && label && label !== this.labels.stepTyping ? this.labelled(label, command) : command;
    const applied = step ? step(this.view.state, (tr) => this.view.dispatch(label ? tr.setMeta('kudosLabel', label) : tr), this.view) : false;
    return { applied, state: this.formatState() };
  }

  private resolve(name: string, a: Record<string, unknown>): Command | null {
    const str = (k: string) => (typeof a[k] === 'string' ? (a[k] as string) : '');
    const num = (k: string) => (typeof a[k] === 'number' ? (a[k] as number) : null);
    const oneOf = <T extends string>(k: string, values: readonly T[]): T | null => (values.includes(a[k] as T) ? (a[k] as T) : null);
    switch (name) {
      case 'toggleMark': { const m = oneOf<FormatMark>('mark', cmd.FORMAT_MARKS); return m && cmd.toggleMark(m); }
      case 'setBlock': {
        const b = oneOf<FormatBlock>('block', ['body', 'heading', 'subheading', 'centred', 'quote', 'bulletedList', 'numberedList', 'foldOut']);
        return b && cmd.setBlock(b, { foldOutTitle: str('title') || this.labels.spoiler });
      }
      case 'setAlignment': { const al = oneOf<FormatAlignment>('alignment', ['left', 'centre', 'right', 'justify']); return al && cmd.setAlignment(al); }
      case 'setDirection': { const d = oneOf<FormatDirection>('direction', ['leftToRight', 'rightToLeft']); return d && cmd.setDirection(d); }
      case 'setLink': return cmd.setLink(str('url'));
      case 'unlink': return cmd.unlink;
      case 'insertImage': return cmd.insertImage({ address: str('address'), description: str('description'), width: num('width'), height: num('height') });
      case 'insertSceneBreak': { const s = oneOf<SceneBreakStyle>('style', ['asterism', 'asterisks', 'line']) ?? 'asterism'; return cmd.insertSceneBreak(s); }
      case 'insertFootnote': return cmd.insertFootnote;
      case 'undo': return cmd.undo;
      case 'redo': return cmd.redo;
      case 'clearFormatting': return cmd.clearFormatting;
      case 'insertText': return str('text').length <= 10_000 ? cmd.insertText(str('text')) : null;
      case 'insertQuotes': return cmd.insertQuotes(str('open') || '“', str('close') || '”');
      case 'moveCaret': return cmd.moveCaret(num('by') ?? 0);
      case 'insertLineBreak': return cmd.hardBreak;
      case 'openTableInHTML': return null; // the native side switches views; nothing changes here
      default: return null;
    }
  }

  /** The name of the undo step a command makes (N6). */
  private stepLabel(name: string, a: Record<string, unknown>): string | null {
    const L = this.labels;
    const mark: Record<string, string> = {
      bold: L.stepBold, italic: L.stepItalic, underline: L.stepUnderline, strikethrough: L.stepStrikethrough,
      superscript: L.stepSuperscript, subscript: L.stepSubscript, smaller: L.stepSmaller, code: L.stepCode,
    };
    switch (name) {
      case 'toggleMark': return mark[String(a.mark)] ?? null;
      case 'setBlock': return L.stepStyle;
      case 'setAlignment': return L.stepAlignment;
      case 'setDirection': return L.stepDirection;
      case 'setLink': return L.stepLink;
      case 'unlink': return L.stepUnlink;
      case 'insertImage': return L.stepImage;
      case 'insertSceneBreak': return L.stepSceneBreak;
      case 'insertFootnote': return L.stepFootnote;
      case 'clearFormatting': return L.stepClearFormatting;
      case 'insertQuotes': return L.stepQuotes;
      case 'insertLineBreak': return L.stepLineBreak;
      case 'insertText': return L.stepTyping;
      default: return null;
    }
  }

  formatState(): FormatState {
    const undoTitle = this.undoLabels.at(-1) ?? null;
    const redoTitle = this.redoLabels.at(-1) ?? null;
    return { ...formatState(this.view.state), undoTitle, redoTitle };
  }

  lint(html: string): { loss: LossReport } {
    return { loss: lint(html, this.variant) };
  }

  /** The switch check (7.11), O(edited blocks). Leaving HTML, the verdict for a preload is kept for the switch. */
  verifySwitch(direction: 'richToSource' | 'sourceToRich', html: string | undefined, deps?: VerifyDeps): { ok: boolean; candidateHtml: string; reason?: string } {
    if (direction === 'richToSource') {
      if (!this.loaded) throw bridgeError('not-loaded', 'verifySwitch before load');
      const doc = this.view.state.doc;
      if (doc === this.loaded.doc && !deps) {
        const original = this.loaded.sources.original;
        return html === undefined || html === original ? { ok: true, candidateHtml: original } : { ok: false, candidateHtml: original, reason: 'unedited document, but the snapshot is not the loaded text' };
      }
      const inc = deps?.blocks ? new IncrementalSerializer(this.loaded.sources, deps.blocks) : this.serializer;
      this.sound ??= layoutIsSound(this.loaded, this.variant, new IncrementalSerializer(this.loaded.sources));
      return verifyLeavingRich(doc, this.variant, inc, html, deps ? new WeakMap() : this.proven, deps, this.sound);
    }
    if (html === undefined) throw bridgeError('bad-args', 'verifySwitch sourceToRich needs html');
    const v = this.sourceVerdict;
    if (!deps && v && v.loaded === this.loaded && v.html === html) return v.result;
    const { sound, ...result } = verifyLeavingSource(html, this.variant, this.loaded ?? undefined, deps ? new WeakMap() : this.proven, deps, this.serializer);
    if (!deps && this.loaded && this.loaded.sources.original === html) {
      this.sourceVerdict = { loaded: this.loaded, html, result };
      this.sound = sound;
    }
    return result;
  }

  dispose(): void {
    this.loaded = null;
    this.lastSnapshot = null;
    this.sourceVerdict = null;
    this.mirror.sent = [];
    this.mirror.reset = true;
    this.frozen = true;
    this.view.dom.blur();
    this.view.updateState(this.newState(schema.nodes.doc!.create(null, schema.nodes.paragraph!.create())));
    this.refreshProps();
    this.serializer = new IncrementalSerializer();
  }

  /** Re-measure the caret (rotation, a new text size). */
  remeasure(): void {
    if (!this.frozen) this.caret.force(this.view);
  }
}
