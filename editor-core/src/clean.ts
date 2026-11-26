// Derived from otwarchive (Organization for Transformative Works), GPL-2.0-or-later; see editor-core/NOTICE.
// HtmlCleaner#sanitize_value (452391b6) for the AO3 fields that allow HTML: content, notes/endnotes, summary.
import { childrenToHtml, parseIn } from './html5.ts';
import { addParagraphsToText } from './paragraph-maker.ts';
import { dropInvalidUtf16, isBlank, strip } from './ruby.ts';
import { DEFAULT_APP_URL, newReport, sanitizeClean } from './sanitize.ts';
import type { CleanOptions, Variant } from './sanitize.ts';

/** HtmlCleaner#fix_bad_characters */
export function fixBadCharacters(text: string): string {
  return dropInvalidUtf16(text).replaceAll('<3', '&lt;3').replace(/\r\n?/g, '\n').replaceAll('____spacer____', '');
}

/** The ParagraphMaker stage exactly as sanitize_value feeds it. Exposed for the stage goldens. */
export function paragraphStage(value: string): string {
  return addParagraphsToText(fixBadCharacters(strip(value)));
}

/**
 * HtmlCleaner#sanitize_value(field, value) for `content`, `notes`/`endnotes` and `summary`.
 * Throws where otwarchive's Ruby raises (ParseLimitError, SanitizerFailure).
 */
export function sanitizeValue(variant: Variant, value: string, opts: CleanOptions = {}): string {
  if (isBlank(value)) return '';
  const v = strip(value);
  const ctx = { appUrl: opts.appUrl ?? DEFAULT_APP_URL, report: opts.report };
  const cleaned = sanitizeClean(addParagraphsToText(fixBadCharacters(v)), variant, ctx);
  // doc.fragment(cleaned).to_html, then "&nbsp;" back to U+00A0 (otwarchive's temporary hack)
  return childrenToHtml(parseIn('body', cleaned)).replaceAll('&nbsp;', '\u00a0');
}

export { newReport };
