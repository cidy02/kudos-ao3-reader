import { writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { buildCorpus, here } from './corpus.ts';

const root = resolve(here, '../../..');
const corpus = buildCorpus(root);
writeFileSync(join(here, 'corpus.json'), JSON.stringify(corpus, null, 1) + '\n');
console.log(`wrote ${corpus.cases.length} corpus cases`);
