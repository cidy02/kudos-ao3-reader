// editor-core public API (part 1): load, serialize, loss report, caret maps, the AO3 cleaning port.
import type { Node as PMNode } from 'prosemirror-model';
import { load } from './load.ts';
import type { LoadResult, LossReport } from './load.ts';
import { serializeDoc } from './serialize.ts';
import type { SerializeResult } from './serialize.ts';
import type { Variant } from './sanitize.ts';

export { schema, SCHEMA_VERSION, GLOBAL_ATTRS, MARK_TAGS, TOOLBAR_TAG } from './schema.ts';
export { load, parse, parseCleaned } from './load.ts';
export type { LoadOptions, LoadResult, LossReport } from './load.ts';
export { serialize, serializeDoc, serializeBlock } from './serialize.ts';
export type { SerializeOptions, SerializeResult, SourceInfo, BlockSource } from './serialize.ts';
export { sanitizeValue, fixBadCharacters, paragraphStage } from './clean.ts';
export { ParseLimitError } from './html5.ts';
export { SanitizerFailure } from './sanitize.ts';
export type { Variant } from './sanitize.ts';

/** Field limits (spec 3.3, 6.6), in the units AO3 counts them. */
export const FIELD_LIMITS: Record<Variant, number> = { content: 510_000, notes: 5_000, summary: 1_250 };

/**
 * The `snapshot` of the bridge (spec 7.2, 7.4). If `doc` is the document that was loaded (no edit), the original text
 * comes back byte for byte (R1) and the head is mapped back through the load's source map. Otherwise the document is
 * serialized, untouched blocks from their source slices (R2) and the head from the serializer.
 */
export function snapshot(loaded: LoadResult, doc: PMNode, opts: { head?: number } = {}): SerializeResult {
  if (doc === loaded.doc || doc.eq(loaded.doc)) {
    return { html: loaded.sources.original, headOffset: opts.head === undefined ? null : loaded.sources.offsetForPos(opts.head) };
  }
  return serializeDoc(doc, { sources: loaded.sources, head: opts.head });
}
export const snapshotHtml = (loaded: LoadResult, doc: PMNode): string => snapshot(loaded, doc).html;

/** `activate`: HTML-mode caret offset (UTF-16) to a document position (spec 7.5). */
export const activate = (loaded: LoadResult, offset: number): { pos: number; caretFound: boolean } => loaded.sources.activate(offset);

/** `lint`: parse only, report what AO3 would drop (spec 7.2). */
export const lint = (html: string, variant: Variant): LossReport => load(html, variant).loss;
