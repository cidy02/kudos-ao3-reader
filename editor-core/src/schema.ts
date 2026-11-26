// The ProseMirror schema for AO3 fields (spec 6.3 to 6.5). Same schema for every field variant: the variants differ
// in what the cleaner lets through (class, embeds), not in the document model.
import { Schema } from 'prosemirror-model';
import type { MarkSpec, NodeSpec } from 'prosemirror-model';

/** "G": attributes every element may carry (spec 6.3). `class` is dropped by the cleaner in the summary variant. */
export const GLOBAL_ATTRS = ['align', 'dir', 'lang', 'title', 'class'] as const;
const g = () => Object.fromEntries(GLOBAL_ATTRS.map((a) => [a, { default: null }]));

/** Own attributes per node or mark type, in AO3's order (spec 3.2, S4). */
export const OWN_ATTR_ORDER: Record<string, string[]> = {
  link: ['href', 'name'], phrase: ['cite'], blockquote: ['cite'], bullet_list: ['type'], ordered_list: ['start', 'type'],
  horizontal_rule: ['align', 'width'], image: ['align', 'alt', 'border', 'height', 'src', 'width'], details: ['open'],
};

export const MARK_TAGS: Record<string, string[]> = {
  link: ['a'], span: ['span'], phrase: ['abbr', 'acronym', 'dfn', 'cite', 'q'], strong: ['strong', 'b'], em: ['em', 'i'],
  underline: ['u'], strike: ['strike', 's', 'del'], ins: ['ins'], size: ['big', 'small'], script: ['sup', 'sub'],
  code: ['code', 'kbd', 'samp', 'var', 'tt'],
};
/** What the toolbar creates (S12). */
export const TOOLBAR_TAG: Record<string, string> = { strong: 'strong', em: 'em', underline: 'u', strike: 'strike', size: 'small', code: 'code' };

const markSpec = (type: string, extra: Record<string, { default: unknown }> = {}): MarkSpec => ({
  attrs: { tag: { default: MARK_TAGS[type]![0] }, ...extra, ...g() },
  inclusive: type !== 'link',
  excludes: type === 'span' ? '' : undefined, // spans with different attributes may nest
  spanning: true,
});

const nodes: Record<string, NodeSpec> = {
  doc: { content: 'block+' },
  paragraph: { group: 'block', content: 'inline*', attrs: { implicit: { default: false }, ...g() } },
  heading: { group: 'block', content: 'inline*', attrs: { level: { default: 3 }, ...g() }, defining: true },
  blockquote: { group: 'block', content: 'block+', attrs: { cite: { default: null }, ...g() }, defining: true },
  bullet_list: { group: 'block', content: 'list_item+', attrs: { type: { default: null }, ...g() } },
  ordered_list: { group: 'block', content: 'list_item+', attrs: { start: { default: null }, type: { default: null }, ...g() } },
  list_item: { content: 'paragraph block*', attrs: g(), defining: true },
  horizontal_rule: { group: 'block', atom: true, attrs: { width: { default: null }, ...g() }, selectable: true },
  details: { group: 'block', content: 'summary? block*', attrs: { open: { default: false }, ...g() }, defining: true },
  summary: { content: 'inline*', attrs: g() },
  container: { group: 'block', content: 'block+', attrs: { tag: { default: 'div' }, ...g() }, defining: true },
  image: { group: 'inline', inline: true, atom: true, attrs: { src: { default: null }, alt: { default: null }, width: { default: null }, height: { default: null }, border: { default: null }, ...g() } },
  hard_break: { group: 'inline', inline: true, selectable: false },
  raw_block: { group: 'block', atom: true, attrs: { source: { default: '' } }, selectable: true },
  raw_inline: { group: 'inline', inline: true, atom: true, attrs: { source: { default: '' } }, selectable: true },
  text: { group: 'inline' },
};

const marks: Record<string, MarkSpec> = {
  link: markSpec('link', { href: { default: null }, name: { default: null } }),
  span: markSpec('span'),
  phrase: markSpec('phrase', { cite: { default: null } }),
  strong: markSpec('strong'),
  em: markSpec('em'),
  underline: markSpec('underline'),
  strike: markSpec('strike'),
  ins: markSpec('ins'),
  size: markSpec('size'),
  script: markSpec('script'),
  code: markSpec('code'),
};

/** Bumped whenever the document model changes in a way that invalidates stored ProseMirror JSON (spec I7). */
export const SCHEMA_VERSION = 1;

export const schema = new Schema({ nodes, marks });
