// The golden corpus (spec 6.10): synthetic cases for every rule in spec 3 and 6, realistic chapters, local fixtures,
// and a seeded fuzz set. `node test/golden/make-corpus.ts` writes corpus.json; the Ruby harness reads it.
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { parseFragment } from 'parse5';
import fc from 'fast-check';
import type { Node as PMNode } from 'prosemirror-model';
import { serialize } from '../../src/serialize.ts';
import { docArb } from '../arb.ts';

export type Case = { id: string; input: string };

const S = (id: string, input: string): Case => ({ id, input });

const synthetic: Case[] = [
  // 3.1 steps and fix_bad_characters
  S('empty', ''), S('blank-ascii', ' \n\t '), S('blank-nbsp', '\u00a0\u2003'), S('nul', '\0'), S('plain', 'Hello'),
  S('crlf', 'a\r\nb\r\n\r\nc\rd'), S('less-than-3', 'I <3 you <3'), S('spacer', 'a ____spacer____ b'), S('spacer-lt3', '<____spacer____3'),
  S('control-chars', 'a\u0001b\u0008c\u000bd\u007fe\u0085f\u009fg\ufdd0h\ufffei'), S('astral-nonchar', 'a\u{1fffe}b\u{10ffff}c'),
  S('leading-trailing-ws', '  \n  text  \n  '), S('nbsp-edges', '\u00a0text\u00a0'),
  S('amp', 'a & b &amp; c &lt; d &copy; e &notit; f &#65; &#x42; &bogus;'), S('lt-gt', 'a < b > c <b'), S('entity-nbsp', 'x&nbsp;y&nbsp;'),
  // 3.4 ParagraphMaker
  S('pm-two-newlines', 'Hello\n\nWorld'), S('pm-one-newline', 'Hello\nWorld'), S('pm-three-newlines', 'a\n\n\nb'), S('pm-many-newlines', 'a\n\n\n\n\n\nb'),
  S('pm-spaces-around-newlines', 'a  \n  \n  b'), S('pm-tab-newline', 'a\t\n\t\nb'), S('pm-unicode-space-newline', 'a\u2003\n\u2003\nb\u3000\n\u3000c'),
  S('pm-nel-newline', 'a\u0085\n\nb'), S('pm-nbsp-literal-newline', 'a\u00a0\n\u00a0\nb'), S('pm-br-br', 'a<br><br>b'), S('pm-br-br-br', 'a<br><br><br>b'),
  S('pm-br-4', 'a<br><br><br><br>b'), S('pm-br-newline-br', 'a<br>\n<br>b'), S('pm-br-single', 'a<br>b'), S('pm-leading-br', '<br><br>a'),
  S('pm-trailing-br', 'a<br><br>'), S('pm-block-newlines', '<p>a</p>\n\n<p>b</p>\n<p>c</p>'), S('pm-p-inner-newlines', '<p>a\n\nb\nc</p>'),
  S('pm-div-text', '<div>x\n\ny</div>'), S('pm-div-loose', '<div>a<b>b</b>c\n\nd</div>'), S('pm-blockquote', '<blockquote>a\n\nb</blockquote>'),
  S('pm-blockquote-inline', '<blockquote>one <i>two</i> three</blockquote>'), S('pm-center', '<center>a\n\nb</center>'),
  S('pm-details', '<details><summary>s</summary>a\n\nb</details>'), S('pm-details-open', '<details open><summary>s</summary>hidden</details>'),
  S('pm-heading-text', '<h1>a\n\nb</h1>'), S('pm-list', '<ul>\n<li>a\n\nb</li>\n<li>c</li>\n</ul>'), S('pm-ol', '<ol><li>x</li></ol>after'),
  S('pm-pre', '<pre>a\n\nb\n</pre>'), S('pm-pre-leading-newline', '<pre>\n\nx</pre>'), S('pm-table', '<table><tr><td>a\n\nb</td></tr></table>'),
  S('pm-inline-in-block-split', '<b>a<br><br>b</b>'), S('pm-nested-inline-split', '<i><b>a\n\nb</b></i> tail'), S('pm-span-split', '<span class="x">a\n\nb</span>'),
  S('pm-a-split', '<a href="http://x.org/">a\n\nb</a>'), S('pm-p-in-span', '<span>a<p>b</p>c</span>'), S('pm-block-in-inline', '<b>x<div>y</div>z</b>'),
  S('pm-hr-between', 'a\n<hr>\nb'), S('pm-hr-in-text', 'a<hr>b'), S('pm-img-wrap', 'text <img src="http://x.org/a.png"> more'),
  S('pm-empty-p', '<p></p><p>a</p><p></p>'), S('pm-space-p', '<p> </p>'), S('pm-nbsp-p', '<p>&nbsp;</p>'), S('pm-p-nested-real', '<p>a<p>b'),
  S('pm-comment', 'a<!-- c -->\n\nb'), S('pm-comment-between-blocks', '<p>a</p><!-- c --><p>b</p>'), S('pm-split-literal', 'a<split>b</split>c'),
  S('pm-split-long-literal', 'a<split long>b'), S('pm-myroot-close', 'a</myroot>b'), S('pm-textarea', 'a<textarea>x\n\ny</textarea>b'),
  S('pm-button', '<button>a\n\nb</button>'), S('pm-form', '<form>a\n\nb</form>c'), S('pm-script', 'a<script>x\n\ny</script>b'),
  S('pm-style', '<style>p{}</style>\n\nb'), S('pm-title', '<title>a\n\nb</title>'), S('pm-listing', '<listing>\n\nx\n\ny</listing>'),
  S('pm-section', '<section>a\n\nb</section>'), S('pm-article-nested', '<article><section>a</section></article>'), S('pm-dl', '<dl><dt>a</dt><dd>b\n\nc</dd></dl>'),
  S('pm-figure', '<figure><img src="http://x.org/a.png"><figcaption>c\n\nd</figcaption></figure>'), S('pm-address', '<address>a\n\nb</address>'),
  S('pm-ruby', '<ruby>漢<rt>kan</rt></ruby>\n\nx'), S('pm-newline-in-inline', 'a <b>b\nc</b> d'), S('pm-trailing-newlines', 'a\n\n\n'), S('pm-only-newlines-between', '<p>a</p>\n\n\n\n<p>b</p>'),
  // 3.2 allow-list: elements
  ...'a abbr acronym address b big blockquote br caption center cite code col colgroup details figcaption figure dd del dfn div dl dt em h1 h2 h3 h4 h5 h6 hr i img ins kbd li ol p pre q rp rt ruby s samp small span strike strong sub summary sup table tbody td tfoot th thead tr tt u ul var'.split(' ').map((t) => S(`el-${t}`, `<${t}>x</${t}>`)),
  ...'font marquee blink article aside footer header hgroup nav section main mark time u1 object param embed iframe video audio source track canvas svg math template noscript xmp plaintext noembed noframes applet frame frameset head body html base link meta title bdo bdi data dialog menu menuitem nobr wbr tt1 center2 label input select option optgroup textarea button fieldset legend form output progress meter map area picture slot'.split(' ').map((t) => S(`strip-${t}`, `a<${t}>inner <b>bold</b></${t}>z`)),
  S('strip-script-content', 'a<script>alert(1)</script>b'), S('strip-style-content', 'a<style>b{}</style>c'), S('strip-svg-content', 'a<svg><circle/><a>t</a></svg>b'),
  S('strip-math-content', 'a<math><mi>x</mi></math>b'), S('strip-iframe-content', 'a<iframe src="x">hi</iframe>b'), S('strip-noscript-b', 'a<noscript><b>n</b></noscript>b'),
  S('strip-whitespace-elements', 'a<section>b</section>c<nav></nav>d<header>e</header><footer>f</footer><aside>g</aside><hgroup>h</hgroup>'),
  // attributes
  S('attr-global', '<p align="center" dir="rtl" lang="en" title="t" id="i" style="color:red" onclick="x" data-a="1" class="c d">x</p>'),
  S('attr-a', '<a href="http://x.org/" name="n" target="_blank" rel="noopener" title="t" id="z">l</a>'), S('attr-a-order', '<a title="t" name="n" href="http://x.org/">l</a>'),
  S('attr-a-rel-existing', '<a rel="me" href="http://x.org/">l</a>'), S('attr-a-no-href', '<a>l</a>'), S('attr-a-name-space', '<a name="a b&quot;c">x</a>'),
  S('attr-blockquote', '<blockquote cite="http://x.org/q" lang="fr">x</blockquote>'), S('attr-q', '<q cite="javascript:x">x</q>'),
  S('attr-col', '<table><colgroup span="2" width="10"><col span="1" width="5" style="x"></colgroup></table>'),
  S('attr-details', '<details open="" title="t"><summary>s</summary>x</details>'), S('attr-details-open-val', '<details open="yes"><summary>s</summary>x</details>'),
  S('attr-hr', '<hr align="left" width="50%" size="3" noshade>'), S('attr-img', '<img align="left" alt="a&amp;b" border="1" height="2" src="http://x.org/i.png" width="3" title="t" loading="lazy">'),
  S('attr-ol', '<ol start="3" type="a" reversed><li>x</li></ol>'), S('attr-ul', '<ul type="disc"><li>x</li></ul>'),
  S('attr-table', '<table border="1" summary="s" width="100" cellpadding="3"><tr><td abbr="a" axis="b" colspan="2" height="3" rowspan="4" width="5" valign="top">x</td><th abbr="a" axis="b" colspan="2" height="3" rowspan="4" scope="col" width="5">y</th></tr></table>'),
  S('attr-dupe', '<p title="a" title="b">x</p>'), S('attr-uppercase', '<P ALIGN="CENTER" CLASS="Foo">x</P>'), S('attr-empty', '<p title="" align>x</p>'), S('attr-nbsp-value', '<p title="a&nbsp;b">x</p>'),
  S('attr-quote-escape', '<p title=\'a"b\'>x</p>'), S('attr-amp-value', '<p title="a&amp;b &lt; &gt;">x</p>'), S('attr-unquoted', '<p title=abc align=left>x</p>'),
  // protocols
  ...['http://x.org/', 'https://x.org/', 'ftp://x.org/', 'mailto:a@b.c', 'javascript:alert(1)', 'JaVaScRiPt:alert(1)', ' javascript:alert(1)', 'java\tscript:alert(1)', 'java&#10;script:alert(1)',
    '&#106;avascript:alert(1)', 'jav&#x61;script:alert(1)', 'data:text/html,x', 'vbscript:x', '/relative/path', 'relative', '#frag', '?q=1', '//x.org/p', 'http:x', 'tel:123', 'HTTP://X.ORG/', '  http://x.org/  ', 'http://x.org/a b', 'http://x.org/a"b', '', 'x:y:z', '&#58;x', 'a&#58;b', 'a&#x3a;b', 'a&#0058;b', 'a/b:c', '#a:b']
    .map((h, i) => S(`proto-a-${i}`, `<a href="${h}">l</a>`)),
  ...['http://x.org/a.png', 'https://x.org/a.png', 'ftp://x.org/a.png', 'data:image/png;base64,AAAA', 'javascript:x', '/a.png', 'a.png', '../a.png', './a/../b.png', '//cdn.x.org/a.png', '', '?x', '#y', '/a b.png', '/é.png', '/a%20b.png', '/a%zz.png', 'a.png?x=1#f', 'http://x.org:8080/a.png', 'http://[::1]/a.png', '  /a.png', 'HTTP://X.ORG/A.PNG', 'x:/a.png', '/a/b/../../../c.png', '/a;b=c/d.png', '/a|b.png', "/a'b.png", '/a(b).png', 'http://u:p@x.org/a.png', '/%E3%81%82.png', '/a<b.png', '/a\\b.png', 'http://x.org:80/a.png', 'https://x.org:443/a.png', 'http://x.org:/a.png', 'http://x.org:81/a.png', 'FTP://x.org:21/a.png']
    .map((h, i) => S(`proto-img-${i}`, `<img src="${h}" alt="x">`)),
  S('proto-cite', '<blockquote cite="/rel">a</blockquote><blockquote cite="ftp://x.org">b</blockquote><q cite="https://x.org">c</q>'),
  // 3.3 class filter and variants
  S('class-valid', '<p class="a bb a-b a_b A1">x</p>'), S('class-invalid', '<p class="1a a b-c $x a.b -a _a a">x</p>'), S('class-all-invalid', '<p class="1 2">x</p>'),
  S('class-empty', '<p class="">x</p>'), S('class-blank', '<p class="   ">x</p>'), S('class-ws', '<p class="a\tb\nc  d">x</p>'), S('class-unicode-space', '<p class="a\u00a0b">x</p>'),
  S('class-span', '<span class="workskin">x</span>'), S('class-div', '<div class="dialogue"><p class="speaker">x</p></div>'), S('class-no-element-allow', '<hr class="x">'),
  S('class-img', '<img src="http://x.org/a.png" class="pic 9">'),
  // embeds and media
  ...['https://www.youtube.com/embed/abc', 'http://www.youtube.com/embed/abc', '//www.youtube.com/embed/abc', 'https://www.youtube-nocookie.com/embed/abc', 'https://youtube.com/embed/abc', 'https://www.YouTube.com/embed/abc',
    'https://www.%79outube.com/embed/abc', 'https://player.vimeo.com/video/1', 'https://vimeo.com/1', 'https://w.soundcloud.com/player/?url=x', 'https://open.spotify.com/embed/track/1', 'https://archive.org/embed/x',
    'https://audio.com/embed/audio/1', 'https://podfic.com/x', 'https://www.criticalcommons.org/x', 'https://vidders.net/x', 'https://viddertube.com/x', 'https://player.bilibili.com/player.html?aid=1', 'https://www.4shared.com/web/embed/audio/file/1',
    'https://evil.com/youtube.com/embed/x', 'https://youtube.com.evil.com/embed/x', 'https://youtube.com@evil.com/embed/x', 'javascript:alert(1)', '', 'https://www.youtube.com:443/embed/x', 'https://www.youtube.com/embed/é', 'https://youtube.com/embed/a b',
    'https://youtube.com/../embed/x', 'https://youtube.com/embed/x?a=1&b=2#f', 'https://youtube.com:abc/embed/x', 'https://ｙｏｕｔｕｂｅ.com/embed/x', 'HTTPS://WWW.youtube.com/embed/abc', 'https://youtube.com\n/embed/x']
    .map((h, i) => S(`embed-iframe-${i}`, `<iframe src="${h}" width="560" height="315" frameborder="0" allowfullscreen onload="x" style="y"></iframe>`)),
  S('embed-allow-fullscreen', '<iframe src="https://www.youtube.com/embed/x" allow="accelerometer; fullscreen; autoplay"></iframe>'), S('embed-allow-none', '<iframe src="https://www.youtube.com/embed/x" allow="autoplay"></iframe>'),
  S('embed-allow-empty', '<iframe src="https://www.youtube.com/embed/x" allow=""></iframe>'), S('embed-iframe-text', '<iframe src="https://www.youtube.com/embed/x">hello <b>x</b></iframe>'),
  S('embed-iframe-class', '<iframe src="https://www.youtube.com/embed/x" class="a 1 b"></iframe>'), S('embed-iframe-no-src', '<iframe></iframe>'),
  S('embed-embed', '<embed src="http://www.youtube.com/v/x" type="application/x-shockwave-flash" width="1" height="2" allowfullscreen flashvars="a=http://x" wmode="opaque">'),
  S('embed-embed-soundcloud', '<embed src="http://w.soundcloud.com/x" flashvars="url=http%3A%2F%2Fx&amp;b=http://y" wmode="opaque">'), S('embed-embed-bad', '<embed src="http://evil.com/x.swf">'),
  S('embed-object', '<object width="1" height="2"><param name="movie" value="http://www.youtube.com/v/x"><embed src="http://www.youtube.com/v/x"></object>'), S('embed-object-bad', '<object><param name="movie" value="http://evil.com/x"></object>'),
  S('embed-in-p', '<p>before <iframe src="https://www.youtube.com/embed/x"></iframe> after</p>'), S('embed-in-summary', '<iframe src="https://www.youtube.com/embed/x"></iframe>'),
  S('media-audio', '<audio src="http://x.org/a.mp3" controls loop muted preload="none" class="a" autoplay onplay="x">fallback <b>b</b></audio>'), S('media-audio-source', '<audio><source src="http://x.org/a.mp3" type="audio/mpeg"><source src="javascript:x"></audio>'),
  S('media-video', '<video src="https://x.org/v.mp4" poster="http://x.org/p.png" width="1" height="2" playsinline autoplay crossorigin="use-credentials" preload="auto" style="x"><track src="http://x.org/t.vtt" kind="captions" srclang="en" label="E" default><source src="https://x.org/v.webm" type="video/webm"></video>'),
  S('media-video-nested', '<video><p>x</p><script>y</script><a href="javascript:z">l</a></video>'), S('media-bad-src', '<audio src="ftp://x.org/a.mp3"></audio>'), S('media-no-src', '<audio></audio><video></video>'),
  S('media-src-no-scheme', '<audio src="x.org/a.mp3"></audio>'), S('media-src-invalid', '<audio src="http://[bad"></audio>'), S('media-src-port', '<audio src="http://x.org:abc/a.mp3"></audio>'),
  S('media-source-orphan', '<source src="http://x.org/a.mp3"><track src="http://x.org/t.vtt">'), S('media-in-p', '<p>x <audio src="http://x.org/a.mp3"></audio> y</p>'),
  // comments, doctype, CDATA, odd markup
  S('comment', 'a<!-- hi -->b'), S('comment-only', '<!-- hi -->'), S('doctype', '<!DOCTYPE html>text'), S('cdata-html', 'a<![CDATA[x]]>b'), S('cdata-svg', '<svg><![CDATA[x]]></svg>'),
  S('processing', 'a<?php echo 1 ?>b'), S('unclosed-b', '<b>a\n\nb'), S('unclosed-p', '<p>a<p>b'), S('misnested', '<b><i>x</b></i>'), S('misnested-p', '<p><b>a</p><p>b</b></p>'),
  S('nested-a', '<a href="/x">a<a href="/y">b</a></a>'), S('stray-end', 'a</b></div></p>b'), S('table-foster', '<table>text<tr><td>a</td></tr></table>'), S('table-bare-tr', '<tr><td>a</td></tr>'),
  S('td-bare', '<td>a</td>'), S('li-bare', '<li>a</li><li>b</li>'), S('body-tag', '<body class="x">hi</body>'), S('html-tag', '<html><head><title>t</title></head><body>b</body></html>'),
  S('select-option', '<select><option>a</option><option>b</option></select>'), S('frameset', '<frameset><frame></frameset>'), S('entity-in-tag', '<b&amp;>x</b&amp;>'), S('tag-case', '<DIV><B>x</B></DIV>'),
  S('unicode', '星 &amp; light 日本語\n\nمرحبا\n\n😀'), S('rtl', '<p dir="rtl" lang="ar">مرحبا</p>'), S('emoji-attr', '<p title="😀">x</p>'), S('nul-in-attr', '<p title="a\0b">x</p>'),
  S('textarea-in-body', '<textarea>\nx</textarea>'), S('pre-first-newline', '<pre>\nabc</pre>'), S('pre-two-newlines', '<pre>\n\nabc</pre>'), S('listing', '<listing>\nabc</listing>'),
  S('xmp', '<xmp><b>x</b></xmp>'), S('plaintext', 'a<plaintext><b>x'), S('nested-deep-ok', '<div>'.repeat(50) + 'x' + '</div>'.repeat(50)),
  S('nested-399', '<div>'.repeat(398) + 'x'), S('nested-400', '<div>'.repeat(399) + 'x'), S('nested-401', '<div>'.repeat(400) + 'x'), S('nested-402', '<div>'.repeat(401) + 'x'),
  S('attrs-400', `<p ${Array.from({ length: 400 }, (_, i) => `title${i}=x`).join(' ')}>x</p>`), S('attrs-401', `<p ${Array.from({ length: 401 }, (_, i) => `title${i}=x`).join(' ')}>x</p>`),
  S('details-nested', '<details><summary>a</summary><details><summary>b</summary>c</details></details>'), S('details-no-summary', '<details>hidden</details>'), S('summary-orphan', '<summary>x</summary>'),
  S('span-nested-class', '<span class="a"><span class="b"><span>x</span></span></span>'), S('anchor-empty', '<a name="ch1"></a>text'), S('span-empty-class', '<span class="x"></span>'),
  S('mixed-marks', '<b><i><u><strike>x</strike></u></i></b> <strong>y</strong><em>z</em><s>s</s><del>d</del><ins>i</ins><sup>1</sup><sub>2</sub><small>s</small><big>b</big><code>c</code><kbd>k</kbd><samp>s</samp><var>v</var><tt>t</tt><cite>c</cite><abbr title="t">a</abbr><acronym>a</acronym><dfn>d</dfn><q>q</q>'),
  S('hr-forms', '<hr/><hr /><hr>'), S('br-forms', 'a<br/>b<br />c<BR>d'), S('self-closing-div', '<div/>x'), S('self-closing-p', '<p/>x'),
  S('whitespace-around-inline', '<p>a <b> b </b> c</p>'), S('nbsp-runs', '<p>a&nbsp;&nbsp;&nbsp;b</p>'), S('wide-spaces', '<p>a\u2003b\u3000c</p>'), S('tabs', '<p>a\tb</p>'),
];

