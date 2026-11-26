// The look the native side asks for (N5): colours, the system font, Dynamic Type size and line height arrive as JSON
// and become CSS variables on the root. Values are checked first, so a theme can't smuggle in `url(...)` or a rule.
export type Theme = {
  background: string;
  text: string;
  accent: string;
  link: string;
  fontFamily: string;
  fontSizePx: number;
  lineHeight: number;
  /** Optional: 'light' or 'dark' (native caret, selection and spelling colours follow it). */
  colorScheme?: string;
  /** Optional: a secondary text colour for chips and placeholders. */
  secondary?: string;
  /** Optional: Bold Text is on. */
  boldText?: boolean;
};

const COLOR = /^(?:#[0-9a-fA-F]{3,8}|(?:rgb|rgba|hsl|hsla)\([0-9.,%\s/+-]{1,60}\)|color\((?:display-p3|srgb) [0-9.\s/%-]{1,60}\)|[a-zA-Z]{3,20})$/;
const FONT = /^[A-Za-z0-9 ,'"_-]{1,200}$/;

export function themeVariables(t: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  const color = (key: string, name: string) => {
    const v = t[key];
    if (v === undefined) return;
    if (typeof v !== 'string' || !COLOR.test(v.trim())) throw { code: 'bad-args', message: `theme.${key} is not a colour` };
    out[name] = v.trim();
  };
  color('background', '--kd-bg');
  color('text', '--kd-text');
  color('accent', '--kd-accent');
  color('link', '--kd-link');
  color('secondary', '--kd-secondary');
  if (t.fontFamily !== undefined) {
    if (typeof t.fontFamily !== 'string' || !FONT.test(t.fontFamily)) throw { code: 'bad-args', message: 'theme.fontFamily is not a font list' };
    out['--kd-font'] = t.fontFamily;
  }
  if (t.fontSizePx !== undefined) {
    if (typeof t.fontSizePx !== 'number' || !Number.isFinite(t.fontSizePx)) throw { code: 'bad-args', message: 'theme.fontSizePx is not a number' };
    out['--kd-size'] = `${Math.min(Math.max(t.fontSizePx, 8), 128)}px`; // AX5 body text is about 53 pt
  }
  if (t.lineHeight !== undefined) {
    if (typeof t.lineHeight !== 'number' || !Number.isFinite(t.lineHeight)) throw { code: 'bad-args', message: 'theme.lineHeight is not a number' };
    out['--kd-line'] = String(Math.min(Math.max(t.lineHeight, 1), 3));
  }
  if (t.boldText !== undefined) out['--kd-weight'] = t.boldText ? '600' : '400';
  if (t.colorScheme !== undefined) {
    if (t.colorScheme !== 'light' && t.colorScheme !== 'dark') throw { code: 'bad-args', message: 'theme.colorScheme is light or dark' };
    out['color-scheme'] = t.colorScheme;
  }
  return out;
}

export function applyTheme(root: HTMLElement, t: Record<string, unknown>): void {
  const vars = themeVariables(t);
  for (const [k, v] of Object.entries(vars)) {
    if (k === 'color-scheme') root.style.colorScheme = v;
    else root.style.setProperty(k, v);
  }
}

/**
 * The native appearance (N5): `{fontFamily, fontSizePx, lineHeight, contentSizeCategory, isAccessibilityCategory,
 * colorScheme, increaseContrast, boldText}`, pushed whenever Dynamic Type, Dark Mode, Increase Contrast or Bold Text
 * changes. Type goes to the same variables as the theme; the rest become root attributes the stylesheet reads.
 */
export function applyAppearance(root: HTMLElement, a: Record<string, unknown>): void {
  const { fontFamily, fontSizePx, lineHeight, boldText, colorScheme } = a;
  applyTheme(root, { fontFamily, fontSizePx, lineHeight, boldText, colorScheme });
  const flag = (k: string) => {
    if (a[k] !== undefined && typeof a[k] !== 'boolean') throw { code: 'bad-args', message: `${k} must be true or false` };
    return a[k] === true;
  };
  root.toggleAttribute('data-increase-contrast', flag('increaseContrast'));
  root.toggleAttribute('data-accessibility-size', flag('isAccessibilityCategory'));
  if (typeof a.contentSizeCategory === 'string' && /^[A-Za-z]{1,80}$/.test(a.contentSizeCategory)) root.dataset.contentSize = a.contentSizeCategory;
}
