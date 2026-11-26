import { test } from 'node:test';
import assert from 'node:assert/strict';
import { measure } from './perf.ts';
import { makeFixture } from './fixture.ts';

// Regression guards, not device budgets (spec 6.10): generous multiples of what a laptop measures (PERF.md).
test('the fixture is exactly 510,000 characters', () => {
  assert.equal(makeFixture('html').length, 510_000);
  assert.equal(makeFixture('plain').length, 510_000);
});

test('510,000-character parse and serialize stay within the regression guard', () => {
  for (const kind of ['html', 'plain'] as const) {
    const { timings } = measure(kind);
    const by = (p: string) => timings.find((t) => t.name.startsWith(p))!.ms;
    assert.ok(by('load') < 15_000, `${kind} load ${by('load')} ms`);
    assert.ok(by('serialize whole') < 3_000, `${kind} serialize ${by('serialize whole')} ms`);
    assert.ok(by('serialize after one edit') < 15_000, `${kind} edit serialize ${by('serialize after one edit')} ms`);
  }
});
