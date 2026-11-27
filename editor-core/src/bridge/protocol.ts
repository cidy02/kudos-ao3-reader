// The JavaScript side of the bridge (spec 7.2, bridgeVersion 1). Every argument arrives as a JSON value and is checked
// here; nothing is ever evaluated or turned into script. Calls run one at a time, in the order they arrive.
import { ParseLimitError, SanitizerFailure, SCHEMA_VERSION } from '../index.ts';
import type { Variant } from '../index.ts';
import { Editor } from '../editor/editor.ts';
import type { MirrorEvent } from '../editor/editor.ts';
import type { CaretInfo } from '../editor/plugins.ts';
import type { PasteInfo } from '../editor/paste.ts';
import { DEFAULT_LABELS } from '../editor/render.ts';
import type { Labels } from '../editor/render.ts';
import type { FormatState } from '../editor/state.ts';
import { realClock, Throttle } from './events.ts';
import type { Clock } from './events.ts';
import { applyAppearance, applyTheme } from './theme.ts';

export const BRIDGE_VERSION = 1;
export const CALLS = ['configure', 'load', 'activate', 'freeze', 'snapshot', 'command', 'lint', 'setTheme', 'setAppearance', 'setMirror', 'setAnnotations', 'dispose', 'verifySwitch'] as const;
export type CallName = (typeof CALLS)[number];

export type BridgeEvent =
  | { type: 'ready'; bundleVersion: string; schemaVersion: number; bridgeVersion: number }
  | { type: 'edited'; revision: number }
  | ({ type: 'toolbarState' } & FormatState)
  | ({ type: 'caretRect' } & CaretInfo)
  | ({ type: 'mirrorBlocks' } & MirrorEvent)
  | ({ type: 'paste' } & PasteInfo)
  | { type: 'annotationTapped'; id: string }
  | { type: 'tkTyped'; from: number; to: number }
  | { type: 'wordAtCaret'; prefix: string | null }
  | { type: 'error'; code: string; message: string };

export type BridgeError = { code: string; message: string };
const fail = (code: string, message: string): never => { throw { code, message } satisfies BridgeError; };

type Args = Record<string, unknown>;
function obj(v: unknown, what: string): Args {
  if (v === undefined || v === null) return {};
  if (typeof v !== 'object' || Array.isArray(v)) return fail('bad-args', `${what} must be an object`);
  return v as Args;
}
function str(a: Args, k: string): string {
  if (typeof a[k] !== 'string') return fail('bad-args', `${k} must be a string`);
  return a[k] as string;
}
function int(a: Args, k: string, min = 0): number {
  const v = a[k];
  if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < min) return fail('bad-args', `${k} must be an integer >= ${min}`);
  return v;
}
function bool(a: Args, k: string, fallback: boolean): boolean {
  if (a[k] === undefined) return fallback;
  if (typeof a[k] !== 'boolean') return fail('bad-args', `${k} must be true or false`);
  return a[k] as boolean;
}

const VARIANTS: readonly Variant[] = ['content', 'notes', 'summary'];
const LOCALE = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{1,8}){0,4}$/;

/** Maps anything thrown to `{code, message}`, the only shape that crosses the bridge. */
export function toBridgeError(e: unknown): BridgeError {
  if (e instanceof ParseLimitError) return { code: 'too-large', message: e.message };
  if (e instanceof SanitizerFailure) return { code: 'sanitizer', message: e.message };
  if (e && typeof e === 'object' && typeof (e as BridgeError).code === 'string' && typeof (e as BridgeError).message === 'string') {
    return { code: (e as BridgeError).code, message: (e as BridgeError).message };
  }
  return { code: 'internal', message: e instanceof Error ? e.message : String(e) };
}

export type BridgeOptions = {
  mount: HTMLElement;
  /** The element that carries the theme's CSS variables (the page's <html>). */
  root: HTMLElement;
  post: (event: BridgeEvent) => void;
  bundleVersion: string;
  clock?: Clock;
  frame?: (f: () => void) => void;
  sleep?: (ms: number) => Promise<void>;
};

export class Bridge {
  readonly editor: Editor;
  readonly bundleVersion: string;
  private readonly root: HTMLElement;
  private readonly post: (event: BridgeEvent) => void;
  private readonly edited: Throttle<number>;
  private readonly toolbar: Throttle<FormatState>;
  /** The word at the caret, for name suggestions: a few letters at most ten times a second, never the text. */
  private readonly words: Throttle<string | null>;
  private lastToolbar = '';
  private queue: Promise<unknown> = Promise.resolve();

