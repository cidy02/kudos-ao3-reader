// The bridge protocol (spec 7.2): calls, argument checks, error shape, events and their rate limits, freezing,
// FormatState, caret reports, theme checks and the Android transport.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { jsdomWindow as w } from './setup.ts';
import { caretAt, command, harness, html, opened, selectText } from './dom.ts';
import { Bridge, BRIDGE_VERSION } from '../src/bridge/protocol.ts';
import type { BridgeEvent } from '../src/bridge/protocol.ts';
import { install } from '../src/bridge/transport.ts';
import { themeVariables } from '../src/bridge/theme.ts';
import { SCHEMA_VERSION } from '../src/index.ts';

const MAC = /Mac|iP(hone|[oa]d)/.test(navigator.platform); // prosemirror-keymap's own test for Mod
const rejects = async (p: Promise<unknown>, code: string) => {
  await assert.rejects(p, (e: any) => { assert.equal(e.code, code); assert.equal(typeof e.message, 'string'); return true; });
};

test('configure answers with the versions; unknown calls and bad arguments reject with {code, message}', async () => {
  const h = harness();
  const r = await h.call('configure', { bridgeVersion: 1, schemaVersion: 1, variant: 'notes', theme: { background: '#000', text: '#fff', accent: '#821019', link: '#06c', fontFamily: "'New York', ui-serif", fontSizePx: 21, lineHeight: 1.6 }, locale: 'en-GB' });
  assert.deepEqual(r, { bridgeVersion: BRIDGE_VERSION, schemaVersion: SCHEMA_VERSION, bundleVersion: 'test' });
  assert.equal(h.bridge.editor.variant, 'notes');
  assert.equal(w.document.documentElement.style.getPropertyValue('--kd-size'), '21px');
  assert.equal(w.document.documentElement.lang, 'en-GB');
  await rejects(h.call('eval', {}), 'unknown-call');
  await rejects(h.call('load', { html: 1, revision: 1 }), 'bad-args');
  await rejects(h.call('load', { html: 'x', revision: -1 }), 'bad-args');
  await rejects(h.call('configure', { variant: 'chapter' }), 'bad-args');
  await rejects(h.call('activate', { caret: null }), 'not-loaded');
  await rejects(h.call('snapshot', {}), 'not-loaded');
  await rejects(h.call('verifySwitch', { direction: 'sideways' }), 'bad-args');
});

test('a failed call does not block the ones after it, and calls run in order', async () => {
  const h = harness();
  await h.ready;
  const order: string[] = [];
  const a = h.call('load', { html: '<p>a</p>', revision: 3 }).then(() => order.push('load'));
  const b = h.call('nope').catch(() => order.push('nope'));
  const c = h.call('snapshot', {}).then((s) => { order.push('snapshot'); return s; });
  await Promise.all([a, b, c]);
  assert.deepEqual(order, ['load', 'nope', 'snapshot']);
  assert.equal((await c).revision, 3);
});

test('load reports the loss and timings and leaves the editor read-only and unfocused', async () => {
  const h = harness();
  await h.ready;
  const r = await h.call('load', { html: '<p><font color="red">hi</font> <span>there</span></p>', revision: 7 });
  assert.equal(r.revision, 7);
  assert.equal(r.loss.dropped.elements.font, 1);
  assert.equal(typeof r.timing.parseMs, 'number');
  assert.equal(typeof r.timing.buildMs, 'number');
  assert.equal(typeof r.timing.renderMs, 'number');
  assert.equal(h.bridge.editor.view.editable, false);
  assert.equal(h.bridge.editor.view.dom.getAttribute('contenteditable'), 'false');
  assert.equal(h.bridge.editor.view.dom.getAttribute('aria-readonly'), 'true');
});

test('the editable root carries the keyboard and accessibility attributes (N1, N9)', async () => {
  const h = await opened('<p>x</p>');
  const root = h.bridge.editor.view.dom;
  assert.equal(root.getAttribute('contenteditable'), 'true');
  assert.equal(root.getAttribute('spellcheck'), 'true');
  assert.equal(root.getAttribute('autocorrect'), 'on');
  assert.equal(root.getAttribute('autocapitalize'), 'sentences');
  assert.equal(root.getAttribute('role'), 'textbox');
  assert.equal(root.getAttribute('aria-multiline'), 'true');
  assert.equal(root.getAttribute('aria-label'), 'Chapter text');
  assert.equal(root.getAttribute('lang'), 'en');
  await h.call('configure', { variant: 'content', autocorrect: false, labels: { editor: 'Texte du chapitre' } });
  assert.equal(root.getAttribute('autocorrect'), 'off');
  assert.equal(root.getAttribute('aria-label'), 'Texte du chapitre');
});

