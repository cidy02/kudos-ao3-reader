// What 576i added to the bridge: the shared fixtures, the HTML mirror's splices, setAppearance, undo step names,
// Apple locale identifiers, resuming without a history reset, and every native command applying.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { jsdomWindow as w } from './setup.ts';
import { caretAt, command, harness, html, opened, selectText } from './dom.ts';
import type { Harness } from './dom.ts';
import { COMMANDS, record } from './bridge-fixtures.ts';
import type { MirrorEvent } from '../src/editor/editor.ts';

const fixtures = JSON.parse(readFileSync(new URL('../test/bridge-fixtures/bridge.json', import.meta.url), 'utf8'));

test('the page produces exactly the committed bridge fixtures (run node test-web/bridge-fixtures.ts after a protocol change)', async () => {
  assert.deepEqual(JSON.parse(JSON.stringify(await record())), fixtures);
});

test('every fixture event is one of the event types the native side decodes', () => {
  const known = new Set(['ready', 'edited', 'toolbarState', 'journal', 'caretRect', 'mirrorBlocks', 'paste', 'annotationTapped', 'tkTyped', 'wordAtCaret', 'error']);
  for (const e of fixtures.events) assert.ok(known.has(e.type), e.type);
  for (const type of ['toolbarState', 'caretRect', 'mirrorBlocks', 'paste', 'edited']) assert.ok(fixtures.events.some((e: any) => e.type === type), `${type} is in the fixtures`);
});

/** Applies mirror events the way the native HTMLMirrorDocument does. */
function mirrorOf(h: Harness): { html: string; blocks: number; active: number } {
  let blocks: { html: string; separatorAfter: string }[] = [];
  let active = -1;
  for (const e of h.events) {
    if (e.type !== 'mirrorBlocks') continue;
    const m = e as unknown as MirrorEvent;
    if (m.reset) blocks = m.blocks.slice();
    else blocks.splice(m.from, m.to - m.from, ...m.blocks);
    assert.equal(blocks.length, m.totalBlocks, 'the block count agrees after every event');
    active = m.activeBlockIndex;
  }
  return { html: blocks.map((b) => b.html + b.separatorAfter).join(''), blocks: blocks.length, active };
}

test('the mirror: nothing until shown, a reset, then splices that keep it equal to the snapshot', async () => {
  const h = await opened('<p>alpha</p>\n\n<p>beta</p>\n<p>gamma</p>\n<p>delta</p>');
  h.clock.advance(1000);
  assert.equal(h.events.filter((e) => e.type === 'mirrorBlocks').length, 0, 'no text crosses while the mirror is hidden');
  await h.call('setMirror', { enabled: true });
  h.clock.advance(10);
  assert.equal(mirrorOf(h).html, await html(h));
  // edit block 2, type a new block in the middle, delete one: each settles 300 ms after typing stops
  caretAt(h, 'gamma');
  await command(h, 'insertText', { text: '!' });
  h.clock.advance(100);
  assert.equal(h.events.filter((e) => e.type === 'mirrorBlocks').length, 1, 'still typing: no update yet');
  h.clock.advance(300);
  assert.equal(mirrorOf(h).html, await html(h));
  const last = h.events.filter((e) => e.type === 'mirrorBlocks').at(-1) as unknown as MirrorEvent;
  assert.deepEqual([last.from, last.to, last.blocks.length], [1, 3, 2], 'only the edited block and the one before it');
  const view = h.bridge.editor.view;
  caretAt(h, 'beta');
  view.dispatch(view.state.tr.split(view.state.selection.from));
  h.clock.advance(400);
  assert.equal(mirrorOf(h).html, await html(h));
  assert.equal(mirrorOf(h).blocks, 5);
  selectText(h, 'alpha', 'beta');
  view.dispatch(view.state.tr.deleteSelection());
  h.clock.advance(400);
  assert.equal(mirrorOf(h).html, await html(h));
  // the highlight follows the caret without resending text
  const before = h.events.length;
  caretAt(h, 'delta');
  h.clock.advance(150);
  const moved = h.events.slice(before).filter((e) => e.type === 'mirrorBlocks') as unknown as MirrorEvent[];
  assert.equal(moved.length, 1);
  assert.equal(moved[0]!.blocks.length, 0);
  assert.equal(moved[0]!.activeBlockIndex, mirrorOf(h).blocks - 1);
  await h.call('setMirror', { enabled: false });
  await command(h, 'insertText', { text: 'x' });
  h.clock.advance(1000);
  assert.equal(h.events.slice(before).filter((e) => e.type === 'mirrorBlocks').length, 1, 'hidden again: nothing more');
});

test('the mirror starts again from a reset at every hand-off in', async () => {
  const h = await opened('<p>a</p>\n<p>b</p>');
  await h.call('setMirror', { enabled: true });
  h.clock.advance(10);
  await h.call('freeze', {});
  await h.call('activate', { caret: 3, focus: false });
  h.clock.advance(10);
  const m = h.events.filter((e) => e.type === 'mirrorBlocks').at(-1) as unknown as MirrorEvent;
  assert.equal(m.reset, true);
});

