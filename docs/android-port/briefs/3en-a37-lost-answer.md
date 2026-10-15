# 3en: a collection write whose answer was lost says it may have landed (A37 F10, Android)

Done 2026-10-15 by Claude. Gate 2,667.

When the connection dropped after a collection write had been sent (claiming an assignment,
reporting a default, a tag set's review, the collection forms: every write that reaches
`collectionWriteVerdict`, which runs only after a POST), the screen said "AO3 took too long
to answer. Try again." or "Couldn't reach AO3. Check your connection and try again.", and a
second tap sent the same write again. It now says "AO3 didn't answer, so the change may have
gone through. Check on AO3 before trying again." (`AO3CollectionFields.NO_ANSWER`). A failure
while preparing (the form read) is unchanged: nothing was sent, so "try again" is right.
iOS shows its generic failure here; this goes further than iOS on purpose (a repeat write).
`AO3TagSetWritesTest` expected the old wording for a dropped POST and now expects this.