test('blocks render as AO3 shows them, with semantic marks and locked chips for preserved HTML', async () => {
  const h = await opened('<h2>T</h2>\n<blockquote><p>q</p></blockquote>\n<hr>\n<ul><li><b>b</b> <i>i</i></li></ul>\n<details open="open"><summary>S</summary>\n<p>d</p></details>\n<table><tr><td>cell one</td></tr></table>\n<p dir="rtl" align="center"><a href="https://x.org/">l</a> <img src="https://img.example/a.png" alt="cat"></p>');
  const root = h.bridge.editor.view.dom;
  assert.ok(root.querySelector('h2'));
  assert.ok(root.querySelector('blockquote > p'));
  assert.equal(root.querySelector('hr')?.getAttribute('aria-label'), 'Scene break');
  assert.ok(root.querySelector('li strong'), '<b> is drawn as strong');
  assert.ok(root.querySelector('li em'), '<i> is drawn as em');
  const details = root.querySelector('.kd-details')!;
  assert.equal(details.getAttribute('role'), 'group');
  assert.equal(details.getAttribute('data-open'), 'true');
  assert.equal(details.querySelector('.kd-summary')?.textContent, 'S');
  const raw = root.querySelector('.kd-raw')!;
  assert.equal(raw.getAttribute('contenteditable'), 'false');
  assert.equal(raw.getAttribute('data-tag'), 'table');
  assert.match(raw.getAttribute('aria-label')!, /^Table\. Edit in HTML view$/);
  assert.equal(raw.querySelector('.kd-raw-preview')?.textContent, 'cell one');
  const p = root.querySelector('p[dir="rtl"]')!;
  assert.equal(p.getAttribute('align'), 'center');
  assert.equal(p.querySelector('a')?.getAttribute('href'), 'https://x.org/');
  assert.equal(root.querySelector('img:not(.ProseMirror-separator)'), null, 'remote images are never loaded (OD2, 11)');
  assert.equal(root.querySelector('.kd-image')?.getAttribute('aria-label'), 'Image: cat (img.example)');
  assert.equal(root.querySelector('iframe, audio, video, script, style'), null);
});

test('activate maps the HTML-mode caret, resets history, and the caret event reports rect and block', async () => {
  const h = harness();
  await h.ready;
  const src = '<p>first</p>\n<p>second <em>para</em></p>';
  await h.call('load', { html: src, revision: 1 });
  const r = await h.call('activate', { caret: src.indexOf('para') + 2, focus: true });
  assert.deepEqual(r, { caretFound: true });
  const { selection, doc } = h.bridge.editor.view.state;
  assert.equal(doc.textBetween(selection.head - 2, selection.head), 'pa');
  const caret = h.events.filter((e) => e.type === 'caret').at(-1) as Extract<BridgeEvent, { type: 'caret' }>;
  assert.equal(caret.block, 1);
  assert.equal(typeof caret.y, 'number');
  assert.equal(typeof caret.height, 'number');
  assert.equal((await h.call('activate', { caret: null, focus: false })).caretFound, false);
});

test('edited events: no text, at most 4 per second, the trailing revision always sent (I3)', async () => {
  const h = await opened('<p>a</p>');
  h.events.length = 0;
  caretAt(h, 'a');
  for (let i = 0; i < 20; i++) { await command(h, 'insertText', { text: 'x' }); h.clock.advance(50); } // 20 keystrokes in one second
  h.clock.advance(1000);
  const edited = h.events.filter((e) => e.type === 'edited') as Extract<BridgeEvent, { type: 'edited' }>[];
  assert.ok(edited.length <= 5 && edited.length >= 2, `${edited.length} edited events`);
  assert.equal(edited.at(-1)!.revision, h.bridge.editor.revision, 'the last revision is sent');
  assert.equal(h.bridge.editor.revision, 21);
  for (const e of edited) assert.deepEqual(Object.keys(e).sort(), ['revision', 'type']);
});

