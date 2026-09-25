# Writing editor architecture: HTML and Rich Text modes

| | |
|---|---|
| **Status** | Plan of record. E1 is in progress. E3 onward waits on owner decision **OD1** (§13). |
| **Applies to** | Apple (`kudos-ao3-reader/`, SwiftUI on iOS, iPadOS and macOS) and Android (`android/` on `kudos-ao3-reader-android`, Compose). |
| **Canonical copy** | This file. Keep it byte-identical on the Android branch. If the two copies ever differ, the one with the later entry in the revision log (§15) wins, and the other is brought up to date in the same change. |
| **Tracking** | TASKS.md **T-262** (this document and E1). Later steps get their own rows when they are claimed (§12). |
| **Ground truth** | AO3's own code, otwarchive at `00ad85b4` (the checkout used for `docs/audits/2026-09-24/otwarchive-facts-wave3.json`). Where this file and AO3 disagree, AO3 wins and this file is corrected. |

The words **MUST**, **MUST NOT**, **SHOULD** and **MAY** are used as in RFC 2119.
Everything marked *normative* binds both platforms. Code sketches are
illustrations, not API.

---

## 0. The decision in one screen

| # | Decision | Status |
|---|---|---|
| D1 | The Rich Text canvas is **ProseMirror** with Kudos's own AO3 schema, running in a **WebView** (WKWebView on Apple, the system WebView on Android). Every control around it (toolbar, link sheet, menus, navigation) stays native. | Proposed; **OD1** |
| D2 | **HTML mode stays native on Apple** (the existing `UITextView` / `NSTextView` controller). On Android, HTML mode is a native text field if it passes the typing gate in §9.2; otherwise it is CodeMirror 6 in the same WebView. | Decided (Apple); gate (Android) |
| D3 | Modes **hand off** ownership of the text. They never sync live. Exactly one mode owns the text at any moment. | Decided |
| D4 | The real text lives **natively**, in a per-field `DraftSession`, as an HTML string plus a revision number. The WebView's state is disposable. | Decided |
| D5 | Parsing, sanitizing and serializing are **one JavaScript package** (`editor-core`), shared byte for byte by Apple, Android and Node CI. It uses **parse5**, not the platform's `DOMParser`, so all three parse identically. | Decided |
| D6 | Each mode keeps its own undo history, and a switch is a boundary. **A switch that isn't followed by an edit changes nothing**, so there's nothing to undo. | Decided |
| D7 | Recovery never depends on the WebView, and recovered text always opens in HTML mode. | Decided |
| D8 | Keystrokes are **O(edit)**. No keystroke copies the chapter, serializes, touches disk, counts words, or sends text over the bridge. | Decided; E1 makes the Apple code comply |

The rejected alternatives and the reasons (TinyMCE, Aztec, RichTextKit, native
rich text per platform, a single WebView for both modes) are in §4.

---

## 1. Terms

| Term | Meaning |
|---|---|
| **Field** | One editable AO3 form field: chapter text, summary, beginning notes or end notes. Each open field has one `DraftSession`. |
| **Mode** | `source` (HTML mode, the raw HTML buffer) or `rich` (Rich Text, the ProseMirror canvas). |
| **Owner** | The mode whose view currently holds the authoritative text and accepts input. |
| **Revision** | A monotonically increasing integer. Every edit in the owning mode increments it. Loading text into a mode doesn't. |
| **Checkpoint** | Fetching the owner's text and writing it out: to the session, to the form field and to the recovery store (§8). |
| **Snapshot** | The text plus its revision, as captured by one checkpoint. |
| **Hand-off** | A mode switch: freeze the owner, snapshot, checkpoint, load into the other mode, transfer ownership (§7). |
| **Canonical HTML** | Output of the `editor-core` serializer (§6.7). The rich mode only ever produces canonical HTML. HTML mode may hold anything the writer typed. |
| **AO3-stable** | HTML that AO3's own cleaning pipeline (§3.1) doesn't change in meaning. |

---

## 2. Where we are (2026-09-25)

### 2.1 Apple

- The field editor is `Features/Writing/WritingTextEditor.swift`: a native text view
  (`WritingNativeTextView.swift`, `UITextView` / `NSTextView`) with tag buttons that
  splice tags around the selection. The splicing logic is `Models/AO3Markup.swift`,
  which the comment composer shares.
- It's used from the work form (`WorkEditView.swift`, four fields) and Add Chapter
  (`AddChapterView.swift`, four fields).
- **Defects that E1 fixes** (verified by reading the code at `c4ce1e2`):
  - Every text change writes a recovery copy synchronously on the main thread:
    `WritingTextEditor.swift:167-170` calls `WritingTextRecovery.save`.
  - Each save then prunes by decoding every stored copy of that field
    (`WritingTextRecovery.swift:49-65`, via `copies(for:)`). For a 50,000-word chapter
    that's up to six ~300 KB JSON files decoded per keystroke.
  - One unreadable copy makes `copies(for:)` throw. After that, nothing for that field
    is pruned, and the recovery prompt shows an error instead of *any* of the other
    copies (`WritingTextEditor.swift:171-173`).
  - Every keystroke copies the whole chapter into the form's SwiftUI state through the
    field binding (`WorkEditView.swift:353-359`). That re-renders the form.
  - Every render recounts words with regex passes over the whole text
    (`WritingTextEditor.swift:42`).
  - `WritingTextController.emit()` compares the full text with the last emitted copy on
    every keystroke (`WritingNativeTextView.swift:139-144`).
  - The SHA-256 of the field's original text is recomputed on every save.
- Autocorrect, smart quotes and smart dashes are off (`WritingNativeTextView.swift:23-27`).
  On iOS, spell-checking follows autocorrect unless it's set explicitly, so writers get
  no spelling help today (E1b).
- History: Codex built a WKWebView `contenteditable` rich editor on 2026-09-12. It was
  replaced by the native controls on 2026-09-13 under the native-only rule (T-215;
  `docs/REDESIGN_PLAN.md:1927-1936`). Its security fencing is worth reusing in E3 (§11).

### 2.2 Android

- There is **no writing editor**. Account → Drafts falls back to the website
  (`AccountWritingDestinationsTest.kt` on `kudos-ao3-reader-android`). Every Android
  part of this document is a clean start.

### 2.3 AO3's own website

- AO3's posting form has **HTML** and **Rich Text** links above one `<textarea>`.
  "Rich Text" attaches TinyMCE 5.0.16 (LGPL, 2019) to that textarea; "HTML" removes it
  again (`public/javascripts/mce_editor.js`, `addEditor` / `removeEditor`).
- The textarea's string is always the source of truth, and a switch resets TinyMCE's
  undo. **That hand-off model is the one this document adopts (D3).** It improves on
  AO3 in four ways:
  - a lossless schema (§6.2);
  - a no-op round trip (R1 in §7.1);
  - a loss report before anything is dropped (§6.9);
  - caret preservation (§7.5).

---

## 3. AO3 ground truth (normative inputs)

All paths are in otwarchive at `00ad85b4`.

### 3.1 The cleaning pipeline

