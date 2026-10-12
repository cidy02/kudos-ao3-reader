# 3cu: what survives the app being killed while writing (Android)

Done 2026-10-12 by Claude, alone. Gate 2,624. Pictures: `shots/3cu/`. Follows 3ct.

## What the design says, and what was seen

`docs/WRITING_EDITOR_ARCHITECTURE.md` §8 covers both apps: a form's **long text** (work
text, summary, notes, end notes) is checkpointed to a recovery copy on the device, and the
copy is offered when that field's editor is opened again. The form's **short fields**
(title, rating, tags, switches) are kept in memory only, on both apps.

Seen on the emulator, through a real kill (`am kill` with the app in the background):

- Work text typed into a draft, Home, kill, back: the app returns to the draft's form.
  Opening Work text asks "Recover unfinished text?" and shows what was typed; "Restore
  local copy" puts it back. **The design's promise holds on Android.** It had not been
  taken through a kill before.
- A title typed into the form, Home, kill, back: the title is as AO3 has it. **As
  designed, and the same on iOS.** Not changed: keeping the short fields would be new
  behaviour on Android only, and laying saved fields over a form read again from AO3
  needs a rule for when AO3's copy has changed. Owner question 26.

## Changed

- **The drafts note carries its second sentence**, as iOS: "Recovery copies stay on this
  device and aren't deleted with it." It was held back (and pinned absent by a test)
  until Android kept recovery copies. It does, and deleting a draft does not touch them.

## Not checked

- The summary and notes fields, the chapter form and the series form through a kill (they
  use the same editor and the same store).
- A kill while the editor is open and the last edit is under 1.5 s old: the design
  checkpoints when the app goes to the background, which is what this pass went through.
