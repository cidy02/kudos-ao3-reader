// The paste hook: pasted HTML runs through editor-core's parse5 pipeline (never the page's DOM) and the paste reports
// what AO3 would drop. Also drop, copy and cut.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { jsdomWindow as w } from './setup.ts';
import { caretAt, command, html, opened, selectText } from './dom.ts';
import type { Harness } from './dom.ts';

/** jsdom has no ClipboardEvent or DataTransfer: an Event with a minimal clipboardData. */
function clipboardEvent(type: string, data: Record<string, string> = {}) {
  const store = { ...data };
  const e = new w.Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(e, 'clipboardData', { value: { getData: (t: string) => store[t] ?? '', setData: (t: string, v: string) => { store[t] = v; }, clearData: () => { for (const k of Object.keys(store)) delete store[k]; }, types: Object.keys(store) } });
  return { e, store };
}

function paste(h: Harness, data: Record<string, string>) {
  const { e } = clipboardEvent('paste', data);
  h.bridge.editor.view.dom.dispatchEvent(e);
  return e;
}

/** Counts innerHTML and outerHTML writes and insertAdjacentHTML calls anywhere in the page while `f` runs. */
function htmlWrites(f: () => void): number {
  let n = 0;
  const restore: (() => void)[] = [];
  for (const [proto, key] of [[w.Element.prototype, 'innerHTML'], [w.Element.prototype, 'outerHTML']] as const) {
    const d = Object.getOwnPropertyDescriptor(proto, key)!;
    Object.defineProperty(proto, key, { ...d, set(v: string) { n++; d.set!.call(this, v); } });
    restore.push(() => Object.defineProperty(proto, key, d));
  }
  const iah = w.Element.prototype.insertAdjacentHTML;
  w.Element.prototype.insertAdjacentHTML = function (...a: [InsertPosition, string]) { n++; return iah.apply(this, a); };
  restore.push(() => { w.Element.prototype.insertAdjacentHTML = iah; });
  try { f(); } finally { for (const r of restore) r(); }
  return n;
}

test('pasted HTML is cleaned by the AO3 pipeline, never parsed by the page, and reports its loss', async () => {
  const h = await opened('<p>Start end</p>');
  caretAt(h, 'Start ');
  const writes = htmlWrites(() => {
    const e = paste(h, { 'text/html': '<meta charset="utf-8"><p style="color:red"><font face="Arial">Hello</font> <b>bold</b><script>alert(1)</script> <img src="x" onerror="alert(2)"></p>', 'text/plain': 'Hello bold' });
    assert.equal(e.defaultPrevented, true);
  });
  assert.equal(writes, 0, 'no HTML string reached the live DOM');
  assert.equal(await html(h), '<p>Start Hello <b>bold</b> <img src="https://archiveofourown.org/x">end</p>');
  const ev = h.events.find((e) => e.type === 'paste') as any;
  assert.equal(ev.kind, 'html');
  assert.equal(ev.words, 2);
  assert.equal(ev.loss.dropped.elements.font, 1);
  assert.equal(ev.loss.dropped.elements.script, 1);
  assert.equal(ev.loss.dropped.attributes.style, 1);
  assert.equal(ev.loss.dropped.attributes.onerror, 1);
  assert.equal(h.bridge.editor.view.dom.querySelector('script, font, [onerror], [style]'), null);
});

test('plain text is paragraphed as AO3 does: blank lines are paragraphs, single newlines are breaks', async () => {
  const h = await opened('<p>x</p>');
  caretAt(h, 'x');
  paste(h, { 'text/plain': 'one\n\ntwo\nthree <tag> & more' });
  assert.equal(await html(h), '<p>xone</p>\n<p>two<br>three &lt;tag&gt; &amp; more</p>');
  assert.equal((h.events.find((e) => e.type === 'paste') as any).kind, 'text');
});

test('a paste is one undo step', async () => {
  const h = await opened('<p>ab</p>');
  caretAt(h, 'a');
  paste(h, { 'text/html': '<p><em>new</em> words</p>' });
  assert.equal(await html(h), '<p>a<em>new</em> wordsb</p>');
  await command(h, 'undo');
  assert.equal(await html(h), '<p>ab</p>');
});

test('pasting multiple paragraphs into the middle of one splits it around them', async () => {
  const h = await opened('<p>headtail</p>');
  caretAt(h, 'head');
  paste(h, { 'text/html': '<p>one</p><blockquote><p>q</p></blockquote><p>two</p>' });
  assert.equal(await html(h), '<p>headone</p>\n<blockquote><p>q</p></blockquote>\n<p>twotail</p>');
});

test('the paste command (native Paste button) returns the loss report; summary fields drop what summaries cannot keep', async () => {
  const h = await opened('<p>x</p>', { variant: 'summary' });
  caretAt(h, 'x');
  const r = await command(h, 'paste', { html: '<p class="note">A <em>summary</em></p><table><tr><td>t</td></tr></table>' }) as any;
  assert.equal(r.applied, true);
  assert.equal(r.paste.kind, 'html');
  assert.ok(r.paste.loss.dropped.attributes.class >= 1, JSON.stringify(r.paste.loss));
  assert.doesNotMatch(await html(h), /class=/);
  assert.equal((await command(h, 'paste', {})).applied, false);
});

test('nothing is pasted while frozen (I1)', async () => {
  const h = await opened('<p>x</p>');
  caretAt(h, 'x');
  await h.call('freeze', {});
  const e = paste(h, { 'text/plain': 'nope' });
  assert.equal(e.defaultPrevented, false);
  assert.equal(await html(h), '<p>x</p>');
});

test('an external drop goes through the same pipeline; files dropped outside are not opened', async () => {
  const h = await opened('<p>ab</p>');
  caretAt(h, 'a');
  const e = new w.Event('drop', { bubbles: true, cancelable: true });
  Object.defineProperty(e, 'dataTransfer', { value: { getData: (t: string) => (t === 'text/html' ? '<p><u>dropped</u><iframe src="https://x.org"></iframe></p>' : ''), types: ['text/html'] } });
  Object.assign(e, { clientX: 1, clientY: 1 });
  h.bridge.editor.view.dom.dispatchEvent(e);
  assert.equal(e.defaultPrevented, true);
  assert.match(await html(h), /<u>dropped<\/u>/);
  assert.doesNotMatch(await html(h), /iframe/);
});

test('copy and cut write AO3-clean HTML and plain text', async () => {
  const h = await opened('<p>keep <b>this</b><br>line</p>\n<p>next</p>');
  selectText(h, 'this', 'next');
  const { e, store } = clipboardEvent('copy');
  h.bridge.editor.view.dom.dispatchEvent(e);
  assert.equal(e.defaultPrevented, true);
  assert.equal(store['text/html'], '<p><b>this</b><br>line</p>\n<p>next</p>');
  assert.equal(store['text/plain'], 'this\nline\n\nnext');
  const cut = clipboardEvent('cut');
  h.bridge.editor.view.dom.dispatchEvent(cut.e);
  assert.equal(await html(h), '<p>keep </p>');
});
