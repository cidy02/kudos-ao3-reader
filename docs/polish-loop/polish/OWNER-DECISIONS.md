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

## 7. Challenge and moderation screens where the spec asks for data AO3 does not give us
The artboards draw a "Send pinch-hit request" button (1cb), a required rejection reason that is emailed (1ce),
an "unmatched pairs" view from potential matches (1cb), reveal dates (1cd), a host byline (1cf), owners and
moderators on a tag set (1ch), and a collection icon upload plus byline (1bl). AO3 exposes no client endpoint
or field for most of these; the app shows the truthful subset and sends people to AO3 for the rest.
Options: (a) keep the truthful subset; (b) parse the few that AO3's pages do print (request dates, item word
counts) and keep the rest at AO3. Recommendation: (a) now, (b) as a later task.

## 8. Form confirm chrome: top check circle or bottom Save bar?
1by / 1cf / 1s / 1bl draw a 34pt filled check circle top-right as the form's Save; the app's AO3 forms save with
a full-width bottom "Save changes" bar (and Collection items with a text "Submit"). Same question as #2 for the
creation sheets. Options: (a) keep bottom bars / text; (b) move every AO3 form to the top check circle.
Recommendation: decide together with #2 — one convention app-wide. (b) matches the spec; (a) keeps a large
target near the thumb.

## 9. AO3 collection form structure (1bl / 1cg / 1cf)
The spec hides the "Email new items" toggle, moves edit-only routes (maintainers, moderation, items, challenge,
reveal, delete) into the edit sheet, draws a dedicated Collection settings screen (1cg), and collapses the
challenge edit form's seven tag-type limits into compact summary rows. Each is a restructure; the first would
hide a real AO3 setting. Options: (a) keep; (b) adopt 1cg + edit-sheet routes, keep Email new items visible.
Recommendation: (b).

## 10. AO3 History's first layout
History shares the Account tab's layout preference (default Compact, a cover grid); 1t draws History as ledger
rows with visit and progress lines, and the layout picker's own note says "History has no cover grid (1ah)".
Marked for Later and Subscriptions already ignore the shared switch because their artboards draw one layout.
Options: (a) keep the shared preference; (b) History ignores Compact and opens in Ledger (Detailed still
offered). Recommendation: (b), matching the precedent of the two lists beside it.
