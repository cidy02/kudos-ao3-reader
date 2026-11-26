import { test } from 'node:test';
import assert from 'node:assert/strict';
import fc from 'fast-check';
import type { Node as PMNode } from 'prosemirror-model';
import { EditorState } from 'prosemirror-state';
import { activate, load, parse, schema, serialize, serializeDoc, snapshot, lint, FIELD_LIMITS } from '../src/index.ts';
import { docArb } from './arb.ts';

const n = schema.nodes;
const m = schema.marks;
const html = (s: string, v: 'content' | 'notes' | 'summary' = 'content') => serialize(parse(s, v));
const text = (s: string, ...marks: ReturnType<typeof m.strong.create>[]) => schema.text(s, marks);
const para = (...c: PMNode[]) => n.paragraph!.create(null, c);
const doc = (...b: PMNode[]) => n.doc!.create(null, b);

test('S1-S3: fragment, void elements without a slash, quoting and escapes', () => {
  assert.equal(serialize(doc(para(text('a'), n.hard_break!.create(), text('b')), n.horizontal_rule!.create({ width: '5"0&' }))), '<p>a<br>b</p>\n<hr width="5&quot;0&amp;">');
  assert.equal(serialize(doc(para(n.image!.create({ src: 'http://x.org/a.png', alt: 'a&b" ' })))), '<p><img alt="a&amp;b&quot;&nbsp;" src="http://x.org/a.png"></p>');
});

test('S4: attribute order is own attributes, then align dir lang title, then class', () => {
  const d = doc(n.blockquote!.create({ class: 'c1', title: 't', lang: 'en', dir: 'rtl', align: 'left', cite: 'http://x.org/' }, [para(text('x'))]));
  assert.equal(serialize(d), '<blockquote cite="http://x.org/" align="left" dir="rtl" lang="en" title="t" class="c1"><p>x</p></blockquote>');
  assert.equal(serialize(doc(n.horizontal_rule!.create({ width: '9', align: 'center', title: 't' }))), '<hr align="center" width="9" title="t">');
  assert.equal(serialize(parse('<a title="t" name="n" href="http://x.org/">l</a>', 'content')), '<p><a href="http://x.org/" name="n" title="t">l</a></p>');
});

test('S5 and S8: only & < > and U+00A0 are escaped; newlines never reach a text node', () => {
  assert.equal(serialize(doc(para(text('a & b < c > d   é 日 😀 "q"')))), '<p>a &amp; b &lt; c &gt; d &nbsp; é 日 😀 "q"</p>');
  assert.equal(html('<p>one\ntwo</p>'), '<p>one two</p>');
  // AO3 deletes the literal marker from typed HTML, so the serializer must not emit it from the writer's text
  const marker = doc(para(text('x ____spacer____ y')));
  assert.equal(serialize(marker), '<p>x ____spacer&#95;___ y</p>');
  assert.equal(parse(serialize(marker), 'content').textContent, 'x ____spacer____ y');
  assert.equal(html('x ____spacer____ y'), '<p>x  y</p>');
});

test('S6: one newline between sibling blocks, none elsewhere, nothing at the ends', () => {
  assert.equal(html('<div>a\n\n\nb</div>\n\n<ul><li>x</li><li>y</li></ul>\n'), '<div><p>a</p>\n<p>&nbsp;</p>\n<p>b</p></div>\n<ul><li>x</li>\n<li>y</li></ul>');
  assert.equal(html('  \n  '), '');
});

test('S7 and S9: inline content only in inline blocks; an empty paragraph is <p>&nbsp;</p>', () => {
  assert.equal(html('<p>a</p><p>&nbsp;</p>'), '<p>a</p>\n<p>&nbsp;</p>');
  assert.equal(serialize(doc(para())), ''); // an empty field
  assert.equal(serialize(doc(para(), para())), '<p>&nbsp;</p>\n<p>&nbsp;</p>');
  assert.equal(html('<ul><li>implicit<ul><li>nested</li></ul></li></ul>'), '<ul><li>implicit<ul><li>nested</li></ul></li></ul>');
  assert.equal(html('<ul><li><p>explicit</p></li></ul>'), '<ul><li><p>explicit</p></li></ul>');
});

test('S10: adjacent <br> split the paragraph as AO3 would (three or more add a spacer)', () => {
  assert.equal(html('<p>a<br><br>b</p>'), '<p>a</p>\n<p>b</p>');
  assert.equal(html('<p>a<br><br><br>b</p>'), '<p>a</p>\n<p>&nbsp;</p>\n<p>b</p>');
  assert.equal(html('<h2>a<br><br>b</h2>'), '<h2>a<br>b</h2>');
});