test('toolbarState: FormatState after a change, deduplicated, at most 10 per second', async () => {
  const h = await opened('<ul><li>plain <a href="https://x.org/"><strong>bold link</strong></a></li></ul>');
  selectText(h, 'plain');
  h.clock.advance(1000);
  h.events.length = 0;
  selectText(h, 'bold');
  h.clock.advance(200);
  const st = h.events.filter((e) => e.type === 'toolbarState').at(-1) as any;
  assert.deepEqual(st.marks, ['bold']);
  assert.equal(st.block, 'bulletedList');
  assert.equal(st.align, 'left');
  assert.equal(st.dir, 'leftToRight');
  assert.equal(st.canUndo, false);
  assert.equal(st.inLink, true);
  assert.equal(st.linkURL, 'https://x.org/');
  const r = await command(h, 'toggleMark', { mark: 'italic' });
  assert.deepEqual(r.state.marks, ['bold', 'italic'], 'the command result carries the new state');
  assert.equal(r.state.canUndo, true);
  const before = h.events.length;
  selectText(h, 'bold'); // same selection again: nothing new to say
  h.clock.advance(200);
  assert.equal(h.events.filter((e, i) => i >= before && e.type === 'toolbarState').length, 0);
});

test('FormatState reports block, alignment and direction', async () => {
  const cases: [string, string, Record<string, unknown>][] = [
    ['<h3>x</h3>', 'x', { block: 'heading' }],
    ['<h5>x</h5>', 'x', { block: 'subheading' }],
    ['<p align="center">x</p>', 'x', { block: 'centred', align: 'centre' }],
    ['<blockquote><p>x</p></blockquote>', 'x', { block: 'quote' }],
    ['<ol><li>x</li></ol>', 'x', { block: 'numberedList' }],
    ['<details><summary>s</summary>\n<p>x</p></details>', 'x', { block: 'foldOut' }],
    ['<p dir="rtl">x</p>', 'x', { block: 'body', dir: 'rightToLeft', align: 'right' }],
    ['<p align="justify">x</p>', 'x', { align: 'justify' }],
    ['<p><sub>x</sub></p>', 'x', { marks: ['subscript'] }],
    ['<p><small>x</small></p>', 'x', { marks: ['smaller'] }],
  ];
  for (const [src, at, want] of cases) {
    const h = await opened(src);
    selectText(h, at);
    const state = (await command(h, 'nothing')).state;
    for (const [k, v] of Object.entries(want)) assert.deepEqual(state[k], v, `${src}: ${k}`);
  }
});

test('freeze waits for IME composition to end; the composed text is in the snapshot (7.6)', async () => {
  const h = await opened('<p>a</p>');
  const view = h.bridge.editor.view;
  caretAt(h, 'a');
  (view as any).input.composing = true; // what compositionstart sets
  const frozen = h.call('freeze', {});
  setTimeout(() => {
    view.dispatch(view.state.tr.insertText('漢字'));
    (view as any).input.composing = false; // compositionend
  }, 30);
  const r = await frozen;
  assert.equal(r.revision, h.bridge.editor.revision);
  assert.equal(await html(h), '<p>a漢字</p>');
  assert.equal(view.editable, false);
});

test('freeze gives up after 500 ms of composition and reports composition-timeout', async () => {
  const h = await opened('<p>a</p>');
  const view = h.bridge.editor.view;
  (view as any).input.composing = true;
  const real = Date.now();
  const p = h.call('freeze', {});
  const tick = setInterval(() => h.clock.advance(100), 5);
  await p;
  clearInterval(tick);
  (view as any).input.composing = false;
  assert.ok(Date.now() - real < 2000);
  assert.ok(h.events.some((e) => e.type === 'error' && e.code === 'composition-timeout'));
});

test('setTheme refuses values that are not colours, fonts or numbers', () => {
  const bad = (re: RegExp) => (e: any) => e.code === 'bad-args' && re.test(e.message);
  assert.throws(() => themeVariables({ background: 'url(https://evil.example/x.png)' }), bad(/colour/));
  assert.throws(() => themeVariables({ text: 'red; background: url(x)' }), bad(/colour/));
  assert.throws(() => themeVariables({ fontFamily: 'x}body{display:none' }), bad(/font/));
  assert.throws(() => themeVariables({ fontSizePx: '17px' }), bad(/number/));
  assert.deepEqual(themeVariables({ background: 'color(display-p3 0.1 0.1 0.1)', fontSizePx: 400, lineHeight: 1.5, boldText: true, colorScheme: 'dark' }),
    { '--kd-bg': 'color(display-p3 0.1 0.1 0.1)', '--kd-size': '128px', '--kd-line': '1.5', '--kd-weight': '600', 'color-scheme': 'dark' });
});

test('dispose drops the document', async () => {
  const h = await opened('<p>a</p>');
  assert.deepEqual(await h.call('dispose', {}), {});
  await rejects(h.call('snapshot', {}), 'not-loaded');
  assert.equal(h.bridge.editor.view.state.doc.textContent, '');
});

