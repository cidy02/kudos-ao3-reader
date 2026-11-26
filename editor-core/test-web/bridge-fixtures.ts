// The bridge fixtures both sides test against (spec 7.2): a scripted session through the real page code, recording
// every call's arguments and result and every event, plus one example of every command. `node
// test-web/bridge-fixtures.ts` rewrites test/bridge-fixtures/bridge.json; bridge-fixtures.test.ts fails if the page
// no longer produces exactly that file, and KudosTests/RichEditorBridgeFixtureTests.swift decodes it natively.
import './setup.ts';
import { writeFileSync } from 'node:fs';
import { harness } from './dom.ts';
import type { Harness } from './dom.ts';

export type Exchange = { name: string; args: unknown; result?: unknown; error?: unknown };
export type Fixtures = { bridgeVersion: number; calls: Exchange[]; events: unknown[]; commands: { id: string; name: string; attrs: Record<string, unknown> }[] };

const THEME = { background: '#1C1C1E', text: '#F2F2F7', accent: '#E0565F', link: '#64A8FF', fontFamily: "'New York', ui-serif, Georgia, serif", fontSizePx: 17, lineHeight: 1.62 };
const APPEARANCE = { fontFamily: "'New York', ui-serif, Georgia, serif", fontSizePx: 19, lineHeight: 1.62, contentSizeCategory: 'UICTContentSizeCategoryXL', isAccessibilityCategory: false, colorScheme: 'dark', increaseContrast: true, boldText: false };
const SOURCE = '<p>One <em>two</em> three.</p>\n<p>Four</p>';

/** Every command the native side sends, keyed the way the Swift test names its FormatCommand values. */
export const COMMANDS: Fixtures['commands'] = [
  ...['bold', 'italic', 'underline', 'strikethrough', 'superscript', 'subscript', 'smaller', 'code'].map((mark) => ({ id: `toggleMark.${mark}`, name: 'toggleMark', attrs: { mark } })),
  ...['body', 'heading', 'subheading', 'centred', 'quote', 'bulletedList', 'numberedList', 'foldOut'].map((block) => ({ id: `setBlock.${block}`, name: 'setBlock', attrs: { block } })),
  ...['left', 'centre', 'right', 'justify'].map((alignment) => ({ id: `setAlignment.${alignment}`, name: 'setAlignment', attrs: { alignment } })),
  ...['leftToRight', 'rightToLeft'].map((direction) => ({ id: `setDirection.${direction}`, name: 'setDirection', attrs: { direction } })),
  { id: 'setLink', name: 'setLink', attrs: { url: 'https://example.com/' } },
  { id: 'unlink', name: 'unlink', attrs: {} },
  { id: 'insertImage', name: 'insertImage', attrs: { address: 'https://example.com/a.png', description: 'A cat', width: 200, height: 100 } },
  { id: 'insertImage.noSize', name: 'insertImage', attrs: { address: 'https://example.com/a.png', description: '' } },
  ...['asterism', 'asterisks', 'line'].map((style) => ({ id: `insertSceneBreak.${style}`, name: 'insertSceneBreak', attrs: { style } })),
  { id: 'insertFootnote', name: 'insertFootnote', attrs: {} },
  { id: 'undo', name: 'undo', attrs: {} },
  { id: 'redo', name: 'redo', attrs: {} },
  { id: 'clearFormatting', name: 'clearFormatting', attrs: {} },
  { id: 'host.moveCaret.left', name: 'moveCaret', attrs: { by: -1 } },
  { id: 'host.moveCaret.right', name: 'moveCaret', attrs: { by: 1 } },
  { id: 'host.insertEmDash', name: 'insertText', attrs: { text: '—' } },
  { id: 'host.insertQuotationMarks', name: 'insertQuotes', attrs: { open: '“', close: '”' } },
  { id: 'tag.lineBreak', name: 'insertLineBreak', attrs: {} },
];

/** Timings vary run to run; everything else is deterministic. */
const normalize = (v: unknown): unknown => JSON.parse(JSON.stringify(v, (k, x) => (k === 'parseMs' || k === 'buildMs' || k === 'renderMs' ? 0 : x)));

export async function record(): Promise<Fixtures> {
  const h: Harness = harness();
  const calls: Exchange[] = [];
  const call = async (name: string, args: unknown) => {
    try {
      const result = await h.call(name, args);
      calls.push({ name, args, result: normalize(result) });
      return result;
    } catch (error) {
      calls.push({ name, args, error });
      return null;
    }
  };
  h.events.length = 0;
  await call('configure', { bridgeVersion: 1, schemaVersion: 1, variant: 'content', theme: THEME, locale: 'en_GB' });
  await call('setAppearance', APPEARANCE);
  await call('load', { html: SOURCE, revision: 4 });
  await call('setMirror', { enabled: true });
  h.clock.advance(10);
  await call('activate', { caret: SOURCE.indexOf('three'), focus: true });
  h.clock.advance(400);
  await call('command', { name: 'toggleMark', attrs: { mark: 'bold' } });
  await call('command', { name: 'insertText', attrs: { text: 'very ' } });
  h.clock.advance(400);
  await call('command', { name: 'paste', attrs: { html: '<p><font color="red">Hi</font> there</p>' } });
  h.clock.advance(400);
  await call('freeze', {});
  const snap = (await call('snapshot', { caret: true })) as { html: string } | null;
  await call('verifySwitch', { direction: 'richToSource', html: snap?.html ?? '' });
  await call('lint', { html: '<p style="color:red"><font>x</font></p>' });
  await call('setTheme', THEME);
  await call('setMirror', { enabled: false });
  await call('nope', {});
  await call('load', { html: 42, revision: 1 });
  await call('dispose', {});
  h.clock.advance(1000);
  return { bridgeVersion: 1, calls, events: h.events.map(normalize), commands: COMMANDS };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const out = new URL('../test/bridge-fixtures/bridge.json', import.meta.url);
  writeFileSync(out, `${JSON.stringify(await record(), null, 2)}\n`);
  console.log(`wrote ${out.pathname}`);
}