test('S11 and S12: marks nest in spec order, adjacent identical marks merge, the written tag is the parsed one', () => {
  assert.equal(html('<p><i><b>x</b></i><b><i>y</i></b></p>'), '<p><b><i>xy</i></b></p>');
  assert.equal(html('<p><u>u</u><s>s</s><strike>k</strike><del>d</del><sup>1</sup><big>b</big><kbd>k</kbd><abbr title="t">a</abbr></p>'), '<p><u>u</u><s>s</s><strike>k</strike><del>d</del><sup>1</sup><big>b</big><kbd>k</kbd><abbr title="t">a</abbr></p>');
  assert.equal(serialize(doc(para(text('x', m.em!.create(), m.strong!.create(), m.underline!.create())))), '<p><b>x</b></p>'.replace('<b>x</b>', '<strong><em><u>x</u></em></strong>'));
  assert.equal(serialize(doc(para(text('a', m.strong!.create()), text('b', m.strong!.create({ tag: 'b' }))))), '<p><strong>a</strong><b>b</b></p>');
});

test('S13 and the tiers: tables, pre, embeds and empty inline elements are kept verbatim; a plain span is unwrapped', () => {
  const src = '<p>a <span>plain</span> <span class="skin">styled</span> <a name="ch1"></a>b</p>\n<table border="1"><tr><td>c</td></tr></table>\n<pre>  keep\n  this</pre>\n<iframe src="https://www.youtube.com/embed/x" allowfullscreen=""></iframe>';
  const r = load(src, 'content');
  assert.equal(r.doc.childCount, 4);
  assert.equal(r.doc.child(1).type.name, 'raw_block');
  assert.equal(r.doc.child(2).attrs.source, '<pre>  keep\n  this</pre>');
  assert.equal(r.doc.child(3).type.name, 'raw_block');
  assert.deepEqual(r.loss.unwrapped, { span: 1 });
  assert.equal(r.loss.preserved, 4);
  assert.equal(serialize(r.doc), '<p>a plain <span class="skin">styled</span> <a name="ch1" rel="nofollow"></a>b</p>\n<table border="1"><tbody><tr><td>c</td></tr></tbody></table>\n<pre>  keep\n  this</pre>\n<iframe src="https://www.youtube.com/embed/x" allowfullscreen=""></iframe>');
});

test('field variants: class survives in content and notes, never in summary; embeds only in content', () => {
  assert.equal(html('<p class="ab">x</p>', 'content'), '<p class="ab">x</p>');
  assert.equal(html('<p class="ab">x</p>', 'notes'), '<p class="ab">x</p>');
  assert.equal(html('<p class="ab">x</p>', 'summary'), '<p>x</p>');
  assert.equal(html('<iframe src="https://www.youtube.com/embed/x"></iframe>', 'notes'), '');
  assert.deepEqual(FIELD_LIMITS, { content: 510000, notes: 5000, summary: 1250 });
});

test('loss report (6.9): dropped elements and attributes are counted, with the AO3 rule that removes them', () => {
  const r = lint('<p style="a" id="b"><font color="red">x</font><font>y</font><marquee>z</marquee><script>1</script></p><p onclick="x" style="c">w</p>', 'content');
  assert.deepEqual(r.dropped.elements, { font: 2, marquee: 1, script: 1 });
  assert.deepEqual(r.dropped.attributes, { style: 2, id: 1, onclick: 1 }); // a removed element's own attributes are not counted again
  assert.equal(lint('<p class="x y">a</p>', 'summary').dropped.attributes.class, 1);
  const clean = lint('<p>fine <b>text</b></p>', 'content');
  assert.deepEqual(clean.dropped, { elements: {}, attributes: {} });
  assert.equal(clean.preserved, 0);
});

test('loss report: javascript: links lose the attribute, unknown tags are unwrapped by AO3 and counted as dropped', () => {
  const r = lint('<a href="javascript:x">l</a><section>s</section>', 'content');
  assert.deepEqual(r.dropped, { elements: { section: 1 }, attributes: { href: 1 } });
});

test('R1 through snapshot: an unedited document returns the original bytes, an edited one the serializer output', () => {
  const src = '<P>a</P>\r\n\r\n\r\nb &amp; c'; // whitespace around a block is insignificant to AO3
  const loaded = load(src, 'content');
  assert.equal(snapshot(loaded, loaded.doc).html, src);
  const st = EditorState.create({ doc: loaded.doc });
  const edited = st.apply(st.tr.insertText('X', 2)).doc;
  assert.equal(snapshot(loaded, edited).html, '<p>aX</p>\n<p>b &amp; c</p>');
});

// ---- caret maps (7.5) ------------------------------------------------------------------------------------