For every field in `FIELDS_ALLOWING_HTML` (`config/config.yml:374-375`), which includes
`content`, `summary`, `notes` and `endnotes`, `HtmlCleaner#sanitize_value`
(`lib/html_cleaner.rb:42-82`) runs these steps in order:

1. `strip!` the value.
2. `fix_bad_characters` (`:25-39`): drop invalid UTF-8, turn `<3` into `&lt;3`, turn
   `\r\n` and `\r` into `\n`, remove `____spacer____`.
3. `add_paragraphs_to_text` (`:130-136`), which is **ParagraphMaker** (§3.4).
4. `Sanitize.clean` with `ARCHIVE`, or with `CSS_ALLOWED` for the `class`-allowing
   fields (§3.3), plus transformers:
   - `<details open>` becomes `open="open"`;
   - relative `img src` is made absolute;
   - `content` gets embed and media rules;
   - `class`-allowing fields get the class filter.
5. Re-serialize with `Nokogiri::HTML5` `fragment(...).to_html`.

**Consequence: "raw HTML" isn't raw on AO3.** Newlines are significant (§3.4), empty
paragraphs vanish, and `<br><br>` becomes a paragraph break. Kudos's HTML mode posts the
writer's text verbatim and AO3 applies all of this. Rich mode MUST produce HTML that
this pipeline leaves unchanged in meaning (S15 in §6.7).

> Correction: the comment at `Models/AO3Markup.swift:112-115` says chapter text is
> posted verbatim and "nothing paragraphs it". AO3 paragraphs every HTML field. E1
> corrects the comment.

### 3.2 The allow-list (`config/initializers/gem-plugin_config/sanitizer_config.rb`)

- **Elements** (`:6-10`): `a abbr acronym address b big blockquote br caption center
  cite code col colgroup details figcaption figure dd del dfn div dl dt em h1 h2 h3 h4
  h5 h6 hr i img ins kbd li ol p pre q rp rt ruby s samp small span strike strong sub
  summary sup table tbody td tfoot th thead tr tt u ul var`.
- **Attributes allowed on every element** (`:12-13`): `align dir lang title`.
- **Attributes per element** (`:14-26`):
  - `a`: `href name`
  - `blockquote`: `cite`
  - `col`, `colgroup`: `span width`
  - `details`: `open`
  - `hr`: `align width`
  - `img`: `align alt border height src width`
  - `ol`: `start type`
  - `q`: `cite`
  - `table`: `border summary width`
  - `td`: `abbr axis colspan height rowspan width`
  - `th`: `abbr axis colspan height rowspan scope width`
  - `ul`: `type`
- **Added on output** (`:29-31`): `rel="nofollow"` on every `a`.
- **Protocols** (`:33-38`):
  - `a href`: ftp, http, https, mailto, relative
  - `blockquote cite` and `q cite`: http, https, relative
  - `img src`: http, https
- **Removed together with their content** (`:42`): `iframe math noembed noframes
  noscript plaintext script style svg xmp`, unless an embed rule allows the `iframe`
  (§3.3).
