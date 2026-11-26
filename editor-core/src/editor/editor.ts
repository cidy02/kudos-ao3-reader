// The Rich Text canvas: a ProseMirror EditorView on part 1's schema, and the operations the bridge exposes (spec 7).
import { EditorState, Selection, TextSelection } from 'prosemirror-state';
import type { Command, Transaction } from 'prosemirror-state';
import { EditorView } from 'prosemirror-view';
import { history } from 'prosemirror-history';
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
  error(code: string, message: string): void;
};

export type EditorOptions = {
  hooks: EditorHooks;
  /** One animation frame (tests pass a synchronous or manual one). */
  frame?: (f: () => void) => void;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
};

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

  constructor(mount: HTMLElement, opts: EditorOptions) {
    this.hooks = opts.hooks;
    this.now = opts.now ?? (() => performance.now());
    this.sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.caret = new CaretTracker((c) => this.hooks.caret(c), opts.frame ?? ((f) => requestAnimationFrame(() => f())));
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

  private newState(doc: EditorState['doc'], selection?: Selection): EditorState {
    const c = cmd;
    return EditorState.create({
      doc,
      selection,
      plugins: [
        invariants,
        history(),
        keymap({
          'Mod-b': c.toggleMark('bold'),
          'Mod-i': c.toggleMark('italic'),
          'Mod-u': c.toggleMark('underline'),
          'Mod-z': c.undo,
          'Shift-Mod-z': c.redo,
          'Mod-y': c.redo,
          Enter: splitListItem(schema.nodes.list_item!),
          'Shift-Enter': c.hardBreak,
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
    if (state.doc !== before.doc) {
      this.revision++;
      this.hooks.edited(this.revision);
    }
    const paste = tr.getMeta('kudosPaste') as PasteInfo | undefined;
    if (paste) this.hooks.pasted(paste);
    if (state.doc !== before.doc || !state.selection.eq(before.selection) || state.storedMarks !== before.storedMarks) this.hooks.changed();
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
    if (cut && !this.frozen) this.view.dispatch(this.view.state.tr.deleteSelection().scrollIntoView().setMeta('uiEvent', 'cut'));
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
    // U2: a hand-off into Rich Text starts with empty history.
    state = this.frozen ? this.newState(state.doc, selection) : state.apply(state.tr.setSelection(selection));
    this.frozen = false;
    this.view.updateState(state);
    this.refreshProps();
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
      insertPaste(this.view, result);
      return { applied: true, state: this.formatState(), paste: { loss: result.loss, words: result.words, kind: result.kind } };
    }
    const command = this.resolve(name, attrs);
    const applied = command ? command(this.view.state, (tr) => this.view.dispatch(tr), this.view) : false;
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
      case 'openTableInHTML': return null; // the native side switches views; nothing changes here
      default: return null;
    }
  }

  formatState(): FormatState {
    return formatState(this.view.state);
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