function textPositions(d: PMNode): { pos: number; ch: string }[] {
  const out: { pos: number; ch: string }[] = [];
  d.descendants((node, pos) => { if (node.isText) for (let i = 0; i < node.text!.length; i++) out.push({ pos: pos + i, ch: node.text![i]! }); });
  return out;
}

test('caret: HTML offset -> position -> HTML offset lands on the same character (entities, tags, CRLF, comments)', () => {
  const src = '<p class="x">Hello &amp; <b>wor&lt;ld</b> &#x1F600;!</p>\r\n\r\nSecond <!-- c --> para\r\nwith &copy; and <i>more</i>\r\n<table><tr><td>cell</td></tr></table>\r\nLast <3 line';
  const loaded = load(src, 'content');
  let checked = 0;
  for (const { pos, ch } of textPositions(loaded.doc)) {
    if (/\s/.test(ch) || /[\udc00-\udfff]/.test(ch)) continue; // no caret between the halves of a surrogate pair
    const off = loaded.sources.offsetForPos(pos);
    assert.notEqual(off, null, `no offset for pos ${pos} (${ch})`);
    const back = activate(loaded, off!);
    assert.deepEqual(back, { pos, caretFound: true }, `char ${JSON.stringify(ch)} at pos ${pos}, offset ${off}`);
    checked++;
  }
  assert.ok(checked > 40);
  // the offset is where the character is written in the original text
  const posOfCopy = textPositions(loaded.doc).find((p) => p.ch === '©')!.pos;
  assert.equal(src.slice(loaded.sources.offsetForPos(posOfCopy)!).slice(0, 6), '&copy;');
});

test('caret: offsets inside a tag, a comment or a reference move to the end of that token; past the end is not found', () => {
  const src = '<p>ab <b>cd</b> &amp; ef</p>';
  const loaded = load(src, 'content');
  const at = (o: number) => activate(loaded, o);
  const posOf = (ch: string, nth = 0) => textPositions(loaded.doc).filter((p) => p.ch === ch)[nth]!.pos;
  assert.deepEqual(at(src.indexOf('<b>') + 1), { pos: posOf('c'), caretFound: true });
  assert.deepEqual(at(src.indexOf('&amp;') + 2), { pos: posOf('e'), caretFound: true });
  assert.deepEqual(at(src.indexOf('d')), { pos: posOf('d'), caretFound: true });
  assert.equal(at(src.length + 50).caretFound, false);
  assert.equal(at(-5).caretFound, true);
});

test('caret: an offset inside a preserved atom lands in the text after it', () => {
  const src = '<p>before</p>\n<table><tr><td>cell</td></tr></table>\n<p>after</p>';
  const loaded = load(src, 'content');
  const r = activate(loaded, src.indexOf('cell'));
  const afterPos = textPositions(loaded.doc).find((p) => p.ch === 'a' && loaded.doc.textBetween(p.pos, p.pos + 5) === 'after')!.pos;
  assert.deepEqual(r, { pos: afterPos, caretFound: true });
});

test('caret after an edit: the serializer reports the output offset of the head, escapes included', () => {
  fc.assert(fc.property(docArb('content'), fc.nat(), (d, pick) => {
    const chars = textPositions(d);
    fc.pre(chars.length > 0);
    const { pos, ch } = chars[pick % chars.length]!;
    const { html: out, headOffset } = serializeDoc(d, { head: pos });
    assert.notEqual(headOffset, null);
    const esc = ch === '&' ? '&amp;' : ch === '<' ? '&lt;' : ch === '>' ? '&gt;' : ch === ' ' ? '&nbsp;' : ch;
    const rest = out.slice(headOffset!);
    // the head sits before the character, possibly just before a closing/opening tag boundary that shares the offset
    // (or before the `&#95;` that keeps a literal ____spacer____ from being deleted by AO3, departure 1)
    assert.ok(rest.startsWith(esc) || (ch === '_' && rest.startsWith('&#95;')) || /^(<\/?[a-z0-9]+[^>]*>)+/.test(rest), `head ${pos} in ${out}`);
  }), { seed: 576576, numRuns: 500 });
});

test('caret in an untouched block of an edited document is mapped through the slice', () => {
  const src = 'First para\n\nSecond para\n\nThird para';
  const loaded = load(src, 'content');
  const st = EditorState.create({ doc: loaded.doc });
  const edited = st.apply(st.tr.insertText('X', loaded.doc.child(0).nodeSize + 1)).doc; // edit block 1
  // head in block 2 ("Third"): block 2 is untouched, its slice is the original text
  let p2 = 0;
  for (let i = 0; i < 2; i++) p2 += edited.child(i).nodeSize;
  const res = serializeDoc(edited, { sources: loaded.sources, head: p2 + 1 + 2 });
  assert.equal(res.html.slice(res.headOffset!, res.headOffset! + 3), 'ird');
});
