# 3em: Edit multiple works merges its tag changes into the one form it sends (A37 F5, Android)

Done 2026-10-15 by Claude. Gate 2,667.

Codex's A37 (3cc/3cd/3ce as landed, `audits/A37-result.md`) found twelve things; this is its
one P1. For each work, Edit multiple works read the Edit Tags form, applied the reader's
changes to that copy, then `editWorkTags` read the form again and copied **every** tag group
from the first copy over the second. A group edited elsewhere between the two reads
(Relationships, say) was written back with its older value though the reader never touched
it. Now each work's form is read once, the changes are merged into that form, and that form
is sent: one read per work instead of two, which is also one AO3 request fewer per work.
The single-work tag editor is unchanged in what it sends (the reader's whole form).

`WritingBulkEditTest.theOneReadSuppliesTheTokenAndTheTagsTheChangesMergeInto`; two other tests
there counted the second read and now count one.

**iOS has the same two reads** (`AO3WorkActions.swift` merges, then `editTags` loads again and
assigns the merged tags): T-408.

Left from A37: F1 to F4 (the page cache after own-work and series writes), F6, F7 (bulk form
groups and a partial run), F8, F9, F10 (assignments' lost answer says "Try again"), F11, F12.
