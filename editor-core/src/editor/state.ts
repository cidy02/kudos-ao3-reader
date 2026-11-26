// The FormatState report (576c's FormatState; the bridge's `toolbarState` event, spec 7.2).
import type { EditorState } from 'prosemirror-state';
import { redoDepth, undoDepth } from 'prosemirror-history';
import { alignmentOf, blockOf, directionOf, FORMAT_MARKS, linkOf, markActive } from './commands.ts';
import type { FormatAlignment, FormatBlock, FormatDirection, FormatMark } from './commands.ts';

export type FormatState = {
  marks: FormatMark[];
  block: FormatBlock;
  align: FormatAlignment;
  dir: FormatDirection;
  canUndo: boolean;
  canRedo: boolean;
  inLink: boolean;
  linkURL: string | null;
  /** Names of the steps undo and redo would take back (the system edit menu's titles, N6); null when none. */
  undoTitle?: string | null;
  redoTitle?: string | null;
};

export function formatState(state: EditorState): FormatState {
  const link = linkOf(state);
  return {
    marks: FORMAT_MARKS.filter((m) => markActive(state, m)),
    block: blockOf(state),
    align: alignmentOf(state),
    dir: directionOf(state),
    canUndo: undoDepth(state) > 0,
    canRedo: redoDepth(state) > 0,
    inLink: link !== null,
    linkURL: link ? String(link.attrs.href ?? '') || null : null,
  };
}