- **Anything else not listed** is removed and its content kept (Sanitize's default).
  Attributes not listed are dropped: `style`, `id`, `data-*`, `on*`, `target`, `rel`,
  `color`, `face`, and so on.

### 3.3 Per-field rules and limits

| Field (AO3 name) | `class` allowed | Embeds and media | Limit (`config/config.yml`) |
|---|---|---|---|
| `content` (chapter text) | yes | yes | 510,000 characters (`CONTENT_MAX`, `:108`); AO3 tells users 500,000 (`:109`) |
| `notes`, `endnotes` | yes | no | 5,000 each (`NOTES_MAX`, `:104`) |
| `summary` | **no** | no | 1,250 (`SUMMARY_MAX`, `:103`) |
| `comment_content` (not in scope; the composer) | no | no | 10,000 (`:105`), counted in code points |

- **Class filter** (`lib/otw_sanitize/user_class_sanitizer.rb:37-39`): each class name
  must match `^[a-zA-Z][\w\-]+$`. Anything else is removed from the list. Classes
  are how work skins work.
- **Embeds** in `content` (`lib/otw_sanitize/embed_sanitizer.rb:9-22`): `iframe` and
  `embed`, and `object`/`param`, from these hosts only: 4shared, audio.com,
  archive.org, bilibili, criticalcommons, podfic.com, soundcloud, spotify, vidders.net,
  viddertube, vimeo, youtube and youtube-nocookie.
- **Media** in `content` (`lib/otw_sanitize/media_sanitizer.rb`): `audio`, `video`,
  `source`, `track`, with http or https sources.

### 3.4 ParagraphMaker (`lib/paragraph_maker.rb`)

`process` (`:271-280`) runs these steps in order:

1. `strip_whitespace`: whitespace next to block tags is removed.
2. `split_text_at_newlines`:
   - one `\n` in text becomes `<br>`;
   - two become a paragraph split;
   - three or more become a split plus a `<p>&nbsp;</p>` spacer.
3. `merge_br_tags`: `<br><br>` becomes a split, and three or more `<br>` become a split
   plus a spacer.
4. `wrap_all`: loose inline content is wrapped in `<p>`.
5. `unwrap_all`: block elements are lifted out of `<p>`.
6. `replace_splits`.
7. `delete_empty_paragraphs`: `<p></p>` with no children is removed.

- It does **not descend into** (`TAG_NAMES_TO_SKIP`, `:20-24`): `a abbr acronym address
  audio dl embed figure h1-h6 hr img ol object p pre source summary table track video
  ul`. So text inside `<p>`, lists, headings and `<summary>` keeps its newlines as
  ordinary whitespace, while text directly in `div`, `blockquote`, `details`, `center`
  or at top level is paragraphed.
- Whitespace is stripped around (`TAG_NAMES_STRIP_WHITESPACE`, `:38-41`): `audio
  blockquote br center details dl div figure figcaption h1-h6 hr ol p pre source
  summary table track ul video`. Newlines *between* block elements are therefore
  insignificant.

### 3.5 AO3's Rich Text configuration (`public/javascripts/mce_editor.js`)

This is the feature set to match:

- **Toolbar** (`:8`): paste | bold italic underline strikethrough | link unlink image |
  blockquote | hr | bullist numlist | align left, center, right, justify | undo redo |
  ltr rtl.
- **Browser spell-check** is on (`:10`).
- **Inline styles** are off (`:13`). Alignment is the `align` attribute (`:39-54`),
  underline is `<u>` (`:55`) and strikethrough is `<strike>` (`:56-60`).
- **Kept as written** (`:28`): `b`, `i`, `strike`, `u`, and `span` only when it has a
  `class` or `dir`. `font` is removed (`:31`).
- **Word paste allow-list** (`:66`): `@[align], strong/b, em/i, u, span, p, ol, ul, li,
  h1-h6, table, tr, td[colspan|rowspan], th, thead, tfoot, tbody, a[href|name], sub,
  sup, strike, br`.

### 3.6 Word counting (`lib/word_counter.rb`, scripts at `config/config.yml:894`)

AO3 counts words like this:

1. Take text nodes only.
2. Replace `--` with `—`.
3. Remove `'`, `’`, `‘` and `-`.
4. Count each character in `CHARACTER_COUNT_SCRIPTS` (Han, Hiragana, Katakana, Thai)
   as one word.
5. Count each run of other word characters as one word.

The editor's count SHOULD match (OD3). E1 keeps the current whitespace count, moved off
the main thread. E2 implements AO3's algorithm once, with shared fixtures, and each
platform's HTML mode ports it.

---

## 4. Alternatives rejected, and why

| Option | Why not |
|---|---|
| **TinyMCE** (AO3's engine) | A whole UI framework (iframe, its own toolbars and menus) that you have to fight to put behind native controls. AO3's help text warns its Rich Text behaviour "depends on your device, browser, and operating system" (`config/locales/views/en.yml:1477`). We copy its *configuration* (§3.5), not the engine. |
| **Aztec** (WordPress) | UIKit only, so no macOS. Separate Swift and Kotlin codebases mean two serializers kept identical only by tests. WordPress's own apps have been moving to a web-based editor (unverified here; check before relying on Aztec's maintenance). The GPL-2.0 licence must be "or later" to be combined with AGPL-3.0. |
| **RichTextKit** | Apple only, and HTML goes through `NSAttributedString`'s importer and exporter, which is WebKit-backed, main-thread only, and writes inline-styled `<span>`s. |
| **iOS 26 SwiftUI `TextEditor` + `AttributedString`** | Good for character formatting, but AO3's block model (blockquote, lists, `hr`, `details`, tables, work-skin `div`s) would all be hand-built, and there's no Android equivalent. The best *native* path if Android parity is ever dropped. |
| **Native rich text on each platform** | Three editors (UIKit, AppKit, Android), each with its own converter, IME handling and block drawing, kept identical only by tests. |
| **One WebView for both modes** | Doesn't remove the hard problem (turning HTML into a document and back without loss). It just moves it into JavaScript. It also removes the only failure-proof path to the text (D7). Still the Android answer if a native field fails the gate (D2). |

---

## 5. Architecture

### 5.1 Components

```
                 ┌──────────────── DraftSession (native, one per open field) ────────────────┐
                 │ text: String        revision: Int        owner: source | rich              │
                 │ baseText (what the form loaded)          checkpoint policy (§8.1)          │
                 │ recovery writer (off the main thread, §8)   hand-off state machine (§7.1)   │
                 └───────▲───────────────────────────▲────────────────────────────▲──────────┘
             fetch text at checkpoints   fetch text at checkpoints        Save / Post read it
                         │                           │                            │
   SourceEditor ─────────┘         RichEditor ───────┘                    AO3 form → POST
   UITextView / NSTextView         WebView + editor-core
   (Android: native field          (ProseMirror, parse5, sanitizer,
    or CodeMirror 6)                serializer, paste cleaner)
```

- **DraftSession.** Native: on Apple a `@MainActor` class whose disk work runs on an
  actor, on Android a main-thread class with an IO-dispatcher writer. It owns the text,
  the revision, the owner, the checkpoint timer and the hand-off. E1 builds its first
  two pieces on Apple (`WritingCheckpointPolicy`/`Scheduler` and
  `WritingRecoveryWriter`). E3 assembles the session around them.
- **SourceEditor.** The native text view. It reports "edited" (O(1)) and returns its
  text only when asked.
- **RichEditor.** The WebView hosting `editor-core`. It reports "edited" with a
  revision number only, and returns text only when asked (§7.2).
- **editor-core.** The shared JS package (D5, E2): schema (§6), parse5 pipeline, AO3
  sanitizer and ParagraphMaker ports, serializer, paste cleaner, AO3 word counter,
  caret maps and loss report. It lives at `editor-core/` at the repo root on both
  branches. The built bundle is copied into each app's resources.

### 5.2 Invariants (normative)

- **I1.** Exactly one mode owns the text. The other MUST NOT accept input.
- **I2.** The native `DraftSession` holds the text of record. Nothing in the WebView is
  required to recover a chapter.
- **I3.** Keystroke cost is O(edit) in both modes (D8). Allowed per keystroke: the
  native text view's own work, one integer increment, and scheduling a timer. At most
  4 "edited" bridge messages per second, carrying no text.
- **I4.** Every hand-off is a checkpoint, written before the new owner accepts input.
- **I5.** Recovery writes are ordered. An older snapshot MUST NOT overwrite a newer one.
- **I6.** Recovery never needs the WebView, and recovered text opens in HTML mode (D7).
- **I7.** Only HTML (plus small metadata) is stored long-term. ProseMirror JSON appears
  only in the short-lived edit log (§8.6), tagged with its schema version.
- **I8.** Loading HTML into rich mode drops nothing AO3 would keep (§6.2). Anything it
  does drop is reported, and confirmed by the writer, before the hand-off completes
  (§6.9, §7.3).
- **I9.** A switch without an edit changes nothing (R1 in §7.1).
- **I10.** An edit in rich mode changes the HTML of the blocks it touches and no others
  (R2 in §7.1).

---

## 6. Document model and schema constraints (normative)

### 6.1 Loading pipeline (`editor-core`)

Every load, preload and paste goes through the same steps:

1. **Parse** with parse5 (the HTML5-spec parser), fragment mode, with source locations
   switched on.
2. **Clean** with a port of §3.1 steps 2–4: bad characters, ParagraphMaker (§3.4), the
   allow-list (§3.2), and the per-field rules (§3.3). Every change is recorded for the
   loss report (§6.9).
3. **Build** the ProseMirror document per §6.2–6.6. Record source ranges for text nodes
   (for caret mapping, §7.5) and for each top-level block (for locality, R2).

The live page's DOM is never used to parse. Untrusted HTML reaches the page only as
ProseMirror's own rendering of a clean document (§11).

### 6.2 Three tiers

| Tier | Contents | In rich mode |
|---|---|---|
| **Editable** | Everything in §6.3 and §6.4 | Rendered and editable. The toolbar creates only the "created by" items. |
| **Preserved** | Allowed by AO3 but not editable on a phone: `table` (with its parts), `pre`, `dl`/`dt`/`dd`, `figure`/`figcaption`, `address`, `ruby`/`rt`/`rp`, allowed embeds and media (content only), and any allowed inline element with no text (for example `<a name="ch1"></a>` anchors, or an empty classed `<span>`) | A locked box or chip labelled with its tag ("Table: edit in HTML mode"). Serialized as its original source slice, byte for byte. |
| **Dropped** | Whatever §3.2 and §3.3 remove | Removed at load, counted in the loss report. |

### 6.3 Nodes

Tags other than `p`, `h1`–`h6` and `li` are serialized as parsed. "G" is the global set
`align dir lang title`, plus `class` in the `content` and `notes` variants.

| Node | HTML | Attributes kept | Content | Created by toolbar |
|---|---|---|---|---|
| `doc` | fragment | — | block+ | — |
| `paragraph` | `p` | G; `implicit` (internal) | inline* | Return |
| `heading` | `h1`–`h6` | `level`, G | inline* | "Heading" creates `h3` (matches `AO3MarkupTag.heading`) |
| `blockquote` | `blockquote` | `cite` (http, https, relative), G | block+. Loose inline children are wrapped in `p`, as AO3 does. | yes |
| `bullet_list` | `ul` | `type`, G | list_item+ | yes |
| `ordered_list` | `ol` | `start`, `type`, G | list_item+ | yes |
| `list_item` | `li` | G | paragraph block*. A leading paragraph built from loose inline content is `implicit` and serialized without `<p>` (AO3 doesn't paragraph inside lists). | via lists |
| `horizontal_rule` | `hr` | `align`, `width`, G | atom | yes |
| `details` | `details` | `open` (serialized `open="open"`), G | summary block* | "Spoiler" |
| `summary` | `summary` | G | inline* | via Spoiler |
| `container` | `div`, `center` (`tag` kept) | G | block+ | never (work-skin wrappers; editable inside) |
| `image` | `img` | `src` (http/https), `alt`, `width`, `height`, `align`, `border`, G | inline atom | yes (native URL sheet) |
| `hard_break` | `br` | — | inline atom | Shift+Return |
| `raw_block` | preserved block | its source slice | atom | never |
| `raw_inline` | preserved inline | its source slice | inline atom | never |

### 6.4 Marks

Listed in nesting order, outermost first. The serializer MUST nest marks in this order.

| Mark | HTML (`tag` kept as parsed) | Extra attributes | Created by toolbar as |
|---|---|---|---|
| `link` | `a` | `href` (ftp, http, https, mailto, relative), `name`, G | `<a href>` (the Kudos sheet allows http, https and mailto only) |
| `span` | `span`, **only** when it has a kept attribute; attribute-less spans are unwrapped | G | never |
| `phrase` | `abbr`, `acronym`, `dfn`, `cite`, `q` | `q` keeps `cite`; G | never |
| `strong` | `strong`, `b` | G | `strong` |
| `em` | `em`, `i` | G | `em` |
| `underline` | `u` | G | `u` |
| `strike` | `strike`, `s`, `del` | G | `strike` (AO3's own format, §3.5) |
| `ins` | `ins` | G | never |
| `size` | `big`, `small` | G | `small` |
| `script` | `sup`, `sub` | G | `sup`, `sub` |
| `code` | `code`, `kbd`, `samp`, `var`, `tt` | G | `code` |

- A mark can't cover zero characters. An allowed inline element with no text is
  therefore a `raw_inline` (§6.2).
- `rel` on `a` is removed silently and counted as *normalized*, because AO3 adds
  `rel="nofollow"` itself.

### 6.5 Attributes

- Only attributes allowed by §3.2 and §3.3 for that element and field are kept.
  Protocols are checked (§3.2), and classes filtered by `^[a-zA-Z][\w\-]+$` in `content`
  and `notes`, removed entirely in `summary`.
- Alignment and direction are attributes (`align`, `dir`). `style` is never written.

### 6.6 Field variants

| Variant | Used for | `class` | Preserved embeds and media | Length limit enforced before Save |
|---|---|---|---|---|
| `content` | chapter text | yes | yes | 510,000 |
| `notes` | beginning notes, end notes | yes | no | 5,000 |
| `summary` | summaries | no | no | 1,250 |

### 6.7 Serializer rules

- **S1.** Output an HTML fragment (no doctype, `html` or `body`).
- **S2.** Void elements (`br hr img col source track embed param`) have no
  self-closing slash.
- **S3.** Attributes are double-quoted. Escape `&`, `"` and U+00A0 as `&amp;`, `&quot;`
  and `&nbsp;`.
- **S4.** Attribute order: the element's own attributes in the order §3.2 lists them,
  then `align dir lang title`, then `class`. Preserved slices keep their own order.
- **S5.** Text escapes `&`, `<`, `>` and U+00A0 only. Every other character is literal
  UTF-8.
- **S6.** Exactly one `\n` between sibling blocks (top level, and inside `blockquote`,
  `div`, `center`, `details`, and between `li`). No other newline outside preserved
  slices. No leading or trailing whitespace.
- **S7.** Inline content appears only inside `p`, `h1`–`h6`, `li` (the implicit
  paragraph), `summary`, or preserved slices. Everywhere else it's wrapped in `<p>`.
- **S8.** A text node never contains `\n`. A line break is `<br>`.
- **S9.** An empty paragraph is written `<p>&nbsp;</p>`. AO3 deletes a childless
  `<p></p>` (§3.4 step 7).
- **S10.** No two adjacent `<br>`. Inserting a hard break directly after another splits
  the paragraph instead (AO3's `merge_br_tags`, §3.4).
- **S11.** Marks nest in §6.4 order, and adjacent identical marks merge.
- **S12.** A mark's element name comes from its `tag` attribute (`b` stays `b`). Marks
  the toolbar creates use `strong em u strike sup sub small code`.
- **S13.** Preserved atoms are written as their source slice, unchanged.
- **S14.** Idempotence: `serialize(parse(serialize(d))) == serialize(d)` for every
  document `d`.
- **S15.** AO3 stability: running §3.1 on `serialize(d)` gives HTML whose parse equals
  `d`.
- **S16.** Locality: a top-level block that is the same node object as when it was
  loaded is written as its original source slice, and so is the whitespace between two
  such blocks (R2).

### 6.8 Paste (rich mode)

- **P1.** Use the clipboard's `text/html` if present. Otherwise use `text/plain`,
  paragraphed with ParagraphMaker rules (§3.4).
- **P2.** Pre-clean the HTML string. Remove comments (including Word's
  `<!--[if …]>…<![endif]-->`), `xml`, `style`, `meta`, `link`, `o:p`, and elements in
  the `w:`, `o:`, `v:` and `m:` namespaces.
- **P3.** Turn styles into structure *before* styles are dropped:
  - `font-weight` bold or 600 and above → `strong`
  - `font-style: italic` → `em`
  - `text-decoration: underline` → `u`
  - `text-decoration: line-through` → `strike`
  - `vertical-align: super` / `sub` → `sup` / `sub`
  - `text-align` → `align` on the enclosing block
  - `direction: rtl` → `dir`
- **P4.** Google Docs wraps every paste in `<b id="docs-internal-guid-…"
  style="font-weight:normal">`. Unwrap it *without* applying bold.
- **P5.** Word:
  - drop `Mso*` classes;
  - turn `mso-list` paragraphs into `ul`/`ol` items, nested by level;
  - unwrap spans whose only attribute is `lang`.
- **P6.** Then run the §6.1 pipeline, exactly as for a loaded document.
- **P7.** Paste never fetches anything.
- **P8.** HTML mode pastes plain text natively. "Paste as HTML" (E3, E5) runs the
  clipboard's HTML through P2–P6 in the hidden WebView and inserts the result.
- **P9.** Fixtures (E2): Word 365 on Windows, Word for Mac, Google Docs in Chrome,
  Pages, a Scrivener export, and a copy from an AO3 work page, each with its expected
  output.

### 6.9 Loss report

```ts
type LossReport = {
  dropped: { elements: Record<string, number>; attributes: Record<string, number> }; // AO3 would remove these too
  unwrapped: Record<string, number>; // tag removed, text kept, no visual change (e.g. attribute-less <span>)
  normalized: number;                // same meaning, different bytes (nesting, attribute order, rel, whitespace)
  preserved: number;                 // raw blocks and inlines kept verbatim
};
```

A switch into rich mode MUST ask for confirmation when `dropped` isn't empty, for
example "AO3 would remove these when you save: `<font>` ×3, `style` ×42". Cancelling
leaves HTML mode untouched. `unwrapped` and `normalized` never block. They're shown in
a "What changed" disclosure.

### 6.10 Conformance tests (E2; required before E3)

- **Golden fixtures** made by running otwarchive's `HtmlCleaner#sanitize_value` and
  `WordCounter` (Ruby) over a corpus: synthetic cases for every rule above, plus real
  chapter HTML. Committed as JSON under `editor-core/test/golden/`. They're
  platform-neutral, so Swift and Kotlin tests reuse them for the HTML-mode word counter
  and recovery keys.
- **Property tests** (fast-check) for S14, S15, S16, R1 and R2 over generated documents.
- **Paste fixtures** (P9).
- **A 510,000-character fixture** (§9.1) for performance regression tests in Node.
  These are regression guards, not device budgets.

---

## 7. Hand-off mechanics (normative)

### 7.1 State machine

```
 ┌─────────────┐  switch→rich   ┌──────────────────────────────┐ loaded (+ confirmed) ┌───────────┐
 │ sourceOwned │ ─────────────▶ │ handOff(source→rich)          │ ───────────────────▶ │ richOwned │
 │             │ ◀───────────── │ freeze · snapshot · checkpoint │                      │           │
 └─────────────┘ cancel/timeout │ · load or activate · confirm   │                      └───────────┘
        ▲        /error         └──────────────────────────────┘                            │
        │                       ┌──────────────────────────────┐        switch→source       │
        └────────────────────── │ handOff(rich→source)          │ ◀──────────────────────────┘
                   commit       │ freeze · snapshot · checkpoint │
                                │ · set text (only if edited)    │
                                └──────────────────────────────┘
 richOwned ── WebView process gone ──▶ sourceOwned (last checkpoint + journal) ; rich off for 60 s
 any handOff ── 2 failures in one session ──▶ rich unavailable until the editor is reopened
```

- **R1, no-op round trip.** If no edit happened in the mode being left (the revision is
  unchanged since the hand-off in), switching back restores the previous owner's text
  byte for byte. The normalized serialization is *not* used.
- **R2, locality.** Rich-mode edits change the HTML of the top-level blocks they touch.
  Untouched blocks, and the whitespace between them, are written from their source
  slices (S16).

### 7.2 Bridge protocol (`bridgeVersion = 1`)

**Transports.** All payloads are JSON. Text always travels as a JSON value; it is
**never** spliced into script source.

| Direction | Apple | Android |
|---|---|---|
| Native → JS call | `callAsyncJavaScript("return await window.KudosEditor.call(name, args)", arguments: ["name": …, "args": …], in: nil, contentWorld: .page)`. It resolves with the call's result. | `WebViewCompat.postWebMessage` with `{id, name, args}`. JS replies with `{id, ok, result \| error}`. |
| JS → native events | `window.webkit.messageHandlers.kudos.postMessage(event)` | `kudosNative.postMessage(JSON.stringify({event}))`, via `WebViewCompat.addWebMessageListener(webView, "kudosNative", [bundle origin], …)` |

**Calls.** Every call rejects with `{code, message}` on failure.

| Call | Args | Result | Timeout |
|---|---|---|---|
| `configure` | `{bridgeVersion, schemaVersion, variant: "content"\|"notes"\|"summary", theme: {background, text, accent, link, fontFamily, fontSizePx, lineHeight}, locale}` | `{bridgeVersion, schemaVersion, bundleVersion}` | 5 s |
| `load` | `{html, revision}` | `{revision, loss: LossReport, timing: {parseMs, buildMs, renderMs}}`. Replaces the document (read-only, not focused) and resets history. | 5 s |
| `activate` | `{caret: number \| null, focus: boolean}` | `{caretFound: boolean}`. Makes the editor editable, sets the caret from the source offset (§7.5), optionally focuses. | 1 s |
| `freeze` | `{}` | `{revision}`. Blurs, makes the editor read-only, and waits for IME composition to end (§7.6). | 1 s |
| `snapshot` | `{caret: boolean}` | `{revision, html, caretOffset: number \| null, words: number}` | 2 s |
| `command` | `{name, attrs}` | `{applied: boolean}` | 1 s |
| `lint` (E3/E5) | `{html}` | `{loss: LossReport}`. Parse only. | 5 s |
| `setTheme` | theme | `{}` | 1 s |
| `dispose` | `{}` | `{}`. Drops the document. | 1 s |

**Events.** These are informational. The session never waits on them.

| Event | Payload | Rate limit |
|---|---|---|
| `ready` | `{bundleVersion, schemaVersion}` | once per page load |
| `edited` | `{revision}` | ≤ 4 per second, trailing edge guaranteed |
| `toolbarState` | `{marks: string[], block: string, align, dir, canUndo, canRedo}` | ≤ 10 per second |
| `journal` (E4) | `{schemaVersion, fromRevision, toRevision, steps: object[]}` | ≤ 2 per second while dirty |
| `error` | `{code, message}` | as needed |

**Versioning.** A `configure` that returns an unexpected `bridgeVersion` or
`schemaVersion` disables rich mode for the session (the bundle and app disagree). HTML
mode is unaffected.

### 7.3 Switching from HTML to Rich Text

1. **Freeze the source view without dropping focus.**
   - Apple: set `isFrozen`, so `textView(_:shouldChangeTextIn:replacementText:)` (UIKit)
     or `textView(_:shouldChangeTextIn:replacementString:)` (AppKit) returns false.
     Then commit marked text (`commitComposition()`).
   - Android: an input filter that rejects edits.
   - The keyboard stays up.
2. **Snapshot.** Record `text`, `revision` and the caret offset (UTF-16), then
   **checkpoint** (§8.2) with composition committed.
3. **Warm path.** If the rich view preloaded exactly this revision (§9.3), skip to step 5
   and reuse that preload's loss report.
4. **Cold path.** Call `load({html: text, revision})`. After 100 ms without a result,
   show the switch transition. On timeout or error: unfreeze, stay in HTML mode, show
   "Rich Text couldn't open this text", and count one failure (§7.1).
5. **Confirm drops.** If `loss.dropped` isn't empty, ask (§6.9). "Cancel" unfreezes HTML
   mode and nothing changes.
6. **Hand over.**
   - Call `activate({caret: offset, focus: true})`.
   - Move first responder or focus to the WebView (§7.7).
   - The session's owner becomes `rich`, with the same revision.
   - Hide the source view. It keeps its text for R1.

### 7.4 Switching from Rich Text to HTML

1. **`freeze()`.** Blur, read-only, and wait for composition to end (§7.6).
2. **`snapshot({caret: true})`** returns `{revision, html, caretOffset, words}`.
3. **If `revision` equals the revision rich mode was loaded at** (no edits, R1): keep the
   source view's existing text untouched. Only the caret changes, mapped back through
   the load's source map (§7.5).
4. **Otherwise:** checkpoint with `html`, replace the source view's text with `html`,
   and clear its undo history (U2 in §7.9). Set the caret to `caretOffset`.
5. **Hand over.** Unfreeze the source view, make it first responder, and make `source`
   the owner. Keep the rich document loaded as the preload at this revision (§9.3), so
   switching straight back is warm.

### 7.5 Caret mapping

Offsets are UTF-16 code units in both directions. `NSRange`, Java `String` and
JavaScript strings all use them, so no conversion is needed.

**HTML offset → rich position** (`activate`):

1. Clamp to `[0, text.length]`.
2. If the offset is inside a tag, a comment or a character reference (per parse5's token
   locations), move it to the end of that token.
3. Find the text node whose source range contains the offset (or the next text node
   after it).
4. Walk that node's source slice, decoding character references, to turn the source
   offset into an offset in the decoded text.
5. Map the node into the document.
6. If the offset falls inside a preserved atom, put the caret after the atom. If there's
   no text node, use the start of the nearest following block, or the end of the
   document.
7. `caretFound` reports whether step 3 found a node.

**Rich position → HTML offset** (`snapshot`):

- **After an edit:** the serializer records the output offset, in UTF-16 units and
  including escapes, at the point where it writes the selection head. Inside an atom,
  that's the end of the atom's output.
- **With no edit since load (R1):** the head is mapped back through the load's source
  map instead. That's the reverse of steps 3–5 above: text node → source slice →
  source offset. It lands in the text HTML mode is about to show again, which is the
  original text, not the serializer's.

### 7.6 Freezing and composition

- **Idle checkpoints MUST NOT commit an in-progress composition.** The snapshot
  includes marked text as it stands. Committing a Japanese or Chinese composition
  because the writer paused would change their text.
- **Explicit checkpoints commit composition first:** switch, Done, Save or Post, and
  leaving the screen.
- **Rich `freeze()`:**
  1. Call `view.dom.blur()`.
  2. Set ProseMirror's `editable` prop to false.
  3. Wait until `view.composing` is false and one macrotask has passed. Cap the wait at
     500 ms.
  4. If the cap is hit, blur again, proceed, and send `{type: "error", code:
     "composition-timeout"}`.

### 7.7 Focus and keyboard

- **Apple, HTML → Rich Text.** Keep the native first responder until `activate`
  resolves, then call `webView.becomeFirstResponder()` plus JS `view.focus()`. WebKit
  may refuse to show the keyboard for a focus it considers programmatic; **E3 MUST
  verify on device**. The accepted fallback is that the caret is restored and the
  keyboard appears on the first tap.
- **Apple, Rich Text → HTML.** Call `textView.becomeFirstResponder()` after the text is
  set. One keyboard bounce is accepted, since switches are rare.
- **Apple, keyboard bar.** WebKit's own bar above the keyboard has no public switch. E3
  decides between the workaround Capacitor's keyboard plugin uses and a native
  formatting bar that sits above WebKit's.
- **Android.** Use `webView.requestFocus()` plus JS focus, with
  `InputMethodManager.showSoftInput` if needed.

### 7.8 Failures

| Failure | Handling |
|---|---|
| `configure` or `load` timeout, or bundle version mismatch | Stay in HTML mode and count a failure. Two failures disable rich mode until the editor reopens. |
| WebView content process dies while rich owns the text (Apple `webViewWebContentProcessDidTerminate`, Android `onRenderProcessGone`, which returns `true`) | HTML mode takes ownership with the last checkpoint, plus the journal from E4 on. Warn if the last `edited` revision is ahead of it ("The last few seconds in Rich Text couldn't be recovered"). Rich mode is off for 60 s, then the WebView is rebuilt on demand. |
| The process dies during a hand-off | Abort. The source view was only frozen, so unfreeze it. |
| JS `error` event | Log it. It isn't fatal unless it's one of the above. |

### 7.9 Undo

- **U1.** HTML mode uses the native undo manager. Rich mode uses `prosemirror-history`,
  and system undo gestures (⌘Z, shake, three-finger swipe) MUST go to it while rich
  mode owns the text.
- **U2.** Each switch starts the new owner with empty history. Merging the two
  histories is out of scope, on purpose.
- **U3.** R1 means a switch without an edit is always reversible by switching back.
  This replaces the "Undo switch" button proposed during design.

---

## 8. Checkpoints, auto-save and recovery (normative)

### 8.1 Checkpoint policy

| Trigger | Commits composition |
|---|---|
| 1.5 s after the last edit | no |
| 20 s after the first edit not yet checkpointed, even during continuous typing | no |
| Mode switch | yes |
| Done, or leaving the screen | yes |
| Save or Post | yes |
| App going inactive or to the background (Apple `scenePhase`; Android `ON_PAUSE`/`ON_STOP`) | no |
| Memory warning (Apple) or `onTrimMemory ≥ TRIM_MEMORY_RUNNING_LOW` (Android) | no |

Constants are `WritingCheckpointPolicy.idleDelay` = 1.5 s and `maxInterval` = 20 s.
They're shared by both platforms and change only here.

### 8.2 A checkpoint

1. If the revision is unchanged since the last checkpoint, stop.
2. Fetch the owner's text. That's one copy for the source view, or `snapshot` for rich.
3. If the text equals the last checkpoint's text (typed and deleted within the window),
   record the revision and stop. This comparison happens at most once per checkpoint,
   never per keystroke.
4. Write the text into the form field. This is the only moment the form's state
   changes.
5. Queue the recovery write off the main thread, with a sequence number (I5).
6. Recount words off the main thread (rich mode already returned `words`). Discard the
   result if a newer count has started.

### 8.3 On-disk layout

- **Directory:**
  - Apple: `Application Support/WritingTextRecovery/`.
  - Android: `filesDir/WritingTextRecovery/`.
  - Device-local; never synced by Kudos. Device backups: see OD4.
- **Field key.** `hex(SHA-256(UTF-8(k)))`, where `k` joins `n:v` for each of
  `account.lowercased()`, `target` (`work:<id>`, `work:new`, …) and `field` (`content`,
  `summary`, `notes`, `endnotes`), with `n` being `v`'s UTF-8 byte count in decimal.
  This is exactly `WritingTextRecovery.fileURL`. Android MUST produce the same bytes;
  shared test vectors come in E2.
- **E1 format (current, kept).** One file per editor session, `<key>.<sessionUUID>.json`,
  containing `{"text": String, "originalDigest": hex SHA-256 of the text at open,
  "savedAt": seconds since 2001-01-01}` (Foundation's default date encoding).
- **E3 format (target).** `<key>.<session>.html` (raw UTF-8) plus
  `<key>.<session>.meta.json` containing `{"schema": 1, "revision", "mode":
  "source"|"rich", "originalDigest", "savedAt"}`. Readers MUST keep accepting E1 files.
  The Privacy screen counts every file in the directory.
- **E4 edit log.** `<key>.<session>.journal` (§8.6).

### 8.4 Pruning

- Keep the newest `copyLimit` = 5 sessions per field key, newest by file modification
  date.
- Pruning MUST NOT decode files. An unreadable file is still counted and pruned.
- The session being written is never pruned.

### 8.5 Recovery on open

1. List the key's files off the main thread, excluding the current session.
2. Decode them off the main thread, and keep those whose text differs from the field's
   current text, newest first. An unreadable file is skipped on its own. It never hides
   the others. It is still pruned (§8.4).
3. Offer them:
   - **Restore** replaces the text as one undoable edit, followed by an immediate
     checkpoint.
   - **Keep form text.**
   - **Delete this copy.**
4. The prompt never waits for, or needs, the WebView (I6).

### 8.6 Edit log (E4)

- Append-only, one JSON object per line, truncated at every snapshot. Each segment
  therefore holds one mode's operations:
  - HTML mode: `{rev, ops: [{loc, len, text}]}`, taken from
    `shouldChangeTextIn` / `InputFilter`.
  - Rich mode: `{rev, schemaVersion, steps: [...]}`, ProseMirror `Step.toJSON()` from the
    `journal` event.
- **Replay:**
  - HTML ops apply natively.
  - Rich steps need the WebView: load the snapshot, apply the steps, take a snapshot.
  - If the schema version doesn't match, skip the replay and keep the snapshot.

### 8.7 Save and Post

- `session.commit()` takes an explicit checkpoint (§8.1) and then posts that text.
- HTML mode posts exactly what the writer typed; AO3 cleans it.
- Rich mode posts serializer output.
- In E1, Done and leaving the screen checkpoint into the form field, so the form's Save
  always has the latest text.

---

## 9. Performance budgets and pre-loading (normative)

### 9.1 Reference devices and fixture

- **Devices:**
  - iPhone 11 (A13): the oldest iPhone that runs iOS 26.
  - An M1 MacBook Air.
  - A Pixel 6a-class Android phone (2022 mid-range).
- **Fixture:** `Scripts/make-writing-fixture.py` (E1) writes a deterministic
  510,000-character chapter to AO3's limit. It has paragraphs of 40–120 words, about 5%
  formatted runs, blockquotes, lists, `hr`, one table, one work-skin `div`, and
  non-Latin text. Budgets are measured with that file loaded in the field editor.

### 9.2 Budgets (p95 unless stated)

| ID | What | Budget | Applies from |
|---|---|---|---|
| B1 | Keystroke to glyph, HTML mode | ≤ 16 ms; no editor hitch > 33 ms | E1 (Apple), E5 (Android gate) |
| B2 | Keystroke to glyph, rich mode | ≤ 16 ms | E3 |
| B3 | Main-thread work per checkpoint, HTML mode | ≤ 4 ms (one string copy, one comparison, scheduling) | E1 |
| B4 | JS-thread work per checkpoint, rich mode (incremental serialization, §9.4) | ≤ 16 ms | E3 |
| B5 | Recovery write, off the main thread | ≤ 50 ms at 510,000 characters | E1 |
| B6 | Editor open to text visible, HTML mode | ≤ 300 ms | E1 |
| B7 | Pre-warm: WebView created, bundle loaded, `configure` resolved | ≤ 1,000 ms after B6, never delaying it | E3 |
| B8 | Preload of the fixture (parse, build, render) in the hidden WebView | ≤ 1,500 ms on the Pixel 6a class, without affecting B1 (it runs in the web content process) | E3 |
| B9 | Warm switch (preloaded, same revision), tap to editable | ≤ 100 ms | E3 |
| B10 | Cold switch HTML → Rich Text at 510,000 characters | ≤ 500 ms on iPhone 11 and Pixel 6a; transition shown after 100 ms | E3 |
| B11 | Switch Rich Text → HTML | ≤ 150 ms | E3 |
| B12 | Web content process memory with the fixture preloaded | ≤ 150 MB | E3 |

**Android HTML-mode gate (D2).** A native text field is used only if it meets B1 on the
Pixel 6a class with the fixture. Otherwise CodeMirror 6 in the same WebView is used.
The decision and measurements are recorded in the E5 row.

### 9.3 Pre-warm and preload policy

- **W1.** Pre-warm the WebView (create, load the bundle, `configure`) when a field
  editor opens, after the HTML view has drawn its first frame (B6).
- **W2.** After each HTML-mode checkpoint, preload the text (`load`) into the hidden
  rich view, but only if all of these hold:
  - rich mode is enabled;
  - the app is in the foreground;
  - there has been no memory warning in the last 60 s;
  - the revision differs from the last preload;
  - the text is within the field's limit (§6.6).
- **W3.** A newer revision supersedes an older preload. A result whose revision isn't
  the latest is discarded.
- **W4.** On a memory warning or going to the background, `dispose` the preload. The
  WebView itself may be kept.
- **W5.** After switching Rich Text → HTML, the rich document stays as the preload for
  that revision (§7.4 step 5).

### 9.4 Incremental serialization and word counts

- ProseMirror documents are immutable, and an edit creates new objects only along the
  changed path. The serializer caches each block's HTML and word count in a `WeakMap`
  keyed by node.
- A checkpoint after typing one character therefore re-serializes one block,
  concatenates the rest, and sums cached counts.
- Blocks unchanged since load use their source slice (S16).

### 9.5 How to measure

- **Apple:**
  - Instruments Hitches and Time Profiler.
  - `os_signpost` intervals named `writing.checkpoint`, `writing.recovery.write`,
    `writing.wordcount` and `writing.handoff`.
- **Web:** `performance.now()` timings returned in `load` (`timing`) and in
  debug-build `edited` events.
- **Android:** JankStats and `androidx.tracing` sections with the same names.

---

## 10. Platform bindings

### 10.1 Apple

- **HTML view.**
  - `WritingTextController` keeps TextKit 2. Never touch `textView.layoutManager`: on
    iOS that silently falls back to TextKit 1, which is slow on long documents.
  - E1b turns on spell-check (`spellCheckingType = .yes`; on macOS
    `isContinuousSpellCheckingEnabled = true`) with autocorrect still off. That's what
    AO3's own textarea does.
- **WebView (E3):**
  - `WKWebsiteDataStore.nonPersistent()`.
  - The bundle is served through a `WKURLSchemeHandler` (`kudos-editor://`).
  - Messages use `WKScriptMessageHandler`; calls use `callAsyncJavaScript`.
  - A `WKNavigationDelegate` cancels every navigation except the bundle's.
  - `webViewWebContentProcessDidTerminate` is handled per §7.8.
- **Session (E3).** `DraftSession` is `@MainActor`. Its recovery writer is an actor, so
  disk I/O never runs on the main thread.
- **Lifecycle.** `scenePhase` (inactive or background) triggers a checkpoint. Memory
  warnings drop the preload (W4) and checkpoint.

### 10.2 Android

- **Screens:** Compose. The WebView is created once per editor screen and held outside
  composition, then shown through `AndroidView`. It is never recreated on recomposition.
- **WebView:**
  - The bundle comes from `WebViewAssetLoader` at
    `https://appassets.androidplatform.net/editor/`.
  - `addWebMessageListener` handles messages and `postWebMessage` sends calls.
  - `onRenderProcessGone` returns `true` and is handled per §7.8.
  - Settings: JavaScript on; file and content access off; `setSupportMultipleWindows(false)`;
    `shouldInterceptRequest` returns empty responses for anything outside the asset
    loader.
  - Theme comes from CSS; algorithmic darkening is off.
- **Recovery:** the writer runs on `Dispatchers.IO.limitedParallelism(1)`, so writes are
  ordered (I5). Files, keys and pruning follow §8.3–8.4.

---

## 11. Security and privacy (normative from E3)

- **Content Security Policy** in the bundle's HTML: `default-src 'none'; script-src
  'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:`. Remote images are off
  by default (OD2).
- **No network from the editor.** Links never navigate inside the editor; tapping one
  opens the native link sheet.
- **Untrusted HTML.** It is parsed by parse5 into a clean document. It is never set as
  `innerHTML` on the live page.
- **Remote images** show as placeholders naming their host. Loading them reveals the
  reader's IP address to that host, so it's a per-chapter choice (OD2).
- **Preserved embeds and media** never create an `iframe`, `audio` or `video` inside the
  editor.
- **Recovery copies** hold text only: no cookies, form tokens or account names in file
  names (unchanged from today).

---

## 12. Work plan

| Step | Scope | Acceptance | Row |
|---|---|---|---|
| **E1** | Apple: recovery store and per-keystroke work (§12.1) | §12.1 list, measured on a Mac or device | **T-262** |
| **E1b** | Apple: spell-check in HTML mode (§10.1) | Screenshot showing underlines, and tags not autocorrected | T-262 (separate commit) |
| **E2** | `editor-core`: schema, parse5 pipeline, sanitizer and ParagraphMaker ports, serializer (S1–S16), paste cleaner, AO3 word counter, caret maps, loss report, golden and property tests, Node CI | §6.10 green in CI; 510k fixture parse and serialize timings recorded | new row |
| **E3** | Apple rich mode behind a feature flag: `DraftSession`, WebView host, bridge, hand-off, pre-warm and preload, E3 recovery format, source-mode lint | B2, B4, B7–B12 on the reference devices; hand-off tests; device check of §7.7 | new row; **needs OD1** |
| **E4** | Edit log and crash replay, both platforms | Kill the web process mid-typing: recovered text matches the last `edited` revision | new row |
| **E5** | Android writing screens using `editor-core`, with the HTML-mode gate (§9.2) | Parity checklist (§12.2); B1, B2, B9–B11 on the Pixel 6a class | new row |

### 12.1 E1 in detail (T-262)

**Scope:**

1. **Recovery store:**
   - writes go through `WritingRecoveryWriter`, an actor, off the main thread;
   - writes are ordered by a sequence number, so an older write never lands after a
     newer one;
   - the SHA-256 of the original text is computed once per session;
   - pruning uses file modification dates and never decodes (§8.4);
   - the recovery list is read and decoded off the main thread, excludes the current
     session, and skips unreadable files one at a time instead of failing (§8.5).
2. **Checkpoints:**
   - `WritingCheckpointPolicy` (1.5 s idle / 20 s max) and `WritingCheckpointScheduler`;
   - the form field binding, the recovery write and the word count happen only at
     checkpoints (§8.2);
   - Done, leaving the screen, restore and scene changes checkpoint per §8.1.
3. **Controller:**
   - `WritingTextController` reports edits in O(1) (a revision counter) instead of
     emitting the full text on every keystroke;
   - text is fetched with `takeCheckpoint()`, which compares at most once per
     checkpoint;
   - composition is committed only on explicit checkpoints (§7.6).
4. **Word count:** computed by a `nonisolated` function off the main thread, at open and
   at checkpoints. It uses the same algorithm as today; the AO3 algorithm is E2 and
   OD3.
5. **Fixture:** `Scripts/make-writing-fixture.py` (§9.1).
6. **Comment:** correct the `AO3Markup.swift` comment (§3.1).

**Acceptance (Mac or device):**

- Both platforms build and `Scripts/lint.sh` is clean.
- `WritingTextEditorTests` and the new policy, scheduler, writer and word-count tests
  pass.
- With the fixture pasted into "Work text" of an **unsaved** new work on an iPhone
  11-class device:
  - B1, B3, B5 and B6 hold;
  - Time Profiler shows no `JSONEncoder`, `SHA256`, `strippingHTML` or file I/O on the
    main thread while typing;
  - recovery writes happen at most once per 1.5 s idle, or once per 20 s while typing
    continuously.
- The recovery prompt still appears after a forced quit mid-edit, and restoring works.
- The Privacy screen's recovery figure still counts the copies.

### 12.2 Parity checklist (Apple ↔ Android)

- **Shared and identical:** the `editor-core` bundle version, `schemaVersion`,
  `bridgeVersion`, the §8.1 constants, the recovery key derivation and file formats,
  and the golden fixtures.
- **Identical in behaviour:** toolbar actions and the tags they create (§6.3, §6.4),
  paste results (P9), loss-report wording, hand-off steps (§7.3–7.4) and budgets (§9.2).
- **Native per platform:** the chrome (SwiftUI vs Compose), keyboard handling (§7.7) and
  the HTML-mode widget (D2).

---

## 13. Owner decisions

| ID | Question | Proposal | Blocks |
|---|---|---|---|
| **OD1** | Run the Rich Text canvas in a WebView? This reverses the 2026-09-12 native-only rule (`docs/REDESIGN_PLAN.md:1927-1936`) for the rich canvas only. | Yes, with native chrome (§4, §7.7) | E3, and E5's rich mode |
| OD2 | Load remote images inside the editor? | Placeholders by default; load per chapter on request | E3 |
| OD3 | Adopt AO3's word-count algorithm (§3.6) in both modes? It changes counts for Chinese, Japanese and Thai text and for hyphenated words. | Yes; the count then matches AO3's | E2 |
| OD4 | Recovery copies in device backups (Apple iCloud backup of Application Support, Android Auto Backup)? | Keep as today (included); revisit if writers ask | — |
| OD5 | Android HTML-mode widget | Decided by the §9.2 gate; owner informed | E5 |
| OD6 | Spell-check in HTML mode (E1b)? | Yes, matching AO3's textarea | E1b |

---

## 14. References

- **otwarchive `00ad85b4`:**
  - `lib/html_cleaner.rb`
  - `lib/paragraph_maker.rb`
  - `config/initializers/gem-plugin_config/sanitizer_config.rb`
  - `lib/otw_sanitize/{user_class,embed,media}_sanitizer.rb`
  - `lib/word_counter.rb`
  - `config/config.yml`
  - `public/javascripts/mce_editor.js`
- **Kudos:**
  - `Features/Writing/WritingTextEditor.swift`
  - `Features/Writing/WritingNativeTextView.swift`
  - `Services/WritingTextRecovery.swift`
  - `Models/AO3Markup.swift`
  - `Services/LocalDataFootprint.swift`
  - `docs/REDESIGN_PLAN.md` (the 2026-09-12 editor review)
  - `docs/audits/2026-09-24/otwarchive-facts-wave3.json` (Q15: comment length is
    counted in code points)
- **Libraries (all MIT):**
  - ProseMirror: `prosemirror-model`, `-state`, `-view`, `-transform`, `-history`,
    `-keymap`
  - parse5
  - CodeMirror 6 (Android fallback only)
  - fast-check (tests)

---

## 15. Revision log

| Date | Rev | Change | By |
|---|---|---|---|
| 2026-09-25 | 1 | First version. Covers decisions D1–D8, AO3 ground truth, schema, hand-off, checkpoints, budgets, platform bindings and work plan. | Claude (cloud), T-262 |
