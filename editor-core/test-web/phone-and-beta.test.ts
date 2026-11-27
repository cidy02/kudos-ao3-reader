// The keys bar's slide and dictation (T-576e) and a beta's suggestion accepted into the text (T-576f).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import './setup.ts';
import { caretAt, command, html, opened, selectText } from './dom.ts';

const caretText = (h: any) => {
  const { state } = h.bridge.editor.view;
  const $h = state.selection.$head;
  return { before: $h.parent.textBetween(0, $h.parentOffset), selected: state.doc.textBetween(state.selection.from, state.selection.to) };
};

test('moveWord goes a word at a time, across paragraphs, and selects when extending', async () => {
  const h = await opened('<p>Slack water was <em>the</em> hour.</p>\n<p>She meant it.</p>');
  caretAt(h, 'Slack', true);
  assert.equal((await command(h, 'moveWord', { by: 1, extend: false })).applied, true);
  assert.equal(caretText(h).before, 'Slack');
  await command(h, 'moveWord', { by: 3, extend: false });
  assert.equal(caretText(h).before, 'Slack water was the', 'a mark boundary is not a word boundary');
  await command(h, 'moveWord', { by: 1, extend: false });
  await command(h, 'moveWord', { by: 1, extend: false });
  assert.equal(caretText(h).before, 'She', 'past the last word it goes on into the next paragraph');
  await command(h, 'moveWord', { by: -2, extend: false });
  assert.equal(caretText(h).before, 'Slack water was the ', 'back to the start of the previous paragraph’s last word');
  await command(h, 'moveWord', { by: 2, extend: true });
  assert.equal(caretText(h).selected, 'hour.She', 'extending keeps the anchor');
  caretAt(h, 'Slack', true);
  assert.equal((await command(h, 'moveWord', { by: -1, extend: false })).applied, false, 'nothing before the first word');
  assert.equal((await command(h, 'moveWord', { by: 0, extend: false })).applied, false);
  assert.equal(h.bridge.editor.revision, 1, 'moving is not an edit');
});

test('a dictated phrase is its own undo step, with a space before it only where one is needed', async () => {
  const h = await opened('<p>Out past the wall</p>');
  caretAt(h, 'wall');
  let r = await command(h, 'insertPhrase', { text: 'the gulls had gone quiet' });
  assert.equal(r.applied, true);
  assert.equal(r.state.undoTitle, 'Dictation');
  r = await command(h, 'insertPhrase', { text: ', as if listening' });
  assert.equal(await html(h), '<p>Out past the wall the gulls had gone quiet, as if listening</p>', 'no space before punctuation');
  await command(h, 'undo', {});
  assert.equal(await html(h), '<p>Out past the wall the gulls had gone quiet</p>', 'undo takes back exactly the last phrase');
  r = await command(h, 'newParagraph', {});
  assert.equal(r.state.undoTitle, 'New Paragraph');
  await command(h, 'insertPhrase', { text: 'Ines waited' });
  assert.equal(await html(h), '<p>Out past the wall the gulls had gone quiet</p>\n<p>Ines waited</p>', 'no space at the start of a paragraph');
  assert.equal((await command(h, 'insertPhrase', { text: '   ' })).applied, false);
});

test('replaceText puts a suggestion in by HTML offsets, as one undo step, inside one run of text only', async () => {
  const src = '<p>Ines counted the ribs &amp; the hull twice, <em>then</em> once more.</p>';
  const h = await opened(src);
  const at = (s: string) => src.indexOf(s);
  let r = await command(h, 'replaceText', { from: at('twice'), to: at('twice') + 5, text: 'three times' });
  assert.equal(r.applied, true);
  assert.equal(r.state.undoTitle, 'Accept Suggestion');
  let out = await html(h);
  assert.equal(out, src.replace('twice', 'three times'));
  // offsets now refer to the new text; an ampersand is one character but five in the HTML
  r = await command(h, 'replaceText', { from: out.indexOf('&amp;'), to: out.indexOf('&amp;') + 5, text: 'and <b>' });
  assert.equal(r.applied, true);
  out = await html(h);
  assert.match(out, /ribs and &lt;b&gt; the hull/, 'the text goes in as text');
  assert.equal((await command(h, 'replaceText', { from: out.indexOf('&lt;') + 1, to: out.indexOf('&lt;') + 3, text: 'x' })).applied, false, 'splits an entity');
  const em = out.indexOf('times, <em>');
  assert.equal((await command(h, 'replaceText', { from: em, to: em + 'times, <em>then'.length, text: 'x' })).applied, false, 'crosses a tag');
  assert.equal((await command(h, 'replaceText', { from: 5, to: 2, text: 'x' })).applied, false);
  assert.equal((await command(h, 'replaceText', { from: out.length + 10, to: out.length + 12, text: 'x' })).applied, false, 'out of bounds');
  await command(h, 'undo', {});
  assert.match(await html(h), /ribs &amp; the hull three times/, 'undo takes back one suggestion');
});

test('replaceText also deletes and inserts', async () => {
  const src = '<p>She had said it every day that week.</p>';
  const h = await opened(src);
  const i = src.indexOf(' every day');
  assert.equal((await command(h, 'replaceText', { from: i, to: i + ' every day'.length, text: '' })).applied, true);
  const out = await html(h);
  const j = out.indexOf('week');
  assert.equal((await command(h, 'replaceText', { from: j, to: j, text: 'whole ' })).applied, true);
  assert.equal(await html(h), '<p>She had said it that whole week.</p>');
  selectText(h, 'She');
  assert.equal((await command(h, 'replaceText', { from: 0, to: 0, text: '' })).applied, false, 'nothing to do');
});