function realistic(): Case[] {
  const para = (n: number) => `Paragraph ${n} of the chapter: the lantern swung on its hook while ${n} gulls argued over the quay, and nobody noticed the tide turning.`;
  const plain = Array.from({ length: 12 }, (_, i) => para(i + 1)).join('\n\n');
  const html = Array.from({ length: 12 }, (_, i) => `<p>${para(i + 1)}</p>`).join('\n');
  const mixed = [
    '<p><strong>Chapter 1</strong></p>', '<p align="center"><em>* * *</em></p>', `<p>${para(1)} <i>Italic</i> and <b>bold</b> and <u>underline</u> and <strike>gone</strike>.</p>`,
    '<blockquote><p>Quoted line one.</p><p>Quoted line two.</p></blockquote>', '<ul>\n<li>one</li>\n<li>two <a href="https://example.org/x">link</a></li>\n</ul>', '<ol start="3"><li>three</li><li>four</li></ol>',
    '<hr>', '<div class="letter"><p class="from">From: Mara</p><p>Dear Ines,</p><p>It rained.</p></div>', '<details><summary>Spoiler</summary><p>She was the thief all along.</p></details>',
    '<table border="1"><tr><th>Day</th><th>Light</th></tr><tr><td>Mon</td><td>dusk</td></tr></table>', '<pre>  ascii\n   art</pre>', '<h3>A heading</h3>', `<p>${para(2)}<br>second line<br>third line</p>`,
    '<p>&nbsp;</p>', '<p><span class="skin-glow">glowing</span> and <font color="red">red</font> text</p>', '<p><a name="ch1"></a>Anchor</p>', '<p>Smart “quotes”, an em—dash, an ellipsis…</p>', '<p>日本語のテキスト and العربية</p>',
    '<p><img src="https://example.org/a.png" alt="pic" width="10"></p>', '<iframe src="https://www.youtube.com/embed/abcdef" width="560" height="315" allowfullscreen></iframe>', '<audio controls src="https://example.org/a.mp3"></audio>',
  ].join('\n');
  const messy = 'Loose first line\nsecond line\n\n<i>Italic start</i> of a para\n\n\nAfter a gap<br><br>Then a br break<br><br><br>and a long one\n<p>A real paragraph</p>\nTrailing text\r\nwith CRLF.\n\n&amp; entities &nbsp; and <3 hearts';
  return [S('chapter-plain', plain), S('chapter-html', html), S('chapter-mixed', mixed), S('chapter-messy', messy), S('chapter-notes', '<p>Thanks to <a href="https://example.org/u/x">x</a> for the beta!</p>\n<p>Content notes: none.</p>'), S('summary-plain', 'A map for the tide, a promise for the night.\n\nSecond line of the summary.')];
}

