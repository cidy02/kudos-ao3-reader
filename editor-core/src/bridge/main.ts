// The page's entry point (editor.html loads only this bundle).
import { Bridge } from './protocol.ts';
import { eventPoster, install } from './transport.ts';
import type { NativeWindow } from './transport.ts';

declare const __BUNDLE_VERSION__: string;

const win = window as NativeWindow;
const post = eventPoster(win);
const bridge = new Bridge({ mount: document.getElementById('editor')!, root: document.documentElement, post, bundleVersion: __BUNDLE_VERSION__ });
install(win, bridge);

// 7.8: JS errors are logged by the native side, never shown.
win.addEventListener('error', (e) => post({ type: 'error', code: 'uncaught', message: String(e.message ?? e) }));
win.addEventListener('unhandledrejection', (e) => post({ type: 'error', code: 'unhandled-rejection', message: String((e.reason as Error)?.message ?? e.reason) }));
win.addEventListener('resize', () => bridge.editor.remeasure());
// N12: never a web page. Files or links dropped outside the canvas don't open.
for (const type of ['dragover', 'drop'] as const) {
  win.addEventListener(type, (e) => { if (!(e.target as Element | null)?.closest?.('.kd-editor')) e.preventDefault(); });
}
bridge.ready();
