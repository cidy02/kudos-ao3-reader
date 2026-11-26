// Ruby string semantics that the AO3 code relies on and that differ from JavaScript's.

/** Ruby's String#strip family: NUL, tab, LF, VT, FF, CR, space (ASCII only, no Unicode spaces). */
const STRIP_CLASS = '\\0\\t\\n\\v\\f\\r ';
const LSTRIP = new RegExp(`^[${STRIP_CLASS}]+`);
const RSTRIP = new RegExp(`[${STRIP_CLASS}]+$`);
export const lstrip = (s: string): string => s.replace(LSTRIP, '');
export const rstrip = (s: string): string => s.replace(RSTRIP, '');
export const strip = (s: string): string => rstrip(lstrip(s));

/** POSIX `[[:space:]]` on a UTF-8 string (Unicode White_Space). JavaScript's \s differs (it has U+FEFF, lacks U+0085). */
export const POSIX_SPACE = '\\t-\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000';
const BLANK = new RegExp(`^[${POSIX_SPACE}]*$`);
/** ActiveSupport's String#blank?. */
export const isBlank = (s: string): boolean => BLANK.test(s);

/** Ruby's `\s` (no /u): ASCII whitespace only. */
export const RB_S = '[ \\t\\r\\n\\f\\v]';

/** Drop lone surrogates: the closest JavaScript analogue of "get rid of invalid characters" for UTF-8. */
export const dropInvalidUtf16 = (s: string): string =>
  s.replace(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g, '');
