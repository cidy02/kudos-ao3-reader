// Every FormatCommand (576c's contract) produces the right document, checked as the HTML rich mode would hand back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { caretAt, command, html, opened, selectText } from './dom.ts';

const run = async (start: string, act: (h: Awaited<ReturnType<typeof opened>>) => Promise<unknown> | void) => {
  const h = await opened(start);
  await act(h);
  return { h, out: await html(h) };
};

test('toggleMark: each FormatMark writes the toolbar tag, and toggles off again', async () => {
  const expected: Record<string, string> = {
    bold: '<p>a <strong>bc</strong> d</p>',
    italic: '<p>a <em>bc</em> d</p>',
    underline: '<p>a <u>bc</u> d</p>',
    strikethrough: '<p>a <strike>bc</strike> d</p>',
    superscript: '<p>a <sup>bc</sup> d</p>',
    subscript: '<p>a <sub>bc</sub> d</p>',
    smaller: '<p>a <small>bc</small> d</p>',
    code: '<p>a <code>bc</code> d</p>',
  };
  for (const [mark, want] of Object.entries(expected)) {
    const { h, out } = await run('<p>a bc d</p>', async (h) => { selectText(h, 'bc'); assert.equal((await command(h, 'toggleMark', { mark })).applied, true); });
    assert.equal(out, want, mark);
    await command(h, 'toggleMark', { mark });
    assert.equal(await html(h), '<p>a bc d</p>', `${mark} off`);
  }
});

test('toggleMark keeps a parsed tag when removing, and superscript replaces subscript', async () => {
  const { out } = await run('<p>a <b>bc</b> d</p>', async (h) => { selectText(h, 'bc'); await command(h, 'toggleMark', { mark: 'bold' }); });
  assert.equal(out, '<p>a bc d</p>');
  const { out: sup } = await run('<p>x<sub>2</sub></p>', async (h) => { selectText(h, '2'); await command(h, 'toggleMark', { mark: 'superscript' }); });
  assert.equal(sup, '<p>x<sup>2</sup></p>');
});

test('toggleMark at a caret applies to what is typed next', async () => {
  const { out } = await run('<p>ab</p>', async (h) => {
    caretAt(h, 'ab');
    await command(h, 'toggleMark', { mark: 'italic' });
    await command(h, 'insertText', { text: 'cd' });
  });
  assert.equal(out, '<p>ab<em>cd</em></p>');
});

test('setBlock: heading, subheading, centred, back to body', async () => {
  const cases: [string, string][] = [
    ['heading', '<h3>Title</h3>'],
    ['subheading', '<h4>Title</h4>'],
    ['centred', '<p align="center">Title</p>'],
  ];
  for (const [block, want] of cases) {
    const { h, out } = await run('<p>Title</p>', async (h) => { caretAt(h, 'Title'); await command(h, 'setBlock', { block }); });
    assert.equal(out, want, block);
    await command(h, 'setBlock', { block }); // the same style again turns it off
    assert.equal(await html(h), '<p>Title</p>', `${block} toggled off`);
    await command(h, 'setBlock', { block });
    await command(h, 'setBlock', { block: 'body' });
    assert.equal(await html(h), '<p>Title</p>', `${block} then body`);
  }
});

test('setBlock: quote wraps and unwraps', async () => {
  const { h, out } = await run('<p>one</p>\n<p>two</p>', async (h) => { selectText(h, 'one', 'two'); await command(h, 'setBlock', { block: 'quote' }); });
  assert.equal(out, '<blockquote><p>one</p>\n<p>two</p></blockquote>');
  await command(h, 'setBlock', { block: 'quote' });
  assert.equal(await html(h), '<p>one</p>\n<p>two</p>');
});

test('setBlock: lists are AO3-shaped (<li>text</li>), switch type, and lift out', async () => {
  const { h, out } = await run('<p>one</p>\n<p>two</p>', async (h) => { selectText(h, 'one', 'two'); await command(h, 'setBlock', { block: 'bulletedList' }); });
  assert.equal(out, '<ul><li>one</li>\n<li>two</li></ul>');
  await command(h, 'setBlock', { block: 'numberedList' });
  assert.equal(await html(h), '<ol><li>one</li>\n<li>two</li></ol>');
  selectText(h, 'one', 'two');
  await command(h, 'setBlock', { block: 'numberedList' });
  assert.equal(await html(h), '<p>one</p>\n<p>two</p>', 'implicit paragraphs become <p> again outside the list');
});