/** Local fixtures: textareas of the AO3 edit forms, chapter bodies of the epubs, userstuff of the preview page. */
function fromFixtures(root: string): Case[] {
  const dir = join(root, 'KudosTests/Fixtures');
  const out: Case[] = [];
  const walk = (n: any, f: (e: any) => void) => { f(n); for (const c of n.childNodes ?? []) walk(c, f); if (n.content) walk(n.content, f); };
  const text = (n: any): string => (n.childNodes ?? []).map((c: any) => (c.nodeName === '#text' ? c.value : '')).join('');
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.html')).sort()) {
    const html = readFileSync(join(dir, f), 'utf8');
    const doc = parseFragment(html);
    let k = 0;
    walk(doc, (e) => {
      if (e.tagName === 'textarea' && text(e).trim()) out.push(S(`fixture-${f}-textarea-${k++}`, text(e)));
    });
  }
  for (const [file, id] of [['ao3_demo_work_preview.html', 'preview']] as const) {
    const doc = parseFragment(readFileSync(join(dir, file), 'utf8'));
    walk(doc, (e) => {
      if (e.tagName === 'div' && (e.attrs ?? []).some((a: any) => a.name === 'class' && a.value === 'userstuff')) {
        const inner = e.childNodes.map((c: any) => (c.nodeName === '#text' ? c.value : '')).join('');
        void inner;
        out.push(S(`fixture-${id}-userstuff`, serializeInner(e)));
      }
    });
  }
  for (const epub of ['demo_work.epub', 'sample.epub']) {
    for (const ch of ['ch1', 'ch2']) {
      try {
        const x = execFileSync('unzip', ['-p', join(dir, epub), `OEBPS/${ch}.xhtml`], { encoding: 'utf8' });
        const body = /<body[^>]*>([\s\S]*)<\/body>/.exec(x)?.[1];
        if (body?.trim()) out.push(S(`fixture-${epub}-${ch}`, body));
      } catch { /* missing member */ }
    }
  }
  return out;
}

