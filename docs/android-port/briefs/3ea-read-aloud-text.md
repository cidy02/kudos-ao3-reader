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

## Left (a `ponytail:` note in the code)

A session still ends after 80,000 characters (about 14,000 words, an hour and a half).
iOS reads on chapter by chapter. Worth doing if long listening matters.

## Display & Themes, lower half, beside the iPhone's

- iOS's Read Aloud section has Engine, Read author's notes, Voice, Pronunciations and
  Developer Settings above Speed and Pitch; Android's has Speed, Pitch and the voice pack.
  Decided in 3ak (2026-10-05): Android has nothing behind them. With the device's voice
  (3dm), "Read author's notes" could now be built on this filter (iOS skips a note's
  label and the quotation after it); Pronunciations has no Android table at all.
- Android ends the sheet with a Font list; iOS keeps Font under Customize Theme… (owner
  question 29).
- The sliders differ (Android's stepped). The reader's controls: question 12.