test('setBlock: body takes a paragraph out of a list and a quote', async () => {
  const { out } = await run('<blockquote><ul><li>deep</li></ul></blockquote>', async (h) => { caretAt(h, 'deep'); await command(h, 'setBlock', { block: 'body' }); });
  assert.equal(out, '<p>deep</p>');
});

test('setBlock: fold-out wraps in details with a summary, and unwraps', async () => {
  const { h, out } = await run('<p>secret</p>', async (h) => { caretAt(h, 'secret'); await command(h, 'setBlock', { block: 'foldOut', title: 'Spoiler' }); });
  assert.equal(out, '<details><summary>Spoiler</summary>\n<p>secret</p></details>');
  caretAt(h, 'secret');
  await command(h, 'setBlock', { block: 'foldOut' });
  assert.equal(await html(h), '<p>Spoiler</p>\n<p>secret</p>');
});

test('setAlignment and setDirection write align and dir attributes, never styles', async () => {
  for (const [alignment, want] of [['centre', '<p align="center">x</p>'], ['right', '<p align="right">x</p>'], ['justify', '<p align="justify">x</p>'], ['left', '<p>x</p>']] as const) {
    const { out } = await run('<p align="right">x</p>', async (h) => { caretAt(h, 'x'); await command(h, 'setAlignment', { alignment }); });
    assert.equal(out, want, alignment);
  }
  const { h, out } = await run('<p>x</p>', async (h) => { caretAt(h, 'x'); await command(h, 'setDirection', { direction: 'rightToLeft' }); });
  assert.equal(out, '<p dir="rtl">x</p>');
  await command(h, 'setAlignment', { alignment: 'left' });
  assert.equal(await html(h), '<p align="left" dir="rtl">x</p>', 'left in a right-to-left paragraph is explicit');
  await command(h, 'setDirection', { direction: 'leftToRight' });
  assert.equal(await html(h), '<p align="left">x</p>');
});

test('setLink on a selection, on a caret in a link, and on an empty caret; unlink', async () => {
  const { h, out } = await run('<p>see here now</p>', async (h) => { selectText(h, 'here'); await command(h, 'setLink', { url: 'https://example.com/a' }); });
  assert.equal(out, '<p>see <a href="https://example.com/a">here</a> now</p>');
  caretAt(h, 'he');
  await command(h, 'setLink', { url: 'mailto:me@example.com' });
  assert.equal(await html(h), '<p>see <a href="mailto:me@example.com">here</a> now</p>', 'the whole link changes');
  caretAt(h, 'her');
  await command(h, 'unlink');
  assert.equal(await html(h), '<p>see here now</p>');
  caretAt(h, 'now');
  await command(h, 'setLink', { url: 'https://example.org/' });
  assert.equal(await html(h), '<p>see here now<a href="https://example.org/">https://example.org/</a></p>', 'a caret inserts the address as its text');
});

test('setLink refuses addresses the link sheet does not allow', async () => {
  for (const url of ['javascript:alert(1)', 'ftp://x.org/', 'data:text/html,hi', 'example.com', '']) {
    const h = await opened('<p>x</p>');
    selectText(h, 'x');
    assert.equal((await command(h, 'setLink', { url })).applied, false, url);
    assert.equal(await html(h), '<p>x</p>');
  }
});

test('insertImage writes img with src, alt, width and height; refuses non-http addresses', async () => {
  const { out } = await run('<p>ab</p>', async (h) => {
    caretAt(h, 'a');
    assert.equal((await command(h, 'insertImage', { address: 'https://example.com/i.png', description: 'A cat', width: 200, height: 100 })).applied, true);
  });
  assert.equal(out, '<p>a<img alt="A cat" height="100" src="https://example.com/i.png" width="200">b</p>');
  const h = await opened('<p>x</p>');
  assert.equal((await command(h, 'insertImage', { address: 'file:///etc/passwd' })).applied, false);
});

