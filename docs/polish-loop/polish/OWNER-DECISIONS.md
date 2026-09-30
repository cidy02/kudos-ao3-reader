# Owner decisions (collected during LOOP-v3; presented at the end)

1. **Word-count precision.** Word counts use two decimals ("18.02K words", owner call 2026-09-12); every other count uses one ("1.5K"). Options: keep; one decimal everywhere ("18K", "9K"). Recommendation: one decimal, for one count language.

2. **New queue sheet chrome.** 1j draws a round glass × on the left and an accent-filled ✓ on the right; the app uses text Cancel / Create so it matches New Collection and every other creation sheet (T-287). Options: keep text (one sheet convention); switch both sheets to 1j's circles. Recommendation: keep text.
3. **Queue tag model gaps (1bh).** The spec's tag manager shows per-tag authors, 9px colour dots and a collaborator "Remove from my view" — these need sharing and a tag colour the model does not have (a new SwiftData field). Options: leave out; add a tag colour field. Recommendation: leave out until sharing exists.

4. **Hide Mature on AO3 lists.** The mature gate covers saved Library works only. AO3 lists — Search, Browse, Bookmarks, History, Subscriptions — show adult works unblurred with Hide Mature on, including a private bookmark note under an adult work you have not saved (Grok L3-B5 #9). Options: keep (the gate is about your Library); extend the blur to adult remote rows on every AO3 list. Recommendation: extend it — the owner treats Hide Mature as a privacy promise, and a bookmark note is personal.

## 5. Subscriptions layout (1p) vs. the swipe to Unsubscribe
1p draws one rail (Works · Series · Authors · Reset) and puts works with new chapters in a 164×232 cover
grid. The app keeps a second All / Updated rail and draws updated works as swipeable rows: a cover grid
cannot take the confirming Unsubscribe swipe (it is not a List). Options: (a) keep as is; (b) covers
with Unsubscribe in a long-press menu, second rail removed (Updated is already grouped first).
Recommendation: (b), matching the queue grid's long-press remove (T-287).

## 6. Reader chapter headings: serif or the reader's chosen font?
With the reader font on System, AO3 chapter headings still render in Readium's default serif ("Chapter 2:
Nine Minutes") above sans body text. Options: (a) keep — a serif heading reads as a book title; (b) headings
follow the chosen reader font. Low-stakes; verify on a real AO3 EPUB, whose own CSS may set the heading face.