test('the Android transport: {id, name, args} in, {id, ok, result | error} out, events as JSON strings', async () => {
  const sent: string[] = [];
  const target = new w.EventTarget();
  const fakeWin = Object.assign(target, { kudosNative: { postMessage: (s: string) => sent.push(s) } }) as any;
  const mount = w.document.createElement('main');
  const bridge = new Bridge({ mount, root: w.document.documentElement, post: (e) => fakeWin.kudosNative.postMessage(JSON.stringify(e)), bundleVersion: 'a', frame: (f) => f() });
  install(fakeWin, bridge);
  assert.equal(typeof fakeWin.KudosEditor.call, 'function');
  assert.throws(() => { fakeWin.KudosEditor = null; }, 'window.KudosEditor cannot be replaced');
  bridge.ready();
  target.dispatchEvent(new w.MessageEvent('message', { data: JSON.stringify({ id: 'c1', name: 'configure', args: { variant: 'content' } }) }));
  target.dispatchEvent(new w.MessageEvent('message', { data: { id: 2, name: 'bogus', args: {} } }));
  target.dispatchEvent(new w.MessageEvent('message', { data: 'not json' }));
  await new Promise((r) => setTimeout(r, 20));
  const msgs = sent.map((s) => JSON.parse(s));
  assert.equal(msgs[0].type, 'ready');
  assert.deepEqual(msgs.find((m) => m.id === 'c1'), { id: 'c1', ok: true, result: { bridgeVersion: 1, schemaVersion: SCHEMA_VERSION, bundleVersion: 'a' } });
  assert.equal(msgs.find((m) => m.id === 2).error.code, 'unknown-call');
  assert.equal(msgs.length, 3);
});

test('a link click never navigates (N12, 11)', async () => {
  const h = await opened('<p><a href="https://x.org/">go</a></p>');
  const a = h.bridge.editor.view.dom.querySelector('a')!;
  const ev = new w.MouseEvent('click', { bubbles: true, cancelable: true });
  a.dispatchEvent(ev);
  assert.equal(ev.defaultPrevented, true);
});

test('keymap: Mod-b, Mod-i, Mod-u toggle marks; Mod-z undoes', async () => {
  const h = await opened('<p>ab</p>');
  selectText(h, 'ab');
  const key = (k: string, extra: Record<string, boolean> = {}) => h.bridge.editor.view.dom.dispatchEvent(new w.KeyboardEvent('keydown', { key: k, ...(MAC ? { metaKey: true } : { ctrlKey: true }), bubbles: true, cancelable: true, ...extra }));
  key('b');
  key('i');
  key('u');
  assert.equal(await html(h), '<p><strong><em><u>ab</u></em></strong></p>');
  key('z');
  assert.equal(await html(h), '<p><strong><em>ab</em></strong></p>');
  key('z', { shiftKey: true });
  assert.equal(await html(h), '<p><strong><em><u>ab</u></em></strong></p>');
});

test('Shift-Enter: a break, and a second break splits the paragraph instead (S10)', async () => {
  const h = await opened('<p>ab</p>');
  caretAt(h, 'a');
  const key = () => h.bridge.editor.view.dom.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Enter', shiftKey: true, bubbles: true, cancelable: true }));
  key();
  assert.equal(await html(h), '<p>a<br>b</p>');
  key();
  assert.equal(await html(h), '<p>a</p>\n<p>b</p>');
});

test('invariants: an implicit list paragraph lifted out becomes <p>; deleting text between two breaks splits', async () => {
  const h = await opened('<ul><li>one</li></ul>');
  caretAt(h, 'one');
  const view = h.bridge.editor.view;
  const { liftListItem } = await import('prosemirror-schema-list');
  liftListItem(view.state.schema.nodes.list_item!)(view.state, view.dispatch);
  assert.equal(await html(h), '<p>one</p>');
  const g = await opened('<p>a<br>x<br>b</p>');
  selectText(g, 'x');
  g.bridge.editor.view.dispatch(g.bridge.editor.view.state.tr.deleteSelection());
  assert.equal(await html(g), '<p>a</p>\n<p>b</p>');
  const t = await opened('<h3>a<br>x<br>b</h3>');
  selectText(t, 'x');
  t.bridge.editor.view.dispatch(t.bridge.editor.view.state.tr.deleteSelection());
  assert.equal(await html(t), '<h3>a<br>b</h3>');
});