test('insertSceneBreak: asterism, asterisks and a line, splitting the paragraph at the caret', async () => {
  const want: Record<string, string> = {
    asterism: '<p>one</p>\n<p align="center">⁂</p>\n<p>two</p>',
    asterisks: '<p>one</p>\n<p align="center">* * *</p>\n<p>two</p>',
    line: '<p>one</p>\n<hr>\n<p>two</p>',
  };
  for (const [style, expected] of Object.entries(want)) {
    const { h, out } = await run('<p>onetwo</p>', async (h) => { caretAt(h, 'one'); await command(h, 'insertSceneBreak', { style }); });
    assert.equal(out, expected, style);
    await command(h, 'insertText', { text: 'X' });
    assert.match(await html(h), /<p>Xtwo<\/p>$/, `${style}: the caret is after the break`);
  }
  const { out } = await run('<p>end</p>', async (h) => { caretAt(h, 'end'); await command(h, 'insertSceneBreak', { style: 'line' }); await command(h, 'insertText', { text: 'next' }); });
  assert.equal(out, '<p>end</p>\n<hr>\n<p>next</p>', 'at the end of the text a new paragraph follows the break');
});

test('insertFootnote: a numbered anchor pair AO3 keeps, and the caret in the note', async () => {
  const { h, out } = await run('<p>Claim.</p>\n<p>More.</p>', async (h) => {
    caretAt(h, 'Claim.');
    await command(h, 'insertFootnote');
    await command(h, 'insertText', { text: 'Source.' });
  });
  assert.equal(out, '<p>Claim.<a href="#fn1" name="fnref1"><sup>1</sup></a></p>\n<p>More.</p>\n<p><a href="#fnref1" name="fn1">1.</a> Source.</p>');
  caretAt(h, 'More.');
  await command(h, 'insertFootnote');
  assert.match(await html(h), /More\.<a href="#fn2" name="fnref2"><sup>2<\/sup><\/a>.*<a href="#fnref2" name="fn2">2\.<\/a> <\/p>$/s);
});

test('undo and redo', async () => {
  const { h, out } = await run('<p>ab</p>', async (h) => { selectText(h, 'ab'); await command(h, 'toggleMark', { mark: 'bold' }); });
  assert.equal(out, '<p><strong>ab</strong></p>');
  assert.equal((await command(h, 'undo')).applied, true);
  assert.equal(await html(h), '<p>ab</p>');
  assert.equal((await command(h, 'redo')).applied, true);
  assert.equal(await html(h), '<p><strong>ab</strong></p>');
});

test('clearFormatting removes character formatting and heading or centring, keeps links', async () => {
  const { out } = await run('<h3 align="center"><em>a</em> <a href="https://x.org/"><b>b</b></a></h3>', async (h) => { selectText(h, 'a', 'b'); await command(h, 'clearFormatting'); });
  assert.equal(out, '<p>a <a href="https://x.org/">b</a></p>');
});

test('openTableInHTML is native-only and changes nothing', async () => {
  const { h, out } = await run('<p>x</p>', async (h) => { assert.equal((await command(h, 'openTableInHTML')).applied, false); });
  assert.equal(out, '<p>x</p>');
  assert.equal((await command(h, 'noSuchCommand')).applied, false);
});

test('typing commands for the keys bar: insertText, insertQuotes, moveCaret', async () => {
  const { h, out } = await run('<p>said hi</p>', async (h) => { selectText(h, 'hi'); await command(h, 'insertQuotes'); });
  assert.equal(out, '<p>said “hi”</p>');
  caretAt(h, 'said');
  await command(h, 'insertText', { text: ' —' });
  assert.equal(await html(h), '<p>said — “hi”</p>');
  await command(h, 'moveCaret', { by: -1 });
  await command(h, 'insertText', { text: '|' });
  assert.equal(await html(h), '<p>said |— “hi”</p>');
  const empty = await opened('<p>a</p>');
  caretAt(empty, 'a');
  await command(empty, 'insertQuotes', { open: '«', close: '»' });
  await command(empty, 'insertText', { text: 'q' });
  assert.equal(await html(empty), '<p>a«q»</p>');
});

test('commands do nothing while frozen (I1)', async () => {
  const h = await opened('<p>ab</p>');
  selectText(h, 'ab');
  await h.call('freeze', {});
  assert.equal((await command(h, 'toggleMark', { mark: 'bold' })).applied, false);
  assert.equal(await html(h), '<p>ab</p>');
});
