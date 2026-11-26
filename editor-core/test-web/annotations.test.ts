// Notes in the text, TK markers and name suggestions (T-576d): highlights that follow edits and are never serialized,
// the selection's range for anchoring a note, a typed "TK" reported with its range, and the word at the caret.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { jsdomWindow as w } from './setup.ts';
import { caretAt, command, html, opened, selectText } from './dom.ts';
import { currentAnnotations } from '../src/editor/annotations.ts';

const SRC = '<p>Marta looked at the boat.</p>\n<p>The tide was <em>low</em> that night.</p>';

test('a note anchored by HTML offsets is drawn over its text, follows edits, and is never serialized', async () => {
  const h = await opened(SRC);
  const from = SRC.indexOf('the boat'), to = from + 'the boat'.length;
  const r = await h.call('setAnnotations', { items: [{ id: 'n1', kind: 'note', from, to }, { id: 't1', kind: 'tk', from: SRC.indexOf('low'), to: SRC.indexOf('low') + 3 }] });
  assert.deepEqual(r, { placed: [{ id: 'n1', found: true }, { id: 't1', found: true }] });
  const root = h.bridge.editor.view.dom;
  assert.equal(root.querySelector('[data-annotation="n1"]')?.textContent, 'the boat');
  assert.ok(root.querySelector('[data-annotation="n1"]')?.classList.contains('kd-note'));
  assert.equal(root.querySelector('[data-annotation="t1"]')?.textContent, 'low');
  caretAt(h, 'Marta', true);
  await command(h, 'insertText', { text: 'Then ' });
  const view = h.bridge.editor.view;
  const n1 = currentAnnotations(view.state).find((a) => a.id === 'n1')!;
  assert.equal(view.state.doc.textBetween(n1.from, n1.to), 'the boat', 'the highlight moved with the edit');
  assert.doesNotMatch(await html(h), /annotation|kd-note/);
  assert.equal(h.bridge.editor.revision, 2, 'drawing notes is not an edit');
});

test('notes anchor to the last snapshot after an edited switch out (the text HTML mode then holds)', async () => {
  const h = await opened(SRC);
  caretAt(h, 'Marta');
  await command(h, 'insertText', { text: ' Ruiz' });
  await h.call('freeze', {});
  const snap = await h.call('snapshot', {});
  await h.call('activate', { caret: 0, focus: false });
  const from = snap.html.indexOf('tide');
  await h.call('setAnnotations', { items: [{ id: 'n', kind: 'note', from, to: from + 4 }] });
  assert.equal(h.bridge.editor.view.dom.querySelector('[data-annotation="n"]')?.textContent, 'tide');
});

test('a tap on a highlight is reported', async () => {
  const h = await opened(SRC);
  const from = SRC.indexOf('boat');
  await h.call('setAnnotations', { items: [{ id: 'tap-me', kind: 'note', from, to: from + 4 }] });
  h.bridge.editor.view.dom.querySelector('[data-annotation="tap-me"]')!.dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.ok(h.events.some((e: any) => e.type === 'annotationTapped' && e.id === 'tap-me'));
});

test('snapshot with selection returns the selection as offsets into its own HTML, before and after edits', async () => {
  const h = await opened(SRC);
  selectText(h, 'tide was');
  let s = await h.call('snapshot', { selection: true });
  assert.equal(s.html.slice(s.selection.from, s.selection.to), 'tide was');
  caretAt(h, 'Marta');
  await command(h, 'insertText', { text: '!' });
  selectText(h, 'that night');
  s = await h.call('snapshot', { selection: true });
  assert.equal(s.html.slice(s.selection.from, s.selection.to), 'that night');
  caretAt(h, 'night');
  assert.equal((await h.call('snapshot', { selection: true })).selection, null, 'an empty selection has no range');
  assert.equal((await h.call('snapshot', {})).selection, undefined, 'not asked for, not sent');
});

test('typing "TK" and then a space reports the token\'s range', async () => {
  const h = await opened('<p>The name of the boat is </p>');
  caretAt(h, 'is ');
  await command(h, 'insertText', { text: 'TK' });
  assert.ok(!h.events.some((e: any) => e.type === 'tkTyped'), 'not until the word ends');
  await command(h, 'insertText', { text: '.' });
  const ev = h.events.find((e: any) => e.type === 'tkTyped') as any;
  const out = await html(h);
  assert.equal(out.slice(ev.from, ev.to), 'TK');
  const g = await opened('<p>x</p>');
  caretAt(g, 'x');
  await command(g, 'insertText', { text: ' TKO ' });
  assert.ok(!g.events.some((e: any) => e.type === 'tkTyped'), 'TKO is not a TK');
});

test('the word at the caret goes to the keys bar for names, and completeWord replaces it', async () => {
  const h = await opened('<p>She saw </p>');
  caretAt(h, 'saw ');
  await command(h, 'insertText', { text: 'M' });
  await command(h, 'insertText', { text: 'a' });
  await command(h, 'insertText', { text: 'r' });
  h.clock.advance(200);
  const words = h.events.filter((e: any) => e.type === 'wordAtCaret').map((e: any) => e.prefix);
  assert.equal(words.at(-1), 'Mar');
  assert.ok(!words.includes('M'), 'one letter is not a word yet');
  const r = await command(h, 'completeWord', { text: 'Marta’s' });
  assert.equal(r.applied, true);
  assert.equal(await html(h), '<p>She saw Marta’s</p>');
  assert.equal(r.state.undoTitle, 'Typing');
});

test('setAnnotations checks its arguments', async () => {
  const h = await opened(SRC);
  await assert.rejects(h.call('setAnnotations', { items: [{ id: 'x', kind: 'comment', from: 0, to: 1 }] }), (e: any) => e.code === 'bad-args');
  await assert.rejects(h.call('setAnnotations', { items: 'no' }), (e: any) => e.code === 'bad-args');
  assert.deepEqual(await h.call('setAnnotations', { items: [] }), { placed: [] });
});
