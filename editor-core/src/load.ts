// The loading pipeline (spec 6.1): clean (AO3 port) -> parse5 -> build. Also produces the loss report (6.9).
import type { Node as PMNode } from 'prosemirror-model';
import { buildDoc } from './build.ts';
import type { BuildReport } from './build.ts';
import { sanitizeValue } from './clean.ts';
import { parseBody } from './html5.ts';
import { newReport } from './sanitize.ts';
import type { Variant } from './sanitize.ts';
import { Sources } from './sources.ts';

export type LossReport = {
  dropped: { elements: Record<string, number>; attributes: Record<string, number> };
  unwrapped: Record<string, number>;
  normalized: number;
  preserved: number;
};

export type LoadOptions = { appUrl?: string };
export type LoadResult = {
  doc: PMNode;
  loss: LossReport;
  sources: Sources;
  /** What AO3's pipeline makes of the input (the string the document was built from). */
  cleaned: string;
  timing: { cleanMs: number; buildMs: number };
};

export function load(html: string, variant: Variant, opts: LoadOptions = {}): LoadResult {
  const report = newReport();
  const t0 = performance.now();
  const cleaned = sanitizeValue(variant, html, { ...opts, report });
  const t1 = performance.now();
  const rep: BuildReport = { unwrapped: {}, normalized: 0, preserved: 0 };
  const doc = buildDoc(parseBody(cleaned, { locations: true }), cleaned, rep);
  const t2 = performance.now();
  const loss: LossReport = {
    dropped: { elements: report.elements, attributes: report.attributes },
    unwrapped: rep.unwrapped,
    normalized: report.normalized + rep.normalized,
    preserved: rep.preserved,
  };
  return { doc, loss, sources: new Sources(html, variant, doc, opts), cleaned, timing: { cleanMs: t1 - t0, buildMs: t2 - t1 } };
}

/** `parse` of the spec's S14/S15 statements: the document for an HTML string. */
export const parse = (html: string, variant: Variant, opts?: LoadOptions): PMNode => load(html, variant, opts).doc;

/** Builds a document from HTML that is already clean (no AO3 cleaning pass): the "parse" of spec S15. */
export function parseCleaned(cleaned: string): PMNode {
  return buildDoc(parseBody(cleaned, { locations: true }), cleaned, { unwrapped: {}, normalized: 0, preserved: 0 });
}
