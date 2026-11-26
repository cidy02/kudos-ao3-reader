// The two native transports (spec 7.2). Apple: calls through `callAsyncJavaScript` into window.KudosEditor.call, events
// to window.webkit.messageHandlers.kudos. Android: `{id, name, args}` web messages in, `{id, ok, result | error}` and
// events out through the `kudosNative` listener object. Payloads are JSON values only.
import type { Bridge, BridgeEvent } from './protocol.ts';
import { BRIDGE_VERSION, toBridgeError } from './protocol.ts';

type NativeAndroid = { postMessage(message: string): void; addEventListener?(type: 'message', f: (e: MessageEvent) => void): void };
export type NativeWindow = Window & {
  webkit?: { messageHandlers?: { kudos?: { postMessage(body: unknown): void } } };
  kudosNative?: NativeAndroid;
};

export function eventPoster(win: NativeWindow): (event: BridgeEvent) => void {
  return (event) => {
    const apple = win.webkit?.messageHandlers?.kudos;
    if (apple) apple.postMessage(event);
    else if (win.kudosNative) win.kudosNative.postMessage(JSON.stringify(event));
    else win.dispatchEvent(new CustomEvent('kudos-editor-event', { detail: event })); // a desktop browser, for development
  };
}

export function install(win: NativeWindow, bridge: Bridge): void {
  Object.defineProperty(win, 'KudosEditor', {
    value: Object.freeze({ bridgeVersion: BRIDGE_VERSION, call: (name: unknown, args: unknown) => bridge.call(name, args) }),
    writable: false,
    configurable: false,
  });
  const android = win.kudosNative;
  if (!android) return;
  const onMessage = (e: MessageEvent) => {
    let msg: unknown = e.data;
    if (typeof msg === 'string') { try { msg = JSON.parse(msg); } catch { return; } }
    if (!msg || typeof msg !== 'object') return;
    const { id, name, args } = msg as { id?: unknown; name?: unknown; args?: unknown };
    if ((typeof id !== 'string' && typeof id !== 'number') || typeof name !== 'string') return;
    bridge.call(name, args).then(
      (result) => android.postMessage(JSON.stringify({ id, ok: true, result })),
      (error) => android.postMessage(JSON.stringify({ id, ok: false, error: toBridgeError(error) })),
    );
  };
  win.addEventListener('message', onMessage);
  android.addEventListener?.('message', onMessage);
}
