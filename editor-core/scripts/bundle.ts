// `npm run bundle`: the page the apps load. Builds editor-core/dist/ (editor.html, editor.css, editor.js and the
// licence notices of what the JS contains) with esbuild, deterministically, and copies it into the Apple app's
// resources. The bundle version is the package version plus a hash of the JS, so the same sources give the same bytes.
import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const appResources = resolve(root, '../kudos-ao3-reader/Resources/EditorCore');
const FILES = ['editor.html', 'editor.css', 'editor.js', 'THIRD-PARTY-NOTICES.txt'];
const PLACEHOLDER = '__KUDOS_BUNDLE_VERSION_PLACEHOLDER__';

const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')) as { version: string };

const result = await build({
  absWorkingDir: root,
  entryPoints: ['src/bridge/main.ts'],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari17', 'chrome120'], // iOS 26 runs Safari 26; Android System WebView tracks Chrome
  minify: true,
  legalComments: 'none', // the notices file carries every licence instead
  charset: 'utf8',
  sourcemap: false,
  write: false,
  metafile: true,
  define: { __BUNDLE_VERSION__: JSON.stringify(PLACEHOLDER) },
  logLevel: 'warning',
});

let js = result.outputFiles[0]!.text;
const hash = createHash('sha256').update(js).digest('hex').slice(0, 12);
const bundleVersion = `${pkg.version}+${hash}`;
if (!js.includes(PLACEHOLDER)) throw new Error('bundle version placeholder missing');
js = js.replaceAll(PLACEHOLDER, bundleVersion);

// Licence notices for every package bundled into editor.js.
const packages = new Set<string>();
for (const input of Object.keys(result.metafile.inputs)) {
  const m = /node_modules\/((?:@[^/]+\/)?[^/]+)\//.exec(input);
  if (m) packages.add(m[1]!);
}
const notices: string[] = [
  `editor.js ${bundleVersion} bundles editor-core (AGPL-3.0-only, part of Kudos) and the packages below.`,
  `editor-core's port of otwarchive's cleaning code: see editor-core/NOTICE in the Kudos repository.`,
];
for (const name of [...packages].sort()) {
  const dir = join(root, 'node_modules', name);
  const meta = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')) as { version: string; license?: string };
  const licenceFile = readdirSync(dir).find((f) => /^licen[cs]e/i.test(f));
  notices.push('', '='.repeat(78), `${name} ${meta.version} (${meta.license ?? 'see licence'})`, '='.repeat(78));
  notices.push(licenceFile ? readFileSync(join(dir, licenceFile), 'utf8').trim() : `No licence file shipped; package.json says ${meta.license}.`);
}

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
writeFileSync(join(dist, 'editor.js'), js);
writeFileSync(join(dist, 'THIRD-PARTY-NOTICES.txt'), `${notices.join('\n')}\n`);
copyFileSync(join(root, 'page/editor.html'), join(dist, 'editor.html'));
copyFileSync(join(root, 'page/editor.css'), join(dist, 'editor.css'));

if (!process.argv.includes('--no-copy')) {
  mkdirSync(appResources, { recursive: true });
  for (const f of FILES) copyFileSync(join(dist, f), join(appResources, f));
  for (const f of readdirSync(appResources)) if (!FILES.includes(f)) rmSync(join(appResources, f));
}

const size = (f: string) => readFileSync(join(dist, f)).length;
const gz = (await import('node:zlib')).gzipSync(readFileSync(join(dist, 'editor.js')), { level: 9 }).length;
console.log(`editor-core bundle ${bundleVersion}: editor.js ${size('editor.js')} B (${gz} B gzip), editor.css ${size('editor.css')} B, editor.html ${size('editor.html')} B; ${packages.size} packages`);
if (existsSync(appResources) && !process.argv.includes('--no-copy')) console.log(`copied to ${appResources}`);