test('setAppearance: type to the CSS variables, contrast and size category to root attributes', async () => {
  const h = harness();
  await h.ready;
  const root = w.document.documentElement;
  await h.call('setAppearance', { fontFamily: '-apple-system', fontSizePx: 53, lineHeight: 1.4, contentSizeCategory: 'UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge', isAccessibilityCategory: true, colorScheme: 'dark', increaseContrast: true, boldText: true });
  assert.equal(root.style.getPropertyValue('--kd-size'), '53px');
  assert.equal(root.style.getPropertyValue('--kd-weight'), '600');
  assert.equal(root.style.colorScheme, 'dark');
  assert.ok(root.hasAttribute('data-increase-contrast'));
  assert.ok(root.hasAttribute('data-accessibility-size'));
  assert.equal(root.dataset.contentSize, 'UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge');
  await h.call('setAppearance', { fontFamily: '-apple-system', fontSizePx: 17, lineHeight: 1.6, contentSizeCategory: 'UICTContentSizeCategoryL', isAccessibilityCategory: false, colorScheme: 'light', increaseContrast: false, boldText: false });
  assert.ok(!root.hasAttribute('data-increase-contrast'));
  await assert.rejects(h.call('setAppearance', { fontFamily: 'x;}', fontSizePx: 17 }), (e: any) => e.code === 'bad-args');
});

test('undo and redo carry the names of their steps', async () => {
  const h = await opened('<p>ab</p>');
  selectText(h, 'ab');
  let r = await command(h, 'toggleMark', { mark: 'italic' });
  assert.equal(r.state.undoTitle, 'Italic');
  caretAt(h, 'ab');
  await command(h, 'insertText', { text: 'c' });
  r = await command(h, 'insertSceneBreak', { style: 'line' });
  assert.equal(r.state.undoTitle, 'Scene Break');
  r = await command(h, 'undo');
  assert.equal(r.state.undoTitle, 'Typing');
  assert.equal(r.state.redoTitle, 'Scene Break');
  r = await command(h, 'redo');
  assert.equal(r.state.undoTitle, 'Scene Break');
  assert.equal(r.state.redoTitle, null);
  await h.call('configure', { variant: 'content', labels: { stepItalic: 'Kursiv' } });
  const g = await opened('<p>ab</p>');
  await g.call('configure', { variant: 'content', labels: { stepItalic: 'Kursiv' } });
  await g.call('load', { html: '<p>ab</p>', revision: 1 });
  await g.call('activate', { caret: 4, focus: false });
  selectText(g, 'ab');
  assert.equal((await command(g, 'toggleMark', { mark: 'italic' })).state.undoTitle, 'Kursiv');
});

test('Apple locale identifiers are accepted; nonsense is ignored rather than failing configure', async () => {
  const h = harness();
  await h.call('configure', { variant: 'content', locale: 'en_GB' });
  assert.equal(w.document.documentElement.lang, 'en-GB');
  await h.call('configure', { variant: 'content', locale: 'sr_Latn_RS@calendar=gregorian' });
  assert.equal(w.document.documentElement.lang, 'sr-Latn-RS');
  const r = await h.call('configure', { variant: 'content', locale: '!!' });
  assert.equal(r.bridgeVersion, 1);
});

test('activate without a caret resumes Rich Text with its history (a switch out that did not happen)', async () => {
  const h = await opened('<p>ab</p>');
  caretAt(h, 'ab');
  await command(h, 'insertText', { text: 'c' });
  await h.call('freeze', {});
  await h.call('snapshot', { caret: true });
  await h.call('activate', { caret: null, focus: true });
  assert.equal((await command(h, 'undo')).applied, true);
  assert.equal(await html(h), '<p>ab</p>');
  await h.call('freeze', {});
  await h.call('activate', { caret: 2, focus: true });
  assert.equal((await command(h, 'undo')).applied, false, 'a hand-off in starts with empty history (U2)');
});

test('every command the native side sends applies to a document where it makes sense', async () => {
  for (const c of COMMANDS) {
    const h = await opened('<p>one two</p>\n<ul><li>item</li></ul>\n<p><a href="https://x.org/">link</a> end</p>');
    if (c.name === 'unlink') caretAt(h, 'lin');
    else if (c.name === 'redo') { selectText(h, 'two'); await command(h, 'toggleMark', { mark: 'bold' }); await command(h, 'undo'); }
    else if (c.name === 'undo') { selectText(h, 'two'); await command(h, 'toggleMark', { mark: 'bold' }); }
    else if (c.name === 'clearFormatting') { selectText(h, 'two'); await command(h, 'toggleMark', { mark: 'bold' }); selectText(h, 'two'); }
    else if (c.name === 'moveCaret' || c.name === 'insertLineBreak') caretAt(h, 'on');
    else if (c.id === 'setBlock.body') caretAt(h, 'item');
    else if (c.id === 'setAlignment.left') { selectText(h, 'two'); await command(h, 'setAlignment', { alignment: 'right' }); }
    else if (c.id === 'setDirection.leftToRight') { selectText(h, 'two'); await command(h, 'setDirection', { direction: 'rightToLeft' }); }
    else if (c.name === 'setLink' || c.name === 'toggleMark' || c.name.startsWith('set')) selectText(h, 'two');
    else caretAt(h, 'one');
    const r = await command(h, c.name, c.attrs);
    assert.equal(r.applied, true, c.id);
  }
});

test('insertLineBreak is Shift+Return: a break, and a second one splits the paragraph', async () => {
  const h = await opened('<p>ab</p>');
  caretAt(h, 'a');
  await command(h, 'insertLineBreak');
  assert.equal(await html(h), '<p>a<br>b</p>');
  await command(h, 'insertLineBreak');
  assert.equal(await html(h), '<p>a</p>\n<p>b</p>');
});
