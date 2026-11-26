// The bundle the apps load: no network or eval code, no remote URLs, a strict CSP, deterministic bytes, and it runs:
// the built editor.js, evaluated in a page made from the built editor.html, answers the bridge end to end.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';

const root = fileURLToPath(new URL('..', import.meta.url));
const dist = (f: string) => readFileSync(`${root}dist/${f}`, 'utf8');
const bundle = () => {
  const r = spawnSync(process.execPath, ['scripts/bundle.ts', '--no-copy'], { cwd: root, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return createHash('sha256').update(dist('editor.js')).digest('hex');
};
const first = bundle();

test('the bundle is deterministic', () => {
  assert.equal(bundle(), first);
});

test('editor.js has no network, eval or dynamic-code APIs', () => {
  const js = dist('editor.js');
  for (const [name, re] of [
    ['fetch(', /\bfetch\s*\(/], ['XMLHttpRequest', /XMLHttpRequest/], ['eval(', /\beval\s*\(/], ['new Function', /new\s+Function\b/],
    ['WebSocket', /WebSocket/], ['EventSource', /EventSource/], ['sendBeacon', /sendBeacon/], ['importScripts', /importScripts/],
    ['import(', /\bimport\s*\(/], ['setTimeout with a string', /setTimeout\s*\(\s*["'`]/], ['document.write', /document\.write/],
  ] as const) assert.doesNotMatch(js, re, name);
});

test('every URL in editor.js is a known identifier, never something loaded', () => {
  const allowed: Record<string, string> = {
    'http://www.w3.org/1999/xhtml': 'parse5: HTML namespace',
    'http://www.w3.org/1998/Math/MathML': 'parse5: MathML namespace',
    'http://www.w3.org/2000/svg': 'parse5: SVG namespace',
    'http://www.w3.org/1999/xlink': 'parse5: XLink namespace',
    'http://www.w3.org/XML/1998/namespace': 'parse5: XML namespace',
    'http://www.w3.org/2000/xmlns/': 'parse5: XMLNS namespace',
    'http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd': 'parse5: a doctype system id in its quirks-mode table',
    'https://archiveofourown.org': 'part 1: the base AO3 resolves relative img src against (a string, never fetched)',
    'https://': 'part 1: a scheme prefix in the URI port',
    'https://prosemirror.net/docs/guide/#generatable': 'prosemirror-model: an error message',
  };
  const found = new Set(dist('editor.js').match(/https?:\/\/[^\s"'`)\\]*/g) ?? []);
  for (const url of found) assert.ok(url in allowed, `unexpected URL in the bundle: ${url}`);
});

test('editor.html: the 11 CSP, one same-origin script, no inline script or handlers, nothing remote', () => {
  const page = dist('editor.html');
  assert.match(page, /<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:">/);
  const scripts = [...page.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  assert.match(scripts[0]![1]!, /\bsrc="editor\.js"/);
  assert.equal(scripts[0]![2]!.trim(), '', 'no inline script');
  assert.doesNotMatch(page, /\son[a-z]+\s*=/i, 'no inline event handlers');
  assert.doesNotMatch(page, /https?:|\/\//, 'no remote or protocol-relative references');
  assert.match(page, /user-scalable=no/);
  const css = dist('editor.css');
  assert.doesNotMatch(css, /url\(|@import|https?:/, 'the stylesheet loads nothing');
  assert.match(css, /-webkit-tap-highlight-color: transparent/);
  assert.match(css, /-webkit-text-size-adjust: 100%/);
});

test('the app\'s copy is the current build', () => {
  const app = `${root}../kudos-ao3-reader/Resources/EditorCore/`;
  if (!existsSync(app)) return;
  for (const f of ['editor.html', 'editor.css', 'editor.js', 'THIRD-PARTY-NOTICES.txt']) {
    assert.equal(readFileSync(app + f, 'utf8'), dist(f), `${f}: run npm run bundle`);
  }
});

test('the built page runs: ready, then configure, load, activate, command, snapshot over the Apple transport', async () => {
  const page = new JSDOM(dist('editor.html'), { runScripts: 'outside-only', pretendToBeVisual: true });
  const win = page.window as any;
  const events: any[] = [];
  // jsdom has no layout (see setup.ts): give ranges and elements a rectangle
  const rect = { left: 0, right: 0, top: 0, bottom: 20, width: 0, height: 20, x: 0, y: 0 };
  win.Range.prototype.getClientRects = () => [rect];
  win.Range.prototype.getBoundingClientRect = () => rect;
  win.Element.prototype.getClientRects = () => [rect];
  win.webkit = { messageHandlers: { kudos: { postMessage: (e: unknown) => events.push(JSON.parse(JSON.stringify(e))) } } };
  win.eval(dist('editor.js'));
  assert.equal(events[0].type, 'ready');
  assert.match(events[0].bundleVersion, /^\d+\.\d+\.\d+\+[0-9a-f]{12}$/);
  assert.equal(events[0].bridgeVersion, 1);
  // results cross into Node's realm as JSON, as they reach native
  const call = async (name: string, args: unknown) => JSON.parse(JSON.stringify(await win.KudosEditor.call(name, args)));
  const conf = await call('configure', { bridgeVersion: 1, schemaVersion: 1, variant: 'content', theme: { background: '#111', text: '#eee', accent: '#c33', link: '#6af', fontFamily: 'ui-serif', fontSizePx: 19, lineHeight: 1.6 }, locale: 'en' });
  assert.equal(conf.bundleVersion, events[0].bundleVersion);
  const src = '<p>Hello <i>there</i>.</p>\n<p>Second.</p>';
  const loaded = await call('load', { html: src, revision: 4 });
  assert.equal(loaded.revision, 4);
  assert.deepEqual(await call('snapshot', { caret: false }), { revision: 4, html: src, caretOffset: null, words: 3 });
  await call('activate', { caret: src.indexOf('Second') + 6, focus: true });
  await call('command', { name: 'toggleMark', attrs: { mark: 'bold' } });
  await call('command', { name: 'insertText', attrs: { text: ' More' } });
  const frozen = await call('freeze', {});
  const snap = await call('snapshot', { caret: true });
  assert.equal(snap.revision, frozen.revision);
  assert.equal(snap.html, '<p>Hello <i>there</i>.</p>\n<p>Second<strong> More</strong>.</p>');
  assert.equal(snap.html.slice(0, snap.caretOffset), '<p>Hello <i>there</i>.</p>\n<p>Second<strong> More');
  assert.deepEqual(await call('verifySwitch', { direction: 'richToSource', html: snap.html }), { ok: true, candidateHtml: snap.html });
  await assert.rejects(call('load', { html: 5, revision: 1 }), (e: any) => e.code === 'bad-args');
  assert.ok(events.some((e) => e.type === 'edited'));
  assert.ok(events.some((e) => e.type === 'toolbarState'));
  assert.equal(page.window.document.documentElement.style.getPropertyValue('--kd-bg'), '#111');
  page.window.close();
});
