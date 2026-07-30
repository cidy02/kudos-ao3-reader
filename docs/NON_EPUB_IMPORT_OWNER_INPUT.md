# Non-EPUB import (T-152…T-155) — decisions made without you, and what needs your call

Written during the overnight run of 2026-07-30 on
`claude/non-epub-pdf-distribution-ab6eba`. You said nothing should block, so every
open question below was resolved with a best-effort choice and shipped. This file
is the review queue: **nothing here is a blocker, everything here is reversible.**

Ordered by how likely you are to disagree.

---

## 1. Deferred formats are *claimed* in the document types, but fail with a message

**What I did.** The app now appears in "Open in Kudos" for PDF, DOCX and RTF even
though T-153 is what actually converts them. Opening one produces: *"PDF import is
coming in a later update. For now, convert it to EPUB (calibre, or Word's Save as)
and import that."*

**Why.** A file that simply cannot be opened teaches the user nothing. A named
format plus a workaround is a better dead end than a greyed-out row.

**If you disagree.** Remove index 4 from `add_doc_type` in the Info.plist build
phase (project.pbxproj) and drop those types from `workImportContentTypes` in
`SettingsView`. Roughly a five-line revert.

---

## 2. Images are dropped from converted HTML, not inlined

**What I did.** `HTMLWorkSanitizer` strips `<img>` entirely.

**Why.** A remote `src` would make the reader fetch from a stranger's server on
every page turn — a privacy leak and against `docs/AO3_NETWORKING_POLICY.md`.
Fetching them at import time is *also* network traffic to an unvetted host, so I
did not do that either.

**What this costs.** Illustrated fic loses its illustrations. For AO3 text works,
which is the overwhelming majority, nothing is lost.

**The real fix, if you want it (T-153 scope).** Two cases are safe and worth doing:
`data:` URI images (SingleFile captures embed everything this way — no network at
all), and a sibling `_files/` folder from a browser "Save Page As". Both can be
embedded into the EPUB as local resources. Remote-only images should stay dropped.

---

## 3. Inline styles are stripped too

Same sanitizer. A community copy's hardcoded colours and fonts would fight every
app theme and ignore Dynamic Type — the reader owns typography. I think this one is
uncontroversial, but it is a deliberate content change, so it is on the list.

---

## 4. Plain-text chapter splitting is biased towards *under*-splitting

**What I did.** A line only counts as a chapter heading if it matches
`Chapter <n>` / `Ch. <n>` / `Part <n>` / `<n>.` / `***` / Markdown `#`, **and** any
trailing title is introduced by a separator (`:`, `.`, `-`, `—`).

**Why the separator rule exists.** Without it the prose line *"chapter 5
implied."* reads as a heading and splits a work mid-sentence. There is a test for
exactly this (`proseMentioningAChapterNumberIsNotASplitPoint`).

**Known gap.** Roman numerals and words up to "twenty" are handled
("Chapter One", "Chapter IV"); "Chapter Twenty-One" and higher are not, and
neither are unlabelled scene breaks that use whitespace alone. Those import as one
long chapter — readable, just with a thin table of contents.

---

## 5. Where the originals live, and what deletes them

**What I did.** Converted imports keep the exact bytes they came from in a new
`Application Support/Originals/<work-uuid>.<ext>`, per your "always keep + hash"
decision.

**Two things to know:**

- **The hash is not stored yet.** There is nowhere to put it — a `SavedWork` field
  is a schema change, which belongs to T-155 with the rest of the provenance
  fields and the manifest v9 bump. The bytes are preserved now; the checksum
  column arrives with the model change. If you want the integrity check sooner,
  that is a reason to reorder T-155 ahead of T-153.
- **`.kudosbackup` does not carry originals yet.** Also T-155 (it is a format
  change). So today an original survives device backup and restore of the app's
  container, but **not** a `.kudosbackup` export/import round trip or folder sync.
  That is the single biggest gap in this task, and it is deliberate: doing it here
  would have meant editing the same files as the annotations work that just landed.

**Deletion.** Permanent delete removes the original; `freeEPUB` deliberately does
not, because freeing exists to reclaim space for works that can be re-downloaded
from AO3, and the original of a community copy is the one artifact that cannot be.

---

## 6. "Show in Library" instead of opening the imported work

When a file is opened from outside the app, the confirmation offers *Show in
Library*, which switches tabs. It does not jump to the work.

**Why.** There is no by-id work route today, and each tab owns its own navigation
stack, so adding one would have been a much larger change than one alert button
justifies. Worth doing properly if you want deep links later (it is also what a
future `kudos://work/<id>` scheme would need).

---

## 7. An EPUB is never re-encoded, and that is load-bearing

If the file is already an EPUB it is imported byte-for-byte, and a converted file
is byte-reproducible from the same source (fixed identifier, pinned
`dcterms:modified`, MiniZip's fixed DOS timestamp).

This is not tidiness: dedup for non-AO3 works falls back to a title + author +
**exact file size** heuristic (`WorkImporter.swift`), so a non-reproducible
conversion would make every re-import look like a new work. If you ever change
`EPUBBuilder`'s output, `reimportingTheSameConvertedFileIsTreatedAsADuplicate`
is the test that will tell you what you broke.

---

## 8. What I did *not* touch

- `Models.swift` and `KudosBackup.swift` — untouched on purpose, so this task
  cannot collide with the annotations v8 work at the tip. All schema/format
  changes are T-155's.
- ~~The two pre-existing lint **errors**~~ — **since fixed as T-156**, after you
  started the spun-off task. `CommentsModel.swift` lost three static methods to a
  new `CommentsErrorMessages.swift` extension (903 → 867 class-body lines), and
  `ReadiumReaderView.swift` was split into `ReadiumBook.swift`,
  `ReaderDismissDrag.swift` and `ReadiumNavigatorContainer.swift` (3585 → 1731
  lines). Verified as pure movement: both trees normalize to 2475 code lines, with
  exactly five differing lines — the five visibility widenings the split forced,
  each documented where it landed. `Scripts/verify.sh` now passes all five stages
  on this branch, which had not been true for any branch on this stack.
  See T-156 in `TASKS.md`.

---

## 9. Verification status

| Gate | Result |
|---|---|
| `check-invariants.sh` | passes |
| `lint.sh` | fails on the two inherited errors above and nothing else; all 8 new files clean |
| iOS test suite | 778 tests / 71 suites pass (baseline was 738 / 68 — the 40 new tests are this task's) |
| `build-macos.sh` | passes |
| Document types | verified in the built `Kudos.app` Info.plist, not just in the script |

**Not verified, and worth ten minutes of your time on a device:** the real
"Open in Kudos" flow. I can assert the Info.plist is correct and that the import
path works, but whether Kudos actually appears in the Files/Safari/Reddit share
sheet — and whether the Inbox copy is cleaned up on a real device — needs a human
with a phone. Everything else here has a test.