  constructor(o: BridgeOptions) {
    this.root = o.root;
    this.post = (e) => { try { o.post(e); } catch { /* a native handler that throws must not break editing */ } };
    this.bundleVersion = o.bundleVersion;
    const clock = o.clock ?? realClock;
    this.edited = new Throttle(4, (revision) => this.post({ type: 'edited', revision }), clock);
    this.toolbar = new Throttle(10, (state) => {
      const key = JSON.stringify(state);
      if (key === this.lastToolbar) return;
      this.lastToolbar = key;
      this.post({ type: 'toolbarState', ...state });
    }, clock);
    this.words = new Throttle(10, (prefix) => this.post({ type: 'wordAtCaret', prefix }), clock);
    this.editor = new Editor(o.mount, {
      hooks: {
        edited: (revision) => this.edited.push(() => revision),
        changed: () => this.toolbar.push(() => this.editor.formatState()),
        caret: (c) => this.post({ type: 'caretRect', ...c }),
        mirror: (m) => this.post({ type: 'mirrorBlocks', ...m }),
        annotationTapped: (id) => this.post({ type: 'annotationTapped', id }),
        tkTyped: (r) => this.post({ type: 'tkTyped', ...r }),
        word: (prefix) => this.words.push(() => prefix),
        pasted: (p) => this.post({ type: 'paste', ...p }),
        error: (code, message) => this.post({ type: 'error', code, message }),
      },
      ...(o.frame ? { frame: o.frame } : {}),
      ...(o.sleep ? { sleep: o.sleep } : {}),
      now: () => clock.now(),
      timer: { set: (f, ms) => clock.setTimeout(f, ms), clear: (t) => clock.clearTimeout(t) },
    });
  }

  ready(): void {
    this.post({ type: 'ready', bundleVersion: this.bundleVersion, schemaVersion: SCHEMA_VERSION, bridgeVersion: BRIDGE_VERSION });
  }

  /** `window.KudosEditor.call(name, args)`: resolves with the result or rejects with `{code, message}`. */
  call(name: unknown, args: unknown): Promise<unknown> {
    const run = this.queue.then(() => this.run(name, args)).catch((e) => { throw toBridgeError(e); });
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async run(name: unknown, rawArgs: unknown): Promise<unknown> {
    if (typeof name !== 'string' || !(CALLS as readonly string[]).includes(name) && name !== 'verify') fail('unknown-call', `no call named ${String(name)}`);
    const a = obj(rawArgs, 'args');
    const ed = this.editor;
    switch (name as CallName | 'verify') {
      case 'configure': {
        const variant = a.variant === undefined ? 'content' : (VARIANTS.includes(a.variant as Variant) ? (a.variant as Variant) : fail('bad-args', 'variant must be content, notes or summary'));
        if (a.theme !== undefined) applyTheme(this.root, obj(a.theme, 'theme'));
        // Apple's Locale.identifier ("en_GB", "sr_Latn_RS@calendar=…") or BCP 47; anything else is ignored, never fatal
        const tag = typeof a.locale === 'string' ? a.locale.split('@')[0]!.replaceAll('_', '-') : '';
        const locale = LOCALE.test(tag) ? tag : null;
        let labels: Partial<Labels> | undefined;
        if (a.labels !== undefined) {
          labels = {};
          for (const [k, v] of Object.entries(obj(a.labels, 'labels'))) {
            if (k in DEFAULT_LABELS && typeof v === 'string' && v.length <= 200) (labels as Record<string, string>)[k] = v;
          }
        }
        ed.configure({ variant, locale, ...(labels ? { labels } : {}), autocorrect: bool(a, 'autocorrect', true) });
        if (locale) this.root.lang = locale;
        return { bridgeVersion: BRIDGE_VERSION, schemaVersion: SCHEMA_VERSION, bundleVersion: this.bundleVersion };
      }
      case 'load': {
        this.edited.cancel();
        this.words.cancel(); // a word from the last document is not at this caret
        const r = ed.load(str(a, 'html'), int(a, 'revision'));
        return r;
      }
      case 'activate': {
        const caret = a.caret === undefined || a.caret === null ? null : int(a, 'caret');
        return ed.activate(caret, bool(a, 'focus', false));
      }
      case 'freeze': return ed.freeze();
      case 'snapshot': return ed.snapshot(bool(a, 'caret', false), bool(a, 'selection', false));
      case 'command': return ed.command(str(a, 'name'), obj(a.attrs, 'attrs'));
      case 'lint': return ed.lint(str(a, 'html'));
      case 'setTheme': applyTheme(this.root, a); return {};
      case 'setAppearance': applyAppearance(this.root, a); ed.remeasure(); return {};
      case 'setMirror': ed.setMirror(bool(a, 'enabled', false)); return {};
      case 'setAnnotations': {
        const items = Array.isArray(a.items) ? a.items : fail('bad-args', 'items must be an array');
        return ed.setAnnotations(items.map((raw) => {
          const it = obj(raw, 'item');
          const kind = it.kind === 'note' || it.kind === 'tk' ? it.kind : fail('bad-args', 'kind must be note or tk');
          return { id: str(it, 'id'), kind, from: int(it, 'from'), to: int(it, 'to') };
        }));
      }
      case 'dispose': this.edited.cancel(); this.words.cancel(); ed.dispose(); return {};
      case 'verifySwitch': case 'verify': {
        const direction = a.direction === 'richToSource' || a.direction === 'sourceToRich' ? a.direction : fail('bad-args', 'direction must be richToSource or sourceToRich');
        return ed.verifySwitch(direction, a.html === undefined || a.html === null ? undefined : str(a, 'html'));
      }
    }
    return fail('unknown-call', String(name));
  }
}