import { serialize as p5serialize } from 'parse5';
function serializeInner(e: any): string { return p5serialize(e); }

/** Seeded fuzz: random mixtures of the pieces that exercise ParagraphMaker and the sanitizer. */
export function fuzz(seed: number, count: number): Case[] {
  let a = seed >>> 0;
  const rnd = () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const pick = <T,>(xs: T[]): T => xs[Math.floor(rnd() * xs.length)]!;
  const words = ['alpha', 'beta', 'gamma', '&amp;', '&nbsp;', '<3', '&lt;', 'x', 'é', '日本', '😀', '"q"', "it's"];
  const gaps = [' ', ' ', ' ', '\n', '\n\n', '\n\n\n', ' \n ', '\t', '\u00a0', '\u2003\n', '<br>', '<br><br>', '<br><br><br>', '\r\n'];
  const inline = ['b', 'i', 'u', 'strike', 'em', 'strong', 'span', 'a', 'sup', 'sub', 'small', 'code', 'font', 'abbr', 'q', 'big', 's', 'del', 'ins', 'tt'];
  const block = ['p', 'div', 'blockquote', 'center', 'h2', 'ul', 'ol', 'li', 'pre', 'details', 'summary', 'table', 'tr', 'td', 'section', 'dl', 'dd', 'figure', 'hr', 'article'];
  const attrs = ['', '', '', ' class="a b"', ' class="1x"', ' title="t"', ' style="x:y"', ' href="http://x.org/"', ' href="javascript:x"', ' align="center"', ' id="i"', ' open', ' src="/a.png"', ' name="n"', ' dir="rtl"'];
  const gen = (depth: number): string => {
    let s = '';
    const n = 1 + Math.floor(rnd() * 5);
    for (let i = 0; i < n; i++) {
      const r = rnd();
      if (r < 0.45 || depth > 3) s += pick(words) + pick(gaps) + (rnd() < 0.3 ? pick(words) : '');
      else if (r < 0.7) { const t = pick(inline); s += `<${t}${pick(attrs)}>${gen(depth + 1)}</${t}>`; }
      else if (r < 0.9) { const t = pick(block); s += t === 'hr' ? '<hr>' : `<${t}${pick(attrs)}>${gen(depth + 1)}${rnd() < 0.8 ? `</${t}>` : ''}`; }
      else if (r < 0.95) s += pick(['<img src="/a.png">', '<br>', '<!-- c -->', '</b>', '</p>', '<split>', '<iframe src="https://youtube.com/embed/x"></iframe>', '<script>x</script>', '<a name="n"></a>']);
      else s += pick(gaps);
    }
    return s;
  };
  return Array.from({ length: count }, (_, i) => S(`fuzz-${seed}-${i}`, gen(0)));
}

/** Serializations of generated documents: Ruby's verdict on S15 (the golden must parse back to the document). */
export const S15_SEED = 1576;
export const S15_COUNT = 300;
export function s15Documents(): PMNode[] { return fc.sample(docArb('content', { maxBlocks: 5 }), { seed: S15_SEED, numRuns: S15_COUNT }); }
const s15Cases = (): Case[] => s15Documents().map((d, i) => S(`s15-${i}`, serialize(d)));

export function buildCorpus(root: string): { cases: Case[] } {
  const cases = [...synthetic, ...realistic(), ...fromFixtures(root), ...fuzz(576, 1200), ...s15Cases()];
  const seen = new Set<string>();
  for (const c of cases) { if (seen.has(c.id)) throw new Error(`duplicate corpus id ${c.id}`); seen.add(c.id); }
  return { cases };
}

export const here = dirname(fileURLToPath(import.meta.url));
