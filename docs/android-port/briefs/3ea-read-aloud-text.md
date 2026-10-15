# 3ea: what Read Aloud says (Android), and the lower half of Display & Themes

Done 2026-10-14 by Claude, alone. Gate 2,655 (two new tests). Pictures: `shots/3ea/`.

## Fixed: Read Aloud read AO3's scaffolding and spelt out links

Android took the text from the reading position on as one run (`content.text()`), squeezed
every line break out of it and cut it into 350-character pieces. So paragraphs ran into each
other, AO3's own labels ("Chapter Notes", "Summary", "End Notes") and its closing plug
("Please drop by the Archive and comment…") were read out, and a link was spelt out letter
by letter. iOS drops those (`KokoroBoilerplateFilter`, built from 19 AO3 exports).

Now (`ReaderContentText.speakableParagraphs`): each paragraph is its own stretch; a
paragraph that is nothing but one of iOS's labels, or the plug, is dropped (a note that
merely starts with one is read); a link is said as its site ("archiveofourown.org.").
`ReaderContentTextTest` has both. Seen on the emulator: Read Aloud still starts.

## The length limit (3ed, the same evening)

A session ended after 80,000 characters (about 14,000 words, an hour and a half), though
`content.text()` had already read the whole rest of the work in, so the cap saved nothing.
It is gone: Read Aloud runs to the end of the work, as iOS's reads on. The `ponytail:` note
left in the code: the rest of the work is read in before the first word, so a very long
work may be slow to start; walk `content.iterator()` lazily if that shows. Gate 2,658;
seen on the emulator that it still starts.

## Display & Themes, lower half, beside the iPhone's

- iOS's Read Aloud section has Engine, Read author's notes, Voice, Pronunciations and
  Developer Settings above Speed and Pitch; Android's has Speed, Pitch and the voice pack.
  Decided in 3ak (2026-10-05): Android has nothing behind them. With the device's voice
  (3dm), "Read author's notes" could now be built on this filter (iOS skips a note's
  label and the quotation after it); Pronunciations has no Android table at all.
- Android ends the sheet with a Font list; iOS keeps Font under Customize Theme… (owner
  question 29).
- The sliders differ (Android's stepped). The reader's controls: question 12.
