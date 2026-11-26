// Test helpers: a bridge on a fresh mount, called the way native calls it.
import { jsdomWindow as w } from './setup.ts';
import * as pmState from 'prosemirror-state';
import { Bridge } from '../src/bridge/protocol.ts';
import type { BridgeEvent } from '../src/bridge/protocol.ts';
import type { Clock } from '../src/bridge/events.ts';

/** A clock the test moves by hand, for the event rate limits. */
export class ManualClock implements Clock {
  t = 0;
  private timers: { at: number; f: () => void; id: number }[] = [];
  private next = 1;
  now(): number { return this.t; }
  setTimeout(f: () => void, ms: number): unknown { const id = this.next++; this.timers.push({ at: this.t + ms, f, id }); return id; }
  clearTimeout(id: unknown): void { this.timers = this.timers.filter((x) => x.id !== id); }
  advance(ms: number): void {
    const end = this.t + ms;
    for (;;) {
      this.timers.sort((a, b) => a.at - b.at);
      const due = this.timers[0];
      if (!due || due.at > end) break;
      this.timers.shift();
      this.t = due.at;
      due.f();
    }
    this.t = end;
  }
}

export type Harness = { bridge: Bridge; events: BridgeEvent[]; mount: HTMLElement; clock: ManualClock; call: (name: string, args?: unknown) => Promise<any> };

/** A bridge on a fresh mount, with events collected and calls made the way native makes them (JSON values only). */
export function harness(opts: { variant?: string } = {}): Harness & { ready: Promise<void> } {
  const mount = w.document.createElement('main');
  w.document.body.replaceChildren(mount);
  const events: BridgeEvent[] = [];
  const clock = new ManualClock();
  const bridge = new Bridge({ mount, root: w.document.documentElement, post: (e) => events.push(JSON.parse(JSON.stringify(e))), bundleVersion: 'test', clock, frame: (f) => f() });
  const call = (name: string, args?: unknown) => bridge.call(name, args === undefined ? undefined : JSON.parse(JSON.stringify(args)));
  const ready = call('configure', { bridgeVersion: 1, schemaVersion: 1, variant: opts.variant ?? 'content', locale: 'en' }).then(() => undefined);
  return { bridge, events, mount, clock, call, ready };
}

/** Loads HTML and activates it at the end, ready for commands. */
export async function opened(html: string, opts: { variant?: string; caret?: number | null } = {}): Promise<Harness> {
  const h = harness(opts);
  await h.ready;
  await h.call('load', { html, revision: 1 });
  await h.call('activate', { caret: opts.caret ?? null, focus: false });
  return h;
}

/** Puts the selection on [from, to) of the text (offsets in the document's text, found by search). */
export function selectText(h: Harness, needle: string, end?: string): void {
  const view = h.bridge.editor.view;
  let from = -1, to = -1;
  view.state.doc.descendants((node, pos) => {
    if (from >= 0 || !node.isText) return from < 0;
    const i = node.text!.indexOf(needle);
    if (i >= 0) { from = pos + i; to = from + needle.length; }
    return false;
  });
  if (from < 0) throw new Error(`text not found: ${needle}`);
  if (end !== undefined) {
    view.state.doc.descendants((node, pos) => {
      if (!node.isText || pos < from) return true;
      const i = node.text!.indexOf(end);
      if (i >= 0 && pos + i >= from) { to = pos + i + end.length; return false; }
      return true;
    });
  }
  const { TextSelection } = pmState;
  view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to)));
}

/** A caret just after `needle` (or before it, with `before`). */
export function caretAt(h: Harness, needle: string, before = false): void {
  selectText(h, needle);
  const view = h.bridge.editor.view;
  const { TextSelection } = pmState;
  const pos = before ? view.state.selection.from : view.state.selection.to;
  view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, pos)));
}


export async function html(h: Harness): Promise<string> {
  return (await h.call('snapshot', { caret: false })).html;
}

export async function command(h: Harness, name: string, attrs: Record<string, unknown> = {}): Promise<{ applied: boolean; state: any }> {
  return h.call('command', { name, attrs });
}
